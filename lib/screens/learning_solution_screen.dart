import 'package:flutter/material.dart';

import '../models/math_display.dart';

/// Shows explicitly supplied solution data, never the student's OCR steps.
class LearningSolutionScreen extends StatelessWidget {
  final Map<dynamic, dynamic> data;
  const LearningSolutionScreen({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final sessionSolution = data['solution'] is Map
        ? data['solution'] as Map
        : null;
    final steps = sessionSolution?['steps'];
    final solution = data['solution'] is String
        ? data['solution'] as String
        : data['explanation'] is String
        ? data['explanation'] as String
        : '';
    // Never expose solution.answer, the backend's grading notation.
    final answer = sessionSolution != null
        ? sessionSolution['answer_display']
        : data['correct_answer'];
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(title: const Text('문제 해설')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3EEFF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '풀이를 함께 살펴봐요',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7C5CFA),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (answer is String && answer.trim().isNotEmpty) ...[
                      Text(
                        '정답: ${displayMath(answer)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (steps is List && steps.whereType<String>().isNotEmpty)
                      for (final (index, step)
                          in steps.whereType<String>().indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: SelectableText(
                            '${index + 1}. ${displayMath(step)}',
                            style: const TextStyle(height: 1.8),
                          ),
                        )
                    else
                      SelectableText(
                        solution.trim().isEmpty
                            ? '이 문제의 해설을 아직 불러올 수 없어요. 원래 문제로 돌아가 도움을 받거나 잠시 후 다시 확인해 주세요.'
                            : displayMath(solution),
                        style: const TextStyle(height: 1.8),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('원래 학습으로 돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LearningCompletionScreen extends StatelessWidget {
  const LearningCompletionScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8FF),
    appBar: AppBar(title: const Text('학습 완료')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF7C5CFA),
              size: 64,
            ),
            const SizedBox(height: 20),
            const Text(
              '이번 학습을 마쳤어요!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            const Text(
              '차근차근 쌓은 실력을 다음 학습에서도 이어가요.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('학습 화면으로 돌아가기'),
            ),
          ],
        ),
      ),
    ),
  );
}
