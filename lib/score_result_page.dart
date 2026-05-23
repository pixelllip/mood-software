import 'package:flutter/material.dart';

class ScoreResultPage extends StatelessWidget {
  final String userName;
  final String? studentId;
  final Map<String, dynamic> scores;

  const ScoreResultPage({
    super.key,
    required this.userName,
    this.studentId,
    required this.scores,
  });

  /// 将分数转为数值
  double _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// 根据分数返回颜色
  Color _scoreColor(double score) {
    if (score >= 90) return Colors.green;
    if (score >= 80) return Colors.blue;
    if (score >= 70) return Colors.orange;
    if (score >= 60) return Colors.amber.shade700;
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
              final color = _scoreColor(score);
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
                            value: score / 100.0,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 分数
                      SizedBox(
                        width: 60,
                        child: Text(
                          score.toStringAsFixed(
                            score == score.roundToDouble() ? 0 : 1,
                          ),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 18,
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
