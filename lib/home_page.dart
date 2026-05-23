import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/score_result_page.dart';
import 'package:ai_agent/settings_page.dart';
import 'package:ai_agent/history_page.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:ai_agent/schedule_detail_page.dart';
import 'package:ai_agent/local_backend.dart';
import 'package:url_launcher/url_launcher.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.dio,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
  });
  final Dio dio;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;

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

  final List<String> pageTitles = ["AI聊天", "我的成绩", "日程安排"];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
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

  void onItemTapped(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  Widget buildDrawer() {
    return Drawer(
      child: ListTileTheme(
        selectedColor: Theme.of(context).primaryColor,
        iconColor: Colors.grey.shade600,
        textColor: Colors.black87,
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
                selectedIndex == 1 ? Icons.analytics : Icons.analytics_outlined,
              ),
              title: const Text("我的成绩"),
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
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("设置"),
              onTap: () async {
                Navigator.pop(context); // Close drawer
                await Navigator.push(
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
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget buildRail() {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onItemTapped,
      labelType: NavigationRailLabelType.all,
      destinations: [
        NavigationRailDestination(
          icon: Icon(selectedIndex == 0 ? Icons.home : Icons.home_outlined),
          label: const Text("AI聊天"),
        ),
        NavigationRailDestination(
          icon: Icon(
            selectedIndex == 1 ? Icons.analytics : Icons.analytics_outlined,
          ),
          label: const Text("我的成绩"),
        ),
        NavigationRailDestination(
          icon: Icon(
            selectedIndex == 2 ? Icons.event_note : Icons.event_note_outlined,
          ),
          label: const Text("日程安排"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          selectedIndex == 0 && _currentChatSummary != null
              ? _currentChatSummary!
              : pageTitles[selectedIndex],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (selectedIndex == 0) ...[
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
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: "查看聊天历史",
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => HistoryPage(dio: widget.dio),
                  ),
                );
                if (result != null && result is Map) {
                  setState(() {
                    _currentChatSummary = result['summary'];
                  });
                  _homeContentKey.currentState?.loadHistory(result);
                }
              },
            ),
          ],
          const SizedBox(width: 10),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
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
            },
          ),
        ],
      ),
      drawer: isMobile ? buildDrawer() : null,
      drawerEdgeDragWidth: isMobile
          ? MediaQuery.of(context).size.width * 0.15
          : null,
      body: isMobile
          ? IndexedStack(
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
              ],
            )
          : Row(
              children: [
                buildRail(),
                const VerticalDivider(width: 1),
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
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class HomeContent extends StatefulWidget {
  final Dio dio;
  final Function(String)? onSummaryUpdate;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  const HomeContent({
    super.key,
    required this.dio,
    this.onSummaryUpdate,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
  });

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final List<Map<String, dynamic>> _messages = [
    {"text": "你好！我是你的AI助手，有什么我可以帮你的吗？", "isUser": false},
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 当前提问是否涉及地图/位置相关
  bool _isMapQuery = false;

  /// 地图相关关键词列表
  static const _mapKeywords = [
    '地图',
    '导航',
    '位置',
    '路线',
    '路况',
    '在哪里',
    '怎么去',
    '到',
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("无法打开高德地图，请手动访问 ditu.amap.com")),
          );
        }
      }
    }
  }

  void resetChat() {
    setState(() {
      _isMapQuery = false;
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

  void _scrollToBottom() {
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

    setState(() {
      _isMapQuery = queryIsMapRelated;
      _messages.add({"text": text, "isUser": true});
    });
    _controller.clear();
    _scrollToBottom();

    // 添加一个空的 AI 回复占位
    setState(() {
      _messages.add({"text": "", "isUser": false});
    });
    int aiMsgIndex = _messages.length - 1;

    try {
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

        // 构建消息列表（含系统提示）
        final apiMessages = [
          {"role": "system", "content": "你是一个 helpful 的 AI 学习助手。"},
          ...historyToSend,
        ];

        final stream = directStreamChat(
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: model,
          messages: apiMessages,
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
        saveBacklog(messages: backlogMessages, summary: summary);
      } else {
        // 💻 PC 模式：通过本地后端
        debugPrint("正在请求: ${widget.dio.options.baseUrl}/chat");

        final response = await widget.dio.post(
          "/chat",
          data: {"prompt": text, "history": historyToSend},
          options: Options(responseType: ResponseType.stream),
        );

        final stream = response.data.stream as Stream<Uint8List>;

        await for (final chunk in stream.cast<List<int>>().transform(
          utf8.decoder,
        )) {
          if (!mounted) break;
          setState(() {
            _messages[aiMsgIndex]["text"] =
                (_messages[aiMsgIndex]["text"] as String) + chunk;
          });
          _scrollToBottom();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isUser = msg["isUser"] as bool;
              // 是否是最后一个AI消息（当前正在渲染或刚完成的回复）
              final isLastAiMsg = !isUser && index == _messages.length - 1;
              return Align(
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
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 0),
                      bottomRight: Radius.circular(isUser ? 0 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MarkdownBody(
                        data: msg["text"],
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 16,
                          ),
                          listBullet: TextStyle(
                            color: isUser ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                      // 地图跳转按钮：整合在AI回复气泡底部
                      if (isLastAiMsg && _isMapQuery)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openAmap,
                              icon: const Icon(Icons.map, size: 16),
                              label: const Text(
                                "在地图中查看",
                                style: TextStyle(fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFF6A00),
                                side: const BorderSide(
                                  color: Color(0xFFFF6A00),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                minimumSize: const Size(0, 32),
                                visualDensity: VisualDensity.compact,
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
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: "给AI发送消息...",
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
                onPressed: _handleSend,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class ScorePage extends StatefulWidget {
  final Dio dio;
  const ScorePage({super.key, required this.dio});

  @override
  State<ScorePage> createState() => _ScorePageState();
}

class _ScorePageState extends State<ScorePage> {
  final TextEditingController idController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final List<Map<String, TextEditingController>> _scoreItems = [];

  int _selectedFuncIndex = 0;
  // 查询复选框状态
  bool _searchById = true;
  bool _searchByName = false;
  // 删除预览
  StudentData? _deletePreview;
  bool _isQueryingDelete = false;

  void _addScoreItem() {
    setState(() {
      _scoreItems.add({
        "subject": TextEditingController(),
        "score": TextEditingController(),
      });
    });
  }

  void _removeScoreItem(int index) {
    setState(() {
      _scoreItems[index]["subject"]!.dispose();
      _scoreItems[index]["score"]!.dispose();
      _scoreItems.removeAt(index);
    });
  }

  /// 跳转到成绩详情页
  void _goToScoreResult(String name, String? id, Map<String, dynamic> scores) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ScoreResultPage(userName: name, studentId: id, scores: scores),
      ),
    );
  }

  /// 展示学生列表让用户选择（居中弹窗）
  Future<void> _showStudentPicker(List<StudentData> students) async {
    if (!mounted) return;
    final selected = await showDialog<StudentData>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text("选择学生"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: students.length,
            itemBuilder: (context, index) {
              final s = students[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    s.name.isNotEmpty ? s.name[0] : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(s.name),
                subtitle: Text(
                  "学号: ${s.studentId}  ·  科目: ${s.scores.length}门",
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, s),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
        ],
      ),
    );
    if (selected != null && mounted) {
      _goToScoreResult(selected.name, selected.studentId, selected.scores);
    }
  }

  Future<void> queryData() async {
    try {
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

      // 两个都未勾选 → 显示全部
      if (!_searchById && !_searchByName) {
        if (Platform.isAndroid) {
          final allStudents = await LocalScoreService.listAllStudents();
          if (!mounted) return;
          if (allStudents.isEmpty) {
            throw "暂无学生数据";
          }
          await _showStudentPicker(allStudents);
          return;
        } else {
          throw "请勾选查找方式并输入内容";
        }
      }

      if (Platform.isAndroid) {
        // 📱 Android：本地文件查询
        if (_searchById && _searchByName) {
          // 严格模式
          final student = await LocalScoreService.queryStudent(id: rawId);
          if (!mounted) return;
          if (student != null && student.name.contains(rawName)) {
            _goToScoreResult(student.name, student.studentId, student.scores);
          } else {
            throw "未找到学号「$rawId」且姓名包含「$rawName」的学生";
          }
        } else if (_searchById) {
          final student = await LocalScoreService.queryStudent(id: rawId);
          if (!mounted) return;
          if (student != null) {
            _goToScoreResult(student.name, student.studentId, student.scores);
          } else {
            throw "未找到学号为「$rawId」的学生";
          }
        } else {
          final matches = await LocalScoreService.queryStudentsByName(rawName);
          if (!mounted) return;
          if (matches.isEmpty) {
            throw "未找到姓名包含「$rawName」的学生";
          } else if (matches.length == 1) {
            _goToScoreResult(
              matches[0].name,
              matches[0].studentId,
              matches[0].scores,
            );
          } else {
            await _showStudentPicker(matches);
          }
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
          _goToScoreResult(
            response.data['name']?.toString() ?? '未知',
            hasId ? rawId : null,
            Map<String, dynamic>.from(response.data['scores'] ?? {}),
          );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    }
  }

  Future<void> _submitAddData() async {
    try {
      final List<Map<String, dynamic>> scoreList = [];
      for (var item in _scoreItems) {
        final subject = item["subject"]!.text.trim();
        final score = item["score"]!.text.trim();
        if (subject.isNotEmpty && score.isNotEmpty) {
          scoreList.add({subject: score});
        }
      }

      if (idController.text.isEmpty || nameController.text.isEmpty) {
        throw "学生ID和姓名不能为空";
      }
      if (scoreList.isEmpty) {
        throw "请至少添加一条成绩";
      }

      // 合并 scores
      final scoresMap = <String, dynamic>{};
      for (final entry in scoreList) {
        scoresMap.addAll(entry);
      }

      if (Platform.isAndroid) {
        // 📱 Android：本地文件添加
        await LocalScoreService.addScore(
          studentId: idController.text,
          name: nameController.text,
          scores: scoresMap,
        );
      } else {
        // 💻 PC：后端添加
        await widget.dio.post(
          "/add",
          data: {
            "id": idController.text,
            "name": nameController.text,
            "scores": scoreList,
          },
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("信息已成功添加到系统")));

      idController.clear();
      nameController.clear();
      setState(() {
        for (var item in _scoreItems) {
          item["subject"]!.dispose();
          item["score"]!.dispose();
        }
        _scoreItems.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("提交失败: $e")));
    }
  }

  /// 查询待删除学生预览
  Future<void> _previewDelete() async {
    final rawId = idController.text.trim();
    final rawName = nameController.text.trim();
    if (rawId.isEmpty && rawName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请输入学生ID或姓名")));
      return;
    }

    setState(() {
      _isQueryingDelete = true;
      _deletePreview = null;
    });

    try {
      if (Platform.isAndroid) {
        StudentData? student;
        if (rawId.isNotEmpty) {
          student = await LocalScoreService.queryStudent(id: rawId);
        } else {
          final matches = await LocalScoreService.queryStudentsByName(rawName);
          student = matches.isNotEmpty ? matches[0] : null;
        }
        if (!mounted) return;
        if (student != null) {
          setState(() => _deletePreview = student);
        } else {
          throw "未找到该学生";
        }
      } else {
        // PC 端
        final params = <String, dynamic>{};
        if (rawId.isNotEmpty) params['id'] = rawId;
        if (rawName.isNotEmpty) params['name'] = rawName;
        final res = await widget.dio.get('/query', queryParameters: params);
        if (!mounted) return;
        if (res.data is Map && res.data['error'] == null) {
          setState(() {
            _deletePreview = StudentData(
              studentId: rawId,
              name: res.data['name']?.toString() ?? '',
              scores: Map<String, dynamic>.from(res.data['scores'] ?? {}),
            );
          });
        } else {
          throw "未找到该学生";
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _deletePreview = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("查询失败: $e")));
    } finally {
      if (mounted) setState(() => _isQueryingDelete = false);
    }
  }

  Future<void> _deleteData() async {
    if (_deletePreview == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先查询学生信息")));
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: Text(
          "确定要删除「${_deletePreview!.name}」(学号: ${_deletePreview!.studentId}) 的信息吗？\n此操作不可撤销。",
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
      if (Platform.isAndroid) {
        await LocalScoreService.deleteStudent(
          id: _deletePreview!.studentId.isNotEmpty
              ? _deletePreview!.studentId
              : null,
          name: _deletePreview!.name.isNotEmpty ? _deletePreview!.name : null,
        );
      } else {
        await widget.dio.delete(
          "/delete",
          queryParameters: {
            "id": _deletePreview!.studentId,
            "name": _deletePreview!.name,
          },
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("已删除「${_deletePreview!.name}」的信息")),
      );

      setState(() {
        _deletePreview = null;
      });
      idController.clear();
      nameController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("删除失败: $e")));
    }
  }

  @override
  void dispose() {
    idController.dispose();
    nameController.dispose();
    for (var item in _scoreItems) {
      item["subject"]!.dispose();
      item["score"]!.dispose();
    }
    super.dispose();
  }

  Widget _buildSearchUI() {
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
                  onChanged: (v) => setState(() => _searchByName = v ?? false),
                  secondary: const Icon(Icons.person),
                  controlAffinity: ListTileControlAffinity.trailing,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 8),
          // 提示文字
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _searchById && _searchByName
                  ? '🔍 严格模式：同时匹配学号和姓名'
                  : _searchById
                  ? '🔍 按学号精确查找'
                  : _searchByName
                  ? '🔍 按姓名模糊查找'
                  : '👥 两项都不勾选将显示全部学生',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.search),
              onPressed: queryData,
              label: const Text('查询成绩'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddUI() {
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
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "科目成绩",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
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
              child: ElevatedButton(
                onPressed: _submitAddData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('确认录入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "删除信息",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            "请提供学生ID或姓名，先查询再删除：",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: idController,
            decoration: const InputDecoration(
              labelText: '学生ID',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '学生姓名',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 16),
          // 先查询按钮
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              icon: _isQueryingDelete
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              onPressed: _isQueryingDelete ? null : _previewDelete,
              label: const Text('查询学生信息'),
            ),
          ),
          // 查询结果预览
          if (_deletePreview != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.orange.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.orange,
                          child: Text(
                            _deletePreview!.name.isNotEmpty
                                ? _deletePreview!.name[0]
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _deletePreview!.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "学号: ${_deletePreview!.studentId}",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 可点击展开查看课程详情
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ScoreResultPage(
                              userName: _deletePreview!.name,
                              studentId: _deletePreview!.studentId,
                              scores: _deletePreview!.scores,
                            ),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Text(
                            "共 ${_deletePreview!.scores.length} 门课程",
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.visibility,
                            size: 16,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "点击查看详情",
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.delete_forever, size: 20),
                        onPressed: _deleteData,
                        label: const Text(
                          '确认删除这名学生',
                          style: TextStyle(fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: _selectedFuncIndex,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              onTap: (index) {
                setState(() {
                  _selectedFuncIndex = index;
                });
              },
              indicatorSize: TabBarIndicatorSize.label,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorWeight: 3,
              tabs: const [
                Tab(icon: Icon(Icons.search), text: "查询"),
                Tab(icon: Icon(Icons.add_circle_outline), text: "录入"),
                Tab(icon: Icon(Icons.delete_outline), text: "删除"),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedFuncIndex,
              children: [_buildSearchUI(), _buildAddUI(), _buildDeleteUI()],
            ),
          ),
        ],
      ),
    );
  }
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

class _SchedulePageState extends State<SchedulePage> {
  final TextEditingController _taskController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _itinerary = "";
  String _summary = ""; // 新增摘要状态
  bool _isLoading = false;

  // 学习弱项相关
  bool _includeStudyAdvice = false;
  List<String> _availableSubjects = []; // 动态加载
  final Set<String> _selectedWeakSubjects = {};
  bool _isFetchingSubjects = false;

  @override
  void initState() {
    super.initState();
    // 页面初始化时自动加载学科列表（如果学号姓名已配置）
    Future.microtask(() => _fetchUserSubjects());
  }

  @override
  void didUpdateWidget(SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 如果身份信息发生变化，重置并刷新学科列表和日程
    if (widget.studentID != oldWidget.studentID ||
        widget.studentName != oldWidget.studentName) {
      setState(() {
        _availableSubjects = [];
        _selectedWeakSubjects.clear();
        _itinerary = "";
        _summary = "";
      });

      // 只有在当前页面是激活状态（被点击选中）时，身份变化才触发加载
      if (widget.isActive) {
        _fetchSavedSchedule();
        _fetchUserSubjects();
      }
    }
    // 或者：从其他页面切换到当前日程页面时触发加载
    else if (widget.isActive && !oldWidget.isActive) {
      _fetchSavedSchedule();
      _fetchUserSubjects();
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
      if (Platform.isAndroid) {
        // 📱 Android：从本地文件读取
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

      if (Platform.isAndroid) {
        // 📱 Android：从本地文件读取日程存档
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("成功加载 $dateStr 的本地存档")));
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("成功加载 $dateStr 的本地存档")));
        }
      }
    } catch (e) {
      debugPrint("读取存档失败: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("读取存档失败: $e")));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请输入任务内容或选择弱势学科")));
      return;
    }

    setState(() {
      _isLoading = true;
      _itinerary = "";
    });

    try {
      final dateStr =
          "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}";

      if (Platform.isAndroid) {
        // 📱 Android：通过直连 AI API 生成日程
        final baseUrl = widget.directBaseUrl;
        final apiKey = widget.directApiKey;
        final model = widget.directModel;

        if (baseUrl == null || apiKey == null || model == null) {
          throw 'AI 配置不完整，请先在设置中配置 AI 服务';
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

        if (itinerary.isNotEmpty && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScheduleDetailPage(content: itinerary),
            ),
          );
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
          if (_itinerary.isNotEmpty && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ScheduleDetailPage(content: _itinerary),
              ),
            );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("生成失败: $e")));
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
    final dateDisplay =
        "${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日";

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "输入任务内容",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              hintText: "例如：\n早上 晨跑 @outdoor\n中午 整理文档 @indoor\n晚上 健身房",
              border: OutlineInputBorder(),
            ),
          ),

          // 学习弱项选择区域
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.1)),
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
                        if (_includeStudyAdvice && _availableSubjects.isEmpty) {
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
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            "选择你的弱势学科，AI将为你安排针对性的学习时间",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // 只有勾选了才显示学科选择
                if (_includeStudyAdvice) ...[
                  const SizedBox(height: 12),
                  if (_isFetchingSubjects)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (_availableSubjects.isEmpty)
                    const Text(
                      "暂无录入的学科，请先在'我的成绩'中录入",
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableSubjects.map((subject) {
                        final isSelected = _selectedWeakSubjects.contains(
                          subject,
                        );
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
                          selectedColor: Theme.of(context).primaryColor,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
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
                border: Border.all(color: Colors.blue.withValues(alpha: 0.1)),
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
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      if (_itinerary.isNotEmpty && mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ScheduleDetailPage(content: _itinerary),
                          ),
                        );
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
    );
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }
}

@Preview()
Widget homePreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
    home: MyHomePage(dio: Dio()),
  );
}
