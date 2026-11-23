import 'dart:math';

import '../models/practice_question.dart';
import 'learning_repository.dart';
import 'question_service.dart';

/// Catalog practice sharing a verified Skill, not an AI-generated variant.
class RelatedQuestionService implements QuestionService {
  final int? problemId;
  final String? skillCode;
  final LearningRepository repository;
  final Random? random;
  final int questionLimit;
  const RelatedQuestionService({
    this.problemId,
    this.skillCode,
    required this.repository,
    this.random,
    this.questionLimit = 3,
  }) : assert((problemId == null) != (skillCode == null)),
       assert(questionLimit > 0);

  @override
  Future<List<PracticeQuestion>> fetchQuestions() async {
    final skills = <String>{};
    if (problemId != null) {
      final source = await repository.get('/api/v1/problems/$problemId');
      if (source['id'] != problemId) {
        throw const FormatException('원래 문제를 확인하지 못했어요.');
      }
      final codes = source['skill_codes'];
      if (codes is List) {
        skills.addAll(codes.whereType<String>().where((c) => c.isNotEmpty));
      }
    } else if (skillCode?.isNotEmpty == true) {
      skills.add(skillCode!);
    }
    if (skills.isEmpty) throw const FormatException('이 문제의 개념 연결은 아직 준비 중이에요.');
    final result = <PracticeQuestion>[], seen = <int>{};
    for (final usage in ['RELEARNING', 'PRACTICE']) {
      for (final skill in skills) {
        final rows = await repository.all('/api/v1/problems', {
          'skill_code': skill,
          'usage': usage,
        });
        for (final row in rows) {
          if (row['usage'] != usage ||
              row['id'] == problemId ||
              row['skill_codes'] is! List ||
              !(row['skill_codes'] as List).contains(skill)) {
            continue;
          }
          final question = PracticeQuestion.fromServerJson(
            row,
            title: '같은 개념 연습',
          );
          if (seen.add(question.problemId!)) result.add(question);
        }
      }
    }
    if (result.isEmpty) {
      throw const FormatException('같은 개념의 다른 문제가 아직 없어요. 원래 문제를 다시 풀 수 있어요.');
    }
    final lastAttempts = <int, DateTime>{};
    try {
      for (final attempt in await repository.all(
        '/api/v1/me/learning-history',
      )) {
        final id = attempt['problem_id'];
        final time = DateTime.tryParse('${attempt['attempted_at']}')?.toUtc();
        if (id is int) {
          final date =
              time ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
          if (!lastAttempts.containsKey(id) ||
              date.isAfter(lastAttempts[id]!)) {
            lastAttempts[id] = date;
          }
        }
      }
    } catch (_) {
      // The catalog remains usable when optional history cannot be loaded.
    }
    result.shuffle(random ?? Random());
    final tieOrder = {
      for (int i = 0; i < result.length; i++) result[i].problemId: i,
    };
    result.sort((a, b) {
      final aTime = lastAttempts[a.problemId],
          bTime = lastAttempts[b.problemId];
      if (aTime == null && bTime != null) return -1;
      if (aTime != null && bTime == null) return 1;
      if (aTime != null && bTime != null) {
        final dateOrder = aTime.compareTo(bTime);
        if (dateOrder != 0) return dateOrder;
      } else {
        final usageOrder = (a.purpose == 'RELEARNING' ? 0 : 1).compareTo(
          b.purpose == 'RELEARNING' ? 0 : 1,
        );
        if (usageOrder != 0) return usageOrder;
      }
      return tieOrder[a.problemId]!.compareTo(tieOrder[b.problemId]!);
    });
    return result.take(questionLimit).toList();
  }
}
