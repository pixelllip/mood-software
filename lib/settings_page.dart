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
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _gaodeKeyController = TextEditingController();
  final TextEditingController _basePathController = TextEditingController();

  // AI 配置
  List<_SettingsAiConfigItem> _aiConfigs = [];
  int _selectedAiIndex = -1;
  List<String> _fetchedModels = [];
  bool _isFetchingModels = false;
  String? _selectedModel;
  int _fetchingIndex = -1;
  final TextEditingController _modelSearchController = TextEditingController();

  /// 根据搜索框过滤模型列表
  List<String> get _filteredModels {
    final query = _modelSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _fetchedModels;
    return _fetchedModels
        .where((m) => m.toLowerCase().contains(query))
        .toList();
  }

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
        _setTextIfNotEmpty(_portController, config['SERVER_PORT']?.toString());
        _setTextIfNotEmpty(_idController, config['STUDENT_ID']);
        _setTextIfNotEmpty(_nameController, config['STUDENT_NAME']);
        _setTextIfNotEmpty(_gaodeKeyController, config['Gaode_API_Key']);

        // 加载 AI 配置
        final aiConfigs = getAiConfigs(config);
        if (aiConfigs.isNotEmpty) {
          _aiConfigs = aiConfigs
              .map(
                (c) => _SettingsAiConfigItem(
                  nameController: TextEditingController(text: c.name),
                  baseUrlController: TextEditingController(text: c.baseUrl),
                  apiKeyController: TextEditingController(text: c.apiKey),
                  model: c.model,
                ),
              )
              .toList();
          _selectedAiIndex = aiConfigs.indexWhere((c) => c.enabled);
          if (_selectedAiIndex < 0 && _aiConfigs.isNotEmpty)
            _selectedAiIndex = 0;
          if (_selectedAiIndex >= 0 && _selectedAiIndex < _aiConfigs.length) {
            _selectedModel = aiConfigs[_selectedAiIndex].model;
          }
        }
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

  void _addAiConfig() {
    setState(() {
      _aiConfigs.add(
        _SettingsAiConfigItem(
          nameController: TextEditingController(),
          baseUrlController: TextEditingController(),
          apiKeyController: TextEditingController(),
          model: '',
        ),
      );
      _selectedAiIndex = _aiConfigs.length - 1;
      _fetchedModels = [];
      _selectedModel = null;
    });
  }

  void _removeAiConfig(int index) {
    setState(() {
      _aiConfigs[index].dispose();
      _aiConfigs.removeAt(index);
      if (_selectedAiIndex >= _aiConfigs.length) {
        _selectedAiIndex = _aiConfigs.length - 1;
      }
      _fetchedModels = [];
      _selectedModel = null;
    });
  }

  Future<void> _fetchModels(int index) async {
    final item = _aiConfigs[index];
    final baseUrl = item.baseUrlController.text.trim();
    final apiKey = item.apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先填写 Base URL 和 API Key")));
      return;
    }

    setState(() {
      _isFetchingModels = true;
      _fetchingIndex = index;
      if (_selectedAiIndex == index) {
        _fetchedModels = [];
        _selectedModel = null;
      }
    });

    try {
      final modelsUrl = baseUrl.endsWith('/')
          ? '${baseUrl}models'
          : '$baseUrl/models';
      final response = await Dio().get(
        modelsUrl,
        options: Options(
          headers: {
            "Authorization": "Bearer $apiKey",
            "Content-Type": "application/json",
          },
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final List<String> models = [];
        if (data is Map && data['data'] is List) {
          for (final m in data['data']) {
            if (m is Map && m['id'] != null) {
              models.add(m['id'].toString());
            }
          }
        }
        setState(() {
          _fetchedModels = models;
          _isFetchingModels = false;
          _fetchingIndex = -1;
        });
        if (models.isEmpty && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("未获取到模型列表")));
        }
      } else {
        setState(() {
          _isFetchingModels = false;
          _fetchingIndex = -1;
        });
      }
    } catch (e) {
      setState(() {
        _isFetchingModels = false;
        _fetchingIndex = -1;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("网络错误: $e")));
      }
    }
  }

  Future<void> _saveSettings() async {
    try {
      final directory = await getProjectDirectory();
      final basePath = _basePathController.text.trim();

      // 构建 AI 配置列表
      final aiConfigList = <Map<String, dynamic>>[];
      for (int i = 0; i < _aiConfigs.length; i++) {
        final item = _aiConfigs[i];
        aiConfigList.add({
          "name": item.nameController.text.trim(),
          "base_url": item.baseUrlController.text.trim(),
          "api_key": item.apiKeyController.text.trim(),
          "model": i == _selectedAiIndex && _selectedModel != null
              ? _selectedModel!
              : item.model,
          "enabled": i == _selectedAiIndex,
        });
      }

      final config = {
        "BASE_PATH": basePath.isNotEmpty ? basePath : directory.path,
        "STUDENT_ID": _idController.text.trim(),
        "STUDENT_NAME": _nameController.text.trim(),
        "Gaode_API_Key": _gaodeKeyController.text.trim(),
        "SERVER_PORT": int.tryParse(_portController.text.trim()) ?? 8080,
        "AI_CONFIGS": aiConfigList,
      };
      await saveConfigFile(config);

      // 同步更新 Dio
      final newPort = _portController.text.trim();
      if (newPort.isNotEmpty) {
        widget.dio.options.baseUrl = "http://127.0.0.1:$newPort";
      }
      // 用已启用配置的 API Key 更新 Authorization
      if (_selectedAiIndex >= 0 && _selectedAiIndex < _aiConfigs.length) {
        final newKey = _aiConfigs[_selectedAiIndex].apiKeyController.text
            .trim();
        if (newKey.isNotEmpty) {
          widget.dio.options.headers["Authorization"] = "Bearer $newKey";
        }
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
            _buildSectionTitle("AI 服务配置"),
            _buildAiConfigSection(),
            const SizedBox(height: 24),
            _buildSectionTitle("高德地图 API"),
            _buildTextField(_gaodeKeyController, "高德 API Key", obscure: true),
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

  Widget _buildAiConfigSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "可添加多个 AI 服务提供商，选择其中一个启用",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        ...List.generate(_aiConfigs.length, (index) {
          final isSelected = _selectedAiIndex == index;
          return _buildAiConfigCard(index, isSelected);
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text("添加 AI 配置"),
          onPressed: _isEditing ? _addAiConfig : null,
        ),
      ],
    );
  }

  Widget _buildAiConfigCard(int index, bool isSelected) {
    final item = _aiConfigs[index];
    final isFetchingThis = _isFetchingModels && _fetchingIndex == index;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<int>(
                  value: index,
                  groupValue: _selectedAiIndex,
                  onChanged: _isEditing
                      ? (v) {
                          setState(() {
                            _selectedAiIndex = v!;
                            _selectedModel = item.model.isNotEmpty
                                ? item.model
                                : null;
                          });
                        }
                      : null,
                ),
                Expanded(
                  child: Text(
                    item.nameController.text.isNotEmpty
                        ? item.nameController.text
                        : "配置 ${index + 1}",
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (_aiConfigs.length > 1 && _isEditing)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeAiConfig(index),
                  ),
              ],
            ),
            _buildTextField(
              item.nameController,
              "API 提供方描述",
              hint: "例如: 阿里云通义千问",
            ),
            const SizedBox(height: 8),
            _buildTextField(
              item.baseUrlController,
              "Base URL",
              hint: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            ),
            const SizedBox(height: 8),
            _buildTextField(item.apiKeyController, "API Key", obscure: true),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: isFetchingThis
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(isFetchingThis ? "获取中..." : "刷新模型列表"),
                  onPressed: (isFetchingThis || !_isEditing)
                      ? null
                      : () => _fetchModels(index),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (isSelected &&
                    _selectedModel != null &&
                    _selectedModel!.isNotEmpty)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Chip(
                        label: Text(
                          "已选: $_selectedModel",
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                        side: const BorderSide(color: Colors.deepPurple),
                      ),
                    ),
                  ),
              ],
            ),
            if (isSelected && _fetchedModels.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                "可选模型（点击选择）:",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _modelSearchController,
                decoration: InputDecoration(
                  hintText: "搜索模型...",
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  itemCount: _filteredModels.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final model = _filteredModels[i];
                    final isModelSelected = _selectedModel == model;
                    return ListTile(
                      dense: true,
                      title: Text(
                        model,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isModelSelected
                          ? const Icon(
                              Icons.check_circle,
                              color: Colors.deepPurple,
                              size: 20,
                            )
                          : null,
                      selected: isModelSelected,
                      onTap: _isEditing
                          ? () {
                              setState(() {
                                _selectedModel = model;
                                item.model = model;
                              });
                            }
                          : null,
                    );
                  },
                ),
              ),
            ],
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

  @override
  void dispose() {
    _modelSearchController.dispose();
    super.dispose();
  }
}

/// AI 配置表单辅助类（设置页）
class _SettingsAiConfigItem {
  final TextEditingController nameController;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  String model;

  _SettingsAiConfigItem({
    required this.nameController,
    required this.baseUrlController,
    required this.apiKeyController,
    this.model = '',
  });

  void dispose() {
    nameController.dispose();
    baseUrlController.dispose();
    apiKeyController.dispose();
  }
}
