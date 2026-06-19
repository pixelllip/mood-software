import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_page.dart';
import 'package:ai_agent/backend_utils.dart';

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

  // 第二步：基础密钥
  final TextEditingController _gaodeKeyController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  // 用户选择的输出目录（文件夹选择器）
  String? _pickedBasePath;

  // AI 配置列表
  List<_AiConfigFormItem> _aiConfigs = [];
  int _selectedAiIndex = -1;

  // 联网搜索配置（WEB_SEARCH_CONFIG）
  bool _webSearchEnabled = false;
  final TextEditingController _webSearchBaseUrlController =
      TextEditingController();
  final TextEditingController _webSearchApiKeyController =
      TextEditingController();
  final TextEditingController _webSearchModelController =
      TextEditingController();
  List<String> _webSearchModels = [];
  bool _isFetchingWebSearchModels = false;
  String? _webSearchSelectedModel;
  final TextEditingController _webSearchModelSearchController =
      TextEditingController();

  /// 搜索模型过滤
  List<String> get _filteredWebSearchModels {
    final query = _webSearchModelSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _webSearchModels;
    return _webSearchModels
        .where((m) => m.toLowerCase().contains(query))
        .toList();
  }

  // 模型列表（刷新后填充）
  List<String> _fetchedModels = [];
  bool _isFetchingModels = false;
  String? _selectedModel;
  final TextEditingController _modelSearchController = TextEditingController();

  /// 根据搜索框过滤模型列表
  List<String> get _filteredModels {
    final query = _modelSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return _fetchedModels;
    return _fetchedModels
        .where((m) => m.toLowerCase().contains(query))
        .toList();
  }

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
        _setTextIfNotEmpty(_gaodeKeyController, config['Gaode_API_Key']);
        _setTextIfNotEmpty(_portController, config['SERVER_PORT']?.toString());
        // 恢复用户之前选择的 BASE_PATH
        final savedPath = config['BASE_PATH']?.toString();
        if (savedPath != null && savedPath.isNotEmpty) {
          _pickedBasePath = savedPath;
        }

        // 加载 AI 配置
        final aiConfigs = getAiConfigs(config);
        if (aiConfigs.isNotEmpty) {
          _aiConfigs = aiConfigs
              .map(
                (c) => _AiConfigFormItem(
                  nameController: TextEditingController(text: c.name),
                  baseUrlController: TextEditingController(text: c.baseUrl),
                  apiKeyController: TextEditingController(text: c.apiKey),
                  model: c.model,
                ),
              )
              .toList();
          _selectedAiIndex = aiConfigs.indexWhere((c) => c.enabled);
          if (_selectedAiIndex < 0) _selectedAiIndex = 0;
          _selectedModel = aiConfigs[_selectedAiIndex].model;
        }

        // 加载联网搜索配置
        final wsc = getWebSearchConfig(config);
        _webSearchEnabled = wsc.enabled;
        _webSearchBaseUrlController.text = wsc.baseUrl;
        _webSearchApiKeyController.text = wsc.apiKey;
        _webSearchModelController.text = wsc.model;
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

  void _addAiConfig() {
    setState(() {
      _aiConfigs.add(
        _AiConfigFormItem(
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

  /// 如果已选 AI 配置是通义千问，自动将 API Key 和模型照搬到联网搜索
  void _autoFillWebSearch() {
    if (_selectedAiIndex < 0 || _selectedAiIndex >= _aiConfigs.length) return;
    final item = _aiConfigs[_selectedAiIndex];
    final baseUrl = item.baseUrlController.text.trim();
    if (!isDashScopeUrl(baseUrl)) return;

    final apiKey = item.apiKeyController.text.trim();
    if (apiKey.isNotEmpty) {
      _webSearchApiKeyController.text = apiKey;
    }
    if (_webSearchModelController.text.isEmpty) {
      _webSearchModelController.text = 'qwen3.5-flash';
    }
  }

  /// 获取联网搜索支持的模型列表（从千问兼容模式端点拉取）
  Future<void> _fetchWebSearchModels() async {
    if (!mounted) return;
    final apiKey = _webSearchApiKeyController.text.trim();
    if (apiKey.isEmpty) {
      showTopSnackBar(context, "请先填写搜索 API Key");
      return;
    }

    setState(() {
      _isFetchingWebSearchModels = true;
      _webSearchModels = [];
      _webSearchSelectedModel = null;
    });

    try {
      // DashScope 可调用兼容模式 /models 获取模型列表
      const modelsUrl =
          'https://dashscope.aliyuncs.com/compatible-mode/v1/models';
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
          _webSearchModels = models;
          _isFetchingWebSearchModels = false;
        });
        if (models.isEmpty && mounted) {
          showTopSnackBar(context, "未获取到模型列表，请检查 API Key");
        }
      } else {
        setState(() => _isFetchingWebSearchModels = false);
      }
    } catch (e) {
      setState(() => _isFetchingWebSearchModels = false);
      if (mounted) showTopSnackBar(context, "获取模型列表失败: $e");
    }
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
      _fetchedModels = [];
      _selectedModel = null;
    });

    try {
      final modelsUrl = baseUrl.endsWith('/')
          ? '${baseUrl}models'
          : '$baseUrl/models';
      debugPrint(">>> 请求模型列表: $modelsUrl");

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

        // OpenAI 兼容格式: { data: [{ id: "model-name", ... }] }
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
        });

        if (models.isEmpty && mounted) {
          showTopSnackBar(context, "未获取到模型列表，请检查 Base URL 和 API Key");
        }
      } else {
        setState(() => _isFetchingModels = false);
        if (mounted) {
          showTopSnackBar(context, "请求失败: ${response.statusCode}");
        }
      }
    } catch (e) {
      setState(() => _isFetchingModels = false);
      if (mounted) {
        showTopSnackBar(context, "网络错误: $e");
      }
    }
  }

  void _completeSetup() async {
    if (!mounted) return;
    // 检查是否有至少一个 AI 配置
    if (_aiConfigs.isEmpty) {
      showTopSnackBar(context, "请至少添加一个 AI API 配置");
      return;
    }

    // 检查选中的配置是否完整
    if (_selectedAiIndex < 0 || _selectedAiIndex >= _aiConfigs.length) {
      showTopSnackBar(context, "请选择一个 AI 配置");
      return;
    }

    final selected = _aiConfigs[_selectedAiIndex];
    if (selected.nameController.text.trim().isEmpty ||
        selected.baseUrlController.text.trim().isEmpty ||
        selected.apiKeyController.text.trim().isEmpty) {
      showTopSnackBar(context, "请填写完整的 AI 配置信息（名称、Base URL、API Key）");
      return;
    }

    if (_selectedModel == null || _selectedModel!.isEmpty) {
      showTopSnackBar(context, "请刷新并选择一个模型");
      return;
    }

    final portStr = _portController.text.trim();
    final port = int.tryParse(portStr) ?? 8080;

    final navigator = Navigator.of(context);
    await _saveToEnv();

    final enabledConfig = _aiConfigs[_selectedAiIndex];
    final apiKey = enabledConfig.apiKeyController.text.trim();

    if (Platform.isAndroid || Platform.isIOS) {
      // 📱 手机端：不启动本地后端，直连 AI API
      debugPrint(">>> 欢迎页 - 手机端模式：跳过后端，使用直连 AI API");
      final dio = Dio(
        BaseOptions(
          baseUrl: enabledConfig.baseUrlController.text.trim(),
          headers: {"Authorization": "Bearer $apiKey"},
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      // 强制直连，避免系统代理干扰
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => "DIRECT";
        return client;
      };

      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (context) => MyHomePage(
            dio: dio,
            useDirectApi: true,
            directBaseUrl: enabledConfig.baseUrlController.text.trim(),
            directApiKey: apiKey,
            directModel: _selectedModel,
            showTour: true,
          ),
        ),
      );
    } else {
      final backendReady = await startBackend(port);

      if (!backendReady) {
        if (!mounted) return;
        showTopSnackBar(
          context,
          "后端启动失败，请检查："
          "① config.json 中 SERVER_PORT 配置\n"
          "② Java 环境是否安装并配置了 PATH\n"
          "③ exe 同目录下是否存在 backend/ai_agent_backend.jar",
        );
        return;
      }

      final baseUrl = "http://127.0.0.1:$port";
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {"Authorization": "Bearer $apiKey"},
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      // 强制直连，避免系统代理干扰本地后端通信
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.findProxy = (uri) => "DIRECT";
        return client;
      };

      if (!mounted) return;
      navigator.pushReplacement(
        MaterialPageRoute(builder: (context) => MyHomePage(dio: dio, showTour: true)),
      );
    }
  }

  Future<void> _saveToEnv() async {
    try {
      final projectDir = await getProjectDirectory();
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
        "BASE_PATH": _pickedBasePath ?? projectDir.path,
        "STUDENT_ID": _idController.text.trim(),
        "STUDENT_NAME": _nameController.text.trim(),
        "Gaode_API_Key": _gaodeKeyController.text.trim(),
        "SERVER_PORT": int.tryParse(_portController.text.trim()) ?? 8080,
        "AI_CONFIGS": aiConfigList,
        "WEB_SEARCH_CONFIG": {
          "enabled": _webSearchEnabled,
          "base_url": _webSearchBaseUrlController.text.trim(),
          "api_key": _webSearchApiKeyController.text.trim(),
          "model": _webSearchModelController.text.trim(),
        },
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
            // 进入第三步时自动填充联网搜索（若AI是千问）
            if (_currentStep == 2) _autoFillWebSearch();
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
            title: const Text("AI 服务配置"),
            isActive: _currentStep >= 1,
            state: _currentStep > 1
                ? StepState.complete
                : (_currentStep == 1 ? StepState.editing : StepState.indexed),
            content: _buildAiConfigStep(),
          ),
          Step(
            title: const Text("其他设置"),
            isActive: _currentStep >= 2,
            state: _currentStep == 2 ? StepState.editing : StepState.indexed,
            content: _buildOtherSettingsStep(),
          ),
        ],
      ),
    );
  }

  Widget _buildAiConfigStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "添加 AI 服务提供商（可添加多个，选择其中一个启用）",
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        RadioGroup<int>(
          groupValue: _selectedAiIndex,
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedAiIndex = v;
              _fetchedModels = [];
              if (v >= 0 && v < _aiConfigs.length) {
                _selectedModel = _aiConfigs[v].model.isNotEmpty
                    ? _aiConfigs[v].model
                    : null;
              }
            });
          },
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
          icon: const Icon(Icons.add),
          label: const Text("添加 AI 配置"),
          onPressed: _addAiConfig,
        ),
      ],
    );
  }

  Widget _buildAiConfigCard(int index, bool isSelected) {
    final item = _aiConfigs[index];
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
                if (_aiConfigs.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeAiConfig(index),
                  ),
              ],
            ),
            TextField(
              controller: item.nameController,
              decoration: const InputDecoration(
                labelText: "API 提供方描述",
                hintText: "例如: 阿里云通义千问",
                prefixIcon: Icon(Icons.cloud),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.baseUrlController,
              decoration: const InputDecoration(
                labelText: "Base URL",
                hintText: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                prefixIcon: Icon(Icons.link),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "API Key",
                prefixIcon: Icon(Icons.vpn_key),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: _isFetchingModels
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_isFetchingModels ? "获取中..." : "刷新模型列表"),
                  onPressed: _isFetchingModels
                      ? null
                      : () => _fetchModels(index),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (_selectedModel != null && _selectedModel!.isNotEmpty)
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
            if (_fetchedModels.isNotEmpty) ...[
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
                      onTap: () {
                        setState(() {
                          _selectedModel = model;
                          item.model = model;
                        });
                      },
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

  Widget _buildOtherSettingsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGaodeCard(),
        const SizedBox(height: 12),
        TextField(
          controller: _portController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "后端通信端口",
            hintText: "默认 8080",
            prefixIcon: Icon(Icons.settings_ethernet),
          ),
        ),
        const SizedBox(height: 16),
        _buildFolderPickerSection(),
        const SizedBox(height: 24),
        _buildWebSearchSection(),
        const SizedBox(height: 16),
        const Text("点击\"继续\"保存配置并开始使用", style: TextStyle(color: Colors.grey)),
      ],
    );
  }

  /// 高德地图 API 配置卡片
  Widget _buildGaodeCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.green.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "高德地图 API（可选）",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.open_in_new,
                    color: Colors.blue,
                    size: 20,
                  ),
                  tooltip: "申请密钥",
                  onPressed: () =>
                      _openUrl("https://console.amap.com/dev/key/app"),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "用于天气查询和地点搜索，免费申请",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _gaodeKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "高德地图 API Key",
                hintText: "请输入高德地图 Web服务 API Key",
                prefixIcon: Icon(Icons.vpn_key),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 文件夹选择器 + 权限申请
  Widget _buildFolderPickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "数据存储路径",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open, size: 20),
          label: Text(
            _pickedBasePath != null ? "已选择: $_pickedBasePath" : "选择输出文件夹（可选）",
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: _onPickFolder,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            minimumSize: const Size(double.infinity, 0),
            alignment: Alignment.centerLeft,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _pickedBasePath != null ? "数据将输出到所选文件夹" : "不选择则使用软件自有目录",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// 打开文件夹选择器 → 检查/申请权限 → 设置路径
  Future<void> _onPickFolder() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    try {
      final result = await getDirectoryPath();
      if (result == null || !mounted) return;

      if (Platform.isAndroid) {
        // Android：检查 MANAGE_EXTERNAL_STORAGE 权限
        final hasPermission = await checkStoragePermission();
        if (!hasPermission) {
          if (!mounted) return;
          // 未授权 → 弹出提示并跳转系统设置
          final goToSettings = await showDialog<bool>(
            context: navigator.context,
            builder: (ctx) => AlertDialog(
              title: const Text("需要存储权限"),
              content: const Text(
                "要在所选文件夹读写文件，需要授予「所有文件访问权限」。\n\n"
                "点击「去授权」后将跳转到系统设置，请在「特殊权限」→「所有文件访问权限」中开启。",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("不授权，使用自有目录"),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("去授权"),
                ),
              ],
            ),
          );

          if (goToSettings == true) {
            await requestStoragePermission();
            // 跳转后用户可能授权也可能不授权，短暂延迟后检查
            await Future.delayed(const Duration(seconds: 1));
            final granted = await checkStoragePermission();
            if (!granted && mounted) {
              showTopSnackBar(context, "权限未授予，将使用软件自有目录存储数据");
              return;
            }
          } else {
            // 用户拒绝授权
            if (mounted) {
              showTopSnackBar(context, "将使用软件自有目录存储数据");
            }
            return;
          }
        }
      }

      // 权限通过或无权限要求 → 使用所选路径
      setState(() {
        _pickedBasePath = result;
      });
      if (mounted) {
        showTopSnackBar(context, "已选择文件夹: $result");
      }
    } catch (e) {
      debugPrint("选择文件夹失败: $e");
      if (mounted) {
        showTopSnackBar(context, "选择文件夹失败: $e");
      }
    }
  }

  /// 联网搜索配置区块
  Widget _buildWebSearchSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.language, size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "联网搜索（可选）",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.open_in_new,
                    color: Colors.blue,
                    size: 20,
                  ),
                  tooltip: "申请密钥",
                  onPressed: () => _openUrl(
                    "https://help.aliyun.com/document_detail/2712195.html",
                  ),
                ),
                Switch(
                  value: _webSearchEnabled,
                  onChanged: (v) => setState(() => _webSearchEnabled = v),
                  activeTrackColor: Colors.orange,
                ),
                Text(
                  _webSearchEnabled ? "已开启" : "已关闭",
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "开启后 AI 可调用联网搜索获取实时信息（需 DashScope 通义千问 API）",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_webSearchEnabled) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _webSearchBaseUrlController,
                decoration: const InputDecoration(
                  labelText: "搜索 API Base URL",
                  hintText: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                  prefixIcon: Icon(Icons.link),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _webSearchApiKeyController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "搜索 API Key",
                  hintText: "使用千问 AI 时自动继承",
                  prefixIcon: Icon(Icons.vpn_key),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: _isFetchingWebSearchModels
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                      _isFetchingWebSearchModels ? "获取中..." : "刷新模型列表",
                    ),
                    onPressed: _isFetchingWebSearchModels
                        ? null
                        : _fetchWebSearchModels,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  if (_webSearchSelectedModel != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Chip(
                          label: Text(
                            "已选: $_webSearchSelectedModel",
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          side: const BorderSide(color: Colors.orange),
                        ),
                      ),
                    ),
                ],
              ),
              if (_webSearchModels.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  "可选模型（点击选择）:",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _webSearchModelSearchController,
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
                    itemCount: _filteredWebSearchModels.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final model = _filteredWebSearchModels[i];
                      final isSelected = _webSearchSelectedModel == model;
                      return ListTile(
                        dense: true,
                        title: Text(
                          model,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.orange,
                                size: 20,
                              )
                            : null,
                        selected: isSelected,
                        onTap: () {
                          setState(() {
                            _webSearchSelectedModel = model;
                            _webSearchModelController.text = model;
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// 打开外部链接
  void _openUrl(String url) async {
    if (!mounted) return;
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      showTopSnackBar(context, "无法打开链接: $url");
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _gaodeKeyController.dispose();
    _portController.dispose();
    _modelSearchController.dispose();
    _webSearchBaseUrlController.dispose();
    _webSearchApiKeyController.dispose();
    _webSearchModelController.dispose();
    _webSearchModelSearchController.dispose();
    for (final item in _aiConfigs) {
      item.dispose();
    }
    super.dispose();
  }
}

/// AI 配置表单辅助类
class _AiConfigFormItem {
  final TextEditingController nameController;
  final TextEditingController baseUrlController;
  final TextEditingController apiKeyController;
  String model;

  _AiConfigFormItem({
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
