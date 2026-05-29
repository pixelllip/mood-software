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
    if (matchedCount >= 20)
      score += 50;
    else if (matchedCount >= 10)
      score += 40;
    else if (matchedCount >= 5)
      score += 30;
    else if (matchedCount >= 3)
      score += 20;
    else if (matchedCount >= 1)
      score += 10;

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

  /// 获取默认关键词列表（从配置和成绩数据中提取）
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

    // 3. 用户自定义关键词（从配置读取）
    final customKeywords = config['STUDY_KEYWORDS'] as List<dynamic>?;
    if (customKeywords != null) {
      for (final kw in customKeywords) {
        final s = kw.toString().trim();
        if (s.isNotEmpty) keywords.add(s);
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

    if (keywords.isEmpty) return result;

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
            // 匹配 AI 回答中的关键词
            final matchedKws = keywords
                .where((kw) => content.contains(kw))
                .toList();
            if (matchedKws.isNotEmpty) {
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
            userMsg = null;
          }
        }
      }
    }

    return result;
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
  }) async {
    final all = await loadAllSummaries();
    if (all.containsKey(date)) {
      // 如果已保存且日程完成数有更新，重新计算
      final existing = all[date]!;
      if (existing.completedSchedules == completedSchedules &&
          existing.totalSchedules == totalSchedules) {
        return existing;
      }
    }

    // 查询当日匹配记录
    final matches = await queryMatchedConversations(
      startDate: date,
      endDate: date,
      keywords: keywords,
    );

    final matchedCount = matches.length;
    final grade = DailyStudySummary.calculateGrade(
      matchedCount,
      completedSchedules,
      totalSchedules,
    );

    final summary = DailyStudySummary(
      date: date,
      matchedCount: matchedCount,
      totalSchedules: totalSchedules,
      completedSchedules: completedSchedules,
      grade: grade,
      encouragement: null, // AI生成由调用方处理
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
  // TODO: 后端实现后替换为真实 API 调用
  // 当前使用本地规则生成

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
}
