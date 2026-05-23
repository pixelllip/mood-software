import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class ScheduleDetailPage extends StatelessWidget {
  final String content;
  const ScheduleDetailPage({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("日程详细规划"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Container(
        color: Colors.grey.shade100,
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: SingleChildScrollView(
            child: MarkdownBody(
              data: content.replaceAll('```markdown', '').replaceAll('```', ''),
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(fontSize: 16, height: 1.6, color: Colors.black87),
                h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black),
                h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                tableBody: const TextStyle(fontSize: 14, color: Colors.black87),
                tableHead: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                tableBorder: TableBorder.all(color: Colors.black, width: 1),
                tableCellsPadding: const EdgeInsets.all(10),
                listBullet: const TextStyle(fontSize: 16, color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
