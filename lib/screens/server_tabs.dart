import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import 'badge_collection.dart';
import 'server_learning.dart';
import 'server_pathways.dart';
import 'server_capture.dart';

void openLearningPage(BuildContext context, Widget page) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
String studyTime(dynamic value) {
  final d = DateTime.tryParse('$value');
  if (d == null) return '';
  return d.toUtc().add(const Duration(hours: 9)).toString().substring(0, 16);
}

String percent(dynamic value) =>
    value is num ? '${(value * 100).round()}%' : '아직 평가되지 않음';

class RemoteSection extends StatefulWidget {
  final Future<JsonMap> Function() load;
  final Widget Function(BuildContext, JsonMap) builder;
  const RemoteSection({super.key, required this.load, required this.builder});
  @override
  State<RemoteSection> createState() => _RemoteSectionState();
}

class _RemoteSectionState extends State<RemoteSection> {
  late Future<JsonMap> future;
  @override
  void initState() {
    super.initState();
    future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<JsonMap>(
    future: future,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        );
      }
      if (s.hasError) {
        return Column(
          children: [
            Text(learningError(s.error!)),
            TextButton(
              onPressed: () => setState(() => future = widget.load()),
              child: const Text('다시 불러오기'),
            ),
          ],
        );
      }
      return widget.builder(context, s.data!);
    },
  );
}

class ServerHomeTab extends StatefulWidget {
  const ServerHomeTab({super.key});
  @override
  State<ServerHomeTab> createState() => ServerHomeState();
}

class ServerHomeState extends State<ServerHomeTab> {
  final repo = LearningRepository();
  int revision = 0;
  Future<void> refresh() async {
    if (mounted) setState(() => revision++);
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: refresh,
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '오늘도 한 걸음씩, STEPi',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        learningCard(
          '나의 성장',
          RemoteSection(
            key: ValueKey('growth-$revision'),
            load: () => repo.get('/api/v1/me/achievements'),
            builder: (context, data) => Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                Text('Lv. ${data['level']}'),
                Text('누적 ${data['xp']} XP'),
                Text('연속 ${data['current_streak']}일'),
                Text('풀이 ${data['total_attempts']}회'),
                Text('획득 배지 ${data['badge_count']}개'),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _open(
                Scaffold(
                  appBar: AppBar(title: const Text('문제 풀기')),
                  body: const ServerProblemList(),
                ),
              ),
              icon: const Icon(Icons.edit_note),
              label: const Text('문제 풀기'),
            ),
            OutlinedButton(
              onPressed: () => _open(const ServerDiagnosticScreen()),
              child: const Text('학습 진단'),
            ),
            OutlinedButton(
              onPressed: () => _open(const ServerRoadmapScreen()),
              child: const Text('나의 로드맵'),
            ),
            OutlinedButton(
              onPressed: () => _open(const ServerRecordScreen(kind: 'wrong')),
              child: const Text('오답 복습'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        learningCard(
          '다음 추천 학습',
          RemoteSection(
            key: ValueKey('recommend-$revision'),
            load: () =>
                repo.get('/api/v1/me/content-recommendations', {'size': '5'}),
            builder: (context, data) => Column(
              children: [
                if (LearningRepository.items(data).isEmpty)
                  const Text('학습 기록이 쌓이면 추천 자료가 표시돼요.'),
                for (final content in LearningRepository.items(data))
                  ListTile(
                    title: Text('${content['title']}'),
                    subtitle: Text('${content['reason'] ?? ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _open(ServerContentScreen(contentId: content['id'])),
                  ),
              ],
            ),
          ),
        ),
        learningCard(
          '오늘의 퀘스트',
          RemoteSection(
            key: ValueKey('quests-$revision'),
            load: () => repo.get('/api/v1/me/quests'),
            builder: (context, data) => questItems(data),
          ),
        ),
      ],
    ),
  );
}

Widget questItems(JsonMap data) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (LearningRepository.items(data).isEmpty) const Text('등록된 퀘스트가 없어요.'),
    for (final q in LearningRepository.items(data))
      ListTile(
        leading: Icon(
          q['completed'] == true ? Icons.check_circle : Icons.flag_outlined,
        ),
        title: Text('${q['title']}'),
        subtitle: Text(
          '${q['progress'] ?? 0} / ${q['target']} · 보상 ${q['reward_xp']} XP',
        ),
      ),
    const Text('진행과 보상 지급은 학습 활동에 따라 서버에서 갱신돼요.'),
  ],
);

class ServerLearningTab extends StatelessWidget {
  const ServerLearningTab({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: '문제'),
            Tab(text: '학습 자료'),
            Tab(text: 'Skill'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              const ServerProblemList(),
              const ServerCatalogScreen(
                path: '/api/v1/learning-contents',
                kind: 'content',
              ),
              const ServerCatalogScreen(path: '/api/v1/skills', kind: 'skill'),
            ],
          ),
        ),
      ],
    ),
  );
}

class ServerCatalogScreen extends StatefulWidget {
  final String path, kind;
  const ServerCatalogScreen({
    super.key,
    required this.path,
    required this.kind,
  });
  @override
  State<ServerCatalogScreen> createState() => _ServerCatalogScreenState();
}

class _ServerCatalogScreenState extends State<ServerCatalogScreen> {
  final repo = LearningRepository();
  int page = 1;
  @override
  Widget build(BuildContext context) => ServerPanel(
    key: ValueKey('${widget.path}-$page'),
    load: () => repo.get(widget.path, {'page': '$page', 'size': '20'}),
    builder: (context, data) => Column(
      children: [
        if (LearningRepository.items(data).isEmpty)
          const Text('준비된 학습 자료가 없어요.'),
        for (final item in LearningRepository.items(data))
          Card(
            child: ListTile(
              title: Text(
                '${item['title'] ?? item['name'] ?? item['skill_name'] ?? item['code']}',
              ),
              subtitle: Text('${item['description'] ?? ''}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openLearningPage(
                context,
                widget.kind == 'content'
                    ? ServerContentScreen(contentId: item['id'])
                    : ServerSkillDetail(
                        code: '${item['code'] ?? item['skill_code']}',
                      ),
              ),
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
    ),
  );
}

class ServerReportTab extends StatelessWidget {
  const ServerReportTab({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = LearningRepository();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '나의 학습 리포트',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () =>
                  openLearningPage(context, const ServerRoadmapScreen()),
              child: const Text('로드맵'),
            ),
            OutlinedButton(
              onPressed: () =>
                  openLearningPage(context, const ServerDiagnosticScreen()),
              child: const Text('학습 진단'),
            ),
            OutlinedButton(
              onPressed: () => openLearningPage(
                context,
                const ServerRecordScreen(kind: 'history'),
              ),
              child: const Text('학습 기록'),
            ),
            OutlinedButton(
              onPressed: () => openLearningPage(
                context,
                const ServerRecordScreen(kind: 'wrong'),
              ),
              child: const Text('오답노트'),
            ),
            OutlinedButton(
              onPressed: () => openLearningPage(
                context,
                const ServerRecordScreen(kind: 'review'),
              ),
              child: const Text('복습할 문제'),
            ),
            OutlinedButton(
              onPressed: () =>
                  openLearningPage(context, const ServerKnowledgeScreen()),
              child: const Text('지식 지도'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        learningCard(
          '전체 학습',
          RemoteSection(
            load: () => repo.get('/api/v1/me/learning-summary'),
            builder: (context, data) => Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                Text('풀이 ${data['total_attempts']}회'),
                Text('정답 ${data['correct_attempts']}회'),
                Text('오답 ${data['incorrect_attempts']}회'),
                Text('정답률 ${percent(data['correct_rate'])}'),
              ],
            ),
          ),
        ),
        learningCard(
          'Skill별 숙련도',
          RemoteSection(
            load: () => repo.get('/api/v1/me/skill-states'),
            builder: (context, data) => Column(
              children: [
                if (LearningRepository.items(data).isEmpty)
                  const Text('아직 측정된 Skill이 없어요.'),
                for (final skill in LearningRepository.items(data))
                  ListTile(
                    title: Text('${skill['skill_name']}'),
                    subtitle: Text('숙련도 ${percent(skill['mastery_score'])}'),
                    onTap: () => openLearningPage(
                      context,
                      ServerSkillDetail(code: '${skill['skill_code']}'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        learningCard(
          '보완할 Skill',
          RemoteSection(
            load: () => repo.get('/api/v1/me/weak-skills'),
            builder: (context, data) => Column(
              children: [
                if (LearningRepository.items(data).isEmpty)
                  const Text('현재 표시할 취약 Skill이 없어요.'),
                for (final skill in LearningRepository.items(data))
                  ListTile(
                    title: Text(
                      '${skill['skill_name'] ?? skill['skill_code']}',
                    ),
                    onTap: () => openLearningPage(
                      context,
                      ServerSkillDetail(code: '${skill['skill_code']}'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ServerSkillDetail extends StatelessWidget {
  final String code;
  const ServerSkillDetail({super.key, required this.code});
  @override
  Widget build(BuildContext context) {
    final repo = LearningRepository();
    final safe = Uri.encodeComponent(code);
    return Scaffold(
      appBar: AppBar(title: Text(code)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          RemoteSection(
            load: () => repo.get('/api/v1/skills/$safe'),
            builder: (context, data) => learningCard(
              '${data['name'] ?? code}',
              Text('${data['description'] ?? ''}'),
            ),
          ),
          FilledButton(
            onPressed: () => openLearningPage(
              context,
              Scaffold(
                appBar: AppBar(title: const Text('Skill 연습')),
                body: ServerProblemList(skillCode: code),
              ),
            ),
            child: const Text('문제 풀기'),
          ),
          learningCard(
            '선수 Skill',
            RemoteSection(
              load: () => repo.get('/api/v1/skills/$safe/prerequisites'),
              builder: (context, data) => Column(
                children: [
                  for (final s in LearningRepository.items(
                    data,
                    'prerequisites',
                  ))
                    ListTile(
                      title: Text(
                        '${s['name'] ?? s['skill_name'] ?? s['code'] ?? s['skill_code']}',
                      ),
                      onTap: () => openLearningPage(
                        context,
                        ServerSkillDetail(
                          code: '${s['code'] ?? s['skill_code']}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          learningCard(
            '관련 학습 자료',
            RemoteSection(
              load: () => repo.get('/api/v1/skills/$safe/contents'),
              builder: (context, data) => Column(
                children: [
                  for (final c in LearningRepository.items(data))
                    ListTile(
                      title: Text('${c['title']}'),
                      onTap: () => openLearningPage(
                        context,
                        ServerContentScreen(contentId: c['id']),
                      ),
                    ),
                ],
              ),
            ),
          ),
          learningCard(
            '숙련도 변화',
            RemoteSection(
              load: () => repo.get('/api/v1/me/skill-states/$safe/history', {
                'limit': '20',
              }),
              builder: (context, data) => Column(
                children: [
                  for (final s in LearningRepository.items(data))
                    ListTile(
                      title: Text(percent(s['mastery_score'])),
                      subtitle: Text(studyTime(s['recorded_at'])),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ServerKnowledgeScreen extends StatelessWidget {
  const ServerKnowledgeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = LearningRepository();
    return Scaffold(
      appBar: AppBar(title: const Text('나의 지식 지도')),
      body: ServerPanel(
        load: () => repo.get('/api/v1/me/knowledge-map'),
        builder: (context, data) => Column(
          children: [
            for (final node in LearningRepository.items(data, 'nodes'))
              Card(
                child: ListTile(
                  title: Text(
                    '${node['name'] ?? node['skill_name'] ?? node['concept_name'] ?? node['code']}',
                  ),
                  subtitle: Text(
                    '숙련도 ${percent(node['mastery_score'] ?? node['mastery'])} · ${node['level'] ?? '미평가'}',
                  ),
                  onTap: node['type'].toString().toUpperCase() == 'SKILL'
                      ? () => openLearningPage(
                          context,
                          ServerSkillDetail(code: node['code']),
                        )
                      : null,
                ),
              ),
            if (LearningRepository.items(data, 'nodes').isEmpty)
              const Text('학습·진단 후 지식 상태가 표시돼요.'),
            ExpansionTile(
              title: const Text('개념 연결 관계'),
              children: [
                for (final edge in LearningRepository.items(data, 'edges'))
                  ListTile(
                    title: Text(
                      '${edge['source'] ?? edge['source_code'] ?? ''} → ${edge['target'] ?? edge['target_code'] ?? ''}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ServerRecordScreen extends StatefulWidget {
  final String kind;
  const ServerRecordScreen({super.key, required this.kind});
  @override
  State<ServerRecordScreen> createState() => _ServerRecordScreenState();
}

class _ServerRecordScreenState extends State<ServerRecordScreen> {
  final repo = LearningRepository();
  int page = 1, revision = 0;
  bool includeResolved = false;
  final _skill = TextEditingController();
  String filter = '';
  @override
  void dispose() {
    _skill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = switch (widget.kind) {
      'wrong' => '/api/v1/me/wrong-answers',
      'review' => '/api/v1/me/review-queue',
      'xp' => '/api/v1/me/xp-history',
      'captures' => '/api/v1/captured-problems',
      'tutor' => '/api/v1/me/tutor-history',
      _ => '/api/v1/me/learning-history',
    };
    final title = switch (widget.kind) {
      'wrong' => '오답노트',
      'review' => '복습할 문제',
      'xp' => 'XP 보상 이력',
      'captures' => '촬영 기록',
      'tutor' => '튜터 도움 이력',
      _ => '학습 기록',
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          if (widget.kind == 'wrong')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('해결한 오답도 보기'),
                    value: includeResolved,
                    onChanged: (v) => setState(() {
                      includeResolved = v;
                      page = 1;
                    }),
                  ),
                  TextField(
                    controller: _skill,
                    decoration: InputDecoration(
                      labelText: 'Skill 코드로 필터',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => setState(() {
                          filter = _skill.text.trim();
                          page = 1;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ServerPanel(
              key: ValueKey('$page-$revision-$includeResolved-$filter'),
              load: () => repo.get(path, {
                if (widget.kind != 'review') 'page': '$page',
                'size': widget.kind == 'review' ? '100' : '20',
                if (widget.kind == 'wrong')
                  'include_resolved': '$includeResolved',
                if (filter.isNotEmpty) 'skill_code': filter,
              }),
              builder: (context, data) => Column(
                children: [
                  if (LearningRepository.items(data).isEmpty)
                    const Text('표시할 기록이 없어요.'),
                  for (final record in LearningRepository.items(data))
                    Card(
                      child: ExpansionTile(
                        title: Text(
                          '${record['question'] ?? record['message'] ?? record['problem_code'] ?? (widget.kind == 'xp' ? '${record['xp']} XP' : '학습 기록')}',
                        ),
                        subtitle: Text(
                          studyTime(
                            record['attempted_at'] ??
                                record['created_at'] ??
                                record['last_attempted_at'],
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (record['student_answer'] != null)
                                  Text('제출 답안: ${record['student_answer']}'),
                                if (record['is_correct'] != null)
                                  Text(
                                    record['is_correct'] == true ? '정답' : '오답',
                                  ),
                                if (record['last_wrong_answer'] != null)
                                  Text(
                                    '마지막 답안: ${record['last_wrong_answer']}',
                                  ),
                                if (record['answer'] != null)
                                  Text('정답: ${record['answer']}'),
                                if (record['explanation'] != null)
                                  Text('해설: ${record['explanation']}'),
                                if (record['resolved'] != null)
                                  Text(
                                    record['resolved'] == true
                                        ? '해결 완료'
                                        : '복습 필요',
                                  ),
                                if (widget.kind == 'xp')
                                  Text(_eventTitle('${record['event_type']}')),
                                if (record['problem_id'] is int &&
                                    widget.kind != 'tutor')
                                  FilledButton(
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ServerProblemScreen(
                                            problemId: record['problem_id'],
                                          ),
                                        ),
                                      );
                                      if (mounted) setState(() => revision++);
                                    },
                                    child: const Text('다시 풀기'),
                                  ),
                                if (widget.kind == 'captures')
                                  FilledButton(
                                    onPressed: () => openLearningPage(
                                      context,
                                      ServerCaptureScreen(
                                        capturedId: record['id'],
                                      ),
                                    ),
                                    child: const Text('사진·분석 보기'),
                                  ),
                                if (widget.kind == 'tutor')
                                  RemoteSection(
                                    load: () => repo.get(
                                      '/api/v1/tutor/actions/${record['id']}',
                                    ),
                                    builder: (context, detail) => Column(
                                      children: [
                                        Text('${detail['message'] ?? ''}'),
                                        for (final reaction
                                            in LearningRepository.items(
                                              detail,
                                              'reactions',
                                            ))
                                          Text(
                                            '${reaction['reaction']} · ${studyTime(reaction['created_at'])}',
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.kind != 'review')
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: page > 1
                              ? () => setState(() => page--)
                              : null,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _eventTitle(String event) => switch (event) {
  'PROBLEM_CORRECT' => '문제 첫 정답 보상',
  'CONTENT_COMPLETE' => '학습 자료 완료 보상',
  'BADGE_EARNED' => '배지 획득 보상',
  'QUEST_COMPLETE' => '퀘스트 완료 보상',
  _ => '학습 활동 보상',
};

class ServerAccountTab extends StatefulWidget {
  const ServerAccountTab({super.key});
  @override
  State<ServerAccountTab> createState() => _ServerAccountTabState();
}

class _ServerAccountTabState extends State<ServerAccountTab> {
  final repo = LearningRepository();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        '마이페이지',
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      learningCard(
        '나의 프로필',
        RemoteSection(
          load: () => repo.get('/api/v1/users/me'),
          builder: (context, data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${data['nickname'] ?? data['name'] ?? '학생'}'),
              TextButton(
                onPressed: () =>
                    openLearningPage(context, const ServerProfileScreen()),
                child: const Text('학년 설정'),
              ),
            ],
          ),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => openLearningPage(
              context,
              const ServerRecordScreen(kind: 'history'),
            ),
            child: const Text('학습 기록'),
          ),
          OutlinedButton(
            onPressed: () =>
                openLearningPage(context, const ServerRecordScreen(kind: 'xp')),
            child: const Text('XP 보상 이력'),
          ),
          OutlinedButton(
            onPressed: () => openLearningPage(
              context,
              const ServerRecordScreen(kind: 'captures'),
            ),
            child: const Text('촬영 기록'),
          ),
          OutlinedButton(
            onPressed: () => openLearningPage(
              context,
              const ServerRecordScreen(kind: 'tutor'),
            ),
            child: const Text('튜터 이력'),
          ),
          OutlinedButton(
            onPressed: () => openLearningPage(
              context,
              Scaffold(
                appBar: AppBar(title: const Text('오늘의 퀘스트')),
                body: ServerPanel(
                  load: () => repo.get('/api/v1/me/quests'),
                  builder: (context, data) => questItems(data),
                ),
              ),
            ),
            child: const Text('오늘의 퀘스트'),
          ),
        ],
      ),
      const SizedBox(height: 20),
      learningCard('배지', const BadgeCollection()),
      const Text('포인트·골드 교환은 준비 중입니다.'),
    ],
  );
}

class ServerProfileScreen extends StatefulWidget {
  const ServerProfileScreen({super.key});
  @override
  State<ServerProfileScreen> createState() => _ServerProfileScreenState();
}

class _ServerProfileScreenState extends State<ServerProfileScreen> {
  final repo = LearningRepository();
  String? grade;
  bool busy = false;
  Future<void> _save() async {
    if (grade == null || busy) return;
    setState(() => busy = true);
    try {
      await repo.patch('/api/v1/me/student-profile', {'grade_level': grade});
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(e))));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('학년 설정')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: '현재 학년'),
            items: [
              for (int i = 1; i <= 12; i++)
                DropdownMenuItem(
                  value: i <= 6
                      ? '초$i'
                      : i <= 9
                      ? '중${i - 6}'
                      : '고${i - 9}',
                  child: Text(
                    i <= 6
                        ? '초등학교 $i학년'
                        : i <= 9
                        ? '중학교 ${i - 6}학년'
                        : '고등학교 ${i - 9}학년',
                  ),
                ),
            ],
            onChanged: (value) => setState(() => grade = value),
          ),
          FilledButton(
            onPressed: busy || grade == null ? null : _save,
            child: const Text('저장'),
          ),
        ],
      ),
    ),
  );
}
