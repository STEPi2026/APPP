import 'api.dart';

class TutorHelpResult {
  final Map<String, dynamic> actionData;
  final int actionId;
  final int? hintLevel;
  final String actionType, message;
  final String? explanation,
      example,
      checkQuestion,
      nextStage,
      nextStep,
      nextAction,
      nextSkillCode;
  const TutorHelpResult({
    required this.actionId,
    required this.actionType,
    required this.message,
    this.hintLevel,
    this.explanation,
    this.example,
    this.checkQuestion,
    this.nextStage,
    this.nextStep,
    this.nextAction,
    this.nextSkillCode,
    this.actionData = const {},
  });

  factory TutorHelpResult.fromJson(Map<String, dynamic> json) {
    final content = json['content'];
    if (json['tutor_action_id'] is! int ||
        json['action_type'] is! String ||
        content is! Map ||
        content['message'] is! String) {
      throw const FormatException('Invalid tutor help response');
    }
    String? value(dynamic v) => v is String && v.trim().isNotEmpty ? v : null;
    return TutorHelpResult(
      actionId: json['tutor_action_id'],
      actionType: json['action_type'],
      message: content['message'],
      hintLevel:
          content['hint_level'] is int &&
              content['hint_level'] >= 1 &&
              content['hint_level'] <= 3
          ? content['hint_level'] as int
          : null,
      explanation: value(content['explanation']),
      example: value(content['example']),
      checkQuestion: value(content['check_question']),
      nextStage: value(json['next_stage']),
      nextStep: value(json['next_step']),
      nextAction: value(json['next_action']),
      nextSkillCode: value(json['next_skill_code']),
      actionData: Map.unmodifiable(json),
    );
  }
}

typedef HelpRequest = Future<TutorHelpResult> Function({
  String? stage,
  String? skillCode,
});
typedef HelpReaction = Future<void> Function(int actionId, String reaction);

class TutorHelpService {
  final int? problemId;
  final String? problemCode;
  final Future<dynamic> Function(String path, Map<String, String> query) get;
  final Future<dynamic> Function(String path, Map<String, dynamic> body) post;
  int? _resolvedId;

  TutorHelpService({
    this.problemId,
    this.problemCode,
    Future<dynamic> Function(String, Map<String, String>)? get,
    Future<dynamic> Function(String, Map<String, dynamic>)? post,
  }) : get = get ?? ((path, query) => Api.get(path, queryParameters: query)),
       post = post ?? ((path, body) => Api.post(path, body: body));

  Future<int> _resolveId() async {
    if (_resolvedId != null) return _resolvedId!;
    if (problemId != null && problemId! > 0) return _resolvedId = problemId!;
    if (problemCode == null || problemCode!.isEmpty) {
      throw const ApiException(
        statusCode: 404,
        code: 'LOCAL_PROBLEM_ONLY',
        message: 'No server problem identifier',
      );
    }
    int page = 1;
    while (true) {
      final response = await get(Api.problemsEndpoint, {
        'page': '$page',
        'size': '100',
      });
      if (response is! Map ||
          response['items'] is! List ||
          response['total_pages'] is! int) {
        throw const FormatException('Invalid problem list');
      }
      for (final item in response['items']) {
        if (item is Map &&
            item['problem_code'] == problemCode &&
            item['id'] is int &&
            item['id'] > 0) {
          return _resolvedId = item['id'];
        }
      }
      if (page >= response['total_pages'] ||
          (response['items'] as List).isEmpty) {
        break;
      }
      page++;
    }
    throw const ApiException(
      statusCode: 404,
      code: 'PROBLEM_NOT_FOUND',
      message: 'Problem code not found',
    );
  }

  Future<TutorHelpResult> request({String? stage, String? skillCode}) async {
    final id = await _resolveId();
    final response = await post('/api/v1/tutor/help', {
      'problem_id': id,
      'stage': ?stage,
      'skill_code': ?skillCode,
    });
    if (response is! Map) throw const FormatException('Invalid tutor response');
    return TutorHelpResult.fromJson(Map<String, dynamic>.from(response));
  }

  Future<void> react(int actionId, String reaction) async {
    await post('/api/v1/tutor/actions/$actionId/responses', {
      'reaction': reaction,
    });
  }
}
