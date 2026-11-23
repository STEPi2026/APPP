import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import 'knowledge_widgets.dart';
import 'xp_history_screen.dart';

class QuestScreen extends StatefulWidget {
  final LearningRepository? repository;
  const QuestScreen({super.key, this.repository});
  @override
  State<QuestScreen> createState() => _QuestScreenState();
}

class _QuestScreenState extends State<QuestScreen> {
  late final _repo = widget.repository ?? LearningRepository();
  late Future<JsonMap> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
    LearningRepository.progressRevision.addListener(_refresh);
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_refresh);
    super.dispose();
  }

  Future<JsonMap> _load() => _repo.get('/api/v1/me/quests');
  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8FF),
    appBar: AppBar(
      title: const Text('오늘의 퀘스트'),
      actions: [
        IconButton(
          tooltip: '새로고침',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: FutureBuilder<JsonMap>(
      future: _future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(
            child: CircularProgressIndicator(color: knowledgePurple),
          );
        }
        if (s.hasError) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: KnowledgeNotice(
              message: learningError(s.error!),
              onRetry: _refresh,
            ),
          );
        }
        final data = s.data!, rows = LearningRepository.items(s.data!);
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                '매일 작은 목표를 달성해 보세요!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                '${data['date']} · 오늘의 목표',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const KnowledgeNotice(
                message:
                    '목표 달성 여부와 XP 보상은 학습 결과에 따라 자동 반영돼요. 별도로 보상을 받을 필요는 없어요.',
              ),
              if (rows.isEmpty)
                const KnowledgeNotice(message: '오늘의 퀘스트를 준비하고 있어요.'),
              for (final row in rows) _quest(row),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => XpHistoryScreen(repository: _repo),
                  ),
                ),
                icon: const Icon(Icons.history_rounded),
                label: const Text('XP 지급 이력 확인'),
              ),
            ],
          ),
        );
      },
    ),
  );
  Widget _quest(JsonMap row) {
    final completed = row['completed'] == true;
    final progress = row['progress'] is num
        ? (row['progress'] as num).toInt()
        : 0;
    final target = row['target'] is num ? (row['target'] as num).toInt() : 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9E2F7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                completed ? Icons.check_circle_rounded : Icons.flag_rounded,
                color: knowledgePurple,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${row['title']}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${row['reward_xp']} XP',
                style: const TextStyle(
                  color: knowledgePurple,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: target > 0 ? (progress / target).clamp(0.0, 1.0) : 0,
              minHeight: 8,
              color: knowledgePurple,
              backgroundColor: const Color(0xFFF0ECF8),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$progress / $target',
                style: const TextStyle(color: Colors.grey),
              ),
              Text(
                completed ? '완료' : '진행 중',
                style: const TextStyle(
                  color: knowledgePurple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
