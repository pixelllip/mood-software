import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/services/local_backend.dart';
import 'package:ai_agent/services/study_analysis_service.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// 每日学情主页面
/// 包含「足迹」「笔记」「总结」三个子界面
class StudyAnalysisPage extends StatefulWidget {
  final Dio? dio;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  final bool isActive;

  const StudyAnalysisPage({
    super.key,
    this.dio,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
    this.isActive = false,
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
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
                child: _AutoNotesTab(
                  key: ValueKey(
                    "auto_notes_${_selectedDate.toIso8601String().split('T')[0]}",
                  ),
                  dio: widget.dio,
                  useDirectApi: widget.useDirectApi,
                  selectedDate: _selectedDate,
                  onDateChanged: _pickDate,
                  directBaseUrl: widget.directBaseUrl,
                  directApiKey: widget.directApiKey,
                  directModel: widget.directModel,
                  isActive: widget.isActive,
                ),
              ),
              _StudyNotesTab(),
              KeepAliveWrapper(
                child: _TodaySummaryTab(
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
              Tab(icon: Icon(Icons.explore), text: "足迹"),
              Tab(icon: Icon(Icons.note_alt), text: "笔记"),
              Tab(icon: Icon(Icons.summarize), text: "总结"),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================== 自动笔记子页面 ====================

class _AutoNotesTab extends StatefulWidget {
  final Dio? dio;
  final bool useDirectApi;
  final DateTime selectedDate;
  final VoidCallback onDateChanged;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  final bool isActive;
  const _AutoNotesTab({
    super.key,
    this.dio,
    this.useDirectApi = false,
    required this.selectedDate,
    required this.onDateChanged,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
    this.isActive = false,
  });

  @override
  State<_AutoNotesTab> createState() => _AutoNotesTabState();
}

class _AutoNotesTabState extends State<_AutoNotesTab> {
  List<MatchedConversation> _matchedResults = [];
  List<String> _keywords = [];
  final List<String> _customKeywords = [];
  final TextEditingController _keywordController = TextEditingController();
  bool _isLoading = false;
  bool _isGenerating = false;
  bool _showKeywordEditor = false;

  /// 上次搜索参数签名，避免条件不变时重复自动搜索
  int _lastSearchSignature = 0;

  @override
  void initState() {
    super.initState();
    _loadKeywords().then((_) {
      if (mounted && widget.isActive) _autoSearchIfChanged();
    });
  }

  @override
  void didUpdateWidget(covariant _AutoNotesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 首次激活或日期变化时自动搜索
    final justActivated = !oldWidget.isActive && widget.isActive;
    if (justActivated || oldWidget.selectedDate != widget.selectedDate) {
      _loadKeywords().then((_) {
        if (mounted) _autoSearchIfChanged();
      });
    }
  }

  /// 搜索条件不变且无新增对话时跳过自动搜索
  void _autoSearchIfChanged() {
    if (!mounted) return;
    final kwSig = Object.hashAll([..._keywords, ..._customKeywords]);
    final dateSig = widget.selectedDate.toIso8601String().split('T')[0];
    final sig = Object.hash(dateSig, kwSig);
    if (sig == _lastSearchSignature && _matchedResults.isNotEmpty) return;
    _lastSearchSignature = sig;
    _doSearch();
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
    if (!mounted) return;
    // 预捕获 SnackBar 参数（避免 async 后使用 context）
    final msgCenter = ScaffoldMessenger.of(context);
    final padBottom = MediaQuery.of(context).padding.bottom;
    final isMobileMode = MediaQuery.of(context).size.width < 450;
    final screenWidth = MediaQuery.of(context).size.width;

    showTopSnackBarWithState(
      messenger: msgCenter,
      message: "正在查询匹配记录...",
      bottomPadding: padBottom,
      isMobile: isMobileMode,
      screenWidth: screenWidth,
      bottomMargin: 82,
    );
    setState(() => _isLoading = true);

    try {
      // 合并关键词：默认 + 自定义（去重）
      final allKeywords = <String>{..._keywords, ..._customKeywords}.toList();

      if (allKeywords.isEmpty) {
        setState(() {
          _matchedResults = [];
          _isLoading = false;
        });
        return;
      }

      final dateStr =
          "${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}";

      // 有 dio 时走后端 API（支持 AI 联想词扩展），否则走本地查询
      final results = await StudyAnalysisService.queryWithBackend(
        startDate: dateStr,
        endDate: dateStr,
        keywords: allKeywords,
        dio: widget.useDirectApi ? null : widget.dio,
        useAiExpansion: true,
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
        showTopSnackBarWithState(
          messenger: msgCenter,
          message: "查询失败: $e",
          bottomPadding: padBottom,
          isMobile: isMobileMode,
          screenWidth: screenWidth,
          bottomMargin: 82,
        );
      }
    }
  }

  /// 一键生成笔记：将匹配的问答对转为简短笔记
  Future<void> _generateNotes() async {
    if (_matchedResults.isEmpty) {
      // 先自动搜索
      await _doSearch();
      if (!mounted || _matchedResults.isEmpty) return;
    }

    setState(() => _isGenerating = true);
    // 预捕获 SnackBar 参数（避免 async 后使用 context）
    final genMessenger = ScaffoldMessenger.of(context);
    final genPadding = MediaQuery.of(context).padding.bottom;
    final genIsMobile = MediaQuery.of(context).size.width < 450;
    final genScreenWidth = MediaQuery.of(context).size.width;

    try {
      int createdCount = 0;
      for (final match in _matchedResults) {
        if (!mounted) break;

        // 从匹配关键词推断科目
        final matchedKeywords = match.matchedKeywords;
        String subject = '';
        if (matchedKeywords.isNotEmpty) {
          // 取第一个可能是科目名的关键词
          final knownSubjects = [
            '数学',
            '英语',
            '语文',
            '物理',
            '化学',
            '生物',
            '历史',
            '地理',
            '政治',
            '科学',
            '编程',
            '计算机',
          ];
          for (final kw in matchedKeywords) {
            if (knownSubjects.contains(kw)) {
              subject = kw;
              break;
            }
          }
          if (subject.isEmpty) subject = matchedKeywords.first;
        }

        // 用用户问题做标题，AI回答做内容
        final title = match.userMessage.length > 40
            ? '${match.userMessage.substring(0, 40)}...'
            : match.userMessage;

        final content =
            '## Q: ${match.userMessage}\n\n'
            '> 时间: ${match.date} ${match.time}\n\n'
            '**A:** ${match.aiResponse}'
            '${match.summary.isNotEmpty ? "\n\n---\n📌 $match.summary" : ""}'
            '${matchedKeywords.isNotEmpty ? "\n\n标签: ${matchedKeywords.join(", ")}" : ""}';

        final note = NoteEntry(
          title: title,
          content: content,
          subject: subject,
          tags: matchedKeywords,
        );
        await NoteService.addNote(note);
        createdCount++;
      }

      if (!mounted) return;

      if (createdCount > 0) {
        showTopSnackBarWithState(
          messenger: genMessenger,
          message: "已生成 $createdCount 条笔记",
          bottomPadding: genPadding,
          isMobile: genIsMobile,
          screenWidth: genScreenWidth,
          bottomMargin: 82,
        );
      }
    } catch (e) {
      debugPrint(">>> 生成笔记失败: $e");
      if (mounted) {
        showTopSnackBarWithState(
          messenger: genMessenger,
          message: "生成笔记失败: $e",
          bottomPadding: genPadding,
          isMobile: genIsMobile,
          screenWidth: genScreenWidth,
          bottomMargin: 82,
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
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

  Future<void> _discoverKeywords() async {
    // 预捕获 SnackBar 参数（避免 async 后使用 context）
    final msgCenter = ScaffoldMessenger.of(context);
    final padBottom = MediaQuery.of(context).padding.bottom;
    final isMobileMode = MediaQuery.of(context).size.width < 450;
    final screenWidth = MediaQuery.of(context).size.width;

    showTopSnackBarWithState(
      messenger: msgCenter,
      message: "正在扫描对话记录，发现学习关键词...",
      bottomPadding: padBottom,
      isMobile: isMobileMode,
      screenWidth: screenWidth,
      bottomMargin: 82,
    );
    setState(() => _isLoading = true);

    try {
      final List<String> discovered;

      if (widget.useDirectApi &&
          widget.directBaseUrl != null &&
          widget.directApiKey != null &&
          widget.directModel != null) {
        // 📱 手机端直连模式 + AI 可用 → 用 AI 分析对话提取关键词
        discovered =
            await StudyAnalysisService.discoverKeywordsFromBacklogWithAI(
              baseUrl: widget.directBaseUrl!,
              apiKey: widget.directApiKey!,
              model: widget.directModel!,
              days: 7,
            );
      } else if (widget.useDirectApi || widget.dio == null) {
        // 📱 手机端直连模式但无 AI 配置 → 回退本地规则匹配
        discovered = await StudyAnalysisService.discoverKeywordsFromBacklog(
          days: 7,
        );
      } else {
        // 💻 PC 模式：通过后端 API
        discovered = await StudyAnalysisService.discoverKeywordsFromBackend(
          dio: widget.dio!,
          days: 7,
        );
      }
      if (!mounted) return;

      if (discovered.isEmpty) {
        showTopSnackBarWithState(
          messenger: msgCenter,
          message: "未发现新的学习关键词",
          bottomPadding: padBottom,
          isMobile: isMobileMode,
          screenWidth: screenWidth,
          bottomMargin: 82,
        );
        return;
      }

      // 过滤掉已有的关键词
      final existing = {..._keywords, ..._customKeywords};
      final newKeywords = discovered
          .where((k) => !existing.contains(k))
          .toList();

      if (newKeywords.isEmpty) {
        showTopSnackBarWithState(
          messenger: msgCenter,
          message: "发现 ${discovered.length} 个关键词，但都已存在",
          bottomPadding: padBottom,
          isMobile: isMobileMode,
          screenWidth: screenWidth,
          bottomMargin: 82,
        );
        return;
      }

      // 自动添加所有新发现的关键词
      setState(() {
        _customKeywords.addAll(newKeywords);
      });
      StudyAnalysisService.saveCustomKeywords(_customKeywords);

      // 显示关联结果通知
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.auto_awesome, size: 20),
                SizedBox(width: 8),
                Text("关键词发现完成", style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("已发现 ${newKeywords.length} 个学习关键词并自动添加："),
                const SizedBox(height: 8),
                Text(
                  newKeywords.join("、"),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "已自动关联到已有学科缓存中，搜索时将能匹配到更多相关记录。",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("知道了"),
              ),
            ],
          ),
        ).then((_) {
          if (mounted) _doSearch();
        });
      }
    } catch (e) {
      debugPrint(">>> 发现关键词失败: $e");
      if (mounted) {
        showTopSnackBarWithState(
          messenger: msgCenter,
          message: "发现关键词失败: $e",
          bottomPadding: padBottom,
          isMobile: isMobileMode,
          screenWidth: screenWidth,
          bottomMargin: 82,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                const SizedBox(height: 6),
                // 从对话中发现关键词
                if (widget.dio != null)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _discoverKeywords,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(
                        _isLoading ? "分析中..." : "从对话中发现关键词",
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
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

        // 查询结果 + 一键生成笔记
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
              : Column(
                  children: [
                    // 操作栏：匹配数 + 一键生成
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Text(
                            "匹配 ${_matchedResults.length} 条问答",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: _isGenerating ? null : _generateNotes,
                            icon: _isGenerating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.auto_stories, size: 18),
                            label: Text(_isGenerating ? "生成中..." : "一键生成笔记"),
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 问答列表
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 1000;
                          if (isWide) {
                            return ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: (_matchedResults.length + 1) ~/ 2,
                              itemBuilder: (context, rowIndex) {
                                final firstIdx = rowIndex * 2;
                                final secondIdx = firstIdx + 1;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: firstIdx < _matchedResults.length
                                            ? _buildConversationCard(
                                                _matchedResults[firstIdx],
                                                isDark,
                                                themeColor,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child:
                                            secondIdx < _matchedResults.length
                                            ? _buildConversationCard(
                                                _matchedResults[secondIdx],
                                                isDark,
                                                themeColor,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _matchedResults.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _matchedResults[index];
                              return _buildConversationCard(
                                item,
                                isDark,
                                themeColor,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 打开问答详情页（类聊天格式，支持 Markdown + LaTeX）
  void _openConversationDetail(MatchedConversation item) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text("${item.date} ${item.time}"),
            backgroundColor: theme.colorScheme.inversePrimary,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 匹配关键词标签
              if (item.matchedKeywords.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 6,
                    children: item.matchedKeywords
                        .map(
                          (kw) => Chip(
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            label: Text(
                              kw,
                              style: const TextStyle(fontSize: 11),
                            ),
                            backgroundColor: theme.colorScheme.primary
                                .withValues(alpha: 0.1),
                          ),
                        )
                        .toList(),
                  ),
                ),
              // 用户消息气泡
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(
                      16,
                    ).copyWith(bottomRight: Radius.zero),
                  ),
                  child: SelectableText(
                    item.userMessage,
                    style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              // AI 回复气泡（Markdown + LaTeX）
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.8,
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(
                      16,
                    ).copyWith(bottomLeft: Radius.zero),
                  ),
                  child: SelectionArea(
                    child: MarkdownBody(
                      data: item.aiResponse,
                      selectable: false,
                      inlineSyntaxes: [_MathInlineSyntax()],
                      builders: {
                        'math': _MathElementBuilder(
                          textColor: isDark ? Colors.white : Colors.black87,
                        ),
                      },
                      styleSheet: _markdownStyle(isDark),
                    ),
                  ),
                ),
              ),
              // 对话摘要
              if (item.summary.isNotEmpty)
                Card(
                  color: theme.colorScheme.tertiaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.summarize,
                          size: 18,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.summary,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openConversationDetail(item),
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
        ), // close InkWell
      ),
    );
  }
}

// ==================== 学习总结子页面 ====================

class _TodaySummaryTab extends StatefulWidget {
  final Dio? dio;
  final bool useDirectApi;
  final String? directBaseUrl;
  final String? directApiKey;
  final String? directModel;
  final DateTime selectedDate;
  final VoidCallback onDateChanged;

  const _TodaySummaryTab({
    this.dio,
    this.useDirectApi = false,
    this.directBaseUrl,
    this.directApiKey,
    this.directModel,
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  State<_TodaySummaryTab> createState() => _TodaySummaryTabState();
}

class _TodaySummaryTabState extends State<_TodaySummaryTab> {
  int _todayNoteCount = 0;
  bool _isLoading = true;
  String? _encouragement;
  bool _isEncouragementLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(covariant _TodaySummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 日期变化时重新刷新总结
    if (oldWidget.selectedDate != widget.selectedDate) {
      _loadData();
    }
  }

  String get _dateStr =>
      "${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}";

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final allNotes = await NoteService.loadNotes();
      _todayNoteCount = allNotes.where((n) {
        final d =
            "${n.createdAt.year}-${n.createdAt.month.toString().padLeft(2, '0')}-${n.createdAt.day.toString().padLeft(2, '0')}";
        return d == _dateStr;
      }).length;
      if (mounted) setState(() => _isLoading = false);
      if (mounted) _loadEncouragement();
    } catch (e) {
      debugPrint(">>> 加载今日总结失败: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _grade {
    if (_todayNoteCount >= 5) return '优秀';
    if (_todayNoteCount >= 3) return '良好';
    if (_todayNoteCount >= 1) return '合格';
    return '不合格';
  }

  String get _gradeDescription {
    switch (_grade) {
      case '优秀':
        return '今日笔记丰富，学习状态极佳！';
      case '良好':
        return '有效笔记不错，再接再厉！';
      case '合格':
        return '有笔记记录，继续保持！';
      default:
        return '今日暂无笔记，试试自动笔记吧';
    }
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case '优秀':
        return Colors.amber;
      case '良好':
        return Colors.green;
      case '合格':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  Future<void> _loadEncouragement() async {
    setState(() => _isEncouragementLoading = true);
    try {
      final config = await loadConfigFile();
      final studentName = config['STUDENT_NAME']?.toString() ?? '同学';
      _encouragement =
          await StudyAnalysisService.generateEncouragementWithBackend(
            grade: _grade,
            studentName: studentName,
            matchedCount: _todayNoteCount,
            completedSchedules: 0,
            totalSchedules: 0,
            dio: widget.useDirectApi ? null : widget.dio,
          );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint(">>> 加载鼓励语失败: $e");
    } finally {
      if (mounted) setState(() => _isEncouragementLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = Theme.of(context).colorScheme.primary;

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final gradeColor = _gradeColor(_grade);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: InkWell(
              onTap: widget.onDateChanged,
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
                      _dateStr,
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
          _buildGradeCardSimple(gradeColor),
          const SizedBox(height: 16),
          _buildNoteCountCard(themeColor),
          const SizedBox(height: 16),
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
          else if (_encouragement != null)
            _buildEncouragementCard(isDark, themeColor, gradeColor),
        ],
      ),
    );
  }

  Widget _buildGradeCardSimple(Color gradeColor) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              gradeColor.withValues(alpha: 0.15),
              gradeColor.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              _grade == '优秀'
                  ? Icons.emoji_events
                  : _grade == '良好'
                  ? Icons.thumb_up_alt
                  : _grade == '合格'
                  ? Icons.check_circle_outline
                  : Icons.trending_down,
              size: 56,
              color: gradeColor,
            ),
            const SizedBox(height: 12),
            Text(
              _grade,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: gradeColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _gradeDescription,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteCountCard(Color themeColor) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.note_alt, color: themeColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("有效笔记数", style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    "今日共创建 $_todayNoteCount 条学习笔记",
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _todayNoteCount > 0
                    ? themeColor.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$_todayNoteCount',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _todayNoteCount > 0 ? themeColor : Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncouragementCard(
    bool isDark,
    Color themeColor,
    Color gradeColor,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? gradeColor.withValues(alpha: 0.3)
              : gradeColor.withValues(alpha: 0.4),
          width: 0.5,
        ),
      ),
      color: isDark
          ? gradeColor.withValues(alpha: 0.12)
          : gradeColor.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: gradeColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              _grade == '优秀'
                  ? Icons.emoji_events
                  : _grade == '良好'
                  ? Icons.thumb_up
                  : _grade == '合格'
                  ? Icons.check_circle
                  : Icons.rocket_launch,
              color: gradeColor,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _encouragement!,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleItem {
  final String task;
  bool isCompleted;

  _ScheduleItem({required this.task}) : isCompleted = false;
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

// ==================== 笔记子页面（主页面 Tab 1） ====================

class _StudyNotesTab extends StatefulWidget {
  const _StudyNotesTab();
  @override
  State<_StudyNotesTab> createState() => _StudyNotesTabState();
}

class _StudyNotesTabState extends State<_StudyNotesTab> {
  List<NoteEntry> _notes = [];
  List<NoteEntry> _filteredNotes = [];
  List<String> _subjects = [];
  String? _selectedSubject;
  String _searchQuery = '';
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);
    final notes = await NoteService.loadNotes();
    final subjects = await NoteService.getDistinctSubjects();
    if (mounted) {
      setState(() {
        _notes = notes;
        _subjects = subjects;
        _isLoading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    var result = List<NoteEntry>.from(_notes);
    if (_selectedSubject != null && _selectedSubject!.isNotEmpty) {
      result = result.where((n) => n.subject == _selectedSubject).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where(
            (n) =>
                n.title.toLowerCase().contains(q) ||
                n.content.toLowerCase().contains(q) ||
                n.tags.any((t) => t.toLowerCase().contains(q)),
          )
          .toList();
    }
    setState(() => _filteredNotes = result);
  }

  Future<void> _addOrEditNote({NoteEntry? existing}) async {
    final result = await Navigator.push<NoteEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => _NoteEditorPage(
          existingNote: existing,
          availableSubjects: _subjects,
        ),
      ),
    );
    if (result != null) {
      if (existing != null) {
        await NoteService.updateNote(result);
      } else {
        await NoteService.addNote(result);
      }
      await _loadNotes();
    }
  }

  /// 构建单条笔记卡片（供双列布局复用）
  Widget _buildNoteCard(NoteEntry note, Color themeColor) {
    final dateStr =
        "${note.updatedAt.year}-${note.updatedAt.month.toString().padLeft(2, '0')}-${note.updatedAt.day.toString().padLeft(2, '0')}";
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: themeColor.withValues(alpha: 0.15),
          child: Icon(Icons.article, color: themeColor, size: 20),
        ),
        title: Text(
          note.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (note.subject.isNotEmpty)
              Text(
                note.subject,
                style: TextStyle(fontSize: 12, color: themeColor),
              ),
            Text(
              dateStr,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit_outlined, size: 18, color: themeColor),
              onPressed: () => _addOrEditNote(existing: note),
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 18,
                color: Colors.red.shade300,
              ),
              onPressed: () => _deleteNote(note),
            ),
          ],
        ),
        onTap: () => _addOrEditNote(existing: note),
      ),
    );
  }

  Future<void> _deleteNote(NoteEntry note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定要删除笔记「${note.title}」吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("删除"),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await NoteService.deleteNote(note.id);
      await _loadNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        // 操作栏：搜索 + 筛选 + 添加
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              // 科目筛选
              if (_subjects.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedSubject,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                      isDense: true,
                      labelText: '科目',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text("全部", style: TextStyle(fontSize: 13)),
                      ),
                      ..._subjects.map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedSubject = v);
                      _applyFilter();
                    },
                  ),
                ),
              const SizedBox(width: 8),
              // 搜索
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索笔记...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                              _applyFilter();
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() => _searchQuery = v);
                    _applyFilter();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // 添加笔记
              FloatingActionButton.small(
                heroTag: 'add_note',
                onPressed: () => _addOrEditNote(),
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            '共 ${_filteredNotes.length} 条笔记',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        // 笔记列表
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredNotes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.note_alt_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "暂无笔记",
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("创建第一条笔记"),
                        onPressed: () => _addOrEditNote(),
                      ),
                    ],
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 1000;
                    if (isWide) {
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: (_filteredNotes.length + 1) ~/ 2,
                        itemBuilder: (context, rowIndex) {
                          final firstIdx = rowIndex * 2;
                          final secondIdx = firstIdx + 1;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: firstIdx < _filteredNotes.length
                                      ? _buildNoteCard(
                                          _filteredNotes[firstIdx],
                                          themeColor,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: secondIdx < _filteredNotes.length
                                      ? _buildNoteCard(
                                          _filteredNotes[secondIdx],
                                          themeColor,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: _filteredNotes.length,
                      itemBuilder: (context, index) {
                        final note = _filteredNotes[index];
                        final dateStr =
                            "${note.updatedAt.year}-${note.updatedAt.month.toString().padLeft(2, '0')}-${note.updatedAt.day.toString().padLeft(2, '0')}";
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: themeColor.withValues(
                                alpha: 0.15,
                              ),
                              child: Icon(
                                Icons.article,
                                color: themeColor,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              note.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (note.subject.isNotEmpty)
                                  Text(
                                    note.subject,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: themeColor,
                                    ),
                                  ),
                                Text(
                                  dateStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: themeColor,
                                  ),
                                  onPressed: () =>
                                      _addOrEditNote(existing: note),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red.shade300,
                                  ),
                                  onPressed: () => _deleteNote(note),
                                ),
                              ],
                            ),
                            onTap: () => _addOrEditNote(existing: note),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ----- 笔记编辑器页面 -----

class _NoteEditorPage extends StatefulWidget {
  final NoteEntry? existingNote;
  final List<String> availableSubjects;
  const _NoteEditorPage({this.existingNote, this.availableSubjects = const []});
  @override
  State<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<_NoteEditorPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late String _subject;
  String _customSubject = '';
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final note = widget.existingNote;
    _titleCtrl = TextEditingController(text: note?.title ?? '');
    _contentCtrl = TextEditingController(text: note?.content ?? '');
    _subject = note?.subject ?? '';
    // 新建笔记直接进入编辑模式，已有笔记先进入查看模式
    _isEditing = note == null;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请输入笔记标题")));
      return;
    }
    final effectiveSubject = _subject == '__custom__'
        ? _customSubject.trim()
        : _subject;

    final existing = widget.existingNote;
    final note = NoteEntry(
      id: existing?.id,
      title: title,
      content: content,
      subject: effectiveSubject,
      tags: existing?.tags ?? [],
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
    );
    Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final note = widget.existingNote;
    final subjects = [
      '',
      ...widget.availableSubjects.where((s) => s.isNotEmpty),
      '__custom__',
    ];
    final subjectLabels = {'': '无科目', '__custom__': '自定义...'};

    return Scaffold(
      appBar: AppBar(
        title: Text(
          note != null ? (note.title.isNotEmpty ? note.title : "查看笔记") : "新建笔记",
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isEditing)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text("保存"),
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit),
              label: const Text("编辑"),
            ),
        ],
      ),
      body: _isEditing
          ? _buildEditMode(subjects, subjectLabels)
          : _buildViewMode(isDark),
    );
  }

  /// 查看模式：渲染 Markdown + LaTeX
  Widget _buildViewMode(bool isDark) {
    final note = widget.existingNote;
    if (note == null) return const SizedBox.shrink();

    final content = note.content;
    final hasContent = content.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text(
            note.title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          // 元信息
          Row(
            children: [
              if (note.subject.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    note.subject,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _formatDate(note.updatedAt),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          // 内容
          if (hasContent)
            MarkdownBody(
              data: content,
              selectable: true,
              inlineSyntaxes: [_MathInlineSyntax()],
              builders: {
                'math': _MathElementBuilder(
                  textColor: isDark ? Colors.white : Colors.black87,
                ),
              },
              styleSheet: _markdownStyle(isDark).copyWith(
                p: TextStyle(
                  fontSize: 16,
                  height: 1.7,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  "（暂无内容）",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    return "${dt.year}年${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  /// 编辑模式
  Widget _buildEditMode(
    List<String> subjects,
    Map<String, String> subjectLabels,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '笔记标题',
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          // 科目选择
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: subjects.contains(_subject) ? _subject : '',
                  decoration: const InputDecoration(
                    labelText: '所属科目',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: subjects.map((s) {
                    final label = subjectLabels[s] ?? s;
                    return DropdownMenuItem(
                      value: s,
                      child: Text(label, style: const TextStyle(fontSize: 14)),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _subject = v ?? ''),
                ),
              ),
              if (_subject == '__custom__') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '输入科目',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => _customSubject = v,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // 内容
          Text(
            "笔记内容（支持 Markdown）",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _contentCtrl,
            maxLines: null,
            minLines: 12,
            decoration: InputDecoration(
              hintText: '在此输入笔记内容...\n\n支持 Markdown 格式：\n# 标题\n**粗体**\n- 列表项',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
              filled: true,
              fillColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            style: const TextStyle(
              fontSize: 14,
              height: 1.6,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// ----- 知识中心子标签 3: 活动时间线 -----

class _ActivityTimelineSubTab extends StatefulWidget {
  const _ActivityTimelineSubTab();
  @override
  State<_ActivityTimelineSubTab> createState() =>
      _ActivityTimelineSubTabState();
}

class _ActivityTimelineSubTabState extends State<_ActivityTimelineSubTab> {
  List<_TimelineEvent> _events = [];
  bool _isLoading = true;
  // 洞察看板
  Map<String, dynamic>? _healthData;
  List<LearningInsight> _insights = [];
  bool _isInsightLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTimeline();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() => _isInsightLoading = true);
    try {
      final config = await loadConfigFile();
      final studentId = config['STUDENT_ID']?.toString() ?? '';
      if (studentId.isNotEmpty) {
        _healthData = await InsightEngine.getOverallLearningHealth(studentId);
        _insights = await InsightEngine.analyzeScoreDecline(studentId);
      }
    } catch (e) {
      debugPrint(">>> 加载洞察失败: $e");
    }
    if (mounted) setState(() => _isInsightLoading = false);
  }

  Future<void> _loadTimeline() async {
    setState(() => _isLoading = true);
    var events = <_TimelineEvent>[];

    try {
      // 1. 最近笔记活动
      final notes = await NoteService.loadNotes();
      for (final note in notes.take(20)) {
        events.add(
          _TimelineEvent(
            date: note.updatedAt,
            type: 'note',
            title: note.subject.isNotEmpty
                ? '[$note.subject] $note.title'
                : note.title,
            subtitle:
                '笔记 ${note.content.length > 50 ? "${note.content.substring(0, 50)}..." : note.content}',
          ),
        );
      }

      // 2. 最近成绩变动
      final students = await LocalScoreService.loadStudents();
      for (final student in students) {
        if (student.scores.isNotEmpty) {
          final subjectList = student.scores.keys.take(3).join(', ');
          events.add(
            _TimelineEvent(
              date: DateTime.now().subtract(const Duration(hours: 1)),
              type: 'score',
              title: '${student.name} 的成绩',
              subtitle: '科目: $subjectList',
            ),
          );
        }
      }

      // 3. 最近对话（从 backlog 取最近 7 天）
      final today = DateTime.now();
      for (int i = 0; i < 7; i++) {
        final date = today.subtract(Duration(days: i));
        final dateStr =
            "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
        final backlog = await loadBacklogForRange(
          startDate: dateStr,
          endDate: dateStr,
          sort: 'desc',
        );
        if (backlog.isNotEmpty) {
          for (final dateEntry in backlog.entries) {
            for (final fileEntry in dateEntry.value.entries.take(3)) {
              final messages =
                  fileEntry.value['messages'] as List<dynamic>? ?? [];
              if (messages.isNotEmpty) {
                final userMsg = messages.firstWhere(
                  (m) => m['role']?.toString() == 'user',
                  orElse: () => <String, dynamic>{'content': ''},
                );
                final content = userMsg['content']?.toString() ?? '';
                final timeStr = fileEntry.key.replaceAll('.json', '');
                events.add(
                  _TimelineEvent(
                    date: DateTime.parse("${dateStr}T$timeStr"),
                    type: 'chat',
                    title: 'AI 对话',
                    subtitle: content.length > 80
                        ? '${content.substring(0, 80)}...'
                        : content,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint(">>> 加载时间线失败: $e");
    }

    // 按日期排序（最新的在前）
    events.sort((a, b) => b.date.compareTo(a.date));
    events = events.take(100).toList();

    if (mounted) {
      setState(() {
        _events = events;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final themeColor = Theme.of(context).colorScheme.primary;

    // 按日期分组
    final grouped = <String, List<_TimelineEvent>>{};
    for (final event in _events) {
      final key =
          "${event.date.year}-${event.date.month.toString().padLeft(2, '0')}-${event.date.day.toString().padLeft(2, '0')}";
      grouped.putIfAbsent(key, () => []).add(event);
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _loadTimeline();
        await _loadInsights();
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // ===== 洞察看板 =====
          if (!_isInsightLoading && _healthData != null) ...[
            // 健康度卡片
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: themeColor.withValues(alpha: 0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.insights, size: 20),
                        const SizedBox(width: 6),
                        const Text(
                          "学习健康度",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _healthData!['grade']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _healthScoreColor(
                              (_healthData!['score'] as num).toDouble(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 评分进度条
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value:
                            ((_healthData!['score'] as num).toDouble()) / 100.0,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _healthScoreColor(
                            (_healthData!['score'] as num).toDouble(),
                          ),
                        ),
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "综合评分: ${(_healthData!['score'] as num).toStringAsFixed(1)}/100",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 退步预警
            if (_insights.isNotEmpty) ...[
              ..._insights.map(
                (insight) => Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  color: insight.severity == 'high'
                      ? Colors.red.withValues(alpha: 0.08)
                      : Colors.orange.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: insight.severity == 'high'
                          ? Colors.red.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      insight.severity == 'high'
                          ? Icons.warning_amber
                          : Icons.trending_down,
                      color: insight.severity == 'high'
                          ? Colors.red
                          : Colors.orange,
                    ),
                    title: Text(
                      insight.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      insight.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Divider(height: 16),
          ],

          // ===== 活动时间线 =====
          if (_events.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.timeline, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text("暂无活动记录", style: TextStyle(color: Colors.grey.shade500)),
                ],
              ),
            )
          else
            ...grouped.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 日期头
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: themeColor,
                      ),
                    ),
                  ),
                  // 该日事件
                  ...entry.value.map((event) {
                    IconData icon;
                    Color iconColor;
                    switch (event.type) {
                      case 'note':
                        icon = Icons.article;
                        iconColor = Colors.blue;
                        break;
                      case 'score':
                        icon = Icons.score;
                        iconColor = Colors.green;
                        break;
                      case 'chat':
                        icon = Icons.chat;
                        iconColor = Colors.orange;
                        break;
                      default:
                        icon = Icons.circle;
                        iconColor = Colors.grey;
                    }
                    final timeStr =
                        "${event.date.hour.toString().padLeft(2, '0')}:${event.date.minute.toString().padLeft(2, '0')}";
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6, left: 8),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: iconColor.withValues(alpha: 0.15),
                          child: Icon(icon, size: 16, color: iconColor),
                        ),
                        title: Text(
                          event.title,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          event.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        trailing: Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            }),
        ],
      ),
    );
  }
}

/// 时间线事件数据类
class _TimelineEvent {
  final DateTime date;
  final String type;
  final String title;
  final String subtitle;
  const _TimelineEvent({
    required this.date,
    required this.type,
    required this.title,
    required this.subtitle,
  });
}

/// 健康度评分颜色
Color _healthScoreColor(double score) {
  if (score >= 85) return Colors.green;
  if (score >= 65) return Colors.blue;
  if (score >= 45) return Colors.orange;
  return Colors.red;
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

// ==================== Markdown + LaTeX 渲染 ====================

/// 内联公式语法解析（$$...$$ 和 $...$）
class _MathInlineSyntax extends md.InlineSyntax {
  _MathInlineSyntax() : super(r'\$\$(.+?)\$\$|\$(.+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = (match.group(1) ?? match.group(2) ?? '').trim();
    if (content.isEmpty) return false;
    final tag = match.group(1) != null ? 'math' : 'math';
    parser.addNode(md.Element.text(tag, content));
    return true;
  }
}

/// 公式元素构建器
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
    final content = element.textContent.trim();
    if (content.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Math.tex(
        content,
        textStyle: TextStyle(fontSize: 16, color: textColor),
        onErrorFallback: (e) =>
            Text('\$$content\$', style: TextStyle(color: textColor)),
      ),
    );
  }
}

/// 聊天 Markdown 样式
MarkdownStyleSheet _markdownStyle(bool isDark) {
  return MarkdownStyleSheet(
    p: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
    code: TextStyle(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
      color: isDark ? const Color(0xFF6A9955) : Colors.black87,
      fontSize: 13,
    ),
    codeblockDecoration: BoxDecoration(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(8),
    ),
    h1: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: isDark ? Colors.white : Colors.black87,
    ),
    h2: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: isDark ? Colors.white : Colors.black87,
    ),
    h3: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: isDark ? Colors.white : Colors.black87,
    ),
    listBullet: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: Colors.grey.shade400, width: 3)),
      color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
    codeblockPadding: const EdgeInsets.all(10),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: Colors.grey.shade300)),
    ),
  );
}

// ==================== Widget Preview ====================

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
