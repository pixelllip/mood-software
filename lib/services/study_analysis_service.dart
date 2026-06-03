import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ai_agent/backend_utils.dart';
import 'package:ai_agent/services/local_backend.dart';
import 'package:dio/dio.dart';

// ==================== 学习分析（本地直连模式） ====================

/// 关键词匹配结果：一条对话记录
class MatchedConversation {
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final String summary; // 对话摘要
  final String userMessage; // 用户问题
  final String aiResponse; // AI回答
  final List<String> matchedKeywords; // 命中的关键词列表

  const MatchedConversation({
    required this.date,
    required this.time,
    required this.summary,
    required this.userMessage,
    required this.aiResponse,
    required this.matchedKeywords,
  });

  factory MatchedConversation.fromJson(Map<String, dynamic> json) =>
      MatchedConversation(
        date: json['date']?.toString() ?? '',
        time: json['time']?.toString() ?? '',
        summary: json['summary']?.toString() ?? '',
        userMessage: json['user_message']?.toString() ?? '',
        aiResponse: json['ai_response']?.toString() ?? '',
        matchedKeywords:
            (json['matched_keywords'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}

/// 每日学习总结
class DailyStudySummary {
  final String date; // yyyy-MM-dd
  final int matchedCount; // 当日匹配的回答条数
  final int totalSchedules; // 当日总日程数
  final int completedSchedules; // 已完成的日程数
  final String grade; // 不合格/合格/良好/优秀
  final String? encouragement; // AI鼓励语

  const DailyStudySummary({
    required this.date,
    required this.matchedCount,
    required this.totalSchedules,
    required this.completedSchedules,
    required this.grade,
    this.encouragement,
  });

  /// 计算评分等级
  static String calculateGrade(
    int matchedCount,
    int completedSchedules,
    int totalSchedules,
  ) {
    // 评分算法：
    // - matchedCount: 关键词匹配的回答条数
    // - 日程完成率: completedSchedules / max(totalSchedules, 1)
    final scheduleRate = totalSchedules > 0
        ? completedSchedules / totalSchedules
        : 1.0;

    // 综合得分 (0~100)
    double score = 0;

    // 匹配条数评分 (最高50分)
    if (matchedCount >= 20) {
      score += 50;
    } else if (matchedCount >= 10) {
      score += 40;
    } else if (matchedCount >= 5) {
      score += 30;
    } else if (matchedCount >= 3) {
      score += 20;
    } else if (matchedCount >= 1) {
      score += 10;
    }

    // 日程完成率评分 (最高50分)
    score += scheduleRate * 50;

    if (score >= 85) return '优秀';
    if (score >= 65) return '良好';
    if (score >= 45) return '合格';
    return '不合格';
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'matched_count': matchedCount,
    'total_schedules': totalSchedules,
    'completed_schedules': completedSchedules,
    'grade': grade,
    'encouragement': encouragement,
  };

  factory DailyStudySummary.fromJson(Map<String, dynamic> json) =>
      DailyStudySummary(
        date: json['date']?.toString() ?? '',
        matchedCount: json['matched_count'] ?? 0,
        totalSchedules: json['total_schedules'] ?? 0,
        completedSchedules: json['completed_schedules'] ?? 0,
        grade: json['grade']?.toString() ?? '不合格',
        encouragement: json['encouragement']?.toString(),
      );
}

/// 学习分析服务（本地模式）
class StudyAnalysisService {
  static const String _summaryFileName = 'study_summary.json';

  /// 获取学习总结文件路径
  static Future<File> _getSummaryFile() async {
    final config = await loadConfigFile();
    final basePath =
        config['BASE_PATH']?.toString() ?? (await getProjectDirectory()).path;
    final dir = Directory('$basePath/StudyAnalysis');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$_summaryFileName');
  }

  // ========== 关键词管理 ==========

  /// 获取默认关键词列表（从配置和成绩数据中提取，不含自定义关键词）
  static Future<List<String>> getDefaultKeywords() async {
    final keywords = <String>{};

    // 1. 用户配置中的姓名和学号
    final config = await loadConfigFile();
    final studentName = config['STUDENT_NAME']?.toString() ?? '';
    final studentId = config['STUDENT_ID']?.toString() ?? '';
    if (studentName.isNotEmpty) keywords.add(studentName);
    if (studentId.isNotEmpty) keywords.add(studentId);

    // 2. 成绩记录中的学科名
    final students = await LocalScoreService.listAllStudents();
    for (final student in students) {
      for (final subject in student.scores.keys) {
        keywords.add(subject);
      }
    }

    return keywords.toList();
  }

  /// 获取自定义关键词
  static Future<List<String>> getCustomKeywords() async {
    final config = await loadConfigFile();
    final customKeywords = config['STUDY_KEYWORDS'] as List<dynamic>?;
    if (customKeywords == null) return [];
    return customKeywords
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 保存自定义关键词
  static Future<void> saveCustomKeywords(List<String> keywords) async {
    final config = await loadConfigFile();
    config['STUDY_KEYWORDS'] = keywords
        .where((s) => s.trim().isNotEmpty)
        .toList();
    await saveConfigFile(config);
  }

  // ========== 对话记录匹配查询 ==========

  /// 查询指定日期范围内与关键词匹配的对话记录
  /// 返回按时间排序的匹配记录列表
  static Future<List<MatchedConversation>> queryMatchedConversations({
    required String startDate,
    required String endDate,
    required List<String> keywords,
  }) async {
    final result = <MatchedConversation>[];
    final seenPairs = <String>{};

    if (keywords.isEmpty) return result;

    // 关键词联想扩展：每个关键词展开为关联词列表
    final expandedKeywords = <String>{};
    for (final kw in keywords) {
      final exps = await getKeywordExpansions(kw);
      expandedKeywords.addAll(exps);
    }
    final allKeywords = expandedKeywords.toList();

    final rangeData = await loadBacklogForRange(
      startDate: startDate,
      endDate: endDate,
      sort: 'asc',
    );

    for (final dateEntry in rangeData.entries) {
      final dateStr = dateEntry.key;
      final files = dateEntry.value;

      for (final fileEntry in files.entries) {
        final data = fileEntry.value;
        final messages = data['messages'] as List<dynamic>? ?? [];
        final summary = data['summary']?.toString() ?? '';

        if (messages.isEmpty) continue;

        // 提取一问一答对
        String? userMsg;
        for (final msg in messages) {
          final role = msg['role']?.toString() ?? '';
          final content = msg['content']?.toString() ?? '';
          if (role == 'user') {
            userMsg = content;
          } else if (role == 'assistant' && userMsg != null) {
            // 匹配 AI 回答中的关键词（使用扩展后的关键词列表）
            final matchedKws = allKeywords
                .where((kw) => content.contains(kw))
                .toList();
            if (matchedKws.isNotEmpty) {
              // 去重：同一问-答对只取第一条
              final pairKey = "$userMsg|||$content";
              if (seenPairs.add(pairKey)) {
                final timeStr = _extractTimeFromFilename(fileEntry.key);
                result.add(
                  MatchedConversation(
                    date: dateStr,
                    time: timeStr,
                    summary: summary,
                    userMessage: userMsg,
                    aiResponse: content,
                    matchedKeywords: matchedKws,
                  ),
                );
              }
            }
            userMsg = null;
          }
        }
      }
    }

    return result;
  }

  /// 通过后端 API 查询匹配记录（支持 AI 联想词扩展）
  /// 当 dio 可用时调用后端，否则回退到本地查询
  static Future<List<MatchedConversation>> queryWithBackend({
    required String startDate,
    required String endDate,
    required List<String> keywords,
    Dio? dio,
    bool useAiExpansion = true,
  }) async {
    if (dio != null) {
      try {
        final response = await dio.post(
          "/api/study/query",
          data: {
            "start_date": startDate,
            "end_date": endDate,
            "keywords": keywords.join(","),
            "use_ai_expansion": useAiExpansion,
          },
        );
        final data = response.data;
        if (data is List) {
          return data
              .map(
                (e) => MatchedConversation.fromJson(e as Map<String, dynamic>),
              )
              .toList();
        }
      } catch (e) {
        debugPrint(">>> 后端查询失败，回退本地: $e");
      }
    }
    // 回退到本地查询
    return queryMatchedConversations(
      startDate: startDate,
      endDate: endDate,
      keywords: keywords,
    );
  }

  /// 从文件名提取时间
  static String _extractTimeFromFilename(String filename) {
    try {
      final name = filename.replaceAll('.json', '');
      final parts = name.split('-');
      if (parts.length >= 2) {
        return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
      }
    } catch (_) {}
    return '';
  }

  // ========== 学习总结 ==========

  /// 获取每日学习总结（已保存的）
  static Future<Map<String, DailyStudySummary>> loadAllSummaries() async {
    final file = await _getSummaryFile();
    if (!await file.exists()) return {};

    try {
      final content = await file.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      return data.map(
        (key, value) => MapEntry(
          key,
          DailyStudySummary.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (e) {
      debugPrint(">>> 读取学习总结失败: $e");
      return {};
    }
  }

  /// 保存每日学习总结
  static Future<void> saveSummary(DailyStudySummary summary) async {
    final all = await loadAllSummaries();
    all[summary.date] = summary;
    final file = await _getSummaryFile();
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(all.map((key, value) => MapEntry(key, value.toJson()))),
    );
  }

  /// 获取某日的学习总结（若不存在则计算并保存）
  static Future<DailyStudySummary> getOrComputeSummary({
    required String date,
    required List<String> keywords,
    int completedSchedules = 0,
    int totalSchedules = 0,
    Dio? dio,
    bool useAiExpansion = true,
  }) async {
    // 加载已有总结（保留已有评语）
    final all = await loadAllSummaries();

    // 查询当日匹配记录（有 dio 时走后端 API 支持 AI 联想词扩展）
    final matches = await queryWithBackend(
      startDate: date,
      endDate: date,
      keywords: keywords,
      dio: dio,
      useAiExpansion: useAiExpansion,
    );

    final matchedCount = matches.length;
    final grade = DailyStudySummary.calculateGrade(
      matchedCount,
      completedSchedules,
      totalSchedules,
    );

    // 保留已有的评语（如果有），避免被覆盖
    final existingSummary = all[date];
    final existingEncouragement = existingSummary?.encouragement;

    final summary = DailyStudySummary(
      date: date,
      matchedCount: matchedCount,
      totalSchedules: totalSchedules,
      completedSchedules: completedSchedules,
      grade: grade,
      encouragement: existingEncouragement, // 保留已有评语
    );

    await saveSummary(summary);
    return summary;
  }

  /// 判断等级是否发生变化（与上次保存的对比）
  static Future<bool> hasGradeChanged(String date, String newGrade) async {
    final all = await loadAllSummaries();
    final existing = all[date];
    if (existing == null) return true; // 首次生成
    return existing.grade != newGrade;
  }

  // ========== AI 鼓励语生成（后端存根） ==========

  /// 生成鼓励语（根据等级）
  /// [backend stub] — 后续替换为 langchain4j 后端调用
  static Future<String> generateEncouragement({
    required String grade,
    required String studentName,
    required int matchedCount,
    required int completedSchedules,
    required int totalSchedules,
  }) async {
    // 🚧 后端存根：后续接入 langchain4j 后端 AI 生成
    // 调用方式示例（待实现）：
    //   POST /api/study/encouragement
    //   { "grade": "优秀", "student_name": "...", ... }
    //   → { "encouragement": "..." }

    final scheduleRate = totalSchedules > 0
        ? completedSchedules / totalSchedules
        : 0.0;

    switch (grade) {
      case '优秀':
        if (scheduleRate >= 0.8) {
          return '$studentName同学，今天你真是太棒了！🎉 不仅积极提问学习($matchedCount条匹配)，还高效完成了日程计划，继续保持这种优秀的状态，你一定能够取得更大的进步！💪';
        }
        return '$studentName同学，你今天的学习热情让人感动！🔥 提出了$matchedCount个与学习相关的问题，看得出你对知识的渴望。继续保持，卓越就在前方！🌟';
      case '良好':
        return '$studentName同学，今天表现不错哦！👍 有$matchedCount条学习相关的对话记录，整体状态良好。明天再加把劲，争取更上一层楼！📈';
      case '合格':
        if (matchedCount == 0 && totalSchedules > 0) {
          return '$studentName同学，今天完成了$completedSchedules项日程任务，但似乎没有进行学习相关的提问交流。学习不仅是被动接收，主动提问能让知识掌握得更牢固哦！📚';
        }
        return '$studentName同学，今天的学习状态还可以，有$matchedCount条匹配记录。学习是一场马拉松，贵在坚持，明天试着多问几个问题吧！🎯';
      case '不合格':
      default:
        return '$studentName同学，今天似乎没有留下学习记录呢😅。学习需要持之以恒，即使每天只学一点点，长期积累也会有惊人的效果。明天开始，一起加油吧！🌈';
    }
  }

  /// 通过后端 API 生成鼓励语（如果后端可用）
  /// 否则回退到本地规则
  static Future<String> generateEncouragementWithBackend({
    required String grade,
    required String studentName,
    required int matchedCount,
    required int completedSchedules,
    required int totalSchedules,
    Dio? dio,
  }) async {
    if (dio != null) {
      try {
        final response = await dio.post(
          "/api/study/encouragement",
          data: {
            "grade": grade,
            "student_name": studentName,
            "matched_count": matchedCount,
            "completed_schedules": completedSchedules,
            "total_schedules": totalSchedules,
          },
        );
        final data = response.data as Map<String, dynamic>;
        final encouragement = data['encouragement']?.toString();
        if (encouragement != null && encouragement.isNotEmpty) {
          return encouragement;
        }
      } catch (e) {
        debugPrint(">>> 后端鼓励语生成失败，回退本地规则: $e");
      }
    }
    // 回退到本地规则
    return generateEncouragement(
      grade: grade,
      studentName: studentName,
      matchedCount: matchedCount,
      completedSchedules: completedSchedules,
      totalSchedules: totalSchedules,
    );
  }

  // ========== AI 关键词发现 ==========

  /// 从后端发现学习关键词（扫描最近对话记录中的学习内容）
  static Future<List<String>> discoverKeywordsFromBackend({
    required Dio dio,
    int days = 7,
  }) async {
    try {
      final response = await dio.post(
        "/api/study/discover-keywords",
        data: {"days": days},
      );
      final data = response.data as Map<String, dynamic>;
      final keywords = data['keywords'] as List<dynamic>?;
      if (keywords == null || keywords.isEmpty) return [];
      return keywords.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint(">>> 发现关键词失败: $e");
      return [];
    }
  }

  // ========== 本地关键词发现（手机端） ==========

  /// 常见学科/课程关键词前缀（用于从对话中提取潜在的学术关键词）
  static const _academicPrefixes = [
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
    '算法',
    '数据',
    '网络',
    '工程',
    '设计',
    '艺术',
    '音乐',
    '体育',
    '哲学',
    '心理',
    '经济',
    '法律',
    '医学',
    '文学',
    '语法',
    '单词',
    '公式',
    '方程',
    '函数',
    '几何',
    '代数',
    '概率',
    '统计',
    '实验',
    '论文',
    '项目',
    '代码',
    '软件',
    '硬件',
    '计算机',
    '程序',
    '数据库',
    '人工智能',
    '前端',
    '后端',
  ];

  /// 测试用：暴露 _academicPrefixes 给单元测试
  static List<String> get academicPrefixesForTest =>
      List.unmodifiable(_academicPrefixes);

  /// 关键词尾缀（用于识别潜在的学术名词）
  static const _academicSuffixes = [
    '学',
    '法',
    '论',
    '题',
    '课',
    '科',
    '术',
    '率',
    '式',
  ];

  /// 常见通用词（过滤掉无意义的常用词）
  static const _stopWords = {
    '什么',
    '怎么',
    '为什么',
    '如何',
    '这个',
    '那个',
    '一个',
    '可以',
    '知道',
    '没有',
    '不是',
    '就是',
    '但是',
    '因为',
    '所以',
    '如果',
    '我们',
    '你们',
    '他们',
    '自己',
    '大家',
    '同学',
    '老师',
    '学校',
    '问题',
    '答案',
    '方法',
    '时候',
    '地方',
    '东西',
    '感觉',
    '觉得',
    '看到',
    '听到',
    '想到',
    '做到',
    '来到',
    '回到',
    '进入',
    '过来',
  };

  /// 从单条 AI 回复文本中提取关键词
  ///
  /// 使用规则匹配提取可能的学术、学科相关词汇。
  /// 返回去重后的关键词集合（不保存到配置文件）。
  static Set<String> _extractKeywordsFromText(String text) {
    final discovered = <String>{};

    // 1. 提取包含学术前缀的词汇
    for (final prefix in _academicPrefixes) {
      int startIdx = 0;
      while (true) {
        final idx = text.indexOf(prefix, startIdx);
        if (idx < 0) break;
        // 从匹配位置向后扩展提取完整短语
        int end = idx + prefix.length;
        for (int i = 0; i < 6 && end < text.length; i++) {
          final ch = text[end];
          if (RegExp(r'[\u4e00-\u9fff]').hasMatch(ch)) {
            end++;
          } else {
            break;
          }
        }
        final word = text.substring(idx, end);
        if (word.length >= 2 && !_stopWords.contains(word)) {
          discovered.add(word);
        }
        startIdx = idx + 1;
      }
    }

    // 2. 提取包含学术尾缀的词汇
    final suffixPattern = RegExp(
      '([\u4e00-\u9fff]{2,6})(${_academicSuffixes.join('|')})',
    );
    for (final match in suffixPattern.allMatches(text)) {
      final word = match.group(0)!;
      if (word.length >= 2 && !_stopWords.contains(word)) {
        discovered.add(word);
      }
    }

    // 3. 提取英文技术术语（首字母大写或全大写，长度 >= 3）
    final enPattern = RegExp(r'\b([A-Z][a-z]{2,}|[A-Z]{2,})\b');
    for (final match in enPattern.allMatches(text)) {
      final word = match.group(1)!;
      if (word.length >= 3) {
        discovered.add(word);
      }
    }

    return discovered;
  }

  /// 手机端本地关键词发现：从 AI 对话内容中自动提取潜在的学习关键词
  ///
  /// 此方法扫描 [aiResponse] 文本，使用规则匹配提取可能的学术、学科相关词汇，
  /// 然后与现有关键词合并去重，并保存到配置文件中。
  /// 返回新发现的关键词列表。
  static Future<List<String>> discoverKeywordsLocally({
    required String aiResponse,
  }) async {
    if (aiResponse.isEmpty) return [];

    final discovered = _extractKeywordsFromText(aiResponse);
    if (discovered.isEmpty) return [];

    // 合并到现有关键词中
    final existingKeywords = await getCustomKeywords();
    final merged = <String>{...existingKeywords, ...discovered};
    final newKeywords = discovered
        .where((kw) => !existingKeywords.contains(kw))
        .toList();

    if (newKeywords.isNotEmpty) {
      await saveCustomKeywords(merged.toList());
      // 新关键词关联到已有关键词（如"小石潭记"关联到"语文"）
      integrateDiscoveredKeywords(newKeywords);
      debugPrint(">>> 本地关键词发现: 新增 ${newKeywords.length} 个关键词: $newKeywords");
    }

    return newKeywords;
  }

  /// 从历史对话记录中批量发现关键词（手机端使用）
  ///
  /// 扫描最近 [days] 天的 backlog 对话文件，提取 AI 回复中出现的潜在学习关键词，
  /// 与现有关键词合并去重后保存。
  /// 返回新发现的关键词列表。
  static Future<List<String>> discoverKeywordsFromBacklog({
    int days = 7,
  }) async {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days - 1));

    String dateStr(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final rangeData = await loadBacklogForRange(
      startDate: dateStr(startDate),
      endDate: dateStr(endDate),
      sort: 'asc',
    );

    // 收集所有 AI 回复文本
    final allTexts = <String>[];
    for (final dateEntry in rangeData.entries) {
      for (final fileEntry in dateEntry.value.entries) {
        final messages = fileEntry.value['messages'] as List<dynamic>? ?? [];
        for (final msg in messages) {
          final role = msg['role']?.toString() ?? '';
          final content = msg['content']?.toString() ?? '';
          if (role == 'assistant' && content.isNotEmpty) {
            allTexts.add(content);
          }
        }
      }
    }

    if (allTexts.isEmpty) return [];

    // 从所有 AI 回复中提取关键词
    final discovered = <String>{};
    for (final text in allTexts) {
      discovered.addAll(_extractKeywordsFromText(text));
    }

    if (discovered.isEmpty) return [];

    // 合并到现有关键词中
    final existingKeywords = await getCustomKeywords();
    final merged = <String>{...existingKeywords, ...discovered};
    final newKeywords = discovered
        .where((kw) => !existingKeywords.contains(kw))
        .toList();

    if (newKeywords.isNotEmpty) {
      await saveCustomKeywords(merged.toList());
      integrateDiscoveredKeywords(newKeywords);
      debugPrint(
        ">>> 批量关键词发现: 扫描 ${allTexts.length} 条回复, 新增 ${newKeywords.length} 个关键词: $newKeywords",
      );
    }

    return newKeywords;
  }

  // ========== 关键词联想扩展（手机端本地） ==========

  /// 内置学科→知识点映射（与后端 PreciseSearch.SUBJECT_TOPICS 一致）
  static const Map<String, List<String>> subjectTopics = {
    '语文': ['文言文', '古诗', '古诗词', '阅读理解', '作文', '写作', '文学常识', '现代文'],
    '数学': ['代数', '几何', '函数', '方程', '三角函数', '概率', '统计'],
    '英语': ['词汇', '单词', '语法', '阅读理解', '听力', '作文', '写作', '翻译'],
    '物理': ['力学', '运动学', '电学', '光学', '热学', '能量', '加速度'],
    '化学': ['元素', '方程式', '化学反应', '周期表', '酸碱', '氧化还原'],
    '历史': ['古代史', '近代史', '世界史', '中国史', '历史事件', '朝代'],
    '地理': ['气候', '地形', '地图', '人口', '区域地理', '自然地理'],
    '生物': ['细胞', '遗传', '进化', '生态系统', '人体', '植物', '动物'],
    '计算机': [
      '编程',
      '代码',
      '算法',
      '数据结构',
      '程序',
      '软件',
      '硬件',
      '网络',
      'Python',
      'Java',
      'C++',
      '前端',
      '后端',
      '数据库',
      '人工智能',
    ],
  };

  /// 反向查找：知识点→所属学科
  static Map<String, String> get topicToSubject {
    final map = <String, String>{};
    for (final entry in subjectTopics.entries) {
      for (final topic in entry.value) {
        map[topic] = entry.key;
      }
    }
    return map;
  }

  /// 关键词扩展缓存文件路径
  static Future<File> _getExpansionCacheFile() async {
    final config = await loadConfigFile();
    final basePath =
        config['BASE_PATH']?.toString() ?? (await getProjectDirectory()).path;
    final dir = Directory('$basePath/Backlog');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/keyword_cache.json');
  }

  /// 加载扩展缓存
  static Future<Map<String, List<String>>> _loadExpansionCache() async {
    try {
      final file = await _getExpansionCacheFile();
      if (!await file.exists()) return {};
      final content = await file.readAsString();
      final data = json.decode(content) as Map<String, dynamic>;
      // 校验版本
      if (data['version'] != 2) return {};
      final expansions = data['expansions'] as Map<String, dynamic>?;
      if (expansions == null) return {};
      return expansions.map(
        (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
      );
    } catch (_) {
      return {};
    }
  }

  /// 保存扩展缓存
  static Future<void> _saveExpansionCache(
    Map<String, List<String>> cache,
  ) async {
    try {
      final file = await _getExpansionCacheFile();
      await file.writeAsString(
        json.encode({'version': 2, 'expansions': cache}),
      );
    } catch (_) {}
  }

  /// 获取单个关键词的扩展列表（合并内置映射 + 自定义缓存）
  static Future<List<String>> getKeywordExpansions(String keyword) async {
    final result = <String>{keyword};

    // 1. 内置映射：学科→知识点
    if (subjectTopics.containsKey(keyword)) {
      result.addAll(subjectTopics[keyword]!);
    }

    // 2. 内置映射：知识点→学科
    final parentSubject = topicToSubject[keyword];
    if (parentSubject != null) {
      result.add(parentSubject);
    }

    // 3. 自定义缓存扩展
    final cache = await _loadExpansionCache();
    if (cache.containsKey(keyword)) {
      result.addAll(cache[keyword]!);
    }

    return result.toList();
  }

  /// 将新发现的关键词与已有关联列表关联
  ///
  /// 例如发现"小石潭记" → 自动关联到"语文"的扩展列表中，
  /// 以后搜"语文"也能搜到含"小石潭记"的对话。
  static Future<void> integrateDiscoveredKeywords(
    List<String> discovered,
  ) async {
    if (discovered.isEmpty) return;

    var cache = await _loadExpansionCache();
    bool changed = false;

    for (final newKw in discovered) {
      // 1. 检查新关键词的扩展中是否有已缓存的关键词
      final expanded =
          (subjectTopics[newKw]?.toList() ?? []) +
          (topicToSubject[newKw] != null ? [topicToSubject[newKw]!] : []);

      for (final term in expanded) {
        if (term == newKw) continue;
        // 将新关键词拓展到关联学科的缓存中
        final existing = cache.putIfAbsent(term, () => []);
        if (!existing.contains(newKw)) {
          existing.add(newKw);
          changed = true;
        }
        // 反向：将关联学科加入新关键词的缓存
        final kwExisting = cache.putIfAbsent(newKw, () => []);
        if (!kwExisting.contains(term)) {
          kwExisting.add(term);
          changed = true;
        }
      }

      // 2. 如果新关键词是某个学科的知识点，自动关联到该学科
      final subject = topicToSubject[newKw];
      if (subject != null) {
        final subjectExp = cache.putIfAbsent(subject, () => []);
        if (!subjectExp.contains(newKw)) {
          subjectExp.add(newKw);
          changed = true;
        }
      }
    }

    if (changed) {
      await _saveExpansionCache(cache);
      debugPrint(">>> 关键词关联: 已更新扩展缓存");
    }
  }

  // ========== AI 增强关键词发现（手机端直连 API） ==========

  /// 调用 AI（非流式）提取学习关键词
  ///
  /// 发送 [prompt] 到 OpenAI 兼容 API，返回解析后的关键词列表。
  static Future<List<String>> _callAiExtractKeywords({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String prompt,
  }) async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {
            "Authorization": "Bearer $apiKey",
            "Content-Type": "application/json",
          },
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      final response = await dio.post(
        "/chat/completions",
        data: {
          "model": model,
          "messages": [
            {"role": "user", "content": prompt},
          ],
          "temperature": 0.3,
          "max_tokens": 200,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return [];

      final content =
          (choices[0] as Map)['message']?['content']?.toString().trim() ?? '';
      if (content.isEmpty || content == "无") return [];

      return content
          .split(RegExp(r'[,，]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty && e.length >= 2)
          .toList()
          .toSet()
          .toList();
    } catch (e) {
      debugPrint(">>> AI 关键词提取调用失败: $e");
      return [];
    }
  }

  /// 手机端 AI 关键词发现（批量）：扫描最近对话记录，用 AI 分析学习科目/知识点
  ///
  /// 收集最近 [days] 天内的用户问题，发送给 AI 分析，返回发现的学科关键词。
  /// 与后端 `PreciseSearch.discoverKeywords()` 逻辑一致。
  static Future<List<String>> discoverKeywordsFromBacklogWithAI({
    required String baseUrl,
    required String apiKey,
    required String model,
    int days = 7,
  }) async {
    // 1. 收集用户问题
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days - 1));

    String dateStr(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final rangeData = await loadBacklogForRange(
      startDate: dateStr(startDate),
      endDate: dateStr(endDate),
      sort: 'desc',
    );

    final questions = <String>[];
    for (final dateEntry in rangeData.entries) {
      final files = dateEntry.value;
      // 每天最多取 5 条最近的对话
      final sortedKeys = files.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final fileKey in sortedKeys.take(5)) {
        final messages = files[fileKey]?['messages'] as List<dynamic>? ?? [];
        for (final msg in messages) {
          if (msg['role']?.toString() == 'user') {
            final content = msg['content']?.toString() ?? '';
            if (content.isNotEmpty) {
              questions.add(
                content.length > 100 ? content.substring(0, 100) : content,
              );
            }
          }
        }
        if (questions.length >= 15) break; // 最多 15 条
      }
      if (questions.length >= 15) break;
    }

    if (questions.isEmpty) return [];

    final uniqueQuestions = questions.toSet().toList().take(15).toList();

    // 2. AI 分析
    final prompt =
        """
你是一个学习关键词发现助手。以下是一些学生向 AI 提出的问题，请从中分析出该学生正在学习的**科目/知识点**。

要求：
1. 只返回关键词列表，用逗号分隔，不要任何其他文字
2. 每个关键词应是一个独立的学习科目或知识点（如"数学"、"英语"、"小石潭记"、"勾股定理"）
3. 不要包含明显非学习类的内容（如问候语、闲聊等）
4. 如果无法从问题中判断学习内容，只返回一个"无"

学生的问题：
${uniqueQuestions.join("\n---\n")}
"""
            .trim();

    final aiResult = await _callAiExtractKeywords(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      prompt: prompt,
    );

    if (aiResult.isEmpty) return [];

    // 3. 合并到现有关键词
    final existingKeywords = await getCustomKeywords();
    final merged = <String>{...existingKeywords, ...aiResult};
    final newKeywords = aiResult
        .where((kw) => !existingKeywords.contains(kw))
        .toList();

    if (newKeywords.isNotEmpty) {
      await saveCustomKeywords(merged.toList());
      integrateDiscoveredKeywords(newKeywords);
      debugPrint(
        ">>> AI关键词发现: 分析 ${uniqueQuestions.length} 条问题, 新增 ${newKeywords.length} 个: $newKeywords",
      );
    }

    return newKeywords;
  }

  /// 手机端 AI 关键词发现（单条对话）：从 AI 回复中提炼学习关键词
  ///
  /// 用于每次对话结束后自动调用。将用户问题 + AI 回复发送给 AI 分析。
  static Future<List<String>> discoverKeywordsFromChatWithAI({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String userMessage,
    required String aiResponse,
  }) async {
    if (userMessage.isEmpty && aiResponse.isEmpty) return [];

    final prompt =
        """
这是一段学生与 AI 助手的对话，请从中提取学生正在学习的**科目/知识点**。

要求：
1. 只返回关键词列表，用逗号分隔，不要任何其他文字
2. 每个关键词应是一个独立的学习科目或知识点
3. 如果明显不是学习内容，只返回一个"无"
4. 不要包含问候语、闲聊等非学习内容

学生问题：$userMessage

AI回答：${aiResponse.length > 200 ? "${aiResponse.substring(0, 200)}..." : aiResponse}
"""
            .trim();

    final aiResult = await _callAiExtractKeywords(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      prompt: prompt,
    );

    if (aiResult.isEmpty) return [];

    // 合并到现有关键词
    final existingKeywords = await getCustomKeywords();
    final merged = <String>{...existingKeywords, ...aiResult};
    final newKeywords = aiResult
        .where((kw) => !existingKeywords.contains(kw))
        .toList();

    if (newKeywords.isNotEmpty) {
      await saveCustomKeywords(merged.toList());
      integrateDiscoveredKeywords(newKeywords);
      debugPrint(">>> AI单条关键词发现: 新增 ${newKeywords.length} 个: $newKeywords");
    }

    return newKeywords;
  }
}
