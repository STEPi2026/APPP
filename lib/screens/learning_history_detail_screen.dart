import 'package:flutter/material.dart';

import '../services/learning_repository.dart';
import '../services/student_learning_records.dart';
import 'recorded_problem_route.dart';
import 'captured_history_screen.dart';

class LearningHistoryDetailScreen extends StatefulWidget {
  final LearningRepository? repository;
  final Map<String, dynamic> record;
  final int? onlyQuestionNumber;

  const LearningHistoryDetailScreen({
    super.key,
    required this.record,
    this.onlyQuestionNumber,
    this.repository,
  });

  @override
  State<LearningHistoryDetailScreen> createState() =>
      _LearningHistoryDetailScreenState();
}

class _LearningHistoryDetailScreenState
    extends State<LearningHistoryDetailScreen> {
  late Map<String, dynamic> _record;

  bool _openingReview = false;

  @override
  void initState() {
    super.initState();
    _record = Map<String, dynamic>.from(widget.record);
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  late final _repo = widget.repository ?? LearningRepository();

  Future<void> _practice(Map<String, dynamic> answer) async {
    if (_openingReview || answer['problemId'] is! int) return;
    setState(() => _openingReview = true);
    try {
      await openRelatedPractice(context, _repo, problemId: answer['problemId']);
    } finally {
      if (mounted) setState(() => _openingReview = false);
    }
  }

  Future<void> _retryQuestion(Map<String, dynamic> answer) async {
    final id = answer['problemId'];
    if (_openingReview || id is! int) return;
    setState(() => _openingReview = true);
    try {
      await openRecordedProblem(context, id, _repo);
      if (!mounted) return;
      final rows = await StudentLearningRecords(_repo).wrongRows();
      final states = {
        for (final row in rows) row['problem_id']: row['resolved'],
      };
      if (!mounted) return;
      setState(() {
        for (final item in (_record['answers'] as List).whereType<Map>()) {
          if (states.containsKey(item['problemId'])) {
            item['reviewCompleted'] = states[item['problemId']];
          }
        }
      });
    } catch (e) {
      _showMessage(learningError(e));
    } finally {
      if (mounted) setState(() => _openingReview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawAnswers = _record['answers'];

    final answers = rawAnswers is List
        ? rawAnswers
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    final visibleIndexes = List<int>.generate(answers.length, (index) => index)
        .where((index) {
          final onlyQuestionNumber = widget.onlyQuestionNumber;

          if (onlyQuestionNumber == null) {
            return true;
          }

          final savedNumber = int.tryParse(
            '${answers[index]['questionNumber'] ?? index + 1}',
          );

          return savedNumber == onlyQuestionNumber;
        })
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_record['topic']?.toString() ?? '학습 상세'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF171717),
      ),

      body: visibleIndexes.isEmpty
          ? Center(
              child: Text(
                answers.isEmpty
                    ? '저장된 문제별 답변이 없어요.'
                    : '모든 오답의 복습이 완료됐어요!\n'
                          '스위치를 끄면 완료한 문제도 볼 수 있어요.',
                textAlign: TextAlign.center,
                style: const TextStyle(height: 1.8),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: visibleIndexes.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, visibleIndex) {
                final index = visibleIndexes[visibleIndex];
                final answer = answers[index];

                final isCorrect = answer['isCorrect'] == true;
                final isWrong = answer['isCorrect'] == false;
                final isPartial =
                    answer['isCorrect'] == null &&
                    answer['isPartialSolution'] == true;
                final reviewCompleted = answer['reviewCompleted'] == true;

                final resultColor = isCorrect
                    ? const Color(0xFF278B4B)
                    : isWrong
                    ? const Color(0xFFC94B4B)
                    : const Color(0xFF777777);

                final reviewColor = reviewCompleted
                    ? const Color(0xFF278B4B)
                    : const Color(0xFFC94B4B);

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F1FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '문제 ${answer['questionNumber'] ?? index + 1}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7652FF),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            isCorrect
                                ? '정답'
                                : isWrong
                                ? '오답'
                                : isPartial
                                ? '풀이가 끝나지 않았어요'
                                : '판정 보류',
                            style: TextStyle(
                              color: resultColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (isWrong)
                            Text(
                              reviewCompleted
                                  ? '복습 완료 ✓'
                                  : answer['reviewCompleted'] == false
                                  ? '미복습'
                                  : '복습 상태 확인 불가',
                              style: TextStyle(
                                color: reviewColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                      if (isWrong && reviewCompleted) ...[
                        const SizedBox(height: 8),
                        const Text(
                          '복습이 완료된 문제예요.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF278B4B),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        answer['title']?.toString() ?? '문제',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        answer['question']?.toString() ?? '',
                        style: const TextStyle(fontSize: 17, height: 1.5),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '제출한 답: '
                        '${answer['selectedAnswer'] ?? '정보 없음'}',
                        style: TextStyle(
                          fontSize: 16,
                          color: resultColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '정답: ${answer['correctAnswer'] ?? '정보 없음'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        '해설',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        answer['explanation']?.toString() ?? '해설이 없어요.',
                        style: const TextStyle(fontSize: 15, height: 1.6),
                      ),
                      if (answer['problemId'] is int) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _openingReview
                                ? null
                                : () => _retryQuestion(answer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: reviewCompleted
                                  ? const Color(0xFF278B4B)
                                  : const Color(0xFF9F86F7),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              isWrong
                                  ? (reviewCompleted
                                        ? '복습 완료 · 한 번 더 풀기'
                                        : '오답 다시 풀기')
                                  : '원래 문제 다시 풀기',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (answer['problemId'] is int) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _openingReview
                              ? null
                              : () => _practice(answer),
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('같은 개념의 다른 문제 풀기'),
                        ),
                      ],
                      if (answer['capturedProblemId'] is int) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => SavedCaptureScreen(
                                captureId: answer['capturedProblemId'],
                                repository: _repo,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('사진과 분석 결과 다시 보기'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}
