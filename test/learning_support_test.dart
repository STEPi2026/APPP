import 'dart:async';

import 'package:stepi/services/api.dart';
import 'package:stepi/services/tutor_help_service.dart';
import 'package:stepi/services/learning_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepi/screens/learning_support_screen.dart';
import 'package:stepi/screens/badge_collection.dart';
import 'package:stepi/screens/problem_screen.dart';

void main() {
  test(
    'XP display requests achievements with server progress fields',
    () async {
      String? requestedPath;
      final progress = await LearningStorage.getExperienceProgress(
        fetch: (path) async {
          requestedPath = path;
          return {'xp': 6420, 'level': 100, 'xp_to_next_level': 80};
        },
      );
      expect(requestedPath, '/api/v1/me/achievements');
      expect(progress.level, 100);
      expect(progress.totalXp, 6420);
      expect(progress.progress, 0);
    },
  );

  testWidgets('badge collection starts with six and can expand and collapse', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BadgeCollection(
              catalogLoader: () async => List.generate(
                8,
                (i) => {
                  'code': 'BDG-${(i + 1).toString().padLeft(3, '0')}',
                  'name': '배지 ${i + 1}',
                  'description': '배지 설명 ${i + 1}',
                },
              ),
              earnedLoader: () async => [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('배지 6'), findsOneWidget);
    expect(find.text('배지 7'), findsNothing);
    await tester.ensureVisible(find.text('더보기 (전체 8개)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('더보기 (전체 8개)'));
    await tester.pumpAndSettle();
    expect(find.text('배지 8'), findsOneWidget);
    await tester.ensureVisible(find.text('배지 8'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('배지 8'));
    await tester.pumpAndSettle();
    expect(find.text('배지 설명 8'), findsOneWidget);
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('접기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('접기'));
    await tester.pumpAndSettle();
    expect(find.text('배지 7'), findsNothing);
    expect(find.text('더보기 (전체 8개)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server stages keep prerequisite context and record reactions', (
    tester,
  ) async {
    final requests = <Map<String, String?>>[];
    final reactions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LearningSupportScreen(
          problemTitle: '연습 문제',
          request: ({String? stage, String? skillCode}) async {
            requests.add({'stage': stage, 'skill': skillCode});
            if (stage == 'hint') {
              return const TutorHelpResult(
                actionId: 45,
                actionType: 'SOCRATIC_HINT',
                hintLevel: 1,
                message: '조건부터 살펴볼까요?',
              );
            }
            return TutorHelpResult(
              actionId: 45,
              actionType: 'CONCEPT_REVIEW',
              message: '같이 볼까요?',
              explanation: stage == null || stage == 'explanation'
                  ? '개념 본문'
                  : null,
              example: stage == 'example' ? '예제 본문' : null,
              checkQuestion: stage == 'check' ? '확인 질문' : null,
              nextStage: stage == null || stage == 'explanation'
                  ? 'example'
                  : stage == 'example'
                  ? 'check'
                  : null,
              nextStep: 'PREREQUISITE_REVIEW',
              nextSkillCode: 'SKL-1-003',
            );
          },
          reaction: (id, value) async {
            expect(id, 45);
            reactions.add(value);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests.first, {'stage': 'hint', 'skill': null});
    Future<void> tap(String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    await tap('개념부터 보기');
    expect(requests.last, {'stage': 'explanation', 'skill': null});
    expect(find.text('개념 본문'), findsOneWidget);
    await tap('선수개념 복습하기');
    expect(requests.last, {'stage': 'explanation', 'skill': 'SKL-1-003'});
    await tap('다음 단계');
    expect(requests.last, {'stage': 'example', 'skill': 'SKL-1-003'});
    expect(find.text('예제 본문'), findsOneWidget);
    await tap('다음 단계');
    expect(find.text('확인 질문'), findsOneWidget);
    expect(find.text('다음 단계'), findsNothing);
    await tap('도움됐어요');
    expect(reactions, ['HELPFUL']);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'server hint levels lead into explanation without a client counter',
    (tester) async {
      final bodies = <Map<String, dynamic>>[];
      var hints = 0;
      final service = TutorHelpService(
        problemId: 123,
        post: (path, body) async {
          expect(path, '/api/v1/tutor/help');
          bodies.add(Map.of(body));
          if (body['stage'] == 'hint' && ++hints <= 3) {
            return {
              'tutor_action_id': hints,
              'action_type': 'SOCRATIC_HINT',
              'content': {'message': '서버 힌트 $hints', 'hint_level': hints},
              // Hint continuation must work even without next_stage.
              'next_stage': null,
            };
          }
          return {
            'tutor_action_id': 4,
            'action_type': 'CONCEPT_REVIEW',
            'content': {
              'message': '개념부터 같이 볼까요?',
              if (body['stage'] == 'explanation') 'explanation': '서버 개념 설명',
            },
            'next_stage': body['stage'] == 'hint' ? 'explanation' : 'example',
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LearningSupportScreen(
            problemTitle: '단계별 도움',
            request: service.request,
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      for (var level = 1; level <= 3; level++) {
        expect(find.text('힌트 $level단계'), findsOneWidget);
        expect(find.text('서버 힌트 $level'), findsOneWidget);
        expect(find.text('이 개념의 도움 단계를 모두 확인했어요.'), findsNothing);
        await tap(level == 3 ? '다음 도움 보기' : '다음 힌트 보기');
      }
      expect(find.text('개념 설명 보기'), findsOneWidget);
      expect(find.text('서버 개념 설명'), findsNothing);
      await tap('개념 설명 보기');
      expect(find.text('서버 개념 설명'), findsOneWidget);
      expect(bodies, [
        for (var i = 0; i < 4; i++) {'problem_id': 123, 'stage': 'hint'},
        {'problem_id': 123, 'stage': 'explanation'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'existing server hint level is shown and explanation does not advance hints',
    (tester) async {
      final stages = <String?>[];
      final reactions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LearningSupportScreen(
            problemTitle: '이어서 도움받기',
            request: ({String? stage, String? skillCode}) async {
              stages.add(stage);
              return TutorHelpResult(
                actionId: 9,
                actionType: stage == 'hint'
                    ? 'SOCRATIC_HINT'
                    : 'CONCEPT_REVIEW',
                hintLevel: stage == 'hint' ? 2 : null,
                message: '서버 도움',
                explanation: stage == 'explanation' ? '개념을 다시 볼까요?' : null,
              );
            },
            reaction: (id, value) async => reactions.add(value),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('힌트 2단계'), findsOneWidget);
      await tester.ensureVisible(find.text('개념으로 설명해 주세요'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개념으로 설명해 주세요'));
      await tester.pumpAndSettle();
      expect(reactions, ['EXPLAIN_AGAIN']);
      expect(stages, ['hint', 'explanation']);
      expect(find.text('개념을 다시 볼까요?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a failed next hint retries hint once and ignores double taps', (
    tester,
  ) async {
    final stages = <String?>[];
    final nextHint = Completer<TutorHelpResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: LearningSupportScreen(
          problemTitle: '힌트 재시도',
          request: ({String? stage, String? skillCode}) {
            stages.add(stage);
            if (stages.length == 2) return nextHint.future;
            return Future.value(
              TutorHelpResult(
                actionId: stages.length,
                actionType: 'SOCRATIC_HINT',
                hintLevel: stages.length == 1 ? 1 : 2,
                message: '서버 힌트',
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다음 힌트 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다음 힌트 보기'));
    await tester.tap(find.text('다음 힌트 보기'));
    expect(stages, ['hint', 'hint']);
    nextHint.completeError(
      const ApiException(
        statusCode: 503,
        code: 'AI_CATALOG_NOT_READY',
        message: 'pending',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('원래 문제 다시 풀기'), findsOneWidget);
    await tester.ensureVisible(find.text('다시 시도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(stages, ['hint', 'hint', 'hint']);
    expect(find.text('힌트 2단계'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('503 has retry and return without fabricated content', (
    tester,
  ) async {
    int requests = 0;
    final pending = Completer<TutorHelpResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: LearningSupportScreen(
          problemTitle: '문제',
          request: ({String? stage, String? skillCode}) {
            requests++;
            return requests == 1
                ? pending.future
                : Future.value(
                    const TutorHelpResult(
                      actionId: 7,
                      actionType: 'CONCEPT_REVIEW',
                      message: '서버 메시지',
                      explanation: '서버 설명',
                    ),
                  );
          },
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(
      const ApiException(
        statusCode: 503,
        code: 'AI_CATALOG_NOT_READY',
        message: 'not ready',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('지금은 도움을 불러올 수 없어요'), findsOneWidget);
    expect(find.text('원래 문제 다시 풀기'), findsOneWidget);
    await tester.ensureVisible(find.text('다시 시도'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('서버 설명'), findsOneWidget);
    expect(requests, 2);
  });
  testWidgets(
    'servers rejecting the hint stage can still provide concept help',
    (tester) async {
      final stages = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LearningSupportScreen(
            problemTitle: '기존 개념 도움',
            request: ({String? stage, String? skillCode}) async {
              stages.add(stage);
              if (stage == 'hint') {
                throw const ApiException(
                  statusCode: 422,
                  code: 'VALIDATION_ERROR',
                  message: 'unsupported stage',
                );
              }
              return const TutorHelpResult(
                actionId: 1,
                actionType: 'CONCEPT_REVIEW',
                message: '서버 메시지',
                explanation: '기존 개념 설명',
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('다시 시도'), findsNothing);
      expect(find.text('원래 문제 다시 풀기'), findsOneWidget);
      await tester.ensureVisible(find.text('개념 설명 보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('개념 설명 보기'));
      await tester.pumpAndSettle();
      expect(stages, ['hint', 'explanation']);
      expect(find.text('기존 개념 설명'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('exact code resolution and help request use no attempt or XP', () async {
    int reads = 0;
    final calls = <Map<String, dynamic>>[];
    final service = TutorHelpService(
      problemCode: 'PRB-1-008',
      get: (path, query) async {
        reads++;
        return {
          'items': [
            {'id': 123, 'problem_code': 'PRB-1-008'},
          ],
          'total_pages': 1,
        };
      },
      post: (path, body) async {
        calls.add({'path': path, ...body});
        return {
          'tutor_action_id': 45,
          'action_type': 'CONCEPT_REVIEW',
          'content': {'message': '설명', 'example': ''},
        };
      },
    );
    expect((await service.request()).example, isNull);
    expect(calls.first, {'path': '/api/v1/tutor/help', 'problem_id': 123});
    await service.request(stage: 'example', skillCode: 'SKL-1-003');
    expect(reads, 1);
    expect(calls.last['stage'], 'example');
    expect(calls.last['skill_code'], 'SKL-1-003');
    await service.react(45, 'UNDERSTOOD');
    expect(calls.last, {
      'path': '/api/v1/tutor/actions/45/responses',
      'reaction': 'UNDERSTOOD',
    });
  });
  test('unknown code never sends guessed problem ID', () async {
    int posts = 0;
    final service = TutorHelpService(
      problemCode: 'missing',
      get: (p, q) async => {'items': [], 'total_pages': 0},
      post: (p, b) async {
        posts++;
        return {};
      },
    );
    await expectLater(service.request(), throwsA(isA<ApiException>()));
    expect(posts, 0);
  });
  test('server level controls all 25-level boundaries and max level', () {
    for (int level = 1; level < 500; level++) {
      final size = 50 + 10 * ((level - 1) ~/ 25);
      final state = ExperienceProgress.fromJson({
        'xp': 90000,
        'level': level,
        'xp_to_next_level': size,
      });
      expect(state.level, level);
      expect(state.progress, 0);
      expect(state.currentLevelXp, 0);
      final partial = ExperienceProgress.fromJson({
        'xp': 90000,
        'level': level,
        'xp_to_next_level': size - 1,
      });
      expect(partial.currentLevelXp, 1);
    }
    final max = ExperienceProgress.fromJson({
      'xp': 100000,
      'level': 500,
      'xp_to_next_level': 0,
    });
    expect(max.progress, 1);
    expect(max.totalXp, 100000);
    expect(max.remainingXp, 0);
    expect(
      () => ExperienceProgress.fromJson({'xp': 0, 'level': 1}),
      throwsFormatException,
    );
  });
  testWidgets(
    'database badge name and description are used even if ownership fails',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BadgeCollection(
              catalogLoader: () async => [
                {
                  'code': 'BDG-001',
                  'name': '첫 걸음',
                  'description': '첫 학습을 완료했어요.',
                },
              ],
              earnedLoader: () async => throw Exception('offline'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('획득 상태를 확인하지 못했어요'), findsOneWidget);
      await tester.tap(find.text('첫 걸음'));
      await tester.pumpAndSettle();
      expect(find.text('첫 학습을 완료했어요.'), findsOneWidget);
      expect(find.text('획득 상태를 확인하지 못했어요.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('problem answer survives help round trip at mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProblemScreen(
          reviewQuestion: PracticeQuestion(
            title: '숫자 문제',
            question: '2 더하기 3은?',
            questionType: PracticeQuestion.shortAnswer,
            answerText: '5',
            gradingMode: 'NUMERIC',
            explanation: '덧셈',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final answer = find.text('그냥 정답 입력하기');
    await tester.ensureVisible(answer);
    await tester.tap(answer);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '4');
    await tester.tap(find.text('답안 저장하기'));
    await tester.pumpAndSettle();
    final help = find.text('모르겠어요');
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('원래 문제 다시 풀기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('원래 문제 다시 풀기'));
    await tester.pumpAndSettle();
    expect(find.text('입력한 답: 4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
