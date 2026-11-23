import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import '../services/question_service.dart';
import '../services/student_knowledge.dart';
import 'problem_screen.dart';
import 'server_pathways.dart';

const knowledgePurple = Color(0xFF7C5CFA);

class KnowledgeNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const KnowledgeNotice({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    margin: const EdgeInsets.only(bottom: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F1FF),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: const TextStyle(color: Color(0xFF686077), height: 1.6),
        ),
        if (onRetry != null)
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('다시 불러오기'),
          ),
      ],
    ),
  );
}

class KnowledgeConceptCard extends StatelessWidget {
  final JsonMap concept;
  final StudentKnowledge knowledge;
  final LearningRepository repository;
  const KnowledgeConceptCard({
    super.key,
    required this.concept,
    required this.knowledge,
    required this.repository,
  });
  @override
  Widget build(BuildContext context) {
    final state = knowledge.conceptStates[concept['code']];
    final score = StudentKnowledge.score(state);
    final skills = knowledge.skillsFor(concept['code']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: PageStorageKey('knowledge-${concept['code']}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            '${concept['name']}',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF171717),
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score ?? 0,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEEEEEE),
                    color: knowledgePurple,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  StudentKnowledge.label(state),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          children: [
            if (skills.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('학습 항목을 준비하고 있어요.'),
              ),
            for (final skill in skills)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text(
                  '${skill['name']}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  StudentKnowledge.label(knowledge.skillStates[skill['code']]),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: knowledgePurple,
                ),
                onTap: () => showKnowledgeSkill(
                  context,
                  skill: skill,
                  knowledge: knowledge,
                  repository: repository,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showKnowledgeSkill(
  BuildContext context, {
  required JsonMap skill,
  required StudentKnowledge knowledge,
  required LearningRepository repository,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
  ),
  builder: (_) =>
      _SkillSheet(skill: skill, knowledge: knowledge, repo: repository),
);

class _SkillSheet extends StatefulWidget {
  final JsonMap skill;
  final StudentKnowledge knowledge;
  final LearningRepository repo;
  const _SkillSheet({
    required this.skill,
    required this.knowledge,
    required this.repo,
  });
  @override
  State<_SkillSheet> createState() => _SkillSheetState();
}

class _SkillSheetState extends State<_SkillSheet> {
  late Future<JsonMap> _contents;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _contents = widget.repo.get(
      '/api/v1/skills/${Uri.encodeComponent(widget.skill['code'])}/contents',
    );
  }

  @override
  Widget build(BuildContext context) {
    final skill = widget.skill, graph = widget.knowledge.graph;
    final parents = graph.prerequisites[skill['code']] ?? <String>[];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: knowledgePurple),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '개념 학습',
                    style: TextStyle(
                      color: knowledgePurple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              '${skill['name']}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            KnowledgeNotice(
              message: StudentKnowledge.label(
                widget.knowledge.skillStates[skill['code']],
              ),
            ),
            if (skill['description'] is String &&
                (skill['description'] as String).isNotEmpty)
              Text(skill['description'], style: const TextStyle(height: 1.6)),
            const SizedBox(height: 20),
            const Text(
              '먼저 알아두면 좋아요',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (parents.isEmpty)
              const Text(
                '등록된 선수개념이 없어요.',
                style: TextStyle(color: Colors.grey),
              ),
            for (final code in parents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${graph.skills[code]?['name'] ?? code}'),
                subtitle: Text(
                  StudentKnowledge.label(widget.knowledge.skillStates[code]),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              '관련 학습 자료',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            FutureBuilder<JsonMap>(
              future: _contents,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator(color: knowledgePurple);
                }
                if (snapshot.hasError) {
                  return KnowledgeNotice(
                    message: learningError(snapshot.error!),
                    onRetry: () => setState(_reload),
                  );
                }
                final items = LearningRepository.items(snapshot.data!);
                if (items.isEmpty) {
                  return const KnowledgeNotice(
                    message: '이 개념의 학습 자료를 준비하고 있어요. 문제 풀이는 먼저 시작할 수 있어요.',
                  );
                }
                return Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.menu_book_rounded,
                          color: knowledgePurple,
                        ),
                        title: Text('${item['title']}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: item['id'] is! int
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => ServerContentScreen(
                                      contentId: item['id'],
                                      repository: widget.repo,
                                    ),
                                  ),
                                );
                                if (mounted) setState(_reload);
                              },
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: knowledgePurple,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('이 개념 문제 풀기'),
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => ProblemScreen(
                      topic: '${skill['name']}',
                      repository: widget.repo,
                      questionService: ServerQuestionService(
                        skillCode: skill['code'],
                        repository: widget.repo,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
