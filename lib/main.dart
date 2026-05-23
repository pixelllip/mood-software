import 'dart:io';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/home_page.dart';
import 'package:ai_agent/welcome.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final projectDir = await getProjectDirectory();
  if (!await projectDir.exists()) {
    await projectDir.create(recursive: true);
  }

  final configFile = File('${projectDir.path}/config.json');
  debugPrint('>>> 项目目录: ${projectDir.path}');
  debugPrint('>>> 配置文件: ${configFile.path}');

  Dio? dio;
  bool showWelcome = false;
  bool useDirectApi = false;
  String? directBaseUrl;
  String? directApiKey;
  String? directModel;

  if (!await configFile.exists()) {
    // 不存在 → 生成模板 → 跳转欢迎页
    debugPrint('>>> config.json 不存在，正在生成模板...');
    final defaultConfig = {
      "BASE_PATH": projectDir.path,
      "STUDENT_ID": "",
      "STUDENT_NAME": "",
      "Gaode_API_Key": "",
      "SERVER_PORT": 8080,
      "AI_CONFIGS": [],
    };
    await saveConfigFile(defaultConfig);
    debugPrint('>>> 模板已生成: ${configFile.path}');
    showWelcome = true;
  } else {
    // 存在 → 读取配置
    final config = await loadConfigFile();
    final port = (config['SERVER_PORT'] ?? config['PORT'] ?? 8080) as int;
    final enabledAi = getEnabledAiConfig(config);

    debugPrint('>>> 读取到端口: $port');
    debugPrint(
      '>>> AI 配置: ${enabledAi != null ? "已配置(${enabledAi.name})" : "未配置"}',
    );

    if (enabledAi == null || enabledAi.apiKey.isEmpty) {
      debugPrint('>>> AI 配置为空，跳转欢迎页');
      showWelcome = true;
    } else if (Platform.isAndroid) {
      // 📱 Android 手机端：不启动本地后端，直连 AI API
      debugPrint('>>> Android 模式：使用直连 AI API');
      useDirectApi = true;
      directBaseUrl = enabledAi.baseUrl;
      directApiKey = enabledAi.apiKey;
      directModel = enabledAi.model;

      // 创建一个指向 AI API 的 Dio（用于成绩查询等需要后端的功能，暂时不可用）
      dio = Dio(
        BaseOptions(
          baseUrl: enabledAi.baseUrl,
          headers: {"Authorization": "Bearer ${enabledAi.apiKey}"},
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );
      debugPrint('>>> 已进入 Android 直连模式');
    } else {
      // 启动后端并等待就绪
      debugPrint('>>> 正在启动后端 (端口: $port)...');
      bool backendReady = await startBackend(port);

      if (backendReady) {
        final baseUrl = "http://127.0.0.1:$port";
        dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            headers: {"Authorization": "Bearer ${enabledAi.apiKey}"},
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );

        // 强制直连
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (uri) => "DIRECT";
          return client;
        };
        debugPrint('>>> 后端已就绪，进入主页面');
      } else {
        debugPrint('>>> 后端启动失败，跳转欢迎页');
        showWelcome = true;
      }
    }
  }

  runApp(
    MyApp(
      initialDio: dio,
      showWelcome: showWelcome,
      useDirectApi: useDirectApi,
      directBaseUrl: directBaseUrl,
      directApiKey: directApiKey,
      directModel: directModel,
    ),
  );
}

class MyApp extends StatelessWidget {
  final Dio? initialDio;
  final bool showWelcome;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  const MyApp({
    super.key,
    this.initialDio,
    required this.showWelcome,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '星火学伴',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: const Locale('zh', 'CN'),
      home: showWelcome || initialDio == null
          ? const WelcomePage()
          : MyHomePage(
              dio: initialDio!,
              useDirectApi: useDirectApi,
              directBaseUrl: directBaseUrl,
              directApiKey: directApiKey,
              directModel: directModel,
            ),
    );
  }
}
