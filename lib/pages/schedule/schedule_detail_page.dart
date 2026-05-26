import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class ScheduleDetailPage extends StatelessWidget {
  final String content;
  const ScheduleDetailPage({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text("日程详细规划"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Container(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: content.replaceAll('```markdown', '').replaceAll('```', ''),
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  fontSize: 16,
                  height: 1.6,
                  color: isDark ? const Color(0xFFE0E0E0) : Colors.black87,
                ),
                h1: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
                h2: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
                tableBody: TextStyle(
                  fontSize: 14,
                  color: isDark ? const Color(0xFFE0E0E0) : Colors.black87,
                ),
                tableHead: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
                tableBorder: TableBorder.all(
                  color: isDark ? Colors.grey.shade600 : Colors.black,
                  width: 1,
                ),
                tableCellsPadding: const EdgeInsets.all(10),
                listBullet: TextStyle(
                  fontSize: 16,
                  color: isDark ? const Color(0xFFE0E0E0) : Colors.black,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
