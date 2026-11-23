import 'package:stepi/models/practice_question.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/learning_repository.dart';

import 'normal_problem_flow_test.dart' as normal;

PracticeQuestion question(int id, bool? ready) =>
    PracticeQuestion.fromServerJson({
      ...normal.problem(id),
      'tutor_ready': ready,
    }, title: '다항식');

void main() {
  testWidgets('non-Tutor problems grade and move next without any AI request', (
    tester,
  ) async {
    final paths = <String>[];
    final repo = LearningRepository(
      read: normal.read,
      write: (method, path, body) async {
        paths.add(path);
        if (path.endsWith('/learning-sessions')) return {'id': 51};
        expect(path, '/api/v1/problem-attempts');
        final b = body as Map;
        expect(b['student_answer'], '5');
        expect(b['session_id'], 51);
        return {
          'id': 81,
          'problem_id': 23,
          'is_correct': true,
          'rewards': {'xp': 7},
        };
      },
    );
    await normal.open(
      tester,
      repo,
      questions: normal.FixedQuestions([
        question(23, false),
        question(24, false),
      ]),
    );
    await normal.enterAnswer(tester, '5');
    await normal.tapText(tester, '제출하기');
    expect(find.text('정답'), findsOneWidget);
    expect(find.text('+ 7 XP'), findsOneWidget);
    expect(find.text('개념 도움 받기'), findsNothing);
    await normal.tapText(tester, '다음 문제 풀기 ▶');
    expect(find.text('다항식 (2/2)'), findsOneWidget);
    expect(paths, ['/api/v1/learning-sessions', '/api/v1/problem-attempts']);
  });
  testWidgets('Tutor 502 retry stays on CHECK_ANSWER with same request ID', (
    tester,
  ) async {
    final keys = <String>[];
    final repo = LearningRepository(
      read: normal.read,
      write: (method, path, body) async {
        if (path.endsWith('/learning-sessions')) return {'id': 51};
        expect(path, '/api/v1/tutor/session');
        final b = body as Map;
        expect(b['action'], 'CHECK_ANSWER');
        keys.add(b['request_id'] as String);
        if (keys.length == 1) {
          throw const ApiException(
            statusCode: 502,
            code: 'AI_REQUEST_FAILED',
            message: 'offline',
          );
        }
        return normal.accepted();
      },
    );
    await normal.open(
      tester,
      repo,
      questions: normal.FixedQuestions([question(23, true)]),
    );
    await normal.enterAnswer(tester, '5');
    await normal.tapText(tester, '제출하기');
    expect(find.textContaining('AI 응답을 불러오지'), findsOneWidget);
    await normal.tapText(tester, '제출하기');
    expect(keys, hasLength(2));
    expect(keys[0], keys[1]);
    expect(find.text('정답'), findsOneWidget);
  });
  testWidgets('missing route metadata refreshes problem before grading', (
    tester,
  ) async {
    var refreshes = 0;
    final paths = <String>[];
    final repo = LearningRepository(
      read: (path, q) async {
        if (path == '/api/v1/problems/23') {
          refreshes++;
          return {...normal.problem(23), 'tutor_ready': false};
        }
        return normal.read(path, q);
      },
      write: (method, path, body) async {
        paths.add(path);
        if (path.endsWith('/learning-sessions')) return {'id': 51};
        expect(path, '/api/v1/problem-attempts');
        return {
          'id': 81,
          'is_correct': true,
          'rewards': {'xp': 0},
        };
      },
    );
    await normal.open(
      tester,
      repo,
      questions: normal.FixedQuestions([question(23, null)]),
    );
    await normal.enterAnswer(tester, '5');
    await normal.tapText(tester, '제출하기');
    expect(refreshes, 1);
    expect(paths, contains('/api/v1/problem-attempts'));
  });
  testWidgets('unknown route never guesses a grading API', (tester) async {
    var writes = 0;
    final repo = LearningRepository(
      read: (p, q) async => normal.problem(23)..remove('tutor_ready'),
      write: (m, p, b) async {
        writes++;
        return {};
      },
    );
    await normal.open(
      tester,
      repo,
      questions: normal.FixedQuestions([question(23, null)]),
    );
    await normal.enterAnswer(tester, '5');
    await normal.tapText(tester, '제출하기');
    expect(writes, 0);
    expect(find.textContaining('채점 경로 정보를 갱신'), findsOneWidget);
  });
  test('server routing flag survives saved-question roundtrip', () {
    final original = question(23, false);
    expect(PracticeQuestion.fromJson(original.toJson()).tutorReady, isFalse);
    expect(
      () => PracticeQuestion.fromServerJson({
        ...normal.problem(23),
        'tutor_ready': 'false',
      }, title: '다항식'),
      throwsFormatException,
    );
  });
}
