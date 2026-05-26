import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/backend_utils.dart';

class HistoryPage extends StatefulWidget {
  final Dio dio;
  final Function(List<dynamic> messages, String summary)? onContinue;
  const HistoryPage({super.key, required this.dio, this.onContinue});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // 排序方式：true=正序(asc)，false=倒序(desc)
  bool _sortAscending = false;
  // 查询模式：false=单日模式，true=时间段模式
  bool _rangeMode = false;

  // 单日模式
  DateTime _selectedDate = DateTime.now();

  // 时间段模式
  DateTime _rangeStart = DateTime.now().subtract(const Duration(days: 7));
  DateTime _rangeEnd = DateTime.now();

  // 时间筛选（精确到小时）
  TimeOfDay? _startTime; // null 表示不限制起始时间
  TimeOfDay? _endTime; // null 表示不限制结束时间
  bool _timeFilterEnabled = false; // 是否启用时间筛选

  Map<String, dynamic> _historyList = {};
  bool _isLoading = false;
  List<String> _sortedKeys = [];

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  String _formatTime(TimeOfDay? t) {
    if (t == null) return '';
    return "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  /// 根据当前模式与排序发起请求（Android 直接读文件，PC 通过后端）
  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);

    final sortParam = _sortAscending ? 'asc' : 'desc';
    final startTimeStr = _timeFilterEnabled ? _formatTime(_startTime) : null;
    final endTimeStr = _timeFilterEnabled ? _formatTime(_endTime) : null;

    try {
      if (Platform.isAndroid) {
        // 📱 Android：从本地 backlog 文件读取
        final Map<String, dynamic> rawData;
        if (_rangeMode) {
          final rangeData = await loadBacklogForRange(
            startDate: _formatDate(_rangeStart),
            endDate: _formatDate(_rangeEnd),
            startTime: startTimeStr,
            endTime: endTimeStr,
            sort: sortParam,
          );
          // 展平：{ date: { filename: data } } -> { "date/filename": data }
          rawData = {};
          for (final dateEntry in rangeData.entries) {
            for (final fileEntry in dateEntry.value.entries) {
              rawData['${dateEntry.key}/${fileEntry.key}'] = fileEntry.value;
            }
          }
        } else {
          final dateData = await loadBacklogForDate(
            date: _formatDate(_selectedDate),
            startTime: startTimeStr,
            endTime: endTimeStr,
            sort: sortParam,
          );
          rawData = Map<String, dynamic>.from(dateData);
        }
        setState(() {
          _historyList = rawData;
          _updateSortedKeys();
        });
      } else {
        // 💻 PC：通过后端 API
        if (_rangeMode) {
          final startStr = _formatDate(_rangeStart);
          final endStr = _formatDate(_rangeEnd);
          final params = <String, dynamic>{
            'start_date': startStr,
            'end_date': endStr,
            'sort': sortParam,
          };
          if (startTimeStr != null) params['start_time'] = startTimeStr;
          if (endTimeStr != null) params['end_time'] = endTimeStr;
          final response = await widget.dio.get(
            '/history/range',
            queryParameters: params,
          );
          setState(() {
            if (response.data is Map && (response.data as Map).isNotEmpty) {
              _historyList = Map<String, dynamic>.from(response.data);
            } else {
              _historyList = {};
            }
            _updateSortedKeys();
          });
        } else {
          final dateStr = _formatDate(_selectedDate);
          final params = <String, dynamic>{'date': dateStr};
          if (startTimeStr != null) params['start_time'] = startTimeStr;
          if (endTimeStr != null) params['end_time'] = endTimeStr;
          final response = await widget.dio.get(
            '/history/list',
            queryParameters: params,
          );
          setState(() {
            if (response.data is Map && (response.data as Map).isNotEmpty) {
              _historyList = Map<String, dynamic>.from(response.data);
            } else {
              _historyList = {};
            }
            _updateSortedKeys();
          });
        }
      }
    } catch (e) {
      setState(() {
        _historyList = {};
        _updateSortedKeys();
      });
      debugPrint("获取历史记录失败: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 根据 _sortAscending 重新排序 _historyList 的键
  void _updateSortedKeys() {
    _sortedKeys = _historyList.keys.toList()
      ..sort((a, b) {
        final nameA = a.contains('/') ? a.split('/').last : a;
        final nameB = b.contains('/') ? b.split('/').last : b;
        return _sortAscending ? nameA.compareTo(nameB) : nameB.compareTo(nameA);
      });
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final current = isStart ? _rangeStart : _rangeEnd;
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _rangeStart = picked;
        } else {
          _rangeEnd = picked;
        }
      });
      _fetchHistory();
    }
  }

  Future<void> _pickSingleDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchHistory();
    }
  }

  Future<void> _pickTime(BuildContext context, bool isStart) async {
    final initial = isStart
        ? (_startTime ?? const TimeOfDay(hour: 0, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 23, minute: 59));
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? "选择开始时间" : "选择结束时间",
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
      _fetchHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 模式选择与日期选择栏（带阴影区分结果区）
        Material(
          elevation: 4,
          shadowColor: Colors.black26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 模式切换行 + 排序按钮
                Row(
                  children: [
                    const Icon(
                      Icons.date_range,
                      size: 20,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "查询模式：",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text("单日"),
                            icon: Icon(Icons.calendar_today, size: 16),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text("时间段"),
                            icon: Icon(Icons.view_week, size: 16),
                          ),
                        ],
                        selected: {_rangeMode},
                        onSelectionChanged: (selected) {
                          setState(() => _rangeMode = selected.first);
                          _fetchHistory();
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStateProperty.all(
                            const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                    // 排序按钮
                    IconButton(
                      icon: Icon(
                        _sortAscending
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                      ),
                      tooltip: _sortAscending ? "正序排列" : "倒序排列",
                      onPressed: () {
                        setState(() => _sortAscending = !_sortAscending);
                        _fetchHistory();
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 日期选择 + 时间选择（对齐各自日期下方）
                if (_rangeMode)
                  // 时间段模式：日期上下对齐时间
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickDate(context, true),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: "开始日期",
                                  prefixIcon: Icon(Icons.play_arrow, size: 18),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                                child: Text(
                                  _formatDate(_rangeStart),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              "～",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickDate(context, false),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: "结束日期",
                                  prefixIcon: Icon(
                                    Icons.fast_forward,
                                    size: 18,
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                                child: Text(
                                  _formatDate(_rangeEnd),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 时间筛选：对齐日期正下方
                      if (_timeFilterEnabled)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => _pickTime(context, true),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.deepPurple.shade200,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.schedule,
                                          size: 14,
                                          color: Colors.deepPurple.shade400,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatTime(_startTime),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.deepPurple.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  "~",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () => _pickTime(context, false),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.deepPurple.shade200,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.schedule,
                                          size: 14,
                                          color: Colors.deepPurple.shade400,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatTime(_endTime),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.deepPurple.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  // 单日模式
                  Column(
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.calendar_month,
                          color: Colors.deepPurple,
                        ),
                        title: const Text(
                          "查看指定日期记录",
                          style: TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          _formatDate(_selectedDate),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        trailing: const Icon(Icons.arrow_drop_down),
                        onTap: () => _pickSingleDate(context),
                      ),
                    ],
                  ),
                // 时间筛选开关行（始终显示在底部）
                const Divider(height: 12),
                Row(
                  children: [
                    SizedBox(
                      height: 28,
                      child: Switch(
                        value: _timeFilterEnabled,
                        onChanged: (v) {
                          setState(() => _timeFilterEnabled = v);
                          if (v && _startTime == null) {
                            _startTime = const TimeOfDay(hour: 0, minute: 0);
                          }
                          if (v && _endTime == null) {
                            _endTime = const TimeOfDay(hour: 23, minute: 59);
                          }
                          _fetchHistory();
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    Text(
                      _timeFilterEnabled ? "时间筛选" : "时间筛选(关)",
                      style: TextStyle(
                        fontSize: 12,
                        color: _timeFilterEnabled
                            ? Colors.deepPurple
                            : Colors.grey,
                        fontWeight: _timeFilterEnabled
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                // 时间段模式下在时间选择下方留间距
                if (_rangeMode && _timeFilterEnabled) const SizedBox(height: 4),
              ],
            ),
          ),
        ),
        // 记录列表
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _historyList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history_toggle_off,
                        size: 64,
                        color: Colors.grey.shade300,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _rangeMode
                            ? "${_formatDate(_rangeStart)} ~ ${_formatDate(_rangeEnd)} 暂无聊天记录"
                            : "${_formatDate(_selectedDate)} 暂无聊天记录",
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sortedKeys.length,
                  itemBuilder: (context, index) {
                    if (index >= _sortedKeys.length) {
                      return const SizedBox.shrink();
                    }
                    String fileKey = _sortedKeys[index];
                    dynamic data = _historyList[fileKey];

                    // 兼容新旧格式
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

                    // 从文件Key提取日期和时间
                    // 格式可能是 "2025-05-23/14-30-05.json" 或直接 "14-30-05.json"
                    final parts = fileKey.split('/');
                    String timeStr = parts.last
                        .replaceAll('.json', '')
                        .replaceAll('-', ':');
                    String datePrefix = parts.length > 1 ? parts[0] : "";

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ExpansionTile(
                        leading: const Icon(Icons.chat_outlined),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                summary.isNotEmpty
                                    ? summary
                                    : "对话开启时间: $timeStr",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (summary.isNotEmpty)
                              Text(
                                datePrefix.isNotEmpty
                                    ? "$datePrefix $timeStr"
                                    : timeStr,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text("本次对话共 ${messages.length} 条消息"),
                        trailing: TextButton(
                          child: const Text("继续"),
                          onPressed: () {
                            widget.onContinue?.call(messages, summary);
                          },
                        ),
                        children: messages.map<Widget>((msg) {
                          if (msg is! Map) return const SizedBox.shrink();
                          bool isUser = msg['role'] == 'user';
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: isUser
                                  ? Colors.transparent
                                  : Colors.grey.withValues(alpha: 0.05),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isUser
                                      ? Icons.person_outline
                                      : Icons.auto_awesome,
                                  size: 18,
                                  color: isUser ? Colors.blue : Colors.green,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SelectableText(
                                    msg['content'] ?? "",
                                    style: TextStyle(
                                      color: isUser
                                          ? Colors.black87
                                          : Colors.black,
                                      fontWeight: isUser
                                          ? FontWeight.normal
                                          : FontWeight.w500,
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
    );
  }
}
