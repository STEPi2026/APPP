import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stepi/screens/server_tabs.dart';
import 'package:stepi/screens/server_pathways.dart';

void main() {
  testWidgets(
    'prerequisite endpoint uses prerequisites field rather than items',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: ServerSkillDetail(code: 'SKL-2')),
          );
          await tester.pumpAndSettle();
          expect(find.text('선수 스킬 이름'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          final p = request.url.path;
          final data = p.endsWith('/prerequisites')
              ? {
                  'skill_code': 'SKL-2',
                  'prerequisites': [
                    {'code': 'SKL-1', 'name': '선수 스킬 이름'},
                  ],
                }
              : p.endsWith('/SKL-2')
              ? {'name': '현재 스킬', 'description': '설명'}
              : {'items': []};
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    },
  );
  testWidgets(
    'diagnostic resumes server question and posts answer then shows results',
    (tester) async {
      final writes = <Map<String, dynamic>>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: ServerDiagnosticScreen()),
          );
          await tester.pumpAndSettle();
          expect(find.text('진단 질문'), findsOneWidget);
          await tester.enterText(find.byType(TextField), '42');
          await tester.tap(find.text('답안 제출'));
          await tester.pumpAndSettle();
          expect(find.text('진단 완료!'), findsOneWidget);
          expect(writes.single, {'question_id': 'Q1', 'answer': '42'});
          expect(tester.takeException(), isNull);
        },
        () => MockClient((request) async {
          final p = request.url.path;
          dynamic data;
          if (request.method == 'POST') {
            writes.add(jsonDecode(request.body));
            data = {'id': 3, 'status': 'COMPLETED', 'answered_count': 1};
          } else if (p.endsWith('/me/diagnostics')) {
            data = {
              'items': [
                {'id': 3, 'status': 'IN_PROGRESS'},
              ],
            };
          } else if (p.endsWith('/results')) {
            data = {'assessed': [], 'weak_skill_codes': [], 'roadmap_id': 4};
          } else {
            data = {
              'id': 3,
              'status': 'IN_PROGRESS',
              'answered_count': 0,
              'current_question': {'question_id': 'Q1', 'prompt': '진단 질문'},
            };
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
    },
  );
}
