import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/capture_service.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/student_learning_records.dart';
import 'package:stepi/screens/captured_history_screen.dart';

import 'capture_learning_test.dart' as fixture;

JsonMap partial() => {
  ...fixture.analyzed(),
  'status': 'ANALYZED',
  'is_correct': null,
  'final_answer_present': false,
  'first_error_step': null,
  'errors': [],
  'solution_steps': ['2+3'],
  'retry_count': 3,
};
void main() {
  test('partial assessment requires the exact three-field combination', () {
    expect(CaptureService.isPartial(partial()), isTrue);
    expect(CaptureService.assessmentLabel(partial()), '풀이가 끝나지 않았어요');
    for (final status in ['REVIEW_REQUIRED', 'UNKNOWN', 'FAILED']) {
      final value = {...partial(), 'status': status};
      expect(CaptureService.isPartial(value), isFalse);
      expect(
        CaptureService.assessmentLabel(value),
        status == 'UNKNOWN'
            ? '풀이를 인식하지 못했어요'
            : status == 'FAILED'
            ? '분석에 실패했어요'
            : '판정 보류',
      );
    }
    expect(
      CaptureService.assessmentLabel({...partial(), 'is_correct': true}),
      '정답',
    );
    expect(
      CaptureService.assessmentLabel({...partial(), 'is_correct': false}),
      '오답',
    );
    expect(
      CaptureService.assessmentLabel({
        ...partial(),
        'final_answer_present': null,
      }),
      '판정 보류',
    );
    expect(
      CaptureService.assessmentLabel(
        fixture.analyzed(status: 'ANALYZED')..['is_correct'] = null,
      ),
      '판정 보류',
    );
    expect(
      () => CaptureService.validateAnalysis({
        ...partial(),
        'final_answer_present': 'false',
      }),
      throwsFormatException,
    );
  });
  testWidgets(
    'partial solution is corrected and creates a new analysis instead of retrying old analysis',
    (tester) async {
      final writes = <JsonMap>[];
      var analyses = 0;
      final service = CaptureService(
        repository: LearningRepository(
          write: (m, p, b) async {
            writes.add({'path': p, 'body': b});
            if (p.endsWith('/analyze')) {
              if (++analyses == 1) return partial();
              return {
                ...fixture.analyzed(),
                'id': 902,
                'is_correct': true,
                'final_answer_present': true,
                'errors': [],
              };
            }
            return fixture.uploaded(51);
          },
        ),
        picker: (_) async => fixture.photo(),
        uploader: (_, s) async => fixture.uploaded(51),
      );
      await fixture.open(tester, service);
      await fixture.pickAndUpload(tester);
      await fixture.tapText(tester, '확인하고 분석하기');
      expect(find.text('풀이가 끝나지 않았어요'), findsOneWidget);
      expect(find.text('AI 튜터에게 힌트 받기'), findsNothing);
      expect(find.textContaining('최초 오류'), findsNothing);
      expect(find.text('분석 재시도 횟수를 모두 사용했어요.'), findsNothing);
      await fixture.tapText(tester, '최종 답 추가하고 다시 분석하기');
      await tester.enterText(
        find.byKey(const ValueKey('ocr-solution')),
        '2+3=5',
      );
      await fixture.tapText(tester, '최종 답 포함해 분석하기');
      expect(writes.map((w) => w['path']), [
        '/api/v1/captured-problems/44/ocr',
        '/api/v1/captured-problems/44/analyze',
        '/api/v1/captured-problems/44/ocr',
        '/api/v1/captured-problems/44/analyze',
      ]);
      expect((writes[2]['body'] as Map)['solution_text'], '2+3=5');
      expect(find.text('풀이가 맞았어요!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'saved partial solution has guidance and no correct or wrong coaching',
    (tester) async {
      var writes = 0;
      final repo = LearningRepository(
        read: (p, q) async => p.endsWith('/ai-analyses/901')
            ? partial()
            : {...fixture.uploaded(51), 'latest_analysis': partial()},
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
      expect(find.text('풀이가 끝나지 않았어요'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('최종 답까지 작성'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('최종 답까지 작성'), findsOneWidget);
      expect(find.text('AI 튜터에게 힌트 받기'), findsNothing);
      expect(writes, 0);
    },
  );
  test('history preserves partial as ungraded and maps it only to matching photo attempt', () async {
    final repo = LearningRepository(
      read: (p, q) async => {
        'items': p.endsWith('/learning-history')
            ? [
                {
                  'id': 1,
                  'session_id': 51,
                  'is_correct': null,
                  'attempted_at': '2026-11-17T00:00:00Z',
                },
              ]
            : p.endsWith('/captured-problems')
            ? [
                {
                  ...fixture.uploaded(51),
                  'attempt_id': 1,
                  'latest_analysis': partial(),
                },
              ]
            : [],
      },
    );
    final records = await StudentLearningRecords(repo).history();
    expect(records.single['correctCount'], 0);
    expect(records.single['answers'].single['isCorrect'], isNull);
    expect(records.single['answers'].single['isPartialSolution'], isTrue);
  });
}
