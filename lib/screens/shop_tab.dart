import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import '../services/student_learning_records.dart';
import 'badge_collection.dart';
import 'knowledge_widgets.dart';
import 'xp_history_screen.dart';
import 'quest_screen.dart';
import 'captured_history_screen.dart';
import 'learning_history_screen.dart';
import 'concept_level_test_dialog.dart';
import 'skill_tree_tab.dart' show curriculumConceptChecklist;

class ShopTab extends StatefulWidget {
  final LearningRepository? repository;
  final DateTime? now;
  const ShopTab({super.key, this.repository, this.now});
  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> {
  static const purple = Color(0xFF7C5CFA);
  late final repo = widget.repository ?? LearningRepository();
  late final DateTime today = (widget.now ?? DateTime.now()).toUtc().add(
    const Duration(hours: 9),
  );
  late DateTime month = DateTime.utc(today.year, today.month);
  JsonMap? growth;
  Map<int, int> days = {};
  bool loading = true, shop = false, editing = false;
  String? error;
  int request = 0;
  @override
  void initState() {
    super.initState();
    _refresh();
    LearningRepository.progressRevision.addListener(_refresh);
  }

  @override
  void dispose() {
    LearningRepository.progressRevision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final generation = ++request;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await Future.wait<dynamic>([
        repo.get('/api/v1/me/gamification'),
        StudentLearningRecords(repo).attempts(),
      ]);
      final counts = <int, int>{};
      for (final row in data[1] as List<JsonMap>) {
        final date = DateTime.tryParse('${row['attempted_at']}');
        if (date != null) {
          final day = StudentLearningOverview.studyDay(date);
          counts[day] = (counts[day] ?? 0) + 1;
        }
      }
      if (mounted && generation == request) {
        setState(() {
          growth = data[0];
          days = counts;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == request) {
        setState(() {
          loading = false;
          error = learningError(e);
          growth = null;
          days = {};
        });
      }
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
    if (mounted) await _refresh();
  }

  Future<void> _profile() async {
    if (editing) return;
    setState(() => editing = true);
    try {
      JsonMap data;
      try {
        data = await repo.get('/api/v1/me/student-profile');
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
        data = {};
      }
      if (!mounted) return;
      await _open(StudentProfileScreen(repository: repo, initial: data));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(learningError(e))));
      }
    } finally {
      if (mounted) setState(() => editing = false);
    }
  }

  Widget _card(Widget child, {bool tinted = false}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: tinted ? const Color(0xFFF3EEFF) : Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFEEEEEE)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF9F9FB),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shop ? '보상 상점' : '마이페이지',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => shop = !shop),
                    icon: Icon(
                      shop
                          ? Icons.person_outline_rounded
                          : Icons.storefront_rounded,
                      size: 18,
                    ),
                    label: Text(shop ? '마이페이지로' : '포인트 상점'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (shop) ...[
                _card(
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.storefront_rounded, color: purple, size: 36),
                      SizedBox(height: 14),
                      Text(
                        '보상 상점을 준비하고 있어요',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '포인트 적립과 상품 교환이 준비되면 여기서 이용할 수 있어요. 학습으로 쌓은 XP는 레벨 성장에 사용돼요.',
                        style: TextStyle(height: 1.7, color: Colors.grey),
                      ),
                    ],
                  ),
                  tinted: true,
                ),
                OutlinedButton(
                  onPressed: () => _open(XpHistoryScreen(repository: repo)),
                  child: const Text('XP 지급 이력 보기'),
                ),
              ] else ...[
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => showConceptLevelTest(
                    context,
                    concepts: curriculumConceptChecklist(),
                    repository: repo,
                  ),
                  child: _card(
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '내 수학 실력 알아보기',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '배웠던 개념을 확인하고 부족한 부분을 채워요',
                          style: TextStyle(fontSize: 13.5),
                        ),
                        SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: purple,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (loading) const LinearProgressIndicator(color: purple),
                if (error != null)
                  KnowledgeNotice(message: error!, onRetry: _refresh),
                if (growth != null)
                  _card(
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        for (final entry in {
                          '레벨': growth!['level'],
                          '누적 XP': growth!['xp'],
                          '연속 학습일': growth!['current_streak'],
                        }.entries)
                          Column(
                            children: [
                              Text(
                                '${entry.value}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: purple,
                                ),
                              ),
                              Text(
                                entry.key,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    tinted: true,
                  ),
                _calendar(),
                _card(
                  Column(
                    children: [
                      _row(
                        Icons.manage_accounts_outlined,
                        '학년·학습 목표 설정',
                        editing ? null : _profile,
                      ),
                      _row(
                        Icons.history_rounded,
                        '나의 학습 기록',
                        () => _open(LearningHistoryScreen(repository: repo)),
                      ),
                      _row(
                        Icons.photo_library_outlined,
                        '사진 풀이 이력',
                        () => _open(CapturedHistoryScreen(repository: repo)),
                      ),
                      _row(
                        Icons.flag_outlined,
                        '오늘의 퀘스트',
                        () => _open(QuestScreen(repository: repo)),
                      ),
                      _row(
                        Icons.auto_awesome_rounded,
                        'XP 지급 이력',
                        () => _open(XpHistoryScreen(repository: repo)),
                      ),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '내 배지 도감',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      BadgeCollection(
                        catalogLoader: () => repo.all('/api/v1/badges'),
                        earnedLoader: () => repo.all('/api/v1/me/badges'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  Widget _row(IconData icon, String title, VoidCallback? action) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: purple),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: action,
  );
  Widget _calendar() {
    final offset = month.weekday % 7,
        count = DateTime.utc(month.year, month.month + 1, 0).day;
    final slots = ((offset + count + 6) ~/ 7) * 7;
    return _card(
      Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '나의 학습 기록 (${month.year}.${month.month})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: '이전 달',
                onPressed: () => setState(
                  () => month = DateTime.utc(month.year, month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: '다음 달',
                onPressed:
                    month.year == today.year && month.month == today.month
                    ? null
                    : () => setState(
                        () => month = DateTime.utc(month.year, month.month + 1),
                      ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final day in ['일', '월', '화', '수', '목', '금', '토'])
                Expanded(
                  child: Text(
                    day,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: List.generate(slots, (index) {
              final day = index - offset + 1;
              if (day < 1 || day > count) return const SizedBox.shrink();
              final date = DateTime.utc(month.year, month.month, day);
              final key = StudentLearningOverview.studyDay(date);
              final activity = days[key] ?? 0;
              return Tooltip(
                message: error != null ? '기록 확인 불가' : '$day일 · 제출 $activity회',
                child: InkWell(
                  key: ValueKey('study-day-$key'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: loading || error != null
                      ? null
                      : () => _open(
                          LearningHistoryScreen(
                            repository: repo,
                            studyDate: date,
                          ),
                        ),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: activity > 0 ? purple : const Color(0xFFF3F0F8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: activity > 0 ? Colors.white : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Text(
            error != null
                ? '학습 기록을 불러오지 못했어요.'
                : '문제를 제출한 날을 표시해요. 출석 보상과는 별개예요.',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class StudentProfileScreen extends StatefulWidget {
  final LearningRepository repository;
  final JsonMap initial;
  const StudentProfileScreen({
    super.key,
    required this.repository,
    required this.initial,
  });
  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  late String grade = '${widget.initial['grade_level'] ?? ''}';
  late final goal = TextEditingController(
    text: '${widget.initial['learning_goal'] ?? ''}',
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    goal.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || grade.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.patch('/api/v1/me/student-profile', {
        'grade_level': grade,
        'learning_goal': goal.text.trim(),
      });
      LearningRepository.notifyProgressChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = learningError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final grades = {
      '초등',
      '중1',
      '중2',
      '중3',
      '고1',
      '고2',
      '고3',
      if (grade.isNotEmpty) grade,
    }.toList();
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF),
      appBar: AppBar(title: const Text('학년·학습 목표')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const KnowledgeNotice(
            message: '현재 학년과 목표를 설정해 주세요. 개념 레벨테스트에서 학년을 선택할 때도 참고해요.',
          ),
          DropdownButtonFormField<String>(
            initialValue: grade.isEmpty ? null : grade,
            decoration: const InputDecoration(
              labelText: '현재 학년',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in grades)
                DropdownMenuItem(value: item, child: Text(item)),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() => grade = value ?? ''),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: goal,
            maxLength: 255,
            minLines: 3,
            maxLines: 5,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: '학습 목표',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          if (error != null) KnowledgeNotice(message: error!),
          FilledButton(
            onPressed: busy || grade.isEmpty ? null : save,
            child: Text(busy ? '저장 중…' : '저장하기'),
          ),
        ],
      ),
    );
  }
}
