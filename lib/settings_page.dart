import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:ai_agent/backend_utils.dart';

class SettingsPage extends StatefulWidget {
  final Dio dio;
  final String userName;
  final String userID;
  const SettingsPage({
    super.key,
    required this.dio,
    required this.userName,
    required this.userID,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _openaiKeyController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _gaodeKeyController = TextEditingController();
  final TextEditingController _dashscopeKeyController = TextEditingController();
  final TextEditingController _basePathController = TextEditingController();

  bool _isLoading = true;
  bool _isEditing = false;
  String _configFilePath = "";
  String _backlogPath = "";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final directory = await getProjectDirectory();
      final config = await loadConfigFile();

      // 取 BASE_PATH（优先用 config 里的，否则用默认目录）
      final basePath = config['BASE_PATH']?.toString() ?? directory.path;
      setState(() {
        _configFilePath = '${directory.path}/config.json';
        _backlogPath = '$basePath/Backlog';
      });

      if (config.isNotEmpty) {
        _setTextIfNotEmpty(_basePathController, config['BASE_PATH']);
        _setTextIfNotEmpty(_openaiKeyController, config['OPENAI_API_KEY']);
        _setTextIfNotEmpty(_portController, config['SERVER_PORT']?.toString());
        _setTextIfNotEmpty(_idController, config['STUDENT_ID']);
        _setTextIfNotEmpty(_nameController, config['STUDENT_NAME']);
        _setTextIfNotEmpty(_gaodeKeyController, config['Gaode_API_Key']);
        _setTextIfNotEmpty(
          _dashscopeKeyController,
          config['DASHSCOPE_API_KEY'],
        );
      }
    } catch (e) {
      debugPrint("加载失败: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setTextIfNotEmpty(TextEditingController ctrl, dynamic value) {
    if (value != null && value.toString().isNotEmpty) {
      ctrl.text = value.toString();
    }
  }

  Future<void> _saveSettings() async {
    try {
      final directory = await getProjectDirectory();
      // 用户可自定义 BASE_PATH，为空则用默认
      final basePath = _basePathController.text.trim();
      final config = {
        "BASE_PATH": basePath.isNotEmpty ? basePath : directory.path,
        "STUDENT_ID": _idController.text.trim(),
        "STUDENT_NAME": _nameController.text.trim(),
        "OPENAI_API_KEY": _openaiKeyController.text.trim(),
        "Gaode_API_Key": _gaodeKeyController.text.trim(),
        "DASHSCOPE_API_KEY": _dashscopeKeyController.text.trim(),
        "SERVER_PORT": int.tryParse(_portController.text.trim()) ?? 8080,
      };
      await saveConfigFile(config);

      // 同步更新 Dio
      final newPort = _portController.text.trim();
      final newKey = _openaiKeyController.text.trim();
      if (newPort.isNotEmpty) {
        widget.dio.options.baseUrl = "http://127.0.0.1:$newPort";
      }
      if (newKey.isNotEmpty) {
        widget.dio.options.headers["Authorization"] = "Bearer $newKey";
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("设置已保存并应用")));
      setState(() => _isEditing = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("保存失败: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text("设置"),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            )
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _saveSettings),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle("个人信息"),
            _buildTextField(_nameController, "姓名"),
            const SizedBox(height: 12),
            _buildTextField(_idController, "学号"),
            const SizedBox(height: 24),
            _buildSectionTitle("API 核心配置"),
            _buildTextField(
              _openaiKeyController,
              "OPENAI_API_KEY",
              obscure: true,
            ),
            const SizedBox(height: 12),
            _buildTextField(_gaodeKeyController, "高德 API Key", obscure: true),
            const SizedBox(height: 12),
            _buildTextField(
              _dashscopeKeyController,
              "DashScope API Key",
              obscure: true,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle("后端通信配置"),
            _buildTextField(_portController, "通信端口", hint: "默认 8080"),
            const SizedBox(height: 24),
            _buildSectionTitle("数据存储路径"),
            _buildTextField(
              _basePathController,
              "BASE_PATH（数据根目录）",
              hint: "例如: C:/Users/.../Academic Aegis",
            ),
            const SizedBox(height: 12),
            Text(
              "📁 配置文件：$_configFilePath\n"
              "📂 对话存档：$_backlogPath/yyyy-mm-dd/",
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.deepPurple,
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      readOnly: !_isEditing,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        enabled: _isEditing,
      ),
    );
  }
}
