import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/screens/tutor_session_screen.dart';
import 'package:stepi/screens/server_pathways.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/capture_service.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/tutor_session_service.dart';

import 'normal_problem_flow_test.dart' as normal;
import 'capture_learning_test.dart' as capture;
import 'ocr_correction_flow_test.dart' as correction;

final examples = jsonDecode(
  File('test/fixtures/tutor_session_examples.json').readAsStringSync(),
) as List;
JsonMap sample(int index, [JsonMap overrides = const {}]) => {
  ...Map<String, dynamic>.from(examples[index]['response']),
  ...overrides,
};
TutorTarget target(JsonMap request) => request['scenario'] == 'RECOMMENDED'
    ? TutorTarget.recommended(
        request['problem_id'],
        sessionId: request['session_id'],
      )
    : TutorTarget.photo(
        request['captured_problem_id'],
        withSolution: request['scenario'] == 'PHOTO_SOLVED',
        skillCode: request['skill_code'],
      );
Future<void> button(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(FilledButton, label);
  await correction.ensureTarget(tester, finder);
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  LearningRepository repo,
  TutorTarget source, {
  TutorSessionResult? initial,
  String action = 'START',
  Future<JsonMap> Function(String)? analyzePhoto,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: TutorSessionScreen(
        target: source,
        service: TutorSessionService(repository: repo),
        initialResult: initial,
        initialAction: action,
        analyzePhoto: analyzePhoto,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'default request keys are UUID v4 and intentional actions use fresh keys',
    () async {
      final keys = <String>[];
      final service = TutorSessionService(
        repository: LearningRepository(
          write: (method, path, body) async {
            final request = body as Map;
            keys.add(request['request_id'] as String);
            return sample(3, {'action': request['action'], 'problem_id': 123});
          },
        ),
      );
      await service.request(const TutorTarget.recommended(123), 'HINT');
      await service.request(const TutorTarget.recommended(123), 'HINT');
      for (final key in keys) {
        expect(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(key),
          isTrue,
        );
      }
      expect(keys.toSet(), hasLength(2));
    },
  );
  testWidgets(
    'photo REVIEW_REQUIRED retains server message verbatim and continues to HINT',
    (tester) async {
      const message = '사진 판정은 보류하고 x^2 + 2*x 식의 힌트를 확인해 주세요.';
      final data = sample(1, {
        'status': 'REVIEW_REQUIRED',
        'next_action': 'HINT',
        'message': message,
        'answer_correct': null,
        'solved': false,
      });
      await open(
        tester,
        LearningRepository(),
        target({
          'scenario': 'PHOTO_SOLVED',
          'captured_problem_id': data['captured_problem_id'],
        }),
        initial: TutorSessionResult(data),
      );
      expect(find.text(message), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '힌트 보기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'OCR confirmation precedes unified photo START, AI1 analysis precedes ANALYZE_RESULT',
    (tester) async {
      final writes = <JsonMap>[];
      JsonMap stored = capture.uploaded(51);
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/captured-problems/44')) return stored;
          throw StateError('Unexpected read: $p');
        },
        write: (m, p, b) async {
          writes.add({'path': p, 'body': b});
          if (m == 'PATCH') {
            stored = {...stored, ...(b as Map)};
            return stored;
          }
          if (p.endsWith('/tutor/session')) {
            final action = (b as Map)['action'];
            return action == 'START'
                ? sample(0, {'captured_problem_id': 44})
                : sample(1, {'captured_problem_id': 44});
          }
          expect(p, '/api/v1/captured-problems/44/analyze');
          return capture.analyzed();
        },
      );
      final service = CaptureService(
        repository: repo,
        picker: (_) async => capture.photo(),
        uploader: (_, s) async => stored,
      );
      await capture.open(tester, service);
      await capture.pickAndUpload(tester);
      await correction.tap(tester, 'AI와 학습 이어가기');
      expect(writes[0]['path'], '/api/v1/captured-problems/44/ocr');
      expect((writes[1]['body'] as Map)['scenario'], 'PHOTO_SOLVED');
      await button(tester, '사진 풀이 분석하기');
      expect(writes.map((r) => r['path']), [
        '/api/v1/captured-problems/44/ocr',
        '/api/v1/tutor/session',
        '/api/v1/captured-problems/44/ocr',
        '/api/v1/captured-problems/44/analyze',
        '/api/v1/tutor/session',
      ]);
      expect((writes[3]['body'] as Map)['skill_codes'], ['SKL-1-004']);
      expect((writes.last['body'] as Map)['action'], 'ANALYZE_RESULT');
      expect((writes.last['body'] as Map)['captured_problem_id'], 44);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'opening help for an existing analysis does not patch unchanged OCR or discard the attempt',
    (tester) async {
      final writes = <String>[];
      final service = CaptureService(
        repository: LearningRepository(
          write: (m, p, b) async {
            writes.add(p);
            if (p.endsWith('/ocr')) return capture.uploaded(51);
            if (p.endsWith('/analyze')) return capture.analyzed();
            expect(p, '/api/v1/tutor/session');
            expect((b as Map)['action'], 'ANALYZE_RESULT');
            return sample(1, {'captured_problem_id': 44});
          },
        ),
        picker: (_) async => capture.photo(),
        uploader: (_, s) async => capture.uploaded(51),
      );
      await capture.open(tester, service);
      await capture.pickAndUpload(tester);
      await correction.tap(tester, '확인하고 분석하기');
      await correction.tap(tester, 'AI 튜터에게 힌트 받기');
      expect(writes, [
        '/api/v1/captured-problems/44/ocr',
        '/api/v1/captured-problems/44/analyze',
        '/api/v1/tutor/session',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'NEXT_SKILL uses nested next_skill rather than inferring from correctness',
    (tester) async {
      final queries = <String?>[];
      final repo = LearningRepository(
        read: (p, q) async {
          expect(p, '/api/v1/problems');
          queries.add(q['skill_code']);
          return {
            'items': [
              {
                ...normal.problem(62),
                'question': '다음 개념 문제',
                'skill_codes': ['SKL-1-005'],
              },
            ],
            'total_pages': 1,
          };
        },
      );
      await open(
        tester,
        repo,
        const TutorTarget.recommended(37),
        initial: TutorSessionResult(sample(4)),
      );
      await button(tester, '다음 개념 학습');
      expect(queries, ['SKL-1-005']);
      expect(find.text('다음 개념 문제'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('all nine supplied Backend examples satisfy the actual request/response contract', () {
    expect(examples, hasLength(9));
    for (final row in examples) {
      final request = Map<String, dynamic>.from(row['request']);
      final response = TutorSessionResult.parse(
        Map<String, dynamic>.from(row['response']),
        target(request),
        request['action'],
      );
      expect(response.data['problem_id'], request['problem_id']);
      expect(
        response.data['captured_problem_id'],
        request['captured_problem_id'],
      );
    }
  });
  test('transport retries keep request_id; concurrent taps share a request; later intentional hints get new IDs', () async {
    final sent = <JsonMap>[];
    var ids = 0;
    final waiting = Completer<JsonMap>();
    final repo = LearningRepository(
      write: (m, p, b) async {
        expect(p, '/api/v1/tutor/session');
        sent.add(Map<String, dynamic>.from(b as Map));
        if (sent.length == 1) {
          throw const ApiException(
            statusCode: 503,
            code: 'AI_REQUEST_FAILED',
            message: 'lost response',
          );
        }
        if (sent.length == 2) return waiting.future;
        return sample(3);
      },
    );
    final service = TutorSessionService(
      repository: repo,
      requestId: () => 'test-${++ids}',
    );
    const source = TutorTarget.recommended(37);
    await expectLater(
      service.request(source, 'HINT'),
      throwsA(isA<ApiException>()),
    );
    final a = service.request(source, 'HINT'),
        b = service.request(source, 'HINT');
    expect(sent, hasLength(2));
    waiting.complete(sample(3));
    await Future.wait([a, b]);
    await service.request(source, 'HINT');
    expect(sent.map((r) => r['request_id']), ['test-1', 'test-1', 'test-2']);
    expect(sent.every((r) => !r.containsKey('hint_count')), isTrue);
  });
  test(
    'wrong-photo response is rejected and retry keeps the original request key',
    () async {
      final keys = <String>[];
      var count = 0;
      final service = TutorSessionService(
        repository: LearningRepository(
          write: (m, p, b) async {
            keys.add((b as Map)['request_id']);
            return sample(0, {'captured_problem_id': ++count == 1 ? 99 : 31});
          },
        ),
      );
      const source = TutorTarget.photo(31, withSolution: true);
      await expectLater(
        service.request(source, 'START'),
        throwsFormatException,
      );
      await service.request(source, 'START');
      expect(keys[0], keys[1]);
    },
  );
  test('PROBLEM_ONLY without verified Skill and invalid answers never send requests', () {
    var calls = 0;
    final service = TutorSessionService(
      repository: LearningRepository(
        write: (m, p, b) async {
          calls++;
          return {};
        },
      ),
    );
    expect(
      () => service.request(
        const TutorTarget.photo(32, withSolution: false),
        'START',
      ),
      throwsFormatException,
    );
    expect(
      () => service.request(
        const TutorTarget.recommended(39),
        'CHECK_ANSWER',
        answer: 'x' * 201,
      ),
      throwsFormatException,
    );
    expect(calls, 0);
  });
  testWidgets(
    'give up then show solution displays only student answer notation and never grades',
    (tester) async {
      final actions = <String>[];
      final repo = LearningRepository(
        write: (m, p, b) async {
          final action = (b as Map)['action'] as String;
          actions.add(action);
          if (action == 'GIVE_UP') return sample(5);
          expect(action, 'SHOW_SOLUTION');
          return sample(6, {
            'solution': {
              'answer': 'PRIVATE_GRADING_x**2',
              'answer_display': 'x²',
              'steps': ['양변에 같은 수를 더해요.', 'x²=4를 확인해요.'],
            },
          });
        },
      );
      await open(
        tester,
        repo,
        const TutorTarget.recommended(39),
        action: 'GIVE_UP',
      );
      expect(find.text('정답이에요!'), findsNothing);
      await button(tester, '해설 보기');
      await correction.ensureTarget(tester, find.text('정답: x²'));
      expect(find.text('정답: x²'), findsOneWidget);
      expect(find.textContaining('PRIVATE_GRADING'), findsNothing);
      expect(actions, ['GIVE_UP', 'SHOW_SOLUTION']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'photo RELEARN requests original photo then submits exactly next_problem.id as RECOMMENDED',
    (tester) async {
      final sent = <JsonMap>[];
      final repo = LearningRepository(
        read: (p, q) async => p == '/api/v1/problems/39'
            ? {
                ...normal.problem(39),
                'question': '다음 연습문제',
                'input_guidance': '정수 하나를 입력하세요.',
              }
            : normal.read(p, q),
        write: (m, p, b) async {
          if (p.endsWith('/learning-sessions')) return {'id': 12};
          expect(p, '/api/v1/tutor/session');
          final body = Map<String, dynamic>.from(b as Map);
          sent.add(body);
          if (body['action'] == 'RELEARN') return sample(2);
          expect(body['scenario'], 'RECOMMENDED');
          expect(body['problem_id'], 39);
          expect(body['answer'], '13');
          expect(body.containsKey('captured_problem_id'), isFalse);
          return sample(8);
        },
      );
      await open(
        tester,
        repo,
        const TutorTarget.photo(31, withSolution: true),
        initial: TutorSessionResult(sample(1)),
      );
      await button(tester, '한 문제 더 연습하기');
      expect(sent.single['captured_problem_id'], 31);
      await button(tester, '이 문제 풀기');
      expect(find.text('다음 연습문제'), findsOneWidget);
      await normal.tapText(tester, '그냥 정답 입력하기');
      expect(find.text('정수 하나를 입력하세요.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '13');
      await normal.tapText(tester, '답안 저장하기');
      await normal.tapText(tester, '제출하기');
      expect(find.text('정답'), findsOneWidget);
      expect(find.text('+ 15 XP'), findsOneWidget);
      expect(sent, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'hint returns to same draft; answer uses new API once and shows server XP zero',
    (tester) async {
      final sent = <JsonMap>[];
      final repo = LearningRepository(
        read: normal.read,
        write: (m, p, b) async {
          if (p.endsWith('/learning-sessions')) return {'id': 12};
          expect(p, '/api/v1/tutor/session');
          final data = Map<String, dynamic>.from(b as Map);
          sent.add(data);
          return data['action'] == 'HINT'
              ? sample(3, {'problem_id': 23})
              : sample(4, {'problem_id': 23});
        },
      );
      await normal.open(tester, repo);
      await normal.enterAnswer(tester, '5');
      await normal.tapText(tester, '모르겠어요');
      await button(tester, '답 입력하기');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '5',
      );
      await normal.tapText(tester, '답안 저장하기');
      await normal.tapText(tester, '제출하기');
      expect(sent.map((b) => b['action']), ['HINT', 'CHECK_ANSWER']);
      expect(find.text('+ 0 XP'), findsOneWidget);
      expect(find.text('정답'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'CONFIRM_INPUT saves exact photo and repeats same action after explicit confirmation with new request ID',
    (tester) async {
      final writes = <JsonMap>[];
      var starts = 0;
      final row = {
        'id': 32,
        'session_id': 12,
        'ocr_status': 'PARTIAL',
        'ocr_raw_text': 'x2 + 2x',
        'problem_text': null,
        'solution_text': null,
      };
      final repo = LearningRepository(
        read: (p, q) async {
          expect(p, '/api/v1/captured-problems/32');
          return row;
        },
        write: (m, p, b) async {
          writes.add({'path': p, 'body': b});
          if (m == 'PATCH') {
            expect(p, '/api/v1/captured-problems/32/ocr');
            return {...row, ...(b as Map)};
          }
          return ++starts == 1
              ? sample(7)
              : sample(7, {
                  'status': 'PROVIDED',
                  'next_action': 'CHECK_ANSWER',
                });
        },
      );
      await open(
        tester,
        repo,
        const TutorTarget.photo(
          32,
          withSolution: false,
          skillCode: 'SKL-1-004',
        ),
      );
      await button(tester, '사진 내용 확인·수정');
      await correction.ensureTarget(
        tester,
        find.byKey(const ValueKey('ocr-problem')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('ocr-problem')),
        'x^2+2*x',
      );
      await correction.tap(tester, '수정 내용 저장');
      await correction.tap(tester, '확인 완료 · 학습으로 돌아가기');
      expect(writes.map((r) => r['path']), [
        '/api/v1/tutor/session',
        '/api/v1/captured-problems/32/ocr',
        '/api/v1/tutor/session',
      ]);
      expect((writes.last['body'] as Map)['action'], 'START');
      expect((writes.last['body'] as Map)['skill_code'], 'SKL-1-004');
      expect(
        (writes.first['body'] as Map)['request_id'],
        isNot((writes.last['body'] as Map)['request_id']),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'AI1 required waits for analysis callback before ANALYZE_RESULT and uses returned Skill',
    (tester) async {
      final actions = <String>[];
      var analyzed = false;
      final repo = LearningRepository(
        write: (m, p, b) async {
          final action = (b as Map)['action'] as String;
          actions.add(action);
          if (action == 'START') return sample(0);
          expect(analyzed, isTrue);
          return sample(1);
        },
      );
      await open(
        tester,
        repo,
        const TutorTarget.photo(31, withSolution: true),
        analyzePhoto: (skill) async {
          expect(skill, 'SKL-1-004');
          analyzed = true;
          return capture.analyzed();
        },
      );
      await button(tester, '사진 풀이 분석하기');
      expect(actions, ['START', 'ANALYZE_RESULT']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'completion opens roadmap and unknown action keeps default concepts and retry',
    (tester) async {
      var writes = 0;
      final repo = LearningRepository(
        read: (p, q) async => {'steps': []},
        write: (m, p, b) async {
          writes++;
          return {};
        },
      );
      await open(
        tester,
        repo,
        const TutorTarget.recommended(39),
        initial: TutorSessionResult(sample(8)),
      );
      await button(tester, '학습 경로 보기');
      expect(find.byType(ServerRoadmapScreen), findsOneWidget);
      expect(writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await open(
        tester,
        repo,
        const TutorTarget.recommended(37),
        initial: TutorSessionResult(
          sample(3, {'next_action': 'FUTURE_ACTION', 'answer_correct': null}),
        ),
      );
      await correction.ensureTarget(tester, find.text('개념 설명 보기'));
      expect(find.text('원래 문제 다시 풀기'), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
