import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:dio/dio.dart';

/// 安全地将进程输出字节流转为**逐行字符串**
/// 先尝试 UTF-8，若含非法字节则回退到系统编码（中文 Windows 为 GBK）
String _decode(List<int> bytes) {
  // 先试 UTF-8
  try {
    return utf8.decode(bytes);
  } catch (_) {
    // 回退到系统编码
    try {
      return systemEncoding.decode(bytes);
    } catch (_) {
      // 最终用 Latin1 保证不抛异常
      return latin1.decode(bytes);
    }
  }
}

Stream<String> _safeDecode(Stream<List<int>> stream) {
  final lines = StreamController<String>();
  var buf = '';
  stream.listen(
    (chunk) {
      try {
        buf += _decode(chunk);
        while (true) {
          final idx = buf.indexOf('\n');
          if (idx < 0) break;
          final line = buf.substring(0, idx).trimRight();
          buf = buf.substring(idx + 1);
          if (line.isNotEmpty) lines.add(line);
        }
      } catch (_) {}
    },
    onDone: () {
      if (buf.trim().isNotEmpty) lines.add(buf.trim());
      lines.close();
    },
    onError: (_) => lines.close(),
    cancelOnError: true,
  );
  return lines.stream;
}

/// 读取 config.json（不存在返回空 map）
Future<Map<String, dynamic>> loadConfigFile() async {
  final projectDir = await getProjectDirectory();
  final file = File('${projectDir.path}/config.json');
  if (await file.exists()) {
    try {
      final content = await file.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    } catch (_) {}
  }
  return {};
}

/// 保存 config.json
Future<void> saveConfigFile(Map<String, dynamic> config) async {
  final projectDir = await getProjectDirectory();
  final file = File('${projectDir.path}/config.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config));
}

// ========== AI 配置管理 ==========

/// AI 配置项的数据模型
class AiConfig {
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool enabled;

  const AiConfig({
    this.name = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.enabled = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'base_url': baseUrl,
    'api_key': apiKey,
    'model': model,
    'enabled': enabled,
  };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
    name: json['name']?.toString() ?? '',
    baseUrl: json['base_url']?.toString() ?? '',
    apiKey: json['api_key']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    enabled: json['enabled'] == true,
  );

  AiConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? enabled,
  }) => AiConfig(
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    enabled: enabled ?? this.enabled,
  );
}

/// 从 config 中读取 AI 配置列表
List<AiConfig> getAiConfigs(Map<String, dynamic> config) {
  final list = config['AI_CONFIGS'] as List<dynamic>?;
  if (list == null) return [];
  return list.map((e) => AiConfig.fromJson(e as Map<String, dynamic>)).toList();
}

/// 获取已启用的 AI 配置（第一个 enabled=true 的配置）
AiConfig? getEnabledAiConfig(Map<String, dynamic> config) {
  final configs = getAiConfigs(config);
  try {
    return configs.firstWhere((c) => c.enabled);
  } catch (_) {
    return null;
  }
}

/// 保存 AI 配置列表到 config
Map<String, dynamic> setAiConfigs(
  Map<String, dynamic> config,
  List<AiConfig> configs,
) {
  config['AI_CONFIGS'] = configs.map((c) => c.toJson()).toList();
  return config;
}

/// 缓存的项目目录
Directory? _cachedProjectDir;

/// 获取全平台统一的 Academic Aegis 目录
///
/// - Windows: Documents/Academic Aegis
/// - Android: 默认使用应用自有目录（无需额外权限）
///            用户可在设置中通过文件夹选择器修改 BASE_PATH
/// - 其他:    Documents/Academic Aegis
Future<Directory> getProjectDirectory() async {
  if (_cachedProjectDir != null) return _cachedProjectDir!;

  if (Platform.isAndroid) {
    // 手机端默认使用应用自有目录（无需 MANAGE_EXTERNAL_STORAGE）
    final docDir = await getApplicationDocumentsDirectory();
    _cachedProjectDir = Directory('${docDir.path}/Academic Aegis');
    debugPrint(">>> 手机端默认使用应用自有目录: ${_cachedProjectDir!.path}");
  } else {
    final docDir = await getApplicationDocumentsDirectory();
    _cachedProjectDir = Directory('${docDir.path}/Academic Aegis');
  }

  // 确保目录存在
  if (!await _cachedProjectDir!.exists()) {
    await _cachedProjectDir!.create(recursive: true);
  }

  return _cachedProjectDir!;
}

// 启动 Kotlin 后端核心逻辑
Future<bool> startBackend(int port) async {
  if (Platform.isWindows) {
    return _startBackendWindows(port);
  } else if (Platform.isAndroid) {
    try {
      const channel = MethodChannel('com.academic.aegis/backend');
      await channel.invokeMethod('startBackend', {'port': port});
      debugPrint("✅ Android 内置后端已尝试拉起");
      return true;
    } catch (e) {
      debugPrint("❌ Android 后端拉起失败: $e");
      return false;
    }
  }
  return true;
}

/// Windows 上启动 Kotlin 后端（优先使用 JAR，否则 Gradle 编译+运行）
Future<bool> _startBackendWindows(int port) async {
  try {
    // 查找 JAR 的优先级：
    // 1. 可执行文件同目录下的 backend/ai_agent_backend.jar（发布版）
    // 2. 项目开发目录下的 backend_kotlin/build/libs/ai_agent_backend.jar（开发版）
    String jarPath = '';
    String rootDir = Directory.current.path;
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // 情况1：发布版 — JAR 在 exe 旁边
    final releaseJar = File('$exeDir/backend/ai_agent_backend.jar');
    if (await releaseJar.exists()) {
      jarPath = releaseJar.path;
      debugPrint("--- 使用发布版 JAR: $jarPath ---");
    }

    // 情况2：开发版 — 项目中的构建产物
    if (jarPath.isEmpty) {
      final devJar = File(
        '$rootDir/backend_kotlin/build/libs/ai_agent_backend.jar',
      );
      if (await devJar.exists()) {
        jarPath = devJar.path;
        debugPrint("--- 使用开发版 JAR: $jarPath ---");
      }
    }
    String gradlewPath = File('$rootDir/backend_kotlin/gradlew.bat').path;

    String launchCmd;
    List<String> launchArgs;

    if (await File(jarPath).exists()) {
      // 🚀 优先使用已编译的 Fat JAR（启动快）
      debugPrint("--- 使用 JAR 启动后端 (端口: $port) ---");
      launchCmd = 'java';
      launchArgs = ['-Dfile.encoding=UTF-8', '-jar', jarPath, '--port=$port'];
    } else if (await File(gradlewPath).exists()) {
      // ⏳ 没有 JAR，先用 Gradle 编译，再运行
      debugPrint("--- 未找到 JAR，正在用 Gradle 编译 (端口: $port) ---");
      debugPrint("首次编译可能需要 1-2 分钟...");
      final buildResult = await Process.run(gradlewPath, [
        '-p',
        'backend_kotlin',
        'buildFatJar',
      ], runInShell: true);
      if (buildResult.exitCode != 0) {
        debugPrint("⚠️ Gradle 编译失败，回退到 gradlew run...");
        launchCmd = gradlewPath;
        launchArgs = ['-p', 'backend_kotlin', 'run'];
      } else {
        debugPrint("✅ JAR 编译成功，正在启动...");
        launchCmd = 'java';
        launchArgs = ['-Dfile.encoding=UTF-8', '-jar', jarPath];
      }
    } else {
      debugPrint("❌ 未找到后端构建文件");
      return false;
    }

    // 启动后端进程
    final process = await Process.start(
      launchCmd,
      launchArgs,
      runInShell: true,
    );

    _safeDecode(process.stdout).listen((data) {
      debugPrint("[后端输出]: $data");
    });

    _safeDecode(process.stderr).listen((data) {
      debugPrint("[后端错误]: $data");
    });

    // 💡 循环检查后端是否就绪 (最多等待 60 秒)
    final pingDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 1),
        receiveTimeout: const Duration(seconds: 1),
      ),
    );
    bool ready = false;
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final response = await pingDio.get("http://127.0.0.1:$port/ping");
        if (response.statusCode == 200) {
          ready = true;
          break;
        }
      } catch (e) {
        debugPrint("⏳ 等待后端就绪 (${(i + 1) * 2}s)... $e");
      }
    }
    if (ready) {
      debugPrint("✅ 后端已就绪！");
      return true;
    }
    debugPrint("⚠️ 后端启动超时 (端口: $port)，请检查控制台错误信息。");
    debugPrint("💡 提示: 确认 config.json 中 SERVER_PORT 与当前端口一致");
    return false;
  } catch (e) {
    debugPrint("❌ 启动后端异常: $e");
    return false;
  }
}

/// 手机端直连 AI API（不经过本地后端）
/// 调用 OpenAI 兼容的 /chat/completions 接口，流式返回文本块
Stream<String> directStreamChat({
  required String baseUrl,
  required String apiKey,
  required String model,
  required List<Map<String, String>> messages,
}) async* {
  final chatUrl = baseUrl.endsWith('/')
      ? '${baseUrl}chat/completions'
      : '$baseUrl/chat/completions';

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );

  try {
    final response = await dio.post(
      chatUrl,
      options: Options(
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
          "Accept": "text/event-stream",
        },
        responseType: ResponseType.stream,
      ),
      data: {"model": model, "messages": messages, "stream": true},
    );

    final stream = response.data.stream as Stream<Uint8List>;
    String buffer = '';
    await for (final chunk in stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      // 解析 SSE 格式：data: {...}\n\n
      while (true) {
        final idx = buffer.indexOf('\n');
        if (idx < 0) break;
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        if (line.isEmpty) continue;
        if (line == 'data: [DONE]') break;
        if (line.startsWith('data: ')) {
          try {
            final json = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            final choices = json['choices'] as List<dynamic>?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0] as Map<String, dynamic>;
              final content = delta['delta'] is Map
                  ? (delta['delta'] as Map)['content']
                  : delta['text'];
              if (content != null && content.toString().isNotEmpty) {
                yield content.toString();
              }
            }
          } catch (_) {}
        }
      }
    }
  } catch (e) {
    debugPrint("❌ 直连 AI API 失败: $e");
    yield "\n\n[请求失败: $e]";
  }
}

// ========== Android 存储权限相关 ==========

const _permChannel = MethodChannel('com.academic.aegis/permission');

/// 检查 Android 是否已授予 MANAGE_EXTERNAL_STORAGE 权限
Future<bool> checkStoragePermission() async {
  if (!Platform.isAndroid) return true;
  try {
    final result = await _permChannel.invokeMethod<bool>(
      'checkStoragePermission',
    );
    return result ?? false;
  } catch (e) {
    debugPrint("检查权限失败: $e");
    return false;
  }
}

/// 打开系统设置页面让用户授予 MANAGE_EXTERNAL_STORAGE 权限
Future<void> requestStoragePermission() async {
  if (!Platform.isAndroid) return;
  try {
    await _permChannel.invokeMethod('openStoragePermissionSettings');
  } catch (e) {
    debugPrint("打开权限设置失败: $e");
  }
}

// ========== 对话记录（Backlog）本地文件读写 ==========

/// 单条聊天消息
class BacklogMessage {
  final String role;
  final String content;
  const BacklogMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory BacklogMessage.fromJson(Map<String, dynamic> json) => BacklogMessage(
    role: json['role']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
  );
}

/// 获取 Backlog 目录路径
Future<Directory> _getBacklogDir() async {
  final config = await loadConfigFile();
  final basePath =
      config['BASE_PATH']?.toString() ?? (await getProjectDirectory()).path;
  return Directory('$basePath/Backlog');
}

/// 保存一次对话到 backlog 文件
/// 文件名格式: {BASE_PATH}/Backlog/{yyyy-MM-dd}/{HH-mm-ss}.json
Future<void> saveBacklog({
  required List<BacklogMessage> messages,
  String? summary,
}) async {
  try {
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}";

    final backlogDir = Directory('${(await _getBacklogDir()).path}/$dateStr');
    if (!await backlogDir.exists()) {
      await backlogDir.create(recursive: true);
    }

    // 写入消息文件
    final file = File('${backlogDir.path}/$timeStr.json');
    await file.writeAsString(
      json.encode(messages.map((m) => m.toJson()).toList()),
    );

    // 写入摘要文件
    if (summary != null && summary.isNotEmpty) {
      final metaFile = File('${backlogDir.path}/$timeStr.meta.json');
      await metaFile.writeAsString(json.encode({'summary': summary}));
    }

    debugPrint(">>> backlog 已保存: ${file.path} (${messages.length} 条消息)");
  } catch (e) {
    debugPrint(">>> backlog 保存失败: $e");
  }
}

/// 从文件中读取单日对话历史
/// 返回 Map: 文件名 -> {messages, summary}
Future<Map<String, Map<String, dynamic>>> loadBacklogForDate({
  required String date, // yyyy-MM-dd
  String? startTime,
  String? endTime,
  String? sort, // 'asc' 或 'desc'
}) async {
  final result = <String, Map<String, dynamic>>{};
  try {
    final backlogDir = Directory('${(await _getBacklogDir()).path}/$date');
    if (!await backlogDir.exists()) return result;

    final files = await backlogDir.list().toList();
    for (final entity in files) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json') || entity.path.endsWith('.meta.json')) {
        continue;
      }

      final filename = entity.uri.pathSegments.last;

      // 时间范围过滤
      if (startTime != null || endTime != null) {
        final fileTime = _timeFromFilename(filename);
        if (fileTime != null) {
          if (startTime != null && fileTime.compareTo(startTime) < 0) continue;
          if (endTime != null && fileTime.compareTo(endTime) > 0) continue;
        }
      }

      try {
        final content = await entity.readAsString();
        final rawMessages = json.decode(content) as List<dynamic>;
        final messages = rawMessages
            .map((m) => BacklogMessage.fromJson(m as Map<String, dynamic>))
            .where((m) => m.role != 'system')
            .toList();

        // 读取摘要
        final metaFile = File(
          '${entity.parent.path}/${filename.replaceAll('.json', '.meta.json')}',
        );
        String summary = '';
        if (await metaFile.exists()) {
          try {
            final meta =
                json.decode(await metaFile.readAsString())
                    as Map<String, dynamic>;
            summary = meta['summary']?.toString() ?? '';
          } catch (_) {}
        }

        result[filename] = {
          'messages': messages
              .map((m) => {'role': m.role, 'content': m.content})
              .toList(),
          'summary': summary,
        };
      } catch (_) {}
    }
  } catch (e) {
    debugPrint(">>> 加载 backlog 失败: $e");
  }
  return result;
}

/// 从文件名 HH-MM-SS.json 提取时间 HH:MM
String? _timeFromFilename(String filename) {
  try {
    final name = filename.replaceAll('.json', '');
    final parts = name.split('-');
    if (parts.length >= 2) {
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 加载日期范围内的对话历史
Future<Map<String, Map<String, Map<String, dynamic>>>> loadBacklogForRange({
  required String startDate,
  required String endDate,
  String? startTime,
  String? endTime,
  String? sort,
}) async {
  final result = <String, Map<String, Map<String, dynamic>>>{};
  try {
    final backlogBase = await _getBacklogDir();
    if (!await backlogBase.exists()) return result;

    // 遍历日期范围内的每一天
    // 时间过滤逻辑：
    //   - 起始日期：只限制 ≥ startTime（不限制上限）
    //   - 结束日期：只限制 ≤ endTime（不限制下限）
    //   - 中间日期：不限制时间
    DateTime current = DateTime.parse(startDate);
    final end = DateTime.parse(endDate);
    final isSingleDay = startDate == endDate;
    while (!current.isAfter(end)) {
      final dateStr =
          "${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}";
      final bool isFirstDay = dateStr == startDate;
      final bool isLastDay = dateStr == endDate;

      String? dayStartTime;
      String? dayEndTime;
      if (isSingleDay) {
        // 单日范围：同时应用起止时间
        dayStartTime = startTime;
        dayEndTime = endTime;
      } else if (isFirstDay) {
        // 起始日：只过滤下限（≥ startTime）
        dayStartTime = startTime;
        dayEndTime = null;
      } else if (isLastDay) {
        // 结束日：只过滤上限（≤ endTime）
        dayStartTime = null;
        dayEndTime = endTime;
      }
      // 中间日期：不限时间（dayStartTime/dayEndTime 均为 null）

      final dayData = await loadBacklogForDate(
        date: dateStr,
        startTime: dayStartTime,
        endTime: dayEndTime,
      );
      if (dayData.isNotEmpty) {
        result[dateStr] = dayData;
      }
      current = current.add(const Duration(days: 1));
    }
  } catch (e) {
    debugPrint(">>> 加载 backlog 范围失败: $e");
  }
  return result;
}
