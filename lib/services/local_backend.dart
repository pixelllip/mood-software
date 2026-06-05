import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_agent/backend_utils.dart';

// ==================== 成绩管理 ====================

/// 考试记录（时间戳版本的成绩快照）
class ExamRecord {
  final String date; // yyyy-MM-dd HH:mm
  final String examType; // 'exam' | 'quiz' | 'mock' | '日常'
  final String? semester;
  final String? label; // 如"期中考试"、"月考"等
  final Map<String, dynamic> scores; // 与 StudentData.scores 格式一致

  const ExamRecord({
    required this.date,
    this.examType = '日常',
    this.semester,
    this.label,
    this.scores = const {},
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'exam_type': examType,
    'semester': semester,
    'label': label,
    'scores': scores,
  };

  factory ExamRecord.fromJson(Map<String, dynamic> json) => ExamRecord(
    date: json['date']?.toString() ?? '',
    examType: json['exam_type']?.toString() ?? '日常',
    semester: json['semester']?.toString(),
    label: json['label']?.toString(),
    scores: json['scores'] is Map
        ? Map<String, dynamic>.from(json['scores'] as Map)
        : {},
  );
}

/// 学生成绩数据模型（与 Kotlin/Python 后端格式一致）
class StudentData {
  final String studentId;
  final String name;
  final Map<String, dynamic> scores;
  final List<ExamRecord> examRecords; // 历史考试记录

  const StudentData({
    required this.studentId,
    required this.name,
    this.scores = const {},
    this.examRecords = const [],
  });

  Map<String, dynamic> toJson() => {
    'student_id': studentId,
    'name': name,
    'scores': scores,
    if (examRecords.isNotEmpty)
      'exam_records': examRecords.map((r) => r.toJson()).toList(),
  };

  factory StudentData.fromJson(Map<String, dynamic> json) => StudentData(
    studentId: json['student_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    scores: json['scores'] is Map
        ? Map<String, dynamic>.from(json['scores'] as Map)
        : {},
    examRecords: json['exam_records'] is List
        ? (json['exam_records'] as List)
              .map((e) => ExamRecord.fromJson(e as Map<String, dynamic>))
              .toList()
        : [],
  );

  /// 获取某科目的历史成绩序列（按时间升序）
  List<Map<String, dynamic>> getScoreHistory(String subject) {
    final history = <Map<String, dynamic>>[];
    for (final record in examRecords) {
      final score = record.scores[subject];
      if (score != null) {
        history.add({
          'date': record.date,
          'label': record.label ?? record.examType,
          'score': score,
        });
      }
    }
    return history;
  }

  /// 判断某科目是否退步（连续两次下降）
  bool isDeclining(String subject) {
    final history = getScoreHistory(subject);
    if (history.length < 3) return false;
    final recent = history.reversed.take(3).toList();
    final v0 = LocalScoreService.extractScore(recent[0]['score']);
    final v1 = LocalScoreService.extractScore(recent[1]['score']);
    final v2 = LocalScoreService.extractScore(recent[2]['score']);
    return v0 < v1 && v1 < v2; // 连续三次下降
  }

  /// 获取最新一次考试成绩与上一次的差值
  double? getScoreChange(String subject) {
    final history = getScoreHistory(subject);
    if (history.length < 2) return null;
    final latest = LocalScoreService.extractScore(history.last['score']);
    final prev = LocalScoreService.extractScore(
      history[history.length - 2]['score'],
    );
    return latest - prev;
  }
}

/// 手机端本地成绩管理服务
class LocalScoreService {
  static Future<File> _getDataFile() async {
    final config = await loadConfigFile();
    final basePath =
        config['BASE_PATH']?.toString() ?? (await getProjectDirectory()).path;
    final dir = Directory('$basePath/Score_info');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/students.json');
  }

  /// 读取全部学生数据
  static Future<List<StudentData>> loadStudents() async {
    try {
      final file = await _getDataFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = json.decode(content) as List<dynamic>;
      return list
          .map((e) => StudentData.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint(">>> 读取学生数据失败: $e");
      return [];
    }
  }

  /// 保存全部学生数据
  static Future<void> _saveStudents(List<StudentData> students) async {
    final file = await _getDataFile();
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(students.map((s) => s.toJson()).toList()),
    );
  }

  /// 从分数值中提取分数（支持旧版纯数字和新版对象格式）
  static double extractScore(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is Map) {
      final score = v['score'];
      if (score is num) return score.toDouble();
      return double.tryParse(score?.toString() ?? '') ?? 0;
    }
    return double.tryParse(v.toString()) ?? 0;
  }

  /// 从分数值中提取满分（支持旧版和新版格式）
  static double extractFullMark(dynamic v) {
    if (v is Map && v.containsKey('fullMark')) {
      final fm = v['fullMark'];
      if (fm is num) return fm.toDouble();
      return double.tryParse(fm?.toString() ?? '') ?? 100;
    }
    return 100; // 默认满分 100
  }

  /// 标准化分数值（统一转为 num，字符串转数字；新格式保存为 Map）
  static dynamic _normalizeScore(dynamic v, {double? fullMark}) {
    if (v == null) return 0;
    double score;
    if (v is num) {
      score = v.toDouble();
    } else if (v is String) {
      score = double.tryParse(v) ?? 0;
    } else {
      score = 0;
    }
    // 如果指定了满分且不是默认 100，保存为对象格式
    if (fullMark != null && fullMark != 100) {
      return {'score': score, 'fullMark': fullMark};
    }
    return score;
  }

  /// 按 ID 查询，返回所有匹配的学生（允许同学号不同名）
  static Future<List<StudentData>> queryStudentsById(String id) async {
    final students = await loadStudents();
    if (id.isEmpty) return [];
    return students.where((s) => s.studentId == id).toList();
  }

  /// 查询单个学生（按 ID 精确匹配，或按姓名模糊匹配返回第一个）
  static Future<StudentData?> queryStudent({String? id, String? name}) async {
    final students = await loadStudents();
    if (id != null && id.isNotEmpty) {
      return students.cast<StudentData?>().firstWhere(
        (s) => s!.studentId == id,
        orElse: () => null,
      );
    }
    if (name != null && name.isNotEmpty) {
      return students.cast<StudentData?>().firstWhere(
        (s) => s!.name.contains(name),
        orElse: () => null,
      );
    }
    return null;
  }

  /// 模糊查询学生（按姓名返回所有匹配的列表）
  static Future<List<StudentData>> queryStudentsByName(String name) async {
    final students = await loadStudents();
    if (name.isEmpty) return [];
    return students.where((s) => s.name.contains(name)).toList();
  }

  /// 获取全部学生列表
  static Future<List<StudentData>> listAllStudents() async {
    return await loadStudents();
  }

  /// 添加/更新成绩（自动标准化分数值，自动创建考试记录）
  /// 匹配规则：同学号 + 同姓名 → 合并成绩；同学号 + 不同姓名 → 新建条目
  /// scores 格式：{"数学": 88} 或 {"数学": {"score": 88, "fullMark": 150}}
  static Future<String> addScore({
    required String studentId,
    required String name,
    required Map<String, dynamic> scores,
    String? label, // 可选：如"期中考试"、"月考"
    String? examType, // 可选：'exam' | 'quiz' | 'mock' | '日常'
  }) async {
    final students = await loadStudents();

    // 标准化所有分数值
    final normalizedScores = <String, dynamic>{};
    for (final entry in scores.entries) {
      final value = entry.value;
      double? fm;
      if (value is Map) {
        fm = (value['fullMark'] as num?)?.toDouble();
      }
      normalizedScores[entry.key] = _normalizeScore(
        value is Map ? (value['score'] ?? value) : value,
        fullMark: fm,
      );
    }

    // 创建考试记录
    final now = DateTime.now();
    final dateStr =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} "
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    final examRecord = ExamRecord(
      date: dateStr,
      examType: examType ?? '日常',
      label: label,
      scores: Map<String, dynamic>.from(normalizedScores),
    );

    // 查找同学号且同姓名（精确匹配）的已有条目
    final idx = students.indexWhere(
      (s) => s.studentId == studentId && s.name == name,
    );

    if (idx >= 0) {
      // 同学号 + 同姓名 → 合并成绩 + 追加考试记录
      final existing = students[idx];
      final merged = Map<String, dynamic>.from(existing.scores);
      merged.addAll(normalizedScores);
      students[idx] = StudentData(
        studentId: studentId,
        name: name,
        scores: merged,
        examRecords: [...existing.examRecords, examRecord],
      );
      await _saveStudents(students);
      return '已为学生 [$name] 更新/合并成绩。';
    } else {
      // 同学号不同名 或 新学生 → 新建条目
      students.add(
        StudentData(
          studentId: studentId,
          name: name,
          scores: normalizedScores,
          examRecords: [examRecord],
        ),
      );
      await _saveStudents(students);
      return '成功录入新学生：$name';
    }
  }

  /// 更新某学生单科成绩的标签
  static Future<bool> updateSubjectTag({
    required String studentId,
    required String subject,
    required String tag,
  }) async {
    final students = await loadStudents();
    final idx = students.indexWhere((s) => s.studentId == studentId);
    if (idx < 0) return false;
    final existing = students[idx];
    final updatedScores = Map<String, dynamic>.from(existing.scores);
    final oldScore = updatedScores[subject];
    if (oldScore is Map) {
      updatedScores[subject] = {...oldScore, 'tag': tag};
    } else if (oldScore != null) {
      updatedScores[subject] = {'score': oldScore, 'tag': tag};
    } else {
      updatedScores[subject] = {'score': 0, 'tag': tag};
    }
    students[idx] = StudentData(
      studentId: existing.studentId,
      name: existing.name,
      scores: updatedScores,
      examRecords: existing.examRecords,
    );
    await _saveStudents(students);
    return true;
  }

  /// 获取某学生的完整考试历史
  static Future<List<ExamRecord>> getExamHistory(String studentId) async {
    final students = await loadStudents();
    final idx = students.indexWhere((s) => s.studentId == studentId);
    if (idx < 0) return [];
    return students[idx].examRecords;
  }

  /// 检测退步科目
  static Future<List<String>> detectDecliningSubjects(String studentId) async {
    final students = await loadStudents();
    final idx = students.indexWhere((s) => s.studentId == studentId);
    if (idx < 0) return [];
    final student = students[idx];
    return student.scores.keys
        .where((subject) => student.isDeclining(subject))
        .toList();
  }

  /// 删除学生
  static Future<bool> deleteStudent({String? id, String? name}) async {
    final students = await loadStudents();
    final initialCount = students.length;

    students.removeWhere((s) {
      if (id != null && id.isNotEmpty) return s.studentId == id;
      if (name != null && name.isNotEmpty) return s.name == name;
      return false;
    });

    if (students.length < initialCount) {
      await _saveStudents(students);
      return true;
    }
    return false;
  }

  /// 删除某学生的单科成绩
  /// 返回 true 表示删除成功，false 表示未找到该科目
  static Future<bool> deleteSubjectScore({
    required String studentId,
    required String subject,
  }) async {
    final students = await loadStudents();
    final idx = students.indexWhere((s) => s.studentId == studentId);
    if (idx < 0) return false;

    final existing = students[idx];
    final updatedScores = Map<String, dynamic>.from(existing.scores);
    if (!updatedScores.containsKey(subject)) return false;

    updatedScores.remove(subject);
    students[idx] = StudentData(
      studentId: existing.studentId,
      name: existing.name,
      scores: updatedScores,
    );
    await _saveStudents(students);
    return true;
  }
}

// ==================== 日程管理 ====================

/// 手机端本地日程管理服务
class LocalScheduleService {
  static Future<Directory> _getScheduleDir() async {
    final config = await loadConfigFile();
    final basePath =
        config['BASE_PATH']?.toString() ?? (await getProjectDirectory()).path;
    final dir = Directory('$basePath/Schedule');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 读取某天的日程
  static Future<String?> loadItinerary(String dateStr) async {
    try {
      final dir = await _getScheduleDir();
      final safeDate = dateStr
          .replaceAll(' ', '_')
          .replaceAll('/', '-')
          .replaceAll(':', '-');
      final file = File('${dir.path}/$safeDate.md');
      if (await file.exists()) return await file.readAsString();
      return null;
    } catch (e) {
      debugPrint(">>> 读取日程失败: $e");
      return null;
    }
  }

  /// 保存日程
  static Future<void> saveItinerary(String dateStr, String content) async {
    try {
      final dir = await _getScheduleDir();
      final safeDate = dateStr
          .replaceAll(' ', '_')
          .replaceAll('/', '-')
          .replaceAll(':', '-');
      final file = File('${dir.path}/$safeDate.md');
      await file.writeAsString(content);
      debugPrint(">>> 日程已保存: ${file.path}");
    } catch (e) {
      debugPrint(">>> 保存日程失败: $e");
    }
  }

  /// 通过 AI 生成日程规划（手机端直连 API）
  static Future<Map<String, String>> generateSchedule({
    required String tasks,
    required String date,
    required String baseUrl,
    required String apiKey,
    required String model,
    List<String>? studyWeaknesses,
    String? weatherInfo, // 可选：天气信息，不传则由AI自行处理
  }) async {
    final studyAdviceSection =
        (studyWeaknesses != null && studyWeaknesses.isNotEmpty)
        ? '\n【学习情况参考】：该学生薄弱学科：${studyWeaknesses.join(", ")}。请在日程中合理插入复习时间。\n'
        : '';

    final weatherSection = (weatherInfo != null && weatherInfo.isNotEmpty)
        ? '\n【实时天气参考】：$weatherInfo\n'
        : '';

    final prompt =
        '''
你是一个集成了天气和交通信息的智能日程规划专家。请为用户生成一份日程规划。
【选定日期】：$date
$weatherSection
$studyAdviceSection
【待办任务】：$tasks

【输出要求】：
请严格按以下 JSON 格式返回，不要包含任何其他文字：
{
  "summary": "一句话总结今日行程重点（30字以内）",
  "detail": "完整的详细日程，包含：1. 今日天气与出行综述。2. 使用 Markdown 管道表格（Pipe Table）展示日程安排，表头列为：时间 | 任务 | 地点 | 环境建议。3. 结尾温馨提醒。"
}

【重要格式要求】：
- detail 中的表格必须使用 Markdown 管道表格语法（| 分隔列），切勿使用 HTML <table> 标签。
- 示例格式：
  | 时间 | 任务 | 地点 | 环境建议 |
  | --- | --- | --- | --- |
  | 07:00-08:00 | 晨跑 | 公园 | 注意防晒 |
'''
            .trim();

    final messages = <Map<String, String>>[
      {"role": "user", "content": prompt},
    ];

    final result = StringBuffer();
    await for (final chunk in directStreamChat(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
    )) {
      result.write(chunk);
    }

    final responseText = result.toString().trim();

    // 尝试解析 JSON
    try {
      // 移除可能的 markdown 代码块标记
      var clean = responseText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final parsed = json.decode(clean) as Map<String, dynamic>;
      final summary = parsed['summary']?.toString() ?? '已生成日程规划';
      final detail = parsed['detail']?.toString() ?? responseText;
      return {'summary': summary, 'detail': detail};
    } catch (_) {
      // JSON 解析失败，原样返回
      return {'summary': '已生成日程规划', 'detail': responseText};
    }
  }
}
