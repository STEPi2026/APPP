import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/models/answer_input.dart';
import 'package:stepi/models/practice_question.dart';
import 'package:stepi/services/numeric_answer_formatter.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/screens/concept_level_test_dialog.dart';

import 'normal_problem_flow_test.dart' as practice;

const options = [
  {'label': 'x² + 2x + 1', 'value': '(x+1)^2'},
  {'label': 'x² + 1', 'value': 'x^2+1'},
];
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('input mode comes from explicit metadata, never from x squared in the prompt', () {
    final number = AnswerInput.fromJson({
      'problem_type': 'SHORT_ANSWER',
      'answer_form': 'NUMERIC',
      'question': 'x²の係数は?',
    });
    expect(number.isChoice, false);
    for (final value in ['-2', '0.5', '3/2', '+12']) {
      expect(number.accepts(value), true);
    }
    for (final value in ['x^2', '1/0', '2+2', '1 2', '']) {
      expect(number.accepts(value), false);
    }
    final expression = AnswerInput.fromJson({
      'problem_type': 'MULTIPLE_CHOICE',
      'choices': options,
    });
    expect(expression.accepts('(x+1)^2'), true);
    expect(expression.accepts('x² + 2x + 1'), false);
    expect(
      AnswerInput.fromJson({'problem_type': 'SHORT_ANSWER', 'question': 'x²=9'})
          .isNumeric,
      false,
    );
  });
  test('numeric input rejects a whole pasted expression instead of keeping its digits', () {
    final formatter = NumericAnswerFormatter();
    const old = TextEditingValue(text: '3/2');
    expect(
      formatter.formatEditUpdate(old, const TextEditingValue(text: 'x^2')),
      old,
    );
    expect(
      formatter
          .formatEditUpdate(old, const TextEditingValue(text: '-0.5'))
          .text,
      '-0.5',
    );
  });
  test(
    'missing or ambiguous choices cannot silently become a text question',
    () {
      for (final data in [
        {'problem_type': 'MULTIPLE_CHOICE'},
        {'problem_type': 'SHORT_ANSWER', 'answer_form': 'EXPRESSION'},
        {
          'problem_type': 'OX',
          'choices': [
            {'label': 'O', 'value': 'same'},
            {'label': 'X', 'value': 'same'},
          ],
        },
      ]) {
        expect(AnswerInput.fromJson(data).missingChoices, true);
      }
      final q = PracticeQuestion.fromServerJson({
        ...practice.problem(23),
        'problem_type': 'MULTIPLE_CHOICE',
      }, title: '보기 준비');
      expect(q.validate, throwsFormatException);
    },
  );
  testWidgets(
    'practice choices replace keyboard input and submit the exact server value',
    (tester) async {
      final q = PracticeQuestion.fromServerJson({
        ...practice.problem(23),
        'problem_type': 'MULTIPLE_CHOICE',
        'choices': options,
      }, title: '식 선택');
      final answers = <String>[];
      final repo = LearningRepository(
        read: practice.read,
        write: (m, p, b) async {
          if (p.endsWith('/learning-sessions')) return {'id': 51};
          if (p.endsWith('/tutor/session')) {
            answers.add((b as Map)['answer']);
          }
          return practice.accepted();
        },
      );
      await practice.open(
        tester,
        repo,
        questions: practice.FixedQuestions([q]),
      );
      await practice.tapText(tester, '보기에서 답 선택하기');
      expect(find.byType(TextField), findsNothing);
      await practice.tapText(tester, '1번: x² + 2x + 1');
      await practice.tapText(tester, '답안 저장하기');
      await practice.tapText(tester, '제출하기');
      expect(answers, ['(x+1)^2']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
  for (final numeric in [false, true]) {
    testWidgets(
      'diagnostic ${numeric ? 'numeric' : 'choice'} submits an answer value and resets for next question',
      (tester) async {
        final bodies = <JsonMap>[];
        final question = numeric
            ? {
                'question_id': 'Q1',
                'prompt': 'x²=9의 양의 해는?',
                'answer_form': 'NUMERIC',
              }
            : {
                'question_id': 'Q1',
                'prompt': '올바른 식을 고르세요',
                'question_type': 'MULTIPLE_CHOICE',
                'choices': options,
              };
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
            if (p.endsWith('/diagnostics/22')) {
              return {
                'id': 22,
                'status': 'IN_PROGRESS',
                'current_question': question,
              };
            }
            return {'items': []};
          },
          write: (m, p, b) async {
            bodies.add(Map<String, dynamic>.from(b as Map));
            return {
              'id': 22,
              'status': 'IN_PROGRESS',
              'answered_count': 1,
              'current_question': {
                'question_id': 'Q2',
                'prompt': '다음 식을 고르세요',
                'question_type': 'MULTIPLE_CHOICE',
                'choices': options,
              },
            };
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ConceptLevelTestDialog(concepts: const [], repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> tap(String label) async {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await tap('기초 문제로 진단하기');
        if (numeric) {
          await tester.enterText(find.byType(TextField), '3/2');
        } else {
          expect(find.byType(TextField), findsNothing);
          await tap('1) x² + 2x + 1');
        }
        await tap('답안 제출');
        expect(bodies.single, {
          'question_id': 'Q1',
          'answer': numeric ? '3/2' : '(x+1)^2',
        });
        expect(find.byType(TextField), findsNothing);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '답안 제출'))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
