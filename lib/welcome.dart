import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'home_page.dart';
import 'backend_utils.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  int _currentStep = 0;

  // 第一步：基本信息
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  // 第二步：密钥配置
  final TextEditingController _openaiKeyController = TextEditingController();
  final TextEditingController _gaodeKeyController = TextEditingController();
  final TextEditingController _dashscopeKeyController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final List<Map<String, TextEditingController>> _extensionApiItems = [];

  @override
  void initState() {
    super.initState();
    _portController.text = "8080";
    _loadExistingSettings();
  }

  Future<void> _loadExistingSettings() async {
    try {
      final config = await loadConfigFile();
      if (config.isNotEmpty) {
        _setTextIfNotEmpty(_idController, config['STUDENT_ID']);
        _setTextIfNotEmpty(_nameController, config['STUDENT_NAME']);
        _setTextIfNotEmpty(_openaiKeyController, config['OPENAI_API_KEY']);
        _setTextIfNotEmpty(_gaodeKeyController, config['Gaode_API_Key']);
        _setTextIfNotEmpty(
          _dashscopeKeyController,
          config['DASHSCOPE_API_KEY'],
        );
        _setTextIfNotEmpty(_portController, config['SERVER_PORT']?.toString());
        setState(() {});
      }
    } catch (e) {
      debugPrint("欢迎页：预加载配置失败: $e");
    }
  }

  void _setTextIfNotEmpty(TextEditingController ctrl, dynamic value) {
    if (value != null && value.toString().isNotEmpty) {
      ctrl.text = value.toString();
    }
  }

  void _completeSetup() async {
    final openaiKey = _openaiKeyController.text.trim();
    if (openaiKey.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("OPENAI_API_KEY 是必填项")));
      return;
    }

    final portStr = _portController.text.trim();
    final port = int.tryParse(portStr) ?? 8080;

    await _saveToEnv(); // 保存配置

    // 启动后端
    await startBackend(port);

    final baseUrl = "http://127.0.0.1:$port";
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: {"Authorization": "Bearer $openaiKey"},
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => MyHomePage(dio: dio)),
    );
  }

  // 保存为 config.json
  Future<void> _saveToEnv() async {
    try {
      final projectDir = await getProjectDirectory();
      final config = {
        "BASE_PATH": projectDir.path,
        "STUDENT_ID": _idController.text.trim(),
        "STUDENT_NAME": _nameController.text.trim(),
        "OPENAI_API_KEY": _openaiKeyController.text.trim(),
        "Gaode_API_Key": _gaodeKeyController.text.trim(),
        "DASHSCOPE_API_KEY": _dashscopeKeyController.text.trim(),
        "SERVER_PORT": int.tryParse(_portController.text.trim()) ?? 8080,
      };
      await saveConfigFile(config);
      debugPrint("配置已保存至: ${projectDir.path}/config.json");
    } catch (e) {
      debugPrint("保存失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("欢迎使用星火学伴"), centerTitle: true),
      body: Stepper(
        type: StepperType.vertical,
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() {
              _currentStep += 1;
            });
          } else {
            _completeSetup();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() {
              _currentStep -= 1;
            });
          }
        },
        steps: [
          Step(
            title: const Text("个人信息"),
            subtitle: const Text("请输入学号和姓名"),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.editing,
            content: Column(
              children: [
                TextField(
                  controller: _idController,
                  decoration: const InputDecoration(
                    labelText: "学号",
                    prefixIcon: Icon(Icons.badge),
                  ),
                ),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: "姓名",
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: const Text("密钥配置"),
            subtitle: const Text("配置各项 API 密钥"),
            isActive: _currentStep >= 1,
            state: _currentStep > 1
                ? StepState.complete
                : (_currentStep == 1 ? StepState.editing : StepState.indexed),
            content: Column(
              children: [
                _buildKeyField(
                  _openaiKeyController,
                  "OPENAI_API_KEY (必填)",
                  "https://dashscope.console.aliyun.com/apiKey",
                  Icons.vpn_key,
                ),
                const SizedBox(height: 8),
                _buildKeyField(
                  _gaodeKeyController,
                  "Gaode_API_Key (可选)",
                  "https://console.amap.com/dev/key/app",
                  Icons.map,
                ),
                const SizedBox(height: 8),
                _buildKeyField(
                  _dashscopeKeyController,
                  "DASHSCOPE_API_KEY (可选)",
                  "https://dashscope.console.aliyun.com/apiKey",
                  Icons.cloud,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "后端通信端口",
                    hintText: "默认 8080",
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: const Text("完成设置"),
            isActive: _currentStep >= 2,
            state: _currentStep == 2 ? StepState.complete : StepState.indexed,
            content: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("一切准备就绪！"),
                SizedBox(height: 8),
                Text("点击“继续”开始您的智能学习之旅。"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyField(
    TextEditingController controller,
    String label,
    String url,
    IconData icon,
  ) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: Icon(icon),
            ),
            obscureText: true,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.open_in_new, color: Colors.blue),
          tooltip: "获取密钥",
          onPressed: () async {
            final uri = Uri.parse(url);
            final launched = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (!launched && mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("无法打开链接: $url")));
            }
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _openaiKeyController.dispose();
    _gaodeKeyController.dispose();
    _dashscopeKeyController.dispose();
    for (final item in _extensionApiItems) {
      item['name']?.dispose();
      item['purpose']?.dispose();
      item['key']?.dispose();
    }
    super.dispose();
  }
}
