import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/concept_check.dart';
import '../services/curriculum_graph.dart';
import '../services/learning_repository.dart';
import 'space_cartoon_painters.dart';
import 'recorded_problem_route.dart';
import '../models/answer_input.dart';
import '../services/numeric_answer_formatter.dart';

Future<ConceptCheckSnapshot?> showConceptLevelTest(
  BuildContext context, {
  required List<ConceptCheckItem> concepts,
  LearningRepository? repository,
  String? satelliteId,
}) => showDialog<ConceptCheckSnapshot>(
  context: context,
  barrierDismissible: false,
  builder: (_) => ConceptLevelTestDialog(
    concepts: concepts,
    repository: repository,
    satelliteId: satelliteId,
  ),
);

class ConceptLevelTestDialog extends StatefulWidget {
  final List<ConceptCheckItem> concepts;
  final LearningRepository? repository;
  final String? satelliteId;
  const ConceptLevelTestDialog({
    super.key,
    required this.concepts,
    this.repository,
    this.satelliteId,
  });
  @override
  State<ConceptLevelTestDialog> createState() => _ConceptLevelTestDialogState();
}

class _ConceptLevelTestDialogState extends State<ConceptLevelTestDialog> {
  static const purple = Color(0xFF7C5CFA),
      light = Color(0xFFF3EEFF),
      ink = Color(0xFF171717);
  late final repo = widget.repository ?? LearningRepository();
  final store = ConceptCheckStore(), answer = TextEditingController();
  ConceptCheckSnapshot snapshot = const ConceptCheckSnapshot();
  int? userId;
  int index = 0;
  String mode = 'diagnosis';
  bool busy = true, saving = false;
  String? error;
  JsonMap? session, results;
  String? selectedChoice;
  CurriculumGraph? graph;
  String? graphError, stateError;
  Map<String, JsonMap> skillStates = {};
  List<String> get availableConcepts => snapshot.grade < 10 || graph == null
      ? []
      : (widget.satelliteId == null
            ? graph!.conceptSkills.keys.toList()
            : graph!.conceptsForSatellite(widget.satelliteId!));
  List<ConceptCheckItem> get selected =>
      graph != null && snapshot.targetConceptCode != null
      ? graph!.checklist(snapshot.targetConceptCode!)
      : widget.concepts
            .where(
              (c) =>
                  c.grade <= snapshot.grade &&
                  (widget.satelliteId == null ||
                      c.id.contains(':${widget.satelliteId}:')),
            )
            .toList();
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    answer.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final me = await repo.get('/api/v1/users/me');
      if (me['id'] is! int) throw const FormatException('학생 정보를 확인하지 못했어요.');
      final id = me['id'] as int;
      var saved = await store.load(id);
      try {
        final profile = await repo.get('/api/v1/me/student-profile');
        final grade = switch (profile['grade_level']) {
          '초등' => 6,
          '중1' => 7,
          '중2' => 8,
          '중3' => 9,
          '고1' => 10,
          '고2' => 11,
          '고3' => 12,
          _ => saved.grade,
        };
        saved = ConceptCheckSnapshot(
          grade: grade,
          answers: saved.answers,
          targetConceptCode: saved.targetConceptCode,
        );
      } catch (_) {
        // A profile is optional; self-check records remain available offline.
      }
      if (!mounted) return;
      setState(() {
        userId = id;
        snapshot = saved;
      });
      await _loadGraph();
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadGraph() async {
    try {
      final loaded = await CurriculumGraph.load(repo);
      if (!mounted) return;
      setState(() {
        graph = loaded;
        graphError = null;
        final allowed = availableConcepts;
        var target = snapshot.targetConceptCode;
        if (!allowed.contains(target)) target = null;
        if (widget.satelliteId != null &&
            target == null &&
            allowed.isNotEmpty) {
          target = allowed.first;
        }
        snapshot = ConceptCheckSnapshot(
          grade: snapshot.grade,
          answers: snapshot.answers,
          targetConceptCode: target,
        );
      });
      // Validate reachable order before exposing a selectable path.
      for (final code in availableConcepts) {
        loaded.pathTo(code);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          graph = null;
          graphError = learningError(e);
          snapshot = ConceptCheckSnapshot(
            grade: snapshot.grade,
            answers: snapshot.answers,
          );
        });
      }
    }
    try {
      final states = await repo.all('/api/v1/me/skill-states');
      if (mounted) {
        setState(() {
          skillStates = {
            for (final s in states)
              if (s['skill_code'] is String) s['skill_code']: s,
          };
          stateError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => stateError = '학습 기록을 불러오지 못했어요. 개념 체크는 계속할 수 있어요.');
      }
    }
  }

  Future<void> _choose(String value) async {
    if (saving || userId == null || selected.isEmpty) return;
    final updated = ConceptCheckSnapshot(
      grade: snapshot.grade,
      answers: {...snapshot.answers, selected[index].id: value},
      targetConceptCode: snapshot.targetConceptCode,
    );
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await store.save(userId!, updated);
      if (mounted) setState(() => snapshot = updated);
    } catch (_) {
      if (mounted) setState(() => error = '기록을 저장하지 못했어요. 다시 선택해 주세요.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _verify() async {
    if (busy || userId == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final history = LearningRepository.items(
        await repo.get('/api/v1/me/diagnostics', {'page': '1', 'size': '100'}),
      );
      final active = history.where((s) => s['status'] == 'IN_PROGRESS');
      JsonMap next;
      if (active.isNotEmpty) {
        next = await repo.get('/api/v1/diagnostics/${active.first['id']}');
      } else {
        await repo.patch('/api/v1/me/student-profile', {
          'grade_level': gradeName(snapshot.grade),
        });
        next = await repo.post('/api/v1/diagnostics');
      }
      if (!mounted) return;
      setState(() {
        session = next;
        mode = 'quiz';
        selectedChoice = null;
        answer.clear();
      });
      if (next['status'] == 'COMPLETED') await _loadResults();
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _loadResults() async {
    final data = await repo.get(
      '/api/v1/diagnostics/${session!['id']}/results',
    );
    LearningRepository.notifyProgressChanged();
    if (mounted) {
      setState(() {
        results = data;
        mode = 'verified';
      });
    }
  }

  Future<void> _practiceSkill(String code) async {
    if (busy || code.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await openRelatedPractice(context, repo, skillCode: code);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _submit() async {
    if (busy || session == null) return;
    final question = session!['current_question'];
    if (question is! Map) return;
    final input = AnswerInput.fromJson(question);
    final value = input.isChoice ? selectedChoice ?? '' : answer.text.trim();
    if (input.missingChoices || !input.accepts(value)) {
      setState(
        () => error = input.isChoice
            ? '보기를 선택해 주세요.'
            : input.isNumeric
            ? '숫자 또는 기약분수로 입력해 주세요. 예: -2, 0.5, 3/2'
            : '답안을 입력해 주세요.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await repo.post(
        '/api/v1/diagnostics/${session!['id']}/answers',
        {'question_id': question['question_id'], 'answer': value},
      );
      if (!mounted) return;
      setState(() {
        session = next;
        answer.clear();
        selectedChoice = null;
      });
      if (next['status'] == 'COMPLETED') await _loadResults();
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _close() {
    if (!saving) Navigator.pop(context, snapshot);
  }

  Widget _diagnosticAnswer(Map question) {
    final input = AnswerInput.fromJson(question);
    if (input.missingChoices) {
      return card(
        const Text(
          '이 문제의 보기를 준비 중이에요. 현재는 답안을 제출할 수 없어요. 잠시 후 진단을 이어서 진행해 주세요.',
          style: TextStyle(height: 1.6),
        ),
        color: light,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (input.isChoice)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < input.choices.length; i++)
                ChoiceChip(
                  label: Text('${i + 1}) ${input.choices[i].label}'),
                  selected: selectedChoice == input.choices[i].value,
                  selectedColor: light,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                          selectedChoice = input.choices[i].value;
                          error = null;
                        }),
                ),
            ],
          )
        else
          TextField(
            controller: answer,
            enabled: !busy,
            maxLength: 200,
            inputFormatters: input.isNumeric
                ? [NumericAnswerFormatter()]
                : null,
            autocorrect: !input.isNumeric,
            maxLines: input.isNumeric ? 1 : 3,
            decoration: InputDecoration(
              labelText: input.isNumeric ? '숫자 답안' : '답안',
              hintText: input.isNumeric ? '예: -2, 0.5, 3/2 (분수는 기약분수)' : null,
              helperText: question['input_guidance'] is String
                  ? question['input_guidance']
                  : null,
              helperMaxLines: 3,
              border: const OutlineInputBorder(),
            ),
          ),
        const SizedBox(height: 12),
        primary(
          '답안 제출',
          busy || (input.isChoice && selectedChoice == null) ? null : _submit,
        ),
      ],
    );
  }

  String _stateLabel(String code) {
    if (stateError != null) return '서버 학습 기록 확인 불가';
    final score = skillStates[code]?['mastery_score'];
    return score is num ? '서버 숙련도: $score' : '서버 진단 전';
  }

  Widget _pathPreview() {
    final items = selected;
    final targets =
        graph!.conceptSkills[snapshot.targetConceptCode] ?? <String>[];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: card(
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text(
            '이 단원까지 이어지는 개념',
            style: TextStyle(
              color: purple,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            '선수관계 순서 · ${items.length}개 Skill',
            style: const TextStyle(fontSize: 12),
          ),
          children: [
            if (stateError != null)
              Text(stateError!, style: const TextStyle(fontSize: 12)),
            for (int i = 0; i < items.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: light,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: purple, fontSize: 12),
                  ),
                ),
                title: Text(
                  items[i].title,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  [
                    targets.contains(items[i].skillCode) ? '현재 단원' : '선수개념',
                    _stateLabel(items[i].skillCode!),
                    if ((graph!.prerequisites[items[i].skillCode] ?? [])
                        .isNotEmpty)
                      '먼저: ${(graph!.prerequisites[items[i].skillCode]!).map((code) => graph!.skills[code]!['name']).join(', ')}',
                  ].join('\n'),
                  style: const TextStyle(fontSize: 11, height: 1.6),
                ),
              ),
          ],
        ),
        color: light,
      ),
    );
  }

  Widget card(Widget child, {Color color = Colors.white}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE7DDFB)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  Widget primary(String text, VoidCallback? onTap) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onTap,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final concepts = selected;
    final answered = concepts
        .where((c) => snapshot.answers.containsKey(c.id))
        .length;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: const Color(0xFFFAF8FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 660,
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: Row(
                children: [
                  const CrewmateMascotBadge(
                    size: 34,
                    suitColor: Color(0xFFCBB2FC),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '내 개념 레벨테스트',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: saving ? null : _close,
                    tooltip: '레벨테스트 닫기',
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (busy) const LinearProgressIndicator(color: purple),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (error != null) ...[
                      card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              error!,
                              style: const TextStyle(height: 1.6, color: ink),
                            ),
                            if (userId == null)
                              TextButton(
                                onPressed: busy ? null : _initialize,
                                child: const Text('다시 불러오기'),
                              ),
                            if (session?['status'] == 'COMPLETED' &&
                                results == null)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () async {
                                        setState(() => busy = true);
                                        try {
                                          await _loadResults();
                                        } catch (e) {
                                          if (mounted) {
                                            setState(
                                              () => error = learningError(e),
                                            );
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => busy = false);
                                          }
                                        }
                                      },
                                child: const Text('결과 다시 불러오기'),
                              ),
                          ],
                        ),
                        color: light,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (mode == 'diagnosis') ...[
                      card(
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '문제로 확인하는\n내 수학 개념',
                              style: TextStyle(
                                fontSize: 23,
                                height: 1.4,
                                fontWeight: FontWeight.w900,
                                color: ink,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              '기초 문제를 직접 풀고, 기억하는 개념과 복습할 부분을 확인해요.',
                              style: TextStyle(height: 1.7),
                            ),
                          ],
                        ),
                        color: light,
                      ),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<int>(
                        initialValue: snapshot.grade,
                        decoration: const InputDecoration(
                          labelText: '현재 학년',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (int grade = 6; grade <= 12; grade++)
                            DropdownMenuItem(
                              value: grade,
                              child: Text(
                                grade == 6 ? '초등 기초' : gradeName(grade),
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (grade) => setState(
                                () => snapshot = ConceptCheckSnapshot(
                                  grade: grade ?? snapshot.grade,
                                  answers: snapshot.answers,
                                ),
                              ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '현재 학년 기준의 진단이에요. 선택 단원만 지정하는 진단은 아직 지원되지 않아요. 진행 중인 진단은 이어서 풀 수 있어요.',
                        style: TextStyle(
                          height: 1.6,
                          color: Color(0xFF777777),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 18),
                      primary(
                        '기초 문제로 진단하기',
                        busy || userId == null ? null : _verify,
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => mode = 'setup'),
                        child: const Text('개념 자가 체크'),
                      ),
                    ],
                    if (mode == 'setup') ...[
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => mode = 'diagnosis'),
                        child: const Text('문제 진단으로 돌아가기'),
                      ),
                      card(
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '내가 배운 개념,\n얼마나 기억할까요?',
                              style: TextStyle(
                                fontSize: 23,
                                height: 1.4,
                                fontWeight: FontWeight.w900,
                                color: ink,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              '선택 기능인 개념 자가 체크예요.\n내가 느끼는 이해도를 기록하고 선수개념을 살펴볼 수 있어요.',
                              style: TextStyle(
                                height: 1.7,
                                color: Color(0xFF777777),
                              ),
                            ),
                          ],
                        ),
                        color: light,
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<int>(
                        key: ValueKey(snapshot.grade),
                        initialValue: snapshot.grade,
                        decoration: const InputDecoration(
                          labelText: '현재 학년',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (int grade = 6; grade <= 12; grade++)
                            DropdownMenuItem(
                              value: grade,
                              child: Text(
                                grade == 6 ? '초등 기초' : gradeName(grade),
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(
                                () => snapshot = ConceptCheckSnapshot(
                                  grade: value ?? 10,
                                  answers: snapshot.answers,
                                ),
                              ),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                          'target:${snapshot.grade}:${snapshot.targetConceptCode}:${graph != null}',
                        ),
                        initialValue: snapshot.targetConceptCode ?? '',
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '지금 배우는 단원',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('단원 선택 없이 학년 기준으로'),
                          ),
                          for (final code in availableConcepts)
                            DropdownMenuItem(
                              value: code,
                              child: Text(
                                '${graph!.concepts[code]!['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (value) => setState(() {
                                snapshot = ConceptCheckSnapshot(
                                  grade: snapshot.grade,
                                  answers: snapshot.answers,
                                  targetConceptCode: value == '' ? null : value,
                                );
                                index = 0;
                              }),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        graphError != null
                            ? '단원 연결을 불러오지 못했어요. 학년 기준 자가 체크를 이용할 수 있어요.'
                            : availableConcepts.isEmpty
                            ? '이 과정의 서버 선수개념 연결은 준비 중이에요. 아래에서는 앱에 등록된 개념을 자가 체크해요.'
                            : '현재 서버에 등록된 단원은 공통수학1이에요. 단원을 고르면 필요한 선수개념부터 차례로 체크해요.',
                        style: const TextStyle(
                          color: Color(0xFF777777),
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      if (graphError != null)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => busy = true);
                                  await _loadGraph();
                                  if (mounted) setState(() => busy = false);
                                },
                          child: const Text('단원 연결 다시 불러오기'),
                        ),
                      if (snapshot.targetConceptCode != null) _pathPreview(),
                      const SizedBox(height: 14),
                      Text(
                        '${snapshot.targetConceptCode == null ? '학년 기준 자가 체크' : '선수개념과 현재 단원'} ${concepts.length}개 · $answered개 체크됨',
                        style: const TextStyle(
                          color: Color(0xFF777777),
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      primary(
                        answered > 0 ? '개념 체크 이어하기' : '배웠던 개념 체크하기',
                        busy || saving || userId == null || concepts.isEmpty
                            ? null
                            : () async {
                                setState(() => saving = true);
                                try {
                                  await store.save(userId!, snapshot);
                                  if (!mounted) return;
                                  setState(() {
                                    index = concepts.indexWhere(
                                      (c) =>
                                          !snapshot.answers.containsKey(c.id),
                                    );
                                    if (index < 0) index = 0;
                                    mode = 'check';
                                  });
                                } catch (_) {
                                  if (mounted) {
                                    setState(
                                      () => error =
                                          '선택한 범위를 저장하지 못했어요. 다시 시도해 주세요.',
                                    );
                                  }
                                } finally {
                                  if (mounted) setState(() => saving = false);
                                }
                              },
                      ),
                      if (answered > 0)
                        TextButton(
                          onPressed: () => setState(() => mode = 'summary'),
                          child: const Text('내 체크 결과 보기'),
                        ),
                    ],
                    if (mode == 'check' && concepts.isNotEmpty) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${index + 1} / ${concepts.length} 개념',
                              style: const TextStyle(
                                color: purple,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => setState(() => mode = 'summary'),
                            child: const Text('여기까지 정리하기'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: answered / concepts.length,
                        color: purple,
                        backgroundColor: light,
                      ),
                      const SizedBox(height: 20),
                      card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${concepts[index].area} · ${gradeName(concepts[index].grade)}',
                              style: const TextStyle(
                                color: purple,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              concepts[index].unit,
                              style: const TextStyle(
                                color: Color(0xFF777777),
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SelectableText(
                              concepts[index].title,
                              style: const TextStyle(
                                fontSize: 19,
                                height: 1.6,
                                fontWeight: FontWeight.w800,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (concepts[index].skillCode != null)
                              Text(
                                _stateLabel(concepts[index].skillCode!),
                                style: const TextStyle(
                                  color: purple,
                                  fontSize: 12,
                                  height: 1.6,
                                ),
                              ),
                            const Text(
                              '이 개념을 설명하거나 문제에 활용할 수 있나요?',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: Color(0xFF777777),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final entry in {
                        'known': '알아요',
                        'unsure': '헷갈려요',
                        'unknown': '모르겠어요',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: OutlinedButton.icon(
                            onPressed: saving ? null : () => _choose(entry.key),
                            icon: Icon(
                              snapshot.answers[concepts[index].id] == entry.key
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              size: 20,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: purple,
                              backgroundColor:
                                  snapshot.answers[concepts[index].id] ==
                                      entry.key
                                  ? light
                                  : Colors.white,
                              padding: const EdgeInsets.all(16),
                              side: BorderSide(
                                color:
                                    snapshot.answers[concepts[index].id] ==
                                        entry.key
                                    ? purple
                                    : const Color(0xFFDDD5EE),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            label: Text(entry.value),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: index > 0 && !saving
                                  ? () => setState(() => index--)
                                  : null,
                              child: const Text('이전 개념'),
                            ),
                          ),
                          Expanded(
                            child: FilledButton(
                              onPressed: saving
                                  ? null
                                  : () => setState(() {
                                      if (index + 1 < concepts.length) {
                                        index++;
                                      } else {
                                        mode = 'summary';
                                      }
                                    }),
                              style: FilledButton.styleFrom(
                                backgroundColor: purple,
                              ),
                              child: Text(
                                index + 1 < concepts.length
                                    ? '다음 개념'
                                    : '체크 결과 보기',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (mode == 'summary') ...[
                      card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '나의 개념 탐사 기록',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: ink,
                              ),
                            ),
                            const SizedBox(height: 16),
                            for (final entry in {
                              'known': '알아요',
                              'unsure': '헷갈려요',
                              'unknown': '모르겠어요',
                            }.entries)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Text(
                                  '${entry.value}  ${snapshot.count(entry.key, concepts)}개',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            Text(
                              '아직 체크하지 않은 개념 ${concepts.length - answered}개',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF777777),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              '내가 느끼는 이해도 기록이에요. 이 체크만으로 숙련 완료나 XP가 지급되지는 않아요.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: Color(0xFF777777),
                              ),
                            ),
                          ],
                        ),
                        color: light,
                      ),
                      const SizedBox(height: 16),
                      for (final c in concepts.where(
                        (c) => [
                          'unsure',
                          'unknown',
                        ].contains(snapshot.answers[c.id]),
                      ))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.auto_awesome_rounded,
                            color: purple,
                          ),
                          title: Text(c.title),
                          subtitle: Text(
                            '${c.area} · ${snapshot.answers[c.id] == 'unsure' ? '헷갈려요' : '모르겠어요'}',
                          ),
                        ),
                      const SizedBox(height: 16),
                      primary('확인 문제 풀기', busy ? null : _verify),
                      const SizedBox(height: 8),
                      const Text(
                        '확인 문제는 현재 학년 기준의 서버 진단이에요. 선택 단원만 지정하는 진단은 아직 지원되지 않아요. 진행 중인 진단이 있으면 이어서 풀어요.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777777),
                          height: 1.6,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => mode = 'setup'),
                        child: const Text('학년·단원 다시 선택하기'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => mode = 'check'),
                        child: const Text('개념 체크 수정하기'),
                      ),
                      OutlinedButton(
                        onPressed: _close,
                        child: const Text('계통도로 돌아가기'),
                      ),
                    ],
                    if (mode == 'quiz' && session != null) ...[
                      Text(
                        '확인 문제 · ${session!['answered_count'] ?? 0}문항 응답 완료',
                        style: const TextStyle(
                          color: purple,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (session!['status'] == 'IN_PROGRESS' &&
                          session!['current_question'] is Map) ...[
                        card(
                          SelectableText(
                            '${session!['current_question']['prompt'] ?? '문제를 준비하고 있어요.'}',
                            style: const TextStyle(fontSize: 18, height: 1.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _diagnosticAnswer(session!['current_question'] as Map),
                      ] else
                        const Text(
                          '현재 진단 상태를 확인해 주세요. 아래에서 내 개념 체크로 돌아갈 수 있어요.',
                        ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => mode = 'diagnosis'),
                        child: const Text('진단 시작 화면으로'),
                      ),
                    ],
                    if (mode == 'verified' && results != null) ...[
                      card(
                        const Column(
                          children: [
                            CrewmateMascotBadge(size: 62),
                            SizedBox(height: 12),
                            Text(
                              '확인 문제 진단 완료!',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                color: ink,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              '이번에 확인한 개념과 보완할 부분을 살펴보세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(height: 1.6),
                            ),
                          ],
                        ),
                        color: light,
                      ),
                      const SizedBox(height: 16),
                      for (final s in LearningRepository.items(
                        results!,
                        'assessed',
                      ))
                        ListTile(
                          title: Text('${s['skill_code']}'),
                          subtitle: Text(
                            s['mastery'] == null
                                ? '아직 평가되지 않았어요'
                                : '숙련도 ${((s['mastery'] as num) * 100).round()}%',
                          ),
                        ),
                      Text(
                        '아직 평가되지 않은 Skill: ${(results!['unassessed_skill_codes'] as List? ?? []).length}개',
                      ),
                      if (results!['weak_skill_codes'] is List &&
                          (results!['weak_skill_codes'] as List)
                              .whereType<String>()
                              .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          '복습할 개념 연습하기',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: purple,
                          ),
                        ),
                        for (final code
                            in (results!['weak_skill_codes'] as List)
                                .whereType<String>()
                                .toSet())
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => _practiceSkill(code),
                              icon: const Icon(Icons.edit_note_rounded),
                              label: Text(
                                '${graph?.skills[code]?['name'] ?? code} 연습하기',
                              ),
                            ),
                          ),
                      ],
                      const SizedBox(height: 16),
                      primary('계통도로 돌아가기', _close),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String gradeName(int grade) => grade <= 6
    ? '초등'
    : grade <= 9
    ? '중${grade - 6}'
    : '고${grade - 9}';
