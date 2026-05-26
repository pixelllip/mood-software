import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:ai_agent/backend_utils.dart';

/// API 设置子页（AI 服务配置 + 更多 API）
class ApiSettingsPage extends StatefulWidget {
  final Dio dio;

  const ApiSettingsPage({super.key, required this.dio});

  @override
  State<ApiSettingsPage> createState() => _ApiSettingsPageState();
}

class _ApiSettingsPageState extends State<ApiSettingsPage> {
  final TextEditingController _gaodeKeyController = TextEditingController();

  // AI 配置
  List<_SettingsAiConfigItem> _aiConfigs = [];
  int _selectedAiIndex = -1;
  List<String> _fetchedModels = [];
  bool _isFetchingModels = false;
  String? _selectedModel;
  int _fetchingIndex = -1;
  final TextEditingController _modelSearchController = TextEditingController();

  List<String> get _filteredModels {
    final query = _modelSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _fetchedModels;
    return _fetchedModels
        .where((m) => m.toLowerCase().contains(query))
        .toList();
  }

  bool _isLoading = true;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final config = await loadConfigFile();
      if (config.isNotEmpty) {
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
          if (_selectedAiIndex < 0 && _aiConfigs.isNotEmpty) {
            _selectedAiIndex = 0;
          }
          if (_selectedAiIndex >= 0 && _selectedAiIndex < _aiConfigs.length) {
            _selectedModel = aiConfigs[_selectedAiIndex].model;
          }
        }
      }
    } catch (e) {
      debugPrint("加载 API 设置失败: $e");
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
    if (!mounted) return;
    final item = _aiConfigs[index];
    final baseUrl = item.baseUrlController.text.trim();
    final apiKey = item.apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      if (!mounted) return;
      showTopSnackBar(context, "请先填写 Base URL 和 API Key");
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
          showTopSnackBar(context, "未获取到模型列表");
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
        showTopSnackBar(context, "网络错误: $e");
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!mounted) return;
    try {
      final config = await loadConfigFile();

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

      config['AI_CONFIGS'] = aiConfigList;
      config['Gaode_API_Key'] = _gaodeKeyController.text.trim();

      await saveConfigFile(config);

      // 同步更新 Dio
      if (Platform.isAndroid) {
        if (_selectedAiIndex >= 0 && _selectedAiIndex < _aiConfigs.length) {
          final item = _aiConfigs[_selectedAiIndex];
          final baseUrl = item.baseUrlController.text.trim();
          final apiKey = item.apiKeyController.text.trim();
          if (baseUrl.isNotEmpty) {
            widget.dio.options.baseUrl = baseUrl;
          }
          if (apiKey.isNotEmpty) {
            widget.dio.options.headers["Authorization"] = "Bearer $apiKey";
          }
        }
      } else {
        if (_selectedAiIndex >= 0 && _selectedAiIndex < _aiConfigs.length) {
          final newKey = _aiConfigs[_selectedAiIndex].apiKeyController.text
              .trim();
          if (newKey.isNotEmpty) {
            widget.dio.options.headers["Authorization"] = "Bearer $newKey";
          }
        }
      }

      if (!mounted) return;
      showTopSnackBar(context, "API 设置已保存");
      setState(() => _isEditing = false);
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, "保存失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("API 设置"),
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
            _buildSectionTitle("AI 服务配置"),
            _buildAiConfigSection(),
            const SizedBox(height: 32),
            _buildSectionTitle("更多 API"),
            _buildMoreApisSection(),
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

  Widget _buildAiConfigSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "可添加多个 AI 服务提供商，选择其中一个启用",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        RadioGroup<int>(
          groupValue: _selectedAiIndex,
          onChanged: _isEditing
              ? (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedAiIndex = v;
                    if (v >= 0 && v < _aiConfigs.length) {
                      _selectedModel = _aiConfigs[v].model.isNotEmpty
                          ? _aiConfigs[v].model
                          : null;
                    }
                  });
                }
              : (_) {},
          child: Column(
            children: [
              ...List.generate(_aiConfigs.length, (index) {
                final isSelected = _selectedAiIndex == index;
                return _buildAiConfigCard(index, isSelected);
              }),
            ],
          ),
        ),
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
                Radio<int>(value: index),
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
                  separatorBuilder: (_, _) => const Divider(height: 1),
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

  Widget _buildMoreApisSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "配置第三方 API 密钥以启用更多功能",
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        _buildTextField(_gaodeKeyController, "高德地图 API Key", obscure: true),
        const SizedBox(height: 4),
        const Text(
          "用于 GPS 定位逆编码获取详细地址信息",
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
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
    _gaodeKeyController.dispose();
    super.dispose();
  }
}

/// AI 配置表单辅助类
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
