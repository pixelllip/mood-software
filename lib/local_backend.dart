import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ai_agent/backend_utils.dart';

// ==================== 成绩管理 ====================

/// 学生成绩数据模型（与 Kotlin/Python 后端格式一致）
class StudentData {
  final String studentId;
  final String name;
  final Map<String, dynamic> scores;

  const StudentData({
    required this.studentId,
    required this.name,
    this.scores = const {},
  });

  Map<String, dynamic> toJson() => {
    'student_id': studentId,
    'name': name,
    'scores': scores,
  };

  factory StudentData.fromJson(Map<String, dynamic> json) => StudentData(
    studentId: json['student_id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    scores: json['scores'] is Map
        ? Map<String, dynamic>.from(json['scores'] as Map)
        : {},
  );
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

  /// 标准化分数值（统一转为 num，字符串转数字）
  static dynamic _normalizeScore(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    if (v is String) {
      final parsed = double.tryParse(v);
      return parsed ?? 0;
    }
    return 0;
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

  /// 添加/更新成绩（自动标准化分数值）
  static Future<String> addScore({
    required String studentId,
    required String name,
    required Map<String, dynamic> scores,
  }) async {
    final students = await loadStudents();
    final idx = students.indexWhere((s) => s.studentId == studentId);

    // 标准化所有分数值
    final normalizedScores = <String, dynamic>{};
    for (final entry in scores.entries) {
      normalizedScores[entry.key] = _normalizeScore(entry.value);
    }

    if (idx >= 0) {
      // 更新已有学生
      final existing = students[idx];
      final merged = Map<String, dynamic>.from(existing.scores);
      merged.addAll(normalizedScores);
      students[idx] = StudentData(
        studentId: studentId,
        name: name,
        scores: merged,
      );
      await _saveStudents(students);
      return '已为学生 [$name] 更新/合并成绩。';
    } else {
      // 添加新学生
      students.add(
        StudentData(studentId: studentId, name: name, scores: normalizedScores),
      );
      await _saveStudents(students);
      return '成功录入新学生：$name';
    }
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
  "detail": "完整的详细日程，包含：1. 今日天气与出行综述。2. 使用 Markdown 表格展示日程安排（列：时间、任务、地点、环境建议）。3. 结尾温馨提醒。"
}
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
