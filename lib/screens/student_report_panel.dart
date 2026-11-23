import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import '../services/student_knowledge.dart';
import '../services/student_learning_records.dart';
import 'knowledge_widgets.dart';
import 'server_pathways.dart';

/// Independent sections keep an unavailable leaderboard from hiding learning.
class StudentReportPanel extends StatefulWidget {
  final LearningRepository repository;
  final StudentKnowledge? knowledge;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  const StudentReportPanel({
    super.key,
    required this.repository,
    required this.knowledge,
    required this.loading,
    this.error,
    required this.onRefresh,
  });
  @override
  State<StudentReportPanel> createState() => _StudentReportPanelState();
}

class _StudentReportPanelState extends State<StudentReportPanel> {
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    LearningRepository.progressRevision.addListener(_recordsChanged);
  }

  void _recordsChanged() {
    if (mounted) setState(() => _revision++);
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_recordsChanged);
    super.dispose();
  }

  void _refresh() {
    setState(() => _revision++);
    widget.onRefresh();
  }

  Future<void> _roadmap() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ServerRoadmapScreen(repository: widget.repository),
      ),
    );
    if (mounted) _refresh();
  }

  Future<void> _friendRequest() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('친구 연결 요청'),
        content: TextField(
          controller: controller,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: '친구 코드',
            hintText: '친구에게 받은 코드를 입력해 주세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 4) Navigator.pop(context, value);
            },
            child: const Text('요청 보내기'),
          ),
        ],
      ),
    );
    // The dialog's exit animation still owns the controller for one frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (code == null || !mounted) return;
    try {
      await widget.repository.post('/api/v1/friend-requests', {
        'friend_code': code,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('친구 요청을 보냈어요. 상대가 수락하면 함께 표시돼요.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(error))));
      }
    }
  }

  Widget _card(String title, Widget child, {bool tinted = false}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: tinted ? const Color(0xFFF3EEFF) : Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: Color(0xFF171717),
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
  Widget _stat(String label, Object? value) => Expanded(
    child: Column(
      children: [
        Text(
          value == null ? '—' : '$value',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: knowledgePurple,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF777777)),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final knowledge = widget.knowledge;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('새로고침'),
          ),
        ),
        _card(
          '나의 학습 기록',
          _ReportData(
            key: ValueKey('summary-$_revision'),
            load: () => widget.repository.get('/api/v1/me/learning-summary'),
            builder: (data) => Row(
              children: [
                _stat('누적 제출', data['total_attempts']),
                _stat('정답', data['correct_attempts']),
                _stat('오답', data['incorrect_attempts']),
              ],
            ),
          ),
        ),
        _card(
          '꾸준히 쌓은 성장',
          _ReportData(
            key: ValueKey('growth-$_revision'),
            load: () => widget.repository.get('/api/v1/me/gamification'),
            builder: (data) => Row(
              children: [
                _stat('레벨', data['level']),
                _stat('누적 XP', data['xp']),
                _stat('연속 학습일', data['current_streak']),
              ],
            ),
          ),
        ),
        _card(
          '다음 학습 로드맵',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReportData(
                key: ValueKey('roadmap-$_revision'),
                load: () async => {
                  'next': await StudentLearningRecords(widget.repository)
                      .nextRoadmapStep(),
                },
                builder: (data) {
                  final next = data['next'];
                  return Text(
                    next is Map
                        ? '${next['skill_name'] ?? next['skill_code']}\n${next['reason'] ?? ''}'
                        : '로드맵에서 나에게 맞는 다음 학습을 확인해 보세요.',
                    style: const TextStyle(fontSize: 13, height: 1.7),
                  );
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _roadmap,
                icon: const Icon(Icons.route_rounded, size: 18),
                label: const Text('내 학습 로드맵'),
              ),
            ],
          ),
          tinted: true,
        ),
        _card(
          '친구와 함께 · 이번 주 XP',
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReportData(
                key: ValueKey('friends-$_revision'),
                load: () =>
                    widget.repository.get('/api/v1/friends/leaderboard'),
                builder: (data) {
                  final rows = LearningRepository.items(data);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (rows.isEmpty) const Text('아직 표시할 친구 순위가 없어요.'),
                      for (final row in rows)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: row['is_me'] == true
                                ? const Color(0xFFF3EEFF)
                                : const Color(0xFFF9F9FB),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Text(
                                row['rank'] == null ? '—' : '${row['rank']}',
                                style: const TextStyle(
                                  color: knowledgePurple,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${row['display_name']}${row['is_me'] == true ? ' (나)' : ''}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      'Lv.${row['level']} · 연속 ${row['current_streak']}일',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${row['weekly_xp']} XP',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: knowledgePurple,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              TextButton.icon(
                onPressed: _friendRequest,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('친구 코드로 연결 요청'),
              ),
              const Text(
                '전국 순위는 아직 제공되지 않아요.',
                style: TextStyle(fontSize: 11, color: Color(0xFF888888)),
              ),
            ],
          ),
        ),
        _card(
          '학년별 개념 숙련도',
          _ReportData(
            key: ValueKey('grades-$_revision'),
            load: () =>
                widget.repository.get('/api/v1/me/knowledge-map/summary'),
            builder: (data) {
              final rows = LearningRepository.items(data, 'grades');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (rows.isEmpty) const Text('진단·학습 후 숙련도를 확인할 수 있어요.'),
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['grade_level']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '평가 ${row['assessed_concept_count']} / ${row['concept_count']}개 개념',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            row['average_mastery_score'] is num
                                ? '평균 숙련도 ${((row['average_mastery_score'] as num) * 100).round()}%'
                                : '아직 평가 전',
                            style: const TextStyle(
                              color: knowledgePurple,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        _card(
          '개념·Skill별 숙련도',
          Column(
            children: [
              if (widget.loading)
                const LinearProgressIndicator(color: knowledgePurple),
              if (widget.error != null)
                KnowledgeNotice(
                  message: widget.error!,
                  onRetry: widget.onRefresh,
                ),
              if (knowledge != null && knowledge.concepts.isEmpty)
                const Text('아직 등록된 개념이 없어요.'),
              if (knowledge != null)
                for (final concept in knowledge.concepts)
                  KnowledgeConceptCard(
                    concept: concept,
                    knowledge: knowledge,
                    repository: widget.repository,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportData extends StatefulWidget {
  final Future<JsonMap> Function() load;
  final Widget Function(JsonMap) builder;
  const _ReportData({super.key, required this.load, required this.builder});
  @override
  State<_ReportData> createState() => _ReportDataState();
}

class _ReportDataState extends State<_ReportData> {
  late Future<JsonMap> _future;
  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<JsonMap>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator(color: knowledgePurple);
      }
      if (snapshot.hasError) {
        return KnowledgeNotice(
          message: learningError(snapshot.error!),
          onRetry: () => setState(() => _future = widget.load()),
        );
      }
      return widget.builder(snapshot.data!);
    },
  );
}
