import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/pages/settings/api_settings_page.dart';

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
  final TextEditingController _basePathController = TextEditingController();

  bool _isLoading = true;
  bool _isEditing = false;
  String _configFilePath = "";
  String _backlogPath = "";

  // 主题模式
  String _themeMode = 'system'; // 'system', 'light', 'dark'

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

        // 加载主题模式
        final themeMode = config['THEME_MODE']?.toString() ?? 'system';
        _themeMode = themeMode;
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

  /// 打开文件夹选择器 → 检查/申请权限 → 设置路径
  Future<void> _onPickFolder() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    try {
      final result = await FilePicker.getDirectoryPath(
        dialogTitle: "选择数据存储文件夹",
      );
      if (result == null || !mounted) return;

      if (Platform.isAndroid) {
        final hasPermission = await checkStoragePermission();
        if (!hasPermission) {
          if (!mounted) return;
          final goToSettings = await showDialog<bool>(
            context: navigator.context,
            builder: (ctx) => AlertDialog(
              title: const Text("需要存储权限"),
              content: const Text(
                "要在所选文件夹读写文件，需要授予「所有文件访问权限」。\n\n"
                "点击「去授权」后将跳转到系统设置，请在权限中开启。",
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
            await Future.delayed(const Duration(seconds: 1));
            final granted = await checkStoragePermission();
            if (!granted && mounted) {
              showTopSnackBar(context, "权限未授予，将使用软件自有目录存储数据");
              return;
            }
          } else {
            if (mounted) {
              showTopSnackBar(context, "将使用软件自有目录存储数据");
            }
            return;
          }
        }
      }

      _basePathController.text = result;
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

  Future<void> _saveSettings() async {
    if (!mounted) return;
    try {
      final directory = await getProjectDirectory();
      final basePath = _basePathController.text.trim();

      final config = {
        "BASE_PATH": basePath.isNotEmpty ? basePath : directory.path,
        "STUDENT_ID": _idController.text.trim(),
        "STUDENT_NAME": _nameController.text.trim(),
        "SERVER_PORT": int.tryParse(_portController.text.trim()) ?? 8080,
        "THEME_MODE": _themeMode,
      };
      await saveConfigFile(config);

      // 更新全局主题
      switch (_themeMode) {
        case 'light':
          themeModeNotifier.value = ThemeMode.light;
          break;
        case 'dark':
          themeModeNotifier.value = ThemeMode.dark;
          break;
        default:
          themeModeNotifier.value = ThemeMode.system;
      }

      if (!mounted) return;
      showTopSnackBar(context, "设置已保存并应用");
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

    final screenWidth = MediaQuery.of(context).size.width;
    final bool useTwoColumns = screenWidth > 1000;

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
        child: useTwoColumns
            ? _buildTwoColumnLayout()
            : _buildSingleColumnLayout(),
      ),
    );
  }

  /// 双列布局（宽度 > 1000）
  Widget _buildTwoColumnLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle("个人信息"),
              _buildTextField(_nameController, "姓名"),
              const SizedBox(height: 12),
              _buildTextField(_idController, "学号"),
              const SizedBox(height: 24),
              _buildSectionTitle("主题模式"),
              _buildThemeModeSelector(),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle("后端通信配置"),
              _buildTextField(_portController, "通信端口", hint: "默认 8080"),
              const SizedBox(height: 24),
              _buildSectionTitle("数据存储路径"),
              _buildFolderPickerSection(),
              const SizedBox(height: 12),
              Text(
                "📁 配置文件：$_configFilePath\n"
                "📂 对话存档：$_backlogPath/yyyy-mm-dd/",
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              _buildApiSettingsCard(),
            ],
          ),
        ),
      ],
    );
  }

  /// 单列布局（宽度 ≤ 1000）
  Widget _buildSingleColumnLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle("个人信息"),
        _buildTextField(_nameController, "姓名"),
        const SizedBox(height: 12),
        _buildTextField(_idController, "学号"),
        const SizedBox(height: 24),
        _buildSectionTitle("主题模式"),
        _buildThemeModeSelector(),
        const SizedBox(height: 24),
        _buildSectionTitle("后端通信配置"),
        _buildTextField(_portController, "通信端口", hint: "默认 8080"),
        const SizedBox(height: 24),
        _buildSectionTitle("数据存储路径"),
        _buildFolderPickerSection(),
        const SizedBox(height: 12),
        Text(
          "📁 配置文件：$_configFilePath\n"
          "📂 对话存档：$_backlogPath/yyyy-mm-dd/",
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 24),
        _buildApiSettingsCard(),
      ],
    );
  }

  /// API 设置导航卡片（跳转到子页）
  Widget _buildApiSettingsCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.deepPurple.shade100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.api, color: Colors.deepPurple),
        ),
        title: const Text("API 设置"),
        subtitle: const Text("AI 服务配置、高德地图 API 等"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ApiSettingsPage(dio: widget.dio),
            ),
          );
          // 返回后刷新（子页可能修改了配置）
          _loadSettings();
        },
      ),
    );
  }

  Widget _buildThemeModeSelector() {
    return RadioGroup<String>(
      groupValue: _themeMode,
      onChanged: (val) {
        if (val == null) return;
        setState(() => _themeMode = val);
        // 立即保存并应用
        _saveSettings();
      },
      child: Column(
        children: [
          _buildThemeRadioTile('system', '跟随系统', Icons.settings_brightness),
          _buildThemeRadioTile('light', '浅色模式', Icons.light_mode),
          _buildThemeRadioTile('dark', '深色模式', Icons.dark_mode),
        ],
      ),
    );
  }

  Widget _buildThemeRadioTile(String value, String label, IconData icon) {
    final isSelected = _themeMode == value;
    return RadioListTile<String>(
      title: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected ? Colors.deepPurple : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
      value: value,
      contentPadding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
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

  Widget _buildFolderPickerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.folder_open, size: 20),
            label: Text(
              _basePathController.text.isNotEmpty
                  ? "已选择: ${_basePathController.text}"
                  : "选择输出文件夹",
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: _isEditing ? _onPickFolder : null,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _basePathController.text.isNotEmpty
              ? "数据将输出到所选文件夹"
              : "不选择则使用软件自有目录（推荐）",
          style: const TextStyle(fontSize: 12, color: Colors.grey),
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
    super.dispose();
  }
}
