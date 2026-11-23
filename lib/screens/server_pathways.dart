import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import 'server_learning.dart';
import 'problem_screen.dart';
import '../services/question_service.dart';

class ServerContentScreen extends StatefulWidget {
  final int contentId;
  final LearningRepository? repository;
  final Future<bool> Function(Uri)? launcher;
  const ServerContentScreen({
    super.key,
    required this.contentId,
    this.repository,
    this.launcher,
  });
  @override
  State<ServerContentScreen> createState() => _ServerContentScreenState();
}

class _ServerContentScreenState extends State<ServerContentScreen> {
  late final repo = widget.repository ?? LearningRepository();
  int? _session;
  bool _busy = false, _completed = false, _allowExit = false;
  Timer? _progressTimer;
  final _watch = Stopwatch();
  Future<void> _open(JsonMap data) async {
    if (_busy) return;
    final uri = Uri.tryParse('${data['url']}');
    if (uri == null || !['http', 'https'].contains(uri.scheme)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('열 수 없는 콘텐츠 주소입니다.')));
      return;
    }
    setState(() => _busy = true);
    try {
      // Open immediately from the user's click so browser popup rules allow it.
      if (!await (widget.launcher ??
          ((uri) =>
              launchUrl(uri, mode: LaunchMode.externalApplication)))(uri)) {
        throw const FormatException('콘텐츠를 열지 못했어요.');
      }
      _session ??=
          (await repo.post('/api/v1/content-learning-sessions', {
                'content_id': widget.contentId,
              }))['id']
              as int;
      _watch.start();
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted && !_busy && !_completed) _saveProgress();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProgress() async {
    if (_busy || _session == null || _completed) return;
    setState(() => _busy = true);
    try {
      await repo.patch('/api/v1/content-learning-sessions/$_session', {
        'progress_seconds': _watch.elapsed.inSeconds,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_session != null && !_completed) {
        await repo.patch('/api/v1/content-learning-sessions/$_session', {
          'progress_seconds': _watch.elapsed.inSeconds,
        });
      }
      if (!mounted) return;
      setState(() {
        _allowExit = true;
        _busy = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('진행 저장에 실패했어요. 다시 뒤로가기를 눌러 주세요.')),
        );
      }
    }
  }

  Future<void> _complete() async {
    if (_busy || _session == null || _completed) return;
    setState(() => _busy = true);
    try {
      final result = await repo.patch(
        '/api/v1/content-learning-sessions/$_session',
        {'progress_seconds': _watch.elapsed.inSeconds, 'completed': true},
      );
      LearningRepository.notifyProgressChanged();
      if (!mounted) return;
      setState(
        () => _completed =
            result['status'] == 'COMPLETED' || result['completed_at'] != null,
      );
      await showServerRewards(context, result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _watch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowExit || (_session == null && !_busy),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('학습 자료'),
        leading: BackButton(onPressed: _busy ? null : _close),
      ),
      body: ServerPanel(
        load: () => repo.get('/api/v1/learning-contents/${widget.contentId}'),
        builder: (context, data) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data['title']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            if (data['description'] != null)
              SelectableText('${data['description']}'),
            FilledButton(
              onPressed: _busy ? null : () => _open(data),
              child: Text(_busy ? '처리 중…' : '학습 자료 열기'),
            ),
            if (_session != null)
              OutlinedButton(
                onPressed: _busy || _completed ? null : _complete,
                child: Text(_completed ? '학습 완료' : '자료 학습 완료 기록'),
              ),
            if (_session != null && !_completed)
              TextButton(
                onPressed: _busy ? null : _saveProgress,
                child: const Text('진행 저장'),
              ),
            const Text('자료를 학습한 뒤 완료를 눌러 주세요.'),
          ],
        ),
      ),
    ),
  );
}

class ServerRoadmapScreen extends StatefulWidget {
  final LearningRepository? repository;
  const ServerRoadmapScreen({super.key, this.repository});
  @override
  State<ServerRoadmapScreen> createState() => _ServerRoadmapScreenState();
}

class _ServerRoadmapScreenState extends State<ServerRoadmapScreen> {
  late final repo = widget.repository ?? LearningRepository();
  int _revision = 0;
  int _polls = 0;
  Timer? _pollTimer;
  Future<JsonMap> _loadRoadmap() async {
    JsonMap data;
    try {
      data = await repo.get('/api/v1/me/roadmap');
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      data = {'steps': []};
    }
    if (!mounted) return data;
    _pollTimer?.cancel();
    if ([
          'PENDING',
          'GENERATING',
          'PROCESSING',
          'QUEUED',
        ].contains(data['status']) &&
        _polls++ < 60) {
      _pollTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _revision++);
      });
    }
    return data;
  }

  @override
  void initState() {
    super.initState();
    LearningRepository.progressRevision.addListener(_refresh);
  }

  void _refresh() {
    if (!mounted) return;
    _pollTimer?.cancel();
    _polls = 0;
    setState(() => _revision++);
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_refresh);
    _pollTimer?.cancel();
    super.dispose();
  }

  bool _busy = false;
  Future<void> _change(bool replan) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await repo.post(
        replan ? '/api/v1/me/roadmap/replan' : '/api/v1/me/roadmap/generate',
        replan ? {'reason': 'STUDENT_REQUEST'} : {'goal_skill_codes': []},
      );
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('나의 학습 로드맵')),
    backgroundColor: Colors.white,
    body: Column(
      children: [
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy ? null : () => _change(false),
              child: const Text('로드맵 생성'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _change(true),
              child: const Text('다시 계획하기'),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ServerRoadmapHistory(repository: repo),
                ),
              ),
              child: const Text('이전 로드맵'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
          child: ServerPanel(
            key: ValueKey(_revision),
            load: _loadRoadmap,
            builder: (context, data) => _roadmapBody(context, data, repo),
          ),
        ),
      ],
    ),
  );
}

Widget _roadmapBody(
  BuildContext context,
  JsonMap data,
  LearningRepository repo, {
  bool interactive = true,
}) {
  final progress = data['progress'];
  final steps = LearningRepository.items(data, 'steps');
  final next = steps
      .where((step) => step['skill_code'] == data['next_skill_code'])
      .firstOrNull;
  if (steps.isEmpty) {
    return learningCard(
      '내 학습 로드맵',
      Text(
        [
              'PENDING',
              'GENERATING',
              'PROCESSING',
              'QUEUED',
            ].contains(data['status'])
            ? '학습 계획을 준비하고 있어요.'
            : data['completed'] == true
            ? '학습 계획 완료!'
            : data['status'] == 'FAILED'
            ? '학습 계획을 준비하지 못했어요. 다시 계획하기를 눌러 주세요.'
            : '아직 학습 계획이 없어요. 로드맵 생성을 눌러 시작해 보세요.',
      ),
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        data['completed'] == true
            ? '학습 계획 완료!'
            : '${data['reason'] ?? '맞춤 학습 계획'}',
      ),
      if (progress is Map) ...[
        Text(
          '${progress['completed_steps']} / ${progress['total_steps']} 단계 완료',
        ),
        LinearProgressIndicator(
          value: ((progress['rate'] as num?)?.toDouble() ?? 0).clamp(0, 1),
        ),
      ],
      if (next != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            '다음 학습: ${next['skill_name'] ?? '추천 개념'}',
            style: const TextStyle(
              color: learningPurple,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      for (final step in steps)
        Card(
          color: const Color(0xFFF5F1FF),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: ListTile(
            leading: Icon(
              step['completed'] == true
                  ? Icons.check_circle
                  : step['ready'] == true
                  ? Icons.play_circle
                  : Icons.lock_outline,
            ),
            title: Text(
              '${step['order']}. ${step['skill_name'] ?? step['skill_code']}',
            ),
            subtitle: Text('${step['reason'] ?? ''}'),
            onTap: !interactive || step['id'] is! int
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('학습 단계')),
                        body: ValueListenableBuilder<int>(
                          valueListenable: LearningRepository.progressRevision,
                          builder: (context, revision, child) => ServerPanel(
                            key: ValueKey(revision),
                            load: () => repo.get(
                              '/api/v1/me/roadmap/steps/${step['id']}',
                            ),
                            builder: (context, detail) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${detail['skill_name'] ?? detail['skill_code']}',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text('${detail['reason'] ?? ''}'),
                                if (detail['mastery'] != null)
                                  Text(
                                    '숙련도: ${((detail['mastery'] as num) * 100).round()}%',
                                  ),
                                for (final id
                                    in detail['content_ids'] is List
                                        ? detail['content_ids']
                                        : [])
                                  ListTile(
                                    title: const Text('관련 학습 자료'),
                                    trailing: const Icon(Icons.open_in_new),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => ServerContentScreen(
                                          contentId: id,
                                          repository: repo,
                                        ),
                                      ),
                                    ),
                                  ),
                                FilledButton(
                                  onPressed:
                                      detail['skill_code'] is String &&
                                          (detail['ready'] == true ||
                                              detail['completed'] == true)
                                      ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => ProblemScreen(
                                              topic:
                                                  '${detail['skill_name'] ?? '로드맵 연습'}',
                                              repository: repo,
                                              questionService:
                                                  ServerQuestionService(
                                                    unit:
                                                        '${detail['skill_name'] ?? '로드맵 연습'}',
                                                    skillCode:
                                                        detail['skill_code'],
                                                    repository: repo,
                                                  ),
                                            ),
                                          ),
                                        )
                                      : null,
                                  child: const Text('이 개념 문제 풀기'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
    ],
  );
}

class ServerRoadmapHistory extends StatelessWidget {
  final LearningRepository? repository;
  const ServerRoadmapHistory({super.key, this.repository});
  @override
  Widget build(BuildContext context) {
    final repo = repository ?? LearningRepository();
    return Scaffold(
      appBar: AppBar(title: const Text('이전 로드맵')),
      body: ServerPanel(
        load: () async => {
          'items': await repo.all('/api/v1/me/roadmap/history'),
        },
        builder: (context, data) => Column(
          children: [
            if (LearningRepository.items(data).isEmpty)
              const Text('이전 로드맵이 없어요.'),
            for (final item in LearningRepository.items(data))
              ExpansionTile(
                title: Text('학습 계획 ${item['version']}'),
                children: [
                  _roadmapBody(context, item, repo, interactive: false),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class ServerDiagnosticScreen extends StatefulWidget {
  const ServerDiagnosticScreen({super.key});
  @override
  State<ServerDiagnosticScreen> createState() => _ServerDiagnosticScreenState();
}

class _ServerDiagnosticScreenState extends State<ServerDiagnosticScreen> {
  final repo = LearningRepository();
  final _answer = TextEditingController();
  JsonMap? _session, _results;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _resume();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    try {
      final list = LearningRepository.items(
        await repo.get('/api/v1/me/diagnostics', {'page': '1', 'size': '20'}),
      );
      final active = list.where((s) => s['status'] == 'IN_PROGRESS');
      if (active.isNotEmpty) {
        _session = await repo.get('/api/v1/diagnostics/${active.first['id']}');
      }
    } catch (e) {
      _error = learningError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _advance() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      JsonMap next;
      if (_session == null) {
        next = await repo.post('/api/v1/diagnostics');
      } else {
        final q = _session!['current_question'];
        if (q is! Map || _answer.text.trim().isEmpty) {
          throw const FormatException('답안을 입력해 주세요.');
        }
        next = await repo.post(
          '/api/v1/diagnostics/${_session!['id']}/answers',
          {'question_id': q['question_id'], 'answer': _answer.text.trim()},
        );
      }
      _session = next;
      _answer.clear();
      if (next['status'] == 'COMPLETED') {
        _results = await repo.get('/api/v1/diagnostics/${next['id']}/results');
      }
    } catch (e) {
      _error = learningError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final question = _session?['current_question'];
    return Scaffold(
      appBar: AppBar(title: const Text('학습 진단')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (_session == null) ...[
            const Text('마이페이지에서 학년을 설정한 뒤 진단해 주세요. 중단한 진단이 있으면 이어서 진행합니다.'),
            FilledButton(
              onPressed: _busy ? null : _advance,
              child: const Text('진단 시작'),
            ),
          ] else if (_session!['status'] == 'IN_PROGRESS') ...[
            Text('${_session!['answered_count']}문항 응답 완료'),
            if (question is Map)
              SelectableText('${question['prompt'] ?? '문제를 준비하고 있어요.'}'),
            TextField(
              controller: _answer,
              maxLength: 200,
              decoration: const InputDecoration(labelText: '답안'),
            ),
            FilledButton(
              onPressed: _busy ? null : _advance,
              child: const Text('답안 제출'),
            ),
          ] else if (_results != null) ...[
            const Text(
              '진단 완료!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            for (final skill in LearningRepository.items(_results!, 'assessed'))
              ListTile(
                title: Text('${skill['skill_code']}'),
                subtitle: Text(
                  skill['mastery'] == null
                      ? '아직 평가되지 않았어요'
                      : '숙련도 ${((skill['mastery'] as num) * 100).round()}%',
                ),
              ),
            Text(
              '보완할 Skill: ${(_results!['weak_skill_codes'] as List?)?.join(', ') ?? '없음'}',
            ),
            FilledButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const ServerRoadmapScreen(),
                ),
              ),
              child: const Text('나의 로드맵 보기'),
            ),
          ] else
            const Text('이 진단은 종료됐어요. 뒤로 돌아가 새 진단을 시작해 주세요.'),
        ],
      ),
    );
  }
}
