import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SettingsPage extends StatefulWidget {
  final Dio dio;
  final String userName;
  final String userID;
  const SettingsPage({super.key, required this.dio, required this.userName, required this.userID});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _openaiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _outputDirController = TextEditingController();
  final TextEditingController _gaodeKeyController = TextEditingController();
  final TextEditingController _dashscopeKeyController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _isLoading = true;
  bool _isEditing = false;
  String _envFilePath = "";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      
      // 优先检测项目下的 lib/.env (开发环境)
      File file = File('lib/.env');
      if (!await file.exists()) {
        file = File('${directory.path}/.env');
      }
      
      setState(() {
        _envFilePath = file.path;
      });

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
                case 'BASE_PATH':
                case 'OUTPUT_DIR': _outputDirController.text = value; break;
                case 'Gaode_API_Key': _gaodeKeyController.text = value; break;
                case 'DASHSCOPE_API_KEY': _dashscopeKeyController.text = value; break;
                case 'STUDENT_ID': _idController.text = value; break;
                case 'STUDENT_NAME': _nameController.text = value; break;
              }
            }
          }
        }
      }
      
      // 移动端逻辑：如果没填，默认使用软件目录
      if (_outputDirController.text.isEmpty && (Platform.isAndroid || Platform.isIOS)) {
        _outputDirController.text = "${directory.path}/AI_Agent_Outputs";
      }
    } catch (e) {
      debugPrint("加载失败: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/.env');

      // 移动端如果没有填，自动分配目录
      String outputDir = _outputDirController.text.trim();
      if (outputDir.isEmpty && (Platform.isAndroid || Platform.isIOS)) {
        outputDir = "${directory.path}/AI_Agent_Outputs";
      }

      final content = '''
# 自动生成的配置信息
# 基础路径
BASE_PATH="$outputDir"
OUTPUT_DIR="$outputDir"

# 个人信息
STUDENT_ID=${_idController.text.trim()}
STUDENT_NAME=${_nameController.text.trim()}

# API 密钥
OPENAI_API_KEY=${_openaiKeyController.text.trim()}
Gaode_API_Key=${_gaodeKeyController.text.trim()}
DASHSCOPE_API_KEY=${_dashscopeKeyController.text.trim()}

# 服务器地址
BASE_URL=${_baseUrlController.text.trim()}
''';

      await file.writeAsString(content);
      
      // 同步更新当前运行中的 Dio 实例
      final newBaseUrl = _baseUrlController.text.trim();
      final newKey = _openaiKeyController.text.trim();
      if (newBaseUrl.isNotEmpty) {
        widget.dio.options.baseUrl = newBaseUrl;
      }
      if (newKey.isNotEmpty) {
        widget.dio.options.headers["Authorization"] = "Bearer $newKey";
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("设置已保存并应用")));
      _loadSettings(); // 重新加载以刷新 UI
      setState(() => _isEditing = false); // 保存后退出编辑模式
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("保存失败: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("设置"),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: "编辑配置",
            )
          else
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text("取消"),
                  onPressed: () {
                    _loadSettings(); // 重新加载以恢复原始值
                    setState(() => _isEditing = false);
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text("保存"),
                  onPressed: _saveSettings,
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle("个人信息"),
            if (!_isEditing)
              // 非编辑状态：显示当前姓名学号
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 35,
                        child: Icon(Icons.person, size: 40),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _nameController.text.isNotEmpty ? _nameController.text : (widget.userName.isNotEmpty ? widget.userName : "未设置姓名"),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _idController.text.isNotEmpty ? "学号: ${_idController.text}" : (widget.userID.isNotEmpty ? "学号: ${widget.userID}" : "未设置学号"),
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              // 编辑状态：显示可编辑的输入框
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 35,
                    child: Icon(Icons.person, size: 40),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      children: [
                        _buildTextField(_nameController, "姓名"),
                        const SizedBox(height: 12),
                        _buildTextField(_idController, "学号"),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            _buildSectionTitle("API 核心配置"),
            _buildTextField(_openaiKeyController, "OPENAI_API_KEY (千问/OpenAI)", obscure: true),
            const SizedBox(height: 12),
            _buildTextField(_baseUrlController, "BASE_URL (服务器地址)", 
              hint: Platform.isWindows ? "本机调试用 http://127.0.0.1:8080" : "手机调试用 http://电脑IP:8080"),
            
            const SizedBox(height: 24),
            _buildSectionTitle("文件与输出"),
            _buildTextField(_outputDirController, "输出文件目录 (BASE_PATH)", 
              hint: Platform.isWindows ? "C:/Users/.../Outputs" : "移动端默认在软件目录下"),
            
            const SizedBox(height: 24),
            _buildSectionTitle("扩展 API"),
            _buildTextField(_gaodeKeyController, "Gaode_API_Key (高德地图)", obscure: true),
            const SizedBox(height: 12),
            _buildTextField(_dashscopeKeyController, "DASHSCOPE_API_KEY (阿里云)", obscure: true),
            
            const SizedBox(height: 20),
            Text("当前配置文件路径：\n$_envFilePath", 
              style: const TextStyle(fontSize: 12, color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, {bool obscure = false, String? hint}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      readOnly: !_isEditing,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabled: _isEditing,
      ),
    );
  }
}
