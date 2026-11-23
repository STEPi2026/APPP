import 'api.dart';
import 'curriculum_graph.dart';
import 'learning_repository.dart';

/// Catalog identity and assessed knowledge must agree before showing a score.
/// Missing knowledge is unassessed, never a zero score or a completed Skill.
class StudentKnowledge {
  final CurriculumGraph graph;
  final Map<String, JsonMap> conceptStates, skillStates;
  StudentKnowledge._(this.graph, this.conceptStates, this.skillStates);

  static Future<StudentKnowledge> load(LearningRepository repo) async {
    final data = await Future.wait<dynamic>([
      CurriculumGraph.load(repo),
      repo.get('/api/v1/me/knowledge-map'),
    ]);
    final graph = data[0] as CurriculumGraph;
    final map = data[1] as JsonMap;
    if (map['nodes'] is! List) {
      throw const FormatException('개념별 학습 상태를 확인하지 못했어요.');
    }
    final concepts = <String, JsonMap>{}, skills = <String, JsonMap>{};
    for (final row in LearningRepository.items(map, 'nodes')) {
      final code = row['code'];
      if (code is! String) continue;
      if (row['type'] == 'CONCEPT' && graph.concepts.containsKey(code)) {
        concepts[code] = row;
      } else if (row['type'] == 'SKILL' && graph.skills.containsKey(code)) {
        skills[code] = row;
      }
    }
    return StudentKnowledge._(graph, concepts, skills);
  }

  List<JsonMap> get concepts => graph.concepts.values.toList();
  List<JsonMap> skillsFor(String concept) => [
    for (final code in graph.conceptSkills[concept] ?? <String>[])
      graph.skills[code]!,
  ];

  static double? score(JsonMap? state) {
    if (state == null || state['level'] == 'UNASSESSED') return null;
    final value = state['mastery_score'];
    return value is num && value.isFinite && value >= 0 && value <= 1
        ? value.toDouble()
        : null;
  }

  static String label(JsonMap? state) {
    final value = score(state);
    return value == null ? '아직 평가 전' : '숙련도 ${(value * 100).round()}%';
  }

  List<JsonMap> conceptsForSatellite(String id) => [
    for (final code in graph.conceptsForSatellite(id)) graph.concepts[code]!,
  ];
}
