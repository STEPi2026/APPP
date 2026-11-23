import 'package:flutter/material.dart';

import '../services/learning_repository.dart';
import '../services/question_service.dart';
import '../services/related_question_service.dart';
import 'problem_screen.dart';

Future<void> openRecordedProblem(
  BuildContext context,
  int id,
  LearningRepository repo,
) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ProblemScreen(
      topic: '문제 다시 풀기',
      repository: repo,
      questionService: ServerQuestionService(
        unit: '오답 복습',
        problemId: id,
        repository: repo,
      ),
    ),
  ),
);

Future<void> openRelatedPractice(
  BuildContext context,
  LearningRepository repo, {
  int? problemId,
  String? skillCode,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ProblemScreen(
      topic: '같은 개념 연습',
      repository: repo,
      questionService: RelatedQuestionService(
        repository: repo,
        problemId: problemId,
        skillCode: skillCode,
      ),
    ),
  ),
);
