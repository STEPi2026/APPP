import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/screens/analysis_support_screen.dart';
import 'package:stepi/screens/captured_history_screen.dart';
import 'package:stepi/screens/quest_screen.dart';
import 'package:stepi/screens/xp_history_screen.dart';
import 'package:stepi/screens/shop_tab.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/student_learning_records.dart';

JsonMap feedback({int action = 8, JsonMap? variant}) => {
  'tutor_action_id': action,
  'action_type': 'HINT',
  'content': {
    'message': '대입한 값을 다시 살펴볼까요?',
    'explanation': '같은 항을 모아서 계산해요.',
    'check_question': '2 + 3은?',
  },
  'next_step': null,
  'next_stage': null,
  'variant_problem': variant,
};
LearningRepository repository({ApiRead? read, ApiWrite? write}) =>
    LearningRepository(
      read: read ?? (path, query) async => throw StateError(path),
      write:
          write ??
          (method, path, body) async =>
              throw StateError('Unexpected mutation $path'),
    );
Widget app(Widget screen) => MaterialApp(home: Scaffold(body: screen));
Future<void> tap(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'photo history matches the actual attempt ID rather than session order',
    () async {
      final repo = repository(
        read: (path, q) async => switch (path) {
          '/api/v1/me/learning-history' => {
            'items': [
              {
                'id': 17,
                'session_id': 9,
                'problem_id': null,
                'is_correct': null,
                'attempted_at': '2026-11-12T01:00:00Z',
              },
              {
                'id': 18,
                'session_id': 9,
                'problem_id': null,
                'is_correct': null,
                'attempted_at': '2026-11-12T02:00:00Z',
              },
            ],
          },
          '/api/v1/captured-problems' => {
            'items': [
              {
                'id': 51,
                'attempt_id': 18,
                'session_id': 9,
                'problem_text': '두 번째 사진',
              },
              {
                'id': 52,
                'attempt_id': 17,
                'session_id': 9,
                'problem_text': '첫 번째 사진',
              },
            ],
          },
          _ => {'items': []},
        },
      );
      final rows = await StudentLearningRecords(repo).history();
      final answers = rows.single['answers'] as List;
      expect(answers.first['capturedProblemId'], 52);
      expect(answers.last['capturedProblemId'], 51);
      expect(answers.first['question'], '첫 번째 사진');
    },
  );
  testWidgets(
    'saved photo list preserves unassessed state and original card ink',
    (tester) async {
      final repo = repository(
        read: (path, q) async => {
          'items': [
            {
              'id': 51,
              'problem_text': '사진으로 푼 문제',
              'created_at': '2026-11-12T01:00:00Z',
              'latest_analysis': null,
            },
          ],
        },
      );
      await tester.pumpWidget(app(CapturedHistoryScreen(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.textContaining('분석 전'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'quests use server targets and completion without a claim or local gold',
    (tester) async {
      await tester.pumpWidget(
        app(
          QuestScreen(
            repository: repository(
              read: (path, query) async => {
                'date': '2026-11-12',
                'items': [
                  {
                    'code': 'Q',
                    'title': '문제 3개 풀기',
                    'target': 3,
                    'progress': 2,
                    'reward_xp': 15,
                    'completed': false,
                  },
                ],
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('15 XP'), findsOneWidget);
      expect(find.text('진행 중'), findsOneWidget);
      expect(find.textContaining('G 받기'), findsNothing);
      expect(find.text('수령 완료'), findsNothing);
    },
  );
  testWidgets(
    'XP pagination keeps previous events on failure and does not duplicate rows',
    (tester) async {
      bool fail = true;
      final repo = repository(
        read: (path, q) async {
          if (q['page'] == '2' && fail) throw StateError('offline');
          return {
            'items': [
              {
                'id': q['page'] == '1' ? 1 : 2,
                'event_type': 'DAILY_QUEST',
                'xp': 15,
                'created_at': '2026-11-11T15:01:00Z',
              },
            ],
            'page': int.parse(q['page']!),
            'total_pages': 2,
          };
        },
      );
      await tester.pumpWidget(app(XpHistoryScreen(repository: repo)));
      await tester.pumpAndSettle();
      await tap(tester, '더 보기');
      expect(find.text('+15 XP'), findsOneWidget);
      expect(find.text('다시 불러오기'), findsOneWidget);
      fail = false;
      await tap(tester, '다시 불러오기');
      expect(find.text('+15 XP'), findsNWidgets(2));
      expect(find.text('2026.11.12 00:01'), findsNWidgets(2));
      expect(find.text('더 보기'), findsNothing);
    },
  );
  testWidgets(
    'analysis help passes actual ID, starts at zero and preserves failed hint count',
    (tester) async {
      final bodies = <JsonMap>[];
      bool fail = true;
      final repo = repository(
        write: (method, path, body) async {
          final data = Map<String, dynamic>.from(body as Map);
          bodies.add(data);
          if (data['hint_count'] == 1 && fail) {
            throw const ApiException(
              statusCode: 503,
              code: 'AI_NOT_CONFIGURED',
              message: '',
            );
          }
          return feedback();
        },
      );
      await tester.pumpWidget(
        app(AnalysisSupportScreen(analysisId: 37, repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(bodies.single, {'analysis_id': 37, 'hint_count': 0});
      expect(find.textContaining('채점하지 않아요'), findsOneWidget);
      await tap(tester, '다음 힌트 확인');
      expect(find.text('대입한 값을 다시 살펴볼까요?'), findsOneWidget);
      fail = false;
      await tap(tester, '다시 불러오기');
      expect(bodies.last, {'analysis_id': 37, 'hint_count': 1});
    },
  );
  testWidgets('pending AI contract has guidance and no repeated retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        AnalysisSupportScreen(
          analysisId: 37,
          repository: repository(
            write: (method, path, body) async => throw const ApiException(
              statusCode: 409,
              code: 'AI_CONTRACT_PENDING',
              message: '',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('연결하는 작업이 준비 중'), findsOneWidget);
    expect(find.text('다시 불러오기'), findsNothing);
    expect(find.text('원래 풀이로 돌아가기'), findsOneWidget);
  });
  testWidgets(
    'feedback reaction is guarded and cannot create a new hint until saved',
    (tester) async {
      final response = Completer<JsonMap>();
      int reactions = 0;
      final repo = repository(
        write: (method, path, body) async {
          if (path.endsWith('/responses')) {
            reactions++;
            return response.future;
          }
          return feedback();
        },
      );
      await tester.pumpWidget(
        app(AnalysisSupportScreen(analysisId: 37, repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('도움됐어요'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        tester.element(find.text('도움됐어요')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('도움됐어요'));
      await tester.pump();
      expect(reactions, 1);
      await tester.tap(find.text('도움됐어요'));
      await tester.pump();
      expect(reactions, 1);
      response.complete({'id': 8});
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'variant grading remains server controlled when correctness is null',
    (tester) async {
      int submissions = 0;
      final repo = repository(
        write: (method, path, body) async {
          submissions++;
          expect(path, '/api/v1/tutor/variant-problems/73/attempts');
          expect(body, {'answer': '5'});
          return {
            'correct': null,
            'feedback': {
              'content': {'message': '확인이 필요해요.'},
            },
          };
        },
      );
      await tester.pumpWidget(
        app(
          TutorVariantScreen(
            problem: {'id': 73, 'prompt': '2 + 3은?'},
            repository: repo,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '5');
      await tap(tester, '제출하기');
      expect(find.text('판정 보류'), findsOneWidget);
      await tester.tap(find.text('제출하기'));
      await tester.pump();
      expect(submissions, 1);
    },
  );
  testWidgets(
    'saved photo opens with GET only and no session or reward mutation',
    (tester) async {
      final paths = <String>[];
      final repo = repository(
        read: (path, q) async {
          paths.add(path);
          if (path.endsWith('/captured-problems/12')) {
            return {
              'id': 12,
              'session_id': 99,
              'problem_text': '문제 본문',
              'solution_text': '내 풀이 본문',
              'latest_analysis': {'id': 37},
            };
          }
          return {
            'id': 37,
            'captured_problem_id': 12,
            'status': 'REVIEW_REQUIRED',
            'is_correct': null,
            'first_error_step': 1,
            'solution_steps': ['2x = 5'],
            'errors': [],
          };
        },
      );
      await tester.pumpWidget(
        app(
          SavedCaptureScreen(
            captureId: 12,
            repository: repo,
            imageLoader: (id) async => base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4n8AAAAASUVORK5CYII=',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        paths,
        containsAll(['/api/v1/captured-problems/12', '/api/v1/ai-analyses/37']),
      );
      expect(find.text('판정 보류'), findsOneWidget);
      expect(find.textContaining('최초 오류'), findsNothing);
      expect(find.text('AI 튜터에게 힌트 받기'), findsNothing);
    },
  );
  testWidgets(
    'my page calendar uses KST records, authoritative streak and real month',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = repository(
        read: (path, q) async => switch (path) {
          '/api/v1/me/gamification' => {
            'xp': 25,
            'level': 1,
            'current_streak': 9,
          },
          '/api/v1/me/learning-history' => {
            'items': [
              {'session_id': 1, 'attempted_at': '2026-11-11T15:01:00Z'},
            ],
          },
          '/api/v1/badges' || '/api/v1/me/badges' => {'items': []},
          _ => throw StateError(path),
        },
      );
      await tester.pumpWidget(
        app(
          ShopTab(
            repository: repo,
            now: DateTime.parse('2026-11-12T00:00:00Z'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('9'), findsWidgets);
      expect(find.text('나의 학습 기록 (2026.11)'), findsOneWidget);
      expect(find.byTooltip('12일 · 제출 1회'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('12일 · 제출 1회'));
      await tester.tap(find.byTooltip('12일 · 제출 1회'));
      await tester.pumpAndSettle();
      expect(find.text('2026.11.12 학습 기록'), findsOneWidget);
      expect(find.text('학습 기록 1개'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ShopTab), findsOneWidget);
      // Rebuild at the top to also preserve the shop entry check.
      await tester.pumpWidget(
        app(
          ShopTab(
            key: UniqueKey(),
            repository: repo,
            now: DateTime.parse('2026-11-12T00:00:00Z'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, '포인트 상점');
      expect(find.text('보상 상점을 준비하고 있어요'), findsOneWidget);
      expect(find.text('교환'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('profile save uses server PATCH and never calculates levels', (
    tester,
  ) async {
    JsonMap? saved;
    final repo = repository(
      write: (method, path, body) async {
        expect(method, 'PATCH');
        expect(path, '/api/v1/me/student-profile');
        saved = Map<String, dynamic>.from(body as Map);
        return {'grade_level': '고1'};
      },
    );
    await tester.pumpWidget(
      app(
        StudentProfileScreen(
          repository: repo,
          initial: {'grade_level': '고1', 'learning_goal': '개념 복습'},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '인수분해 익히기');
    await tap(tester, '저장하기');
    expect(saved, {'grade_level': '고1', 'learning_goal': '인수분해 익히기'});
  });
}
