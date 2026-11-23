import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/models/learning_next_action.dart';
import 'package:stepi/models/math_display.dart';
import 'package:stepi/screens/learning_action_routes.dart';
import 'package:stepi/screens/learning_solution_screen.dart';
import 'package:stepi/screens/problem_screen.dart';
import 'package:stepi/screens/server_pathways.dart';
import 'package:stepi/services/learning_repository.dart';

import 'normal_problem_flow_test.dart' as flow;
import 'ocr_correction_flow_test.dart' as ocr;

Future<void> route(
  WidgetTester tester,
  LearningNextAction action,
  LearningRepository repo, {
  Map<String, dynamic> response = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openLearningAction(
              context,
              action,
              repository: repo,
              response: response,
            ),
            child: const Text('이어가기'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('이어가기'));
  await tester.pumpAndSettle();
}

Future<void> tapAction(WidgetTester tester, String text) async {
  final target = find.widgetWithText(FilledButton, text);
  await ocr.ensureTarget(tester, target);
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'math formatting preserves raw values and does not evaluate answers',
    () {
      expect(displayMath('x^2 + x^{-12} + 2*x'), 'x² + x⁻¹² + 2×x');
      expect(displayMath('x^n + 3/2'), 'x^n + 3/2');
      final q = PracticeQuestion.fromServerJson({
        ...flow.problem(23),
        'question': 'x^2',
        'problem_type': 'MULTIPLE_CHOICE',
        'choices': [
          {'label': 'x^2', 'value': 'x^2'},
        ],
      }, title: '식');
      expect(q.displayChoice(0), 'x²');
      expect(q.choiceAnswer(0), 'x^2');
    },
  );

  testWidgets('HINT requests the real problem and leaves counting to Backend', (
    tester,
  ) async {
    final writes = <Map<String, dynamic>>[];
    final repo = LearningRepository(
      write: (m, p, b) async {
        expect(p, '/api/v1/tutor/help');
        writes.add(Map<String, dynamic>.from(b as Map));
        return {
          'tutor_action_id': 8,
          'action_type': 'SOCRATIC_HINT',
          'content': {'message': 'x^2 항을 보세요.', 'hint_level': 1},
          'next_stage': 'hint',
        };
      },
    );
    await route(
      tester,
      LearningNextAction.hint,
      repo,
      response: {'problem_id': 23},
    );
    expect(writes, [
      {'problem_id': 23, 'stage': 'hint'},
    ]);
    expect(find.text('x² 항을 보세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'CHECK_ANSWER opens canonical input, displays math, submits raw syntax',
    (tester) async {
      final writes = <String>[];
      final repo = LearningRepository(
        read: (p, q) async => p == '/api/v1/problems/23'
            ? {...flow.problem(23), 'question': 'x^2 + 2*x를 정리하세요.'}
            : flow.read(p, q),
        write: (m, p, b) async {
          writes.add(p);
          if (p.endsWith('/learning-sessions')) return {'id': 51};
          if (p.endsWith('/tutor/session')) {
            expect((b as Map)['answer'], 'x^2+2*x');
            return flow.accepted();
          }
          return {};
        },
      );
      await route(
        tester,
        LearningNextAction.checkAnswer,
        repo,
        response: {'problem_id': 23},
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(mathInputGuide), findsOneWidget);
      expect(writes, isEmpty);
      await tester.enterText(find.byType(TextField), 'x^2+2*x');
      await flow.tapText(tester, '답안 저장하기');
      expect(find.text('x² + 2×x를 정리하세요.'), findsOneWidget);
      await flow.tapText(tester, '제출하기');
      expect(writes.where((p) => p.endsWith('/tutor/session')), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SHOW_SOLUTION displays supplied solution and never treats OCR steps as explanation',
    (tester) async {
      var calls = 0;
      final repo = LearningRepository(
        read: (p, q) async {
          calls++;
          return {};
        },
        write: (m, p, b) async {
          calls++;
          return {};
        },
      );
      await route(
        tester,
        LearningNextAction.showSolution,
        repo,
        response: {
          'solution_steps': ['student x=999'],
          'content': {'explanation': '개념 설명일 뿐'},
        },
      );
      expect(find.textContaining('해설을 아직 불러올 수 없어요'), findsOneWidget);
      expect(find.textContaining('999'), findsNothing);
      expect(calls, 0);
      await flow.tapText(tester, '원래 학습으로 돌아가기');
      await tester.pumpWidget(const SizedBox.shrink());
      await route(
        tester,
        LearningNextAction.showSolution,
        repo,
        response: {'solution': 'x^2=4 이므로 x=±2', 'correct_answer': '±2'},
      );
      expect(find.text('x²=4 이므로 x=±2'), findsOneWidget);
      expect(find.text('정답: ±2'), findsOneWidget);
    },
  );

  testWidgets(
    'CONFIRM_INPUT resumes exact photo for correction without guessing Skill or analyzing',
    (tester) async {
      final reads = <String>[], writes = <String>[];
      final repo = LearningRepository(
        read: (p, q) async {
          reads.add(p);
          expect(p, '/api/v1/captured-problems/77');
          return {
            'id': 77,
            'session_id': 51,
            'ocr_status': 'PARTIAL',
            'ocr_raw_text': 'x^2=4\nx=2',
            'problem_text': null,
            'solution_text': null,
          };
        },
        write: (m, p, b) async {
          writes.add(p);
          return {};
        },
      );
      await route(
        tester,
        LearningNextAction.confirmInput,
        repo,
        response: {'captured_problem_id': 77},
      );
      expect(find.byKey(const ValueKey('ocr-problem')), findsOneWidget);
      expect(find.text('x^2=4\nx=2'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(reads, ['/api/v1/captured-problems/77']);
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RELEARN after correct result opens one different problem and never reposts original rewards',
    (tester) async {
      var submits = 0;
      final repo = LearningRepository(
        read: (p, q) async {
          if (p == '/api/v1/problems/23') return flow.problem(23);
          if (p == '/api/v1/problems/24') {
            return {...flow.problem(24), 'question': '연습 24'};
          }
          if (p == '/api/v1/problems') {
            return {
              'items': [
                for (var id = 24; id <= 26; id++)
                  {
                    ...flow.problem(id),
                    'question': '연습 $id',
                    'usage': q['usage'],
                  },
              ],
              'total_pages': 1,
            };
          }
          if (p.endsWith('/learning-history')) {
            return {'items': [], 'total_pages': 1};
          }
          return flow.read(p, q);
        },
        write: (m, p, b) async {
          if (p.endsWith('/learning-sessions')) return {'id': 51};
          if (p.endsWith('/tutor/session')) {
            if ((b as Map)['action'] == 'RELEARN') {
              return {
                ...flow.accepted(),
                'action': 'RELEARN',
                'answer_correct': null,
                'next_action': 'CHECK_ANSWER',
                'next_problem': {'id': 24, 'prompt': '연습 24'},
              };
            }
            submits++;
            return {...flow.accepted(), 'next_action': 'RELEARN'};
          }
          return {};
        },
      );
      await flow.open(tester, repo);
      await flow.enterAnswer(tester, '5');
      await flow.tapText(tester, '제출하기');
      expect(find.text('정답'), findsOneWidget);
      await tapAction(tester, '한 문제 더 연습하기');
      await tapAction(tester, '이 문제 풀기');
      final screen = tester.widget<ProblemScreen>(
        find.byType(ProblemScreen).last,
      );
      expect((await screen.questionService.fetchQuestions()), hasLength(1));
      expect(find.text('2와 3을 더하면?'), findsNothing);
      expect(submits, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('NEXT_SKILL uses only server target; no target opens roadmap', (
    tester,
  ) async {
    final queries = <String?>[];
    final repo = LearningRepository(
      read: (p, q) async {
        if (p == '/api/v1/problems') {
          queries.add(q['skill_code']);
          return {
            'items': [
              {
                ...flow.problem(62),
                'question': '다음 개념 문제',
                'skill_codes': ['S2'],
              },
            ],
            'total_pages': 1,
          };
        }
        return {};
      },
    );
    await route(
      tester,
      LearningNextAction.nextSkill,
      repo,
      response: {'next_skill_code': 'S2'},
    );
    expect(queries, ['S2']);
    expect(find.text('다음 개념 문제'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await route(tester, LearningNextAction.nextSkill, repo);
    expect(find.byType(ServerRoadmapScreen), findsOneWidget);
    expect(queries, ['S2']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completion only displays server action and does not grant rewards',
    (tester) async {
      var writes = 0;
      final repo = LearningRepository(
        write: (m, p, b) async {
          writes++;
          return {};
        },
      );
      await route(tester, LearningNextAction.complete, repo);
      expect(find.byType(LearningCompletionScreen), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'help CHECK_ANSWER returns to same draft without another problem or submission',
    (tester) async {
      final writes = <String>[];
      final repo = LearningRepository(
        read: flow.read,
        write: (m, p, b) async {
          writes.add(p);
          expect(p, '/api/v1/tutor/session');
          return {
            'scenario': 'RECOMMENDED',
            'action': 'HINT',
            'problem_id': 23,
            'status': 'PROVIDED',
            'message': '이제 답을 적어볼까요?',
            'next_action': 'CHECK_ANSWER',
            'content': {'message': '이제 답을 적어볼까요?'},
          };
        },
      );
      await flow.open(tester, repo);
      await flow.enterAnswer(tester, '5');
      await flow.tapText(tester, '모르겠어요');
      await tapAction(tester, '답 입력하기');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '5',
      );
      expect(writes, ['/api/v1/tutor/session']);
      expect(tester.takeException(), isNull);
    },
  );
}
