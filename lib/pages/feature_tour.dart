import 'package:flutter/material.dart';

/// 功能引导步骤数据
class _TourStep {
  final String title;
  final String description;
  final IconData icon;

  const _TourStep({
    required this.title,
    required this.description,
    required this.icon,
  });
}

/// 独立全屏功能引导页面
/// 使用 Navigator.push 导航，避免被误判为广告弹窗。
class FeatureTour {
  static const List<_TourStep> _steps = [
    _TourStep(
      title: '💬 AI 聊天',
      description:
          '与 AI 智能助手进行学习对话，支持 Markdown 渲染和 LaTeX 公式显示。\n'
          '可以上传代码/文本文件进行分析，或上传图片进行 OCR 识别。\n'
          '目前暂不支持图片识物。',
      icon: Icons.chat_bubble_outline,
    ),
    _TourStep(
      title: '📊 成绩管理',
      description:
          '查询、添加、修改考试成绩，支持多科目管理。\n'
          '自动记录历史成绩变化，检测退步科目。',
      icon: Icons.assessment_outlined,
    ),
    _TourStep(
      title: '📅 日程安排',
      description:
          '使用 Markdown 编辑器手动规划学习日程，\n'
          '或让 AI 根据待办任务和薄弱学科一键生成日程。\n'
          '还能自动寻找成绩库中与您设置里的姓名学号相符的学科*，\n'
          '作为生成日程的参数。\n\n'
          '*您可以选择先添加成绩信息，再将设置中的学号姓名改成与您的添加项一致。',
      icon: Icons.event_note_outlined,
    ),
    _TourStep(
      title: '📖 每日学情',
      description:
          '自动匹配学习关键词，分析对话记录中的学习内容。\n'
          '综合匹配条数和日程完成率，生成每日评分和鼓励语。',
      icon: Icons.auto_stories_outlined,
    ),
  ];

  /// 导航到全屏功能引导页面，完成后调用 [onCompleted] 并返回
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onCompleted,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _TourPage(onCompleted: onCompleted),
      ),
    );
  }
}

class _TourPage extends StatefulWidget {
  final VoidCallback onCompleted;
  const _TourPage({required this.onCompleted});

  @override
  State<_TourPage> createState() => _TourPageState();
}

class _TourPageState extends State<_TourPage> {
  int _currentStep = 0;

  void _nextStep() {
    if (_currentStep < FeatureTour._steps.length - 1) {
      setState(() => _currentStep++);
    } else {
      widget.onCompleted();
      Navigator.of(context).pop();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = FeatureTour._steps[_currentStep];
    final isFirst = _currentStep == 0;
    final isLast = _currentStep == FeatureTour._steps.length - 1;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: theme.appBarTheme.systemOverlayStyle,
        actions: [
          
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            children: [
              const Spacer(flex: 1),
              // 步骤指示器
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  FeatureTour._steps.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: i == _currentStep ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i == _currentStep
                          ? theme.primaryColor
                          : (isDark
                              ? Colors.grey.shade600
                              : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 56),
              // 图标
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  step.icon,
                  size: 64,
                  color: theme.primaryColor,
                ),
              ),
              const SizedBox(height: 36),
              // 标题
              Text(
                step.title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              // 描述
              Text(
                step.description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark ? Colors.grey.shade300 : Colors.black54,
                  height: 1.7,
                  fontSize: 16,
                ),
              ),
              const Spacer(flex: 2),
              // 按钮行
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (!isFirst)
                    OutlinedButton.icon(
                      onPressed: _prevStep,
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('上一步'),
                    )
                  else
                    const SizedBox.shrink(),
                  FilledButton.icon(
                    onPressed: _nextStep,
                    icon: isLast
                        ? const Icon(Icons.rocket_launch, size: 18)
                        : const Icon(Icons.arrow_forward, size: 18),
                    label: Text(isLast ? '开始使用' : '下一步'),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
