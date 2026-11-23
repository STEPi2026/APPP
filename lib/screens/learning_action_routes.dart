import 'package:flutter/material.dart';

import '../models/learning_next_action.dart';
import '../models/math_display.dart';
import '../services/learning_repository.dart';
import '../services/capture_service.dart';
import '../services/question_service.dart';
import '../services/related_question_service.dart';
import 'analysis_support_screen.dart';
import 'learning_support_screen.dart';
import 'capture_learning_screen.dart';
import 'problem_screen.dart';
import 'server_pathways.dart';
import 'learning_solution_screen.dart';

Future<void> showLearningHint(BuildContext context, String message) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFAF8FF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('생각을 여는 힌트'),
        content: SingleChildScrollView(
          child: SelectableText(
            displayMath(message),
            style: const TextStyle(height: 1.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인했어요'),
          ),
        ],
      ),
    );

Future<void> openLearningAction(
  BuildContext context,
  LearningNextAction action, {
  required LearningRepository repository,
  Map<dynamic, dynamic> response = const {},
  int? problemId,
  int? captureId,
  int? analysisId,
  Future<void> Function()? onHint,
  Future<void> Function()? onAnswer,
}) async {
  final data = {...response, ...LearningNextAction.payload(response)};
  int? positive(Object? value) => value is int && value > 0 ? value : null;
  final problem = positive(data['problem_id']) ?? positive(problemId);
  var photo = positive(data['captured_problem_id']) ?? positive(captureId);
  final aiId = positive(data['ai_analysis_id']) ?? positive(analysisId);
  Future<void> open(Widget screen) => Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => screen),
  );
  void unavailable(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  switch (action) {
    case LearningNextAction.hint:
      if (onHint != null) return onHint();
      if (aiId != null) {
        return open(
          AnalysisSupportScreen(
            analysisId: aiId,
            captureId: photo,
            problemId: problem,
            repository: repository,
          ),
        );
      }
      if (problem != null) {
        return open(
          LearningSupportScreen(
            problemTitle: '문제 도움',
            problemId: problem,
            repository: repository,
          ),
        );
      }
      unavailable('이 문제의 힌트 연결을 준비하고 있어요.');
      return;
    case LearningNextAction.checkAnswer:
      if (onAnswer != null) return onAnswer();
      if (problem != null) {
        return open(
          ProblemScreen(
            topic: '답 입력하기',
            repository: repository,
            openAnswerOnStart: true,
            questionService: ServerQuestionService(
              problemId: problem,
              repository: repository,
            ),
          ),
        );
      }
      unavailable('답을 제출할 문제 정보를 아직 받지 못했어요.');
      return;
    case LearningNextAction.showSolution:
      return open(LearningSolutionScreen(data: data));
    case LearningNextAction.relearn:
      final variant = data['variant_problem'];
      if (variant is Map &&
          positive(variant['id']) != null &&
          variant['prompt'] is String) {
        return open(
          TutorVariantScreen(
            problem: Map<String, dynamic>.from(variant),
            repository: repository,
          ),
        );
      }
      final skill = data['target_skill_code'];
      if (problem != null || (skill is String && skill.isNotEmpty)) {
        return open(
          ProblemScreen(
            topic: '한 문제 더 연습하기',
            repository: repository,
            questionService: RelatedQuestionService(
              problemId: problem,
              skillCode: problem == null ? skill as String : null,
              repository: repository,
              questionLimit: 1,
            ),
          ),
        );
      }
      unavailable('다음 연습 문제를 준비하고 있어요.');
      return;
    case LearningNextAction.confirmInput:
      if (photo == null && aiId != null) {
        try {
          final analysis = await repository.get('/api/v1/ai-analyses/$aiId');
          if (!context.mounted) return;
          if (analysis['id'] == aiId) {
            photo = positive(analysis['captured_problem_id']);
          }
        } catch (e) {
          if (context.mounted) unavailable(learningError(e));
          return;
        }
      }
      if (photo != null) {
        return open(
          CaptureLearningScreen(
            savedCaptureId: photo,
            service: CaptureService(repository: repository),
          ),
        );
      }
      unavailable('확인할 사진 정보를 아직 받지 못했어요. 사진을 먼저 올려 주세요.');
      return;
    case LearningNextAction.nextSkill:
      final skill = data['next_skill_code'];
      if (skill is String && skill.isNotEmpty) {
        return open(
          ProblemScreen(
            topic: '다음 개념 학습',
            repository: repository,
            questionService: ServerQuestionService(
              skillCode: skill,
              repository: repository,
            ),
          ),
        );
      }
      return open(ServerRoadmapScreen(repository: repository));
    case LearningNextAction.complete:
      return open(const LearningCompletionScreen());
  }
}
