import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/screens/home_tab.dart';
import 'package:stepi/screens/learning_history_screen.dart';
import 'package:stepi/screens/learning_history_detail_screen.dart';
import 'package:stepi/screens/wrong_answer_screen.dart';
import 'package:stepi/screens/server_pathways.dart';
import 'package:stepi/screens/problem_screen.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/student_learning_records.dart';
import 'package:stepi/services/learning_storage.dart';

JsonMap wrong({bool resolved = false}) => {
  'problem_id': 23,
  'problem_code': 'PRB-023',
  'question': '2 + 3은?',
  'answer': '5',
  'explanation': '덧셈이에요.',
  'last_wrong_answer': '4',
  'wrong_count': 2,
  'resolved': resolved,
  'last_attempted_at': '2026-11-11T01:00:00Z',
};
JsonMap problem() => {
  'id': 23,
  'tutor_ready': true,
  'problem_code': 'PRB-023',
  'question': '2 + 3은?',
  'problem_type': 'SHORT_ANSWER',
  'concept_codes': ['C1'],
  'skill_codes': ['S1'],
};
JsonMap step({bool ready = true, bool completed = false}) => {
  'id': 7,
  'order': 1,
  'skill_code': 'S1',
  'skill_name': '분배법칙',
  'ready': ready,
  'completed': completed,
  'reason': '서버에서 추천한 학습',
  'content_ids': [],
};
JsonMap plan() => {
  'id': 2,
  'version': 1,
  'status': 'ACTIVE',
  'completed': false,
  'next_skill_code': 'S1',
  'steps': [step()],
  'progress': {'completed_steps': 0, 'total_steps': 1, 'rate': 0.0},
};
List<JsonMap> attempts() => [
  {
    'id': 1,
    'session_id': 5,
    'problem_id': 23,
    'problem_code': 'PRB-023',
    'is_correct': false,
    'student_answer': '4',
    'attempted_at': '2026-11-10T14:59:00Z',
  },
  {
    'id': 2,
    'session_id': 5,
    'problem_id': 23,
    'problem_code': 'PRB-023',
    'is_correct': true,
    'student_answer': '5',
    'attempted_at': '2026-11-10T15:01:00Z',
  },
  {
    'id': 3,
    'session_id': 6,
    'problem_id': null,
    'is_correct': null,
    'attempted_at': '2026-11-10T15:03:00Z',
  },
];
Future<dynamic> read(String path, Map<String, String> query) async {
  return switch (path) {
    '/api/v1/me/learning-history' => {'items': attempts()},
    '/api/v1/me/wrong-answers' => {
      'items': [wrong(resolved: true)],
    },
    '/api/v1/me/review-queue' => {'items': []},
    '/api/v1/problems' => {
      'items': [problem()],
    },
    '/api/v1/problems/23' => problem(),
    '/api/v1/concepts' => {
      'items': [
        {'code': 'C1', 'subject': '다항식'},
      ],
    },
    '/api/v1/me/learning-summary' => {
      'total_attempts': 45,
      'correct_attempts': 34,
    },
    '/api/v1/me/gamification' => {
      'xp': 888,
      'current_streak': 17,
      'last_study_date': '2026-11-11',
    },
    '/api/v1/me/achievements' => {
      'xp': 888,
      'level': 10,
      'xp_to_next_level': 12,
    },
    '/api/v1/me/roadmap' => plan(),
    '/api/v1/me/roadmap/steps/7' => step(),
    _ => throw StateError(path),
  };
}

Future<void> tapText(WidgetTester tester, String value) async {
  final finder = find.text(value);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
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
  test('history groups real sessions, preserves pending and historical wrong outcomes', () async {
    final queries = <Map<String, String>>[];
    final repo = LearningRepository(
      read: (p, q) async {
        if (p.endsWith('/wrong-answers')) queries.add(q);
        return read(p, q);
      },
    );
    final records = await StudentLearningRecords(repo).history();
    expect(records.length, 2);
    expect(records.first['topic'], '사진 풀이');
    expect(records.first['answers'].single['isCorrect'], isNull);
    final original = (records.last['answers'] as List).first;
    expect(original['isCorrect'], false);
    expect(original['reviewCompleted'], true);
    expect(records.last['totalCount'], 2);
    expect(records.last['correctCount'], 1);
    expect(queries.single['include_resolved'], 'true');
  });
  test(
    'metadata outages do not convert unknown review state into completion',
    () async {
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/learning-history')) return {'items': attempts()};
          throw Exception('offline');
        },
      );
      final records = await StudentLearningRecords(repo).history();
      expect(
        (records.last['answers'] as List).first['reviewCompleted'],
        isNull,
      );
    },
  );
  test(
    'overview takes totals and streak from server and counts KST sessions once',
    () async {
      final overview = await StudentLearningRecords(
        LearningRepository(read: read),
      ).overview(now: DateTime.parse('2026-11-10T16:00:00Z'));
      expect(overview.streak, 17);
      expect(overview.attempts, 45);
      expect(overview.correct, 34);
      expect(overview.todaySessions, 2);
      expect(overview.days.length, 2);
      expect(overview.xp, 888);
    },
  );
  test('blocked, completed and generating roadmaps are never offered as next learning', () async {
    for (final data in [
      {
        ...plan(),
        'steps': [step(ready: false)],
      },
      {...plan(), 'completed': true},
      {...plan(), 'status': 'GENERATING'},
    ]) {
      final repo = LearningRepository(read: (p, q) async => data);
      expect(await StudentLearningRecords(repo).nextRoadmapStep(), isNull);
    }
  });
  testWidgets(
    'empty wrong list has no fabricated sample cards and failure offers retry',
    (tester) async {
      var failed = false;
      final repo = LearningRepository(
        read: (p, q) async {
          if (failed) throw Exception('offline');
          return {'items': []};
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: WrongAnswerScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('표시할 오답이 없어요.'), findsOneWidget);
      expect(find.textContaining('쎈'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      failed = true;
      await tester.pumpWidget(
        MaterialApp(home: WrongAnswerScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('다시 불러오기'), findsOneWidget);
      expect(find.text('표시할 오답이 없어요.'), findsNothing);
      failed = false;
      await tapText(tester, '다시 불러오기');
      expect(find.text('표시할 오답이 없어요.'), findsOneWidget);
    },
  );
  testWidgets(
    'pending history detail never displays wrong or offers a fabricated problem',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LearningHistoryDetailScreen(
            record: {
              'topic': '사진 풀이',
              'answers': [
                {'isCorrect': null, 'questionNumber': 1},
              ],
            },
            repository: LearningRepository(read: read),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('판정 보류'), findsOneWidget);
      expect(find.text('오답'), findsNothing);
      expect(find.text('오답 다시 풀기'), findsNothing);
    },
  );
  testWidgets(
    'history reads server records and displays ungraded submissions separately',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LearningHistoryScreen(
            repository: LearningRepository(read: read),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('제출 1회 · 정답 0회 · 미판정 1회'), findsOneWidget);
      expect(find.text('사진 풀이'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'wrong retry submits original ID and refreshes server resolved state without local XP',
    (tester) async {
      var resolved = false, posts = 0;
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/wrong-answers')) {
            return {
              'items': [wrong(resolved: resolved)],
            };
          }
          return read(p, q);
        },
        write: (method, path, body) async {
          if (path.endsWith('/learning-sessions')) return {'id': 91};
          if (path.endsWith('/tutor/session')) {
            posts++;
            expect((body as Map)['problem_id'], 23);
            resolved = true;
            return {
              'id': 99,
              'scenario': 'RECOMMENDED',
              'action': 'CHECK_ANSWER',
              'problem_id': 23,
              'status': 'GRADED',
              'message': '정답이에요.',
              'answer_correct': true,
              'is_correct': true,
              'rewards': {'xp': 4, 'new_badges': []},
            };
          }
          return {};
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: WrongAnswerScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      await tapText(tester, '원래 문제 다시 풀기');
      expect(find.byType(ProblemScreen), findsOneWidget);
      await tapText(tester, '그냥 정답 입력하기');
      await tester.enterText(find.byType(TextField), '5');
      await tapText(tester, '답안 저장하기');
      await tapText(tester, '제출하기');
      await tapText(tester, '학습 마치기');
      expect(find.text('정복완료'), findsOneWidget);
      expect(posts, 1);
      expect(await LearningStorage.loadSessions(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'home retains its design, shows server stats and exposes the roadmap',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = LearningRepository(read: read);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeTab(onNavigate: (_) {}, repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('분배법칙'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('누적 풀이 45회 · 정답 34회'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('17일 연속 학습 기록 🔥'), findsOneWidget);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tapText(tester, '내 학습 로드맵');
      expect(find.byType(ServerRoadmapScreen), findsOneWidget);
      expect(find.text('다음 학습: 분배법칙'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a missing roadmap is shown empty and generation happens only on request',
    (tester) async {
      var created = false, posts = 0;
      final repo = LearningRepository(
        read: (p, q) async {
          if (!created) {
            throw const ApiException(
              statusCode: 404,
              code: 'ROADMAP_NOT_FOUND',
              message: 'none',
            );
          }
          return plan();
        },
        write: (method, path, body) async {
          expect(path, '/api/v1/me/roadmap/generate');
          expect(body, {'goal_skill_codes': []});
          posts++;
          created = true;
          return plan();
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: ServerRoadmapScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(find.textContaining('아직 학습 계획이 없어요'), findsOneWidget);
      await tapText(tester, '로드맵 생성');
      expect(posts, 1);
      expect(find.text('다음 학습: 분배법칙'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
