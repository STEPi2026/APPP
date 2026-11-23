// 피그마 시안(image_fc8dde.png 5번째 화면 '< 오답 정복!': 전체/미복습/복습완료 칩 + 쎈 공통수학1 - 425번 카드 + #단순 계산 실수 #이항 부호 오류 해시태그 + 보라색 다시 풀기 버튼)
import 'package:flutter/material.dart';

import '../services/learning_repository.dart';
import '../services/student_learning_records.dart';
import 'learning_history_detail_screen.dart';
import 'recorded_problem_route.dart';

class WrongAnswerScreen extends StatefulWidget {
  final LearningRepository? repository;
  const WrongAnswerScreen({super.key, this.repository});

  @override
  State<WrongAnswerScreen> createState() => _WrongAnswerScreenState();
}

class _WrongAnswerScreenState extends State<WrongAnswerScreen> {
  static const _purple = Color(0xFF7C5CFA);
  static const _lightPurple = Color(0xFFF3EEFF);
  static const _textColor = Color(0xFF171717);
  static const _mutedColor = Color(0xFF888888);

  late Future<List<Map<String, dynamic>>> _wrongAnswers;
  int _selectedFilterIndex = 0; // 0: 전체, 1: 미복습, 2: 복습 완료

  @override
  void initState() {
    super.initState();
    _wrongAnswers = _loadWrongAnswers();
  }

  late final _repo = widget.repository ?? LearningRepository();
  Future<List<Map<String, dynamic>>> _loadWrongAnswers() =>
      StudentLearningRecords(_repo).wrongAnswers();

  void _reload() {
    setState(() {
      _wrongAnswers = _loadWrongAnswers();
    });
  }

  bool _openingReview = false;
  Future<void> _openRelated(Map<String, dynamic> item) async {
    final id = item['answer']['problemId'];
    if (_openingReview || id is! int) return;
    setState(() => _openingReview = true);
    try {
      await openRelatedPractice(context, _repo, problemId: id);
      if (mounted) _reload();
    } finally {
      if (mounted) setState(() => _openingReview = false);
    }
  }

  Future<void> _openRetryFlow(Map<String, dynamic> item) async {
    final id = item['answer']['problemId'];
    if (_openingReview || id is! int) return;
    setState(() => _openingReview = true);
    try {
      await openRecordedProblem(context, id, _repo);
      _reload();
    } finally {
      if (mounted) setState(() => _openingReview = false);
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final answer = item['answer'] as Map<String, dynamic>;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => LearningHistoryDetailScreen(
          repository: _repo,
          record: {
            'topic': item['topic'] ?? '오답 상세',
            'completedAt': item['completedAt'],
            'answers': [answer],
          },
          onlyQuestionNumber: int.tryParse('${answer['questionNumber']}'),
        ),
      ),
    );

    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
        ),
        titleSpacing: 0,
        title: const Text(
          '오답 정복!',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _wrongAnswers,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(learningError(snapshot.error!)),
                  TextButton(onPressed: _reload, child: const Text('다시 불러오기')),
                ],
              ),
            );
          }
          final allItems = snapshot.data ?? [];
          final filtered = allItems.where((item) {
            final ans = item['answer'] as Map<String, dynamic>;
            final done = ans['reviewCompleted'] == true;
            if (_selectedFilterIndex == 1) {
              return ans['reviewCompleted'] == false;
            }
            if (_selectedFilterIndex == 2) return done;
            return true;
          }).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _buildFilterPill('전체 (${allItems.length})', 0),
                        _buildFilterPill('미복습', 1),
                        _buildFilterPill('복습 완료', 2),
                      ],
                    ),
                  ),

                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('표시할 오답이 없어요.'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            itemCount: filtered.length,
                            separatorBuilder: (context, idx) =>
                                const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final answer =
                                  item['answer'] as Map<String, dynamic>;
                              final isDone = answer['reviewCompleted'] == true;
                              final sourceLabel =
                                  item['sourceLabel']?.toString() ?? '오답 문제';
                              final tags =
                                  (item['tags'] as List?)?.cast<String>() ??
                                  const <String>[];

                              return Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: isDone
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFFD6BCFA),
                                    width: 1.5,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x0A000000),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: isDone
                                                ? const Color(0xFF86CA9A)
                                                : const Color(0xFFF6B8B8),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              isDone
                                                  ? '정복완료'
                                                  : answer['reviewCompleted'] ==
                                                        false
                                                  ? '미복습'
                                                  : '확인 중',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () => _openDetail(item),
                                          child: const Text(
                                            '풀이 상세 보기',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _mutedColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      sourceLabel,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: _textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      answer['question']?.toString() ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF555555),
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: tags.map((tag) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDone
                                                ? const Color(0xFFF2F2F5)
                                                : _lightPurple,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            tag,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: isDone
                                                  ? _mutedColor
                                                  : _purple,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 16),

                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _openingReview
                                            ? null
                                            : () => _openRetryFlow(item),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _purple,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 15,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          isDone ? '한 번 더 풀기' : '원래 문제 다시 풀기',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: _openingReview
                                          ? null
                                          : () => _openRelated(item),
                                      icon: const Icon(
                                        Icons.auto_awesome_rounded,
                                      ),
                                      label: const Text('같은 개념의 다른 문제 풀기'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterPill(String label, int index) {
    final active = _selectedFilterIndex == index;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() => _selectedFilterIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFD8DFEE) : const Color(0xFFEDF0F7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w900 : FontWeight.w600,
            color: _textColor,
          ),
        ),
      ),
    );
  }
}
