import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import 'knowledge_widgets.dart';

String recordTime(Object? value) {
  final date = DateTime.tryParse('$value');
  if (date == null) return '날짜 정보 없음';
  final kst = date.toUtc().add(const Duration(hours: 9));
  return '${kst.year}.${kst.month.toString().padLeft(2, '0')}.${kst.day.toString().padLeft(2, '0')} ${kst.hour.toString().padLeft(2, '0')}:${kst.minute.toString().padLeft(2, '0')}';
}

class XpHistoryScreen extends StatefulWidget {
  final LearningRepository? repository;
  const XpHistoryScreen({super.key, this.repository});
  @override
  State<XpHistoryScreen> createState() => _XpHistoryScreenState();
}

class _XpHistoryScreenState extends State<XpHistoryScreen> {
  late final repo = widget.repository ?? LearningRepository();
  final List<JsonMap> rows = [];
  bool busy = false, more = true;
  int page = 0, epoch = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    _load(reset: true);
    LearningRepository.progressRevision.addListener(_refresh);
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (busy && !reset) return;
    final request = ++epoch, next = reset ? 1 : page + 1;
    setState(() {
      busy = true;
      error = null;
      if (reset) {
        rows.clear();
        page = 0;
      }
    });
    try {
      final data = await repo.get('/api/v1/me/xp-history', {
        'page': '$next',
        'size': '20',
      });
      if (!mounted || request != epoch) return;
      final incoming = LearningRepository.items(data);
      setState(() {
        final ids = rows.map((r) => r['id']).toSet();
        rows.addAll(incoming.where((r) => ids.add(r['id'])));
        page = next;
        more = incoming.isNotEmpty && next < (data['total_pages'] as num? ?? 1);
        busy = false;
      });
    } catch (e) {
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          error = learningError(e);
        });
      }
    }
  }

  String label(Object? type) => switch (type) {
    'PROBLEM_SOLVED' || 'PROBLEM_ATTEMPT' => '문제 풀이',
    'DAILY_QUEST' || 'QUEST_COMPLETED' => '퀘스트 달성',
    'BADGE_EARNED' || 'BADGE_REWARD' => '배지 달성',
    'CONTENT_COMPLETED' => '콘텐츠 학습',
    _ => '$type',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF8FF),
    appBar: AppBar(title: const Text('XP 지급 이력')),
    body: RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const KnowledgeNotice(
            message: '학습 점수와 XP는 서로 달라요. 여기서는 학습 활동으로 지급된 XP를 확인해요.',
          ),
          for (final row in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: knowledgePurple,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label(row['event_type']),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          recordTime(row['created_at']),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${row['xp'] is num && (row['xp'] as num) > 0 ? '+' : ''}${row['xp']} XP',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: knowledgePurple,
                    ),
                  ),
                ],
              ),
            ),
          if (busy)
            const Center(
              child: CircularProgressIndicator(color: knowledgePurple),
            ),
          if (error != null)
            KnowledgeNotice(
              message: error!,
              onRetry: () => _load(reset: page == 0),
            ),
          if (!busy && error == null && rows.isEmpty)
            const KnowledgeNotice(message: '아직 지급된 XP가 없어요.'),
          if (!busy && error == null && more && rows.isNotEmpty)
            OutlinedButton(onPressed: () => _load(), child: const Text('더 보기')),
        ],
      ),
    ),
  );
}
