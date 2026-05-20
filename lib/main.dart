import 'dart:io';
import 'package:ai_agent/home_page.dart';
import 'package:ai_agent/welcome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 💡 新增：用于读取资源文件
import 'package:flutter/widget_previews.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart'; // 💡 新增：用于配置底层 HttpClient
import 'package:path_provider/path_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  Dio? dio;
  try {
    final directory = await getApplicationDocumentsDirectory();
    File file = File('${directory.path}/.env');

    // 💡 手机调试核心逻辑：如果是移动端，尝试从资源中同步 lib/.env 到存储空间
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        // 读取 asset
        String content = await rootBundle.loadString('lib/.env');
        // 写入本地存储 (覆盖模式，确保调试时 Key 保持最新)
        await file.writeAsString(content);
        debugPrint("已将 lib/.env 同步到移动端存储: ${file.path}");
      } catch (e) {
        debugPrint("未在资源中找到 lib/.env，将使用已有配置或进入欢迎页");
      }
    } else {
      // Windows 桌面端逻辑：优先读项目源码下的 lib/.env
      File devFile = File('lib/.env');
      if (await devFile.exists()) {
        file = devFile;
      }
    }
    
    if (await file.exists()) {
      final content = await file.readAsString();
      final lines = content.split('\n');
      Map<String, String> config = {};
      
      for (var line in lines) {
        final trimmedLine = line.trim();
        if (trimmedLine.contains('=') && !trimmedLine.startsWith('#')) {
          final parts = trimmedLine.split('=');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join('=').trim().replaceAll('"', '').replaceAll("'", "");
            config[key] = value;
          }
        }
      }
      
      // 核心校验
      final openaiKey = config['OPENAI_API_KEY'];
      
      // 智能默认地址逻辑
      String defaultUrl = Platform.isWindows ? "http://127.0.0.1:8080" : "http://10.44.159.179:8080";
      final baseUrl = config['BASE_URL'] ?? defaultUrl;
      
      if (openaiKey != null && openaiKey.isNotEmpty) {
        dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {"Authorization": "Bearer $openaiKey"},
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ));

        // 💡 强制禁用代理，直接连接后端
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (uri) => "DIRECT"; // 关键：强制直连
          return client;
        };
        
        debugPrint("Dio 初始化成功并禁用代理: $baseUrl");
      }
    }
  } catch (e) {
    debugPrint("启动加载配置失败: $e");
  }

  runApp(MyApp(initialDio: dio));
}

class MyApp extends StatelessWidget {
  final Dio? initialDio;
  const MyApp({super.key, this.initialDio});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '星火学伴',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      locale: const Locale('zh', 'CN'),
      // 只有在 initialDio 不为空时才进入主页，否则进入欢迎页
      home: initialDio != null ? MyHomePage(dio: initialDio!) : const WelcomePage(),
    );
  }
}

@Preview()
Widget appPreview() {
  return const MyApp();
}
