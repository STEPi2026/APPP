import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ConceptCheckItem {
  final String id, planetId, area, unit, title;
  final int grade;
  final String? skillCode, conceptCode;
  const ConceptCheckItem({
    required this.id,
    required this.planetId,
    required this.area,
    required this.unit,
    required this.title,
    required this.grade,
    this.skillCode,
    this.conceptCode,
  });
}

class ConceptCheckSnapshot {
  final int grade;
  final Map<String, String> answers;
  final String? targetConceptCode;
  const ConceptCheckSnapshot({
    this.grade = 10,
    this.answers = const {},
    this.targetConceptCode,
  });
  int count(String value, Iterable<ConceptCheckItem> items) =>
      items.where((i) => answers[i.id] == value).length;
}

class ConceptCheckStore {
  static String _key(int userId) => 'concept_self_check_v1_$userId';
  Future<ConceptCheckSnapshot> load(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return const ConceptCheckSnapshot();
    try {
      final data = jsonDecode(raw);
      final answers = <String, String>{};
      if (data is! Map) return const ConceptCheckSnapshot();
      if (data['answers'] is Map) {
        for (final entry in (data['answers'] as Map).entries) {
          if (entry.key is String &&
              ['known', 'unsure', 'unknown'].contains(entry.value)) {
            answers[entry.key] = entry.value;
          }
        }
      }
      final grade = data['grade'];
      return ConceptCheckSnapshot(
        grade: grade is int && grade >= 6 && grade <= 12 ? grade : 10,
        answers: answers,
        targetConceptCode: data['target_concept_code'] is String
            ? data['target_concept_code']
            : null,
      );
    } catch (_) {
      return const ConceptCheckSnapshot();
    }
  }

  Future<void> save(int userId, ConceptCheckSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _key(userId),
      jsonEncode({
        'grade': snapshot.grade,
        'answers': snapshot.answers,
        'target_concept_code': snapshot.targetConceptCode,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    if (!saved) throw StateError('개념 체크를 저장하지 못했어요.');
  }
}
