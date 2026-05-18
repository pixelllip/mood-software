import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

class HistoryPage extends StatefulWidget {
  final Dio dio;
  const HistoryPage({super.key, required this.dio});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<String> _dates = [];
  String? _selectedDate;
  Map<String, dynamic> _historyList = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchDates();
  }

  Future<void> _fetchDates() async {
    setState(() => _isLoading = true);
    try {
      final response = await widget.dio.get('/history/dates');
      setState(() {
        _dates = List<String>.from(response.data);
        if (_dates.isNotEmpty) {
          _selectedDate = _dates.first;
          _fetchHistoryForDate(_selectedDate!);
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("获取日期失败: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchHistoryForDate(String date) async {
    setState(() => _isLoading = true);
    try {
      final response = await widget.dio.get('/history/list', queryParameters: {'date': date});
      setState(() {
        if (response.data is Map) {
          _historyList = Map<String, dynamic>.from(response.data);
        } else {
          _historyList = {};
          debugPrint("历史记录返回格式异常: ${response.data}");
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("获取记录失败: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              const Text("选择日期: ", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              Expanded(
                child: _dates.isEmpty 
                  ? const Text("暂无日期可选", style: TextStyle(color: Colors.grey))
                  : DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedDate,
                      items: _dates.map((date) => DropdownMenuItem(value: date, child: Text(date))).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedDate = value);
                          _fetchHistoryForDate(value);
                        }
                      },
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _historyList.isEmpty
                  ? const Center(child: Text("该日期暂无记录"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _historyList.length,
                      itemBuilder: (context, index) {
                        dynamic messagesRaw = _historyList[fileKey];
                        if (messagesRaw is! List) {
                          return const SizedBox.shrink();
                        }
                        List<dynamic> messages = messagesRaw;
                        String time = fileKey.split('/').last.replaceAll('.json', '').replaceAll('-', ':');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: ExpansionTile(
                            title: Text("对话时间: $time"),
                            subtitle: Text("共 ${messages.length} 条消息"),
                            children: messages.map<Widget>((msg) {
                              if (msg is! Map) return const SizedBox.shrink();
                              bool isUser = msg['role'] == 'user';
                              return ListTile(
                                leading: Icon(isUser ? Icons.person : Icons.android, 
                                  color: isUser ? Colors.blue : Colors.green),
                                title: SelectableText(msg['content'] ?? ""),
                                subtitle: Text(isUser ? "用户" : "AI助手"),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
