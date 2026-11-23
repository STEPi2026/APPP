import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/learning_next_action.dart';
import '../models/math_display.dart';
import '../services/api.dart';
import '../services/capture_service.dart';
import '../services/learning_repository.dart';
import '../services/question_service.dart';
import '../services/tutor_session_service.dart';
import 'capture_learning_screen.dart';
import 'problem_screen.dart';
import 'server_pathways.dart';
import 'space_cartoon_painters.dart';

/// Learning support beside the existing scratchpad, using the unified API.
class TutorSessionScreen extends StatefulWidget {
  final TutorTarget target;
  final TutorSessionService service;
  final String problemTitle, initialAction;
  final TutorSessionResult? initialResult;
  final bool returnForAnswer;
  final CapturePhoto? photo;
  final Future<JsonMap> Function(String skillCode)? analyzePhoto;
  const TutorSessionScreen({
    super.key,
    required this.target,
    required this.service,
    this.problemTitle = '학습 도움',
    this.initialAction = 'START',
    this.initialResult,
    this.returnForAnswer = false,
    this.photo,
    this.analyzePhoto,
  });
  @override
  State<TutorSessionScreen> createState() => _TutorSessionScreenState();
}

class _TutorSessionScreenState extends State<TutorSessionScreen> {
  static const purple = Color(0xFF7C5CFA), lavender = Color(0xFFF3EEFF);
  TutorSessionResult? result;
  String? error;
  String lastAction = 'START';
  String? lastAnswer;
  bool busy = false, enteringAnswer = false, following = false;
  final answer = TextEditingController();
  LearningRepository get repo => widget.service.repository;
  @override
  void initState() {
    super.initState();
    result = widget.initialResult;
    if (result == null) _request(widget.initialAction);
  }

  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  Future<void> _request(String action, {String? value}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      lastAction = action;
      lastAnswer = value;
    });
    try {
      final response = await widget.service.request(
        widget.target,
        action,
        answer: value,
      );
      if (mounted) {
        setState(() {
          result = response;
          enteringAnswer = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _analyze() async {
    final skill = result?.skillCode, callback = widget.analyzePhoto;
    if (busy || callback == null || skill == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final analysis = await callback(skill);
      if (!mounted) return;
      if (CaptureService.pending(analysis)) {
        setState(() => error = '사진 분석이 진행 중이에요. 잠시 후 분석 상태를 다시 확인해 주세요.');
      } else {
        final response = await widget.service.request(
          widget.target,
          'ANALYZE_RESULT',
        );
        if (mounted) setState(() => result = response);
      }
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm() async {
    final id = widget.target.captureId;
    if (following || id == null) return;
    following = true;
    try {
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => CaptureLearningScreen(
            savedCaptureId: id,
            service: CaptureService(repository: repo),
            returnAfterCorrection: true,
            savedPhoto: widget.photo,
          ),
        ),
      );
      if (mounted && saved == true) {
        await _request(
          result?.data['action'] is String
              ? result!.data['action']
              : widget.initialAction,
        );
      }
    } finally {
      following = false;
    }
  }

  Future<void> _problem({int? id, String? skill}) async {
    if (following) return;
    following = true;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProblemScreen(
            topic: id != null ? '한 문제 더 연습하기' : '다음 개념 학습',
            repository: repo,
            questionService: ServerQuestionService(
              problemId: id,
              skillCode: skill,
              repository: repo,
            ),
          ),
        ),
      );
    } finally {
      following = false;
    }
  }

  Widget _card(String title, Widget body) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFECE7F5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: purple,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        body,
      ],
    ),
  );
  Widget _text(String text) =>
      SelectableText(text, style: const TextStyle(height: 1.8, fontSize: 14));
  Widget _button(String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : action,
        style: FilledButton.styleFrom(
          backgroundColor: purple,
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label),
      ),
    ),
  );
  List<Widget> _concept(Object? value, String fallbackTitle) {
    if (value is! Map) return [];
    final parts = [
      value['explanation_easy'],
      value['explanation'],
      value['example'],
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toSet();
    if (parts.isEmpty) return [];
    return [
      _card(
        '${value['concept_name'] ?? fallbackTitle}',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final part in parts)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _text(part),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _next(TutorSessionResult current) {
    if (current.needsAnalysis) {
      return [
        _card(
          '사진 풀이 분석',
          const Text(
            '확인한 문제와 풀이를 먼저 분석한 뒤 학습을 이어가요.',
            style: TextStyle(height: 1.7),
          ),
        ),
        if (widget.analyzePhoto != null)
          _button('사진 풀이 분석하기', _analyze)
        else
          _button('사진 내용 확인·수정', _confirm),
      ];
    }
    switch (current.nextAction) {
      case 'CONFIRM_INPUT':
        return [_button('사진 내용 확인·수정', _confirm)];
      case 'SHOW_SOLUTION':
        return [_button('해설 보기', () => _request('SHOW_SOLUTION'))];
      case 'RELEARN':
        return [_button('한 문제 더 연습하기', () => _request('RELEARN'))];
      case 'HINT':
        return [_button('힌트 보기', () => _request('HINT'))];
      case 'CHECK_ANSWER':
        final next = current.nextProblem;
        if (next != null) {
          final id = next['id'];
          return [
            _card('다음 연습 문제', _text('${next['prompt'] ?? ''}')),
            if (id is int && id > 0)
              _button('이 문제 풀기', () => _problem(id: id))
            else
              _card(
                '문제 준비 중',
                const Text(
                  '아직 답을 제출할 수 있는 문제 정보가 없어요. 개념을 복습하거나 원래 문제로 돌아가 주세요.',
                ),
              ),
          ];
        }
        return [
          _button('답 입력하기', () {
            if (widget.returnForAnswer) {
              Navigator.pop(context, LearningNextAction.checkAnswer);
            } else {
              setState(() => enteringAnswer = true);
            }
          }),
        ];
      case 'NEXT_SKILL':
        final code = current.nextSkill?['skill_code'];
        return [
          if (current.nextSkill?['name'] is String)
            _card('다음 개념', _text(current.nextSkill!['name'])),
          _button('다음 개념 학습', () {
            if (code is String && code.trim().isNotEmpty) {
              _problem(skill: code);
            } else {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ServerRoadmapScreen(repository: repo),
                ),
              );
            }
          }),
        ];
      case 'LEARNING_COMPLETE':
        return [
          _card('학습 완료', const Text('이번 학습을 마쳤어요! 학습 경로에서 다음 목표를 확인해 보세요.')),
          _button(
            '학습 경로 보기',
            () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ServerRoadmapScreen(repository: repo),
              ),
            ),
          ),
        ];
      default:
        return [
          _button('개념 설명 보기', () => _request('CONCEPT')),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => Navigator.pop(
                    context,
                    widget.returnForAnswer
                        ? LearningNextAction.checkAnswer
                        : null,
                  ),
            child: const Text('원래 문제 다시 풀기'),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = result, data = result?.data;
    final solution = data?['solution'];
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
        ),
        title: Text(data?['action'] == 'SHOW_SOLUTION' ? '문제 해설' : '학습 도움'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: lavender,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'STEPi 튜터',
                            style: TextStyle(
                              color: purple,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            '함께 한 걸음씩!',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(widget.problemTitle),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const CrewmateMascotBadge(
                      size: 72,
                      suitColor: Color(0xFFCBB2FC),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(color: purple),
                ),
              if (error != null)
                _card(
                  '지금은 도움을 불러올 수 없어요',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(error!, style: const TextStyle(height: 1.7)),
                      TextButton(
                        onPressed: busy
                            ? null
                            : current?.needsAnalysis == true
                            ? _analyze
                            : () => _request(lastAction, value: lastAnswer),
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              if (current != null && data != null) ...[
                if (!current.needsAnalysis)
                  _card('함께 살펴봐요', _text(current.message)),
                if (data['answer_correct'] is bool)
                  _card(
                    data['answer_correct'] == true ? '정답이에요!' : '다시 도전해 볼까요?',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data['rewards'] is Map &&
                            data['rewards']['xp'] is num)
                          Text('이번 풀이 획득 XP · +${data['rewards']['xp']} XP'),
                        if (data['rewards'] is Map &&
                            data['rewards']['level_up'] == true)
                          const Text('레벨이 올랐어요!'),
                        if (data['rewards'] is Map &&
                            data['rewards']['new_badges'] is List)
                          for (final badge
                              in (data['rewards']['new_badges'] as List)
                                  .whereType<Map>())
                            Text(
                              '새 배지 · ${badge['name'] ?? badge['code'] ?? ''}',
                            ),
                      ],
                    ),
                  ),
                if (solution is Map)
                  _card(
                    '문제 해설',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (solution['answer_display'] is String &&
                            (solution['answer_display'] as String)
                                .trim()
                                .isNotEmpty)
                          _text('정답: ${solution['answer_display']}'),
                        if (solution['steps'] is List)
                          for (final (i, step)
                              in (solution['steps'] as List)
                                  .whereType<String>()
                                  .indexed)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: _text('${i + 1}. $step'),
                            ),
                      ],
                    ),
                  ),
                if (data['hint'] is String &&
                    (data['hint'] as String).isNotEmpty)
                  _card(
                    '힌트${data['hint_level'] is int ? ' ${data['hint_level']}단계' : ''}',
                    _text(data['hint']),
                  ),
                ..._concept(data['concept'], '개념 설명'),
                ..._concept(data['prerequisite_concept'], '선수개념 복습'),
                if (data['approved_videos'] is List)
                  for (final video
                      in (data['approved_videos'] as List).whereType<Map>())
                    if (video['url'] is String &&
                        [
                          'https',
                          'http',
                        ].contains(Uri.tryParse(video['url'])?.scheme))
                      OutlinedButton.icon(
                        icon: const Icon(Icons.play_circle_outline),
                        label: Text('${video['title'] ?? '학습 영상'}'),
                        onPressed: () => launchUrl(
                          Uri.parse(video['url']),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                ..._next(current),
              ],
              if (enteringAnswer) ...[
                TextField(
                  key: const ValueKey('tutor-session-answer'),
                  controller: answer,
                  maxLength: 200,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: '내 답안',
                    helperText: mathInputGuide,
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
                _button(
                  '답 제출하기',
                  () => _request('CHECK_ANSWER', value: answer.text),
                ),
              ],
              if (current != null)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final entry in {
                      'HINT': '힌트 보기',
                      'CONCEPT': '개념 설명',
                      'VIDEOS': '학습 영상',
                      'GIVE_UP': '못 풀겠어요',
                      'SKIP': '이번 문제 넘기기',
                    }.entries)
                      TextButton(
                        onPressed: busy ? null : () => _request(entry.key),
                        child: Text(entry.value),
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('원래 학습으로 돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
