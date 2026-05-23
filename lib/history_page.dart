import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class HistoryPage extends StatefulWidget {
  final Dio dio;
  const HistoryPage({super.key, required this.dio});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<String> _availableDates = [];
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic> _historyList = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    await _fetchAvailableDates();
    // 默认加载今天的记录，如果没有则不强制加载
    _fetchHistoryForDate(_selectedDate);
  }

  Future<void> _fetchAvailableDates() async {
    try {
      final response = await widget.dio.get('/history/dates');
      setState(() {
        _availableDates = List<String>.from(response.data);
      });
    } catch (e) {
      debugPrint("获取历史日期列表失败: $e");
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      // 这里的快捷样式会让用户一眼看出哪些天有记录（可选优化）
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchHistoryForDate(picked);
    }
  }

  Future<void> _fetchHistoryForDate(DateTime date) async {
    setState(() => _isLoading = true);
    // 格式化为后端文件夹名格式：YYYY-MM-DD (带补零)
    String year = date.year.toString();
    String month = date.month.toString().padLeft(2, '0');
    String day = date.day.toString().padLeft(2, '0');
    String dateStr = "$year-$month-$day";
    
    try {
      final response = await widget.dio.get('/history/list', queryParameters: {'date': dateStr});
      setState(() {
        if (response.data is Map && (response.data as Map).isNotEmpty) {
          _historyList = Map<String, dynamic>.from(response.data);
        } else {
          _historyList = {};
        }
      });
    } catch (e) {
      setState(() => _historyList = {});
      debugPrint("该日期无记录或获取失败: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String dateDisplay = "${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日";
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("历史对话记录"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Material(
            elevation: 2,
            child: ListTile(
              leading: const Icon(Icons.calendar_month, color: Colors.deepPurple),
              title: const Text("查看指定日期记录"),
              subtitle: Text(dateDisplay, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.arrow_drop_down),
              onTap: () => _selectDate(context),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _historyList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text("$dateDisplay 暂无聊天记录", style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _historyList.length,
                        itemBuilder: (context, index) {
                          String fileKey = _historyList.keys.elementAt(index);
                          dynamic data = _historyList[fileKey];
                          
                          // 兼容新旧格式：新格式是 Map {messages: [...], summary: "..."}，旧格式是 List
                          List<dynamic> messages = [];
                          String summary = "";
                          
                          if (data is Map && data.containsKey('messages')) {
                            messages = data['messages'] as List<dynamic>;
                            summary = data['summary']?.toString() ?? "";
                          } else if (data is List) {
                            messages = data;
                          } else {
                            return const SizedBox.shrink();
                          }
                          
                          // 提取时间部分 (例如从 2024-5-20/14-30-05.json 提取 14:30:05)
                          String time = fileKey.split('/').last.replaceAll('.json', '').replaceAll('-', ':');

                          return Card(
                            margin: const EdgeInsets.only(bottom: 16),
                            child: ExpansionTile(
                              leading: const Icon(Icons.chat_outlined),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      summary.isNotEmpty ? summary : "对话开启时间: $time",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (summary.isNotEmpty)
                                    Text(
                                      time,
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                              subtitle: Text("本次对话共 ${messages.length} 条消息"),
                              trailing: TextButton(
                                child: const Text("继续"),
                                onPressed: () {
                                  Navigator.pop(context, {
                                    "messages": messages, 
                                    "fileKey": fileKey,
                                    "summary": summary,
                                  });
                                },
                              ),
                              children: messages.map<Widget>((msg) {
                                if (msg is! Map) return const SizedBox.shrink();
                                bool isUser = msg['role'] == 'user';
                                return Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                  decoration: BoxDecoration(
                                    color: isUser ? Colors.transparent : Colors.grey.withValues(alpha: 0.05),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(isUser ? Icons.person_outline : Icons.auto_awesome, 
                                        size: 18, 
                                        color: isUser ? Colors.blue : Colors.green),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: SelectableText(
                                          msg['content'] ?? "",
                                          style: TextStyle(
                                            color: isUser ? Colors.black87 : Colors.black,
                                            fontWeight: isUser ? FontWeight.normal : FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
