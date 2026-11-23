import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/services/concept_check.dart';
import 'package:stepi/services/curriculum_graph.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/screens/concept_level_test_dialog.dart';

final concepts = [
  {'code': 'STP-1-001', 'name': '다항식의 덧셈과 뺄셈'},
  {'code': 'STP-1-006', 'name': '나머지정리'},
  {'code': 'STP-2-014', 'name': '절댓값을 포함한 일차부등식'},
];
final skills = [
  {'code': 'SKL-1-001', 'name': '기초 개념', 'concept_code': 'STP-1-001'},
  {'code': 'SKL-1-002', 'name': '중간 개념', 'concept_code': 'STP-1-001'},
  {'code': 'SKL-1-014', 'name': '나머지정리 적용', 'concept_code': 'STP-1-006'},
];
Map<String, dynamic> edge(String source, String target, String type) => {
  'source': source,
  'target': target,
  'type': type,
};
Map<String, dynamic> graph({bool cycle = false}) => {
  'edges': [
    edge('concept:STP-1-001', 'skill:SKL-1-001', 'CONCEPT_SKILL'),
    edge('concept:STP-1-001', 'skill:SKL-1-002', 'CONCEPT_SKILL'),
    edge('concept:STP-1-006', 'skill:SKL-1-014', 'CONCEPT_SKILL'),
    edge('skill:SKL-1-001', 'skill:SKL-1-002', 'SKILL_PREREQUISITE'),
    edge('skill:SKL-1-001', 'skill:SKL-1-014', 'SKILL_PREREQUISITE'),
    edge('skill:SKL-1-002', 'skill:SKL-1-014', 'SKILL_PREREQUISITE'),
    if (cycle) edge('skill:SKL-1-014', 'skill:SKL-1-001', 'SKILL_PREREQUISITE'),
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('traces real ancestors before target, deduplicates shared branches', () {
    final catalog = CurriculumGraph.fromJson(concepts, skills, graph());
    expect(catalog.pathTo('STP-1-006'), [
      'SKL-1-001',
      'SKL-1-002',
      'SKL-1-014',
    ]);
    expect(catalog.checklist('STP-1-006').last.skillCode, 'SKL-1-014');
    expect(catalog.pathTo('PRB-1-006'), isEmpty);
    expect(catalog.conceptsForSatellite('sat_m3_quad'), isEmpty);
    expect(catalog.conceptsForSatellite('sat_poly'), [
      'STP-1-001',
      'STP-1-006',
    ]);
  });
  test('rejects cycles instead of producing a fabricated order', () {
    final catalog = CurriculumGraph.fromJson(
      concepts,
      skills,
      graph(cycle: true),
    );
    expect(() => catalog.pathTo('STP-1-006'), throwsFormatException);
  });
  test('rejects conflicting graph and catalog concept membership', () {
    final data = graph();
    (data['edges'] as List).add(
      edge('concept:STP-2-014', 'skill:SKL-1-014', 'CONCEPT_SKILL'),
    );
    final catalog = CurriculumGraph.fromJson(concepts, skills, data);
    expect(catalog.pathTo('STP-2-014'), isEmpty);
  });
  testWidgets(
    'current unit scopes checklist to canonical prerequisite skills and restores selection',
    (tester) async {
      final writes = <String>[];
      final repo = LearningRepository(
        read: (path, query) async {
          if (path == '/api/v1/users/me') return {'id': 9};
          if (path == '/api/v1/concepts') return {'items': concepts};
          if (path == '/api/v1/skills') return {'items': skills};
          if (path == '/api/v1/curriculum/graph') return graph();
          if (path == '/api/v1/me/skill-states') {
            return {
              'items': [
                {'skill_code': 'SKL-1-014', 'mastery_score': 0.72},
              ],
            };
          }
          throw StateError(path);
        },
        write: (method, path, body) async {
          writes.add(path);
          return {};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConceptLevelTestDialog(
            concepts: const [],
            repository: repo,
            satelliteId: 'sat_poly',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('개념 자가 체크'));
      await tester.tap(find.text('개념 자가 체크'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('나머지정리').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('배웠던 개념 체크하기'));
      await tester.tap(find.text('배웠던 개념 체크하기'));
      await tester.pumpAndSettle();
      expect(find.text('기초 개념'), findsOneWidget);
      expect(find.text('1 / 3 개념'), findsOneWidget);
      await tester.tap(find.text('모르겠어요'));
      await tester.pumpAndSettle();
      final saved = await ConceptCheckStore().load(9);
      expect(saved.targetConceptCode, 'STP-1-006');
      expect(saved.answers, {
        'change_and_relations:server:SKL-1-001': 'unknown',
      });
      expect(writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: ConceptLevelTestDialog(concepts: const [], repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('개념 자가 체크'));
      await tester.tap(find.text('개념 자가 체크'));
      await tester.pumpAndSettle();
      expect(find.text('나머지정리'), findsOneWidget);
      expect(find.text('개념 체크 이어하기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
