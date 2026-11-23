import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepi/models/learning_next_action.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/learning_storage.dart';
import 'package:stepi/services/tutor_help_service.dart';
import 'package:stepi/screens/problem_result_dialog.dart';
import 'package:stepi/screens/analysis_support_screen.dart';
import 'package:stepi/screens/learning_support_screen.dart';

void main() {
  testWidgets(
    'correct variant answer can request RELEARN through nested feedback',
    (tester) async {
      final repo = LearningRepository(
        write: (m, p, b) async => {
          'correct': true,
          'feedback': {
            'next_step': 'RELEARN',
            'content': {'message': '정답이에요. 같은 개념을 더 연습해요.'},
          },
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TutorVariantScreen(
            problem: const {'id': 7, 'prompt': '2+3은?'},
            repository: repo,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '5');
      await tester.tap(find.text('제출하기'));
      await tester.pumpAndSettle();
      expect(find.text('정답이에요!'), findsOneWidget);
      expect(find.text('한 문제 더 연습하기'), findsWidgets);
      expect(find.text('다시 생각해 볼까요?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'correct answer with RELEARN stays correct and offers more practice',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProblemResultDialog(
              result: {
                'is_correct': true,
                'next_step': 'RELEARN',
                'mastery_score': 0.7,
                'rewards': {'xp': 5},
              },
              experience: ExperienceProgress(25),
              isLast: true,
            ),
          ),
        ),
      );
      expect(find.text('정답'), findsOneWidget);
      expect(find.text('훌륭한 풀이입니다!'), findsOneWidget);
      expect(find.text('한 문제 더 연습하기'), findsWidgets);
      expect(find.text('오답'), findsNothing);
      expect(find.textContaining('재학습'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test('server action controls the label independently of local mastery or correctness', () {
    expect(
      LearningNextAction.fromResponse({
        'is_correct': true,
        'mastery_score': 0.2,
        'next_action': 'NEXT_SKILL',
      }),
      LearningNextAction.nextSkill,
    );
    expect(
      LearningNextAction.fromResponse({'next_step': 'LEARNING_COMPLETE'}),
      LearningNextAction.complete,
    );
    expect(
      LearningNextAction.fromResponse({
        'is_correct': true,
        'mastery_score': 1.0,
      }),
      isNull,
    );
    expect(LearningNextAction.fromCode('PREREQUISITE_REVIEW'), isNull);
  });
  testWidgets(
    'analysis help does not call a correct learner mistaken for RELEARN',
    (tester) async {
      final repo = LearningRepository(
        write: (m, p, b) async => {
          'tutor_action_id': 8,
          'action_type': 'HINT',
          'is_correct': true,
          'next_step': 'RELEARN',
          'mastery_score': 0.7,
          'content': {'message': '같은 개념을 더 연습해 봐요.'},
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AnalysisSupportScreen(analysisId: 42, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('한 문제 더 연습하기'), findsWidgets);
      expect(find.text('실수한 부분부터,\n함께 한 걸음씩!'), findsNothing);
      expect(find.textContaining('재학습'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pre-submission help shows the server next action without implying an incorrect answer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LearningSupportScreen(
            problemTitle: '개념 연습',
            request: ({String? stage, String? skillCode}) async =>
                const TutorHelpResult(
                  actionId: 8,
                  actionType: 'CONCEPT_REVIEW',
                  message: '개념을 더 익혀봐요.',
                  nextAction: 'RELEARN',
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('한 문제 더 연습하기'), findsWidgets);
      expect(find.text('오답'), findsNothing);
      expect(find.textContaining('재학습'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
