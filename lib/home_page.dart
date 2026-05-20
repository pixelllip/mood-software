import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/score_result_page.dart';
import 'package:ai_agent/settings_page.dart';
import 'package:ai_agent/history_page.dart';
import 'package:flutter/widget_previews.dart';
import 'package:path_provider/path_provider.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.dio});
  final Dio dio;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 0;
  final GlobalKey<_HomeContentState> _homeContentKey = GlobalKey<_HomeContentState>();

  String userID = "未知学号";
  String userName = "未知用户";
  String? _currentChatSummary;

  final List<String> pageTitles = [
    "AI聊天",
    "我的成绩",
    "日程安排",
  ];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/.env');
      if (await file.exists()) {
        final content = await file.readAsString();
        final lines = content.split('\n');
        String? newID;
        String? newName;
        for (var line in lines) {
          final trimmedLine = line.trim();
          if (trimmedLine.contains('=') && !trimmedLine.startsWith('#')) {
            final parts = trimmedLine.split('=');
            if (parts.length >= 2) {
              final key = parts[0].trim();
              final value = parts.sublist(1).join('=').trim().replaceAll('"', '').replaceAll("'", "");
              if (key == 'STUDENT_ID') newID = value;
              if (key == 'STUDENT_NAME') newName = value;
            }
          }
        }
        if (mounted) {
          setState(() {
            if (newID != null && newID.isNotEmpty) userID = newID;
            if (newName != null && newName.isNotEmpty) userName = newName;
          });
        }
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
              accountName: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(userID),
              currentAccountPicture: const CircleAvatar(
                child: Icon(Icons.person),
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
            ),
            ListTile(
              leading: Icon(selectedIndex == 0 ? Icons.chat_bubble : Icons.chat_bubble_outline),
              title: const Text("AI聊天"),
              selected: selectedIndex == 0,
              onTap: () {
                onItemTapped(0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(selectedIndex == 1 ? Icons.analytics : Icons.analytics_outlined),
              title: const Text("我的成绩"),
              selected: selectedIndex == 1,
              onTap: () {
                onItemTapped(1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(selectedIndex == 2 ? Icons.event_note : Icons.event_note_outlined),
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
                  MaterialPageRoute(builder: (context) => SettingsPage(dio: widget.dio, userName: userName, userID: userID)),
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
          icon: Icon(selectedIndex == 1 ? Icons.analytics : Icons.analytics_outlined),
          label: const Text("我的成绩"),
        ),
        NavigationRailDestination(
          icon: Icon(selectedIndex == 2 ? Icons.event_note : Icons.event_note_outlined),
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
        title: Text(selectedIndex == 0 && _currentChatSummary != null 
            ? _currentChatSummary! 
            : pageTitles[selectedIndex]),
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
                  MaterialPageRoute(builder: (context) => HistoryPage(dio: widget.dio)),
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
          const SizedBox(width:10),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsPage(dio: widget.dio, userName: userName, userID: userID)),
              );
              _loadUserInfo(); // 刷新用户信息
            },
          ),
        ],
      ),
      drawer: isMobile ? buildDrawer() : null,
      drawerEdgeDragWidth: isMobile ? MediaQuery.of(context).size.width * 0.15 : null,
      body: isMobile
          ? IndexedStack(
              index: selectedIndex,
              children: [
                HomeContent(
                  key: _homeContentKey, 
                  dio: widget.dio,
                  onSummaryUpdate: (summary) {
                    setState(() {
                      _currentChatSummary = summary;
                    });
                  },
                ),
                ScorePage(dio: widget.dio),
                SchedulePage(dio: widget.dio, isActive: selectedIndex == 2),
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
                        onSummaryUpdate: (summary) {
                          setState(() {
                            _currentChatSummary = summary;
                          });
                        },
                      ),
                      ScorePage(dio: widget.dio),
                      SchedulePage(dio: widget.dio, isActive: selectedIndex == 2),
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
  const HomeContent({super.key, required this.dio, this.onSummaryUpdate});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final List<Map<String, dynamic>> _messages = [
    {"text": "你好！我是你的AI助手，有什么我可以帮你的吗？", "isUser": false}
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void resetChat() {
    setState(() {
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
      _messages.clear();
      for (var msg in historyMessages) {
        if (msg is Map) {
          bool isUser = msg['role'] == 'user';
          _messages.add({"text": msg['content'] ?? "", "isUser": isUser});
        }
      }
      // 如果历史对话最后一条是 AI 的消息，或者历史为空，保留默认的欢迎消息
      if (_messages.isEmpty || _messages.last["isUser"] == false) {
        _messages.insert(0, {"text": "你好！我是你的AI助手，有什么我可以帮你的吗？", "isUser": false});
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

    // 如果是第一条用户消息，生成摘要并更新 AppBar
    bool isFirstMessage = _messages.length <= 1; // 只有一条欢迎语或为空
    if (isFirstMessage && widget.onSummaryUpdate != null) {
      String summary = text.length > 20 ? "${text.substring(0, 20)}..." : text;
      widget.onSummaryUpdate!(summary);
    }

    setState(() {
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
      debugPrint("正在请求: ${widget.dio.options.baseUrl}/chat");
      
      // 构建历史上下文发送给后端，以便后端重置时间并生成摘要
      List<Map<String, dynamic>> historyToSend = [];
      for (int i = 0; i < _messages.length - 1; i++) {
        final msg = _messages[i];
        historyToSend.add({
          "role": msg["isUser"] ? "user" : "assistant",
          "content": msg["text"]
        });
      }

      final response = await widget.dio.post(
        "/chat",
        data: {
          "prompt": text,
          "history": historyToSend,
        },
        options: Options(responseType: ResponseType.stream),
      );

      final stream = response.data.stream as Stream<Uint8List>;
      
      await for (final chunk in stream.cast<List<int>>().transform(utf8.decoder)) {
        setState(() {
          _messages[aiMsgIndex]["text"] = (_messages[aiMsgIndex]["text"] as String) + chunk;
        });
        _scrollToBottom();
      }
    } catch (e) {
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
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                  ),
                  decoration: BoxDecoration(
                    color: isUser ? Theme.of(context).primaryColor : Colors.grey.shade200,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 0),
                      bottomRight: Radius.circular(isUser ? 0 : 16),
                    ),
                  ),
                  child: SelectableText(
                    msg["text"],
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
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

  Future<void> queryData() async {
    try {
      if (idController.text.isEmpty && nameController.text.isEmpty) {
        throw "请输入学生ID或姓名进行查询";
      }

      final dioInstance = widget.dio;
      Response res = await dioInstance.get(
        "/query",
        queryParameters: {
          "id": idController.text,
          "name": nameController.text,
        },
      );

      if (!mounted) return;

      if (res.data != null && res.data is Map) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScoreResultPage(
              userName: res.data["name"]?.toString() ?? "未知",
              scores: Map<String, dynamic>.from(res.data["scores"] ?? {}),
            ),
          ),
        );
      } else {
        throw "服务器返回数据格式不正确";
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
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
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

      final data = {
        "id": idController.text,
        "name": nameController.text,
        "scores": scoreList,
      };

      await widget.dio.post("/add", data: data);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("信息已成功添加到系统")),
      );

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("提交失败: $e")),
      );
    }
  }

  Future<void> _deleteData() async {
    if (idController.text.isEmpty && nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请输入学生ID或姓名以进行删除")),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("确定要删除该学生的信息吗？此操作不可撤销。"),
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
      await widget.dio.delete(
        "/delete",
        queryParameters: {
          "id": idController.text,
          "name": nameController.text,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("学生信息已成功删除")),
      );

      idController.clear();
      nameController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("删除失败: $e")),
      );
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
          TextField(
            controller: idController,
            decoration: const InputDecoration(
              labelText: '输入学生id',
              hintText: '在这里输入学生id...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: '输入学生姓名',
              hintText: '在这里输入学生姓名...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: queryData,
              child: const Text('查询成绩'),
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
            const Text("基本信息", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                const Text("科目成绩", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                child: Text("暂无成绩项，请点击上方“添加项”开始录入", style: TextStyle(color: Colors.grey)),
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
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
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
          const Text("删除信息", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text("请提供学生ID或姓名进行信息注销：", style: TextStyle(color: Colors.grey)),
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
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _deleteData,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white,
              ),
              child: const Text('确认删除'),
            ),
          ),
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
                  color: Colors.black.withOpacity(0.05),
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
                Tab(
                  icon: Icon(Icons.search),
                  text: "查询",
                ),
                Tab(
                  icon: Icon(Icons.add_circle_outline),
                  text: "录入",
                ),
                Tab(
                  icon: Icon(Icons.delete_outline),
                  text: "删除",
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedFuncIndex,
              children: [
                _buildSearchUI(),
                _buildAddUI(),
                _buildDeleteUI(),
              ],
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
  const SchedulePage({super.key, required this.dio, this.isActive = false});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final TextEditingController _taskController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  String _itinerary = "";
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _autoLoad();
    }
  }

  @override
  void didUpdateWidget(SchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 关键：当 isActive 从 false 变为 true 时，说明用户切换到了本页
    if (widget.isActive && !oldWidget.isActive) {
      _autoLoad();
    }
  }

  void _autoLoad() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchSavedSchedule();
    });
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
    setState(() {
      _isLoading = true;
      _itinerary = "";
    });

    try {
      final dioInstance = widget.dio;
      final dateStr = "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}";
      final response = await dioInstance.post(
        "/schedule",
        data: {
          "tasks": "", // 传空任务表示仅尝试读取存档
          "date": dateStr,
        },
      );
      
      setState(() {
        _itinerary = response.data["itinerary"]?.toString() ?? "无内容";
      });
      
      if (response.data["from_cache"] != true && _itinerary.contains("暂无存档")) {
         // 说明没找到，提示用户
      } else if (response.data["from_cache"] == true) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text("成功加载 $dateStr 的本地存档")),
         );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("读取存档失败: $e")),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _generateSchedule() async {
    if (_taskController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("请输入任务内容")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _itinerary = "";
    });

    try {
      final dioInstance = widget.dio;
      final dateStr = "${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}";
      final response = await dioInstance.post(
        "/schedule",
        data: {
          "tasks": _taskController.text,
          "city": "440100",
          "date": dateStr,
        },
      );
      
      if (response.data != null && response.data is Map) {
        setState(() {
          _itinerary = response.data["itinerary"]?.toString() ?? "服务器返回内容为空";
        });
      } else {
        setState(() {
          _itinerary = "服务器返回数据格式错误";
        });
      }
    } catch (e) {
      debugPrint("生成日程出错: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("生成失败: $e")),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateDisplay = "${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日";

    return Padding(
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
          if (_itinerary.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.withOpacity(0.1)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 这里使用 Markdown 解析器会更好，如果没有引入，先用 SelectableText 处理简单的换行
                      SelectableText(
                        _itinerary,
                        style: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
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
