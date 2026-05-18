import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

class ScoreResultPage extends StatelessWidget {
  final String userName;
  final Map<String, dynamic> scores;

  const ScoreResultPage({
    super.key,
    required this.userName,
    required this.scores,
  });

  @override
  Widget build(BuildContext context) {
    final entries = scores.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("查询结果"),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [

            Text(
              "姓名：$userName",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final e = entries[index];

                  return Card(
                    child: ListTile(
                      title: Text(e.key),
                      trailing: Text(
                        "${e.value}",
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SecondaryApp extends StatelessWidget {
  const SecondaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI聊天',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
        ),
      ),
      home: const ScoreResultPage(userName: "我",scores: {

      },),
    );
  }
}

@Preview()
Widget pagePreview() {
  return const SecondaryApp();
}