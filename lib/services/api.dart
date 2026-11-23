import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef JsonMap = Map<String, dynamic>;

class Api {
  Api._();

  // 서버 주소가 변경되면 이 값을 변경하세요.
  // 실행 시 --dart-define=API_BASE_URL=... 을 지정하면 그 값이 우선합니다.
  static const String defaultDevBaseUrl =
      'https://frugally-unsubtle-luminous.ngrok-free.dev';

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');
  // Opt in only when a development/web host forwards /api/v1 to the backend.
  // The normal Android, iOS and localhost builds keep their configured URL.
  static const bool _sameOrigin = bool.fromEnvironment('API_SAME_ORIGIN');

  static String get baseUrl =>
      (_envBaseUrl.isNotEmpty ? _envBaseUrl : defaultDevBaseUrl).trim();

  static bool get isBackendConfigured => baseUrl.isNotEmpty;

  static const Duration _timeout = Duration(seconds: 20);

  // 기기 저장소 키 상수
  static const String _keyAccessToken = 'stepi_access_token';
  static const String _keyRefreshToken = 'stepi_refresh_token';

  // 메모리 및 기기 저장소 토큰 관리
  static String? _accessToken;
  static String? _refreshToken;

  static Future<bool>? _refreshFuture;

  static void Function()? onSessionExpired;
  static void Function()? onForbiddenRole;

  static bool get hasAccessToken =>
      _accessToken != null && _accessToken!.isNotEmpty;

  /// 앱 시작 시 기기에 저장된 토큰이 있는지 확인하고 불러옵니다.
  static Future<bool> initTokens() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final access = prefs.getString(_keyAccessToken);
      final refresh = prefs.getString(_keyRefreshToken);

      if (access != null && access.isNotEmpty) {
        _accessToken = access;
        _refreshToken = refresh;
        return true;
      }
    } catch (_) {}
    return false;
  }

  static void setAccessToken(String? token) {
    _accessToken = token;
    _persistTokens(accessToken: token);
  }

  static void setTokens({String? accessToken, String? refreshToken}) {
    _accessToken = accessToken;
    if (refreshToken != null) {
      _refreshToken = refreshToken;
    }
    _persistTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  static Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _persistTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  static Future<void> _persistTokens({
    String? accessToken,
    String? refreshToken,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (accessToken != null && accessToken.isNotEmpty) {
        await prefs.setString(_keyAccessToken, accessToken);
      }
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await prefs.setString(_keyRefreshToken, refreshToken);
      }
    } catch (_) {}
  }

  static Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyAccessToken);
      await prefs.remove(_keyRefreshToken);
    } catch (_) {}
  }

  // --------------------------------------------------
  // API 경로
  // --------------------------------------------------

  static const String loginEndpoint = '/api/v1/auth/login';
  static const String checkEmailEndpoint = '/api/v1/auth/check-email';
  static const String signupEndpoint = '/api/v1/auth/signup';
  static const String refreshEndpoint = '/api/v1/auth/refresh';
  static const String logoutEndpoint = '/api/v1/auth/logout';
  static const String passwordEndpoint = '/api/v1/auth/password';

  static const String passwordResetRequestEndpoint =
      '/api/v1/auth/password-reset/request';

  static const String passwordResetConfirmEndpoint =
      '/api/v1/auth/password-reset/confirm';

  static const String usersMeEndpoint = '/api/v1/users/me';
  static const String studentProfileEndpoint = '/api/v1/me/student-profile';

  static const String sessionsEndpoint = '/api/v1/learning-sessions';

  static const String capturedProblemsEndpoint = '/api/v1/captured-problems';

  static const String attemptsEndpoint = '/api/v1/problem-attempts';

  static const String ai1AnalyzeEndpoint = '/api/v1/captured-problems';

  // 기존 코드 호환용입니다.
  // 이 경로는 튜터 기록 조회용이며, 튜터 피드백 요청용이 아닙니다.
  static const String ai2TutorDecisionEndpoint = '/api/v1/me/tutor-history';

  static const String tutorFeedbackEndpoint = '/api/v1/tutor/feedback';

  static const String studentStatesEndpoint = '/api/v1/me/skill-states';

  static const String studentGamificationEndpoint = '/api/v1/me/gamification';

  static const String studentHistoryEndpoint = '/api/v1/me/learning-history';

  static const String curriculumGradesEndpoint = '/api/v1/curriculum/grades';

  static const String curriculumUnitsEndpoint = '/api/v1/curriculum/units';

  static const String curriculumGraphEndpoint = '/api/v1/curriculum/graph';

  static const String conceptsEndpoint = '/api/v1/concepts';
  static const String skillsEndpoint = '/api/v1/skills';
  static const String problemsEndpoint = '/api/v1/problems';

  static const String learningSummaryEndpoint = '/api/v1/me/learning-summary';

  static const String wrongAnswersEndpoint = '/api/v1/me/wrong-answers';

  static const String reviewQueueEndpoint = '/api/v1/me/review-queue';

  static const String knowledgeMapEndpoint = '/api/v1/me/knowledge-map';

  static const String knowledgeMapSummaryEndpoint =
      '/api/v1/me/knowledge-map/summary';

  static const String knowledgeMapHistoryEndpoint =
      '/api/v1/me/knowledge-map/history';

  static const String conceptStatesEndpoint = '/api/v1/me/concept-states';

  static const String weakSkillsEndpoint = '/api/v1/me/weak-skills';

  static const String xpHistoryEndpoint = '/api/v1/me/xp-history';

  static const String myBadgesEndpoint = '/api/v1/me/badges';
  static const String allBadgesEndpoint = '/api/v1/badges';

  static const String dailyQuestsEndpoint = '/api/v1/quests/daily';

  static const String myQuestsEndpoint = '/api/v1/me/quests';

  static const String achievementsEndpoint = '/api/v1/me/achievements';

  static const String learningContentsEndpoint = '/api/v1/learning-contents';

  static const String contentSessionsEndpoint =
      '/api/v1/content-learning-sessions';

  static const String contentRecommendationsEndpoint =
      '/api/v1/me/content-recommendations';

  static const String friendsEndpoint = '/api/v1/friends';

  static const String friendRequestsEndpoint = '/api/v1/friend-requests';

  static const String friendsLeaderboardEndpoint =
      '/api/v1/friends/leaderboard';

  static const String competitionSummaryEndpoint =
      '/api/v1/me/competition-summary';

  static const String blocksEndpoint = '/api/v1/me/blocks';

  static const String guardianLinkCodeEndpoint =
      '/api/v1/me/guardian-link-code';

  static const String guardianLinksEndpoint = '/api/v1/me/guardian-links';

  static const String joinClassEndpoint = '/api/v1/me/classes/join';

  static const String myClassesEndpoint = '/api/v1/me/classes';

  static String capturedProblemOcrPath(int id) =>
      '/api/v1/captured-problems/$id/ocr';

  static String capturedProblemAnalyzePath(int id) =>
      '/api/v1/captured-problems/$id/analyze';

  static String aiAnalysisDetailPath(int id) => '/api/v1/ai-analyses/$id';

  static String aiAnalysisRetryPath(int id) => '/api/v1/ai-analyses/$id/retry';

  static String tutorActionDetailPath(int id) => '/api/v1/tutor/actions/$id';

  static String tutorActionResponsePath(int id) =>
      '/api/v1/tutor/actions/$id/responses';

  // --------------------------------------------------
  // 로그인 / 회원가입 / 내 정보 / 로그아웃
  // --------------------------------------------------

  static Future<JsonMap> login({
    required String email,
    required String password,
  }) async {
    // post() 내부에서 로그인 응답의 토큰을 자동 저장합니다.
    final result = await post(
      loginEndpoint,
      body: {'email': email.trim(), 'password': password},
    );

    return _requireMap(result);
  }

  static Future<JsonMap> signup({
    required String email,
    required String password,
    required String name,
    String role = 'STUDENT',
    String? nickname,
  }) async {
    final result = await post(
      signupEndpoint,
      body: {
        'email': email.trim(),
        'password': password,
        'name': name,
        'role': role,
        'nickname': ?nickname,
      },
    );

    // 회원가입 응답에는 로그인 토큰이 없으므로
    // 가입 후 별도로 login()을 호출해야 합니다.
    return _requireMap(result);
  }

  static Future<JsonMap> getMe() async {
    final result = await get(usersMeEndpoint);
    return _requireMap(result);
  }

  static Future<void> logout() async {
    final refreshToken = _refreshToken;

    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await post(logoutEndpoint, body: {'refresh_token': refreshToken});
      }
    } finally {
      await clearTokens();
    }
  }

  static JsonMap _requireMap(dynamic data) {
    if (data is Map) {
      return JsonMap.from(data);
    }

    throw const ApiException(
      statusCode: 0,
      code: 'INVALID_RESPONSE',
      message: '서버 응답 형식이 올바르지 않습니다.',
    );
  }

  static void _saveLoginTokens(dynamic result) {
    final data = _requireMap(result);

    final accessToken = data['access_token'];
    final refreshToken = data['refresh_token'];

    if (accessToken is! String ||
        accessToken.isEmpty ||
        refreshToken is! String ||
        refreshToken.isEmpty) {
      throw const ApiException(
        statusCode: 0,
        code: 'INVALID_TOKEN_RESPONSE',
        message: '로그인 응답에 인증 토큰이 없습니다.',
      );
    }

    setTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  // --------------------------------------------------
  // URL / 헤더
  // --------------------------------------------------

  static Map<String, String> _makeHeaders({
    bool authenticated = true,
    bool jsonContent = true,
  }) {
    return {
      'Accept': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (jsonContent) 'Content-Type': 'application/json; charset=utf-8',
      if (authenticated && hasAccessToken)
        'Authorization': 'Bearer $_accessToken',
    };
  }

  static String _normalizePath(String path) {
    var endpoint = path.replaceFirst(RegExp(r'^/+'), '');

    if (endpoint != 'health' && !endpoint.startsWith('api/v1/')) {
      endpoint = 'api/v1/$endpoint';
    }

    return '/$endpoint';
  }

  static bool _isPublicAuthPath(String path) {
    final normalized = _normalizePath(path);

    return normalized == loginEndpoint ||
        normalized == signupEndpoint ||
        normalized == refreshEndpoint ||
        normalized == logoutEndpoint ||
        normalized == checkEmailEndpoint ||
        normalized == passwordResetRequestEndpoint ||
        normalized == passwordResetConfirmEndpoint;
  }

  static Uri _buildUri(String path, Map<String, String>? queryParameters) {
    if (!isBackendConfigured) {
      throw StateError(
        'Backend 주소가 설정되지 않았습니다. '
        'API_BASE_URL을 설정해 주세요.',
      );
    }

    // Accept either the server origin or the shared URL ending in /api/v1.
    // Endpoint constants already contain /api/v1, so include it only once.
    final base = baseUrl
        .replaceFirst(RegExp(r'/+$'), '')
        .replaceFirst(RegExp(r'/api/v1$'), '');
    final endpoint = _normalizePath(path);
    final uri = _sameOrigin
        ? Uri.base.replace(path: endpoint, query: '', fragment: '')
        : Uri.parse('$base$endpoint');

    if (!uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError('Backend 주소 형식이 올바르지 않습니다.');
    }

    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    return uri.replace(
      queryParameters: {...uri.queryParameters, ...queryParameters},
    );
  }

  // --------------------------------------------------
  // 공통 HTTP 요청
  // --------------------------------------------------

  static Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
    int? page,
    int? size,
  }) async {
    final mergedQuery = <String, String>{
      ...?queryParameters,
      if (page != null) 'page': page.toString(),
      if (size != null) 'size': size.toString(),
    };

    final authenticated = !_isPublicAuthPath(path);

    return _sendWithRetry(
      () => http
          .get(
            _buildUri(path, mergedQuery.isEmpty ? null : mergedQuery),
            headers: _makeHeaders(authenticated: authenticated),
          )
          .timeout(_timeout),
      authenticated: authenticated,
    );
  }

  static Future<dynamic> post(String path, {Object? body}) async {
    final authenticated = !_isPublicAuthPath(path);

    final result = await _sendWithRetry(
      () => http
          .post(
            _buildUri(path, null),
            headers: _makeHeaders(authenticated: authenticated),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout),
      authenticated: authenticated,
    );

    // 로그인 성공 시 응답의 토큰을 기기 저장소에 자동 저장합니다.
    if (_normalizePath(path) == loginEndpoint) {
      _saveLoginTokens(result);
    }

    return result;
  }

  static Future<dynamic> patch(String path, {Object? body}) async {
    final authenticated = !_isPublicAuthPath(path);

    return _sendWithRetry(
      () => http
          .patch(
            _buildUri(path, null),
            headers: _makeHeaders(authenticated: authenticated),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout),
      authenticated: authenticated,
    );
  }

  static Future<dynamic> delete(String path, {Object? body}) async {
    final authenticated = !_isPublicAuthPath(path);

    return _sendWithRetry(
      () => http
          .delete(
            _buildUri(path, null),
            headers: _makeHeaders(authenticated: authenticated),
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(_timeout),
      authenticated: authenticated,
    );
  }

  // --------------------------------------------------
  // 인증 오류 / 토큰 갱신
  // --------------------------------------------------

  static void _expireSession() {
    final hadSession = _accessToken != null || _refreshToken != null;

    clearTokens();

    if (hadSession) {
      onSessionExpired?.call();
    }
  }

  static Future<dynamic> _sendWithRetry(
    Future<http.Response> Function() requestFn, {
    bool authenticated = true,
    dynamic Function(http.Response)? decode,
  }) async {
    final sentAccessToken = _accessToken;
    final sentRefreshToken = _refreshToken;

    var response = await requestFn();

    if (authenticated && response.statusCode == 401) {
      final errorCode = _extractErrorCode(response);

      if (errorCode == 'AUTH_TOKEN_EXPIRED') {
        if (hasAccessToken && _accessToken != sentAccessToken) {
          response = await requestFn();
        } else if (_refreshToken != null && _refreshToken!.isNotEmpty) {
          final refreshed = await _tryRefreshTokenOnce();

          if (refreshed) {
            response = await requestFn();
          } else {
            if (_accessToken == sentAccessToken &&
                _refreshToken == sentRefreshToken) {
              _expireSession();
            }
          }
        } else {
          if (_accessToken == sentAccessToken &&
              _refreshToken == sentRefreshToken) {
            _expireSession();
          }
        }
      } else if (errorCode == 'AUTH_TOKEN_INVALID' ||
          errorCode == 'AUTH_REFRESH_EXPIRED' ||
          errorCode == 'AUTH_REFRESH_REVOKED') {
        if (_accessToken == sentAccessToken &&
            _refreshToken == sentRefreshToken) {
          _expireSession();
        }
      }

      if (response.statusCode == 401) {
        final finalCode = _extractErrorCode(response);

        if (finalCode == 'AUTH_TOKEN_INVALID' ||
            finalCode == 'AUTH_TOKEN_EXPIRED' ||
            finalCode == 'AUTH_REFRESH_EXPIRED' ||
            finalCode == 'AUTH_REFRESH_REVOKED') {
          if (_accessToken == sentAccessToken &&
              _refreshToken == sentRefreshToken) {
            _expireSession();
          }
        }
      }
    }

    if (authenticated && response.statusCode == 403) {
      final errorCode = _extractErrorCode(response);

      if (errorCode == 'AUTH_FORBIDDEN_ROLE') {
        onForbiddenRole?.call();
      }
    }

    return (decode ?? _handleResponse)(response);
  }

  static Future<Uint8List> getCapturedImage(int id) async {
    final result = await _sendWithRetry(
      () => http
          .get(
            _buildUri('/api/v1/captured-problems/$id/image', null),
            headers: {..._makeHeaders(jsonContent: false), 'Accept': 'image/*'},
          )
          .timeout(_timeout),
      decode: (response) {
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return _handleResponse(response);
        }
        if (!(response.headers['content-type'] ?? '').startsWith('image/')) {
          throw const FormatException('사진을 불러오지 못했어요.');
        }
        return response.bodyBytes;
      },
    );
    return result as Uint8List;
  }

  static Future<bool> _tryRefreshTokenOnce() {
    final pending = _refreshFuture;

    if (pending != null) {
      return pending;
    }

    final future = _performTokenRefresh().whenComplete(() {
      _refreshFuture = null;
    });

    _refreshFuture = future;
    return future;
  }

  static Future<bool> _performTokenRefresh() async {
    final token = _refreshToken;

    if (token == null || token.isEmpty) {
      return false;
    }

    final response = await http
        .post(
          _buildUri(refreshEndpoint, null),
          headers: _makeHeaders(authenticated: false),
          body: jsonEncode({'refresh_token': token}),
        )
        .timeout(_timeout);

    if (response.statusCode == 401) {
      return false;
    }

    final data = _requireMap(_handleResponse(response));

    final newAccess = data['access_token'];
    final newRefresh = data['refresh_token'];

    if (newAccess is! String ||
        newAccess.isEmpty ||
        newRefresh is! String ||
        newRefresh.isEmpty) {
      throw const ApiException(
        statusCode: 0,
        code: 'INVALID_TOKEN_RESPONSE',
        message: '토큰 갱신 응답 형식이 올바르지 않습니다.',
      );
    }

    if (_refreshToken != token) {
      return hasAccessToken;
    }

    setTokens(accessToken: newAccess, refreshToken: newRefresh);

    return true;
  }

  // --------------------------------------------------
  // 사진 문제 업로드 / OCR / 분석
  // --------------------------------------------------

  static Future<JsonMap?> uploadCapturedProblem({
    required Uint8List imageBytes,
    String filename = 'problem_solution.jpg',
    int? sessionId,
  }) async {
    if (!isBackendConfigured) return null;

    Future<http.Response> sendMultipart() {
      return (() async {
        final request = http.MultipartRequest(
          'POST',
          _buildUri(capturedProblemsEndpoint, null),
        );

        // MultipartRequest sets its own Content-Type and boundary.
        request.headers.addAll(_makeHeaders(jsonContent: false));
        if (sessionId != null) request.fields['session_id'] = '$sessionId';

        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: filename,
            contentType: MediaType(
              'image',
              filename.toLowerCase().endsWith('.png') ? 'png' : 'jpeg',
            ),
          ),
        );

        final streamed = await request.send();
        return await http.Response.fromStream(streamed);
      })().timeout(_timeout);
    }

    final result = await _sendWithRetry(sendMultipart);

    return result is Map ? JsonMap.from(result) : null;
  }

  static Future<JsonMap?> updateCapturedProblemOcr({
    required int capturedProblemId,
    required String problemText,
    String? solutionText,
  }) async {
    if (!isBackendConfigured) return null;

    final result = await patch(
      capturedProblemOcrPath(capturedProblemId),
      body: {'problem_text': problemText, 'solution_text': ?solutionText},
    );

    return result is Map ? JsonMap.from(result) : null;
  }

  static Future<JsonMap?> analyzeCapturedProblem({
    required int capturedProblemId,
    required List<String> skillCodes,
  }) async {
    if (!isBackendConfigured) return null;

    final result = await post(
      capturedProblemAnalyzePath(capturedProblemId),
      body: {'skill_codes': skillCodes},
    );

    return result is Map ? JsonMap.from(result) : null;
  }

  // --------------------------------------------------
  // 기존 학습 관련 함수 호환
  // --------------------------------------------------

  static Future<JsonMap?> submitAndAnalyzeSolution({
    required String problemCode,
    required int solveTimeSeconds,
    required int hintCount,
    String? studentAnswer,
    String? solutionImageUrl,
    int? capturedProblemId,
    List<String>? skillCodes,
  }) async {
    if (!isBackendConfigured) return null;

    if (capturedProblemId != null) {
      return analyzeCapturedProblem(
        capturedProblemId: capturedProblemId,
        skillCodes: (skillCodes != null && skillCodes.isNotEmpty)
            ? skillCodes
            : ['SKL-1-001'],
      );
    }

    final result = await post(
      attemptsEndpoint,
      body: {
        'problem_code': problemCode,
        'student_answer': studentAnswer,
        'solution_image_url': solutionImageUrl,
        'solve_time_seconds': solveTimeSeconds,
        'hint_count': hintCount,
      },
    );

    return result is Map ? JsonMap.from(result) : null;
  }

  static Future<JsonMap?> requestTutorAction({
    required String problemCode,
    required String actionType,
    int? attemptId,
    int? aiAnalysisId,
    int? firstErrorStep,
    String? misconceptionCode,
    String? studentMessage,
    int hintCount = 1,
  }) async {
    if (!isBackendConfigured) return null;

    final result = await post(
      ai2TutorDecisionEndpoint,
      body: {
        'problem_code': problemCode,
        'action_type': actionType,
        'attempt_id': attemptId,
        'ai_analysis_id': aiAnalysisId,
        'first_error_step': firstErrorStep,
        'misconception_code': misconceptionCode,
        'student_message': studentMessage,
        'hint_count': hintCount,
      },
    );

    return result is Map ? JsonMap.from(result) : null;
  }

  static Future<JsonMap?> recordLearningEvent({
    required String eventType,
    required String problemCode,
    JsonMap? metadata,
  }) async {
    if (!isBackendConfigured) return null;

    final result = await post(
      attemptsEndpoint,
      body: {
        'event_type': eventType,
        'problem_code': problemCode,
        'metadata': metadata ?? const <String, dynamic>{},
      },
    );

    return result is Map ? JsonMap.from(result) : null;
  }

  // --------------------------------------------------
  // 응답 처리
  // --------------------------------------------------

  static String? _extractErrorCode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is Map) {
        final code = decoded['code'];
        return code is String ? code : null;
      }
    } catch (_) {}

    return null;
  }

  static dynamic _handleResponse(http.Response response) {
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String code = 'UNKNOWN_ERROR';
      String message = text.isEmpty ? 'API 요청에 실패했습니다.' : text;

      dynamic details;

      if (text.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(text);

          if (decoded is Map) {
            final responseCode = decoded['code'];
            final responseMessage = decoded['message'];

            if (responseCode is String) {
              code = responseCode;
            }

            message =
                responseMessage?.toString() ??
                decoded['detail']?.toString() ??
                message;

            details = decoded['details'] ?? decoded['detail'];
          }
        } catch (_) {}
      }

      throw ApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
        details: details,
      );
    }

    if (text.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(text);
    } on FormatException {
      throw ApiException(
        statusCode: response.statusCode,
        code: 'INVALID_JSON',
        message: '서버 응답이 올바른 JSON 형식이 아닙니다.',
      );
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;
  final dynamic details;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.code = 'UNKNOWN_ERROR',
    this.details,
  });

  @override
  String toString() {
    return 'ApiException($statusCode, $code): $message';
  }
}
