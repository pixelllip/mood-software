import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/pages/scores/score_result_page.dart';
import 'package:ai_agent/pages/settings/settings_page.dart';
import 'package:ai_agent/pages/history/history_page.dart';
import 'package:ai_agent/pages/study/study_analysis_page.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:ai_agent/services/local_backend.dart';
import 'package:ai_agent/services/location_service.dart';
import 'package:ai_agent/services/study_analysis_service.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ai_agent/pages/feature_tour.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.dio,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
    this.showTour = false,
  });
  final Dio dio;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  final bool showTour;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 0;
  final GlobalKey<_HomeContentState> _homeContentKey =
      GlobalKey<_HomeContentState>();

  String userID = "未知学号";
  String userName = "未知用户";
  String? _currentChatSummary;
  int _chatTabIndex = 0;

  final List<String> pageTitles = ["AI聊天", "我的成绩", "日程安排", "每日学情"];

  /// 已展示过 Tooltip 的 tab 索引集合
  final Set<int> _tooltipShown = {};

  static const List<String> _tabTooltips = [
    '💡 你可以点击 + 号新建对话，或添加文件/图片进行 OCR 识别',
    '💡 输入学号查询成绩，使用底部 Tab 可新增或修改成绩',
    '💡 支持 Markdown 编辑日程，也可用 AI 一键生成',
    '💡 选择日期范围，自动匹配学习关键词并计算每日评分',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    if (widget.showTour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FeatureTour.show(context, onCompleted: _onTourCompleted);
      });
    }
  }

  Future<void> _loadUserInfo() async {
    try {
      final config = await loadConfigFile();
      if (mounted && config.isNotEmpty) {
        setState(() {
          final id = config['STUDENT_ID']?.toString() ?? '';
          final name = config['STUDENT_NAME']?.toString() ?? '';
          if (id.isNotEmpty) userID = id;
          if (name.isNotEmpty) userName = name;
        });
      }
    } catch (e) {
      debugPrint("主页：加载用户信息失败: $e");
    }
  }

  /// 保存主题模式到配置文件
  Future<void> _saveThemeMode(ThemeMode mode) async {
    try {
      final config = await loadConfigFile();
      String modeStr;
      switch (mode) {
        case ThemeMode.light:
          modeStr = 'light';
          break;
        case ThemeMode.dark:
          modeStr = 'dark';
          break;
        default:
          modeStr = 'system';
      }
      config['THEME_MODE'] = modeStr;
      await saveConfigFile(config);
    } catch (e) {
      debugPrint("保存主题模式失败: $e");
    }
  }

  void onItemTapped(int index) {
    if (index == selectedIndex) return;
    // 切换页面时取消所有TextField焦点（收起键盘，防止手机端输入框保持选中）
    FocusScope.of(context).unfocus();
    setState(() {
      _displayedIndex = index;
      selectedIndex = index;
    });
    // 首次切换 tab 时显示 Tooltip
    _showTabTooltip(index);
  }

  void _showTabTooltip(int index) {
    if (_tooltipShown.contains(index)) return;
    _tooltipShown.add(index);
    final message = _tabTooltips[index];
    if (message.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showTopSnackBar(context, message, bottomMargin: 82);
    });
  }

  /// 从设置页面重新触发 Tour
  void _restartTour() {
    FeatureTour.show(context, onCompleted: _onTourCompleted);
  }

  Future<void> _onTourCompleted() async {
    _tooltipShown.clear();
    try {
      final config = await loadConfigFile();
      config['FEATURE_TOUR_COMPLETED'] = true;
      await saveConfigFile(config);
    } catch (_) {}
  }

  int _displayedIndex = 0; // AppBar实际显示的标题索引

  Widget buildDrawer() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      child: ListTileTheme(
        selectedColor: isDark ? Colors.white : Theme.of(context).primaryColor,
        iconColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
        textColor: isDark ? Colors.white : Colors.black87,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(
                userName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              accountEmail: Text(userID),
              currentAccountPicture: const CircleAvatar(
                child: Icon(Icons.person),
              ),
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
            ),
            ListTile(
              leading: Icon(
                selectedIndex == 0
                    ? Icons.chat_bubble
                    : Icons.chat_bubble_outline,
              ),
              title: const Text("AI聊天"),
              selected: selectedIndex == 0,
              onTap: () {
                onItemTapped(0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                selectedIndex == 1
                    ? Icons.assessment
                    : Icons.assessment_outlined,
              ),
              title: const Text("成绩管理"),
              selected: selectedIndex == 1,
              onTap: () {
                onItemTapped(1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                selectedIndex == 2
                    ? Icons.event_note
                    : Icons.event_note_outlined,
              ),
              title: const Text("日程安排"),
              selected: selectedIndex == 2,
              onTap: () {
                onItemTapped(2);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                selectedIndex == 3
                    ? Symbols.overview
                    : Symbols.overview_rounded,
                fill: selectedIndex == 3 ? 1 : 0,
              ),
              title: const Text("每日学情"),
              selected: selectedIndex == 3,
              onTap: () {
                onItemTapped(3);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            // 快捷深浅色切换（检测实际亮度）
            ListTile(
              leading: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode
                    : Icons.dark_mode,
              ),
              title: Text(
                Theme.of(context).brightness == Brightness.dark
                    ? "切换到浅色模式"
                    : "切换到深色模式",
              ),
              onTap: () {
                Navigator.pop(context);
                final next = Theme.of(context).brightness == Brightness.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
                themeModeNotifier.value = next;
                _saveThemeMode(next);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("设置"),
              onTap: () async {
                Navigator.pop(context); // Close drawer
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsPage(
                      dio: widget.dio,
                      userName: userName,
                      userID: userID,
                    ),
                  ),
                );
                _loadUserInfo(); // 刷新用户信息
                if (result == true) _restartTour();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget buildRail({bool compact = false}) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemTapped,
      // 高度不足时仅显示选中项的标签，避免溢出
      labelType: compact
          ? NavigationRailLabelType.selected
          : NavigationRailLabelType.all,
      destinations: [
        NavigationRailDestination(
          icon: Icon(selectedIndex == 0 ? Icons.home : Icons.home_outlined),
          label: const Text("AI聊天"),
        ),
        NavigationRailDestination(
          icon: Icon(
            selectedIndex == 1 ? Icons.assessment : Icons.assessment_outlined,
          ),
          label: const Text("成绩管理"),
        ),
        NavigationRailDestination(
          icon: Icon(
            selectedIndex == 2 ? Icons.event_note : Icons.event_note_outlined,
          ),
          label: const Text("日程安排"),
        ),
        NavigationRailDestination(
          icon: Icon(
            selectedIndex == 3 ? Symbols.overview : Symbols.overview_rounded,
            fill: selectedIndex == 3 ? 1 : 0,
          ),
          label: const Text("每日学情"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // 宽度 < 450 或高度 < 500 时切换为抽屉模式，避免导航栏溢出
    final bool isMobile = screenSize.width < 450 || screenSize.height < 500;
    // 移动端平台检测（用于键盘行为），无论横竖屏都生效
    final bool isMobilePlatform = Platform.isAndroid || Platform.isIOS;

    return Stack(
      fit: StackFit.expand,
      children: [
        Scaffold(
          // 移动端键盘弹出时自动调整 body，让输入框保持在键盘上方
          // 桌面端保持不动
          resizeToAvoidBottomInset: isMobilePlatform,
          appBar: AppBar(
            title: Text(
              _displayedIndex == 0
                  ? (_chatTabIndex == 1
                        ? "聊天历史"
                        : (_currentChatSummary ?? "AI聊天"))
                  : pageTitles[_displayedIndex],
            ),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: [
              if (selectedIndex == 0 && _chatTabIndex == 0) ...[
                IconButton(
                  icon: const Icon(Icons.add_comment),
                  tooltip: "新建对话",
                  onPressed: () {
                    setState(() {
                      _currentChatSummary = null;
                    });
                    _homeContentKey.currentState?.resetChat();
                  },
                ),
              ],
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SettingsPage(
                        dio: widget.dio,
                        userName: userName,
                        userID: userID,
                      ),
                    ),
                  );
                  _loadUserInfo(); // 刷新用户信息
                  if (result == true) _restartTour();
                },
              ),
            ],
          ),
          drawer: isMobile ? buildDrawer() : null,
          drawerEdgeDragWidth: isMobile
              ? MediaQuery.of(context).size.width * 0.16
              : null,

          body: Row(
            children: [
              // 桌面侧栏（移动端用 AnimatedSize 平滑收起/展开）
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.centerLeft,
                child: isMobile
                    ? const SizedBox.shrink()
                    : Container(
                        width: 80,
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: buildRail(
                                compact: screenSize.height < 600,
                              ),
                            ),
                            // 主题切换（图标靠上，文字上边沿对齐底部导航栏上边沿）
                            SizedBox(
                              height: 72,
                              child: InkWell(
                                onTap: () {
                                  final next =
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? ThemeMode.light
                                      : ThemeMode.dark;
                                  themeModeNotifier.value = next;
                                  _saveThemeMode(next);
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 10),
                                    Icon(
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Icons.light_mode
                                          : Icons.dark_mode,
                                      size: 24,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "主题",
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 设置（与底部导航栏对齐，底部留安全边距）
                            SizedBox(
                              height: 66,
                              child: InkWell(
                                onTap: () async {
                                  final result = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SettingsPage(
                                        dio: widget.dio,
                                        userName: userName,
                                        userID: userID,
                                      ),
                                    ),
                                  );
                                  _loadUserInfo();
                                  if (result == true) _restartTour();
                                },
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.settings, size: 24),
                                    const SizedBox(height: 4),
                                    Text(
                                      "设置",
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 底部安全距离，防止设置触底
                            SizedBox(
                              height: MediaQuery.of(context).padding.bottom + 4,
                            ),
                          ],
                        ),
                      ),
              ),
              Expanded(
                child: IndexedStack(
                  index: selectedIndex,
                  children: [
                    HomeContent(
                      key: _homeContentKey,
                      dio: widget.dio,
                      useDirectApi: widget.useDirectApi,
                      directBaseUrl: widget.directBaseUrl,
                      directApiKey: widget.directApiKey,
                      directModel: widget.directModel,
                      onSummaryUpdate: (summary) {
                        setState(() {
                          _currentChatSummary = summary;
                        });
                      },
                      onChatTabChanged: (index) {
                        setState(() {
                          _chatTabIndex = index;
                        });
                      },
                    ),
                    ScorePage(dio: widget.dio),
                    SchedulePage(
                      dio: widget.dio,
                      isActive: selectedIndex == 2,
                      studentID: userID,
                      studentName: userName,
                      useDirectApi: widget.useDirectApi,
                      directBaseUrl: widget.directBaseUrl,
                      directApiKey: widget.directApiKey,
                      directModel: widget.directModel,
                    ),
                    StudyAnalysisPage(
                      dio: widget.dio,
                      useDirectApi: widget.useDirectApi,
                      directBaseUrl: widget.directBaseUrl,
                      directApiKey: widget.directApiKey,
                      directModel: widget.directModel,
                      isActive: selectedIndex == 3,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HomeContent extends StatefulWidget {
  final Dio dio;
  final Function(String)? onSummaryUpdate;
  final Function(int)? onChatTabChanged;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  const HomeContent({
    super.key,
    required this.dio,
    this.onSummaryUpdate,
    this.onChatTabChanged,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

/// 附件信息
class AttachmentInfo {
  final String type; // 'code' 或 'image'
  final String name;
  final String data; // 文件内容（文本）或 base64（图片）
  final String? ocrText; // 图片OCR识别结果（可选）
  const AttachmentInfo({
    required this.type,
    required this.name,
    required this.data,
    this.ocrText,
  });
}

class _HomeContentState extends State<HomeContent>
    with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _messages = [
    {"text": "你好！我是你的AI助手，有什么我可以帮你的吗？", "isUser": false},
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  /// 已添加的附件列表
  final List<AttachmentInfo> _attachments = [];

  /// 当前提问是否涉及地图/位置相关
  bool _isMapQuery = false;

  /// OCR 后台识别中（禁用发送按钮）
  bool _isOcrRunning = false;

  /// 地图相关关键词列表
  static const _mapKeywords = [
    '地图',
    '导航',
    '位置',
    '路线',
    '路况',
    '在哪里',
    '怎么去',
    '地址',
    '附近',
    '周边',
    '地理位置',
    '定位',
    '坐标',
    '经纬度',
    'map',
    'location',
    '导航到',
    'route',
    'direction',
    '地图上',
    '高德',
    'amap',
  ];

  /// 检测文本是否包含地图相关关键词
  bool _isMapRelated(String text) {
    final lower = text.toLowerCase();
    return _mapKeywords.any((kw) => lower.contains(kw));
  }

  /// 打开高德地图（手机端优先App，桌面端跳转网页）
  Future<void> _openAmap() async {
    final uriAndroid = Uri.parse(
      'androidamap://openFeature?featureName=MapShow',
    );
    final uriIos = Uri.parse('iosamap://');
    final uriWeb = Uri.parse('https://ditu.amap.com/');

    try {
      if (Platform.isAndroid) {
        if (await canLaunchUrl(uriAndroid)) {
          await launchUrl(uriAndroid, mode: LaunchMode.externalApplication);
          return;
        }
      } else if (Platform.isIOS) {
        if (await canLaunchUrl(uriIos)) {
          await launchUrl(uriIos, mode: LaunchMode.externalApplication);
          return;
        }
      }
      // 回退到网页版
      await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
    } catch (e) {
      // 如果App跳转失败，尝试网页版
      try {
        await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
      } catch (e2) {
        debugPrint("打开高德地图失败: $e2");
        if (mounted) {
          showTopSnackBar(
            context,
            "无法打开高德地图，请手动访问 ditu.amap.com",
            bottomMargin: 142,
          );
        }
      }
    }
  }

  /// 添加文件附件（代码文件读取为文本，图片转为 base64）
  Future<void> _handlePickFile() async {
    final hfpMessenger = ScaffoldMessenger.of(context);
    final hfpPadding = MediaQuery.of(context).padding.bottom;
    final hfpIsMobile = MediaQuery.of(context).size.width < 450;
    final hfpScreenWidth = MediaQuery.of(context).size.width;

    final results = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '代码/文本文件',
          extensions: [
            'dart',
            'py',
            'java',
            'kt',
            'js',
            'ts',
            'json',
            'xml',
            'html',
            'css',
            'yaml',
            'yml',
            'md',
            'txt',
            'sql',
            'sh',
            'bat',
            'gradle',
            'properties',
            'cfg',
            'ini',
            'log',
            'csv',
            'env',
            'c',
            'cpp',
            'h',
            'hpp',
            'go',
            'rs',
            'rb',
            'php',
            'swift',
            'ps1',
            'pl',
            'lua',
            'r',
            'scala',
            'groovy',
          ],
        ),
        XTypeGroup(
          label: '图片文件',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
        ),
      ],
    );

    if (results.isEmpty) return;

    int addedCount = 0;
    bool hasImage = false;
    const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'];

    for (final result in results) {
      final file = File(result.path);
      final name = result.name;
      if (!await file.exists()) continue;

      final ext = name.split('.').last.toLowerCase();

      if (imageExts.contains(ext)) {
        hasImage = true;
        try {
          final bytes = await file.readAsBytes();
          final b64 = base64Encode(bytes);
          unawaited(_autoOcrImage(name, b64));
          setState(() {
            _attachments.add(
              AttachmentInfo(type: 'image', name: name, data: b64),
            );
          });
          addedCount++;
        } catch (e) {
          debugPrint("读取图片失败($name): $e");
        }
      } else {
        try {
          final content = await file.readAsString();
          setState(() {
            _attachments.add(
              AttachmentInfo(type: 'code', name: name, data: content),
            );
          });
          addedCount++;
        } catch (e) {
          debugPrint("读取文件失败($name): $e");
        }
      }
    }

    if (mounted && addedCount > 0) {
      final msg = "已添加 $addedCount 个文件${hasImage ? '（图片正在OCR...）' : ''}";
      showTopSnackBarWithState(
        messenger: hfpMessenger,
        message: msg,
        bottomPadding: hfpPadding,
        isMobile: hfpIsMobile,
        screenWidth: hfpScreenWidth,
        bottomMargin: 142,
      );
    }
  }

  /// 后台自动 OCR 图片（优先 AI，失败回退本地 Tesseract）
  Future<void> _autoOcrImage(String name, String b64) async {
    // 预捕获 SnackBar 参数（避免 async 后使用 context）
    final ocrMessenger = ScaffoldMessenger.of(context);
    final ocrPadding = MediaQuery.of(context).padding.bottom;
    final ocrIsMobile = MediaQuery.of(context).size.width < 450;
    final ocrScreenWidth = MediaQuery.of(context).size.width;

    setState(() => _isOcrRunning = true);
    try {
      String ocrResult = '';

      // 优先 AI 识别
      bool aiSucceeded = false;
      if (widget.useDirectApi) {
        final baseUrl = widget.directBaseUrl;
        final apiKey = widget.directApiKey;
        final model = widget.directModel;
        if (baseUrl != null && apiKey != null && model != null) {
          final result = await _ocrWithAiVision(
            baseUrl: baseUrl,
            apiKey: apiKey,
            model: model,
            imageBase64: b64,
          );
          if (result.text.isNotEmpty && !result.text.startsWith("AI 识别失败")) {
            ocrResult = result.text;
            aiSucceeded = true;
          }
        }
      } else {
        try {
          final response = await widget.dio.post(
            "/api/ocr",
            data: {"image": b64, "enable_formula": true},
          );
          final data = response.data as Map<String, dynamic>;
          final text = data['text']?.toString() ?? '';
          if (text.isNotEmpty && !text.startsWith("[Tesseract")) {
            ocrResult = text;
            aiSucceeded = true;
          }
        } catch (_) {}
      }

      // AI 失败则回退本地 Tesseract
      if (!aiSucceeded && !widget.useDirectApi) {
        try {
          final response = await widget.dio.post(
            "/api/ocr",
            data: {"image": b64, "enable_formula": false},
          );
          final data = response.data as Map<String, dynamic>;
          ocrResult = data['text']?.toString() ?? '';
        } catch (_) {}
      }

      if (!mounted || ocrResult.isEmpty) return;

      // 更新对应附件的 OCR 结果
      setState(() {
        for (int i = 0; i < _attachments.length; i++) {
          if (_attachments[i].name == name && _attachments[i].type == 'image') {
            _attachments[i] = AttachmentInfo(
              type: 'image',
              name: name,
              data: _attachments[i].data,
              ocrText: ocrResult,
            );
            break;
          }
        }
      });
      if (mounted) {
        final label = aiSucceeded ? "AI" : "本地";
        showTopSnackBarWithState(
          messenger: ocrMessenger,
          message: "✅ $name OCR 完成（$label）",
          bottomPadding: ocrPadding,
          isMobile: ocrIsMobile,
          screenWidth: ocrScreenWidth,
          bottomMargin: 142,
        );
      }
    } catch (e) {
      debugPrint(">>> 自动OCR失败($name): $e");
    } finally {
      if (mounted) setState(() => _isOcrRunning = false);
    }
  }

  /// OCR 识别图片
  Future<void> _handleOcr() async {
    // 预捕获 SnackBar 参数（避免 async 后使用 context）
    final msgCenter = ScaffoldMessenger.of(context);
    final padBottom = MediaQuery.of(context).padding.bottom;
    final mobileMode = MediaQuery.of(context).size.width < 450;
    final screenWidth = MediaQuery.of(context).size.width;

    // 选择图片文件
    final result = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: '图片文件',
          extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
        ),
      ],
    );

    if (result == null) return;

    final file = File(result.path);
    final name = result.name;
    if (!await file.exists()) return;

    try {
      showTopSnackBarWithState(
        messenger: msgCenter,
        message: "正在使用本地 OCR 识别: $name ...",
        bottomPadding: padBottom,
        isMobile: mobileMode,
        screenWidth: screenWidth,
        bottomMargin: 142,
      );

      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      // 第一步：快速本地识别（Tesseract，不用 AI）
      final ocrText = await _ocrLocalFast(b64);
      if (!mounted) return;

      // 显示结果，传 b64 用于后续 AI 重新识别
      _showOcrResultDialog(fileName: name, text: ocrText, imageBase64: b64);
    } catch (e) {
      if (mounted) {
        showTopSnackBarWithState(
          messenger: msgCenter,
          message: "OCR 处理失败: $e",
          bottomPadding: padBottom,
          isMobile: mobileMode,
          screenWidth: screenWidth,
          bottomMargin: 142,
        );
      }
    }
  }

  /// 快速本地识别（仅 Tesseract）
  Future<String> _ocrLocalFast(String b64) async {
    if (widget.useDirectApi) {
      // 手机端直连：快速模式只能用 AI（跳过本地 Tesseract）
      final baseUrl = widget.directBaseUrl;
      final apiKey = widget.directApiKey;
      final model = widget.directModel;
      if (baseUrl != null && apiKey != null && model != null) {
        final result = await _ocrWithAiVision(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          imageBase64: b64,
        );
        return result.text;
      }
      return "AI 配置不完整";
    } else {
      // PC端：后端 Tesseract 本地识别（快速）
      try {
        final response = await widget.dio.post(
          "/api/ocr",
          data: {"image": b64, "enable_formula": false},
        );
        final data = response.data as Map<String, dynamic>;
        return data['text']?.toString() ?? '';
      } catch (e) {
        return "OCR 识别失败: $e";
      }
    }
  }

  /// 使用 AI 重新识别（公式精修）
  Future<String> _ocrWithAi(String b64) async {
    if (widget.useDirectApi) {
      final baseUrl = widget.directBaseUrl;
      final apiKey = widget.directApiKey;
      final model = widget.directModel;
      if (baseUrl != null && apiKey != null && model != null) {
        final result = await _ocrWithAiVision(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          imageBase64: b64,
        );
        return result.text;
      }
      return "AI 配置不完整";
    } else {
      try {
        final response = await widget.dio.post(
          "/api/ocr",
          data: {"image": b64, "enable_formula": true},
        );
        final data = response.data as Map<String, dynamic>;
        return data['text']?.toString() ?? '';
      } catch (e) {
        return "AI 识别失败: $e";
      }
    }
  }

  /// 使用 AI Vision API 进行 OCR 识别
  Future<({String text, String? formulaText})> _ocrWithAiVision({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String imageBase64,
  }) async {
    final apiMessages = [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text":
                "请识别这张图片中的所有文字。如果包含数学公式，请用 LaTeX 格式（\$...\$）内嵌在原位输出。直接输出完整文本，不要添加额外说明。",
          },
          {
            "type": "image_url",
            "image_url": {"url": "data:image/png;base64,$imageBase64"},
          },
        ],
      },
    ];

    final requestBody = {
      "model": model,
      "messages": apiMessages,
      "max_tokens": 4096,
      "temperature": 0.1,
    };

    try {
      final response = await Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {"Authorization": "Bearer $apiKey"},
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 120),
        ),
      ).post("/chat/completions", data: requestBody);

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      final content =
          choices?.firstOrNull?['message']?['content']?.toString() ?? '';

      // AI 直接返回完整文本（公式已用 LaTeX 内嵌在原位）
      return (text: content, formulaText: null);
    } catch (e) {
      return (text: "AI 识别失败: $e", formulaText: null);
    }
  }

  /// 显示 OCR 结果对话框
  void _showOcrResultDialog({
    required String fileName,
    required String text,
    required String imageBase64,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => _OcrResultDialog(
        fileName: fileName,
        initialText: text,
        imageBase64: imageBase64,
        controller: _controller,
        inputFocusNode: _inputFocusNode,
        onOcrWithAi: _ocrWithAi,
      ),
    );
  }

  void resetChat() {
    setState(() {
      _isMapQuery = false;
      _attachments.clear();
      _messages.clear();
      _messages.add({"text": "你好！我是你的AI助手，有什么我可以帮你的吗？", "isUser": false});
    });
  }

  void loadHistory(dynamic historyData) {
    List<dynamic> historyMessages = [];

    if (historyData is Map && historyData.containsKey('messages')) {
      historyMessages = historyData['messages'] as List<dynamic>;
    } else if (historyData is List) {
      historyMessages = historyData;
    }

    // 切回聊天标签
    _chatTabController.animateTo(0);

    setState(() {
      _isMapQuery = false;
      _messages.clear();
      for (var msg in historyMessages) {
        if (msg is Map) {
          bool isUser = msg['role'] == 'user';
          _messages.add({"text": msg['content'] ?? "", "isUser": isUser});
        }
      }
      // 加载历史对话时，不再插入欢迎语，完整还原历史
      if (_messages.isEmpty) {
        _messages.add({"text": "你好！我是你的AI助手，有什么我可以帮你的吗？", "isUser": false});
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom({bool force = false}) {
    // 用户已手动滚离底部且非强制滚动 → 暂停自动滚动
    if (_userScrolledAway && !force) return;

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // 检测是否涉及地图/位置相关查询
    final queryIsMapRelated = _isMapRelated(text);

    // 如果是第一条用户消息，生成摘要并更新 AppBar
    bool isFirstMessage = _messages.length <= 1; // 只有一条欢迎语或为空
    if (isFirstMessage && widget.onSummaryUpdate != null) {
      String summary = text.length > 20 ? "${text.substring(0, 20)}..." : text;
      widget.onSummaryUpdate!(summary);
    }

    // 构建附件文本（如果有附件，拼接到用户消息中）
    String attachmentText = '';
    if (_attachments.isNotEmpty) {
      final attachmentParts = <String>[];
      for (final att in _attachments) {
        if (att.type == 'code') {
          attachmentParts.add(
            '\n--- 文件附件: ${att.name} ---\n```\n${att.data}\n```\n--- 附件结束 ---',
          );
        } else if (att.type == 'image') {
          if (att.ocrText != null && att.ocrText!.isNotEmpty) {
            // 有OCR结果：直接使用识别文本
            attachmentParts.add(
              '\n--- 图片附件: ${att.name}（OCR识别结果）---\n${att.ocrText}\n--- 附件结束 ---',
            );
          } else {
            // 无OCR结果（正在识别或失败）：提示用户
            attachmentParts.add('\n--- 图片附件: ${att.name}（正在OCR识别中，请稍后重发）---\n');
          }
        }
      }
      attachmentText = '\n\n【用户上传的附件】\n${attachmentParts.join('\n')}';
    }

    final fullText = text + attachmentText;

    setState(() {
      _isMapQuery = queryIsMapRelated;
      _messages.add({"text": fullText, "isUser": true});
      _attachments.clear();
    });
    _controller.clear();
    _scrollToBottom();

    // 添加一个空的 AI 回复占位
    setState(() {
      _messages.add({"text": "", "isUser": false});
    });
    int aiMsgIndex = _messages.length - 1;

    try {
      // 🌍 获取当前城市定位信息（GPS优先→IP定位→默认值）
      String cityInfoStr = '未知位置,000000';
      String? gpsHint;
      try {
        cityInfoStr = await LocationService.getCityInfoForAi();
        gpsHint = LocationService.gpsCoordsHint;
        debugPrint(">>> 定位城市信息: $cityInfoStr, GPS坐标: ${gpsHint ?? '无'}");
      } catch (e) {
        debugPrint(">>> 获取定位失败（不影响AI回复）: $e");
      }
      final parts = cityInfoStr.split(',');
      final cityName = parts.isNotEmpty ? parts[0] : '未知位置';
      final cityAdcode = parts.length > 1 ? parts[1] : '000000';

      // 构建历史上下文发送给后端
      List<Map<String, String>> historyToSend = [];
      for (int i = 0; i < _messages.length - 1; i++) {
        final msg = _messages[i];
        historyToSend.add({
          "role": msg["isUser"] ? "user" : "assistant",
          "content": msg["text"] as String,
        });
      }

      if (widget.useDirectApi) {
        // 📱 手机端直连 AI API
        debugPrint(">>> 手机端直连 AI API");
        final baseUrl = widget.directBaseUrl;
        final apiKey = widget.directApiKey;
        final model = widget.directModel;

        if (baseUrl == null || apiKey == null || model == null) {
          setState(() {
            _messages[aiMsgIndex]["text"] = "AI 配置不完整，请先在设置中配置 AI 服务。";
          });
          return;
        }

        // 构建消息列表（含系统提示和定位信息）
        final now = DateTime.now();
        final dateStr = "${now.year}年${now.month}月${now.day}日";
        final timeStr =
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
        final locationLine = gpsHint != null && cityName == '未知位置'
            ? "【用户位置】GPS坐标: $gpsHint（城市名解析失败）"
            : "【用户当前城市】$cityName（城市编码：$cityAdcode）";
        final apiMessages = [
          {
            "role": "system",
            "content":
                "你是一个智能学习助手'星火学伴'。请用自然、友好的中文回答用户的问题。"
                "当前日期：$dateStr，当前时间：$timeStr。"
                "当回答涉及成绩、天气等数据时，要用通俗的语言描述，不要返回原始数据格式。"
                "\n\n$locationLine"
                "当用户询问天气、路况等需要位置信息的问题时，请使用上述信息。",
          },
          ...historyToSend,
        ];

        // 检查是否启用了联网搜索
        final config = await loadConfigFile();
        final wsc = getWebSearchConfig(config);
        final enableWebSearch = wsc.enabled && isDashScopeUrl(baseUrl);

        final stream = directStreamChat(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: apiMessages,
          enableSearch: enableWebSearch,
          onReasoning: (reasoning) {
            if (!mounted) return;
            setState(() {
              final existing =
                  _messages[aiMsgIndex]["reasoning"] as String? ?? '';
              _messages[aiMsgIndex]["reasoning"] = existing + reasoning;
            });
            _scrollToBottom();
          },
        );

        await for (final chunk in stream) {
          if (!mounted) break;
          setState(() {
            _messages[aiMsgIndex]["text"] =
                (_messages[aiMsgIndex]["text"] as String) + chunk;
          });
          _scrollToBottom();
        }

        // 📱 手机端：将对话保存到本地 backlog 文件
        if (!mounted) return;
        final backlogMessages = <BacklogMessage>[];
        for (final msg in _messages) {
          final role = msg["isUser"] == true ? "user" : "assistant";
          final content = msg["text"] as String;
          if (content.isNotEmpty) {
            backlogMessages.add(BacklogMessage(role: role, content: content));
          }
        }
        final firstUserMsg =
            backlogMessages
                .where((m) => m.role == 'user')
                .firstOrNull
                ?.content ??
            '';
        final summary = firstUserMsg.length > 20
            ? '${firstUserMsg.substring(0, 20)}...'
            : firstUserMsg;
        await saveBacklog(messages: backlogMessages, summary: summary);
        // 通知历史页面刷新
        _historyRefreshNotifier.value++;

        // 手机端：从 AI 回复中自动发现并提取学习关键词
        final aiReply = _messages[aiMsgIndex]["text"] as String? ?? '';
        final userMsg = text;
        if (aiReply.isNotEmpty) {
          if (widget.directBaseUrl != null &&
              widget.directApiKey != null &&
              widget.directModel != null) {
            // 有 AI 配置 → 用 AI 分析对话提取关键词（更精准）
            unawaited(
              StudyAnalysisService.discoverKeywordsFromChatWithAI(
                baseUrl: widget.directBaseUrl!,
                apiKey: widget.directApiKey!,
                model: widget.directModel!,
                userMessage: userMsg,
                aiResponse: aiReply,
              ),
            );
          } else {
            // 无 AI 配置 → 回退本地规则匹配
            unawaited(
              StudyAnalysisService.discoverKeywordsLocally(aiResponse: aiReply),
            );
          }
        }
      } else {
        // 💻 PC 模式：通过本地后端（附带定位信息），解析 SSE JSON 格式
        debugPrint("正在请求: ${widget.dio.options.baseUrl}/chat");

        // 在历史消息开头插入一条定位 system 消息，让后端 AI 知道用户所在城市
        final locationLine = gpsHint != null && cityName == '未知位置'
            ? "用户当前GPS坐标: $gpsHint（城市名解析失败）"
            : "用户当前所在城市：$cityName（城市编码：$cityAdcode）";
        final historyWithLocation = [
          {"role": "system", "content": locationLine},
          ...historyToSend,
        ];

        final response = await widget.dio.post(
          "/chat",
          data: {"prompt": text, "history": historyWithLocation},
          options: Options(responseType: ResponseType.stream),
        );

        final rawStream = response.data.stream as Stream<Uint8List>;
        String buffer = '';

        await for (final raw in rawStream) {
          if (!mounted) break;
          buffer += utf8.decode(raw, allowMalformed: true);

          // 解析 SSE 事件行：data: {...}\n\n
          while (true) {
            final idx = buffer.indexOf('\n');
            if (idx < 0) break;
            final line = buffer.substring(0, idx).trim();
            buffer = buffer.substring(idx + 1);

            if (line.isEmpty) continue;
            if (line == 'data: [DONE]') break;
            if (line.startsWith('data: ')) {
              try {
                final jsonStr = line.substring(6);
                final json = jsonDecode(jsonStr) as Map<String, dynamic>;

                // 普通内容块：{"c": "文本"}
                if (json.containsKey('c')) {
                  final chunk = json['c'] as String? ?? '';
                  if (chunk.isNotEmpty) {
                    setState(() {
                      _messages[aiMsgIndex]["text"] =
                          (_messages[aiMsgIndex]["text"] as String) + chunk;
                    });
                    _scrollToBottom();
                  }
                }

                // 思考过程块：{"r": "思考文本"}
                if (json.containsKey('r')) {
                  final reasoning = json['r'] as String? ?? '';
                  if (reasoning.isNotEmpty) {
                    setState(() {
                      final existing =
                          _messages[aiMsgIndex]["reasoning"] as String? ?? '';
                      _messages[aiMsgIndex]["reasoning"] = existing + reasoning;
                    });
                    _scrollToBottom();
                  }
                }
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages[aiMsgIndex]["text"] = "AI响应失败，请稍后重试。($e)";
      });
      _scrollToBottom();
    }
  }

  /// 是否显示"滚动到底部"按钮
  bool _showScrollToBottom = false;

  /// 用户是否已手动滚离底部（生成中暂停自动滚动）
  bool _userScrolledAway = false;

  /// AI聊天内部 Tab 控制器（0=聊天, 1=历史）
  late final TabController _chatTabController;

  /// 记录上次通知父级的tab索引，避免动画过半时重复通知
  int _lastNotifiedChatTab = 0;

  /// 历史页面刷新触发器（值变化时通知 HistoryPage 重新加载）
  final ValueNotifier<int> _historyRefreshNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _chatTabController = TabController(length: 2, vsync: this);
    _chatTabController.addListener(_onChatTabChanged);
    // 监听滚动位置，控制"返回底部"按钮的显隐
    _scrollController.addListener(_onScrollChanged);
    // PC端自动聚焦输入框，手机端不聚焦
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocusNode.requestFocus();
      });
    }
  }

  /// Tab切换时通知父级更新AppBar
  /// - 聊天→历史：动画一开始就更新
  /// - 历史→聊天：动画完全结束后才更新
  void _onChatTabChanged() {
    if (!_chatTabController.indexIsChanging) {
      // 动画结束 → 无论方向都更新
      if (_lastNotifiedChatTab != _chatTabController.index) {
        _lastNotifiedChatTab = _chatTabController.index;
        widget.onChatTabChanged?.call(_chatTabController.index);
      }
      // 切换到历史标签时自动刷新（确保看到最新记录）
      if (_chatTabController.index == 1) {
        _historyRefreshNotifier.value++;
      }
    } else {
      // 动画进行中 → 仅聊天→历史方向(0→1)时提前更新
      final targetIndex = _chatTabController.index;
      final fromIndex = _chatTabController.previousIndex;
      if (fromIndex == 0 &&
          targetIndex == 1 &&
          targetIndex != _lastNotifiedChatTab) {
        _lastNotifiedChatTab = targetIndex;
        widget.onChatTabChanged?.call(targetIndex);
        // 聊天→历史方向：提前刷新
        _historyRefreshNotifier.value++;
      }
    }
  }

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final awayFromBottom = maxScroll - currentScroll > 100;

    // 更新"返回底部"按钮显隐
    if (awayFromBottom != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = awayFromBottom;
      });
    }

    // 用户手动滚离底部时标记暂停自动滚动（仅在生成中有效）
    if (awayFromBottom && !_userScrolledAway) {
      setState(() {
        _userScrolledAway = true;
      });
    }

    // 用户手动滚回底部时恢复自动滚动
    if (!awayFromBottom && _userScrolledAway) {
      setState(() {
        _userScrolledAway = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    final isMobilePlatform = Platform.isAndroid || Platform.isIOS;
    final shouldHideBottomBar = isKeyboardVisible && isMobilePlatform;

    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: _chatTabController,
            children: [
              // 页面0：聊天消息列表 + 输入框
              Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 16,
                            bottom: 8,
                          ),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isUser = msg["isUser"] as bool;
                            final isLastAiMsg =
                                !isUser && index == _messages.length - 1;
                            final reasoning = msg["reasoning"] as String?;
                            return Align(
                              key: ValueKey(index),
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  top: 10,
                                  bottom: 6,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.88,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? (isDark
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer
                                            : Theme.of(context).primaryColor)
                                      : (isDark
                                            ? const Color(0xFF2A2A2A)
                                            : Colors.grey.shade200),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(
                                      isUser ? 16 : 0,
                                    ),
                                    bottomRight: Radius.circular(
                                      isUser ? 0 : 16,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 可折叠的思考过程（仅 AI 回复且含 reasoning 时显示）
                                    if (!isUser &&
                                        reasoning != null &&
                                        reasoning.isNotEmpty)
                                      _ThinkingSection(
                                        reasoning: reasoning,
                                        autoCollapse:
                                            (msg["text"] as String).isNotEmpty,
                                      ),
                                    // 回复文本
                                    TextSelectionTheme(
                                      data: TextSelectionThemeData(
                                        selectionColor: isDark
                                            ? Colors.blue.withAlpha(100)
                                            : Colors.orange.withAlpha(80),
                                      ),
                                      child: _MathAwareText(
                                        text: msg["text"],
                                        isUser: isUser,
                                        isDark: isDark,
                                      ),
                                    ),
                                    if (isLastAiMsg && _isMapQuery)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: _openAmap,
                                            icon: const Icon(
                                              Icons.map,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              "在地图中查看",
                                              style: TextStyle(fontSize: 13),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFFFF6A00,
                                              ),
                                              side: const BorderSide(
                                                color: Color(0xFFFF6A00),
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              minimumSize: const Size(0, 32),
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        // "返回底部"浮动按钮（横向与发送按钮对齐）
                        if (_showScrollToBottom)
                          Positioned(
                            right: 16,
                            bottom: 6,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  _userScrolledAway = false;
                                  _scrollToBottom(force: true);
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  width: 44,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.indigo.shade400
                                        : Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.2,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.arrow_downward,
                                    color: isDark
                                        ? Colors.black87
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onPrimaryContainer,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          offset: const Offset(0, -1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 附件预览列表（图片显示缩略图，非图片显示文件名）
                        if (_attachments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SizedBox(
                              height: 56,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _attachments.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final att = _attachments[index];
                                  return _AttachmentPreview(
                                    attachment: att,
                                    onDelete: () {
                                      setState(() {
                                        _attachments.removeAt(index);
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            // 左侧竖排按钮（类似 Gemini 风格）- 已放大
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // OCR 按钮
                                IconButton(
                                  icon: const Icon(Icons.photo_outlined),
                                  tooltip: 'OCR 识别图片',
                                  onPressed: _handleOcr,
                                  constraints: const BoxConstraints(
                                    minWidth: 44, // 从 36 放大到 44
                                    minHeight: 44,
                                  ),
                                  padding: EdgeInsets.zero,
                                  iconSize: 32, // 从 26 放大到 32
                                ),
                                // 附件按钮（带数量标记）
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.attach_file),
                                      tooltip: '添加文件',
                                      onPressed: _handlePickFile,
                                      constraints: const BoxConstraints(
                                        minWidth: 44, // 从 36 放大到 44
                                        minHeight: 44,
                                      ),
                                      padding: EdgeInsets.zero,
                                      iconSize: 32, // 从 26 放大到 32
                                    ),
                                    // 附件数量标记
                                    if (_attachments.isNotEmpty)
                                      Positioned(
                                        top: 2, // 微调位置，适应更大的按钮
                                        right: 2, // 微调位置
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            shape: BoxShape.circle,
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 16,
                                            minHeight: 16,
                                          ),
                                          child: Text(
                                            '${_attachments.length}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Focus(
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent &&
                                      event.logicalKey ==
                                          LogicalKeyboardKey.enter &&
                                      !HardwareKeyboard
                                          .instance
                                          .isShiftPressed) {
                                    _handleSend();
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: TextField(
                                  controller: _controller,
                                  focusNode: _inputFocusNode,
                                  enabled: !_isOcrRunning,
                                  minLines: 2,
                                  maxLines: 5,
                                  textInputAction: TextInputAction.newline,
                                  decoration: InputDecoration(
                                    hintText: "给AI发送消息...",
                                    filled: true,
                                    fillColor:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : Colors.grey.shade100,
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color:
                                            Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white.withValues(
                                                alpha: 0.15,
                                              )
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Theme.of(context).primaryColor,
                                        width: 1.5,
                                      ),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // 发送按钮 - 已改小
                            IconButton(
                              icon: Icon(
                                Icons.send,
                                color: _isOcrRunning
                                    ? (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white38
                                          : Colors.grey.shade400)
                                    : (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Colors.white
                                          : Theme.of(context).primaryColor),
                              ),
                              iconSize: 22, // 从 26 缩小到 22
                              // 移除了 constraints 限制，使其回归较小的自然尺寸
                              padding: const EdgeInsets.all(
                                8,
                              ), // 适当保留一些点击内边距，方便点击
                              onPressed: _isOcrRunning ? null : _handleSend,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 页面1：聊天历史（内嵌，用 KeepAlive 包裹）
              _KeepAliveWrapper(
                child: HistoryPage(
                  dio: widget.dio,
                  refreshNotifier: _historyRefreshNotifier,
                  onContinue: (messages, summary) {
                    _chatTabController.animateTo(0);
                    loadHistory(messages);
                  },
                ),
              ),
            ],
          ),
        ),
        // 底部导航栏（TabBar 样式）："聊天" | "历史"
        // 移动端输入法弹出时隐藏，避免被键盘遮挡
        Offstage(
          offstage: shouldHideBottomBar,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
            ),
            child: TabBar(
              controller: _chatTabController,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: isDark
                  ? Colors.white
                  : Theme.of(context).primaryColor,
              unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey,
              indicatorWeight: 3,
              tabs: const [
                Tab(icon: Icon(Icons.chat_bubble_outline), text: "聊天"),
                Tab(icon: Icon(Icons.history), text: "历史"),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _chatTabController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }
}

class ScorePage extends StatefulWidget {
  final Dio dio;
  const ScorePage({super.key, required this.dio});

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController idController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController _batchTagCtrl = TextEditingController();
  final List<Map<String, TextEditingController>> _scoreItems = [];
  late final TabController _tabController;

  int _selectedFuncIndex = 0; // ignore: unused_field
  // 查询复选框状态（查询和删除共用）
  bool _searchById = true;
  bool _searchByName = false;
  // 查询结果（直接展示在搜索按钮下方，不弹窗）
  List<StudentData> _queryResults = [];
  bool _isQuerying = false;
  bool _hasQueried = false;
  String? _queryFilterTag; // 查询结果标签筛选
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedFuncIndex = _tabController.index;
        });
      }
    });
    // 默认弹出一组空白添加项
    _addScoreItem();
  }

  void _addScoreItem() {
    setState(() {
      _scoreItems.add({
        "subject": TextEditingController(),
        "score": TextEditingController(),
        "fullMark": TextEditingController(),
      });
    });
  }

  void _removeScoreItem(int index) {
    setState(() {
      _scoreItems[index]["subject"]!.dispose();
      _scoreItems[index]["score"]!.dispose();
      _scoreItems[index]["fullMark"]!.dispose();
      _scoreItems.removeAt(index);
    });
  }

  /// 构建单个学生结果卡片（供查询和删除共用）
  Widget _buildResultCard(StudentData student, {bool showDelete = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).colorScheme.primary;
    final scores = student.scores;
    final scoreEntries = scores.entries.toList();
    final borderColor = themeColor.withValues(alpha: isDark ? 0.35 : 0.25);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 学生信息头
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: themeColor,
                  child: Text(
                    student.name.isNotEmpty ? student.name[0] : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        "学号: ${student.studentId}",
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                // 查看详情（showDelete 时也在删除页显示详情入口）
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ScoreResultPage(
                          userName: student.name,
                          studentId: student.studentId,
                          scores: student.scores,
                          examRecords: student.examRecords,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "详情",
                        style: TextStyle(
                          fontSize: 13,
                          color: themeColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right, size: 18, color: themeColor),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 标签筛选行
            Builder(
              builder: (ctx) {
                // 从 examRecords 收集所有标签
                final allTags = student.examRecords
                    .map((r) => r.label)
                    .where((l) => l != null && l.isNotEmpty)
                    .toSet()
                    .toList();
                if (allTags.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      ChoiceChip(
                        label: const Text("所有", style: TextStyle(fontSize: 12)),
                        selected: _queryFilterTag == null,
                        onSelected: (_) =>
                            setState(() => _queryFilterTag = null),
                      ),
                      ...allTags.map((tag) {
                        final isSelected = _queryFilterTag == tag;
                        return ChoiceChip(
                          label: Text(
                            tag!,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: isSelected,
                          onSelected: (_) => setState(
                            () => _queryFilterTag = isSelected ? null : tag,
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
            // 科目成绩摘要
            Text(
              _queryFilterTag != null
                  ? "科目成绩（标签: $_queryFilterTag）"
                  : "科目成绩（共 ${scores.length} 门）",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            if (scoreEntries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  "暂无科目成绩",
                  style: TextStyle(
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              ..._buildFilteredScoreEntries(
                scoreEntries,
                student,
                isDark,
                themeColor,
                showDelete,
              ),
            if (scoreEntries.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "... 还有 ${scoreEntries.length - 5} 门科目",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (showDelete) ...[
              // 检测缺少标签的科目
              Builder(
                builder: (ctx) {
                  final untagged = scoreEntries.where((e) {
                    final v = e.value;
                    return v is! Map ||
                        v['tag'] == null ||
                        v['tag'].toString().isEmpty;
                  }).toList();
                  if (untagged.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.label_outline,
                            size: 16,
                            color: Colors.orange.shade400,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "${untagged.length} 个科目缺少标签，将使用默认标签",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _autoTagAll(
                              student,
                              untagged.map((e) => e.key).toList(),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              "一键补全",
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever, size: 18),
                  onPressed: () => _deleteStudentData(student),
                  label: const Text(
                    '删除此学生的所有信息',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                    side: BorderSide(color: Colors.red.shade300),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建按标签筛选的成绩项列表
  List<Widget> _buildFilteredScoreEntries(
    List<MapEntry<String, dynamic>> scoreEntries,
    StudentData student,
    bool isDark,
    Color themeColor,
    bool showDelete,
  ) {
    final entriesToShow = <MapEntry<String, dynamic>>[];

    if (_queryFilterTag != null) {
      final taggedRecords =
          student.examRecords.where((r) => r.label == _queryFilterTag).toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      if (taggedRecords.isNotEmpty) {
        final latest = taggedRecords.first;
        for (final subject in scoreEntries.map((e) => e.key)) {
          if (latest.scores.containsKey(subject)) {
            entriesToShow.add(MapEntry(subject, latest.scores[subject]!));
          }
        }
      }
      if (entriesToShow.isEmpty) entriesToShow.addAll(scoreEntries);
    } else {
      entriesToShow.addAll(scoreEntries);
    }

    if (entriesToShow.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            "该标签下暂无成绩",
            style: TextStyle(
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ];
    }

    return entriesToShow.take(5).map((entry) {
      final subject = entry.key;
      final score = entry.value;
      String displayScore;
      if (score is Map) {
        final s = score['score'] ?? 0;
        final fm = score['fullMark'];
        displayScore = fm != null ? "$s/$fm" : "$s";
      } else {
        displayScore = "$score";
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(Icons.auto_stories, size: 16, color: themeColor),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(subject, style: const TextStyle(fontSize: 14)),
                  if (score is Map &&
                      score['tag'] != null &&
                      score['tag'].toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: themeColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          score['tag'].toString(),
                          style: TextStyle(fontSize: 10, color: themeColor),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showDelete) ...[
              if (score is! Map ||
                  score['tag'] == null ||
                  score['tag'].toString().isEmpty)
                IconButton(
                  icon: Icon(
                    Icons.label_outline,
                    size: 16,
                    color: Colors.orange.shade400,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  tooltip: "为「$subject」添加标签",
                  onPressed: () => _showAddTagDialog(student, subject),
                ),
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Colors.blue.shade300,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: "修改「$subject」成绩",
                onPressed: () => _showEditScoreDialog(student, subject),
              ),
              IconButton(
                icon: Icon(
                  Icons.remove_circle_outline,
                  size: 16,
                  color: Colors.red.shade400,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: "删除「$subject」成绩",
                onPressed: () => _deleteSubjectScoreFrom(subject, student),
              ),
            ] else ...[
              const Spacer(),
            ],
            Text(
              displayScore,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: themeColor,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  /// 弹出添加标签对话框
  Future<void> _showAddTagDialog(StudentData student, String subject) async {
    final tagCtrl = TextEditingController();
    // 从 ExamRecord 中提取已有标签供快速选择
    final existingTags = student.examRecords
        .map((r) => r.label)
        .where((l) => l != null && l.isNotEmpty)
        .toSet()
        .toList();

    String? selectedTag;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("为「$subject」添加标签"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tagCtrl,
                decoration: const InputDecoration(
                  labelText: '自定义标签',
                  hintText: '例如：期中考试、月考、模拟考',
                  border: OutlineInputBorder(),
                ),
              ),
              if (existingTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  "已有标签：",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: existingTags.map((tag) {
                    final isSelected = selectedTag == tag;
                    return ChoiceChip(
                      label: Text(tag!, style: const TextStyle(fontSize: 12)),
                      selected: isSelected,
                      onSelected: (_) {
                        setDialogState(() {
                          selectedTag = tag;
                          tagCtrl.text = tag;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, true);
              },
              child: const Text("确认"),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      final tag = tagCtrl.text.trim();
      await _updateScoreTag(student, subject, tag.isNotEmpty ? tag : '日常');
    }
    tagCtrl.dispose();
  }

  /// 一键补全所有缺少标签的科目（弹出对话框让用户输入标签名）
  Future<void> _autoTagAll(StudentData student, List<String> subjects) async {
    final tagCtrl = TextEditingController();
    // 从已有记录提取标签供选择
    final existingTags = student.examRecords
        .map((r) => r.label)
        .where((l) => l != null && l.isNotEmpty)
        .toSet()
        .toList();

    String? selectedTag;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text("为 ${subjects.length} 个科目补全标签"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: tagCtrl,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  hintText: '例如：期中考试、月考、模拟考',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              if (existingTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  "或选择已有标签：",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: existingTags.map((tag) {
                    final isSel = selectedTag == tag;
                    return ChoiceChip(
                      label: Text(tag!, style: const TextStyle(fontSize: 12)),
                      selected: isSel,
                      onSelected: (_) {
                        setDialogState(() {
                          selectedTag = tag;
                          tagCtrl.text = tag;
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("取消"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("确认补全"),
            ),
          ],
        ),
      ),
    );

    tagCtrl.dispose();

    if (result != true || !mounted) return;

    final tag = tagCtrl.text.trim();
    final effectiveTag = tag.isNotEmpty ? tag : '日常';
    for (final subject in subjects) {
      await _updateScoreTag(student, subject, effectiveTag);
    }
    if (mounted) {
      showTopSnackBar(
        context,
        "已为 ${subjects.length} 个科目补全标签「$effectiveTag」",
        bottomMargin: 82,
      );
      queryData();
    }
  }

  /// 更新单科成绩的标签
  Future<void> _updateScoreTag(
    StudentData student,
    String subject,
    String tag,
  ) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await LocalScoreService.updateSubjectTag(
          studentId: student.studentId,
          subject: subject,
          tag: tag,
        );
        if (mounted) {
          showTopSnackBar(context, "已更新「$subject」标签：$tag", bottomMargin: 82);
          queryData();
        }
      } else {
        await widget.dio.post(
          "/update/tag",
          data: {"id": student.studentId, "subject": subject, "tag": tag},
        );
        if (mounted) {
          showTopSnackBar(context, "已更新「$subject」标签：$tag", bottomMargin: 82);
          queryData();
        }
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, "更新标签失败: $e", bottomMargin: 82);
      }
    }
  }

  /// 弹出修改成绩对话框
  Future<void> _showEditScoreDialog(StudentData student, String subject) async {
    final scoreCtrl = TextEditingController();
    final fullMarkCtrl = TextEditingController();
    final tagCtrl = TextEditingController();
    final existingScore = student.scores[subject];
    if (existingScore is Map) {
      scoreCtrl.text = (existingScore['score'] ?? '').toString();
      fullMarkCtrl.text = (existingScore['fullMark'] ?? '').toString();
      tagCtrl.text = (existingScore['tag'] ?? '').toString();
    } else {
      scoreCtrl.text = existingScore?.toString() ?? '';
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("修改「$subject」成绩"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: scoreCtrl,
                decoration: const InputDecoration(
                  labelText: '分数',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: fullMarkCtrl,
                decoration: const InputDecoration(
                  labelText: '满分（留空默认100）',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagCtrl,
                decoration: const InputDecoration(
                  labelText: '标签',
                  hintText: '例如：期中考试、月考',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("保存"),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final newScore = scoreCtrl.text.trim();
      final newFullMark = fullMarkCtrl.text.trim();
      final newTag = tagCtrl.text.trim();
      if (newScore.isEmpty) return;

      Map<String, dynamic> scoreValue;
      if (newFullMark.isNotEmpty) {
        scoreValue = {
          'score': num.tryParse(newScore) ?? 0,
          'fullMark': num.tryParse(newFullMark) ?? 100,
        };
      } else {
        scoreValue = {'score': num.tryParse(newScore) ?? 0};
      }
      if (newTag.isNotEmpty) {
        scoreValue['tag'] = newTag;
      }

      try {
        if (Platform.isAndroid || Platform.isIOS) {
          await LocalScoreService.addScore(
            studentId: student.studentId,
            name: student.name,
            scores: {subject: scoreValue},
          );
        } else {
          await widget.dio.post(
            "/add",
            data: {
              "id": student.studentId,
              "name": student.name,
              "scores": [
                {subject: scoreValue},
              ],
              if (newTag.isNotEmpty) "label": newTag,
            },
          );
        }
        if (mounted) {
          showTopSnackBar(context, "已更新「$subject」成绩", bottomMargin: 82);
          queryData();
        }
      } catch (e) {
        if (mounted) {
          showTopSnackBar(context, "更新失败: $e", bottomMargin: 82);
        }
      }
    }
    scoreCtrl.dispose();
    fullMarkCtrl.dispose();
    tagCtrl.dispose();
  }

  Future<void> queryData() async {
    setState(() {
      _isQuerying = true;
      _hasQueried = true;
      _queryResults = [];
    });
    try {
      // 检查：两项都未勾选
      if (!_searchById && !_searchByName) {
        throw "请至少勾选一种查找方式";
      }

      // 仅获取已勾选项的输入内容
      final rawId = _searchById ? idController.text.trim() : '';
      final rawName = _searchByName ? nameController.text.trim() : '';
      final hasId = _searchById && rawId.isNotEmpty;
      final hasName = _searchByName && rawName.isNotEmpty;

      // 检查：勾选了但没输入
      if (_searchById && !hasId) {
        throw "请输入学号";
      }
      if (_searchByName && !hasName) {
        throw "请输入姓名";
      }

      if (Platform.isAndroid || Platform.isIOS) {
        // 📱 Android：本地文件查询
        if (_searchById && _searchByName) {
          // 严格模式：按 ID 查所有匹配，再筛选姓名
          final matches = await LocalScoreService.queryStudentsById(rawId);
          if (!mounted) return;
          final filtered = matches
              .where((s) => s.name.contains(rawName))
              .toList();
          if (filtered.isEmpty) {
            throw "未找到学号「$rawId」且姓名包含「$rawName」的学生";
          }
          setState(() => _queryResults = filtered);
        } else if (_searchById) {
          final matches = await LocalScoreService.queryStudentsById(rawId);
          if (!mounted) return;
          if (matches.isEmpty) {
            throw "未找到学号为「$rawId」的学生";
          }
          setState(() => _queryResults = matches);
        } else {
          final matches = await LocalScoreService.queryStudentsByName(rawName);
          if (!mounted) return;
          if (matches.isEmpty) {
            throw "未找到姓名包含「$rawName」的学生";
          }
          setState(() => _queryResults = matches);
        }
      } else {
        // 💻 PC：后端查询（仅传已勾选的参数）
        final params = <String, dynamic>{};
        if (hasId) params['id'] = rawId;
        if (hasName) params['name'] = rawName;
        final response = await widget.dio.get(
          '/query',
          queryParameters: params,
        );
        if (!mounted) return;
        if (response.data is Map && response.data['error'] == null) {
          List<StudentData> students;
          if (response.data['students'] is List) {
            final list = response.data['students'] as List;
            if (list.isEmpty) throw '未找到该学生';
            students = list
                .map((e) => StudentData.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            // 单条结果（兼容旧格式）
            students = [
              StudentData(
                studentId: hasId ? rawId : '',
                name: response.data['name']?.toString() ?? '未知',
                scores: Map<String, dynamic>.from(
                  response.data['scores'] ?? {},
                ),
              ),
            ];
          }
          setState(() => _queryResults = students);
        } else {
          throw response.data['error']?.toString() ?? '未找到该学生';
        }
      }
    } catch (e) {
      String errorMsg = "查询失败";
      if (e is DioException) {
        if (e.response?.statusCode == 404) {
          errorMsg = "未找到该学生的信息";
        } else {
          errorMsg = "服务器错误: ${e.response?.statusCode ?? e.message}";
        }
      } else {
        errorMsg = e.toString();
      }
      if (mounted) {
        showTopSnackBar(context, errorMsg, bottomMargin: 82);
      }
    } finally {
      if (mounted) {
        setState(() => _isQuerying = false);
        _defaultQueryFilterTag();
      }
    }
  }

  /// 将查询结果标签筛选默认设为最新标签
  void _defaultQueryFilterTag() {
    if (_queryResults.isEmpty) return;
    final first = _queryResults.first;
    final records = first.examRecords.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final latestTag = records
        .map((r) => r.label)
        .firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null);
    if (latestTag != null && _queryFilterTag != latestTag) {
      setState(() => _queryFilterTag = latestTag);
    }
  }

  Future<void> _submitAddData() async {
    try {
      final List<Map<String, dynamic>> scoreList = [];
      final batchTag = _batchTagCtrl.text.trim();
      for (var item in _scoreItems) {
        final subject = item["subject"]!.text.trim();
        final scoreRaw = item["score"]!.text.trim();
        final fullMarkRaw = item["fullMark"]!.text.trim();
        if (subject.isNotEmpty && scoreRaw.isNotEmpty) {
          // 将分数转为数值
          final scoreNum = num.tryParse(scoreRaw) ?? scoreRaw;
          final hasFullMark = fullMarkRaw.isNotEmpty;
          final fullMarkNum = hasFullMark ? num.tryParse(fullMarkRaw) : null;
          // 构建分数值（含可选的批次标签）
          Map<String, dynamic> scoreValue;
          if (hasFullMark && fullMarkNum != null) {
            scoreValue = {'score': scoreNum, 'fullMark': fullMarkNum};
          } else {
            scoreValue = {'score': scoreNum};
          }
          if (batchTag.isNotEmpty) {
            scoreValue['tag'] = batchTag;
          }
          scoreList.add({subject: scoreValue});
        }
      }

      if (idController.text.isEmpty || nameController.text.isEmpty) {
        throw "学生ID和姓名不能为空";
      }
      if (scoreList.isEmpty) {
        throw "请至少添加一条成绩";
      }

      // 合并 scores（Android 本地用）
      final scoresMap = <String, dynamic>{};
      for (final entry in scoreList) {
        scoresMap.addAll(entry);
      }

      if (Platform.isAndroid || Platform.isIOS) {
        // 📱 Android：本地文件添加（支持自定义满分）
        await LocalScoreService.addScore(
          studentId: idController.text,
          name: nameController.text,
          scores: scoresMap,
        );
      } else {
        // 💻 PC：后端添加（支持标签和对象格式）
        final pcScoreList = <Map<String, dynamic>>[];
        for (final entry in scoresMap.entries) {
          final v = entry.value;
          if (v is Map) {
            // 保留完整格式（score, fullMark, tag）
            pcScoreList.add({entry.key: v});
          } else if (v is num) {
            pcScoreList.add({entry.key: v.toDouble()});
          } else {
            final parsed = double.tryParse(v.toString());
            pcScoreList.add({entry.key: parsed ?? 0.0});
          }
        }
        final response = await widget.dio.post(
          "/add",
          data: {
            "id": idController.text,
            "name": nameController.text,
            "scores": pcScoreList,
            if (batchTag.isNotEmpty) "label": batchTag,
          },
        );
        // 检查服务端返回是否有错误
        if (response.data is Map &&
            (response.data as Map).containsKey('error')) {
          throw (response.data as Map)['error']?.toString() ?? "服务器返回错误";
        }
      }

      if (!mounted) return;
      showTopSnackBar(context, "信息已成功添加到系统", bottomMargin: 82);

      idController.clear();
      nameController.clear();
      _batchTagCtrl.clear();
      setState(() {
        for (var item in _scoreItems) {
          item["subject"]!.dispose();
          item["score"]!.dispose();
          item["fullMark"]!.dispose();
        }
        _scoreItems.clear();
      });
    } catch (e) {
      if (!mounted) return;
      String errorMsg;
      if (e is DioException) {
        // 尝试提取服务端返回的错误信息
        final resp = e.response;
        if (resp?.data is Map) {
          errorMsg = (resp!.data as Map)['error']?.toString() ?? e.toString();
        } else if (resp?.statusCode != null) {
          errorMsg = "服务器错误(${resp!.statusCode}): ${resp.statusMessage}";
        } else {
          errorMsg = "网络请求失败: ${e.message ?? e.error}";
        }
      } else {
        errorMsg = e.toString();
      }
      showTopSnackBar(context, "提交失败: $errorMsg", bottomMargin: 82);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    idController.dispose();
    nameController.dispose();
    _batchTagCtrl.dispose();
    for (var item in _scoreItems) {
      item["subject"]!.dispose();
      item["score"]!.dispose();
      item["fullMark"]!.dispose();
    }
    super.dispose();
  }

  Widget _buildQueryUI() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 1000;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 复选框：选择查找方式
              Card(
                child: Column(
                  children: [
                    CheckboxListTile(
                      title: const Text("按学号查找"),
                      subtitle: const Text("精确匹配学生ID"),
                      value: _searchById,
                      onChanged: (v) => setState(() => _searchById = v ?? true),
                      secondary: const Icon(Icons.badge),
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                    Divider(height: 1, indent: 16, endIndent: 16),
                    CheckboxListTile(
                      title: const Text("按姓名查找"),
                      subtitle: const Text("模糊匹配学生姓名"),
                      value: _searchByName,
                      onChanged: (v) =>
                          setState(() => _searchByName = v ?? false),
                      secondary: const Icon(Icons.person),
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 宽屏：两个输入框并列
              if (isWide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: idController,
                        enabled: _searchById,
                        decoration: InputDecoration(
                          labelText: '学生ID',
                          hintText: _searchById ? '输入学生ID...' : '未勾选按学号查找',
                          border: const OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.badge,
                            color: _searchById ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: nameController,
                        enabled: _searchByName,
                        decoration: InputDecoration(
                          labelText: '学生姓名',
                          hintText: _searchByName ? '输入学生姓名...' : '未勾选按姓名查找',
                          border: const OutlineInputBorder(),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: _searchByName ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                // ID 输入框
                TextField(
                  controller: idController,
                  enabled: _searchById,
                  decoration: InputDecoration(
                    labelText: '学生ID',
                    hintText: _searchById ? '输入学生ID...' : '未勾选按学号查找',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.badge,
                      color: _searchById ? null : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 姓名输入框
                TextField(
                  controller: nameController,
                  enabled: _searchByName,
                  decoration: InputDecoration(
                    labelText: '学生姓名',
                    hintText: _searchByName ? '输入学生姓名...' : '未勾选按姓名查找',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(
                      Icons.person_outline,
                      color: _searchByName ? null : Colors.grey,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // 提示文字
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _searchById && _searchByName
                      ? '🔍 严格模式：同时匹配学号和姓名'
                      : _searchById
                      ? '🔍 按学号精确查找'
                      : '🔍 按姓名模糊查找',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  icon: _isQuerying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  onPressed: _isQuerying ? null : queryData,
                  label: const Text('查询成绩'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    side: Theme.of(context).brightness == Brightness.dark
                        ? BorderSide(
                            color: Colors.white.withValues(alpha: 0.24),
                            width: 1,
                          )
                        : BorderSide.none,
                  ),
                ),
              ),
              // 查询结果卡片区域（直接展示在按钮下方）
              if (_hasQueried) ...[
                const SizedBox(height: 16),
                if (_queryResults.isEmpty && !_isQuerying)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "未找到匹配的学生",
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      Text(
                        "查询结果（${_queryResults.length} 条）",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text("重新查询"),
                        onPressed: queryData,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._queryResults.map(
                    (student) => _buildResultCard(student, showDelete: true),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAddUI() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isWide = constraints.maxWidth > 1000;
        return Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "基本信息",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                // 宽屏：ID和姓名并列
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: idController,
                          decoration: const InputDecoration(
                            labelText: '学生ID',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.badge),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: '学生姓名',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                      ),
                    ],
                  )
                else ...[
                  TextField(
                    controller: idController,
                    decoration: const InputDecoration(
                      labelText: '学生ID',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: '学生姓名',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // 批次标签
                TextField(
                  controller: _batchTagCtrl,
                  decoration: const InputDecoration(
                    labelText: '批次标签（可选）',
                    hintText: '例如：期中考试、月考、模拟考',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "科目成绩",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addScoreItem,
                      icon: const Icon(Icons.add),
                      label: const Text("添加项"),
                    ),
                  ],
                ),
                const Divider(),
                if (_scoreItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      "暂无成绩项，请点击上方“添加项”开始录入",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                // 宽屏：科目成绩项用双列网格
                if (isWide)
                  _buildScoreGrid()
                else
                  ...List.generate(_scoreItems.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _scoreItems[index]["subject"],
                              decoration: const InputDecoration(
                                hintText: '科目',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _scoreItems[index]["score"],
                              decoration: const InputDecoration(
                                hintText: '分数',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _scoreItems[index]["fullMark"],
                              decoration: const InputDecoration(
                                hintText: '满分',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => _removeScoreItem(index),
                          ),
                        ],
                      ),
                    );
                  }),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _submitAddData,
                    label: const Text('添加成绩'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      side: Theme.of(context).brightness == Brightness.dark
                          ? BorderSide(
                              color: Colors.white.withValues(alpha: 0.24),
                              width: 1,
                            )
                          : BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 宽屏下成绩项的网格布局
  Widget _buildScoreGrid() {
    final items = <Widget>[];
    for (int i = 0; i < _scoreItems.length; i += 2) {
      final rowChildren = <Widget>[Expanded(child: _buildScoreRow(i))];
      if (i + 1 < _scoreItems.length) {
        rowChildren.add(const SizedBox(width: 12));
        rowChildren.add(Expanded(child: _buildScoreRow(i + 1)));
      }
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowChildren,
          ),
        ),
      );
    }
    return Column(children: items);
  }

  Widget _buildScoreRow(int index) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _scoreItems[index]["subject"],
            decoration: const InputDecoration(
              hintText: '科目',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _scoreItems[index]["score"],
            decoration: const InputDecoration(
              hintText: '分数',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _scoreItems[index]["fullMark"],
            decoration: const InputDecoration(
              hintText: '满分',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
          onPressed: () => _removeScoreItem(index),
        ),
      ],
    );
  }

  /// 删除指定学生的单科成绩（支持多条结果中的任意卡片）
  Future<void> _deleteSubjectScoreFrom(
    String subject,
    StudentData student,
  ) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定要删除「${student.name}」的「$subject」成绩吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("删除"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await LocalScoreService.deleteSubjectScore(
          studentId: student.studentId,
          subject: subject,
        );
      } else {
        await widget.dio.delete(
          "/delete/subject",
          queryParameters: {"id": student.studentId, "subject": subject},
        );
      }

      if (!mounted) return;

      // 刷新查询结果
      await queryData();

      if (!mounted) return;
      showTopSnackBar(
        context,
        "已删除「${student.name}」的「$subject」成绩",
        bottomMargin: 82,
      );
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, "删除失败: $e", bottomMargin: 82);
    }
  }

  /// 删除指定学生的所有信息（支持多条结果中的任意卡片）
  Future<void> _deleteStudentData(StudentData student) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: Text(
          "确定要删除「${student.name}」(学号: ${student.studentId}) 的所有信息吗？\n此操作不可撤销。",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("删除"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await LocalScoreService.deleteStudent(
          id: student.studentId.isNotEmpty ? student.studentId : null,
          name: student.name.isNotEmpty ? student.name : null,
        );
      } else {
        await widget.dio.delete(
          "/delete",
          queryParameters: {"id": student.studentId, "name": student.name},
        );
      }

      if (!mounted) return;
      showTopSnackBar(context, "已删除「${student.name}」的所有信息", bottomMargin: 82);

      setState(() {
        _queryResults = [];
        _hasQueried = false;
      });
      idController.clear();
      nameController.clear();
    } catch (e) {
      if (!mounted) return;
      showTopSnackBar(context, "删除失败: $e", bottomMargin: 82);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    final isMobilePlatform = Platform.isAndroid || Platform.isIOS;
    final shouldHideBottomBar = isKeyboardVisible && isMobilePlatform;
    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildTrendUI(), _buildQueryUI(), _buildAddUI()],
          ),
        ),
        // 移动端输入法弹出时隐藏底部导航栏
        Offstage(
          offstage: shouldHideBottomBar,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: isDark
                  ? Colors.white
                  : Theme.of(context).primaryColor,
              unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey,
              indicatorWeight: 3,
              tabs: const [
                Tab(icon: Icon(Icons.trending_up), text: "成绩走向"),
                Tab(icon: Icon(Icons.search), text: "成绩查询"),
                Tab(icon: Icon(Icons.add_circle_outline), text: "成绩录入"),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 成绩走向 — 趋势图表
  Widget _buildTrendUI() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return _TrendChartView(
          dio: widget.dio,
          idController: idController,
          nameController: nameController,
        );
      },
    );
  }
}

/// 成绩走向 — 趋势图表组件
class _TrendChartView extends StatefulWidget {
  final Dio dio;
  final TextEditingController idController;
  final TextEditingController nameController;
  const _TrendChartView({
    required this.dio,
    required this.idController,
    required this.nameController,
  });

  @override
  State<_TrendChartView> createState() => _TrendChartViewState();
}

class _TrendChartViewState extends State<_TrendChartView> {
  List<StudentData> _students = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _prefillFromConfig();
  }

  /// 从配置中预填姓名和学号，然后自动执行查询
  Future<void> _prefillFromConfig() async {
    try {
      final config = await loadConfigFile();
      final id = config['STUDENT_ID']?.toString() ?? '';
      final name = config['STUDENT_NAME']?.toString() ?? '';
      if (id.isNotEmpty || name.isNotEmpty) {
        if (widget.idController.text.trim().isEmpty) {
          widget.idController.text = id;
        }
        if (widget.nameController.text.trim().isEmpty) {
          widget.nameController.text = name;
        }
      }
      // 下一帧自动搜索（确保组件已就绪）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasSearched) _searchStudent();
      });
    } catch (e) {
      debugPrint(">>> 预填用户信息失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 查询区域
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: widget.idController,
                          decoration: const InputDecoration(
                            labelText: '学生ID',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: widget.nameController,
                          decoration: const InputDecoration(
                            labelText: '学生姓名',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _searchStudent,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.trending_up, size: 18),
                      label: const Text("查看成绩走向"),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 查询结果
          if (_hasSearched && !_isLoading) ...[
            if (_students.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "未找到该学生的成绩记录",
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "请检查学号或姓名是否正确",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "提示：成绩走向基于考试记录（examRecords）绘制，\n与标签（tag）无关。请先在成绩录入中添加成绩。",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._buildTrendCharts(isDark),
          ],
        ],
      ),
    );
  }

  Future<void> _searchStudent() async {
    final id = widget.idController.text.trim();
    final name = widget.nameController.text.trim();
    if (id.isEmpty && name.isEmpty) {
      showTopSnackBar(context, "请输入学生ID或姓名", bottomMargin: 82);
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _students = [];
    });

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (id.isNotEmpty && name.isNotEmpty) {
          // 双条件：先按 ID 精确查，再按姓名过滤
          final byId = await LocalScoreService.queryStudentsById(id);
          _students = byId.where((s) => s.name.contains(name)).toList();
          if (_students.isEmpty) {
            // ID+姓名组合无结果，尝试仅姓名模糊查
            final byName = await LocalScoreService.queryStudentsByName(name);
            _students = byName.where((s) => s.studentId == id).toList();
          }
        } else if (id.isNotEmpty) {
          _students = await LocalScoreService.queryStudentsById(id);
        } else {
          _students = await LocalScoreService.queryStudentsByName(name);
        }
      } else {
        final params = <String, dynamic>{};
        if (id.isNotEmpty) params['id'] = id;
        if (name.isNotEmpty) params['name'] = name;
        final res = await widget.dio.get('/query', queryParameters: params);
        if (!mounted) return;
        if (res.data is Map && res.data['error'] == null) {
          if (res.data['students'] is List) {
            _students = (res.data['students'] as List)
                .map((e) => StudentData.fromJson(e as Map<String, dynamic>))
                .toList();
          } else {
            // 单条结果（兼容旧格式）
            final single = StudentData(
              studentId: id.isNotEmpty ? id : '',
              name: res.data['name']?.toString() ?? '未知',
              scores: Map<String, dynamic>.from(res.data['scores'] ?? {}),
            );
            _students = [single];
          }
        } else {
          throw res.data['error']?.toString() ?? '未找到该学生';
        }
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, "查询失败: $e", bottomMargin: 82);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Widget> _buildTrendCharts(bool isDark) {
    final result = <Widget>[];
    final themeColor = Theme.of(context).colorScheme.primary;
    for (final student in _students) {
      // 收集该学生所有科目及标签
      final subjects = student.scores.keys.toList();
      final allTags = <String>{};
      for (final record in student.examRecords) {
        for (final entry in record.scores.entries) {
          final score = entry.value;
          if (score is Map && score['tag'] != null) {
            allTags.add(score['tag'].toString());
          }
        }
      }

      // 学生信息头
      result.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${student.name}（${student.studentId}）",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "共 ${student.examRecords.length} 次考试记录",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      );

      // 当无考试记录时，用当前成绩作为单点展示
      final List<ExamRecord> chartRecords;
      if (student.examRecords.isEmpty) {
        // 用当前成绩模拟一条记录
        final now = DateTime.now();
        final dateStr =
            "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} 00:00";
        chartRecords = [
          ExamRecord(date: dateStr, examType: '当前', scores: student.scores),
        ];
        result.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.blue.shade400,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "仅有当前成绩数据，录入多次考试后可查看趋势",
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        chartRecords = student.examRecords;
      }

      // === 总分趋势图 ===
      if (chartRecords.length >= 2) {
        final totalSpots = <FlSpot>[];
        final totalLabels = <int, String>{};
        int ti = 0;
        final sortedTotal = chartRecords.toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        for (final record in sortedTotal) {
          double total = 0;
          bool hasAny = false;
          for (final subject in subjects) {
            final s = record.scores[subject];
            if (s != null) {
              total += LocalScoreService.extractScore(s);
              hasAny = true;
            }
          }
          if (!hasAny) continue;
          totalSpots.add(FlSpot(ti.toDouble(), total));
          final dateShort = record.date.length >= 16
              ? record.date.substring(5, 10)
              : record.date;
          totalLabels[ti] = dateShort;
          ti++;
        }
        if (totalSpots.length >= 2) {
          final maxV = totalSpots
              .map((s) => s.y)
              .reduce((a, b) => a > b ? a : b);
          final minV = totalSpots
              .map((s) => s.y)
              .reduce((a, b) => a < b ? a : b);
          final pad = (maxV - minV).clamp(10, 100) * 0.3;
          result.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.summarize, size: 20, color: themeColor),
                          const SizedBox(width: 8),
                          Text(
                            "总分趋势",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${totalSpots.length} 次记录 · 最新总分: ${totalSpots.last.y.toStringAsFixed(0)}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: LineChart(
                          LineChartData(
                            minX: 0,
                            maxX: (totalSpots.length - 1).toDouble(),
                            minY: (minV - pad).floorToDouble(),
                            maxY: (maxV + pad).ceilToDouble(),
                            gridData: FlGridData(
                              show: true,
                              drawVerticalLine: false,
                              horizontalInterval:
                                  (((maxV - minV + pad * 2) / 5).ceilToDouble())
                                      .clamp(1, 200)
                                      .toDouble(),
                              getDrawingHorizontalLine: (v) => FlLine(
                                color: isDark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                                strokeWidth: 0.5,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (v, _) => Text(
                                    v.toStringAsFixed(0),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  interval: 1,
                                  getTitlesWidget: (v, _) {
                                    final l = totalLabels[v.toInt()];
                                    return l == null
                                        ? const SizedBox.shrink()
                                        : Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Text(
                                              l,
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: isDark
                                                    ? Colors.grey.shade400
                                                    : Colors.grey.shade600,
                                              ),
                                            ),
                                          );
                                  },
                                ),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineBarsData: [
                              LineChartBarData(
                                spots: totalSpots,
                                isCurved: true,
                                color: Colors.green.shade600,
                                barWidth: 2.5,
                                dotData: FlDotData(
                                  show: true,
                                  getDotPainter: (_, _, _, _) =>
                                      FlDotCirclePainter(
                                        radius: 3,
                                        color: Colors.green.shade600,
                                        strokeWidth: 1.5,
                                        strokeColor: isDark
                                            ? Colors.black
                                            : Colors.white,
                                      ),
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Colors.green.withValues(alpha: 0.1),
                                ),
                              ),
                            ],
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (spots) => spots.map((s) {
                                  final l = totalLabels[s.x.toInt()] ?? '';
                                  return LineTooltipItem(
                                    '总分: ${s.y.toStringAsFixed(0)}\n$l',
                                    TextStyle(
                                      color: Colors.green.shade600,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      }

      // 查看全部详情按钮
      result.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScoreResultPage(
                    userName: student.name,
                    studentId: student.studentId,
                    scores: student.scores,
                    examRecords: student.examRecords,
                  ),
                ),
              ),
              label: const Text("查看各科成绩走势 →", style: TextStyle(fontSize: 13)),
            ),
          ),
        ),
      );
    }
    return result;
  }
}

/// 将 HTML <table> 标签转换为 Markdown 管道表格
/// 用于兼容 AI 偶尔生成 HTML 表格而非 Markdown 表格的情况
String _convertHtmlTablesToMarkdown(String input) {
  // 匹配 <table>...</table> 块
  final tableRegExp = RegExp(
    r'<table[^>]*>(.*?)</table>',
    dotAll: true,
    caseSensitive: false,
  );
  return input.replaceAllMapped(tableRegExp, (match) {
    final tableContent = match.group(1) ?? '';
    final rows = <List<String>>[];
    final rowRegExp = RegExp(
      r'<tr[^>]*>(.*?)</tr>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final rowMatch in rowRegExp.allMatches(tableContent)) {
      final rowHtml = rowMatch.group(1) ?? '';
      // 提取 th 或 td 的内容
      final cellRegExp = RegExp(
        r'<(?:th|td)[^>]*>(.*?)</(?:th|td)>',
        dotAll: true,
        caseSensitive: false,
      );
      final cells = cellRegExp.allMatches(rowHtml).map((c) {
        var text = c.group(1)?.trim() ?? '';
        // 移除单元格内可能残留的 HTML 标签
        text = text.replaceAll(RegExp(r'<[^>]+>'), '');
        return text;
      }).toList();
      if (cells.isNotEmpty) rows.add(cells);
    }

    if (rows.isEmpty) return match.group(0) ?? '';

    final buffer = StringBuffer();
    final colCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

    // 表头（第一行）
    buffer.writeln('| ${rows[0].join(' | ')} |');
    // 分隔行
    buffer.writeln('| ${List.filled(colCount, '---').join(' | ')} |');
    // 数据行
    for (int i = 1; i < rows.length; i++) {
      // 补齐列数
      final row = List<String>.from(rows[i]);
      while (row.length < colCount) {
        row.add('');
      }
      buffer.writeln('| ${row.join(' | ')} |');
    }
    return buffer.toString().trim();
  });
}

class SchedulePage extends StatefulWidget {
  final Dio dio;
  final bool isActive;
  final String studentID;
  final String studentName;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  const SchedulePage({
    super.key,
    required this.dio,
    this.isActive = false,
    required this.studentID,
    required this.studentName,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
  });

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _taskController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _itinerary = "";
  String _summary = "";
  bool _isLoading = false;

  late final TabController _scheduleTabController;

  // 学习弱项相关
  bool _includeStudyAdvice = false;
  List<String> _availableSubjects = [];
  final Set<String> _selectedWeakSubjects = {};
  bool _isFetchingSubjects = false;
  bool _hasBeenActivated = false; // 首次激活标记

  @override
  void initState() {
    super.initState();
    _scheduleTabController = TabController(length: 2, vsync: this);
  }

  @override
  void didUpdateWidget(SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 首次激活或从其他页切换过来时刷新
    final isNowActive = widget.isActive;
    final wasActive = oldWidget.isActive;
    if (isNowActive && (!wasActive || !_hasBeenActivated)) {
      _hasBeenActivated = true;
      _fetchSavedSchedule();
      _fetchUserSubjects();
    }

    // 如果身份信息发生变化，重置并刷新
    if (widget.studentID != oldWidget.studentID ||
        widget.studentName != oldWidget.studentName) {
      setState(() {
        _availableSubjects = [];
        _selectedWeakSubjects.clear();
        _itinerary = "";
        _summary = "";
      });
      if (isNowActive) {
        _fetchSavedSchedule();
        _fetchUserSubjects();
      }
    }
  }

  Future<void> _fetchUserSubjects() async {
    // 如果是默认值，说明用户还没设置个人信息，直接跳过
    if (widget.studentID == "未知学号" ||
        widget.studentName == "未知用户" ||
        (widget.studentID.isEmpty && widget.studentName.isEmpty)) {
      return;
    }
    if (_isFetchingSubjects) return;

    setState(() => _isFetchingSubjects = true);
    try {
      List<String> subjects = [];
      if (Platform.isAndroid || Platform.isIOS) {
        // 📱 手机端：从本地文件读取
        final student = await LocalScoreService.queryStudent(
          id: widget.studentID.isNotEmpty ? widget.studentID : null,
          name: widget.studentName.isNotEmpty ? widget.studentName : null,
        );
        if (student != null) {
          subjects = student.scores.keys.toList();
        }
      } else {
        // 💻 PC：后端查询
        final response = await widget.dio.get(
          "/query",
          queryParameters: {"id": widget.studentID, "name": widget.studentName},
        );
        if (response.data != null && response.data["scores"] != null) {
          Map<String, dynamic> scores = Map<String, dynamic>.from(
            response.data["scores"],
          );
          subjects = scores.keys.toList();
        }
      }
      setState(() {
        _availableSubjects = subjects;
      });
    } catch (e) {
      debugPrint("获取科目列表失败: $e");
      setState(() => _availableSubjects = []);
    } finally {
      if (mounted) setState(() => _isFetchingSubjects = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      // 选好日期后自动尝试加载存档
      _fetchSavedSchedule();
    }
  }

  Future<void> _fetchSavedSchedule() async {
    // 如果组件已经卸载，直接返回防报错
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final dateStr =
          "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}";

      if (Platform.isAndroid || Platform.isIOS) {
        // 📱 手机端：从本地文件读取日程存档
        final saved = await LocalScheduleService.loadItinerary(dateStr);
        if (!mounted) return;
        if (saved != null) {
          final lines = saved.split('\n').where((l) => l.isNotEmpty).toList();
          final summary = lines.isNotEmpty
              ? lines[0].replaceAll('#', '').trim()
              : '已加载历史日程规划';
          setState(() {
            _itinerary = saved;
            _summary = summary;
          });
          showTopSnackBar(context, "成功加载 $dateStr 的本地存档", bottomMargin: 82);
        } else {
          setState(() {
            _itinerary = "";
            _summary =
                dateStr ==
                    "${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}"
                ? "暂无存档，请输入任务后生成"
                : "$dateStr 暂无存档";
          });
        }
      } else {
        // 💻 PC：后端读取
        final dioInstance = widget.dio;
        final response = await dioInstance.post(
          "/schedule",
          data: {"tasks": "", "date": dateStr},
        );
        if (!mounted) return;
        final fetchedItinerary =
            response.data["itinerary"]?.toString() ?? "无内容";
        setState(() {
          _itinerary = fetchedItinerary;
          if (response.data["summary"] != null) {
            _summary = response.data["summary"].toString();
          } else if (fetchedItinerary.contains("今日行程规划建议")) {
            _summary = "已加载历史日程规划";
          } else {
            _summary = "";
          }
        });
        if (response.data["from_cache"] == true) {
          showTopSnackBar(context, "成功加载 $dateStr 的本地存档", bottomMargin: 82);
        }
      }
    } catch (e) {
      debugPrint("读取存档失败: $e");
      if (mounted) {
        showTopSnackBar(context, "读取存档失败: $e", bottomMargin: 82);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generateSchedule() async {
    bool hasTasks = _taskController.text.trim().isNotEmpty;
    bool hasStudyAdvice =
        _includeStudyAdvice && _selectedWeakSubjects.isNotEmpty;

    if (!hasTasks && !hasStudyAdvice) {
      showTopSnackBar(context, "请输入任务内容或选择弱势学科", bottomMargin: 82);
      return;
    }

    setState(() {
      _isLoading = true;
      _itinerary = "";
    });

    showTopSnackBar(context, "正在生成日志……", bottomMargin: 82);

    try {
      final dateStr =
          "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}";

      if (Platform.isAndroid || Platform.isIOS) {
        // 📱 手机端：通过直连 AI API 生成日程
        final baseUrl = widget.directBaseUrl;
        final apiKey = widget.directApiKey;
        final model = widget.directModel;

        if (baseUrl == null || apiKey == null || model == null) {
          throw 'AI 配置不完整，请先在设置中配置 AI 服务';
        }

        // 获取城市和天气信息（让日程更准确）
        String? weatherInfo;
        try {
          final cityAdcode = await LocationService.getCityAdcode();
          final config = await loadConfigFile();
          final gaodeKey = config['Gaode_API_Key']?.toString() ?? '';
          if (gaodeKey.isNotEmpty) {
            final dio = Dio();
            final weatherRes = await dio.get(
              'https://restapi.amap.com/v3/weather/weatherInfo',
              queryParameters: {
                'city': cityAdcode,
                'key': gaodeKey,
                'extensions': 'base',
              },
            );
            if (weatherRes.data is Map &&
                weatherRes.data['lives'] is List &&
                (weatherRes.data['lives'] as List).isNotEmpty) {
              final live = (weatherRes.data['lives'] as List)[0];
              weatherInfo =
                  '城市: ${live['city']}, 天气: ${live['weather']}, '
                  '温度: ${live['temperature']}°C, 风向: ${live['winddirection']}, '
                  '风力: ${live['windpower']}级, 湿度: ${live['humidity']}%';
              debugPrint(">>> 获取到实时天气: $weatherInfo");
            }
          }
        } catch (e) {
          debugPrint(">>> 获取城市天气失败(不影响生成): $e");
        }

        final result = await LocalScheduleService.generateSchedule(
          tasks: _taskController.text,
          date: dateStr,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          studyWeaknesses: _includeStudyAdvice
              ? _selectedWeakSubjects.toList()
              : null,
          weatherInfo: weatherInfo,
        );

        if (!mounted) return;
        final itinerary = result['detail'] ?? '';
        final summary = result['summary'] ?? '已生成日程详细规划';

        setState(() {
          _itinerary = itinerary;
          _summary = summary;
        });

        // 保存到本地
        if (itinerary.isNotEmpty) {
          await LocalScheduleService.saveItinerary(dateStr, itinerary);
        }

        if (itinerary.isNotEmpty) {
          _scheduleTabController.animateTo(1);
        }
      } else {
        // 💻 PC：后端生成
        final dioInstance = widget.dio;
        Map<String, dynamic> requestData = {
          "tasks": _taskController.text,
          "city": "440100",
          "date": dateStr,
        };
        if (_includeStudyAdvice && _selectedWeakSubjects.isNotEmpty) {
          requestData["study_weaknesses"] = _selectedWeakSubjects.toList();
        }

        final response = await dioInstance.post(
          "/schedule",
          data: requestData,
          options: Options(receiveTimeout: const Duration(seconds: 90)),
        );

        if (response.data != null && response.data is Map) {
          setState(() {
            _itinerary = response.data["itinerary"]?.toString() ?? "";
            _summary = response.data["summary"]?.toString() ?? "已生成日程详细规划";
          });
          if (_itinerary.isNotEmpty) {
            _scheduleTabController.animateTo(1);
          }
        } else {
          setState(() {
            _summary = "服务器返回数据格式错误";
          });
        }
      }
    } catch (e) {
      debugPrint("生成日程出错: $e");
      if (mounted) {
        showTopSnackBar(context, "生成失败: $e", bottomMargin: 82);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    final isMobilePlatform = Platform.isAndroid || Platform.isIOS;
    final shouldHideBottomBar = isKeyboardVisible && isMobilePlatform;
    final dateDisplay =
        "${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日";

    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: _scheduleTabController,
            children: [
              // Tab 0：创建日程
              SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "输入任务内容",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _selectDate(context),
                          icon: const Icon(Icons.calendar_today),
                          label: Text(dateDisplay),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "格式提示：每行一个任务，可带时间关键词（早上/中午/晚上）和位置标签（@outdoor/@indoor）",
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _taskController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText:
                            "例如：\n早上 晨跑 @outdoor\n中午 整理文档 @indoor\n晚上 健身房",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blueGrey.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: _includeStudyAdvice,
                                onChanged: (value) {
                                  setState(() {
                                    _includeStudyAdvice = value ?? false;
                                  });
                                  if (_includeStudyAdvice &&
                                      _availableSubjects.isEmpty) {
                                    _fetchUserSubjects();
                                  }
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "根据学习情况提供建议",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      "选择你的弱势学科，AI将为你安排针对性的学习时间",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (_includeStudyAdvice) ...[
                            const SizedBox(height: 12),
                            if (_isFetchingSubjects)
                              const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else if (_availableSubjects.isEmpty)
                              const Text(
                                "暂无录入的学科，请先在'我的成绩'中录入",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange,
                                ),
                              )
                            else
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _availableSubjects.map((subject) {
                                  final isSelected = _selectedWeakSubjects
                                      .contains(subject);
                                  return FilterChip(
                                    label: Text(subject),
                                    selected: isSelected,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedWeakSubjects.add(subject);
                                        } else {
                                          _selectedWeakSubjects.remove(subject);
                                        }
                                      });
                                    },
                                    backgroundColor: Colors.white,
                                    selectedColor: Theme.of(
                                      context,
                                    ).primaryColor,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _generateSchedule,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: const Text("生成智能日程规划"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_summary.isNotEmpty) ...[
                      const Divider(),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.summarize, color: Colors.blue),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    "今日日程概要",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _summary,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                if (_itinerary.isNotEmpty) {
                                  _scheduleTabController.animateTo(1);
                                }
                              },
                              child: const Text("查看详情"),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Tab 1：查看日程
              _itinerary.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_note,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "暂无日程数据",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey.shade800 : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                          border: Border.all(
                            color: isDark
                                ? Colors.grey.shade700
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: MarkdownBody(
                          data: _convertHtmlTablesToMarkdown(
                            _itinerary
                                .replaceAll('```markdown', '')
                                .replaceAll('```', ''),
                          ),
                          selectable: true,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              fontSize: 16,
                              height: 1.6,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            h1: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            h2: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            tableBody: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            tableHead: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            tableBorder: TableBorder.all(
                              color: isDark
                                  ? Colors.grey.shade600
                                  : Colors.black,
                              width: 1,
                            ),
                            tableColumnWidth: const IntrinsicColumnWidth(),
                            tableScrollbarThumbVisibility: true,
                            tableCellsPadding: const EdgeInsets.all(10),
                            listBullet: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white70 : Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
            ],
          ),
        ),
        // 移动端输入法弹出时隐藏底部导航栏
        Offstage(
          offstage: shouldHideBottomBar,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
            ),
            child: TabBar(
              controller: _scheduleTabController,
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: isDark
                  ? Colors.white
                  : Theme.of(context).primaryColor,
              unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey,
              indicatorWeight: 3,
              tabs: const [
                Tab(icon: Icon(Icons.add_circle_outline), text: "创建"),
                Tab(icon: Icon(Icons.visibility), text: "查看"),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scheduleTabController.dispose();
    _taskController.dispose();
    super.dispose();
  }
}

/// 构建 OCR 插入文本（公式已内联在 text 中）
String buildOcrInsertText(String text, String? formulaText) => text;

/// 自定义 InlineSyntax：匹配 $...$（行内公式）和 $$...$$（显示公式）
class _MathInlineSyntax extends md.InlineSyntax {
  _MathInlineSyntax() : super(r'\$\$([\s\S]+?)\$\$|\$([\s\S]+?)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final formula = (match.group(1) ?? match.group(2) ?? '').trim();
    if (formula.isEmpty) return false;
    final isDisplay = match.group(1) != null;
    final el = md.Element('math', [md.Text(formula)]);
    if (isDisplay) {
      el.attributes['display'] = 'true';
    }
    parser.addNode(el);
    return true;
  }
}

/// 文本段：普通 Markdown 或防剧透块（details 标签）
class _TextSegment {
  final bool isDetails;
  final String summary;
  final String content;
  const _TextSegment({
    required this.isDetails,
    this.summary = '',
    required this.content,
  });
}

/// 防剧透 Widget：点击前模糊/隐藏，点击后显示内容（类似 Telegram spoiler）
class _SpoilerWidget extends StatefulWidget {
  final String summary;
  final Widget contentWidget;

  const _SpoilerWidget({required this.summary, required this.contentWidget});

  @override
  State<_SpoilerWidget> createState() => _SpoilerWidgetState();
}

class _SpoilerWidgetState extends State<_SpoilerWidget> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.shade800
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.visibility : Icons.visibility_off,
                  size: 16,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.color?.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.summary,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.color?.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 8),
            child: widget.contentWidget,
          ),
      ],
    );
  }
}

/// 可折叠的思考过程组件（用于展示 AI 推理过程）
/// 用户可点击标题展开/收起，默认收起
class _ThinkingSection extends StatefulWidget {
  final String reasoning;

  /// 当 AI 已开始输出回复内容时设为 true，触发自动收起
  final bool autoCollapse;
  const _ThinkingSection({required this.reasoning, this.autoCollapse = false});

  @override
  State<_ThinkingSection> createState() => _ThinkingSectionState();
}

class _ThinkingSectionState extends State<_ThinkingSection> {
  bool _expanded = true; // 默认展开

  @override
  void didUpdateWidget(covariant _ThinkingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // AI 开始输出回复内容 → 自动收起思考过程
    if (!oldWidget.autoCollapse && widget.autoCollapse && _expanded) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? themeColor.withValues(alpha: 0.08)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? themeColor.withValues(alpha: 0.2)
              : Colors.grey.shade300,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 可点击的标题栏
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology,
                    size: 18,
                    color: themeColor.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "思考过程",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: themeColor.withValues(alpha: 0.8),
                    ),
                  ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 20,
                      color: themeColor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 展开的思考内容
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                widget.reasoning,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

/// 聊天消息：MarkdownBody + flutter_math_fork 混合渲染
/// 支持防剧透块（details/summary 标签）
class _MathAwareText extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isDark;

  const _MathAwareText({
    required this.text,
    required this.isUser,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final userColor = isDark
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Colors.white;
    final aiColor = isDark
        ? (Theme.of(context).textTheme.bodyLarge?.color ??
              const Color(0xFFE0E0E0))
        : Colors.black87;
    final textColor = isUser ? userColor : aiColor;

    // 1) 基础清理：移除横线、合并多空行
    final cleaned = text
        .replaceAll(RegExp(r'\n-{3,}\n'), '\n\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 2) 解析 <details> 块
    final segments = _parseDetails(cleaned);

    // 3) 没有 details 块 → 直接 MarkdownBody
    if (segments.length == 1 && !segments[0].isDetails) {
      return _buildMarkdown(segments[0].content, textColor, isDark);
    }

    // 4) 混合内容 → Column
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: segments.map((seg) {
        if (seg.isDetails) {
          final contentWidget = _buildMarkdown(seg.content, textColor, isDark);
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: _SpoilerWidget(
              summary: seg.summary,
              contentWidget: contentWidget,
            ),
          );
        }
        if (seg.content.trim().isEmpty) return const SizedBox.shrink();
        return _buildMarkdown(seg.content, textColor, isDark);
      }).toList(),
    );
  }

  /// 解析 details/summary HTML 标签包裹的防剧透内容
  static List<_TextSegment> _parseDetails(String text) {
    final regex = RegExp(
      r'<details>\s*<summary>(.*?)</summary>\s*(.*?)\s*</details>',
      caseSensitive: false,
      dotAll: true,
    );
    final segments = <_TextSegment>[];
    int lastEnd = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > lastEnd) {
        segments.add(
          _TextSegment(
            isDetails: false,
            content: text.substring(lastEnd, m.start),
          ),
        );
      }
      segments.add(
        _TextSegment(
          isDetails: true,
          summary: m.group(1)!.trim(),
          content: m.group(2)!.trim(),
        ),
      );
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      segments.add(
        _TextSegment(isDetails: false, content: text.substring(lastEnd)),
      );
    }
    if (segments.isEmpty) {
      segments.add(_TextSegment(isDetails: false, content: text));
    }
    return segments;
  }

  /// 构建一段 MarkdownBody（含公式支持+多行选择）
  Widget _buildMarkdown(String data, Color textColor, bool isDark) {
    return SelectionArea(
      child: MarkdownBody(
        data: data,
        selectable: false,
        inlineSyntaxes: [_MathInlineSyntax()],
        builders: {'math': _MathElementBuilder(textColor: textColor)},
        styleSheet: _markdownStyle(textColor, isDark),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(Color textColor, bool isDark) {
    return MarkdownStyleSheet(
      p: TextStyle(color: textColor, fontSize: 16),
      code: TextStyle(
        backgroundColor: isDark
            ? const Color(0xFF1E1E1E)
            : Colors.grey.shade100,
        color: isDark ? const Color(0xFF6A9955) : Colors.black87,
        fontSize: 14,
      ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      h1: TextStyle(
        color: textColor,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      h2: TextStyle(
        color: textColor,
        fontSize: 19,
        fontWeight: FontWeight.bold,
      ),
      h3: TextStyle(
        color: textColor,
        fontSize: 17,
        fontWeight: FontWeight.bold,
      ),
      a: TextStyle(color: isDark ? const Color(0xFF64B5F6) : Colors.blue),
      strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      blockquote: TextStyle(
        color: isDark ? const Color(0xFFE0E0E0) : Colors.black54,
      ),
      blockquoteDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E3A3A) : const Color(0xFFF0F7FF),
        borderRadius: BorderRadius.circular(6),
      ),
      tableBorder: TableBorder.all(
        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
        width: 1,
      ),
      tableHead: TextStyle(fontWeight: FontWeight.bold, color: textColor),
      tableBody: TextStyle(color: textColor),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableScrollbarThumbVisibility: true,
      tableCellsPadding: const EdgeInsets.all(8),
      listBullet: TextStyle(color: textColor.withValues(alpha: 0.7)),
    );
  }
}

/// MarkdownElementBuilder for 元素：用 flutter_math_fork 渲染公式
/// 含中文时回退为普通文本，避免 LaTeX "unicodeTextInMathMode" 警告
class _MathElementBuilder extends MarkdownElementBuilder {
  final Color textColor;
  _MathElementBuilder({required this.textColor});

  @override
  bool isBlockElement() => false;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final formula = element.textContent.trim();
    if (formula.isEmpty) return null;

    final isDisplay = element.attributes['display'] == 'true';

    // 含中文时不作为公式渲染
    if (_containsChinese(formula)) {
      // 用斜体表示被 $ 包裹的中文文本
      return Text(
        formula,
        style: TextStyle(
          color: textColor,
          fontSize: 16,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (isDisplay) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              _sanitizeLatex(formula),
              textStyle: TextStyle(color: textColor, fontSize: 16),
              mathStyle: MathStyle.display,
            ),
          ),
        ),
      );
    }

    // 行内公式：Text.rich + WidgetSpan 嵌入文字流，ConstrainedBox 限制宽度防溢出
    final maxFormulaWidth = MediaQuery.of(context).size.width * 0.6;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxFormulaWidth),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Math.tex(
                  _sanitizeLatex(formula),
                  textStyle: TextStyle(color: textColor, fontSize: 16),
                  mathStyle: MathStyle.text,
                ),
              ),
            ),
          ),
        ],
      ),
      style: TextStyle(color: textColor, fontSize: 16),
    );
  }

  /// 将 Unicode 上标/下标字符转为 LaTeX 语法，避免 KaTeX "unknownSymbol" 警告
  static String _sanitizeLatex(String s) {
    return s
        // 上标
        .replaceAll('\u{2070}', '^0')
        .replaceAll('\u{00B9}', '^1')
        .replaceAll('\u{00B2}', '^2')
        .replaceAll('\u{00B3}', '^3')
        .replaceAll('\u{2074}', '^4')
        .replaceAll('\u{2075}', '^5')
        .replaceAll('\u{2076}', '^6')
        .replaceAll('\u{2077}', '^7')
        .replaceAll('\u{2078}', '^8')
        .replaceAll('\u{2079}', '^9')
        .replaceAll('\u{207A}', '^+')
        .replaceAll('\u{207B}', '^-')
        .replaceAll('\u{207C}', '^=')
        .replaceAll('\u{207D}', '^(')
        .replaceAll('\u{207E}', '^)')
        .replaceAll('\u{207F}', '^n')
        // 下标
        .replaceAll('\u{2080}', '_0')
        .replaceAll('\u{2081}', '_1')
        .replaceAll('\u{2082}', '_2')
        .replaceAll('\u{2083}', '_3')
        .replaceAll('\u{2084}', '_4')
        .replaceAll('\u{2085}', '_5')
        .replaceAll('\u{2086}', '_6')
        .replaceAll('\u{2087}', '_7')
        .replaceAll('\u{2088}', '_8')
        .replaceAll('\u{2089}', '_9');
  }

  bool _containsChinese(String s) => s.contains(RegExp(r'[\u4e00-\u9fff]'));
}

/// OCR 结果对话框（独立 StatefulWidget 避免状态重置问题）
class _OcrResultDialog extends StatefulWidget {
  final String fileName;
  final String initialText;
  final String imageBase64;
  final TextEditingController controller;
  final FocusNode inputFocusNode;
  final Future<String> Function(String b64) onOcrWithAi;

  const _OcrResultDialog({
    required this.fileName,
    required this.initialText,
    required this.imageBase64,
    required this.controller,
    required this.inputFocusNode,
    required this.onOcrWithAi,
  });

  @override
  State<_OcrResultDialog> createState() => _OcrResultDialogState();
}

class _OcrResultDialogState extends State<_OcrResultDialog> {
  late String _displayText;
  bool _isAiEnhanced = false;
  bool _isAiLoading = false;

  @override
  void initState() {
    super.initState();
    _displayText = widget.initialText;
  }

  void _onInsert() {
    Navigator.pop(context);
    final existingText = widget.controller.text;
    if (existingText.isNotEmpty) {
      widget.controller.text = '$existingText\n\n$_displayText';
    } else {
      widget.controller.text = _displayText;
    }
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: widget.controller.text.length),
    );
    widget.inputFocusNode.requestFocus();
  }

  Future<void> _onAiRetry() async {
    showOverlaySnackBar(context, "正在使用 AI 重新识别...", bottomMargin: 142);
    setState(() => _isAiLoading = true);
    final aiText = await widget.onOcrWithAi(widget.imageBase64);
    if (mounted) {
      setState(() {
        _displayText = aiText;
        _isAiEnhanced = true;
        _isAiLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isAiEnhanced ? Icons.auto_awesome : Icons.text_snippet,
            size: 20,
            color: _isAiEnhanced ? Colors.amber.shade700 : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isAiEnhanced ? "OCR 识别结果 (AI精修)" : "OCR 识别结果",
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 360),
        child: SizedBox(
          width: double.maxFinite,
          child: Stack(
            children: [
              // 内容始终可见
              Opacity(
                opacity: _isAiLoading ? 0.4 : 1.0,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "文件: ${widget.fileName}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Text(
                            "📝 识别结果:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          if (_isAiEnhanced) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "AI 精修",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _displayText.isNotEmpty ? _displayText : "（未识别到文字）",
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 加载中遮罩
              if (_isAiLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("关闭"),
        ),
        // AI 重新识别按钮
        if (!_isAiEnhanced && !_isAiLoading)
          OutlinedButton.icon(
            onPressed: _onAiRetry,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: const Text("使用 AI 重新识别"),
          ),
        // 插入到输入框
        if (!_isAiLoading)
          FilledButton.icon(
            onPressed: _onInsert,
            icon: const Icon(Icons.edit, size: 16),
            label: const Text("插入到输入框"),
          ),
      ],
    );
  }
}

/// 附件预览组件（图片显示缩略图，非图片显示文件图标+名称）
class _AttachmentPreview extends StatelessWidget {
  final AttachmentInfo attachment;
  final VoidCallback onDelete;

  const _AttachmentPreview({required this.attachment, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (attachment.type == 'image') {
      // 图片附件：显示缩略图
      return Stack(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Image.memory(
                base64Decode(attachment.data),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    child: const Center(
                      child: Icon(Icons.broken_image, size: 24),
                    ),
                  );
                },
              ),
            ),
          ),
          // 文件名浮层
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(7),
                  bottomRight: Radius.circular(7),
                ),
                color: Colors.black.withValues(alpha: 0.5),
              ),
              child: Text(
                attachment.name.length > 10
                    ? '...${attachment.name.substring(attachment.name.length - 10)}'
                    : attachment.name,
                style: const TextStyle(color: Colors.white, fontSize: 9),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // 删除按钮
          Positioned(
            top: -4,
            right: -4,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade700 : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: isDark ? Colors.white : Colors.grey.shade700,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      // 非图片附件：显示文件图标+名称
      return SizedBox(
        height: 56,
        child: Material(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file,
                    size: 20,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      attachment.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }
}

/// 包裹 [TabBarView] 子项，使其在标签切换时保持存活不被销毁
class _KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const _KeepAliveWrapper({required this.child});

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}

@Preview()
Widget homePreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
    home: MyHomePage(dio: Dio()),
  );
}
