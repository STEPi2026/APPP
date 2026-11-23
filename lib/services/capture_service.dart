import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'learning_repository.dart';

class CapturePhoto {
  final Uint8List bytes;
  final String filename;
  CapturePhoto(Uint8List source)
    : bytes = Uint8List.fromList(source),
      filename = _filename(source);
  static String _filename(Uint8List bytes) {
    if (bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('사진은 10MB 이하로 선택해 주세요.');
    }
    const png = [137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length >= 8 &&
        List.generate(8, (i) => bytes[i] == png[i]).every((v) => v)) {
      return 'solution.png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      return 'solution.jpg';
    }
    throw const FormatException('JPG 또는 PNG 사진을 선택해 주세요.');
  }
}

typedef CapturePicker = Future<CapturePhoto?> Function(ImageSource source);
typedef CaptureUpload = Future<JsonMap> Function(
  CapturePhoto photo,
  int? sessionId,
);

class CaptureService {
  // Current deployed AI① contract; expand only after Backend confirms support.
  static bool supportsSkills(List<String> skills) =>
      skills.isNotEmpty && skills.every((code) => code == 'SKL-1-004');
  final LearningRepository repository;
  final CapturePicker picker;
  final CaptureUpload uploader;
  CaptureService({
    LearningRepository? repository,
    CapturePicker? picker,
    CaptureUpload? uploader,
  }) : repository = repository ?? LearningRepository(),
       picker = picker ?? _pick,
       uploader = uploader ?? _upload;

  static Future<CapturePhoto?> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
    );
    return file == null ? null : CapturePhoto(await file.readAsBytes());
  }

  static Future<JsonMap> _upload(CapturePhoto photo, int? sessionId) async =>
      LearningRepository.object(
        await Api.uploadCapturedProblem(
          imageBytes: photo.bytes,
          filename: photo.filename,
          sessionId: sessionId,
        ),
      );

  Future<JsonMap> upload(CapturePhoto photo, {int? sessionId}) async {
    final result = await uploader(photo, sessionId);
    if (result['id'] is! int ||
        result['id'] <= 0 ||
        result['session_id'] is! int ||
        result['session_id'] <= 0) {
      throw const FormatException('사진 저장 정보를 확인하지 못했어요.');
    }
    return result;
  }

  Future<JsonMap> analyze({
    required int captureId,
    required String problem,
    required String solution,
    required List<String> skills,
    int? retryAnalysisId,
  }) async {
    if (!supportsSkills(skills)) {
      throw const FormatException('이 개념의 사진 분석은 아직 준비 중이에요.');
    }
    if (problem.trim().isEmpty ||
        solution.trim().isEmpty ||
        skills.isEmpty ||
        skills.length > 5) {
      throw const FormatException('문제와 풀이 내용, 분석할 개념을 확인해 주세요.');
    }
    if (problem.length > 5000 || solution.length > 10000) {
      throw const FormatException('문제는 5,000자, 풀이 내용은 10,000자 이내로 입력해 주세요.');
    }
    // Corrections create a new attempt; retry reuses the accepted input.
    if (retryAnalysisId == null) {
      await repository.patch('/api/v1/captured-problems/$captureId/ocr', {
        'problem_text': problem.trim(),
        'problem_latex': null,
        'solution_text': solution.trim(),
      });
    }
    return validateAnalysis(
      await repository.post(
        retryAnalysisId == null
            ? '/api/v1/captured-problems/$captureId/analyze'
            : '/api/v1/ai-analyses/$retryAnalysisId/retry',
        retryAnalysisId == null ? {'skill_codes': skills} : null,
      ),
    );
  }

  Future<JsonMap> correctOcr({
    required int captureId,
    required int sessionId,
    required String problem,
    required String solution,
  }) async {
    if (problem.trim().isEmpty && solution.trim().isEmpty) {
      throw const FormatException('수정할 문제나 풀이 내용을 먼저 확인해 주세요.');
    }
    if (problem.length > 5000 || solution.length > 10000) {
      throw const FormatException('문제는 5,000자, 풀이 내용은 10,000자 이내로 입력해 주세요.');
    }
    final result = await repository.patch(
      '/api/v1/captured-problems/$captureId/ocr',
      {
        'problem_text': problem.trim(),
        // Plain-text correction replaces any previously saved formula draft.
        'problem_latex': null,
        'solution_text': solution.trim(),
      },
    );
    if (result['id'] != captureId || result['session_id'] != sessionId) {
      throw const FormatException('수정한 사진 정보가 요청한 사진과 일치하지 않아요.');
    }
    return result;
  }

  Future<JsonMap> analysis(int id) async {
    final result = validateAnalysis(
      await repository.get('/api/v1/ai-analyses/$id'),
    );
    if (result['id'] != id) throw const FormatException('요청한 분석 결과와 응답이 다릅니다.');
    return result;
  }

  static JsonMap validateAnalysis(JsonMap result) {
    if (result['final_answer_present'] != null &&
        result['final_answer_present'] is! bool) {
      throw const FormatException('최종 답 확인 값을 읽지 못했어요.');
    }
    if (result['is_correct'] != null && result['is_correct'] is! bool) {
      throw const FormatException('분석 판정 값을 확인하지 못했어요.');
    }
    if (result['id'] is! int ||
        result['id'] <= 0 ||
        ![
          'PENDING',
          'PROCESSING',
          'QUEUED',
          'ANALYZED',
          'REVIEW_REQUIRED',
          'UNKNOWN',
          'FAILED',
        ].contains(result['status'])) {
      throw const FormatException('분석 응답을 확인하지 못했어요.');
    }
    return result;
  }

  static bool pending(JsonMap? result) =>
      ['PENDING', 'PROCESSING', 'QUEUED'].contains(result?['status']);

  static bool isPartial(JsonMap? result) =>
      result?['status'] == 'ANALYZED' &&
      result?['is_correct'] == null &&
      result?['final_answer_present'] == false;

  static String assessmentLabel(JsonMap? result) {
    if (result == null) return '분석 전';
    if (pending(result)) return '분석 중';
    if (result['status'] == 'UNKNOWN') return '풀이를 인식하지 못했어요';
    if (result['status'] == 'FAILED') return '분석에 실패했어요';
    if (result['status'] != 'ANALYZED') return '판정 보류';
    if (result['is_correct'] == true) return '정답';
    if (result['is_correct'] == false) return '오답';
    return isPartial(result) ? '풀이가 끝나지 않았어요' : '판정 보류';
  }
}

String captureError(Object error) {
  if (error is PlatformException) {
    return '카메라나 사진 접근 권한을 확인해 주세요. 사진 선택으로도 올릴 수 있어요.';
  }
  if (error is ApiException) {
    if (error.code == 'PROBLEM_TYPE_NOT_SUPPORTED') {
      return '아직 지원하지 않는 문제 유형이에요. 다른 문제를 이용해 주세요.';
    }
    if (error.statusCode == 502 ||
        error.statusCode == 503 ||
        error.code.startsWith('AI_')) {
      return '지금은 사진 분석을 이용할 수 없어요. 사진과 입력 내용은 유지되니 잠시 후 다시 시도해 주세요.';
    }
    if (error.statusCode == 413) return '사진은 10MB 이하로 선택해 주세요.';
    if (error.statusCode == 415) return 'JPG 또는 PNG 사진을 선택해 주세요.';
  }
  return learningError(error);
}
