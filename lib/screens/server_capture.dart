import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import 'server_learning.dart';

class ServerCaptureScreen extends StatefulWidget {
  final int? capturedId;
  const ServerCaptureScreen({super.key, this.capturedId});
  @override
  State<ServerCaptureScreen> createState() => _ServerCaptureScreenState();
}

class _ServerCaptureScreenState extends State<ServerCaptureScreen> {
  final repo = LearningRepository();
  final _problem = TextEditingController(), _solution = TextEditingController();
  Uint8List? _bytes;
  JsonMap? _capture, _analysis;
  List<JsonMap> _skills = [];
  String? _skill, _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final skills = await repo.all('/api/v1/skills');
      if (mounted) setState(() => _skills = skills);
    } catch (e) {
      if (mounted) setState(() => _error = learningError(e));
    }
    if (widget.capturedId != null) {
      try {
        final capture = await repo.get(
          '/api/v1/captured-problems/${widget.capturedId}',
        );
        if (!mounted) return;
        _setCapture(capture);
        final bytes = await Api.getCapturedImage(widget.capturedId!);
        if (mounted) setState(() => _bytes = bytes);
        final latest = capture['latest_analysis'];
        if (latest is Map && latest['id'] is int) {
          final analysis = await repo.get(
            '/api/v1/ai-analyses/${latest['id']}',
          );
          if (mounted) setState(() => _analysis = analysis);
        }
      } catch (e) {
        if (mounted) setState(() => _error = learningError(e));
      }
    }
  }

  void _setCapture(JsonMap capture) {
    setState(() {
      _capture = capture;
      _problem.text = '${capture['problem_text'] ?? ''}';
      _solution.text = '${capture['solution_text'] ?? ''}';
    });
  }

  @override
  void dispose() {
    _problem.dispose();
    _solution.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('사진은 10MB 이하로 선택해 주세요.');
      }
      final png =
          bytes.length > 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71;
      final jpeg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216;
      if (!png && !jpeg) throw const FormatException('JPG 또는 PNG 사진을 선택해 주세요.');
      if (!mounted) return;
      setState(() {
        _busy = true;
        _error = null;
        _bytes = bytes;
        _capture = null;
        _analysis = null;
      });
      final result = await Api.uploadCapturedProblem(
        imageBytes: bytes,
        filename: png ? 'solution.png' : 'solution.jpg',
      );
      if (result == null) throw const FormatException('사진을 올리지 못했어요.');
      if (mounted) _setCapture(result);
    } catch (e) {
      if (mounted) setState(() => _error = learningError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze({bool retry = false}) async {
    if (_busy || _capture == null) return;
    if (!retry &&
        (_skill == null ||
            _problem.text.trim().isEmpty ||
            _solution.text.trim().isEmpty)) {
      setState(() => _error = '문제·풀이 텍스트와 관련 Skill을 확인해 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      JsonMap result;
      if (retry) {
        result = await repo.post(
          '/api/v1/ai-analyses/${_analysis!['id']}/retry',
        );
      } else {
        await repo.patch('/api/v1/captured-problems/${_capture!['id']}/ocr', {
          'problem_text': _problem.text.trim(),
          'solution_text': _solution.text.trim(),
        });
        result = await repo.post(
          '/api/v1/captured-problems/${_capture!['id']}/analyze',
          {
            'skill_codes': [_skill],
          },
        );
      }
      for (
        int i = 0;
        i < 60 &&
            ['PENDING', 'PROCESSING', 'QUEUED'].contains(result['status']);
        i++
      ) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        result = await repo.get('/api/v1/ai-analyses/${result['id']}');
      }
      if (!mounted) return;
      setState(() => _analysis = result);
    } catch (e) {
      if (mounted) setState(() => _error = learningError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    return Scaffold(
      appBar: AppBar(title: const Text('풀이 사진 분석')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('문제와 풀이가 함께 보이는 사진을 선택해 주세요. 인식 내용을 확인한 뒤 분석합니다.'),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('사진 촬영'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('사진 선택'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_bytes != null)
            Image.memory(_bytes!, height: 220, fit: BoxFit.contain),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          if (_capture != null) ...[
            for (final warning
                in _capture!['ocr_warnings'] is List
                    ? _capture!['ocr_warnings']
                    : [])
              Text('$warning'),
            TextField(
              controller: _problem,
              enabled: !_busy,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '인식된 문제 · 수정 가능'),
            ),
            TextField(
              controller: _solution,
              enabled: !_busy,
              minLines: 3,
              maxLines: 10,
              decoration: const InputDecoration(labelText: '인식된 풀이 · 수정 가능'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _skill,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '관련 Skill'),
              items: [
                for (final skill in _skills)
                  DropdownMenuItem(
                    value: '${skill['code'] ?? skill['skill_code']}',
                    child: Text(
                      '${skill['name'] ?? skill['skill_name'] ?? skill['code']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _skill = value),
            ),
            FilledButton(
              onPressed: _busy ? null : () => _analyze(),
              child: const Text('확인하고 분석하기'),
            ),
          ],
          if (a != null) ...[
            learningCard(
              '분석 결과',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a['status'] != 'ANALYZED'
                        ? '인식·분석 결과를 더 확인해야 해요.'
                        : a['is_correct'] == true
                        ? '풀이가 맞았어요.'
                        : a['is_correct'] == false
                        ? '처음 실수한 단계를 확인해 보세요.'
                        : '정오를 확정하지 못했어요.',
                  ),
                  if ((a['confidence'] as num?) != null &&
                      (a['confidence'] as num) < 0.5)
                    const Text('신뢰도가 낮아 참고용으로 확인해 주세요.'),
                  if (a['first_error_step'] != null)
                    Text('최초 오류: ${a['first_error_step']}단계'),
                  for (
                    int i = 0;
                    i < (a['solution_steps'] as List? ?? []).length;
                    i++
                  )
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: a['first_error_step'] == i + 1
                          ? const Color(0xFFFFE6E6)
                          : const Color(0xFFF5F1FF),
                      child: Text('${i + 1}. ${a['solution_steps'][i]}'),
                    ),
                  for (final error in LearningRepository.items(a, 'errors'))
                    Text(
                      '${error['step_no'] ?? ''}단계: ${error['content'] ?? ''}',
                    ),
                  if ([
                    'FAILED',
                    'UNKNOWN',
                    'REVIEW_REQUIRED',
                  ].contains(a['status']))
                    OutlinedButton(
                      onPressed: _busy || (a['retry_count'] ?? 0) >= 3
                          ? null
                          : () => _analyze(retry: true),
                      child: const Text('분석 다시 시도 (최대 3회)'),
                    ),
                  if (a['status'] == 'ANALYZED')
                    FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ServerFeedbackScreen(analysisId: a['id']),
                        ),
                      ),
                      child: const Text('AI 튜터 도움 받기'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ServerFeedbackScreen extends StatefulWidget {
  final int analysisId;
  const ServerFeedbackScreen({super.key, required this.analysisId});
  @override
  State<ServerFeedbackScreen> createState() => _ServerFeedbackScreenState();
}

class _ServerFeedbackScreenState extends State<ServerFeedbackScreen> {
  final repo = LearningRepository();
  JsonMap? _feedback;
  String? _error;
  bool _busy = false;
  int _hint = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool variant = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextHint = _hint + 1;
      final result = await repo.post(
        variant ? '/api/v1/tutor/variant-problems' : '/api/v1/tutor/feedback',
        variant
            ? {'tutor_action_id': _feedback!['tutor_action_id']}
            : {'analysis_id': widget.analysisId, 'hint_count': nextHint},
      );
      if (mounted) {
        setState(() {
          _feedback = result;
          if (!variant) _hint = nextHint;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = learningError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _react(String reaction) async {
    if (_busy || _feedback == null) return;
    setState(() => _busy = true);
    try {
      await repo.post(
        '/api/v1/tutor/actions/${_feedback!['tutor_action_id']}/responses',
        {'reaction': reaction},
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('의견을 전달했어요.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (reaction == 'EXPLAIN_AGAIN' && _hint < 3) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _feedback?['content'];
    final variant = _feedback?['variant_problem'];
    return Scaffold(
      appBar: AppBar(title: const Text('풀이 맞춤 도움')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: () => _load(), child: const Text('다시 시도')),
          ],
          if (c is Map) ...[
            for (final field in [
              'message',
              'explanation',
              'example',
              'check_question',
            ])
              if (c[field] is String && (c[field] as String).isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText('${c[field]}'),
                  ),
                ),
            if (_hint < 3)
              FilledButton(
                onPressed: _busy ? null : () => _load(),
                child: const Text('다음 힌트'),
              ),
            Wrap(
              children: [
                for (final entry in {
                  'HELPFUL': '도움됐어요',
                  'UNDERSTOOD': '이해했어요',
                  'EXPLAIN_AGAIN': '다시 설명해 주세요',
                }.entries)
                  TextButton(
                    onPressed: _busy ? null : () => _react(entry.key),
                    child: Text(entry.value),
                  ),
              ],
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _load(variant: true),
              child: const Text('변형문제 요청'),
            ),
          ],
          if (variant is Map)
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ServerVariantScreen(
                    problem: Map<String, dynamic>.from(variant),
                  ),
                ),
              ),
              child: const Text('변형문제 풀기'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('풀이로 돌아가기'),
          ),
        ],
      ),
    );
  }
}

class ServerVariantScreen extends StatefulWidget {
  final JsonMap problem;
  const ServerVariantScreen({super.key, required this.problem});
  @override
  State<ServerVariantScreen> createState() => _ServerVariantScreenState();
}

class _ServerVariantScreenState extends State<ServerVariantScreen> {
  final _answer = TextEditingController();
  final repo = LearningRepository();
  bool _busy = false;
  JsonMap? _result;
  String? _error;
  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _answer.text.trim().isEmpty || _result != null) return;
    setState(() => _busy = true);
    try {
      final r = await repo.post(
        '/api/v1/tutor/variant-problems/${widget.problem['id']}/attempts',
        {'answer': _answer.text.trim()},
      );
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = learningError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('변형문제')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        SelectableText('${widget.problem['prompt']}'),
        TextField(
          controller: _answer,
          maxLength: 200,
          enabled: !_busy && _result == null,
          decoration: const InputDecoration(labelText: '답안'),
        ),
        FilledButton(
          onPressed: _busy || _result != null ? null : _submit,
          child: const Text('제출하기'),
        ),
        if (_error != null) Text(_error!),
        if (_result != null) ...[
          Text(
            _result!['correct'] == true
                ? '정답이에요!'
                : _result!['correct'] == false
                ? '다시 생각해 볼까요?'
                : '평가를 확정하지 못했어요.',
          ),
          if (_result!['feedback'] is Map)
            Text('${_result!['feedback']['content']?['message'] ?? ''}'),
        ],
      ],
    ),
  );
}
