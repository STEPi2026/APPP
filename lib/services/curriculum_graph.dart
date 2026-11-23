import 'api.dart';
import 'concept_check.dart';
import 'learning_repository.dart';

/// Uses canonical server identifiers only. Display codes in the old map are
/// deliberately not used: several of them refer to different server concepts.
class CurriculumGraph {
  final Map<String, JsonMap> concepts, skills;
  final Map<String, List<String>> conceptSkills, prerequisites;
  CurriculumGraph._(
    this.concepts,
    this.skills,
    this.conceptSkills,
    this.prerequisites,
  );

  static Future<CurriculumGraph> load(LearningRepository repo) async {
    final data = await Future.wait([
      repo.all('/api/v1/concepts'),
      repo.all('/api/v1/skills'),
      repo.get('/api/v1/curriculum/graph'),
    ]);
    return CurriculumGraph.fromJson(
      data[0] as List<JsonMap>,
      data[1] as List<JsonMap>,
      data[2] as JsonMap,
    );
  }

  factory CurriculumGraph.fromJson(
    List<JsonMap> conceptRows,
    List<JsonMap> skillRows,
    JsonMap graph,
  ) {
    final concepts = <String, JsonMap>{}, skills = <String, JsonMap>{};
    for (final row in conceptRows) {
      if (row['code'] is String) concepts[row['code']] = row;
    }
    for (final row in skillRows) {
      if (row['code'] is String) skills[row['code']] = row;
    }
    if (concepts.isEmpty || skills.isEmpty || graph['edges'] is! List) {
      throw const FormatException('단원 연결 정보를 확인하지 못했어요.');
    }
    final children = <String, List<String>>{},
        parents = <String, List<String>>{};
    for (final edge in LearningRepository.items(graph, 'edges')) {
      final source = '${edge['source']}', target = '${edge['target']}';
      if (edge['type'] == 'CONCEPT_SKILL' &&
          source.startsWith('concept:') &&
          target.startsWith('skill:')) {
        final c = source.substring(8), s = target.substring(6);
        // Both catalog and graph must agree on concept membership.
        if (concepts.containsKey(c) && skills[s]?['concept_code'] == c) {
          final list = children.putIfAbsent(c, () => []);
          if (!list.contains(s)) list.add(s);
        }
      } else if (edge['type'] == 'SKILL_PREREQUISITE' &&
          source.startsWith('skill:') &&
          target.startsWith('skill:')) {
        final p = source.substring(6), s = target.substring(6);
        if (skills.containsKey(p) && skills.containsKey(s)) {
          final list = parents.putIfAbsent(s, () => []);
          if (!list.contains(p)) list.add(p);
        }
      }
    }
    return CurriculumGraph._(concepts, skills, children, parents);
  }

  /// Prerequisites first, current concept last; shared ancestors appear once.
  /// A cycle is a catalog error, never a made-up learning order.
  List<String> pathTo(String conceptCode) {
    final result = <String>[], visiting = <String>{}, visited = <String>{};
    void visit(String skill) {
      if (visiting.contains(skill)) {
        throw const FormatException('선수개념 연결에 순환이 있어 확인이 필요해요.');
      }
      if (visited.contains(skill)) return;
      visiting.add(skill);
      for (final parent in prerequisites[skill] ?? <String>[]) {
        visit(parent);
      }
      visiting.remove(skill);
      visited.add(skill);
      result.add(skill);
    }

    for (final skill in conceptSkills[conceptCode] ?? <String>[]) {
      visit(skill);
    }
    return result;
  }

  List<ConceptCheckItem> checklist(String conceptCode) => [
    for (final code in pathTo(conceptCode))
      ConceptCheckItem(
        id: '${planetFor(code)}:server:$code',
        planetId: planetFor(code),
        area: '선수개념 탐사',
        unit: '${concepts[skills[code]!['concept_code']]?['name'] ?? ''}',
        title: '${skills[code]!['name']}',
        grade: 10,
        skillCode: code,
        conceptCode: '${skills[code]!['concept_code']}',
      ),
  ];

  static String planetFor(String skill) =>
      switch (skill.split('-').elementAtOrNull(1)) {
        '3' => 'data_and_probability',
        '4' => 'numbers_and_operations',
        _ => 'change_and_relations',
      };

  // Explicit map-to-catalog bindings, limited to concepts actually represented
  // by each local satellite. No PRB/STP/SKL suffix inference or fuzzy matching.
  List<String> conceptsForSatellite(String id) {
    final candidates = switch (id) {
      'sat_poly' => <String, String>{
        'STP-1-001': '다항식의 덧셈과 뺄셈',
        'STP-1-002': '다항식의 곱셈',
        'STP-1-005': '항등식',
        'STP-1-006': '나머지정리',
      },
      'sat_eq_ineq' => <String, String>{
        'STP-2-001': '복수수의 뜻',
        'STP-2-002': '복수수의 상등',
        'STP-2-005': '이차방정식의 근',
        'STP-2-006': '이차방정식의 판별식',
      },
      'sat_matrix' => <String, String>{
        'STP-4-001': '행렬의 뜻',
        'STP-4-002': '행렬의 표현',
      },
      'sat_perm_comb' => <String, String>{
        'STP-3-004': '순열의 뜻',
        'STP-3-005': '순열의 수',
        'STP-3-006': '조합의 뜻',
        'STP-3-007': '조합의 수',
      },
      _ => <String, String>{},
    };
    return [
      for (final entry in candidates.entries)
        if (concepts[entry.key]?['name'] == entry.value &&
            (conceptSkills[entry.key]?.isNotEmpty ?? false))
          entry.key,
    ];
  }
}
