import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'learning_repository.dart';

class TutorTarget {
  final String scenario;
  final int? problemId, captureId, sessionId;
  final String? skillCode;
  const TutorTarget.recommended(int id, {this.sessionId})
    : scenario = 'RECOMMENDED',
      problemId = id,
      captureId = null,
      skillCode = null;
  const TutorTarget.photo(
    int id, {
    required bool withSolution,
    this.skillCode,
    this.sessionId,
  }) : scenario = withSolution ? 'PHOTO_SOLVED' : 'PROBLEM_ONLY',
       captureId = id,
       problemId = null;
  Map<String, dynamic> get body => {
    'scenario': scenario,
    'problem_id': ?problemId,
    'captured_problem_id': ?captureId,
    'skill_code': ?skillCode,
    'session_id': ?sessionId,
  };
}

class TutorSessionResult {
  final JsonMap data;
  const TutorSessionResult(this.data);
  String get status => data['status'] as String;
  String get message => data['message'] as String;
  String? get nextAction =>
      data['next_action'] is String ? data['next_action'] : null;
  bool get needsAnalysis => status == 'AI1_ANALYZE_REQUIRED';
  Map<dynamic, dynamic>? get nextProblem =>
      data['next_problem'] is Map ? data['next_problem'] as Map : null;
  Map<dynamic, dynamic>? get nextSkill =>
      data['next_skill'] is Map ? data['next_skill'] as Map : null;
  String? get skillCode =>
      data['skill'] is Map && data['skill']['skill_code'] is String
      ? data['skill']['skill_code']
      : null;

  factory TutorSessionResult.parse(
    JsonMap data,
    TutorTarget target,
    String action,
  ) {
    if (data['scenario'] != target.scenario ||
        data['action'] != action ||
        (target.problemId != null && data['problem_id'] != target.problemId) ||
        (target.captureId != null &&
            data['captured_problem_id'] != target.captureId) ||
        data['status'] is! String ||
        data['message'] is! String ||
        (data['answer_correct'] != null && data['answer_correct'] is! bool) ||
        (data['next_action'] != null && data['next_action'] is! String)) {
      throw const FormatException('학습 응답과 현재 문제 정보가 일치하지 않아요. 다시 확인해 주세요.');
    }
    return TutorSessionResult(Map.unmodifiable(data));
  }
}

/// A failed request retains its key. Reopening help shares this client with the
/// problem so a transport retry cannot create another attempt or hint event.
class TutorSessionService {
  final LearningRepository repository;
  final String Function() requestId;
  final _pending = <String, String>{};
  final _inFlight = <String, Future<TutorSessionResult>>{};
  TutorSessionService({required this.repository, String Function()? requestId})
    : requestId = requestId ?? _newId;
  static String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<TutorSessionResult> request(
    TutorTarget target,
    String action, {
    String? answer,
  }) {
    if (!const [
      'START',
      'CONCEPT',
      'HINT',
      'SHOW_SOLUTION',
      'GIVE_UP',
      'SKIP',
      'CHECK_ANSWER',
      'RELEARN',
      'VIDEOS',
      'ANALYZE_RESULT',
    ].contains(action)) {
      throw const FormatException('지원하지 않는 학습 요청이에요.');
    }
    if ((target.problemId ?? target.captureId ?? 0) <= 0 ||
        (target.scenario == 'PROBLEM_ONLY' &&
            (target.skillCode?.trim().isEmpty ?? true))) {
      throw const FormatException(
        '사진과 개념의 자동 연결을 준비하고 있어요. 연결된 문제에서 도움을 이용해 주세요.',
      );
    }
    if (action == 'CHECK_ANSWER' &&
        (answer == null ||
            answer.trim().isEmpty ||
            answer.trim().length > 200)) {
      throw const FormatException('답안은 1~200자로 입력해 주세요.');
    }
    final body = {
      ...target.body,
      'action': action,
      if (action == 'CHECK_ANSWER') 'answer': answer!.trim(),
    };
    final fingerprint = jsonEncode(body);
    return _inFlight.putIfAbsent(
      fingerprint,
      () => _send(target, action, body, fingerprint),
    );
  }

  Future<TutorSessionResult> _send(
    TutorTarget target,
    String action,
    JsonMap body,
    String fingerprint,
  ) async {
    final key = _pending.putIfAbsent(fingerprint, requestId);
    try {
      final result = TutorSessionResult.parse(
        await repository.post('/api/v1/tutor/session', {
          ...body,
          'request_id': key,
        }),
        target,
        action,
      );
      _pending.remove(fingerprint);
      if (result.data['attempt_id'] is int || result.data['rewards'] is Map) {
        LearningRepository.notifyProgressChanged();
      }
      return result;
    } on ApiException catch (error) {
      // Opt-in development evidence. Never log headers, tokens or credentials.
      if (const bool.fromEnvironment('TUTOR_TRACE')) {
        debugPrint(
          jsonEncode({
            'event': 'tutor_session_error',
            'time_utc': DateTime.now().toUtc().toIso8601String(),
            'request': {...body, 'request_id': key},
            'http_status': error.statusCode,
            'code': error.code,
          }),
        );
      }
      rethrow;
    } finally {
      _inFlight.remove(fingerprint);
    }
  }
}
