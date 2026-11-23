import 'api.dart';

import 'package:flutter/foundation.dart';

typedef ApiRead = Future<dynamic> Function(
  String path,
  Map<String, String> query,
);
typedef ApiWrite = Future<dynamic> Function(
  String method,
  String path,
  Object? body,
);

class ServerPage {
  final List<JsonMap> items;
  final int page, totalPages;
  const ServerPage(this.items, this.page, this.totalPages);
  factory ServerPage.fromJson(JsonMap json) => ServerPage(
    LearningRepository.items(json),
    (json['page'] as num?)?.toInt() ?? 1,
    (json['total_pages'] as num?)?.toInt() ?? 1,
  );
}

class ServerProblem {
  final String? inputGuidance;
  final int id;
  final String code, question, type;
  final List<JsonMap> choices;
  const ServerProblem({
    required this.id,
    required this.code,
    required this.question,
    required this.type,
    this.choices = const [],
    this.inputGuidance,
  });
  factory ServerProblem.fromJson(JsonMap json) {
    if (json['id'] is! int || json['question'] is! String) {
      throw const FormatException('문제 정보가 올바르지 않습니다.');
    }
    final choices = json['choices'] ?? json['options'];
    return ServerProblem(
      id: json['id'],
      code: '${json['problem_code'] ?? ''}',
      question: json['question'],
      type: '${json['problem_type'] ?? 'SHORT_ANSWER'}',
      inputGuidance: json['input_guidance'] is String
          ? json['input_guidance']
          : null,
      choices: choices is List
          ? [
              for (int i = 0; i < choices.length; i++)
                choices[i] is Map
                    ? Map<String, dynamic>.from(choices[i])
                    : {'label': '${choices[i]}', 'value': '${i + 1}'},
            ]
          : [],
    );
  }
}

class LearningRepository {
  static final progressRevision = ValueNotifier<int>(0);
  static void notifyProgressChanged() => progressRevision.value++;
  final ApiRead read;
  final ApiWrite write;
  LearningRepository({ApiRead? read, ApiWrite? write})
    : read = read ?? ((path, query) => Api.get(path, queryParameters: query)),
      write =
          write ??
          ((method, path, body) => switch (method) {
            'PATCH' => Api.patch(path, body: body),
            _ => Api.post(path, body: body),
          });

  static JsonMap object(dynamic value) {
    if (value is! Map) throw const FormatException('서버 응답을 읽지 못했습니다.');
    return Map<String, dynamic>.from(value);
  }

  static List<JsonMap> items(JsonMap value, [String key = 'items']) {
    final list = value[key];
    if (list == null) return [];
    if (list is! List) throw const FormatException('목록 응답이 올바르지 않습니다.');
    return list.map(object).toList();
  }

  Future<JsonMap> get(
    String path, [
    Map<String, String> query = const {},
  ]) async => object(await read(path, query));
  Future<JsonMap> post(String path, [Object? body]) async =>
      object(await write('POST', path, body));
  Future<JsonMap> patch(String path, [Object? body]) async =>
      object(await write('PATCH', path, body));
  Future<ServerPage> page(
    String path, {
    int page = 1,
    Map<String, String> query = const {},
  }) async => ServerPage.fromJson(
    await get(path, {...query, 'page': '$page', 'size': '20'}),
  );
  Future<ServerProblem> problem(int id) async =>
      ServerProblem.fromJson(await get('/api/v1/problems/$id'));

  Future<List<JsonMap>> all(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final result = <JsonMap>[];
    int page = 1;
    while (true) {
      final data = await get(path, {...query, 'page': '$page', 'size': '100'});
      final rows = items(data);
      result.addAll(rows);
      if (rows.isEmpty || page >= (data['total_pages'] as num? ?? 1)) break;
      page++;
    }
    return result;
  }

  Future<int> startSession() async {
    final result = await post('/api/v1/learning-sessions');
    if (result['id'] is! int) throw const FormatException('학습 세션을 만들지 못했습니다.');
    return result['id'];
  }

  Future<JsonMap> submit({
    required int sessionId,
    required int problemId,
    required String answer,
    required int seconds,
    int hintCount = 0,
  }) {
    if (answer.trim().isEmpty) throw const FormatException('답안을 입력해 주세요.');
    return post('/api/v1/problem-attempts', {
      'session_id': sessionId,
      'problem_id': problemId,
      'student_answer': answer.trim(),
      'solve_time_seconds': seconds,
      'hint_count': hintCount,
    });
  }

  Future<void> finishSession(int id) async {
    await patch('/api/v1/learning-sessions/$id/finish');
  }
}

String learningError(Object error) {
  if (error is ApiException) {
    if (error.code == 'AI_CATALOG_NOT_READY') {
      return '이 문제의 학습 콘텐츠를 준비 중이에요. 잠시 후 다시 시도해 주세요.';
    }
    if (error.code == 'AI_NOT_CONFIGURED') {
      return 'AI 학습 지원이 아직 준비되지 않았어요. 잠시 후 다시 시도해 주세요.';
    }
    if (error.code == 'TUTOR_ANALYSIS_NOT_READY') {
      return '풀이 분석이 아직 끝나지 않았어요. 분석이 끝난 뒤 다시 시도해 주세요.';
    }
    if (error.code.startsWith('AI_')) {
      return 'AI 응답을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.';
    }
    if (error.statusCode == 401) return '로그인이 만료됐어요. 다시 로그인해 주세요.';
    if (error.statusCode == 403) return '이 계정에서 이용할 수 없는 기능이에요.';
    if (error.statusCode == 404) return '아직 준비된 학습 데이터가 없어요.';
    if (error.code == 'VARIANT_NOT_AVAILABLE') return '지금은 변형문제를 제공할 수 없어요.';
    if (error.statusCode == 422) return '입력 내용을 확인해 주세요.';
    return '요청을 완료하지 못했어요. 다시 시도해 주세요.';
  }
  if (error is FormatException) return error.message;
  return '서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.';
}
