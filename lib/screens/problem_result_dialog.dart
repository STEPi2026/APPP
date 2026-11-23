import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_storage.dart';
import '../models/learning_next_action.dart';
import 'learning_next_action_notice.dart';

enum ProblemResultAction { retry, next, help, related, followNextAction }

/// Shares the existing completion card's purple, spacing and rounded shapes.
/// Every reward and assessment shown here comes from the accepted server reply.
class ProblemResultDialog extends StatelessWidget {
  final JsonMap result;
  final ExperienceProgress experience;
  final bool isLast;
  final bool tutorAvailable;
  const ProblemResultDialog({
    super.key,
    required this.result,
    required this.experience,
    required this.isLast,
    this.tutorAvailable = true,
  });
  static const purple = Color(0xFF7C5CFA), light = Color(0xFFF3EEFF);

  @override
  Widget build(BuildContext context) {
    final correct = result.containsKey('answer_correct')
        ? result['answer_correct']
        : result['is_correct'];
    final nextAction = LearningNextAction.fromResponse(result);
    final unknownSessionAction =
        result['scenario'] is String &&
        result['next_action'] is String &&
        nextAction == null;
    final rewards = result['rewards'] is Map
        ? result['rewards'] as Map
        : const {};
    final badges = rewards['new_badges'] is List
        ? rewards['new_badges'] as List
        : const [];
    final quests = rewards['completed_quests'] is List
        ? rewards['completed_quests'] as List
        : const [];
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                correct == true
                    ? Icons.celebration_rounded
                    : Icons.rocket_launch_rounded,
                color: purple,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                correct == true
                    ? '훌륭한 풀이입니다!'
                    : correct == false
                    ? '다시 도전해 볼까요?'
                    : '답안을 제출했어요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF171717),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                correct is bool ? '서버에 풀이 결과가 저장되었어요.' : '아직 채점 결과가 나오지 않았어요.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF777777)),
              ),
              const SizedBox(height: 20),
              if (nextAction != null)
                LearningNextActionNotice(action: nextAction),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: light,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _row(
                      '채점 결과',
                      correct == true
                          ? '정답'
                          : correct == false
                          ? '오답'
                          : '채점 대기',
                    ),
                    if (result['score'] is num) ...[
                      const SizedBox(height: 8),
                      _row(
                        '문제 점수',
                        '${result['score']}${result['max_score'] is num ? ' / ${result['max_score']}' : ''}',
                      ),
                    ],
                    const SizedBox(height: 8),
                    _row('새 배지', '${badges.length}개'),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    _row(
                      '이번 풀이 획득 XP',
                      rewards['xp'] is num
                          ? '+ ${rewards['xp']} XP'
                          : '지급 내역 확인 필요',
                      highlight: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (rewards['level_up'] == true) ...[
                const Text(
                  '레벨이 올랐어요!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: purple, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
              ],
              _row(
                experience.isAvailable
                    ? 'Lv.${experience.level}${experience.isMaxLevel ? ' · 최고 레벨' : ''}'
                    : '레벨 확인 불가',
                experience.isAvailable
                    ? '${experience.totalXp} XP'
                    : '다시 입장하면 갱신돼요',
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: experience.progress,
                  minHeight: 7,
                  color: purple,
                  backgroundColor: const Color(0xFFEEEEEE),
                ),
              ),
              if (experience.isAvailable && !experience.isMaxLevel)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '다음 레벨까지 ${experience.remainingXp} XP',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF777777),
                    ),
                  ),
                ),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final badge in badges.whereType<Map>())
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Image.asset(
                          'img/badges/${badge['code']}.png',
                          width: 38,
                          height: 38,
                          errorBuilder: (_, error, stack) => const Icon(
                            Icons.workspace_premium,
                            color: purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${badge['name'] ?? '새 배지'}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              for (final quest in quests.whereType<Map>())
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '퀘스트 완료 · ${quest['title'] ?? ''}',
                    style: const TextStyle(fontSize: 13, color: purple),
                  ),
                ),
              const SizedBox(height: 20),
              if (tutorAvailable)
                OutlinedButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, ProblemResultAction.help),
                  icon: const Icon(Icons.lightbulb_outline_rounded),
                  label: const Text('개념 도움 받기'),
                ),
              if (tutorAvailable) const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pop(context, ProblemResultAction.related),
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('같은 개념의 다른 문제 풀기'),
              ),
              const SizedBox(height: 8),
              if (correct == false) ...[
                OutlinedButton(
                  onPressed: () =>
                      Navigator.pop(context, ProblemResultAction.retry),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: purple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('원래 문제 다시 풀기'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  nextAction == null && !unknownSessionAction
                      ? ProblemResultAction.next
                      : ProblemResultAction.followNextAction,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: purple,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  nextAction?.title ??
                      (unknownSessionAction
                          ? '개념 확인하고 다시 풀기'
                          : (isLast ? '학습 마치기' : '다음 문제 풀기 ▶')),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (nextAction != null &&
                  nextAction != LearningNextAction.complete)
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, ProblemResultAction.next),
                  child: Text(isLast ? '학습 마치기' : '다음 문제 풀기'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: Text(
          label,
          style: TextStyle(
            fontSize: highlight ? 15 : 13,
            color: highlight ? purple : const Color(0xFF555555),
            fontWeight: highlight ? FontWeight.w800 : FontWeight.normal,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: highlight ? 16 : 13,
            color: highlight ? purple : const Color(0xFF555555),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}
