import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import 'knowledge_widgets.dart';
import 'space_cartoon_painters.dart';
import '../models/learning_next_action.dart';
import '../models/math_display.dart';
import 'learning_action_routes.dart';
import 'learning_next_action_notice.dart';

/// Analysis help always uses the actual AI① analysis ID. It never invents a
/// problem_id for a student's external photograph or grades a check question.
class AnalysisSupportScreen extends StatefulWidget {
  final int analysisId;
  final LearningRepository? repository;
  final int? captureId, problemId;
  const AnalysisSupportScreen({
    super.key,
    required this.analysisId,
    this.repository,
    this.captureId,
    this.problemId,
  });
  @override
  State<AnalysisSupportScreen> createState() => _AnalysisSupportScreenState();
}

class _AnalysisSupportScreenState extends State<AnalysisSupportScreen> {
  late final repo = widget.repository ?? LearningRepository();
  JsonMap? feedback;
  String? error;
  bool busy = false,
      contractPending = false,
      variantUnavailable = false,
      variantFailed = false;
  int hintCount = 0, requestedHint = 0;
  bool following = false;
  Future<void> _follow(LearningNextAction action) async {
    if (following || busy || feedback == null) return;
    following = true;
    try {
      await openLearningAction(
        context,
        action,
        repository: repo,
        response: feedback!,
        problemId: widget.problemId,
        captureId: widget.captureId,
        analysisId: widget.analysisId,
        onHint: () =>
            showLearningHint(context, '${feedback!['content']['message']}'),
      );
    } finally {
      following = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int count) async {
    if (busy || count > 10) return;
    setState(() {
      busy = true;
      error = null;
      contractPending = false;
      requestedHint = count;
      variantFailed = false;
    });
    try {
      final result = await repo.post('/api/v1/tutor/feedback', {
        'analysis_id': widget.analysisId,
        'hint_count': count,
      });
      _validate(result);
      if (mounted) {
        setState(() {
          feedback = result;
          hintCount = count;
          variantUnavailable = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _message(e);
          contractPending =
              e is ApiException &&
              [
                'AI_CONTRACT_PENDING',
                'TUTOR_ANALYSIS_NOT_READY',
              ].contains(e.code);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _validate(JsonMap result) {
    if (result['tutor_action_id'] is! int ||
        result['content'] is! Map ||
        result['content']['message'] is! String) {
      throw const FormatException('도움 응답을 확인하지 못했어요.');
    }
  }

  String _message(Object e) {
    if (e is ApiException && e.code == 'AI_CONTRACT_PENDING') {
      return '풀이 분석과 맞춤 도움을 연결하는 작업이 준비 중이에요. 분석 결과를 먼저 확인해 주세요.';
    }
    if (e is ApiException && e.code == 'TUTOR_ANALYSIS_NOT_READY') {
      return '풀이 분석이 완료된 뒤 도움을 받을 수 있어요.';
    }
    if (e is ApiException && (e.statusCode == 502 || e.statusCode == 503)) {
      return '지금은 도움을 불러올 수 없어요. 풀이 결과는 그대로 남아 있어요.';
    }
    return learningError(e);
  }

  Future<void> _react(String reaction) async {
    if (busy || feedback == null) return;
    setState(() => busy = true);
    bool accepted = false;
    try {
      await repo.post(
        '/api/v1/tutor/actions/${feedback!['tutor_action_id']}/responses',
        {'reaction': reaction},
      );
      accepted = true;
      if (mounted && reaction == 'UNDERSTOOD') {
        Navigator.pop(context);
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (accepted && mounted) {
      if (reaction == 'EXPLAIN_AGAIN') {
        await _load(hintCount);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('의견을 전달했어요.')));
      }
    }
  }

  Future<void> _variant() async {
    if (busy || feedback == null || variantUnavailable) return;
    setState(() {
      busy = true;
      error = null;
      variantFailed = true;
    });
    try {
      final result = await repo.post('/api/v1/tutor/variant-problems', {
        'tutor_action_id': feedback!['tutor_action_id'],
      });
      _validate(result);
      if (mounted) setState(() => feedback = result);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = _message(e);
          if (e is ApiException && e.code == 'VARIANT_NOT_AVAILABLE') {
            variantUnavailable = true;
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _card(Widget child, {bool tinted = false}) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: tinted ? const Color(0xFFF3EEFF) : Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFECE7F5)),
    ),
    child: child,
  );
  @override
  Widget build(BuildContext context) {
    final content = feedback?['content'],
        variant = feedback?['variant_problem'];
    final nextAction = LearningNextAction.fromResponse(feedback ?? {});
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(title: const Text('풀이 맞춤 도움')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _card(
                const Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STEPi 튜터',
                            style: TextStyle(
                              color: knowledgePurple,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 10),
                          Text(
                            '개념을 탄탄하게,\n함께 한 걸음씩!',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w900,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CrewmateMascotBadge(size: 70, suitColor: Color(0xFFCBB2FC)),
                  ],
                ),
                tinted: true,
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(color: knowledgePurple),
                ),
              if (error != null)
                KnowledgeNotice(
                  message: error!,
                  onRetry: contractPending || busy || variantUnavailable
                      ? null
                      : () => variantFailed ? _variant() : _load(requestedHint),
                ),
              if (content is Map) ...[
                if (nextAction != null)
                  LearningNextActionNotice(
                    action: nextAction,
                    onAction: () => _follow(nextAction),
                  ),
                for (final entry in {
                  '함께 살펴봐요': content['message'],
                  '개념 설명': content['explanation'],
                  '쉬운 예제': content['example'],
                  '확인 문제': content['check_question'],
                }.entries)
                  if (entry.value is String &&
                      (entry.value as String).trim().isNotEmpty)
                    _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              color: knowledgePurple,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            displayMath(entry.value as String),
                            style: const TextStyle(height: 1.8, fontSize: 14),
                          ),
                          if (entry.key == '확인 문제')
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Text(
                                '생각해 보는 문제예요. 현재는 정답을 제출하거나 채점하지 않아요.',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                if (content['video'] is Map &&
                    content['video']['url'] is String)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final uri = Uri.tryParse(content['video']['url']);
                            if (uri != null &&
                                ['http', 'https'].contains(uri.scheme)) {
                              final opened = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!opened && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('영상을 열지 못했어요.')),
                                );
                              }
                            }
                          },
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('관련 영상 보기'),
                  ),
                if (feedback?['next_step'] == 'PREREQUISITE_REVIEW')
                  const KnowledgeNotice(
                    message: '선수개념을 함께 복습하면 좋아요. 위 개념 설명과 예제를 확인해 주세요.',
                  ),
                if (hintCount < 10)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: knowledgePurple,
                      padding: const EdgeInsets.all(16),
                    ),
                    onPressed: busy ? null : () => _load(hintCount + 1),
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    label: const Text('다음 힌트 확인'),
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final r in {
                      'HELPFUL': '도움됐어요',
                      'UNDERSTOOD': '이해했어요',
                      'EXPLAIN_AGAIN': '다시 설명해 주세요',
                    }.entries)
                      TextButton(
                        onPressed: busy ? null : () => _react(r.key),
                        child: Text(r.value),
                      ),
                  ],
                ),
                if (variant is! Map && !variantUnavailable)
                  OutlinedButton(
                    onPressed: busy ? null : _variant,
                    child: Text(
                      nextAction == LearningNextAction.relearn
                          ? '한 문제 더 연습하기'
                          : '비슷한 문제로 연습하기',
                    ),
                  ),
              ],
              if (variant is Map &&
                  variant['id'] is int &&
                  variant['prompt'] is String)
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '비슷한 문제',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: knowledgePurple,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(displayMath(variant['prompt'])),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: busy
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => TutorVariantScreen(
                                      problem: Map<String, dynamic>.from(
                                        variant,
                                      ),
                                      repository: repo,
                                    ),
                                  ),
                                );
                              },
                        child: const Text('문제 풀기'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('원래 풀이로 돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TutorVariantScreen extends StatefulWidget {
  final JsonMap problem;
  final LearningRepository repository;
  const TutorVariantScreen({
    super.key,
    required this.problem,
    required this.repository,
  });
  @override
  State<TutorVariantScreen> createState() => _TutorVariantScreenState();
}

class _TutorVariantScreenState extends State<TutorVariantScreen> {
  final answer = TextEditingController();
  JsonMap? result;
  String? error;
  bool busy = false, expired = false;
  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (busy || result != null || expired || answer.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.repository.post(
        '/api/v1/tutor/variant-problems/${widget.problem['id']}/attempts',
        {'answer': answer.text.trim()},
      );
      if (data['correct'] != null && data['correct'] is! bool) {
        throw const FormatException('평가 결과를 확인하지 못했어요.');
      }
      LearningRepository.notifyProgressChanged();
      if (mounted) setState(() => result = data);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = learningError(e);
          expired =
              e is ApiException &&
              [
                'VARIANT_EXPIRED',
                'VARIANT_ALREADY_ATTEMPTED',
                'VARIANT_NOT_AVAILABLE',
              ].contains(e.code);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8FF),
    appBar: AppBar(title: const Text('비슷한 문제 풀기')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        KnowledgeNotice(message: displayMath('${widget.problem['prompt']}')),
        TextField(
          controller: answer,
          maxLength: 200,
          minLines: 2,
          maxLines: 5,
          enabled: !busy && result == null && !expired,
          decoration: const InputDecoration(
            labelText: '내 답안',
            helperText: mathInputGuide,
            helperMaxLines: 2,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy || result != null || expired ? null : _submit,
          child: Text(busy ? '제출 중…' : '제출하기'),
        ),
        if (error != null) KnowledgeNotice(message: error!),
        if (result != null) ...[
          KnowledgeNotice(
            message: result!['correct'] == true
                ? '정답이에요!'
                : result!['correct'] == false
                ? '다시 생각해 볼까요?'
                : '판정 보류',
          ),
          if (LearningNextAction.fromResponse(result!) case final action?)
            LearningNextActionNotice(
              action: action,
              onAction: () => openLearningAction(
                context,
                action,
                repository: widget.repository,
                response: result!,
                onHint: () => showLearningHint(
                  context,
                  '${result!['feedback']?['content']?['message'] ?? '힌트를 준비하고 있어요.'}',
                ),
              ),
            ),
          if (result!['feedback'] is Map &&
              result!['feedback']['content'] is Map)
            Text(
              displayMath('${result!['feedback']['content']['message'] ?? ''}'),
              style: const TextStyle(height: 1.7),
            ),
        ],
      ],
    ),
  );
}
