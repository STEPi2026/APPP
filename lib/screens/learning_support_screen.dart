import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/tutor_help_service.dart';
import 'space_cartoon_painters.dart';
import '../models/learning_next_action.dart';
import '../models/math_display.dart';
import '../services/learning_repository.dart';
import 'learning_action_routes.dart';
import 'learning_next_action_notice.dart';

/// Help leaves the underlying problem mounted and never submits an answer.
class LearningSupportScreen extends StatefulWidget {
  final String problemTitle;
  final int? problemId;
  final String? problemCode;
  final HelpRequest? request;
  final HelpReaction? reaction;
  final LearningRepository? repository;
  final bool returnForAnswer;
  const LearningSupportScreen({
    super.key,
    required this.problemTitle,
    this.problemId,
    this.problemCode,
    this.request,
    this.reaction,
    this.repository,
    this.returnForAnswer = false,
  });
  @override
  State<LearningSupportScreen> createState() => _LearningSupportScreenState();
}

class _LearningSupportScreenState extends State<LearningSupportScreen> {
  late final TutorHelpService _service;
  late final _repository = widget.repository ?? LearningRepository();
  TutorHelpResult? _result;
  bool _busy = false;
  bool _hintRejected = false;
  String? _error;
  String? _stage, _skillCode, _retryStage, _retrySkillCode;
  @override
  void initState() {
    super.initState();
    _service = TutorHelpService(
      problemId: widget.problemId,
      problemCode: widget.problemCode,
      get: _repository.get,
      post: _repository.post,
    );
    _load(stage: 'hint');
  }

  String _errorMessage(Object error) {
    if (error is ApiException) {
      switch (error.code) {
        case 'LOCAL_PROBLEM_ONLY':
        case 'PROBLEM_NOT_FOUND':
          return '이 문제의 서버 정보를 찾지 못했어요. 원래 문제로 돌아가 주세요.';
        case 'TUTOR_STUDENT_ONLY':
          return '학생 계정에서 도움을 받을 수 있어요.';
        case 'AUTH_TOKEN_EXPIRED':
        case 'AUTH_TOKEN_INVALID':
        case 'AUTH_REFRESH_EXPIRED':
        case 'AUTH_REFRESH_REVOKED':
          return '로그인 상태를 확인해 주세요.';
        case 'TUTOR_SKILL_NOT_RELATED':
          return '이 문제에서 복습할 수 있는 개념이 아니에요. 원래 문제로 돌아가 주세요.';
        case 'AI_CATALOG_NOT_READY':
        case 'AI_NOT_CONFIGURED':
        case 'AI_REQUEST_FAILED':
          return '지금은 도움을 불러올 수 없어요. 원래 문제로 돌아가거나 잠시 후 다시 시도해 주세요.';
      }
    }
    return '지금은 도움을 불러올 수 없어요. 잠시 후 다시 시도해 주세요.';
  }

  Future<void> _load({String? stage, String? skillCode}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _hintRejected = false;
      _retryStage = stage;
      _retrySkillCode = skillCode;
    });
    try {
      final result = await (widget.request ?? _service.request)(
        stage: stage,
        skillCode: skillCode,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _stage = stage;
        _skillCode = skillCode;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hintRejected =
            stage == 'hint' &&
            error is ApiException &&
            error.statusCode == 422 &&
            (error.code == 'VALIDATION_ERROR' || error.code == 'UNKNOWN_ERROR');
        _error = _hintRejected
            ? '힌트를 요청하지 못했어요. 개념 설명을 먼저 확인할 수 있어요.'
            : _errorMessage(error);
        _busy = false;
      });
    }
  }

  Future<void> _react(
    String reaction, {
    bool returnToProblem = false,
    bool explainAgain = false,
  }) async {
    final result = _result;
    if (_busy || result == null) return;
    setState(() {
      _busy = true;
    });
    try {
      await (widget.reaction ?? _service.react)(result.actionId, reaction);
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      if (returnToProblem) {
        Navigator.pop(context);
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('의견을 전달했어요.')));
      if (explainAgain) {
        // Repeating a hint request advances the server's counter. Request a
        // concept explanation instead when the student asks for explanation.
        await _load(
          stage: _stage == 'hint' ? 'explanation' : _stage,
          skillCode: _skillCode,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('의견을 저장하지 못했어요. 다시 시도하거나 원래 문제로 돌아가 주세요.'),
        ),
      );
    }
  }

  static const _purple = Color(0xFF7C5CFA);
  bool _following = false;
  Future<void> _follow(
    LearningNextAction action,
    TutorHelpResult result,
  ) async {
    if (_following || _busy) return;
    if (action == LearningNextAction.checkAnswer && widget.returnForAnswer) {
      Navigator.pop(context, action);
      return;
    }
    _following = true;
    try {
      await openLearningAction(
        context,
        action,
        repository: _repository,
        response: result.actionData,
        problemId: widget.problemId,
        onHint: () => showLearningHint(context, result.message),
      );
    } finally {
      _following = false;
    }
  }

  static const _ink = Color(0xFF171717);
  static const _muted = Color(0xFF85818F);
  static const _lavender = Color(0xFFF3EEFF);

  Widget _card(Widget child, {Color color = Colors.white}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xFFECE7F5)),
    ),
    child: child,
  );

  Widget _primary(
    String label,
    VoidCallback? action, {
    IconData icon = Icons.arrow_forward_rounded,
  }) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: action,
      icon: Icon(icon, size: 19),
      label: Text(label, textAlign: TextAlign.center),
      style: FilledButton.styleFrom(
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE5DCF9),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        textStyle: Theme.of(context).textTheme.labelLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );

  Widget _hero() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: _lavender,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: _purple),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'STEPi 튜터',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _purple,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '막막할 땐,\n함께 한 걸음씩!',
                style: TextStyle(
                  fontSize: 23,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.problemTitle,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const ExcludeSemantics(
          child: CrewmateMascotBadge(size: 76, suitColor: Color(0xFFCBB2FC)),
        ),
      ],
    ),
  );

  Widget _steps() {
    final showingHints =
        _result?.actionType == 'SOCRATIC_HINT' ||
        (_result == null && _retryStage == 'hint');
    final selected = showingHints
        ? (_result?.hintLevel ?? 0) - 1
        : _stage == 'example'
        ? 1
        : _stage == 'check'
        ? 2
        : 0;
    final labels = showingHints
        ? const ['첫 힌트', '두 번째', '세 번째']
        : const ['개념 설명', '쉬운 예제', '확인 문제'];
    return Row(
      children: [
        for (int i = 0; i < labels.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: i == selected ? _lavender : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: i == selected
                        ? const Color(0xFFD9CAFF)
                        : const Color(0xFFECE7F5),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      '0${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: i == selected ? _purple : _muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: i == selected ? _purple : _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _loadingCard() => _card(
    const Column(
      children: [
        SizedBox(height: 8),
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(color: _purple, strokeWidth: 3),
        ),
        SizedBox(height: 18),
        Text(
          '도움 내용을 준비하고 있어요…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: _ink,
          ),
        ),
        SizedBox(height: 8),
        Text('조금만 기다려 주세요.', style: TextStyle(fontSize: 13, color: _muted)),
        SizedBox(height: 8),
      ],
    ),
  );

  Widget _errorCard() => _card(
    Column(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: const BoxDecoration(
            color: _lavender,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.cloud_off_rounded, color: _purple, size: 27),
        ),
        const SizedBox(height: 18),
        const Text(
          '도움을 불러오지 못했어요',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.7, color: _muted),
        ),
        const SizedBox(height: 22),
        _primary(
          _hintRejected ? '개념 설명 보기' : '다시 시도',
          () => _load(
            stage: _hintRejected ? 'explanation' : _retryStage,
            skillCode: _retrySkillCode,
          ),
          icon: _hintRejected ? Icons.menu_book_rounded : Icons.refresh_rounded,
        ),
      ],
    ),
  );

  Widget _contentCard(String title, String text, IconData icon) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _lavender,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: _purple),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SelectableText(
          displayMath(text),
          style: const TextStyle(fontSize: 14, height: 1.85, color: _ink),
        ),
        if (title == '확인 문제') ...[
          const SizedBox(height: 14),
          const Text(
            '정답을 제출하지 않고, 스스로 생각해 봐도 좋아요.',
            style: TextStyle(fontSize: 12, height: 1.6, color: _muted),
          ),
        ],
      ],
    ),
  );

  List<Widget> _content(TutorHelpResult result) => [
    if (LearningNextAction.fromCode(result.nextAction ?? result.nextStep)
        case final action?)
      LearningNextActionNotice(
        action: action,
        onAction: () => _follow(action, result),
      ),
    _card(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: _lavender,
            child: Icon(Icons.auto_awesome_rounded, size: 18, color: _purple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.actionType == 'SOCRATIC_HINT') ...[
                  Text(
                    result.hintLevel == null
                        ? '생각을 여는 힌트'
                        : '힌트 ${result.hintLevel}단계',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _purple,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  displayMath(result.message),
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    for (final entry in {
      '개념 설명': result.explanation,
      '쉬운 예제': result.example,
      '확인 문제': result.checkQuestion,
    }.entries)
      if (entry.value != null) ...[
        const SizedBox(height: 14),
        _contentCard(
          entry.key,
          entry.value!,
          entry.key == '개념 설명'
              ? Icons.menu_book_rounded
              : entry.key == '쉬운 예제'
              ? Icons.lightbulb_outline_rounded
              : Icons.edit_note_rounded,
        ),
      ],
    const SizedBox(height: 18),
    if (result.actionType == 'SOCRATIC_HINT') ...[
      _primary(
        result.hintLevel == 3 ? '다음 도움 보기' : '다음 힌트 보기',
        () => _load(stage: 'hint', skillCode: _skillCode),
        icon: Icons.lightbulb_outline_rounded,
      ),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () => _load(stage: 'explanation', skillCode: _skillCode),
        icon: const Icon(Icons.menu_book_rounded, size: 19),
        label: const Text('개념부터 보기'),
      ),
    ] else if ([
      'hint',
      'explanation',
      'example',
      'check',
    ].contains(result.nextStage))
      _primary(
        result.nextStage == 'explanation' ? '개념 설명 보기' : '다음 단계',
        () => _load(stage: result.nextStage, skillCode: _skillCode),
      )
    else if (result.nextStage == null)
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _lavender,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: _purple, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '이 개념의 도움 단계를 모두 확인했어요.',
                style: TextStyle(
                  color: _purple,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    if (result.nextStep == 'PREREQUISITE_REVIEW' &&
        result.nextSkillCode != null) ...[
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: () =>
            _load(stage: 'explanation', skillCode: result.nextSkillCode),
        icon: const Icon(Icons.route_rounded, size: 19),
        label: const Text('선수개념 복습하기'),
      ),
    ],
    if (_skillCode != null)
      TextButton(
        onPressed: () => _load(),
        child: const Text('현재 문제 개념으로 돌아가기'),
      ),
    const SizedBox(height: 12),
    _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '어떤 도움이 되었나요?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              TextButton(
                onPressed: () => _react('HELPFUL'),
                child: const Text('도움됐어요'),
              ),
              TextButton(
                onPressed: () => _react('UNDERSTOOD', returnToProblem: true),
                child: const Text('이해했어요'),
              ),
              TextButton(
                onPressed: () => _react('EXPLAIN_AGAIN', explainAgain: true),
                child: Text(
                  result.actionType == 'SOCRATIC_HINT'
                      ? '개념으로 설명해 주세요'
                      : '다시 설명해 주세요',
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final title = result?.actionType == 'PREREQUISITE_REVIEW'
        ? '선수개념 복습'
        : '학습 도움';
    return Theme(
      data: Theme.of(context).copyWith(
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _purple,
            textStyle: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _purple,
            side: const BorderSide(color: Color(0xFFD9CAFF)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            textStyle: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontSize: 14, fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF8FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            tooltip: '원래 문제로 돌아가기',
          ),
          titleSpacing: 0,
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 20),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _lavender,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'AI 튜터',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _purple,
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _hero(),
                        const SizedBox(height: 18),
                        _steps(),
                        const SizedBox(height: 18),
                        if (_busy)
                          _loadingCard()
                        else if (_error != null)
                          _errorCard()
                        else if (result != null)
                          ..._content(result),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFECE7F5))),
              ),
              child: SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(
                                Icons.edit_note_rounded,
                                size: 20,
                              ),
                              label: const Text('원래 문제 다시 풀기'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '작성한 답안과 필기는 그대로예요.',
                            style: TextStyle(fontSize: 11, color: _muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
