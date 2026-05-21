import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _outputDirController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final List<Map<String, TextEditingController>> _extensionApiItems = [];

  bool _isLoading = true;
  bool _isEditing = false;
  String _envFilePath = "";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _addExtensionApiItem({
    String name = '',
    String purpose = '',
    String key = '',
  }) {
    _extensionApiItems.add({
      'name': TextEditingController(text: name),
      'purpose': TextEditingController(text: purpose),
      'key': TextEditingController(text: key),
    });
  }

  void _removeExtensionApiItem(int index) {
    setState(() {
      _extensionApiItems[index]['name']?.dispose();
      _extensionApiItems[index]['purpose']?.dispose();
      _extensionApiItems[index]['key']?.dispose();
      _extensionApiItems.removeAt(index);
    });
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法打开链接: $url')));
    }
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
              final value = parts
                  .sublist(1)
                  .join('=')
                  .trim()
                  .replaceAll('"', '')
                  .replaceAll("'", "");

              switch (key) {
                case 'OPENAI_API_KEY':
                  _openaiKeyController.text = value;
                  break;
                case 'BASE_URL':
                  _baseUrlController.text = value;
                  break;
                case 'BASE_PATH':
                case 'OUTPUT_DIR':
                  _outputDirController.text = value;
                  break;
                case 'Gaode_API_Key':
                  final gaodeVal = value;
                  final gaodeExists = _extensionApiItems.any(
                    (e) =>
                        (e['key']?.text.trim().isNotEmpty == true &&
                            e['key']?.text.trim() == gaodeVal) ||
                        (e['name']?.text.trim().toLowerCase() == 'gaode'),
                  );
                  if (!gaodeExists) {
                    _extensionApiItems.add({
                      'name': TextEditingController(text: 'Gaode'),
                      'purpose': TextEditingController(text: '高德地图'),
                      'key': TextEditingController(text: gaodeVal),
                    });
                  }
                  break;
                case 'DASHSCOPE_API_KEY':
                  final dashVal = value;
                  final dashExists = _extensionApiItems.any(
                    (e) =>
                        (e['key']?.text.trim().isNotEmpty == true &&
                            e['key']?.text.trim() == dashVal) ||
                        (e['name']?.text.trim().toLowerCase() == 'dashscope'),
                  );
                  if (!dashExists) {
                    _extensionApiItems.add({
                      'name': TextEditingController(text: 'DashScope'),
                      'purpose': TextEditingController(text: '阿里云 DashScope'),
                      'key': TextEditingController(text: dashVal),
                    });
                  }
                  break;
                case 'STUDENT_ID':
                  _idController.text = value;
                  break;
                case 'STUDENT_NAME':
                  _nameController.text = value;
                  break;
                default:
                  final extMatch = RegExp(
                    r'^EXT_API_(NAME|PURPOSE|KEY)_(\d+)$',
                  ).firstMatch(key);
                  if (extMatch != null) {
                    final field = extMatch.group(1)!.toLowerCase();
                    final index = int.parse(extMatch.group(2)!) - 1;
                    while (_extensionApiItems.length <= index) {
                      _extensionApiItems.add({
                        'name': TextEditingController(),
                        'purpose': TextEditingController(),
                        'key': TextEditingController(),
                      });
                    }
                    if (field == 'name') {
                      _extensionApiItems[index]['name']?.text = value;
                    } else if (field == 'purpose') {
                      _extensionApiItems[index]['purpose']?.text = value;
                    } else if (field == 'key') {
                      _extensionApiItems[index]['key']?.text = value;
                    }
                  }
                  break;
              }
            }
          }
        }
      }

      // 已在解析阶段将 Gaode/DashScope 转换为扩展 API 条目

      // 移动端逻辑：如果没填，默认使用 Aegis Academic 目录
      if (_outputDirController.text.isEmpty &&
          (Platform.isAndroid || Platform.isIOS)) {
        _outputDirController.text = "/storage/emulated/0/Aegis Academic";
      }
    } catch (e) {
      debugPrint("加载失败: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      // 确定保存路径：桌面端优先写 lib/.env（源码目录），移动端写应用文档目录
      File file;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        file = File('lib/.env');
      } else {
        final directory = await getApplicationDocumentsDirectory();
        file = File('${directory.path}/.env');
      }

      // 移动端如果没有填，自动分配目录
      String outputDir = _outputDirController.text.trim();
      if (outputDir.isEmpty && (Platform.isAndroid || Platform.isIOS)) {
        outputDir = "/storage/emulated/0/Aegis Academic";
      }

      // 统一通过扩展 API 列表处理，无需单独合并字段
      // 保存前：读取现有 .env，若包含旧的 Gaode/DashScope 键，则合并为扩展条目
      if (await file.exists()) {
        final existing = await file.readAsString();

        void _tryAddLegacy(String keyName, String label, String purpose) {
          final match = RegExp(
            '^' + RegExp.escape(keyName) + '=(.*)\$',
            multiLine: true,
          ).firstMatch(existing);
          if (match != null) {
            var val = match.group(1)!.trim();
            val = val.replaceAll('"', '').replaceAll("'", '');
            if (val.isNotEmpty) {
              final exists = _extensionApiItems.any(
                (e) =>
                    (e['key']?.text.trim().isNotEmpty == true &&
                        e['key']?.text.trim() == val) ||
                    (e['name']?.text.trim().toLowerCase() ==
                        label.toLowerCase()),
              );
              if (!exists) {
                _extensionApiItems.add({
                  'name': TextEditingController(text: label),
                  'purpose': TextEditingController(text: purpose),
                  'key': TextEditingController(text: val),
                });
              }
            }
          }
        }

        _tryAddLegacy('Gaode_API_Key', 'Gaode', '高德地图');
        _tryAddLegacy('DASHSCOPE_API_KEY', 'DashScope', '阿里云 DashScope');
      }

      final buffer = StringBuffer();
      buffer.writeln('# 自动生成的配置信息');
      buffer.writeln('# 基础路径');
      buffer.writeln('BASE_PATH="$outputDir"');
      buffer.writeln('OUTPUT_DIR="$outputDir"');
      buffer.writeln();
      buffer.writeln('# 个人信息');
      buffer.writeln('STUDENT_ID=${_idController.text.trim()}');
      buffer.writeln('STUDENT_NAME=${_nameController.text.trim()}');
      buffer.writeln();
      buffer.writeln('# API 密钥');
      buffer.writeln('OPENAI_API_KEY=${_openaiKeyController.text.trim()}');
      buffer.writeln();
      buffer.writeln('# 服务器地址');
      buffer.writeln('BASE_URL=${_baseUrlController.text.trim()}');
      if (_extensionApiItems.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('# 自定义扩展 API 标签及用途');
        for (var i = 0; i < _extensionApiItems.length; i++) {
          buffer.writeln(
            'EXT_API_NAME_${i + 1}=${_extensionApiItems[i]['name']?.text.trim()}',
          );
          buffer.writeln(
            'EXT_API_PURPOSE_${i + 1}=${_extensionApiItems[i]['purpose']?.text.trim()}',
          );
          buffer.writeln(
            'EXT_API_KEY_${i + 1}=${_extensionApiItems[i]['key']?.text.trim()}',
          );
        }
      }
      final content = buffer.toString();

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("设置已保存并应用")));
      _loadSettings(); // 重新加载以刷新 UI
      setState(() => _isEditing = false); // 保存后退出编辑模式
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
                              _nameController.text.isNotEmpty
                                  ? _nameController.text
                                  : (widget.userName.isNotEmpty
                                        ? widget.userName
                                        : "未设置姓名"),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _idController.text.isNotEmpty
                                  ? "学号: ${_idController.text}"
                                  : (widget.userID.isNotEmpty
                                        ? "学号: ${widget.userID}"
                                        : "未设置学号"),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
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
            _buildTextField(
              _openaiKeyController,
              "OPENAI_API_KEY (千问/OpenAI)",
              obscure: true,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              _baseUrlController,
              "BASE_URL (服务器地址)",
              hint: Platform.isWindows
                  ? "本机调试用 http://127.0.0.1:8080"
                  : Platform.isAndroid
                  ? "安卓真机请填写电脑局域网IP:8080，模拟器可用 10.0.2.2:8080"
                  : "iOS真机请填写电脑局域网IP:8080，模拟器可用 localhost:8080",
            ),
            const SizedBox(height: 12),
            _buildTextField(
              _outputDirController,
              "输出文件目录 (BASE_PATH)",
              hint: Platform.isWindows ? "C:/Users/.../Outputs" : "移动端默认在软件目录下",
            ),

            const SizedBox(height: 24),
            _buildSectionTitle("扩展 API"),
            const SizedBox(height: 16),
            ..._extensionApiItems.asMap().entries.map((entry) {
              final index = entry.key;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '扩展API ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: '删除此扩展 API',
                              onPressed: () => _removeExtensionApiItem(index),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(
                          _extensionApiItems[index]['name']!,
                          '标签',
                          hint: '例如：天气、图像识别、翻译',
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(
                          _extensionApiItems[index]['purpose']!,
                          '用途',
                          hint: '说明该 API 的用途',
                        ),
                        const SizedBox(height: 8),
                        _buildTextField(
                          _extensionApiItems[index]['key']!,
                          'API Key',
                          obscure: true,
                          hint: '该扩展 API 的密钥',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            if (_isEditing)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _addExtensionApiItem()),
                  icon: const Icon(Icons.add),
                  label: const Text('添加扩展 API'),
                ),
              ),
            const SizedBox(height: 20),
            Text(
              "当前配置文件路径：\n$_envFilePath",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
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
    String? url,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      readOnly: !_isEditing,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabled: _isEditing,
        suffixIcon: url != null
            ? IconButton(
                icon: const Icon(Icons.open_in_new, color: Colors.blue),
                tooltip: '打开链接',
                onPressed: () => _openUrl(url),
              )
            : null,
      ),
    );
  }
}
