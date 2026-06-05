import 'package:flutter/material.dart';
import 'package:ai_agent/services/local_backend.dart';

class ScoreResultPage extends StatelessWidget {
  final String userName;
  final String? studentId;
  final Map<String, dynamic> scores;
  final List<ExamRecord> examRecords; // 历史考试记录

  const ScoreResultPage({
    super.key,
    required this.userName,
    this.studentId,
    required this.scores,
    this.examRecords = const [],
  });

  /// 将分数转为数值（兼容旧版纯数字和新版对象格式）
  double _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    if (v is Map) {
      final score = v['score'];
      if (score is num) return score.toDouble();
      return double.tryParse(score?.toString() ?? '') ?? 0;
    }
    return double.tryParse(v.toString()) ?? 0;
  }

  /// 获取满分（兼容旧版纯数字和新版对象格式）
  double _getFullMark(dynamic v) {
    if (v is Map && v.containsKey('fullMark')) {
      final fm = v['fullMark'];
      if (fm is num) return fm.toDouble();
      return double.tryParse(fm?.toString() ?? '') ?? 100;
    }
    return 100; // 默认满分
  }

  /// 计算百分比（相对于满分）
  double _scorePercent(dynamic v) {
    final score = _toNum(v);
    final fullMark = _getFullMark(v);
    if (fullMark <= 0) return 0;
    return score / fullMark;
  }

  /// 根据分数百分比返回颜色
  Color _scoreColor(double percent) {
    if (percent >= 0.9) return Colors.green;
    if (percent >= 0.8) return Colors.blue;
    if (percent >= 0.7) return Colors.orange;
    if (percent >= 0.6) return Colors.amber.shade700;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final entries = scores.entries.toList();
    final total = entries.fold<double>(0, (sum, e) => sum + _toNum(e.value));
    final average = entries.isNotEmpty ? total / entries.length : 0.0;
    final passed = entries.where((e) => _toNum(e.value) >= 60).length;
    final failed = entries.length - passed;

    return Scaffold(
      appBar: AppBar(
        title: const Text("查询结果"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 学生信息卡片
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Theme.of(context).primaryColor,
                        child: Text(
                          userName.isNotEmpty ? userName[0] : '?',
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (studentId != null && studentId!.isNotEmpty)
                              Text(
                                "学号: $studentId",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 成绩概览卡片
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildSummaryItem(
                    context,
                    icon: Icons.pie_chart,
                    label: "科目数",
                    value: "${entries.length}",
                    color: Colors.deepPurple,
                  ),
                  _buildDivider(),
                  _buildSummaryItem(
                    context,
                    icon: Icons.calculate,
                    label: "总分",
                    value: total.toStringAsFixed(
                      total == total.roundToDouble() ? 0 : 1,
                    ),
                    color: Colors.blue,
                  ),
                  _buildDivider(),
                  _buildSummaryItem(
                    context,
                    icon: Icons.trending_up,
                    label: "平均分",
                    value: average.toStringAsFixed(1),
                    color: average >= 60 ? Colors.green : Colors.red,
                  ),
                  _buildDivider(),
                  _buildSummaryItem(
                    context,
                    icon: Icons.check_circle_outline,
                    label: "及格/不及格",
                    value: "$passed/$failed",
                    color: passed > failed ? Colors.green : Colors.red,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 各科成绩标题
          Row(
            children: [
              const Text(
                "各科成绩",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(
                "${entries.length} 门课程",
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 各科成绩列表
          if (entries.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text("暂无成绩数据", style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...entries.map((e) {
              final score = _toNum(e.value);
              final fullMark = _getFullMark(e.value);
              final percent = _scorePercent(e.value);
              final color = _scoreColor(percent);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: color.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      // 左侧科目名
                      SizedBox(
                        width: 100,
                        child: Text(
                          e.key,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 进度条
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: percent.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 分数（含满分）
                      SizedBox(
                        width: fullMark != 100 ? 90 : 60,
                        child: Text(
                          fullMark != 100
                              ? '${score.toStringAsFixed(score == score.roundToDouble() ? 0 : 1)}/$fullMark'
                              : score.toStringAsFixed(
                                  score == score.roundToDouble() ? 0 : 1,
                                ),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          // 成绩趋势历史（有历史记录时显示）
          if (examRecords.length >= 2) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.trending_up, size: 20),
                const SizedBox(width: 6),
                const Text(
                  "成绩趋势",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  "${examRecords.length} 次记录",
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 每个科目的历史趋势
            ...entries.map((e) {
              final subject = e.key;
              // 提取该科目的历史记录
              final history = <Map<String, dynamic>>[];
              for (final record in examRecords) {
                final score = record.scores[subject];
                if (score != null) {
                  history.add({
                    'date': record.date.split(' ')[0],
                    'label': record.label ?? record.examType,
                    'score': LocalScoreService.extractScore(score),
                    'fullMark': LocalScoreService.extractFullMark(score),
                  });
                }
              }
              if (history.length < 2) return const SizedBox.shrink();

              // 计算变化
              final latest = history.last;
              final prev = history[history.length - 2];
              final change = latest['score'] - prev['score'];
              final isUp = change > 0;
              final isDown = change < 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              subject,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (isUp)
                              Icon(
                                Icons.trending_up,
                                size: 18,
                                color: Colors.green,
                              )
                            else if (isDown)
                              Icon(
                                Icons.trending_down,
                                size: 18,
                                color: Colors.red,
                              )
                            else
                              Icon(
                                Icons.remove_red_eye,
                                size: 18,
                                color: Colors.grey,
                              ),
                            const SizedBox(width: 4),
                            Text(
                              isUp
                                  ? '+${change.toStringAsFixed(change == change.roundToDouble() ? 0 : 1)}'
                                  : isDown
                                  ? change.toStringAsFixed(
                                      change == change.roundToDouble() ? 0 : 1,
                                    )
                                  : '持平',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isUp
                                    ? Colors.green
                                    : isDown
                                    ? Colors.red
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 简易历史点状图（文字版）
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: history.map((h) {
                              final fm = h['fullMark'] as double;
                              final s = h['score'] as double;
                              final pct = fm > 0 ? s / fm : 0.0;
                              final color = _scoreColor(pct);
                              final dateStr = h['date'].toString();
                              final shortDate = dateStr.length >= 5
                                  ? dateStr.substring(5)
                                  : dateStr;
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          s.toStringAsFixed(
                                            s == s.roundToDouble() ? 0 : 1,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      shortDate,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                    Text(
                                      h['label'].toString(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(width: 1, height: 50, color: Colors.grey.shade300);
  }
}
