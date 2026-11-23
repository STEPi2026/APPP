import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/screens/capture_learning_screen.dart';
import 'package:stepi/screens/problem_screen.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/capture_service.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/learning_storage.dart';

CapturePhoto photo() =>
    CapturePhoto(File('img/badges/BDG-085.png').readAsBytesSync());
JsonMap uploaded(int sessionId) => {
  'id': 44,
  'session_id': sessionId,
  'problem_text': '2와 3을 더하면?',
  'solution_text': '2 + 3 = 6',
  'ocr_status': 'COMPLETED',
  'ocr_warnings': [],
};
JsonMap analyzed({String status = 'ANALYZED', int retries = 0}) => {
  'id': 901,
  'captured_problem_id': 44,
  'status': status,
  'is_correct': false,
  'first_error_step': 2,
  'solution_steps': ['2 + 3을 계산해요.', '2 + 3 = 6'],
  'errors': [
    {'step_no': 2, 'content': '덧셈 결과를 다시 확인해 주세요.'},
  ],
  'retry_count': retries,
};
PracticeQuestion question() => PracticeQuestion.fromServerJson({
  'id': 23,
  'problem_code': 'P23',
  'question': '2와 3을 더하면?',
  'problem_type': 'SHORT_ANSWER',
  'skill_codes': ['SKL-1-004'],
}, title: '덧셈');
Future<dynamic> read(String path, Map<String, String> query) async => {
  'items': [
    {'code': 'SKL-1-004', 'name': '덧셈의 원리'},
  ],
};
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.pumpAndSettle();
  if (find.text(text).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(
    tester.element(find.text(text)),
    alignment: .5,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  CaptureService service, {
  int? sessionId,
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
                builder: (_) => CaptureLearningScreen(
                  problem: question(),
                  service: service,
                  sessionId: sessionId,
                  maxPolls: 0,
                ),
              ),
            ),
            child: const Text('사진 학습 시작'),
          ),
        ),
      ),
    ),
  );
  await tapText(tester, '사진 학습 시작');
}

Future<void> pickAndUpload(WidgetTester tester) async {
  await tapText(tester, '앨범에서 사진 선택');
  await tapText(tester, '사진 올리고 내용 확인하기');
}

void main() {
  test('unsupported Skills never patch OCR or request analysis', () async {
    var writes = 0;
    final service = CaptureService(
      repository: LearningRepository(
        write: (m, p, b) async {
          writes++;
          return {};
        },
      ),
    );
    await expectLater(
      service.analyze(
        captureId: 44,
        problem: '문제',
        solution: '풀이',
        skills: ['SKL-2-018'],
      ),
      throwsFormatException,
    );
    expect(writes, 0);
  });
  testWidgets('raw OCR stays an unsplit original and never starts analysis', (
    tester,
  ) async {
    var writes = 0;
    final service = CaptureService(
      repository: LearningRepository(
        write: (m, p, b) async {
          writes++;
          return {};
        },
      ),
      picker: (_) async => photo(),
      uploader: (_, session) async => {
        ...uploaded(51),
        'problem_text': null,
        'solution_text': null,
        'ocr_raw_text': '문제와 학생 풀이가 섞인 원문',
      },
    );
    await open(tester, service);
    await pickAndUpload(tester);
    expect(find.text('인식된 원문'), findsOneWidget);
    expect(find.text('문제와 학생 풀이가 섞인 원문'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('확인하고 분석하기'), findsNothing);
    expect(writes, 0);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('photo validation rejects unsupported and oversized files', () {
    expect(
      () => CapturePhoto(Uint8List.fromList([255, 216])),
      throwsFormatException,
    );
    expect(
      () => CapturePhoto(Uint8List(10 * 1024 * 1024 + 1)),
      throwsFormatException,
    );
    expect(photo().filename, 'solution.png');
  });
  for (final status in ['REVIEW_REQUIRED', 'UNKNOWN']) {
    testWidgets('$status with null correctness is never treated as wrong', (
      tester,
    ) async {
      final service = CaptureService(
        repository: LearningRepository(
          read: read,
          write: (method, path, body) async => path.endsWith('/analyze')
              ? {...analyzed(status: status), 'is_correct': null}
              : {},
        ),
        picker: (_) async => photo(),
        uploader: (_, session) async => uploaded(51),
      );
      await open(tester, service);
      await pickAndUpload(tester);
      await tapText(tester, '확인하고 분석하기');
      expect(
        find.text(status == 'UNKNOWN' ? '풀이를 인식하지 못했어요' : '판정 보류'),
        findsOneWidget,
      );
      expect(find.text('풀이가 맞았어요!'), findsNothing);
      expect(find.text('처음 실수한 부분을 살펴볼까요?'), findsNothing);
      expect(find.text('2단계 · 최초 오류'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  for (final duringRetry in [false, true]) {
    testWidgets(
      'unsupported problem hides all retry actions (retry=$duringRetry)',
      (tester) async {
        var uploads = 0, posts = 0;
        final service = CaptureService(
          repository: LearningRepository(
            read: read,
            write: (method, path, body) async {
              if (method == 'POST') {
                posts++;
                if (duringRetry && posts == 1) {
                  return analyzed(status: 'FAILED');
                }
                throw const ApiException(
                  statusCode: 422,
                  code: 'PROBLEM_TYPE_NOT_SUPPORTED',
                  message: 'unsupported',
                );
              }
              return {};
            },
          ),
          picker: (_) async => photo(),
          uploader: (_, session) async {
            uploads++;
            return uploaded(51);
          },
        );
        await open(tester, service);
        await pickAndUpload(tester);
        await tapText(tester, '확인하고 분석하기');
        if (duringRetry) {
          await tapText(tester, '인식 내용 확인하고 다시 시도하기');
          await tapText(tester, '수정한 내용으로 다시 분석하기');
        }
        expect(
          find.text('아직 지원하지 않는 문제 유형이에요. 다른 문제를 이용해 주세요.'),
          findsOneWidget,
        );
        expect(find.text('확인하고 분석하기'), findsNothing);
        expect(find.text('수정한 내용으로 다시 분석하기'), findsNothing);
        expect(find.text('인식 내용 확인하고 다시 시도하기'), findsNothing);
        expect(find.text('분석 상태 다시 확인하기'), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(uploads, 1);
        expect(posts, duringRetry ? 2 : 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('multipart carries real image bytes, auth headers and optional parent session', () async {
    final p = photo();
    await http.runWithClient(
      () async {
        final service = CaptureService();
        expect((await service.upload(p, sessionId: 51))['id'], 44);
      },
      () => MockClient((request) async {
        expect(request.url.path, '/api/v1/captured-problems');
        expect(request.headers['ngrok-skip-browser-warning'], 'true');
        expect(
          request.headers['content-type'],
          contains('multipart/form-data; boundary='),
        );
        final body = String.fromCharCodes(request.bodyBytes);
        expect(body, contains('name="session_id"'));
        expect(body, contains('\r\n51\r\n'));
        expect(body, contains('name="image"'));
        expect(body, contains('image/png'));
        expect(body, contains(String.fromCharCodes(p.bytes)));
        return http.Response(
          jsonEncode(uploaded(51)),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  testWidgets(
    '503 preserves photo and corrected OCR; retry reuses upload and server Skill',
    (tester) async {
      var uploads = 0, requests = 0, finishes = 0;
      final writes = <JsonMap>[];
      final service = CaptureService(
        repository: LearningRepository(
          read: read,
          write: (method, path, body) async {
            writes.add({'method': method, 'path': path, 'body': body});
            if (path.endsWith('/analyze')) {
              requests++;
              if (requests == 1) {
                throw const ApiException(
                  statusCode: 503,
                  code: 'AI_NOT_CONFIGURED',
                  message: 'pending',
                );
              }
              return analyzed();
            }
            if (path.endsWith('/finish')) finishes++;
            return {};
          },
        ),
        picker: (source) async {
          expect(source, ImageSource.gallery);
          return photo();
        },
        uploader: (p, session) async {
          uploads++;
          expect(p.bytes, photo().bytes);
          return uploaded(51);
        },
      );
      await open(tester, service);
      await pickAndUpload(tester);
      await tester.enterText(find.byType(TextField).last, '2 + 3 = 6\n내 풀이 확인');
      await tapText(tester, '확인하고 분석하기');
      expect(find.textContaining('지금은 사진 분석을 이용할 수 없어요'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(
        (tester.widget(
          find.byType(TextField).last,
        ) as TextField).controller!.text,
        contains('내 풀이 확인'),
      );
      await tapText(tester, '확인하고 분석하기');
      expect(uploads, 1);
      expect(requests, 2);
      expect(
        (writes.where((w) => w['path'].endsWith('/analyze')).last['body']
            as Map)['skill_codes'],
        ['SKL-1-004'],
      );
      expect(find.text('2단계 · 최초 오류'), findsOneWidget);
      expect(find.text('덧셈 결과를 다시 확인해 주세요.'), findsOneWidget);
      expect(find.textContaining('획득 XP'), findsNothing);
      expect(await LearningStorage.loadSessions(), isEmpty);
      await tapText(tester, '원래 문제 다시 풀기');
      expect(finishes, 1);
      expect(find.text('사진 학습 시작'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending analysis refreshes the same ID after a failed read without re-posting',
    (tester) async {
      var posts = 0, gets = 0;
      final service = CaptureService(
        repository: LearningRepository(
          read: (path, query) async {
            if (path.endsWith('/skills')) return read(path, query);
            expect(path, '/api/v1/ai-analyses/901');
            gets++;
            if (gets == 1) {
              throw const ApiException(statusCode: 502, message: 'unavailable');
            }
            return analyzed();
          },
          write: (method, path, body) async {
            if (path.endsWith('/analyze')) {
              posts++;
              return {'id': 901, 'status': 'PENDING'};
            }
            return {};
          },
        ),
        picker: (_) async => photo(),
        uploader: (_, session) async => uploaded(51),
      );
      await open(tester, service);
      await pickAndUpload(tester);
      await tapText(tester, '확인하고 분석하기');
      expect(find.text('풀이를 살펴보고 있어요'), findsOneWidget);
      expect(find.text('2단계 · 최초 오류'), findsNothing);
      await tapText(tester, '분석 상태 다시 확인하기');
      expect(find.textContaining('지금은 사진 분석을 이용할 수 없어요'), findsOneWidget);
      await tapText(tester, '분석 상태 다시 확인하기');
      expect(find.text('2단계 · 최초 오류'), findsOneWidget);
      expect(posts, 1);
      expect(gets, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed analysis retries its own ID and respects server retry count',
    (tester) async {
      final posts = <String>[];
      final service = CaptureService(
        repository: LearningRepository(
          read: read,
          write: (method, path, body) async {
            if (method == 'POST') {
              posts.add(path);
              if (path.endsWith('/analyze')) {
                return analyzed(status: 'FAILED', retries: 2);
              }
              expect(path, '/api/v1/ai-analyses/901/retry');
              expect(body, isNull);
              return analyzed(status: 'UNKNOWN', retries: 3);
            }
            return {};
          },
        ),
        picker: (_) async => photo(),
        uploader: (_, session) async => uploaded(51),
      );
      await open(tester, service);
      await pickAndUpload(tester);
      await tapText(tester, '확인하고 분석하기');
      await tapText(tester, '인식 내용 확인하고 다시 시도하기');
      await tapText(tester, '수정한 내용으로 다시 분석하기');
      expect(posts, [
        '/api/v1/captured-problems/44/analyze',
        '/api/v1/ai-analyses/901/retry',
      ]);
      expect(find.text('분석 재시도 횟수를 모두 사용했어요.'), findsOneWidget);
      expect(find.text('인식 내용 확인하고 다시 시도하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'closing capture never finishes a session owned by the original problem',
    (tester) async {
      var finishes = 0;
      final service = CaptureService(
        repository: LearningRepository(
          read: read,
          write: (method, path, body) async {
            if (path.endsWith('/finish')) finishes++;
            return {};
          },
        ),
        picker: (_) async => photo(),
        uploader: (_, session) async {
          expect(session, 51);
          return uploaded(51);
        },
      );
      await open(tester, service, sessionId: 51);
      await pickAndUpload(tester);
      await tapText(tester, '원래 문제 다시 풀기');
      expect(finishes, 0);
      expect(find.text('사진 학습 시작'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'external photo does not ask the student to classify the problem',
    (tester) async {
      var writes = 0;
      final service = CaptureService(
        repository: LearningRepository(
          read: read,
          write: (m, p, b) async {
            writes++;
            return {};
          },
        ),
        picker: (_) async => photo(),
        uploader: (_, session) async => uploaded(51),
      );
      await tester.pumpWidget(
        MaterialApp(home: CaptureLearningScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await pickAndUpload(tester);
      expect(find.text('사진 분석을 준비하고 있어요'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('확인하고 분석하기'), findsNothing);
      expect(writes, 0);
    },
  );
  testWidgets(
    'unavailable OCR is not shown as recognized text or manual homework',
    (tester) async {
      var uploads = 0, writes = 0;
      final failed = {
        ...uploaded(51),
        'ocr_status': 'UNAVAILABLE',
        'problem_text': null,
        'solution_text': null,
      };
      final service = CaptureService(
        repository: LearningRepository(
          read: (p, q) async => failed,
          write: (m, p, b) async {
            writes++;
            return {};
          },
        ),
        picker: (_) async => photo(),
        uploader: (_, session) async {
          uploads++;
          return failed;
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: CaptureLearningScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await pickAndUpload(tester);
      expect(find.text('사진 인식 결과를 받지 못했어요'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('인식된 내용을 확인해 주세요'), findsNothing);
      await tapText(tester, '인식 결과 다시 확인');
      expect(uploads, 1);
      expect(writes, 0);
    },
  );
  testWidgets('empty completed OCR is not a recognition success', (
    tester,
  ) async {
    final service = CaptureService(
      repository: LearningRepository(read: read, write: (m, p, b) async => {}),
      picker: (_) async => photo(),
      uploader: (_, session) async => {
        ...uploaded(51),
        'problem_text': '',
        'solution_text': '',
      },
    );
    await open(tester, service);
    await pickAndUpload(tester);
    expect(find.text('사진 인식 결과를 받지 못했어요'), findsOneWidget);
    expect(find.text('확인하고 분석하기'), findsNothing);
  });
  testWidgets('pending OCR polls the same capture and uses server text', (
    tester,
  ) async {
    var reads = 0;
    final service = CaptureService(
      repository: LearningRepository(
        read: (path, q) async {
          expect(path, '/api/v1/captured-problems/44');
          reads++;
          return uploaded(51);
        },
      ),
      picker: (_) async => photo(),
      uploader: (_, session) async => {
        ...uploaded(51),
        'ocr_status': 'PROCESSING',
        'problem_text': null,
        'solution_text': null,
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CaptureLearningScreen(
          problem: question(),
          service: service,
          pollInterval: const Duration(milliseconds: 1),
          maxPolls: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pickAndUpload(tester);
    expect(reads, 1);
    expect(find.text('인식된 내용을 확인해 주세요'), findsOneWidget);
  });
}
