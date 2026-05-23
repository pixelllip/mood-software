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
  if (!await projectDir.exists()) await projectDir.create(recursive: true);
  final file = File('${projectDir.path}/config.json');
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config));
}

// 获取全平台统一的 Academic Aegis 目录
Future<Directory> getProjectDirectory() async {
  if (Platform.isWindows) {
    final docDir = await getApplicationDocumentsDirectory();
    return Directory('${docDir.path}/Academic Aegis');
  } else if (Platform.isAndroid) {
    return Directory('/storage/emulated/0/Documents/Academic Aegis');
  } else {
    final docDir = await getApplicationDocumentsDirectory();
    return Directory('${docDir.path}/Academic Aegis');
  }
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
    String rootDir = Directory.current.path;
    String jarPath = File(
      '$rootDir/backend_kotlin/build/libs/ai_agent_backend.jar',
    ).path;
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
