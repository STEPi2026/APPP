import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import 'learning_support_screen.dart';
import 'server_capture.dart';

const learningPurple = Color(0xFF7C5CFA);

Widget learningCard(String title, Widget child) => Card(
  margin: const EdgeInsets.only(bottom: 16),
  child: Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  ),
);

Future<void> showServerRewards(BuildContext context, JsonMap result) async {
  final rewards = result['rewards'];
  if (rewards is! Map) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(rewards['level_up'] == true ? '레벨이 올랐어요!' : '학습 결과'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('획득 XP: ${rewards['xp'] ?? 0}'),
            for (final badge
                in rewards['new_badges'] is List ? rewards['new_badges'] : [])
              ListTile(
                leading: Image.asset(
                  'img/badges/${badge['code']}.png',
                  width: 48,
                  height: 48,
                  errorBuilder: (_, error, stack) =>
                      const Icon(Icons.workspace_premium),
                ),
                title: Text('${badge['name'] ?? '새 배지'}'),
              ),
            for (final quest
                in rewards['completed_quests'] is List
                    ? rewards['completed_quests']
                    : [])
              Text('퀘스트 완료: ${quest['title']}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

class ServerPanel extends StatefulWidget {
  final Future<JsonMap> Function() load;
  final Widget Function(BuildContext, JsonMap) builder;
  const ServerPanel({super.key, required this.load, required this.builder});
  @override
  State<ServerPanel> createState() => _ServerPanelState();
}

class _ServerPanelState extends State<ServerPanel> {
  late Future<JsonMap> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  Future<void> _reload() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<JsonMap>(
    future: _future,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (s.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(learningError(s.error!)),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('다시 시도')),
              ],
            ),
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [widget.builder(context, s.data!)],
        ),
      );
    },
  );
}

class ServerProblemScreen extends StatefulWidget {
  final int problemId;
  final LearningRepository? repository;
  const ServerProblemScreen({
    super.key,
    required this.problemId,
    this.repository,
  });
  @override
  State<ServerProblemScreen> createState() => _ServerProblemScreenState();
}

class _ServerProblemScreenState extends State<ServerProblemScreen> {
  late final LearningRepository repo;
  ServerProblem? _problem;
  final _answer = TextEditingController();
  final _clock = Stopwatch()..start();
  final List<List<Offset>> _strokes = [];
  int? _session;
  int _helpCount = 0;
  bool _busy = false, _loading = true, _allowExit = false;
  String? _error;
  JsonMap? _attempt;
  @override
  void initState() {
    super.initState();
    repo = widget.repository ?? LearningRepository();
    _load();
  }

  @override
  void dispose() {
    _answer.dispose();
    _clock.stop();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await repo.problem(widget.problemId);
      if (mounted) {
        setState(() {
          _problem = p;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = learningError(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_busy || _answer.text.trim().isEmpty || _attempt != null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _session ??= await repo.startSession();
      final result = await repo.submit(
        sessionId: _session!,
        problemId: widget.problemId,
        answer: _answer.text,
        seconds: _clock.elapsed.inSeconds,
        hintCount: _helpCount,
      );
      if (!mounted) return;
      setState(() => _attempt = result);
      await showServerRewards(context, result);
    } catch (e) {
      if (mounted) setState(() => _error = learningError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_session != null) await repo.finishSession(_session!);
      if (!mounted) return;
      setState(() {
        _allowExit = true;
        _busy = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '학습 종료를 저장하지 못했어요. 다시 뒤로가기를 눌러 주세요. ${learningError(e)}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _problem;
    return PopScope(
      canPop: _allowExit || (_session == null && !_busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('문제 풀기'),
          leading: BackButton(onPressed: _busy ? null : _close),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (p != null) ...[
                    learningCard(
                      p.code,
                      SelectableText(
                        p.question,
                        style: const TextStyle(fontSize: 18, height: 1.6),
                      ),
                    ),
                    if (p.type.toUpperCase() == 'OX' ||
                        p.type.toUpperCase() == 'TRUE_FALSE')
                      Wrap(
                        spacing: 12,
                        children: [
                          for (final value in ['O', 'X'])
                            ChoiceChip(
                              label: Text(value),
                              selected: _answer.text == value,
                              onSelected: _busy || _attempt != null
                                  ? null
                                  : (_) => setState(() => _answer.text = value),
                            ),
                        ],
                      ),
                    if (p.choices.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final choice in p.choices)
                            ChoiceChip(
                              label: Text(
                                '${choice['label'] ?? choice['text'] ?? choice['content'] ?? ''}',
                              ),
                              selected:
                                  _answer.text ==
                                  '${choice['value'] ?? choice['id'] ?? choice['label']}',
                              onSelected: _busy || _attempt != null
                                  ? null
                                  : (_) => setState(
                                      () => _answer.text =
                                          '${choice['value'] ?? choice['id'] ?? choice['label']}',
                                    ),
                            ),
                        ],
                      ),
                    TextField(
                      controller: _answer,
                      enabled: !_busy && _attempt == null,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 5000,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: '답안',
                        hintText: '구한 답 또는 보기 번호를 입력하세요',
                        helperText: p.inputGuidance,
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: const Text('연습장'),
                      children: [
                        SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: GestureDetector(
                            onPanStart: (d) =>
                                setState(() => _strokes.add([d.localPosition])),
                            onPanUpdate: (d) => setState(
                              () => _strokes.last.add(d.localPosition),
                            ),
                            child: CustomPaint(
                              painter: _ScratchPainter(_strokes),
                              size: Size.infinite,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(_strokes.clear),
                          child: const Text('필기 지우기'),
                        ),
                      ],
                    ),
                    if (_attempt == null)
                      FilledButton(
                        onPressed: _busy || _answer.text.trim().isEmpty
                            ? null
                            : _submit,
                        child: Text(_busy ? '제출 중…' : '제출하기'),
                      ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.lightbulb_outline),
                      label: const Text('모르겠어요'),
                      onPressed: _busy
                          ? null
                          : () async {
                              _helpCount++;
                              await Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => LearningSupportScreen(
                                    problemTitle: p.code,
                                    problemId: p.id,
                                  ),
                                ),
                              );
                            },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('풀이 사진 분석'),
                      onPressed: _busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const ServerCaptureScreen(),
                              ),
                            ),
                    ),
                    if (_attempt != null)
                      learningCard(
                        '풀이 결과',
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _attempt!['is_correct'] == true
                                  ? '정답이에요!'
                                  : _attempt!['is_correct'] == false
                                  ? '다시 풀어볼까요?'
                                  : '평가 결과를 확인하고 있어요.',
                            ),
                            if (_attempt!['score'] != null)
                              Text(
                                '점수: ${_attempt!['score']}${_attempt!['max_score'] != null ? ' / ${_attempt!['max_score']}' : ''}',
                              ),
                            if (_attempt!['points'] != null)
                              Text('획득 포인트: ${_attempt!['points']}'),
                            if (_attempt!['is_correct'] != true)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _attempt = null;
                                        _clock.reset();
                                      }),
                                child: const Text('다시 풀기'),
                              ),
                            TextButton(
                              onPressed: _busy ? null : _close,
                              child: const Text('학습 마치기'),
                            ),
                          ],
                        ),
                      ),
                  ],
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    if (p == null)
                      FilledButton(
                        onPressed: _load,
                        child: const Text('다시 시도'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _ScratchPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  _ScratchPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF5F1FF),
    );
    final pen = Paint()
      ..color = learningPurple
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final line in strokes) {
      for (int i = 1; i < line.length; i++) {
        canvas.drawLine(line[i - 1], line[i], pen);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ServerProblemList extends StatefulWidget {
  final String? skillCode;
  final LearningRepository? repository;
  const ServerProblemList({super.key, this.skillCode, this.repository});
  @override
  State<ServerProblemList> createState() => _ServerProblemListState();
}

class _ServerProblemListState extends State<ServerProblemList> {
  late final repo = widget.repository ?? LearningRepository();
  int page = 1;
  String type = '';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DropdownButtonFormField<String>(
          initialValue: type,
          decoration: const InputDecoration(labelText: '문제 유형'),
          items: const [
            DropdownMenuItem(value: '', child: Text('전체')),
            DropdownMenuItem(value: 'SHORT_ANSWER', child: Text('주관식')),
            DropdownMenuItem(value: 'MULTIPLE_CHOICE', child: Text('객관식')),
            DropdownMenuItem(value: 'OX', child: Text('OX')),
          ],
          onChanged: (value) => setState(() {
            type = value ?? '';
            page = 1;
          }),
        ),
      ),
      Expanded(
        child: ServerPanel(
          key: ValueKey('$page-$type-${widget.skillCode}'),
          load: () => repo.get('/api/v1/problems', {
            'page': '$page',
            'size': '20',
            if (type.isNotEmpty) 'problem_type': type,
            if (widget.skillCode != null) 'skill_code': widget.skillCode!,
          }),
          builder: (context, data) {
            final items = LearningRepository.items(data);
            return Column(
              children: [
                if (items.isEmpty) const Text('준비된 문제가 없어요.'),
                for (final item in items)
                  Card(
                    child: ListTile(
                      title: Text('${item['question']}'),
                      subtitle: Text(
                        '${item['problem_code']} · 난이도 ${item['difficulty']}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ServerProblemScreen(
                              problemId: item['id'],
                              repository: repo,
                            ),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: page > 1 ? () => setState(() => page--) : null,
                      child: const Text('이전'),
                    ),
                    Text('$page / ${data['total_pages'] ?? 1}'),
                    TextButton(
                      onPressed: page < (data['total_pages'] ?? 1)
                          ? () => setState(() => page++)
                          : null,
                      child: const Text('다음'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}
