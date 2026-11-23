import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/practice_question.dart';
import '../models/learning_next_action.dart';
import '../models/math_display.dart';
import '../services/api.dart';
import '../services/capture_service.dart';
import '../services/learning_repository.dart';
import 'space_cartoon_painters.dart';
import 'learning_action_routes.dart';
import 'learning_next_action_notice.dart';
import '../services/tutor_session_service.dart';
import 'tutor_session_screen.dart';

/// Production photo flow, shared by the bottom camera button and a problem's
/// photo button. No sample image, fabricated error pin or local reward is used.
class CaptureLearningScreen extends StatefulWidget {
  final PracticeQuestion? problem;
  final int? sessionId;
  final CaptureService? service;
  final int? savedCaptureId;
  final CapturePhoto? savedPhoto;
  final Duration pollInterval;
  final int maxPolls;
  final bool returnAfterCorrection;
  const CaptureLearningScreen({
    super.key,
    this.problem,
    this.sessionId,
    this.service,
    this.savedCaptureId,
    this.savedPhoto,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 30,
    this.returnAfterCorrection = false,
  });
  @override
  State<CaptureLearningScreen> createState() => _CaptureLearningScreenState();
}

class _CaptureLearningScreenState extends State<CaptureLearningScreen> {
  static const purple = Color(0xFF7C5CFA),
      light = Color(0xFFF3EEFF),
      ink = Color(0xFF171717);
  late final service = widget.service ?? CaptureService();
  late final tutor = TutorSessionService(repository: service.repository);
  final problemText = TextEditingController(),
      solutionText = TextEditingController();
  final scroll = ScrollController();
  CapturePhoto? photo;
  JsonMap? capture, analysis;
  List<String> selectedSkills = [];
  String phase = 'pick';
  String? error;
  String? photoError;
  bool busy = false, polling = false, closing = false, allowExit = false;
  int? sessionId;
  int pollEpoch = 0;
  bool unsupported = false;
  bool correctingPartial = false;
  bool verifiedSavedAnalysis = false;
  String? analyzedCorrection;
  String? savedCorrection;
  bool get canAnalyze =>
      (widget.problem?.isServerProblem == true || verifiedSavedAnalysis) &&
      CaptureService.supportsSkills(selectedSkills);
  String get rawText => capture?['ocr_raw_text'] is String
      ? capture!['ocr_raw_text'] as String
      : '';
  String get correctionKey =>
      '${problemText.text.trim()}\u0000${solutionText.text.trim()}';

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _failure(Object e) {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      error = captureError(e);
      if (e is ApiException && e.code == 'PROBLEM_TYPE_NOT_SUPPORTED') {
        unsupported = true;
        phase = 'unsupported';
        pollEpoch++;
        polling = false;
      }
    });
    _scrollToTop();
  }

  @override
  void initState() {
    super.initState();
    sessionId = widget.sessionId;
    selectedSkills = (widget.problem?.skillCodes ?? [])
        .toSet()
        .take(5)
        .toList();
    problemText.text = widget.problem?.question ?? '';
    if (widget.savedCaptureId != null) _resume();
  }

  Future<void> _resume([int? captureId]) async {
    if (busy) return;
    final id = captureId ?? widget.savedCaptureId;
    setState(() {
      busy = true;
      error = null;
      phase = 'resuming';
    });
    try {
      final row = await service.repository.get('/api/v1/captured-problems/$id');
      if (row['id'] != id ||
          row['session_id'] is! int ||
          row['session_id'] <= 0) {
        throw const FormatException('저장된 사진 정보를 확인하지 못했어요.');
      }
      JsonMap? result;
      final latest = row['latest_analysis'];
      if (latest is Map && latest['id'] is int) {
        result = await service.analysis(latest['id']);
        if (result['captured_problem_id'] != row['id']) {
          throw const FormatException('사진과 분석 결과가 일치하지 않아요.');
        }
      }
      CapturePhoto? storedPhoto = widget.savedPhoto ?? photo;
      if (storedPhoto == null) {
        try {
          storedPhoto = CapturePhoto(await Api.getCapturedImage(row['id']));
        } catch (_) {
          photoError = '사진을 불러오지 못했어요. 인식된 원문과 입력 내용을 확인해 주세요.';
        }
      }
      if (!mounted) return;
      setState(() {
        _applyRecognition(row);
        photo = storedPhoto;
        analysis = result;
        final codes = result?['skill_codes'] ?? widget.problem?.skillCodes;
        selectedSkills = codes is List
            ? codes.whereType<String>().toSet().toList()
            : [];
        verifiedSavedAnalysis =
            result != null && CaptureService.supportsSkills(selectedSkills);
        analyzedCorrection = result == null ? null : correctionKey;
        correctingPartial = CaptureService.isPartial(result);
        phase = CaptureService.pending(result) ? 'result' : 'edit';
      });
    } catch (e) {
      if (mounted) {
        setState(() => phase = 'resume_failed');
        _failure(e);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    pollEpoch++;
    problemText.dispose();
    solutionText.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _applyRecognition(JsonMap result) {
    capture = result;
    sessionId = result['session_id'];
    final text = result['problem_text'] ?? result['problem_latex'];
    problemText.text = text is String ? text : '';
    solutionText.text = result['solution_text'] is String
        ? result['solution_text']
        : '';
    error = null;
    savedCorrection = null;
    final raw = result['ocr_raw_text'];
    final hasRaw = raw is String && raw.trim().isNotEmpty;
    if (['PENDING', 'PROCESSING', 'QUEUED'].contains(result['ocr_status'])) {
      phase = 'recognizing';
    } else if ([
          'UNAVAILABLE',
          'FAILED',
          'EMPTY',
          'UNREADABLE',
        ].contains(result['ocr_status']) ||
        (problemText.text.trim().isEmpty && !hasRaw)) {
      phase = 'recognition_failed';
    } else if (LearningNextAction.fromResponse(result) ==
        LearningNextAction.confirmInput) {
      phase = 'edit';
    } else if (selectedSkills.isEmpty) {
      phase = 'mapping_unavailable';
    } else if (!CaptureService.supportsSkills(selectedSkills)) {
      phase = 'analysis_unavailable';
    } else if (problemText.text.trim().isEmpty && hasRaw) {
      phase = 'raw_recognized';
    } else if (solutionText.text.trim().isEmpty) {
      phase = 'solution_missing';
    } else {
      phase = 'edit';
    }
  }

  Future<void> _refreshRecognition() async {
    if (capture == null || busy || closing) return;
    setState(() => busy = true);
    try {
      final id = capture!['id'];
      final result = await service.repository.get(
        '/api/v1/captured-problems/$id',
      );
      if (result['id'] != id || result['session_id'] != sessionId) {
        throw const FormatException('사진 인식 결과가 요청한 사진과 일치하지 않아요.');
      }
      if (mounted) setState(() => _applyRecognition(result));
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _waitForRecognition() async {
    final epoch = ++pollEpoch;
    setState(() => polling = true);
    try {
      for (var i = 0; i < widget.maxPolls; i++) {
        await Future<void>.delayed(widget.pollInterval);
        if (!mounted || epoch != pollEpoch || closing) return;
        final id = capture!['id'];
        final result = await service.repository.get(
          '/api/v1/captured-problems/$id',
        );
        if (!mounted || epoch != pollEpoch || closing) return;
        if (result['id'] != id || result['session_id'] != sessionId) {
          throw const FormatException('사진 인식 결과가 일치하지 않아요.');
        }
        setState(() => _applyRecognition(result));
        if (phase != 'recognizing') break;
      }
    } catch (e) {
      if (mounted && epoch == pollEpoch) _failure(e);
    } finally {
      if (mounted && epoch == pollEpoch) setState(() => polling = false);
    }
  }

  Future<void> _pick(ImageSource source) async {
    if (busy || closing) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await service.picker(source);
      if (!mounted || selected == null) return;
      setState(() {
        pollEpoch++;
        polling = false;
        photo = selected;
        capture = null;
        analysis = null;
        unsupported = false;
        correctingPartial = false;
        verifiedSavedAnalysis = false;
        analyzedCorrection = null;
        savedCorrection = null;
        phase = 'preview';
        problemText.text = widget.problem?.question ?? '';
        solutionText.clear();
      });
      _scrollToTop();
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _upload() async {
    if (photo == null || busy || closing) return;
    if (capture != null) {
      setState(() => _applyRecognition(capture!));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.upload(photo!, sessionId: sessionId);
      if (!mounted) return;
      setState(() => _applyRecognition(result));
      if (phase == 'recognizing' && widget.maxPolls > 0) _waitForRecognition();
      _scrollToTop();
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool get pending => CaptureService.pending(analysis);

  void _editRecognition() {
    if (busy || closing || capture == null || analysis != null) return;
    setState(() {
      // Only registered problems have a known prompt. Raw OCR is never split
      // into a problem and solution or classified by the client.
      if (problemText.text.trim().isEmpty && widget.problem != null) {
        problemText.text = widget.problem!.question;
      }
      error = null;
      phase = 'edit';
    });
    _scrollToTop();
  }

  Future<void> _saveCorrection() async {
    if (busy ||
        closing ||
        capture == null ||
        savedCorrection == correctionKey) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.correctOcr(
        captureId: capture!['id'],
        sessionId: sessionId!,
        problem: problemText.text,
        solution: solutionText.text,
      );
      if (!mounted) return;
      setState(() {
        capture = {...capture!, ...result};
        // Backend creates a new attempt when an analyzed capture is corrected.
        // Keep the supported Skill provenance, but never reuse the old result.
        if (analysis != null) {
          analysis = null;
          analyzedCorrection = null;
          correctingPartial = false;
        }
        savedCorrection = correctionKey;
      });
      LearningRepository.notifyProgressChanged();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('수정한 내용을 저장했어요.')));
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<JsonMap> _tutorAnalysis(String code) async {
    if (!CaptureService.supportsSkills([code])) {
      throw const FormatException('이 개념의 사진 분석은 아직 준비 중이에요.');
    }
    final row = await service.repository.get(
      '/api/v1/captured-problems/${capture!['id']}',
    );
    if (!mounted) throw const FormatException('학습 화면으로 돌아가 다시 확인해 주세요.');
    if (row['id'] != capture!['id'] || row['session_id'] != sessionId) {
      throw const FormatException('확인할 사진 정보가 일치하지 않아요.');
    }
    setState(() {
      final previous = correctionKey;
      problemText.text = row['problem_text'] is String
          ? row['problem_text']
          : row['problem_latex'] is String
          ? row['problem_latex']
          : '';
      solutionText.text = row['solution_text'] is String
          ? row['solution_text']
          : '';
      if (previous != correctionKey) {
        analysis = null;
        analyzedCorrection = null;
      }
      selectedSkills = [code];
      verifiedSavedAnalysis = true;
    });
    if (pending) {
      await _poll();
    } else if (analysis == null ||
        analysis!['status'] != 'ANALYZED' ||
        analyzedCorrection != correctionKey) {
      await _analyze(waitForCompletion: true);
    }
    if (analysis == null) {
      throw FormatException(error ?? '사진 분석을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
    return analysis!;
  }

  Future<void> _openTutor({String action = 'START'}) async {
    if (busy || closing || capture == null) return;
    if (savedCorrection != correctionKey && analyzedCorrection != correctionKey) {
      await _saveCorrection();
    }
    if (!mounted ||
        busy ||
        (savedCorrection != correctionKey &&
            analyzedCorrection != correctionKey)) {
      return;
    }
    final withSolution = solutionText.text.trim().isNotEmpty;
    final code = selectedSkills.length == 1 ? selectedSkills.single : null;
    if (!withSolution && code == null) {
      _failure(
        const FormatException(
          '문제만 찍은 사진의 개념 자동 연결을 준비하고 있어요. 연결된 앱 문제에서 도움을 이용해 주세요.',
        ),
      );
      return;
    }
    final id = capture!['id'] as int;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TutorSessionScreen(
          target: TutorTarget.photo(
            id,
            withSolution: withSolution,
            skillCode: code,
            sessionId: sessionId,
          ),
          service: tutor,
          problemTitle: widget.problem?.title ?? '촬영한 문제',
          initialAction: action,
          photo: photo,
          analyzePhoto: withSolution ? _tutorAnalysis : null,
        ),
      ),
    );
    if (mounted) {
      await _resume(id);
      if (mounted && analysis != null) setState(() => phase = 'result');
    }
  }

  bool get retryAllowed =>
      !unsupported &&
      (analysis == null ||
          CaptureService.isPartial(analysis) ||
          (analyzedCorrection != null && analyzedCorrection != correctionKey) ||
          ([
                'FAILED',
                'UNKNOWN',
                'REVIEW_REQUIRED',
              ].contains(analysis!['status']) &&
              (analysis!['retry_count'] is num
                      ? analysis!['retry_count'] as num
                      : 0) <
                  3));

  Future<void> _analyze({bool waitForCompletion = false}) async {
    if (busy ||
        closing ||
        capture == null ||
        pending ||
        !retryAllowed ||
        !canAnalyze) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.analyze(
        captureId: capture!['id'],
        problem: problemText.text,
        solution: solutionText.text,
        skills: selectedSkills,
        retryAnalysisId:
            correctingPartial || analyzedCorrection != correctionKey
            ? null
            : analysis?['id'],
      );
      if (!mounted) return;
      setState(() {
        analysis = result;
        analyzedCorrection = correctionKey;
        correctingPartial = false;
        phase = 'result';
      });
      _scrollToTop();
      if (pending) {
        if (waitForCompletion) {
          await _poll();
        } else {
          _poll();
        }
      } else {
        LearningRepository.notifyProgressChanged();
      }
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _poll() async {
    if (!mounted || analysis == null || !pending || widget.maxPolls <= 0) {
      return;
    }
    final epoch = ++pollEpoch;
    setState(() => polling = true);
    try {
      for (var i = 0; i < widget.maxPolls; i++) {
        await Future<void>.delayed(widget.pollInterval);
        if (!mounted || epoch != pollEpoch || closing) return;
        final result = await service.analysis(analysis!['id']);
        if (!mounted || epoch != pollEpoch || closing) return;
        setState(() => analysis = result);
        if (!pending) {
          LearningRepository.notifyProgressChanged();
          break;
        }
      }
    } catch (e) {
      if (mounted && epoch == pollEpoch) {
        _failure(e);
      }
    } finally {
      if (mounted && epoch == pollEpoch) setState(() => polling = false);
    }
  }

  Future<void> _refreshAnalysis() async {
    if (busy || polling || closing || analysis == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await service.analysis(analysis!['id']);
      if (!mounted) return;
      setState(() => analysis = result);
      if (pending) {
        _poll();
      } else {
        LearningRepository.notifyProgressChanged();
      }
    } catch (e) {
      _failure(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _close() async {
    if (busy || closing) return;
    pollEpoch++;
    setState(() {
      closing = true;
      polling = false;
    });
    try {
      // A supplied session belongs to the underlying problem screen.
      if (widget.savedCaptureId == null &&
          widget.sessionId == null &&
          sessionId != null) {
        await service.repository.finishSession(sessionId!);
      }
      if (!mounted) return;
      LearningRepository.notifyProgressChanged();
      setState(() {
        allowExit = true;
        closing = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          closing = false;
          error = '학습 종료를 저장하지 못했어요. 뒤로가기를 눌러 다시 시도해 주세요. ${captureError(e)}';
        });
      }
    }
  }

  Widget _card(Widget child, {Color color = light}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE6DFFF)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget _primary(String label, VoidCallback? action) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: FilledButton(
      onPressed: busy || closing ? null : action,
      style: FilledButton.styleFrom(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
  );

  void _importRaw(TextEditingController target, int limit) {
    if (busy || closing || target.text.isNotEmpty) return;
    if (rawText.length > limit) {
      _failure(FormatException('원문이 길어요. 필요한 부분만 선택해 복사해 주세요.'));
      return;
    }
    setState(() => target.text = rawText);
  }

  Widget _rawPreview({bool editable = false}) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '인식된 원문',
          style: TextStyle(color: purple, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        SelectableText(rawText, style: const TextStyle(height: 1.7)),
        if (editable) ...[
          const SizedBox(height: 10),
          const Text(
            '원문을 빈 칸에 가져온 뒤, 문제와 풀이에 해당하는 부분만 남겨 주세요. = 기호나 x가 잘못 읽히지 않았는지도 확인해요.',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: busy || closing || problemText.text.isNotEmpty
                    ? null
                    : () => _importRaw(problemText, 5000),
                child: const Text('문제 칸에 가져오기'),
              ),
              TextButton(
                onPressed: busy || closing || solutionText.text.isNotEmpty
                    ? null
                    : () => _importRaw(solutionText, 10000),
                child: const Text('풀이 칸에 가져오기'),
              ),
            ],
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dark = phase == 'pick';
    return PopScope(
      canPop: allowExit || (!busy && !closing && sessionId == null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: dark ? const Color(0xFF141414) : Colors.white,
        appBar: AppBar(
          backgroundColor: dark ? const Color(0xFF757575) : Colors.white,
          foregroundColor: ink,
          leading: IconButton(
            onPressed: busy || closing ? null : _close,
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
          ),
          title: Text(
            dark
                ? '공책 풀이 촬영'
                : phase == 'preview'
                ? '사진 확인'
                : phase == 'edit'
                ? '풀이 내용 확인'
                : phase == 'result' || phase == 'unsupported'
                ? '풀이 분석 결과'
                : '인식 내용 확인',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (busy || closing || polling)
                const LinearProgressIndicator(color: purple),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                      children: [
                        if (photoError != null) _card(Text(photoError!)),
                        if (error != null)
                          _card(
                            Text(
                              error!,
                              style: const TextStyle(
                                color: Color(0xFF9D3D4D),
                                height: 1.6,
                              ),
                            ),
                            color: const Color(0xFFFFF0F0),
                          ),
                        if (phase == 'resume_failed')
                          _primary('다시 불러오기', _resume),
                        if (dark) ...[
                          const SizedBox(height: 24),
                          AspectRatio(
                            aspectRatio: 1.15,
                            child: CustomPaint(
                              painter: _CaptureFramePainter(),
                              child: const Padding(
                                padding: EdgeInsets.all(30),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.white70,
                                      size: 64,
                                    ),
                                    SizedBox(height: 24),
                                    Text(
                                      '문제와 풀이가 함께 보이게\n사진을 촬영하거나 선택해 주세요.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 15,
                                        height: 1.7,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          _primary(
                            '카메라로 촬영하기',
                            () => _pick(ImageSource.camera),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => _pick(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('앨범에서 사진 선택'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ] else ...[
                          if (photo != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                color: const Color(0xFFF7F5FC),
                                child: Image.memory(
                                  photo!.bytes,
                                  height: phase == 'result' ? 190 : 260,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, error, stack) =>
                                      const SizedBox(
                                        height: 180,
                                        child: Center(
                                          child: Text('사진 미리보기를 불러오지 못했어요.'),
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
                          if (phase == 'preview') ...[
                            _card(
                              const Text(
                                '문제와 풀이가 잘 보이나요? 사진을 올린 뒤 인식된 내용을 확인해요.',
                                style: TextStyle(height: 1.6),
                              ),
                            ),
                            _primary('사진 올리고 내용 확인하기', _upload),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => _pick(ImageSource.camera),
                              child: const Text('다시 촬영하기'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => _pick(ImageSource.gallery),
                              child: const Text('다른 사진 선택하기'),
                            ),
                          ],
                          if ([
                            'recognizing',
                            'recognition_failed',
                            'mapping_unavailable',
                            'solution_missing',
                            'raw_recognized',
                            'analysis_unavailable',
                          ].contains(phase))
                            ..._recognitionNotice(),
                          if (phase == 'edit') ...[
                            if (rawText.trim().isNotEmpty)
                              _rawPreview(editable: true),
                            _card(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '인식된 내용을 확인해 주세요',
                                    style: TextStyle(
                                      color: purple,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '사진과 비교해 문제와 풀이를 확인해 주세요. 인식이 틀린 부분만 고칠 수 있어요.',
                                    style: TextStyle(height: 1.6),
                                  ),
                                  if (widget.problem != null)
                                    const Text(
                                      '앱에서 제공한 문제 내용과도 비교해 주세요.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.6,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            TextField(
                              controller: problemText,
                              key: const ValueKey('ocr-problem'),
                              onChanged: (_) => setState(() {}),
                              enabled: !busy && !closing,
                              minLines: 2,
                              maxLines: 6,
                              maxLength: 5000,
                              decoration: const InputDecoration(
                                labelText: '문제 내용',
                                helperText: mathInputGuide,
                                helperMaxLines: 2,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: solutionText,
                              key: const ValueKey('ocr-solution'),
                              onChanged: (_) => setState(() {}),
                              enabled: !busy && !closing,
                              minLines: 3,
                              maxLines: 8,
                              maxLength: 10000,
                              decoration: const InputDecoration(
                                labelText: '내 풀이 내용',
                                helperText: mathInputGuide,
                                helperMaxLines: 2,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _card(
                              Text(
                                canAnalyze ? '확인한 문제와 풀이를 연결된 개념으로 분석해요.' : '수정한 내용을 저장할 수 있어요. 이 사진의 풀이 분석은 아직 준비 중이에요.',
                                style: const TextStyle(color: purple),
                              ),
                            ),
                            _primary(
                              savedCorrection == correctionKey
                                  ? '수정 내용 저장됨'
                                  : '수정 내용 저장',
                              savedCorrection == correctionKey
                                  ? null
                                  : _saveCorrection,
                            ),
                            if (widget.returnAfterCorrection &&
                                savedCorrection == correctionKey)
                              _primary(
                                '확인 완료 · 학습으로 돌아가기',
                                () => Navigator.pop(context, true),
                              ),
                            if (!widget.returnAfterCorrection &&
                                problemText.text.trim().isNotEmpty)
                              _primary('AI와 학습 이어가기', () => _openTutor()),
                            if (!retryAllowed &&
                                canAnalyze &&
                                !widget.returnAfterCorrection)
                              Text(
                                analysis?['status'] == 'ANALYZED'
                                    ? '내용을 수정하면 새로 분석할 수 있어요.'
                                    : '분석 재시도 횟수를 모두 사용했어요. 내용을 수정하면 새 분석을 요청할 수 있어요.',
                                style: TextStyle(height: 1.6),
                              ),
                            if (retryAllowed &&
                                canAnalyze &&
                                !widget.returnAfterCorrection)
                              _primary(
                                correctingPartial
                                    ? '최종 답 포함해 분석하기'
                                    : analysis == null
                                    ? '확인하고 분석하기'
                                    : '수정한 내용으로 다시 분석하기',
                                _analyze,
                              ),
                          ],
                          if (phase == 'result' && analysis != null)
                            ..._resultWidgets(),
                          if (phase != 'preview')
                            OutlinedButton(
                              onPressed: busy || closing ? null : _close,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: purple,
                                padding: const EdgeInsets.all(16),
                              ),
                              child: Text(
                                widget.problem == null ? '돌아가기' : '원래 문제 다시 풀기',
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _recognitionNotice() => [
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.document_scanner_outlined, color: purple, size: 32),
          const SizedBox(height: 14),
          Text(
            phase == 'recognizing'
                ? '사진의 글씨를 읽고 있어요'
                : phase == 'recognition_failed'
                ? (capture?['ocr_status'] == 'UNREADABLE'
                      ? '사진의 글씨를 읽지 못했어요'
                      : '사진 인식 결과를 받지 못했어요')
                : phase == 'solution_missing'
                ? '문제는 인식했어요'
                : phase == 'raw_recognized'
                ? '사진의 글씨를 읽었어요'
                : '사진 분석을 준비하고 있어요',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: purple,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            phase == 'recognizing'
                ? '문제와 풀이를 인식한 결과를 기다리고 있어요.'
                : phase == 'recognition_failed'
                ? ((capture?['ocr_status'] == 'UNREADABLE')
                      ? '글씨가 선명하게 보이도록 문제 하나와 풀이를 가까이 찍어 주세요. 내용을 직접 옮겨 적을 필요는 없어요.'
                      : '사진은 저장됐지만 글씨 인식 결과를 받지 못했어요. 인식 결과를 다시 확인하거나 잠시 후 다시 촬영해 주세요.')
                : phase == 'solution_missing'
                ? '풀이 내용은 인식되지 않았어요. 문제만 찍었다면 개념 도움을 받거나, 풀이가 함께 보이게 다시 촬영해 주세요.'
                : phase == 'raw_recognized'
                ? '아래는 사진에서 읽은 원문이에요. 문제와 풀이를 자동으로 나누지는 않아요. 확인·수정을 눌러 잘못 읽은 부분을 고칠 수 있어요.'
                : phase == 'analysis_unavailable'
                ? '이 문제의 사진 풀이 분석은 아직 지원되지 않아요. 원래 문제로 돌아가 답안을 제출하거나 개념 도움을 받을 수 있어요.'
                : '사진 속 문제의 개념을 자동으로 찾는 기능은 아직 준비 중이에요. 개념을 직접 선택할 필요는 없어요.',
            style: const TextStyle(height: 1.7),
          ),
          if (problemText.text.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('인식된 문제', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SelectableText(
              problemText.text,
              style: const TextStyle(height: 1.6),
            ),
          ],
          if (capture?['ocr_raw_text'] is String &&
              phase != 'recognition_failed' &&
              (capture!['ocr_raw_text'] as String).trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('인식된 원문', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SelectableText(capture!['ocr_raw_text'] as String),
          ],
          if (solutionText.text.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('인식된 풀이', style: TextStyle(fontWeight: FontWeight.w800)),
            SelectableText(solutionText.text),
          ],
        ],
      ),
    ),
    if (rawText.trim().isNotEmpty &&
        phase != 'recognition_failed' &&
        phase != 'recognizing' &&
        analysis == null)
      _primary('인식 내용 확인·수정', _editRecognition),
    if (!polling) _primary('인식 결과 다시 확인', _refreshRecognition),
    if ([
          'solution_missing',
          'raw_recognized',
          'analysis_unavailable',
        ].contains(phase) &&
        widget.problem?.problemId != null)
      _primary('내용 확인하고 개념 도움 받기', _editRecognition),
    if (phase != 'recognizing')
      OutlinedButton.icon(
        onPressed: busy || closing ? null : () => _pick(ImageSource.camera),
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('다시 촬영하기'),
      ),
  ];

  List<Widget> _resultWidgets() {
    if (unsupported) return [];
    final a = analysis!, status = analysis!['status'];
    if (pending) {
      return [
        _card(
          const Column(
            children: [
              CrewmateMascotBadge(size: 48),
              SizedBox(height: 12),
              Text(
                '풀이를 살펴보고 있어요',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: purple,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '분석이 진행 중이에요. 결과가 준비되면 표시할게요.',
                textAlign: TextAlign.center,
                style: TextStyle(height: 1.6),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: busy || polling ? null : _refreshAnalysis,
          child: const Text('분석 상태 다시 확인하기'),
        ),
      ];
    }
    final definitive = status == 'ANALYZED';
    final partial = CaptureService.isPartial(a);
    final steps = a['solution_steps'] is List
        ? a['solution_steps'] as List
        : const [];
    final errors = a['errors'] is List
        ? (a['errors'] as List).whereType<Map>().toList()
        : <Map>[];
    final first = definitive && a['is_correct'] == false
        ? a['first_error_step']
        : null;
    final label = CaptureService.assessmentLabel(a);
    final title = label == '정답'
        ? '풀이가 맞았어요!'
        : label == '오답'
        ? '처음 실수한 부분을 살펴볼까요?'
        : label;
    return [
      if (LearningNextAction.fromResponse(a) case final action?)
        LearningNextActionNotice(
          action: action,
          onAction: () {
            if (action == LearningNextAction.confirmInput) {
              setState(() {
                phase = 'edit';
                savedCorrection = null;
                correctingPartial = partial;
                error = null;
              });
              _scrollToTop();
            } else {
              openLearningAction(
                context,
                action,
                repository: service.repository,
                response: a,
                captureId: capture?['id'],
                analysisId: a['id'],
                problemId: widget.problem?.problemId,
              );
            }
          },
        ),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: purple,
              ),
            ),
            const SizedBox(height: 8),
            if (partial)
              const Text(
                '아직 최종 답이 없어요. 마지막 답까지 적은 뒤 다시 분석해 주세요. 정답이나 오답으로 집계되지 않아요.',
                style: TextStyle(height: 1.6),
              ),
            if (!definitive)
              Text(
                a['is_correct'] == null && status == 'REVIEW_REQUIRED'
                    ? 'AI가 정답 여부를 판정하지 못했어요. 인식된 문제와 풀이 내용을 확인해 주세요.'
                    : status == 'UNKNOWN' && a['is_correct'] == null
                    ? '사진의 문제와 풀이가 잘 보이는지, 인식된 내용이 맞는지 확인해 주세요.'
                    : '분석이 완료되지 않았거나 추가 확인이 필요한 상태예요. 인식 내용을 수정한 뒤 다시 시도할 수 있어요.',
                style: const TextStyle(height: 1.6),
              ),
            if (a['confidence'] is num && (a['confidence'] as num) < .5)
              const Text(
                '분석 신뢰도가 낮아요. 풀이와 함께 참고해 주세요.',
                style: TextStyle(height: 1.6),
              ),
            if (first is int)
              Text(
                '최초 오류 · $first단계',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  height: 1.8,
                ),
              ),
          ],
        ),
      ),
      for (var i = 0; i < steps.length; i++)
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                first == i + 1 ? '${i + 1}단계 · 최초 오류' : '${i + 1}단계',
                style: TextStyle(
                  color: first == i + 1 ? const Color(0xFFB44050) : purple,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                '${steps[i]}',
                style: const TextStyle(height: 1.7),
              ),
              for (final e in errors.where(
                (e) => e['step_no'] == i + 1 && e['content'] is String,
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${e['content']}',
                    style: const TextStyle(
                      color: Color(0xFFB44050),
                      height: 1.6,
                    ),
                  ),
                ),
            ],
          ),
          color: first == i + 1
              ? const Color(0xFFFFEEEE)
              : const Color(0xFFF8F6FD),
        ),
      for (final e in errors.where(
        (e) =>
            e['content'] is String &&
            (e['step_no'] is! int ||
                e['step_no'] < 1 ||
                e['step_no'] > steps.length),
      ))
        _card(Text('${e['content']}', style: const TextStyle(height: 1.6))),
      if (!definitive && canAnalyze)
        _primary(
          '인식 내용 확인하고 다시 시도하기',
          () => setState(() {
            phase = 'edit';
            error = null;
          }),
        ),
      if (!definitive && !retryAllowed) const Text('분석 재시도 횟수를 모두 사용했어요.'),
      if (partial && canAnalyze)
        _primary(
          '최종 답 추가하고 다시 분석하기',
          () => setState(() {
            correctingPartial = true;
            savedCorrection = null;
            phase = 'edit';
            error = null;
            _scrollToTop();
          }),
        ),
      if (definitive && !partial)
        _primary('AI 튜터에게 힌트 받기', () => _openTutor(action: 'ANALYZE_RESULT')),
    ];
  }
}

class _CaptureFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF5238)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    const d = 26.0;
    for (final corner in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ]) {
      final dx = corner.dx == 0 ? d : -d, dy = corner.dy == 0 ? d : -d;
      canvas.drawPath(
        Path()
          ..moveTo(corner.dx, corner.dy + dy)
          ..lineTo(corner.dx, corner.dy)
          ..lineTo(corner.dx + dx, corner.dy),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
