import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent/services/study_analysis_service.dart';

void main() {
  // ==================== DailyStudySummary 评分测试 ====================
  group('DailyStudySummary.calculateGrade()', () {
    test('优秀: 匹配20条以上 + 日程完成率100%', () {
      expect(
        DailyStudySummary.calculateGrade(20, 10, 10),
        '优秀',
      );
    });

    test('优秀: 匹配10条 + 日程完成率100%', () {
      expect(
        DailyStudySummary.calculateGrade(10, 5, 5),
        '优秀',
      );
    });

    test('良好: 匹配10条 + 日程完成率50%', () {
      expect(
        DailyStudySummary.calculateGrade(10, 3, 6),
        '良好',
      );
    });

    test('良好: 匹配5条 + 日程完成率100%', () {
      expect(
        DailyStudySummary.calculateGrade(5, 5, 5),
        '良好',
      );
    });

    test('合格: 匹配3条 + 日程完成率50%', () {
      expect(
        DailyStudySummary.calculateGrade(3, 3, 6),
        '合格',
      );
    });

    test('不合格: 匹配0条 + 日程完成率0%', () {
      expect(
        DailyStudySummary.calculateGrade(0, 0, 5),
        '不合格',
      );
    });

    test('无日程时按匹配条数评分', () {
      expect(
        DailyStudySummary.calculateGrade(20, 0, 0),
        '优秀',
      );
      expect(
        DailyStudySummary.calculateGrade(5, 0, 0),
        '良好',
      );
      expect(
        DailyStudySummary.calculateGrade(1, 0, 0),
        '合格',
      );
      expect(
        DailyStudySummary.calculateGrade(0, 0, 0),
        '合格', // 无日程时完成率=100% → 50分，匹配0条0分，共50分→合格
      );
    });

    test('边缘值: 匹配19条刚好到良好上限', () {
      // 19条匹配 = 40分(匹配部分) + 50分(日程全完成) = 90分 → 优秀
      final grade = DailyStudySummary.calculateGrade(19, 5, 5);
      expect(grade, '优秀');
    });

    test('边缘值: 匹配4条 + 全完成 = 良好', () {
      // 4条匹配 = 20分 + 50分 = 70分 → 良好
      expect(
        DailyStudySummary.calculateGrade(4, 5, 5),
        '良好',
      );
    });

    test('边缘值: 匹配2条 + 全完成 = 合格', () {
      // 2条匹配 = 10分 + 50分 = 60分 → 合格
      expect(
        DailyStudySummary.calculateGrade(2, 5, 5),
        '合格',
      );
    });
  });

  // ==================== 学科映射测试 ====================
  group('subjectTopics 映射', () {
    test('包含所有主要学科', () {
      expect(StudyAnalysisService.subjectTopics.containsKey('语文'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('数学'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('英语'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('物理'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('化学'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('历史'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('地理'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('生物'), isTrue);
      expect(StudyAnalysisService.subjectTopics.containsKey('计算机'), isTrue);
    });

    test('每个学科至少有3个知识点', () {
      for (final entry in StudyAnalysisService.subjectTopics.entries) {
        expect(
          entry.value.length,
          greaterThanOrEqualTo(3),
          reason: '${entry.key} 的知识点不足3个',
        );
      }
    });

    test('语文包含文言文和古诗', () {
      final topics = StudyAnalysisService.subjectTopics['语文']!;
      expect(topics, contains('文言文'));
      expect(topics, contains('古诗'));
      expect(topics, contains('阅读理解'));
    });

    test('计算机包含编程和代码', () {
      final topics = StudyAnalysisService.subjectTopics['计算机']!;
      expect(topics, contains('编程'));
      expect(topics, contains('代码'));
      expect(topics, contains('算法'));
    });
  });

  // ==================== 反向知识点→学科映射测试 ====================
  group('topicToSubject 反向映射', () {
    test('文言文 → 语文', () {
      expect(StudyAnalysisService.topicToSubject['文言文'], '语文');
    });

    test('函数 → 数学', () {
      expect(StudyAnalysisService.topicToSubject['函数'], '数学');
    });

    test('代码 → 计算机', () {
      expect(StudyAnalysisService.topicToSubject['代码'], '计算机');
    });

    test('不存在的知识点返回null', () {
      expect(
        StudyAnalysisService.topicToSubject['不存在的知识点'],
        isNull,
      );
    });
  });

  // ==================== 学科前缀列表测试 ====================
  group('_academicPrefixes 列表', () {
    test('包含所有学科名', () {
      // subjectTopics 中的所有学科都应在前缀列表中能找到对应词
      for (final subject in StudyAnalysisService.subjectTopics.keys) {
        final found = StudyAnalysisService.academicPrefixesForTest
            .any((p) => p.contains(subject) || subject.contains(p));
        expect(found, isTrue,
            reason: '学科 "$subject" 未在 _academicPrefixes 中找到对应词');
      }
    });
  });

  // ==================== MatchedConversation JSON 序列化 ====================
  group('MatchedConversation 序列化', () {
    test('fromJson 正确解析', () {
      final json = {
        'date': '2026-06-03',
        'time': '14:30',
        'summary': '数学学习',
        'user_message': '三角函数怎么解？',
        'ai_response': 'sin²x + cos²x = 1',
        'matched_keywords': ['数学', '三角函数'],
      };

      final conv = MatchedConversation.fromJson(json);

      expect(conv.date, '2026-06-03');
      expect(conv.time, '14:30');
      expect(conv.summary, '数学学习');
      expect(conv.userMessage, '三角函数怎么解？');
      expect(conv.aiResponse, 'sin²x + cos²x = 1');
      expect(conv.matchedKeywords, ['数学', '三角函数']);
    });

    test('fromJson 处理空字段', () {
      final json = <String, dynamic>{};

      final conv = MatchedConversation.fromJson(json);

      expect(conv.date, '');
      expect(conv.time, '');
      expect(conv.summary, '');
      expect(conv.userMessage, '');
      expect(conv.aiResponse, '');
      expect(conv.matchedKeywords, []);
    });

    test('fromJson 处理 null matched_keywords', () {
      final json = {
        'date': '2026-06-03',
        'matched_keywords': null,
      };

      final conv = MatchedConversation.fromJson(json);

      expect(conv.matchedKeywords, []);
    });
  });

  // ==================== DailyStudySummary JSON 序列化 ====================
  group('DailyStudySummary 序列化', () {
    test('toJson / fromJson 往返', () {
      final original = DailyStudySummary(
        date: '2026-06-03',
        matchedCount: 5,
        totalSchedules: 8,
        completedSchedules: 6,
        grade: '良好',
        encouragement: '表现不错，再接再厉！',
      );

      final json = original.toJson();
      final restored = DailyStudySummary.fromJson(json);

      expect(restored.date, original.date);
      expect(restored.matchedCount, original.matchedCount);
      expect(restored.totalSchedules, original.totalSchedules);
      expect(restored.completedSchedules, original.completedSchedules);
      expect(restored.grade, original.grade);
      expect(restored.encouragement, original.encouragement);
    });

    test('toJson 处理 null encouragement', () {
      final summary = DailyStudySummary(
        date: '2026-06-03',
        matchedCount: 0,
        totalSchedules: 0,
        completedSchedules: 0,
        grade: '不合格',
      );

      final json = summary.toJson();
      expect(json['encouragement'], isNull);
    });

    test('fromJson 处理 null encouragement', () {
      final json = {
        'date': '2026-06-03',
        'matched_count': 0,
        'total_schedules': 0,
        'completed_schedules': 0,
        'grade': '不合格',
      };

      final restored = DailyStudySummary.fromJson(json);
      expect(restored.encouragement, isNull);
    });
  });

  // ==================== 更多边界评分测试 ====================
  group('calculateGrade() 边界值', () {
    test('精确边界: 19条匹配+全完成 → 优秀', () {
      // 匹配 19 条: score += 40, 完成率 100%: score += 50 → 90 → 优秀
      expect(DailyStudySummary.calculateGrade(19, 5, 5), '优秀');
    });

    test('精确边界: 9条匹配+全完成 → 良好', () {
      // 匹配 9 条: score += 30, 完成率 100%: score += 50 → 80 → 良好
      expect(DailyStudySummary.calculateGrade(9, 5, 5), '良好');
    });

    test('精确边界: 4条匹配+全完成 → 良好', () {
      // 匹配 4 条: score += 30, 完成率 100%: score += 50 → 80 → 良好
      expect(DailyStudySummary.calculateGrade(4, 5, 5), '良好');
    });

    test('精确边界: 2条匹配+全完成 → 合格', () {
      // 匹配 2 条: score += 10, 完成率 100%: score += 50 → 60 → 合格
      expect(DailyStudySummary.calculateGrade(2, 5, 5), '合格');
    });

    test('精确边界: 0条匹配+0完成 → 不合格', () {
      // 匹配 0 条: score += 0, 完成率 0%: score += 0  → 0 → 不合格
      expect(DailyStudySummary.calculateGrade(0, 0, 5), '不合格');
    });

    test('大量匹配 + 0完成率 → 合格', () {
      // 20+ 条: score += 50, 0%: score += 0 → 50 → 合格
      expect(DailyStudySummary.calculateGrade(100, 0, 5), '合格');
    });

    test('0条匹配 + 100%完成率 → 合格', () {
      // 0 条: score += 0, 100%: score += 50 → 50 → 合格
      expect(DailyStudySummary.calculateGrade(0, 5, 5), '合格');
    });
  });

  // ==================== 学科映射双向完整性 ====================
  group('学科映射双向完整性', () {
    test('所有 topicToSubject 的映射都在 subjectTopics 中有对应', () {
      for (final entry in StudyAnalysisService.topicToSubject.entries) {
        final topic = entry.key;
        final subject = entry.value;
        expect(
          StudyAnalysisService.subjectTopics.containsKey(subject),
          isTrue,
          reason: '反向映射 "$topic" → "$subject" 的目标学科在 subjectTopics 中不存在',
        );
        expect(
          StudyAnalysisService.subjectTopics[subject],
          contains(topic),
          reason: '知识点 "$topic" 在 subjectTopics["$subject"] 中找不到',
        );
      }
    });

    test('所有 subjectTopics 的 topic 都在 topicToSubject 中有反向映射', () {
      for (final entry in StudyAnalysisService.subjectTopics.entries) {
        for (final topic in entry.value) {
          expect(
            StudyAnalysisService.topicToSubject.containsKey(topic),
            isTrue,
            reason: '知识点 "$topic" (属于 ${entry.key}) 缺少反向映射',
          );
        }
      }
    });
  });

  // ==================== generateEncouragement 测试 ====================
  group('generateEncouragement()', () {
    test('优秀 + 高完成率 → 包含鼓励词', () async {
      final msg = await StudyAnalysisService.generateEncouragement(
        grade: '优秀',
        studentName: '张三',
        matchedCount: 15,
        completedSchedules: 9,
        totalSchedules: 10,
      );

      expect(msg, contains('张三'));
      expect(msg, anyOf(contains('优秀'), contains('太棒了'), contains('高效')));
    });

    test('良好 → 包含鼓励词', () async {
      final msg = await StudyAnalysisService.generateEncouragement(
        grade: '良好',
        studentName: '张三',
        matchedCount: 8,
        completedSchedules: 5,
        totalSchedules: 10,
      );

      expect(msg, contains('张三'));
      expect(msg, anyOf(contains('不错'), contains('良好')));
    });

    test('合格 + 0匹配但有日程 → 提及完成日程', () async {
      final msg = await StudyAnalysisService.generateEncouragement(
        grade: '合格',
        studentName: '李四',
        matchedCount: 0,
        completedSchedules: 3,
        totalSchedules: 5,
      );

      expect(msg, contains('李四'));
      expect(msg, contains('完成'));
    });

    test('合格 + 有匹配 → 提及匹配数', () async {
      final msg = await StudyAnalysisService.generateEncouragement(
        grade: '合格',
        studentName: '王五',
        matchedCount: 3,
        completedSchedules: 0,
        totalSchedules: 0,
      );

      expect(msg, contains('王五'));
      expect(msg, contains('3'));
    });

    test('不合格 → 包含学习记录提示', () async {
      final msg = await StudyAnalysisService.generateEncouragement(
        grade: '不合格',
        studentName: '赵六',
        matchedCount: 0,
        completedSchedules: 0,
        totalSchedules: 0,
      );

      expect(msg, contains('赵六'));
      expect(msg, anyOf(contains('没有'), contains('学习记录'), contains('加油')));
    });
  });
}
