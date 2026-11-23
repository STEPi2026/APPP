import 'dart:math';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/capture_service.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/related_question_service.dart';
import 'package:stepi/screens/captured_history_screen.dart';
import 'package:stepi/screens/capture_learning_screen.dart';
import 'package:stepi/screens/problem_screen.dart';

import 'capture_learning_test.dart' as capture;
import 'ocr_correction_flow_test.dart' as correction;
import 'normal_problem_flow_test.dart' as normal;
import 'relearning_flow_test.dart' as related;

JsonMap partial() => {
  ...capture.analyzed(),
  'is_correct': null,
  'final_answer_present': false,
  'skill_codes': ['SKL-1-004'],
  'errors': [],
};
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'result help round trip preserves the accepted answer even when AI is unavailable',
    (tester) async {
      var submissions = 0;
      final repo = LearningRepository(
        read: normal.read,
        write: (m, p, b) async {
          if (p.endsWith('/learning-sessions')) return {'id': 51};
          if (p.endsWith('/tutor/session')) {
            if ((b as Map)['action'] != 'CHECK_ANSWER') {
              throw const ApiException(
                statusCode: 503,
                code: 'AI_CATALOG_NOT_READY',
                message: 'not ready',
              );
            }
            submissions++;
          }
          return normal.accepted();
        },
      );
      await http.runWithClient(
        () async {
          await normal.open(tester, repo);
          await normal.enterAnswer(tester, '5');
          await normal.tapText(tester, '제출하기');
          await normal.tapText(tester, '개념 도움 받기');
          expect(find.textContaining('지금은 도움을 불러올 수 없어요'), findsOneWidget);
          await correction.tap(tester, '원래 학습으로 돌아가기');
          expect(find.text('훌륭한 풀이입니다!'), findsOneWidget);
          expect(submissions, 1);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(tester.takeException(), isNull);
        },
        () => MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 'AI_CATALOG_NOT_READY',
              'message': 'not ready',
            }),
            503,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
    },
  );
  test(
    'unchanged retry never patches OCR or creates a corrected attempt',
    () async {
      final calls = <String>[];
      final service = CaptureService(
        repository: LearningRepository(
          write: (m, p, b) async {
            calls.add('$m $p');
            return capture.analyzed();
          },
        ),
      );
      await service.analyze(
        captureId: 44,
        problem: '문제',
        solution: '풀이',
        skills: ['SKL-1-004'],
        retryAnalysisId: 901,
      );
      expect(calls, ['POST /api/v1/ai-analyses/901/retry']);
    },
  );
  for (final status in ['UNKNOWN', 'REVIEW_REQUIRED', 'FAILED']) {
    testWidgets(
      '$status correction uses a new analysis even when old retries are exhausted',
      (tester) async {
        final calls = <JsonMap>[];
        var count = 0;
        final service = CaptureService(
          repository: LearningRepository(
            write: (m, p, b) async {
              calls.add({'method': m, 'path': p, 'body': b});
              if (p.endsWith('/analyze')) {
                if (++count == 1) {
                  return {
                    ...capture.analyzed(status: status, retries: 3),
                    'is_correct': null,
                  };
                }
                return {...capture.analyzed(), 'id': 902};
              }
              return capture.uploaded(51);
            },
          ),
          picker: (_) async => capture.photo(),
          uploader: (_, s) async => capture.uploaded(51),
        );
        await capture.open(tester, service);
        await capture.pickAndUpload(tester);
        await capture.tapText(tester, '확인하고 분석하기');
        await capture.tapText(tester, '인식 내용 확인하고 다시 시도하기');
        await correction.ensureTarget(
          tester,
          find.byKey(const ValueKey('ocr-solution')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('ocr-solution')),
          '2+3=5',
        );
        await correction.tap(tester, '수정한 내용으로 다시 분석하기');
        expect(calls.map((c) => c['path']), [
          '/api/v1/captured-problems/44/ocr',
          '/api/v1/captured-problems/44/analyze',
          '/api/v1/captured-problems/44/ocr',
          '/api/v1/captured-problems/44/analyze',
        ]);
        expect((calls[2]['body'] as Map)['problem_latex'], isNull);
        expect((calls[2]['body'] as Map)['solution_text'], '2+3=5');
      },
    );
  }
  testWidgets(
    'saved partial can be opened, closed and resumed without finishing or reuploading history',
    (tester) async {
      final calls = <JsonMap>[];
      var latest = partial();
      final repo = LearningRepository(
        read: (p, q) async => p.contains('/ai-analyses/')
            ? latest
            : {...capture.uploaded(51), 'latest_analysis': latest},
        write: (m, p, b) async {
          calls.add({'method': m, 'path': p, 'body': b});
          if (p.endsWith('/analyze')) {
            latest = {
              ...capture.analyzed(),
              'id': 902,
              'is_correct': true,
              'final_answer_present': true,
              'skill_codes': ['SKL-1-004'],
            };
            return latest;
          }
          return {
            ...capture.uploaded(51),
            'attempt_id': 2,
            'latest_analysis': null,
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SavedCaptureScreen(
            captureId: 44,
            repository: repo,
            imageLoader: (_) async => capture.photo().bytes,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await correction.tap(tester, '최종 답 추가하고 다시 분석하기');
      expect(find.byType(CaptureLearningScreen), findsOneWidget);
      expect(calls, isEmpty);
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(SavedCaptureScreen), findsOneWidget);
      expect(calls, isEmpty);
      await correction.tap(tester, '최종 답 추가하고 다시 분석하기');
      await correction.ensureTarget(
        tester,
        find.byKey(const ValueKey('ocr-solution')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('ocr-solution')),
        '2+3=5',
      );
      await correction.tap(tester, '최종 답 포함해 분석하기');
      expect(calls.map((c) => c['path']), [
        '/api/v1/captured-problems/44/ocr',
        '/api/v1/captured-problems/44/analyze',
      ]);
      expect(calls.last['body'], {
        'skill_codes': ['SKL-1-004'],
      });
      await tester.tap(find.byIcon(Icons.chevron_left_rounded));
      await tester.pumpAndSettle();
      expect(find.text('정답'), findsOneWidget);
      expect(calls.length, 2);
    },
  );
  testWidgets(
    'saved capture with mismatched analysis cannot be edited or analyzed',
    (tester) async {
      var writes = 0;
      final repo = LearningRepository(
        read: (p, q) async => p.contains('/ai-analyses/')
            ? {...partial(), 'captured_problem_id': 999}
            : {
                ...capture.uploaded(51),
                'latest_analysis': {'id': 901},
              },
        write: (m, p, b) async {
          writes++;
          return {};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CaptureLearningScreen(
            savedCaptureId: 44,
            service: CaptureService(repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('사진과 분석 결과가 일치하지'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(writes, 0);
    },
  );
  test(
    'related practice prioritizes unseen problems then the oldest attempt',
    () async {
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/23')) return related.item(23, 'PRACTICE');
          if (p.endsWith('/learning-history')) {
            return {
              'items': [
                {'problem_id': 99, 'attempted_at': '2026-11-17T00:00:00Z'},
                {'problem_id': 100, 'attempted_at': '2026-11-01T00:00:00Z'},
                {'problem_id': 101, 'attempted_at': '2026-11-05T00:00:00Z'},
              ],
            };
          }
          return {
            'items': [
              related.item(99, 'RELEARNING'),
              for (var i = 100; i <= 103; i++) related.item(i, 'PRACTICE'),
            ],
          };
        },
      );
      final result = await RelatedQuestionService(
        problemId: 23,
        repository: repo,
        random: Random(1),
      ).fetchQuestions();
      expect(result.take(2).map((q) => q.problemId).toSet(), {102, 103});
      expect(result.last.problemId, 100);
    },
  );
  testWidgets(
    'result to related practice and back never submits the accepted answer twice',
    (tester) async {
      var submissions = 0;
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/problems/23')) return normal.problem(23);
          if (p.endsWith('/problems/99')) return related.item(99, 'RELEARNING');
          if (p.endsWith('/problems')) {
            return {
              'items': [related.item(99, 'RELEARNING')],
            };
          }
          if (p.endsWith('/learning-history')) return {'items': []};
          return normal.read(p, q);
        },
        write: (m, p, b) async {
          if (p.endsWith('/learning-sessions')) return {'id': 51};
          if (p.endsWith('/tutor/session')) {
            if ((b as Map)['action'] == 'RELEARN') {
              return {
                ...normal.accepted(),
                'action': 'RELEARN',
                'answer_correct': null,
                'next_action': 'CHECK_ANSWER',
                'next_problem': {'id': 99, 'prompt': '문제 99'},
              };
            }
            submissions++;
          }
          return normal.accepted();
        },
      );
      await normal.open(tester, repo);
      await normal.enterAnswer(tester, '5');
      await normal.tapText(tester, '제출하기');
      expect(submissions, 1);
      await normal.tapText(tester, '같은 개념의 다른 문제 풀기');
      await correction.tap(tester, '이 문제 풀기');
      expect(find.text('문제 99'), findsOneWidget);
      Navigator.of(tester.element(find.byType(ProblemScreen))).pop();
      await tester.pumpAndSettle();
      await correction.tap(tester, '원래 학습으로 돌아가기');
      expect(find.text('훌륭한 풀이입니다!'), findsOneWidget);
      expect(submissions, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
