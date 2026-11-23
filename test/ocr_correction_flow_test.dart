import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/capture_service.dart';
import 'package:stepi/screens/capture_learning_screen.dart';
import 'package:stepi/screens/captured_history_screen.dart';

import 'capture_learning_test.dart' as fixture;

const raw = '2+3?\n2+3=5\nX=5';
JsonMap partial({String status = 'PARTIAL'}) => {
  ...fixture.uploaded(51),
  'ocr_status': status,
  'ocr_raw_text': raw,
  'problem_text': null,
  'problem_latex': null,
  'solution_text': null,
  'ocr_confidence': 0.715,
  'ocr_warnings': ['Raw OCR preview only: ...'],
};
Future<void> ensureTarget(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2500));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await ensureTarget(tester, find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'external PARTIAL can be corrected and saved without classification or analysis',
    (tester) async {
      final writes = <JsonMap>[];
      final saved = Completer<JsonMap>();
      var uploads = 0;
      final service = CaptureService(
        repository: LearningRepository(
          write: (m, p, b) async {
            writes.add({'method': m, 'path': p, 'body': b});
            return saved.future;
          },
        ),
        picker: (_) async => fixture.photo(),
        uploader: (_, s) async {
          uploads++;
          return partial();
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: CaptureLearningScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await fixture.pickAndUpload(tester);
      expect(find.text(raw), findsOneWidget);
      expect(find.text('사진 인식 결과를 받지 못했어요'), findsNothing);
      await tap(tester, '인식 내용 확인·수정');
      expect(find.text('확인하고 분석하기'), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tap(tester, '문제 칸에 가져오기');
      await ensureTarget(tester, find.byKey(const ValueKey('ocr-problem')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ocr-problem')))
            .controller!
            .text,
        raw,
      );
      await ensureTarget(tester, find.byKey(const ValueKey('ocr-problem')));
      await tester.enterText(
        find.byKey(const ValueKey('ocr-problem')),
        '2+3은?',
      );
      await ensureTarget(tester, find.text('수정 내용 저장'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('수정 내용 저장'));
      await tester.tap(find.text('수정 내용 저장'));
      expect(writes.length, 1);
      expect(writes.single, {
        'method': 'PATCH',
        'path': '/api/v1/captured-problems/44/ocr',
        'body': {
          'problem_text': '2+3은?',
          'problem_latex': null,
          'solution_text': '',
        },
      });
      saved.complete({...partial(), 'problem_text': '2+3은?'});
      await tester.pumpAndSettle();
      expect(find.text('수정 내용 저장됨'), findsOneWidget);
      expect(writes.length, 1);
      expect(uploads, 1);
      expect(find.textContaining('Raw OCR preview only'), findsNothing);
      expect(find.text('확인하고 분석하기'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registered PARTIAL prefills catalog prompt and analyzes only explicitly corrected solution',
    (tester) async {
      final writes = <JsonMap>[];
      final service = CaptureService(
        repository: LearningRepository(
          write: (m, p, b) async {
            writes.add({'method': m, 'path': p, 'body': b});
            if (p.endsWith('/analyze')) {
              return {
                ...fixture.analyzed(status: 'REVIEW_REQUIRED'),
                'is_correct': null,
              };
            }
            return partial();
          },
        ),
        picker: (_) async => fixture.photo(),
        uploader: (_, s) async => partial(),
      );
      await fixture.open(tester, service);
      await fixture.pickAndUpload(tester);
      expect(writes, isEmpty);
      await tap(tester, '인식 내용 확인·수정');
      await ensureTarget(tester, find.byKey(const ValueKey('ocr-problem')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ocr-problem')))
            .controller!
            .text,
        fixture.question().question,
      );
      await ensureTarget(tester, find.byKey(const ValueKey('ocr-solution')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ocr-solution')))
            .controller!
            .text,
        isEmpty,
      );
      await tap(tester, '풀이 칸에 가져오기');
      await ensureTarget(tester, find.byKey(const ValueKey('ocr-solution')));
      await tester.enterText(
        find.byKey(const ValueKey('ocr-solution')),
        '2+3=5',
      );
      await tap(tester, '확인하고 분석하기');
      expect(writes.length, 2);
      expect(writes.first['path'], '/api/v1/captured-problems/44/ocr');
      expect(
        (writes.first['body'] as Map)['problem_text'],
        fixture.question().question,
      );
      expect((writes.first['body'] as Map)['solution_text'], '2+3=5');
      expect(writes.last['body'], {
        'skill_codes': ['SKL-1-004'],
      });
      expect(find.text('판정 보류'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed correction preserves edits and retries the same capture',
    (tester) async {
      var saves = 0, uploads = 0;
      final service = CaptureService(
        repository: LearningRepository(
          write: (m, p, b) async {
            expect(p, '/api/v1/captured-problems/44/ocr');
            expect((b as Map)['problem_text'], '수정한 문제');
            if (++saves == 1) {
              throw const ApiException(statusCode: 503, message: 'offline');
            }
            return {...partial(), 'problem_text': '수정한 문제'};
          },
        ),
        picker: (_) async => fixture.photo(),
        uploader: (_, s) async {
          uploads++;
          return partial();
        },
      );
      await tester.pumpWidget(
        MaterialApp(home: CaptureLearningScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await fixture.pickAndUpload(tester);
      await tap(tester, '인식 내용 확인·수정');
      await ensureTarget(tester, find.byKey(const ValueKey('ocr-problem')));
      await tester.enterText(
        find.byKey(const ValueKey('ocr-problem')),
        '수정한 문제',
      );
      await tap(tester, '수정 내용 저장');
      await ensureTarget(tester, find.byKey(const ValueKey('ocr-problem')));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ocr-problem')))
            .controller!
            .text,
        '수정한 문제',
      );
      await tap(tester, '수정 내용 저장');
      expect(saves, 2);
      expect(uploads, 1);
      expect(find.text('수정 내용 저장됨'), findsOneWidget);
    },
  );

  for (final status in ['UNREADABLE', 'FAILED', 'UNAVAILABLE']) {
    testWidgets('$status does not expose stale raw text as successful OCR', (
      tester,
    ) async {
      final service = CaptureService(
        picker: (_) async => fixture.photo(),
        uploader: (_, s) async => partial(status: status),
      );
      await tester.pumpWidget(
        MaterialApp(home: CaptureLearningScreen(service: service)),
      );
      await tester.pumpAndSettle();
      await fixture.pickAndUpload(tester);
      expect(find.text('인식 내용 확인·수정'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(raw), findsNothing);
      if (status == 'UNREADABLE') {
        expect(find.text('사진의 글씨를 읽지 못했어요'), findsOneWidget);
      }
    });
  }
  test(
    'correction checks capture identity and size before reporting success',
    () async {
      var writes = 0;
      final service = CaptureService(
        repository: LearningRepository(
          write: (m, p, b) async {
            writes++;
            return {...partial(), 'id': 99};
          },
        ),
      );
      await expectLater(
        service.correctOcr(
          captureId: 44,
          sessionId: 51,
          problem: '',
          solution: '',
        ),
        throwsFormatException,
      );
      expect(writes, 0);
      await expectLater(
        service.correctOcr(
          captureId: 44,
          sessionId: 51,
          problem: '문제',
          solution: '풀이',
        ),
        throwsFormatException,
      );
      expect(writes, 1);
    },
  );
  testWidgets('saved history shows raw and corrected text without writes', (
    tester,
  ) async {
    var writes = 0;
    final repo = LearningRepository(
      read: (p, q) async => {
        ...partial(),
        'problem_text': '수정된 문제',
        'solution_text': '수정된 풀이',
      },
      write: (m, p, b) async {
        writes++;
        return {};
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SavedCaptureScreen(
          captureId: 44,
          repository: repo,
          imageLoader: (_) async => fixture.photo().bytes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
    expect(find.text('수정된 문제'), findsOneWidget);
    await ensureTarget(tester, find.text('수정된 풀이'));
    expect(find.text('수정된 풀이'), findsOneWidget);
    expect(writes, 0);
    expect(tester.takeException(), isNull);
  });
}
