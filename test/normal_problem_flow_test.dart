import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/screens/problem_screen.dart';
import 'package:stepi/screens/capture_learning_screen.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/learning_storage.dart';
import 'package:stepi/services/question_service.dart';

JsonMap problem(int id, {String concept = 'C1'}) => {
  'id': id,
  'tutor_ready': true,
  'problem_code': 'P$id',
  'question': '2와 3을 더하면?',
  'problem_type': 'SHORT_ANSWER',
  'usage': 'PRACTICE',
  'concept_codes': [concept],
  'skill_codes': ['S1'],
};
JsonMap accepted({bool? correct = true, int xp = 17}) => {
  'scenario': 'RECOMMENDED',
  'action': 'CHECK_ANSWER',
  'problem_id': 23,
  'status': 'GRADED',
  'message': '답안을 확인했어요.',
  'answer_correct': correct,
  'id': 81,
  'is_correct': correct,
  'rewards': {
    'xp': xp,
    'level_up': true,
    'new_badges': [
      {'code': 'BDG-085', 'name': '레벨 100 달성'},
    ],
    'completed_quests': [
      {'code': 'Q1', 'title': '오늘의 학습'},
    ],
  },
};

class FixedQuestions implements QuestionService {
  final List<PracticeQuestion> questions;
  FixedQuestions([List<PracticeQuestion>? questions])
    : questions =
          questions ??
          [PracticeQuestion.fromServerJson(problem(23), title: '다항식')];
  @override
  Future<List<PracticeQuestion>> fetchQuestions() async => questions;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  LearningRepository repo, {
  QuestionService? questions,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ProblemScreen(
                  repository: repo,
                  questionService: questions ?? FixedQuestions(),
                ),
              ),
            ),
            child: const Text('시작'),
          ),
        ),
      ),
    ),
  );
  await tapText(tester, '시작');
}

Future<void> enterAnswer(WidgetTester tester, String answer) async {
  await tapText(tester, '그냥 정답 입력하기');
  expect(find.textContaining('자동입력'), findsNothing);
  await tester.enterText(find.byType(TextField), answer);
  await tapText(tester, '답안 저장하기');
}

Future<dynamic> read(String path, Map<String, String> query) async => {
  'xp': 95000,
  'level': 500,
  'xp_to_next_level': 0,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'the final page of a 418-problem catalog can supply an exact problem',
    () async {
      final pages = <int>[];
      final repo = LearningRepository(
        read: (path, query) async {
          expect(path, '/api/v1/problems');
          final page = int.parse(query['page']!);
          pages.add(page);
          final end = min(page * 100, 418);
          return {
            'items': [
              for (var id = (page - 1) * 100 + 1; id <= end; id++) problem(id),
            ],
            'total_pages': 5,
          };
        },
      );
      final questions = await ServerQuestionService(
        repository: repo,
        problemCode: 'P418',
      ).fetchQuestions();
      expect(pages, [1, 2, 3, 4, 5]);
      expect(questions.single.problemId, 418);
    },
  );
  testWidgets('fraction answers reach server grading as text', (tester) async {
    final answers = <String>[];
    final repo = LearningRepository(
      read: read,
      write: (method, path, body) async {
        if (path.endsWith('/learning-sessions')) return {'id': 51};
        if (path.endsWith('/tutor/session')) {
          answers.add((body as JsonMap)['answer'] as String);
          return accepted(correct: null, xp: 0);
        }
        return {};
      },
    );
    await open(tester, repo);
    await enterAnswer(tester, '  3/2  ');
    await tapText(tester, '제출하기');
    expect(answers, ['3/2']);
    expect(find.text('채점 대기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('new practice excludes diagnostic and relearning items while exact retries preserve them', () async {
    final queries = <Map<String, String>>[];
    final repo = LearningRepository(
      read: (path, query) async {
        queries.add(Map.of(query));
        return {
          'items': [
            for (var id = 1; id <= 3; id++) problem(id),
            {...problem(4), 'usage': 'DIAGNOSTIC'},
            {...problem(5), 'usage': 'RELEARNING'},
          ],
          'total_pages': 1,
        };
      },
    );
    final practice = await ServerQuestionService(
      skillCode: 'S1',
      repository: repo,
    ).fetchQuestions();
    expect(practice.map((q) => q.problemId), [1, 2, 3]);
    expect(queries.last['usage'], 'PRACTICE');
    final relearning = await ServerQuestionService(
      skillCode: 'S1',
      usage: 'RELEARNING',
      repository: repo,
    ).fetchQuestions();
    expect(relearning.single.problemId, 5);
    expect(queries.last['usage'], 'RELEARNING');
    final retry = await ServerQuestionService(
      problemCode: 'P4',
      repository: repo,
    ).fetchQuestions();
    expect(retry.single.problemId, 4);
    expect(queries.last.containsKey('usage'), false);
  });
  test(
    'a 26-problem catalog becomes a five-question session with varied Skills',
    () async {
      final repo = LearningRepository(
        read: (path, query) async => path.endsWith('/concepts')
            ? {
                'items': [
                  {'code': 'C1', 'subject': '다항식'},
                ],
              }
            : {
                'items': [
                  for (var i = 1; i <= 26; i++)
                    {
                      ...problem(i),
                      'skill_codes': ['S${i % 6}'],
                    },
                ],
                'total_pages': 1,
              },
      );
      final first = await ServerQuestionService(
        repository: repo,
        random: Random(1),
      ).fetchQuestions();
      final second = await ServerQuestionService(
        repository: repo,
        random: Random(2),
      ).fetchQuestions();
      expect(first.length, 5);
      expect(first.map((q) => q.problemId).toSet().length, 5);
      expect(first.map((q) => q.skillCodes.single).toSet().length, 5);
      expect(
        first.map((q) => q.problemId).toList(),
        isNot(second.map((q) => q.problemId).toList()),
      );
      final short = await ServerQuestionService(
        repository: repo,
        questionLimit: 3,
        random: Random(1),
      ).fetchQuestions();
      expect(short.length, 3);
    },
  );
  test('one Skill still fills five questions without duplicates', () async {
    final repo = LearningRepository(
      read: (path, query) async => {
        'items': [for (var i = 1; i <= 12; i++) problem(i)],
        'total_pages': 1,
      },
    );
    final batch = await ServerQuestionService(
      skillCode: 'S1',
      repository: repo,
      random: Random(4),
    ).fetchQuestions();
    expect(batch.length, 5);
    expect(batch.map((q) => q.problemId).toSet().length, 5);
  });
  test('catalog uses server concept membership across pages without local question fallback', () async {
    final pages = <String>[];
    final repo = LearningRepository(
      read: (path, query) async {
        if (path.endsWith('/concepts')) {
          return {
            'items': [
              {'code': 'C1', 'subject': '다항식'},
            ],
          };
        }
        pages.add(query['page']!);
        return {
          'items': [
            problem(int.parse(query['page']!)),
            problem(99, concept: 'OTHER'),
          ],
          'total_pages': 2,
        };
      },
    );
    final questions = await ServerQuestionService(repository: repo)
        .fetchQuestions();
    expect(questions.map((q) => q.problemId), [1, 2]);
    expect(pages, ['1', '2']);
    expect(questions.first.correctAnswer, isEmpty);
    expect(() => questions.first.validate(), returnsNormally);
    await expectLater(
      ServerQuestionService(unit: '미등록 단원', repository: repo).fetchQuestions(),
      throwsFormatException,
    );
    final exact = await ServerQuestionService(
      problemCode: 'P2',
      repository: repo,
    ).fetchQuestions();
    expect(exact.map((q) => q.problemId), [2]);
    await expectLater(
      ServerQuestionService(
        problemCode: 'STP-2-014',
        repository: repo,
      ).fetchQuestions(),
      throwsFormatException,
    );
  });
  testWidgets(
    'original workspace uses server grading and rewards, never writes local XP',
    (tester) async {
      final writes = <JsonMap>[];
      final repo = LearningRepository(
        read: read,
        write: (method, path, body) async {
          writes.add({'method': method, 'path': path, 'body': body});
          if (path.endsWith('/learning-sessions')) return {'id': 51};
          if (path.endsWith('/tutor/session')) {
            return accepted(correct: false);
          }
          return {};
        },
      );
      await open(tester, repo);
      await enterAnswer(tester, '5');
      await tapText(tester, '제출하기');
      expect(find.text('오답'), findsOneWidget);
      expect(find.text('+ 17 XP'), findsOneWidget);
      expect(find.text('레벨 100 달성'), findsOneWidget);
      expect(find.text('Lv.500 · 최고 레벨'), findsOneWidget);
      expect((writes[1]['body'] as Map)['problem_id'], 23);
      expect((writes[1]['body'] as Map)['session_id'], 51);
      expect((writes[1]['body'] as Map)['answer'], '5');
      expect(await LearningStorage.loadSessions(), isEmpty);
      await tapText(tester, '원래 문제 다시 풀기');
      await tapText(tester, '제출하기');
      expect(
        writes.where((w) => w['path'] == '/api/v1/learning-sessions').length,
        1,
      );
      expect(
        writes.where((w) => w['path'] == '/api/v1/tutor/session').length,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed submit preserves answer and reuses session on retry', (
    tester,
  ) async {
    var starts = 0, submits = 0;
    final repo = LearningRepository(
      read: read,
      write: (method, path, body) async {
        if (path.endsWith('/learning-sessions')) {
          starts++;
          return {'id': 51};
        }
        if (path.endsWith('/tutor/session')) {
          submits++;
          if (submits == 1) {
            throw const ApiException(
              statusCode: 503,
              code: 'NOT_READY',
              message: 'try again',
            );
          }
          expect((body as Map)['answer'], '5');
          expect(body['session_id'], 51);
          return accepted();
        }
        return {};
      },
    );
    await open(tester, repo);
    await enterAnswer(tester, '5');
    await tapText(tester, '제출하기');
    expect(find.text('입력한 답: 5'), findsOneWidget);
    await tapText(tester, '제출하기');
    expect(starts, 1);
    expect(submits, 2);
    expect(find.text('정답'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'duplicate taps and failed finish do not repeat accepted rewards',
    (tester) async {
      var starts = 0, submits = 0, finishes = 0;
      final pending = Completer<JsonMap>();
      final repo = LearningRepository(
        read: read,
        write: (method, path, body) async {
          if (path.endsWith('/learning-sessions')) {
            starts++;
            return {'id': 51};
          }
          if (path.endsWith('/tutor/session')) {
            submits++;
            return pending.future;
          }
          if (path.endsWith('/finish')) {
            finishes++;
            if (finishes == 1) throw Exception('offline');
          }
          return {};
        },
      );
      await open(tester, repo);
      await enterAnswer(tester, '5');
      await tester.tap(find.text('제출하기'));
      await tester.tap(find.text('제출하기'));
      await tester.pump();
      expect(starts, 1);
      expect(submits, 1);
      pending.complete(accepted());
      await tester.pumpAndSettle();
      await tapText(tester, '학습 마치기');
      expect(find.textContaining('학습 종료를 저장하지 못했어요'), findsOneWidget);
      await tapText(tester, '결과 다시 보기');
      await tapText(tester, '학습 마치기');
      expect(submits, 1);
      expect(finishes, 2);
      expect(find.text('시작'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'nullable grading remains pending and never reports success or a retry award',
    (tester) async {
      final repo = LearningRepository(
        read: read,
        write: (method, path, body) async => path.endsWith('/learning-sessions')
            ? {'id': 51}
            : accepted(correct: null, xp: 0),
      );
      await open(tester, repo);
      await enterAnswer(tester, '5');
      await tapText(tester, '제출하기');
      expect(find.text('채점 대기'), findsOneWidget);
      expect(find.text('정답'), findsNothing);
      expect(find.text('오답'), findsNothing);
      expect(find.text('원래 문제 다시 풀기'), findsNothing);
      expect(find.text('+ 0 XP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'original photo button opens real capture flow and preserves the typed answer',
    (tester) async {
      var writes = 0;
      final repo = LearningRepository(
        read: read,
        write: (method, path, body) async {
          writes++;
          return {};
        },
      );
      await open(tester, repo);
      await enterAnswer(tester, '5');
      final camera = find.text('카메라로 공책 풀이 촬영하기 (AI 과정 분석)');
      await tester.ensureVisible(camera);
      await tester.tap(camera);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureLearningScreen), findsOneWidget);
      expect(find.text('앨범에서 사진 선택'), findsOneWidget);
      expect(find.textContaining('시연:'), findsNothing);
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('입력한 답: 5'), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('structured choice sends server value rather than display text', (
    tester,
  ) async {
    final q = PracticeQuestion.fromServerJson({
      ...problem(23),
      'problem_type': 'MULTIPLE_CHOICE',
      'choices': [
        {'label': '다섯', 'value': 'B'},
        {'label': '여섯', 'value': 'C'},
      ],
    }, title: '다항식');
    final repo = LearningRepository(
      read: read,
      write: (method, path, body) async {
        if (path.endsWith('/learning-sessions')) return {'id': 51};
        if (path.endsWith('/tutor/session')) {
          expect((body as Map)['answer'], 'B');
        }
        return accepted();
      },
    );
    await open(tester, repo, questions: FixedQuestions([q]));
    await tapText(tester, '1) 다섯');
    await tapText(tester, '제출하기');
    expect(find.text('정답'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
