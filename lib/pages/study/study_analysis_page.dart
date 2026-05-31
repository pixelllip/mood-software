import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/services/local_backend.dart';
import 'package:ai_agent/services/study_analysis_service.dart';
import 'package:flutter/widget_previews.dart';

/// 学习分析主页面
/// 包含「记录查询」和「学习总结」两个子界面
class StudyAnalysisPage extends StatefulWidget {
  final Dio? dio;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;

  const StudyAnalysisPage({
    super.key,
    this.dio,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
  });

  @override
  State<StudyAnalysisPage> createState() => _StudyAnalysisPageState();
}

class _StudyAnalysisPageState extends State<StudyAnalysisPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              KeepAliveWrapper(
                child: _RecordQueryTab(
                dio: widget.dio,
                useDirectApi: widget.useDirectApi,
                selectedDate: _selectedDate,
                onDateChanged: _pickDate,
              ),
              ),
              KeepAliveWrapper(
                child: _StudySummaryTab(
                dio: widget.dio,
                useDirectApi: widget.useDirectApi,
                directBaseUrl: widget.directBaseUrl,
                directApiKey: widget.directApiKey,
                directModel: widget.directModel,
                selectedDate: _selectedDate,
                onDateChanged: _pickDate,
              ),
              ),
            ],
          ),
        ),
        // 底部导航栏（TabBar 样式）
        Container(
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
            labelColor: isDark ? Colors.white : Theme.of(context).primaryColor,
            unselectedLabelColor: isDark ? Colors.grey.shade400 : Colors.grey,
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.search), text: "记录查询"),
              Tab(icon: Icon(Icons.summarize), text: "学习总结"),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================== 记录查询子页面 ====================

class _RecordQueryTab extends StatefulWidget {
  final Dio? dio;
  final bool useDirectApi;
  final DateTime selectedDate;
  final VoidCallback onDateChanged;
  const _RecordQueryTab({
    this.dio,
    this.useDirectApi = false,
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  State<_RecordQueryTab> createState() => _RecordQueryTabState();
}

class _RecordQueryTabState extends State<_RecordQueryTab> {
  List<MatchedConversation> _matchedResults = [];
  List<String> _keywords = [];
  final List<String> _customKeywords = [];
  final TextEditingController _keywordController = TextEditingController();
  bool _isLoading = false;
  bool _showKeywordEditor = false;

  @override
  void initState() {
    super.initState();
    _loadKeywords().then((_) => _doSearch());
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _loadKeywords() async {
    final defaults = await StudyAnalysisService.getDefaultKeywords();
    final customs = await StudyAnalysisService.getCustomKeywords();
    if (mounted) {
      setState(() {
        _keywords = defaults;
        _customKeywords.clear();
        _customKeywords.addAll(customs);
      });
    }
  }

  Future<void> _doSearch() async {
    setState(() => _isLoading = true);

    try {
      // 合并关键词：默认 + 自定义
      final allKeywords = <String>[..._keywords, ..._customKeywords];

      if (allKeywords.isEmpty) {
        setState(() {
          _matchedResults = [];
          _isLoading = false;
        });
        return;
      }

      final dateStr = "${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}";
      final results = await StudyAnalysisService.queryMatchedConversations(
        startDate: dateStr,
        endDate: dateStr,
        keywords: allKeywords,
      );

      if (mounted) {
        setState(() {
          _matchedResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(">>> 查询失败: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        showTopSnackBar(context, "查询失败: $e");
      }
    }
  }

  void _addCustomKeyword() {
    final text = _keywordController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _customKeywords.add(text);
      _keywordController.clear();
    });
    StudyAnalysisService.saveCustomKeywords(_customKeywords);
  }

  void _removeCustomKeyword(int index) {
    setState(() {
      _customKeywords.removeAt(index);
    });
    StudyAnalysisService.saveCustomKeywords(_customKeywords);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // 关键词编辑面板（可折叠）
        if (_showKeywordEditor)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey.shade900
                  : themeColor.withValues(alpha: 0.05),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  width: 0.5,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.keyboard, size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      "匹配关键词",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "共 ${_keywords.length + _customKeywords.length} 个",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 默认关键词标签
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _keywords.map((kw) {
                    return Chip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      label: Text(kw, style: const TextStyle(fontSize: 12)),
                      backgroundColor: themeColor.withValues(alpha: 0.1),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                // 自定义关键词
                if (_customKeywords.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: List.generate(_customKeywords.length, (i) {
                      return Chip(
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          _customKeywords[i],
                          style: const TextStyle(fontSize: 12),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => _removeCustomKeyword(i),
                      );
                    }),
                  ),
                const SizedBox(height: 6),
                // 添加自定义关键词
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _keywordController,
                          decoration: InputDecoration(
                            hintText: "添加自定义关键词",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onSubmitted: (_) => _addCustomKeyword(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, size: 22),
                      onPressed: _addCustomKeyword,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),

        // 操作栏：日期选择 + 关键词编辑切换 + 查询
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // 日期选择
              InkWell(
                onTap: widget.onDateChanged,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: themeColor.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: themeColor),
                      const SizedBox(width: 6),
                      Text(
                        "${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: themeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 关键词编辑切换
              IconButton(
                icon: Icon(
                  _showKeywordEditor
                      ? Icons.keyboard_alt
                      : Icons.keyboard_alt_outlined,
                  color: _showKeywordEditor ? themeColor : null,
                ),
                tooltip: "管理关键词",
                onPressed: () {
                  setState(() => _showKeywordEditor = !_showKeywordEditor);
                },
              ),
              const Spacer(),
              // 查询按钮
              ElevatedButton.icon(
                onPressed: _doSearch,
                icon: const Icon(Icons.search, size: 18),
                label: const Text("查询"),
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 查询结果列表
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _matchedResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "暂无匹配记录",
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "请选择日期并点击「查询」",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _matchedResults.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _matchedResults[index];
                    return _buildConversationCard(item, isDark, themeColor);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildConversationCard(
    MatchedConversation item,
    bool isDark,
    Color themeColor,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：时间 + 匹配关键词标签
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  item.time,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 8),
                ...item.matchedKeywords
                    .take(3)
                    .map(
                      (kw) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: themeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            kw,
                            style: TextStyle(fontSize: 10, color: themeColor),
                          ),
                        ),
                      ),
                    ),
                if (item.matchedKeywords.length > 3)
                  Text(
                    "+${item.matchedKeywords.length - 3}",
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // 用户消息
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                item.userMessage,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            // AI 回答（截取前200字）
            Text(
              item.aiResponse.length > 200
                  ? '${item.aiResponse.substring(0, 200)}...'
                  : item.aiResponse,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                "📌 $item.summary",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== 学习总结子页面 ====================

class _StudySummaryTab extends StatefulWidget {
  final Dio? dio;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  final DateTime selectedDate;
  final VoidCallback onDateChanged;

  const _StudySummaryTab({
    this.dio,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  State<_StudySummaryTab> createState() => _StudySummaryTabState();
}

class _StudySummaryTabState extends State<_StudySummaryTab> {
  DailyStudySummary? _summary;
  List<String> _keywords = [];
  bool _isEncouragementLoading = false;

  // 日程勾选
  List<_ScheduleItem> _scheduleItems = [];
  bool _showScheduleDialog = false;

  // 上次的等级，用于判断是否变化
  String? _lastGrade;
  String? _currentEncouragement;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final defaults = await StudyAnalysisService.getDefaultKeywords();
      final customs = await StudyAnalysisService.getCustomKeywords();
      _keywords = [...defaults, ...customs];

      // 先加载总结（本地数据，无需网络）
      await _refreshSummary();

      // 加载日程
      if (_scheduleItems.isEmpty && mounted) {
        await _loadScheduleItems();
        if (_scheduleItems.isNotEmpty && !_showScheduleDialog) {
          _showScheduleDialog = true;
          if (mounted) _showScheduleCheckDialog();
        }
      }

      // 再异步加载鼓励语（可能涉及AI/网络）
      if (mounted) _loadEncouragement();
    } catch (e) {
      debugPrint(">>> 加载学习总结失败: $e");
    }
  }

  /// 异步加载鼓励语（仅评语部分转圈）
  Future<void> _loadEncouragement() async {
    if (_summary == null || !mounted) return;
    setState(() => _isEncouragementLoading = true);

    try {
      final config = await loadConfigFile();
      final studentName = config['STUDENT_NAME']?.toString() ?? '同学';

      final encouragement =
          await StudyAnalysisService.generateEncouragementWithBackend(
            grade: _summary!.grade,
            studentName: studentName,
            matchedCount: _summary!.matchedCount,
            completedSchedules: _summary!.completedSchedules,
            totalSchedules: _summary!.totalSchedules,
            dio: widget.dio,
          );

      if (mounted) {
        setState(() {
          _currentEncouragement = encouragement;
          _lastGrade = _summary!.grade;
        });
      }
    } catch (e) {
      debugPrint(">>> 生成鼓励语失败: $e");
    } finally {
      if (mounted) setState(() => _isEncouragementLoading = false);
    }
  }

  String get _dateStr => "${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}";

  /// 加载当日日程列表（从日程文件解析）
  Future<void> _loadScheduleItems() async {
    try {
      final content = await LocalScheduleService.loadItinerary(_dateStr);

      if (content != null && content.isNotEmpty) {
        // 解析日程内容，提取任务项
        final items = <_ScheduleItem>[];
        final lines = content.split('\n');
        for (final line in lines) {
          // 匹配 Markdown 表格行或列表项中的任务描述
          final trimmed = line.trim();
          if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
            final cells = trimmed
                .split('|')
                .map((c) => c.trim())
                .where((c) => c.isNotEmpty)
                .toList();
            if (cells.length >= 2) {
              final task = cells.length >= 2 ? cells[1] : cells[0];
              if (task.isNotEmpty &&
                  !task.contains('时间') &&
                  !task.contains('任务') &&
                  !task.contains('地点') &&
                  !task.contains('---')) {
                items.add(_ScheduleItem(task: task));
              }
            }
          } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
            final task = trimmed.substring(2).trim();
            if (task.isNotEmpty && !task.startsWith('[')) {
              items.add(_ScheduleItem(task: task));
            }
          }
        }

        // 读取已保存的勾选状态
        final allSummaries = await StudyAnalysisService.loadAllSummaries();
        final saved = allSummaries[_dateStr];
        if (saved != null) {
          // 如果已有保存的完成数，恢复勾选状态
          // 勾选总数匹配时标记前 N 项为已完成
          int completed = 0;
          for (
            int i = 0;
            i < items.length && completed < saved.completedSchedules;
            i++
          ) {
            items[i].isCompleted = true;
            completed++;
          }
        }

        if (mounted) {
          setState(() => _scheduleItems = items);
        }
      }
    } catch (e) {
      debugPrint(">>> 加载日程失败: $e");
    }
  }

  /// 刷新总结
  Future<void> _refreshSummary() async {
    final dateStr = _dateStr;
    final completed = _scheduleItems.where((s) => s.isCompleted).length;

    // 先获取旧评级（在重新计算之前存档）
    final allExisting = await StudyAnalysisService.loadAllSummaries();
    final oldGrade = allExisting[dateStr]?.grade;

    final summary = await StudyAnalysisService.getOrComputeSummary(
      date: dateStr,
      keywords: _keywords,
      completedSchedules: completed,
      totalSchedules: _scheduleItems.length,
    );

    // 判断等级是否变化（对比旧评级）
    final gradeChanged = oldGrade != null && oldGrade != summary.grade;

    if (mounted) {
      setState(() {
        _summary = summary;
      });

      // 等级有变化时清除旧鼓励语（等待异步加载）
      if (gradeChanged) {
        setState(() => _currentEncouragement = null);
      }
    }
  }

  /// 显示日程勾选弹窗
  Future<void> _showScheduleCheckDialog() async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ScheduleCheckDialog(
        items: _scheduleItems,
        dateStr: _dateStr,
      ),
    );

    if (result == true && mounted) {
      _showScheduleDialog = false;
      await _refreshSummary();
    }
  }

  void _onDateChanged() {
    widget.onDateChanged();
    // 日期变化时重新加载
    setState(() {
      _summary = null;
      _scheduleItems = [];
      _currentEncouragement = null;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 日期选择
          Center(
            child: InkWell(
              onTap: _onDateChanged,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: themeColor.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month, size: 20, color: themeColor),
                    const SizedBox(width: 8),
                    Text(
                      "${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: themeColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: themeColor),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (_summary != null) ...[
            // 评分卡片
            _buildGradeCard(_summary!, isDark, themeColor),
            const SizedBox(height: 16),

            // 日程完成情况
            if (_scheduleItems.isNotEmpty) ...[
              _buildScheduleCard(isDark, themeColor),
              const SizedBox(height: 16),
            ],

            // 匹配记录数
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.chat, color: themeColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("关键词匹配记录", style: TextStyle(fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(
                            "当日有 ${_summary!.matchedCount} 条对话记录与学习关键词匹配",
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: _summary!.matchedCount > 0
                            ? themeColor.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${_summary!.matchedCount}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _summary!.matchedCount > 0
                                ? themeColor
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 鼓励语
            if (_isEncouragementLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else if (_currentEncouragement != null)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: themeColor.withValues(alpha: 0.05),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _summary!.grade == '优秀'
                            ? Icons.emoji_events
                            : _summary!.grade == '良好'
                            ? Icons.thumb_up
                            : _summary!.grade == '合格'
                            ? Icons.check_circle
                            : Icons.rocket_launch,
                        color: _gradeColor(_summary!.grade, themeColor),
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _currentEncouragement!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 重新勾选日程按钮
            if (_scheduleItems.isNotEmpty)
              Center(
                child: OutlinedButton.icon(
                  onPressed: _showScheduleCheckDialog,
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text("重新勾选完成的日程"),
                ),
              ),
          ],

          // 无数据时的提示
          if (_summary == null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.summarize_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "暂无学习总结数据",
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "请选择日期查看学习总结",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 评分卡片
  Widget _buildGradeCard(
    DailyStudySummary summary,
    bool isDark,
    Color themeColor,
  ) {
    final gradeColors = _gradeColor(summary.grade, themeColor);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              gradeColors.withValues(alpha: 0.15),
              gradeColors.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 大号等级图标
            Icon(
              summary.grade == '优秀'
                  ? Icons.emoji_events
                  : summary.grade == '良好'
                  ? Icons.thumb_up_alt
                  : summary.grade == '合格'
                  ? Icons.check_circle_outline
                  : Icons.trending_down,
              size: 56,
              color: gradeColors,
            ),
            const SizedBox(height: 12),
            Text(
              summary.grade,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: gradeColors,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _gradeDescription(summary.grade),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  /// 日程完成情况卡片
  Widget _buildScheduleCard(bool isDark, Color themeColor) {
    final completed = _scheduleItems.where((s) => s.isCompleted).length;
    final total = _scheduleItems.length;
    final rate = total > 0 ? completed / total : 0.0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note, color: themeColor),
                const SizedBox(width: 8),
                const Text(
                  "日程完成情况",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                Text(
                  "$completed/$total",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: rate,
                minHeight: 6,
                backgroundColor: Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: 8),
            ..._scheduleItems.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      item.isCompleted
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: item.isCompleted
                          ? Colors.green
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.task,
                        style: TextStyle(
                          fontSize: 12,
                          decoration: item.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.isCompleted
                              ? Colors.grey
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _gradeColor(String grade, Color themeColor) {
    switch (grade) {
      case '优秀':
        return Colors.amber;
      case '良好':
        return Colors.green;
      case '合格':
        return Colors.blue;
      case '不合格':
      default:
        return Colors.orange;
    }
  }

  String _gradeDescription(String grade) {
    switch (grade) {
      case '优秀':
        return '学习状态极佳，继续保持！';
      case '良好':
        return '表现不错，再接再厉！';
      case '合格':
        return '基本达标，尚需努力！';
      case '不合格':
      default:
        return '今日学习不足，明天加油！';
    }
  }
}

// ==================== 日程勾选弹窗 ====================

class _ScheduleItem {
  final String task;
  bool isCompleted;

  _ScheduleItem({required this.task, this.isCompleted = false});
}

class _ScheduleCheckDialog extends StatefulWidget {
  final List<_ScheduleItem> items;
  final String dateStr;

  const _ScheduleCheckDialog({required this.items, required this.dateStr});

  @override
  State<_ScheduleCheckDialog> createState() => _ScheduleCheckDialogState();
}

class _ScheduleCheckDialogState extends State<_ScheduleCheckDialog> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.checklist, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text("${widget.dateStr} 日程完成确认"),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.items.isEmpty
            ? const Text("今天暂无日程安排")
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("请勾选你已完成的任务："),
                  const SizedBox(height: 12),
                  ...widget.items.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    return CheckboxListTile(
                      value: item.isCompleted,
                      onChanged: (v) {
                        setState(() => item.isCompleted = v ?? false);
                      },
                      title: Text(
                        item.task,
                        style: TextStyle(
                          fontSize: 14,
                          decoration: item.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.isCompleted
                              ? Colors.grey
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text("取消"),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text("确认"),
        ),
      ],
    );
  }
}

/// TabBarView 切换时保持子页面存活，避免重建
class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}

// ==================== Widget Preview ====================

@Preview()
Widget studyAnalysisPagePreview() {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: Colors.deepPurple,
      useMaterial3: true,
      brightness: Brightness.light,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.deepPurple,
      useMaterial3: true,
      brightness: Brightness.dark,
    ),
    home: const Scaffold(body: StudyAnalysisPage()),
  );
}
