import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'home_page.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

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
  final TextEditingController _baseUrlController = TextEditingController(text: "http://192.168.1.5:8080");
  final TextEditingController _outputDirController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingSettings();
  }

  Future<void> _loadExistingSettings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/.env');
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        for (var line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.contains('=') && !trimmedLine.startsWith('#')) {
            final parts = trimmedLine.split('=');
            if (parts.length >= 2) {
              final key = parts[0].trim();
              final value = parts.sublist(1).join('=').trim().replaceAll('"', '').replaceAll("'", "");
              switch (key) {
                case 'OPENAI_API_KEY': _openaiKeyController.text = value; break;
                case 'BASE_URL': _baseUrlController.text = value; break;
                case 'STUDENT_ID': _idController.text = value; break;
                case 'STUDENT_NAME': _nameController.text = value; break;
                case 'Gaode_API_Key': _gaodeKeyController.text = value; break;
                case 'DASHSCOPE_API_KEY': _dashscopeKeyController.text = value; break;
                case 'OUTPUT_DIR': _outputDirController.text = value; break;
              }
            }
          }
        }
        setState(() {}); // 刷新 UI 展示读取到的内容
      }
    } catch (e) {
      debugPrint("欢迎页：预加载配置失败: $e");
    }
  }

  void _completeSetup() async {
    if (_openaiKeyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OPENAI_API_KEY 是必填项")),
      );
      return;
    }

    await _saveToEnv(); // 保存配置

    final dio = Dio(
      BaseOptions(
        baseUrl: _baseUrlController.text,
        headers: {
          "Authorization": "Bearer ${_openaiKeyController.text.trim()}",
        },
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => MyHomePage(dio: dio)),
    );
  }

  // 保存为 .env 文件的逻辑
  Future<void> _saveToEnv() async {
    try {
      // 获取应用文档目录
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/.env');

      final content = '''
# 自动生成的配置信息
BASE_PATH="${directory.path}"

# 个人信息
STUDENT_ID=${_idController.text.trim()}
STUDENT_NAME=${_nameController.text.trim()}

# 千问/OpenAI API 密钥
OPENAI_API_KEY=${_openaiKeyController.text.trim()}

# 高德API密钥
Gaode_API_Key=${_gaodeKeyController.text.trim()}

# 阿里云 DashScope API 密钥
DASHSCOPE_API_KEY=${_dashscopeKeyController.text.trim()}

# 服务器地址
BASE_URL=${_baseUrlController.text.trim()}

# 输出文件目录
OUTPUT_DIR=${_outputDirController.text.trim()}
''';

      await file.writeAsString(content);
      debugPrint("配置已保存至: ${file.path}");
    } catch (e) {
      debugPrint("保存失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("欢迎使用星火学伴"),
        centerTitle: true,
      ),
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
            state: _currentStep > 1 ? StepState.complete : (_currentStep == 1 ? StepState.editing : StepState.indexed),
            content: Column(
              children: [
                _buildKeyField(
                  _openaiKeyController, 
                  "OPENAI_API_KEY (必填)", 
                  "https://dashscope.console.aliyun.com/apiKey",
                  Icons.vpn_key
                ),
                const SizedBox(height: 8),
                _buildKeyField(
                  _gaodeKeyController, 
                  "Gaode_API_Key (可选)", 
                  "https://console.amap.com/dev/key/app",
                  Icons.map
                ),
                const SizedBox(height: 8),
                _buildKeyField(
                  _dashscopeKeyController, 
                  "DASHSCOPE_API_KEY (可选)", 
                  "https://dashscope.console.aliyun.com/apiKey",
                  Icons.cloud
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _baseUrlController,
                  decoration: const InputDecoration(
                    labelText: "服务器地址",
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _outputDirController,
                  decoration: const InputDecoration(
                    labelText: "输出文件目录",
                    hintText: "配置 AI 生成文件的存放路径",
                    prefixIcon: Icon(Icons.folder),
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

  Widget _buildKeyField(TextEditingController controller, String label, String url, IconData icon) {
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
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("无法打开链接: $url")),
                );
              }
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
    _baseUrlController.dispose();
    _outputDirController.dispose();
    super.dispose();
  }
}
