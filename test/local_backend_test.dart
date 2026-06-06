import 'package:flutter_test/flutter_test.dart';
import 'package:ai_agent/services/local_backend.dart';

void main() {
  // ==================== LocalScoreService 工具方法测试 ====================
  group('LocalScoreService.extractScore()', () {
    test('null 输入返回 0', () {
      expect(LocalScoreService.extractScore(null), 0.0);
    });

    test('int 转为 double', () {
      expect(LocalScoreService.extractScore(88), 88.0);
    });

    test('字符串数字转为 double', () {
      expect(LocalScoreService.extractScore('92.5'), 92.5);
    });

    test('Map 格式 {score: 88} 提取分数', () {
      expect(
        LocalScoreService.extractScore({'score': 88}),
        88.0,
      );
    });

    test('Map 缺少 score 字段返回 0', () {
      expect(
        LocalScoreService.extractScore({'fullMark': 150}),
        0.0,
      );
    });

    test('非法字符串返回 0', () {
      expect(LocalScoreService.extractScore('abc'), 0.0);
    });
  });

  group('LocalScoreService.extractFullMark()', () {
    test('无 fullMark 返回默认 100', () {
      expect(LocalScoreService.extractFullMark(null), 100.0);
    });

    test('Map 包含 fullMark 返回对应值', () {
      expect(
        LocalScoreService.extractFullMark({'score': 88, 'fullMark': 150}),
        150.0,
      );
    });

    test('纯数字分数返回默认 100', () {
      expect(LocalScoreService.extractFullMark(95), 100.0);
    });

    test('Map 含字符串 fullMark 转为 double', () {
      expect(
        LocalScoreService.extractFullMark({'score': 88, 'fullMark': '120'}),
        120.0,
      );
    });
  });

  // ==================== StudentData 工具方法测试 ====================
  group('StudentData 成绩历史方法', () {
    test('getScoreHistory 只返回指定科目的记录', () {
      final student = StudentData(
        studentId: '2024001',
        name: '张三',
        scores: {'数学': 95, '英语': 88},
        examRecords: [
          ExamRecord(
            date: '2026-01-10 10:00',
            examType: '月考',
            scores: {'数学': 85, '英语': 90},
          ),
          ExamRecord(
            date: '2026-01-20 10:00',
            examType: '月考',
            scores: {'数学': 95},
          ),
        ],
      );

      final mathHistory = student.getScoreHistory('数学');
      final engHistory = student.getScoreHistory('英语');

      expect(mathHistory.length, 2);
      expect(engHistory.length, 1);
      expect(mathHistory[1]['score'], 95);
      expect(engHistory[0]['score'], 90);
    });

    test('getScoreHistory 使用 label 作为返回的标签', () {
      final student = StudentData(
        studentId: '2024001',
        name: '张三',
        scores: {'数学': 95},
        examRecords: [
          ExamRecord(
            date: '2026-01-10 10:00',
            examType: 'exam',
            label: '期中考试',
            scores: {'数学': 85},
          ),
        ],
      );

      final history = student.getScoreHistory('数学');
      expect(history[0]['label'], '期中考试');
    });

    test('getScoreHistory 无 label 时使用 examType 作为标签', () {
      final student = StudentData(
        studentId: '2024001',
        name: '张三',
        scores: {'数学': 95},
        examRecords: [
          ExamRecord(
            date: '2026-01-10 10:00',
            examType: '月考',
            scores: {'数学': 85},
          ),
        ],
      );

      final history = student.getScoreHistory('数学');
      expect(history[0]['label'], '月考');
    });
  });

  group('StudentData 退步检测', () {
    test('isDeclining 先降后升返回 false', () {
      final student = StudentData(
        studentId: '2024001',
        name: '张三',
        scores: {'数学': 85},
        examRecords: [
          ExamRecord(date: '2026-01-01 10:00', examType: '月考', scores: {'数学': 90}),
          ExamRecord(date: '2026-01-08 10:00', examType: '月考', scores: {'数学': 80}),
          ExamRecord(date: '2026-01-15 10:00', examType: '月考', scores: {'数学': 85}),
        ],
      );

      expect(student.isDeclining('数学'), isFalse);
    });

    test('isDeclining 不存�在的科目返回 false', () {
      final student = StudentData(
        studentId: '2024001',
        name: '张三',
        scores: {},
      );

      expect(student.isDeclining('不存在科目'), isFalse);
    });
  });
}
