import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/learning_repository.dart';
import '../services/student_learning_records.dart';
import '../services/question_service.dart';
import 'problem_screen.dart';
import 'quest_screen.dart';
import 'wrong_answer_screen.dart';
import 'skill_tree_tab.dart' show curriculumConceptChecklist;
import 'concept_level_test_dialog.dart';
import 'server_pathways.dart' show ServerRoadmapScreen;

class HomeTab extends StatefulWidget {
  final Function(int) onNavigate;

  final LearningRepository? repository;
  const HomeTab({super.key, required this.onNavigate, this.repository});

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  static const _purple = Color(0xFF9F86F7);
  static const _deepPurple = Color(0xFF7652FF);
  static const _lightPurple = Color(0xFFF5F1FF);
  static const _textColor = Color(0xFF171717);
  static const _mutedColor = Color(0xFF929292);

  bool _loading = true;
  String? _loadError;

  int _streak = 0;
  int _todayLearningCount = 0;
  int _attemptCount = 0, _correctCount = 0;
  late final _repo = widget.repository ?? LearningRepository();
  JsonMap? _nextStep;
  bool _preferRoadmap = true;
  JsonMap? get _suggestedStep => _preferRoadmap ? _nextStep : null;
  int _totalXp = 0;

  Set<int> _learningDays = {};
  int _todayDay = StudentLearningOverview.studyDay(DateTime.now());

  String? _diagnosedWeakConcept;

  // 고1(공통수학1) 맞춤 추천 단원 상태 및 카탈로그
  int _recommendedIndex = 0;
  String _recommendationReason = '선택한 단원의 문제를 최대 5개까지 풀어요.';

  static const List<Map<String, String>> _highSchoolGrade1Units = [
    {
      'unit': '다항식',
      'title': '다항식의 연산과\n나머지정리 복습하기',
      'badge': '고1 공통수학1 · I. 다항식',
    },
    {
      'unit': '방정식과 부등식',
      'title': '복소수와 이차방정식\n판별식 정복하기',
      'badge': '고1 공통수학1 · II. 방정식과 부등식',
    },
    {
      'unit': '경우의 수',
      'title': '합의 법칙·곱의 법칙\n순열과 조합 마스터',
      'badge': '고1 공통수학1 · III. 경우의 수',
    },
    {'unit': '행렬', 'title': '행렬의 뜻과\n성분·연산 학습하기', 'badge': '고1 공통수학1 · IV. 행렬'},
  ];

  int _requestId = 0;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final requestId = ++_requestId;
    final records = StudentLearningRecords(_repo);
    final nextFuture = records.nextRoadmapStep();
    try {
      final overview = await records.overview();
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _streak = overview.streak;
        _todayLearningCount = overview.todaySessions;
        _totalXp = overview.xp;
        _attemptCount = overview.attempts;
        _correctCount = overview.correct;
        _learningDays = overview.days;
        _todayDay = overview.today;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _loading = false;
          _loadError = '학습 정보를 불러오지 못했어요.';
        });
      }
    }
    final next = await nextFuture;
    if (mounted && requestId == _requestId) setState(() => _nextStep = next);
  }

  Future<void> _openRoadmap() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ServerRoadmapScreen(repository: _repo)),
    );
    if (!mounted) return;
    setState(() => _preferRoadmap = true);
    await refresh();
  }

  void _cycleRecommendedUnit() {
    setState(() {
      _preferRoadmap = false;
      _recommendedIndex =
          (_recommendedIndex + 1) % _highSchoolGrade1Units.length;
      final unitName = _highSchoolGrade1Units[_recommendedIndex]['unit']!;
      _recommendationReason = '🎯 고1 공통수학1 [$unitName] 단원이 선택되었어요!';
    });
  }

  Future<void> _openLevelTestSheet() async {
    final result = await showConceptLevelTest(
      context,
      concepts: curriculumConceptChecklist(),
      repository: _repo,
    );
    if (!mounted || result == null || result.answers.isEmpty) return;
    final review = result.answers.values
        .where((v) => v == 'unsure' || v == 'unknown')
        .length;
    setState(
      () => _diagnosedWeakConcept = review > 0 ? '복습할 개념 $review개' : '개념 체크 기록',
    );
    widget.onNavigate(2);
  }

  Future<void> _startQuickProblemSolve() async {
    final step = _suggestedStep;
    final selectedUnit = step == null
        ? _highSchoolGrade1Units[_recommendedIndex]['unit']!
        : '${step['skill_name'] ?? '추천 개념'}';

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ProblemScreen(
          topic: selectedUnit,
          repository: _repo,
          questionService: ServerQuestionService(
            unit: selectedUnit,
            skillCode: step?['skill_code'] as String?,
            repository: _repo,
          ),
        ),
      ),
    );

    if (mounted) {
      await refresh();
    }
  }

  void _showNotificationSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: _deepPurple,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '알림 센터',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: _lightPurple,
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: _deepPurple,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    '오늘 1문제만 풀이 찍어 분석해볼까요?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    '하단 중앙 카메라 버튼을 눌러 공책 풀이를 바로 진단해 보세요.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF7E6),
                    child: Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFD97706),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    _loading || _loadError != null
                        ? '학습 정보를 확인하고 있어요'
                        : '누적 $_totalXp XP · 연속 학습 $_streak일',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text(
                    '오늘의 퀘스트를 완료하고 보상 골드와 배지를 획득하세요.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth < 360 ? 18.0 : 24.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              120,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildGreetingHeader(),
                      const SizedBox(height: 18),
                      _buildAssessmentCard(),
                      const SizedBox(height: 14),
                      _buildLearningCard(),
                      const SizedBox(height: 24),
                      _buildAttendanceCard(),
                      const SizedBox(height: 24),
                      _buildShortcutCards(context),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGreetingHeader() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            '사용자님 , 오늘도 화이팅~!!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: _textColor,
              letterSpacing: -0.3,
            ),
          ),
        ),
        IconButton(
          onPressed: _showNotificationSheet,
          tooltip: '알림 확인',
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(
                Icons.notifications_none_rounded,
                size: 28,
                color: _textColor,
              ),
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B35),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssessmentCard() {
    return Material(
      color: _lightPurple,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openLevelTestSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '내 수학 실력 알아보기',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _diagnosedWeakConcept != null
                          ? '개념 체크 기록 · 복습할 부분을 확인해요'
                          : '빵꾸난 개념을 채울 수 있어요',
                      style: const TextStyle(fontSize: 14, color: _textColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// AI 알고리즘 분석 & 고1 단원 전환이 적용된 '오늘의 맞춤 학습' 카드
  Widget _buildLearningCard() {
    final currentItem = _highSchoolGrade1Units[_recommendedIndex];
    final step = _suggestedStep;

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: _lightPurple,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      step == null ? '오늘의 단원 연습' : '오늘의 맞춤 학습',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _deepPurple,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        step == null ? currentItem['badge']! : '로드맵 추천',
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _deepPurple,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _cycleRecommendedUnit,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shuffle_rounded, size: 15, color: _deepPurple),
                      SizedBox(width: 3),
                      Text(
                        '다른 단원',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _deepPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            step == null
                ? currentItem['title']!
                : '${step['skill_name'] ?? '다음 추천 개념'}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1.32,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            step == null
                ? _recommendationReason
                : '${step['reason'] ?? '로드맵의 다음 학습 단계예요.'}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _mutedColor,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: _startQuickProblemSolve,
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step == null ? '${currentItem['unit']} 문제 풀기' : '추천 개념 문제 풀기',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.play_arrow_rounded, size: 22),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _openRoadmap,
            icon: const Icon(Icons.route_rounded),
            label: const Text('내 학습 로드맵'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _deepPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard() {
    final available = !_loading && _loadError == null;

    String title;
    if (_loading) {
      title = '학습 기록 불러오는 중…';
    } else if (_loadError != null) {
      title = _loadError!;
    } else if (_streak == 0) {
      title = '오늘부터 연속 학습을 시작해 보세요!';
    } else {
      title = '$_streak일 연속 학습 기록 🔥';
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _textColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.5,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 8),
          if (available) ...[
            Text(
              _todayLearningCount > 0
                  ? '오늘 학습 기록 · $_todayLearningCount회'
                  : '오늘은 아직 학습 기록이 없어요.',
              style: const TextStyle(fontSize: 13, color: _mutedColor),
            ),
            const SizedBox(height: 8),
            Text(
              '누적 풀이 $_attemptCount회 · 정답 $_correctCount회',
              style: const TextStyle(fontSize: 13, color: _mutedColor),
            ),
            const SizedBox(height: 8),
            Text(
              '누적 $_totalXp XP',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _purple,
              ),
            ),
          ],
          if (_loadError != null)
            TextButton(onPressed: refresh, child: const Text('다시 불러오기')),
          const SizedBox(height: 20),
          const Text(
            '최근 7일 · 학습 기록',
            style: TextStyle(fontSize: 12, color: _mutedColor),
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(7, (index) {
              final day = _todayDay - 6 + index;
              final learned = available && _learningDays.contains(day);
              final date = DateTime.fromMillisecondsSinceEpoch(
                day * Duration.millisecondsPerDay,
                isUtc: true,
              );

              return Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 36),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: learned
                                  ? _purple
                                  : const Color(0xFFF4F4F4),
                              shape: BoxShape.circle,
                            ),
                            child: learned
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      !available
                          ? '—'
                          : index == 6
                          ? '오늘'
                          : '${date.month}/${date.day}',
                      style: const TextStyle(fontSize: 10, color: _mutedColor),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutCards(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildShortcutCard(
            title: '오늘의 퀘스트',
            graphic: Transform.rotate(
              angle: -0.22,
              child: const Icon(
                Icons.edit_note_rounded,
                size: 108,
                color: _textColor,
              ),
            ),
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => QuestScreen(repository: _repo),
                ),
              );
              if (mounted) await refresh();
            },
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: _buildShortcutCard(
            title: '오답',
            graphic: Image.asset(
              'img/wrong_answer.png',
              width: 104,
              height: 104,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Transform.rotate(
                  angle: -0.15,
                  child: const Icon(
                    Icons.menu_book_rounded,
                    size: 96,
                    color: _textColor,
                  ),
                );
              },
            ),
            showCheck: false,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => WrongAnswerScreen(repository: _repo),
                ),
              );
              if (mounted) await refresh();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutCard({
    required String title,
    required Widget graphic,
    required VoidCallback onTap,
    bool showCheck = false,
  }) {
    return Material(
      color: const Color(0xFFF0F0F0),
      borderRadius: BorderRadius.circular(36),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 108,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    graphic,
                    if (showCheck)
                      Positioned(
                        right: 4,
                        top: 6,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: Color(0xFF3DB366),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: _textColor,
                            size: 26,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
