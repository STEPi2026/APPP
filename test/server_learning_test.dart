import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/screens/server_learning.dart';
import 'package:stepi/screens/server_pathways.dart';

void main() {
  test('catalog selectors load every server page', () async {
    final reads = <String>[];
    final repo = LearningRepository(
      read: (path, query) async {
        reads.add(query['page']!);
        return {
          'items': [
            {'code': 'S${query['page']}'},
          ],
          'total_pages': 2,
        };
      },
    );
    expect((await repo.all('/api/v1/skills')).length, 2);
    expect(reads, ['1', '2']);
  });
  test(
    'protected image request includes ngrok header and preserves binary bytes',
    () async {
      await http.runWithClient(
        () async {
          expect(await Api.getCapturedImage(8), [137, 80, 78, 71]);
        },
        () => MockClient((request) async {
          expect(request.url.path, '/api/v1/captured-problems/8/image');
          expect(request.headers['ngrok-skip-browser-warning'], 'true');
          return http.Response.bytes(
            [137, 80, 78, 71],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
    },
  );
  testWidgets(
    'content opens from click and records server completion rewards',
    (tester) async {
      final actions = <String>[];
      final writes = <Map<String, dynamic>>[];
      final repo = LearningRepository(
        read: (p, q) async => {
          'id': 2,
          'title': '학습 자료',
          'url': 'https://example.com/lesson',
        },
        write: (method, path, body) async {
          writes.add({'path': path, 'body': body});
          if (path == '/api/v1/content-learning-sessions') {
            actions.add('start');
            return {'id': 6};
          }
          return {
            'id': 6,
            'status': 'COMPLETED',
            'completed_at': '2026-11-10T01:00:00Z',
            'rewards': {'xp': 5, 'new_badges': []},
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ServerContentScreen(
            contentId: 2,
            repository: repo,
            launcher: (uri) async {
              actions.add('open');
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('학습 자료 열기'));
      await tester.pumpAndSettle();
      expect(actions, ['open', 'start']);
      await tester.tap(find.text('자료 학습 완료 기록'));
      await tester.pumpAndSettle();
      expect((writes.last['body'] as Map)['completed'], true);
      expect(writes.last['path'], '/api/v1/content-learning-sessions/6');
      expect(find.text('획득 XP: 5'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('학습 완료'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  test('normal problem does not require or expose a local answer', () {
    final problem = ServerProblem.fromJson({
      'id': 12,
      'problem_code': 'P12',
      'question': '문제',
      'problem_type': 'MULTIPLE_CHOICE',
    });
    expect(problem.id, 12);
    expect(problem.choices, isEmpty);
  });
  test('session submission and completion follow backend contract', () async {
    final calls = <Map<String, dynamic>>[];
    final repo = LearningRepository(
      write: (method, path, body) async {
        calls.add({'method': method, 'path': path, 'body': body});
        if (path == '/api/v1/learning-sessions') return {'id': 99};
        return {
          'id': 1,
          'is_correct': true,
          'rewards': {'xp': 10, 'level_up': true, 'new_badges': []},
        };
      },
    );
    final session = await repo.startSession();
    final result = await repo.submit(
      sessionId: session,
      problemId: 12,
      answer: '  7  ',
      seconds: 18,
      hintCount: 2,
    );
    expect(calls[1]['body'], {
      'session_id': 99,
      'problem_id': 12,
      'student_answer': '7',
      'solve_time_seconds': 18,
      'hint_count': 2,
    });
    expect(result['is_correct'], true);
    await repo.finishSession(99);
    expect(calls.last['method'], 'PATCH');
    expect(calls.last['path'], '/api/v1/learning-sessions/99/finish');
  });
  test('empty answers never reach backend and failures propagate', () async {
    int writes = 0;
    final repo = LearningRepository(
      write: (method, path, body) async {
        writes++;
        throw const ApiException(
          statusCode: 503,
          code: 'AI_NOT_CONFIGURED',
          message: 'offline',
        );
      },
    );
    expect(
      () => repo.submit(sessionId: 1, problemId: 1, answer: ' ', seconds: 0),
      throwsFormatException,
    );
    expect(writes, 0);
    await expectLater(repo.startSession(), throwsA(isA<ApiException>()));
    expect(
      learningError(
        const ApiException(
          statusCode: 503,
          code: 'AI_NOT_CONFIGURED',
          message: 'offline',
        ),
      ),
      contains('아직 준비되지'),
    );
  });
  testWidgets(
    'submission is guarded, displays server rewards and finishes session',
    (tester) async {
      final submitted = Completer<JsonMap>();
      int submissions = 0, starts = 0, finishes = 0;
      final repo = LearningRepository(
        read: (path, query) async => {
          'id': 12,
          'problem_code': 'P12',
          'question': '서버 문제',
          'problem_type': 'SHORT_ANSWER',
        },
        write: (method, path, body) async {
          if (path == '/api/v1/learning-sessions') {
            starts++;
            return {'id': 99};
          }
          if (path.endsWith('/finish')) {
            finishes++;
            return {'id': 99};
          }
          submissions++;
          return submitted.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ServerProblemScreen(problemId: 12, repository: repo),
                  ),
                ),
                child: const Text('학습 열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('학습 열기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '서버에서 판단할 답');
      await tester.ensureVisible(find.text('제출하기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('제출하기'));
      await tester.pump();
      await tester.pump();
      expect(submissions, 1);
      expect(starts, 1);
      expect(find.text('제출 중…'), findsOneWidget);
      submitted.complete({
        'id': 7,
        'is_correct': true,
        'rewards': {
          'xp': 17,
          'level_up': true,
          'new_badges': [
            {'code': 'BDG-085', 'name': '레벨 100 달성'},
          ],
          'completed_quests': [],
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('획득 XP: 17'), findsOneWidget);
      expect(find.text('레벨이 올랐어요!'), findsOneWidget);
      await tester.tap(find.text('확인'));
      await tester.pumpAndSettle();
      expect(find.text('정답이에요!'), findsOneWidget);
      await tester.ensureVisible(find.text('학습 마치기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('학습 마치기'));
      await tester.pumpAndSettle();
      expect(finishes, 1);
      expect(find.text('학습 열기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed submission keeps answer and reuses existing session', (
    tester,
  ) async {
    int attempts = 0, starts = 0;
    final repo = LearningRepository(
      read: (path, query) async => {
        'id': 4,
        'problem_code': 'P4',
        'question': '문제',
        'problem_type': 'SHORT_ANSWER',
      },
      write: (method, path, body) async {
        if (path == '/api/v1/learning-sessions') {
          starts++;
          return {'id': 5};
        }
        attempts++;
        if (attempts == 1) {
          throw const ApiException(
            statusCode: 502,
            code: 'TEMPORARY_ERROR',
            message: 'temporary',
          );
        }
        return {
          'id': 9,
          'is_correct': false,
          'rewards': {'xp': 0, 'new_badges': []},
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: ServerProblemScreen(problemId: 4, repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '보존할 답');
    await tester.ensureVisible(find.text('제출하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제출하기'));
    await tester.pumpAndSettle();
    expect(
      (tester.widget(find.byType(TextField)) as TextField).controller!.text,
      '보존할 답',
    );
    await tester.ensureVisible(find.text('제출하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제출하기'));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(attempts, 2);
    expect(find.text('획득 XP: 0'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('다시 풀어볼까요?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
