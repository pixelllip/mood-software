import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/score_result_page.dart';
import 'package:ai_agent/settings_page.dart';
import 'package:ai_agent/history_page.dart';
import 'package:flutter/widget_previews.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.dio});
  final Dio dio;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 0;

  final String userID = "3124004360";
  final String userName = "Ri Freez";

  final List<String> pageTitles = [
    "AI聊天",
    "我的成绩",
    "日程安排",
    "历史记录",
  ];

  late List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      HomeContent(dio: widget.dio),
      ScorePage(dio: widget.dio),
      const SchedulePage(),
      HistoryPage(dio: widget.dio),
    ];
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
            ListTile(
              leading: Icon(selectedIndex == 3 ? Icons.history : Icons.history_outlined),
              title: const Text("历史记录"),
              selected: selectedIndex == 3,
              onTap: () {
                onItemTapped(3);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("设置"),
              onTap: () {
                Navigator.pop(context); // Close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsPage(dio: widget.dio)),
                );
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
        NavigationRailDestination(
          icon: Icon(selectedIndex == 3 ? Icons.history : Icons.history_outlined),
          label: const Text("历史记录"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = MediaQuery.of(context).size.width < 700;

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitles[selectedIndex]),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsPage(dio: widget.dio)),
              );
            },
          ),
        ],
      ),
      drawer: isMobile ? buildDrawer() : null,
      drawerEdgeDragWidth: isMobile ? MediaQuery.of(context).size.width * 0.15 : null,
      body: isMobile
          ? IndexedStack(
              index: selectedIndex,
              children: pages,
            )
          : Row(
              children: [
                buildRail(),
                const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(
                    index: selectedIndex,
                    children: pages,
                  ),
                ),
              ],
            ),
    );
  }
}

class HomeContent extends StatefulWidget {
  final Dio dio;
  const HomeContent({super.key, required this.dio});

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> {
  final List<Map<String, dynamic>> _messages = [
    {"text": "你好！我是你的AI助手，有什么我可以帮你的吗？", "isUser": false}
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

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
      final response = await widget.dio.post(
        "/chat",
        data: {"prompt": text},
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
      Response res = await widget.dio.get(
        "/query",
        queryParameters: {
          "id": idController.text,
          "name": nameController.text,
        },
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ScoreResultPage(
            userName: res.data["name"],
            scores: res.data["scores"],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("查询失败: $e")),
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

  List<NavigationRailDestination> funcDestinations() {
    return const [
      NavigationRailDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: Text('查询成绩')),
      NavigationRailDestination(
          icon: Icon(Icons.add_outlined),
          selectedIcon: Icon(Icons.add),
          label: Text('添加信息')),
      NavigationRailDestination(
          icon: Icon(Icons.delete_outlined),
          selectedIcon: Icon(Icons.delete),
          label: Text('删除信息')),
    ];
  }

  Widget _buildSearchUI() {
    return Padding(
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
    return Padding(
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
    Widget content;
    switch (_selectedFuncIndex) {
      case 0:
        content = _buildSearchUI();
        break;
      case 1:
        content = _buildAddUI();
        break;
      case 2:
        content = _buildDeleteUI();
        break;
      default:
        content = _buildSearchUI();
    }

    return Row(
      children: [
        NavigationRail(
          destinations: funcDestinations(),
          selectedIndex: _selectedFuncIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedFuncIndex = index;
            });
          },
          labelType: NavigationRailLabelType.all,
        ),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ],
    );
  }
}

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text("日程安排页面", style: TextStyle(fontSize: 24)),
    );
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
