import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/related_question_service.dart';
import 'package:stepi/services/student_learning_records.dart';
import 'package:stepi/screens/concept_level_test_dialog.dart';
import 'package:stepi/screens/learning_history_detail_screen.dart';

JsonMap item(int id, String usage, {String skill = 'S1'}) => {
  'id': id,
  'problem_code': 'P$id',
  'tutor_ready': true,
  'question': '문제 $id',
  'problem_type': 'SHORT_ANSWER',
  'usage': usage,
  'skill_codes': [skill],
};
Future<void> tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'completed diagnosis opens catalog practice for the returned weak Skill',
    (tester) async {
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/users/me')) return {'id': 7};
          if (p.endsWith('/me/diagnostics')) {
            return {
              'items': [
                {'id': 22, 'status': 'IN_PROGRESS'},
              ],
            };
          }
          if (p == '/api/v1/diagnostics/22') {
            return {'id': 22, 'status': 'COMPLETED'};
          }
          if (p.endsWith('/results')) {
            return {
              'assessed': [],
              'weak_skill_codes': ['S1'],
              'unassessed_skill_codes': [],
            };
          }
          if (p.endsWith('/problems')) {
            expect(q['skill_code'], 'S1');
            return {
              'items': [item(99, 'RELEARNING')],
            };
          }
          return {'items': []};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConceptLevelTestDialog(concepts: const [], repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, '기초 문제로 진단하기');
      expect(find.text('확인 문제 진단 완료!'), findsOneWidget);
      await tap(tester, 'S1 연습하기');
      expect(find.text('문제 99'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('related catalog excludes original, diagnostic and unrelated Skill and deduplicates pages', () async {
    final repo = LearningRepository(
      read: (p, q) async {
        if (p.endsWith('/23')) return item(23, 'PRACTICE');
        return {
          'items': [
            item(23, 'PRACTICE'),
            item(99, 'RELEARNING'),
            item(100, 'PRACTICE'),
            item(101, 'DIAGNOSTIC'),
            item(102, 'RELEARNING', skill: 'OTHER'),
            item(99, 'RELEARNING'),
          ],
          'total_pages': 1,
        };
      },
    );
    final questions = await RelatedQuestionService(
      problemId: 23,
      repository: repo,
    ).fetchQuestions();
    expect(questions.map((q) => q.problemId), [99, 100]);
  });
  test(
    'diagnosed Skill connects to catalog without invented problem IDs',
    () async {
      final repo = LearningRepository(
        read: (p, q) async {
          if (p == '/api/v1/me/learning-history') return {'items': []};
          expect(p, '/api/v1/problems');
          expect(q['skill_code'], 'S1');
          return {
            'items': [item(99, 'RELEARNING')],
          };
        },
      );
      expect(
        (await RelatedQuestionService(
          skillCode: 'S1',
          repository: repo,
        ).fetchQuestions()).single.problemId,
        99,
      );
    },
  );
  test('no other problem produces a real empty state', () async {
    final repo = LearningRepository(
      read: (p, q) async => p.endsWith('/23')
          ? item(23, 'PRACTICE')
          : {
              'items': [item(23, 'PRACTICE')],
            },
    );
    await expectLater(
      RelatedQuestionService(problemId: 23, repository: repo).fetchQuestions(),
      throwsFormatException,
    );
  });
  test(
    'KST date filter splits a single session spanning midnight before grouping',
    () async {
      final repo = LearningRepository(
        read: (p, q) async => {
          'items': p.endsWith('/learning-history')
              ? [
                  {
                    'id': 1,
                    'session_id': 5,
                    'problem_id': 23,
                    'attempted_at': '2026-11-10T14:59:00Z',
                    'is_correct': false,
                  },
                  {
                    'id': 2,
                    'session_id': 5,
                    'problem_id': 23,
                    'attempted_at': '2026-11-10T15:01:00Z',
                    'is_correct': true,
                  },
                ]
              : [],
        },
      );
      final records = StudentLearningRecords(repo);
      final first = await records.history(
        studyDate: DateTime.utc(2026, 11, 10),
      );
      final second = await records.history(
        studyDate: DateTime.utc(2026, 11, 11),
      );
      expect(first.single['answers'].single['isCorrect'], false);
      expect(second.single['answers'].single['isCorrect'], true);
      expect(first.single['totalCount'], 1);
      expect(
        await records.history(studyDate: DateTime.utc(2026, 11, 12)),
        isEmpty,
      );
    },
  );
  testWidgets(
    'diagnosis starts without self-check and resumes existing server session without writes',
    (tester) async {
      var writes = 0;
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/users/me')) return {'id': 7};
          if (p == '/api/v1/me/diagnostics') {
            return {
              'items': [
                {'id': 22, 'status': 'IN_PROGRESS'},
              ],
            };
          }
          if (p == '/api/v1/diagnostics/22') {
            return {
              'id': 22,
              'status': 'IN_PROGRESS',
              'answered_count': 2,
              'current_question': {
                'question_id': 'Q3',
                'prompt': '기초 계산을 해보세요',
              },
            };
          }
          return {'items': []};
        },
        write: (m, p, b) async {
          writes++;
          return {};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConceptLevelTestDialog(concepts: const [], repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('알아요'), findsNothing);
      await tap(tester, '기초 문제로 진단하기');
      expect(find.text('기초 계산을 해보세요'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(writes, 0);
    },
  );
  testWidgets(
    'correct history can retry or practice another problem and never overwrites old answer',
    (tester) async {
      final writes = <JsonMap>[];
      final repo = LearningRepository(
        read: (p, q) async {
          if (p.endsWith('/problems/23')) return item(23, 'PRACTICE');
          if (p.endsWith('/problems')) {
            return {
              'items': [item(99, 'RELEARNING')],
            };
          }
          return {'xp': 0, 'level': 1, 'xp_to_next_level': 50};
        },
        write: (m, p, b) async {
          writes.add({'path': p, 'body': b});
          if (p.endsWith('/learning-sessions')) return {'id': 6};
          return {
            'id': 1000,
            'is_correct': false,
            'rewards': {'xp': 0},
          };
        },
      );
      final record = {
        'answers': [
          {
            'problemId': 23,
            'question': '원래 문제',
            'selectedAnswer': '5',
            'isCorrect': true,
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: LearningHistoryDetailScreen(record: record, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('원래 문제 다시 풀기'), findsOneWidget);
      await tap(tester, '같은 개념의 다른 문제 풀기');
      expect(find.text('문제 99'), findsOneWidget);
      expect(writes, isEmpty);
      await tap(tester, '그냥 정답 입력하기');
      await tester.enterText(find.byType(TextField), '3/2');
      await tap(tester, '답안 저장하기');
      await tap(tester, '제출하기');
      expect((writes.last['body'] as Map)['problem_id'], 99);
      expect(record['answers']!.single['selectedAnswer'], '5');
      expect(record['answers']!.single['isCorrect'], true);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
