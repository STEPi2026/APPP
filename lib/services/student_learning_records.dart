import 'api.dart';
import 'learning_repository.dart';
import 'capture_service.dart';

/// Maps server records into the existing history and review cards. A historical
/// wrong attempt stays wrong even after the server marks its problem resolved.
class StudentLearningRecords {
  final LearningRepository repo;
  StudentLearningRecords(this.repo);

  Future<List<JsonMap>> attempts() => repo.all('/api/v1/me/learning-history');
  Future<List<JsonMap>> wrongRows() =>
      repo.all('/api/v1/me/wrong-answers', {'include_resolved': 'true'});

  Future<StudentLearningOverview> overview({DateTime? now}) async {
    final data = await Future.wait<dynamic>([
      repo.get('/api/v1/me/learning-summary'),
      repo.get('/api/v1/me/gamification'),
      attempts(),
    ]);
    final summary = data[0] as JsonMap, gamification = data[1] as JsonMap;
    final history = data[2] as List<JsonMap>;
    final today = StudentLearningOverview.studyDay(now ?? DateTime.now());
    final days = <int>{}, todaySessions = <int>{};
    for (final row in history) {
      final date = DateTime.tryParse('${row['attempted_at']}');
      if (date == null) continue;
      final day = StudentLearningOverview.studyDay(date);
      if (day >= today - 6 && day <= today) days.add(day);
      if (day == today && row['session_id'] is int) {
        todaySessions.add(row['session_id']);
      }
    }
    final last = DateTime.tryParse(
      '${gamification['last_study_date']}T00:00:00+09:00',
    );
    if (last != null) {
      final day = StudentLearningOverview.studyDay(last);
      if (day >= today - 6 && day <= today) days.add(day);
    }
    final xp = gamification['xp'], streak = gamification['current_streak'];
    final attemptsCount = summary['total_attempts'],
        correct = summary['correct_attempts'];
    if (xp is! int ||
        streak is! int ||
        attemptsCount is! int ||
        correct is! int) {
      throw const FormatException('서버 학습 통계를 확인하지 못했어요.');
    }
    return StudentLearningOverview(
      today: today,
      days: days,
      todaySessions: todaySessions.length,
      xp: xp,
      streak: streak,
      attempts: attemptsCount,
      correct: correct,
    );
  }

  Future<JsonMap?> nextRoadmapStep() async {
    try {
      final plan = await repo.get('/api/v1/me/roadmap');
      if ([
        'PENDING',
        'GENERATING',
        'PROCESSING',
        'QUEUED',
      ].contains(plan['status'])) {
        return null;
      }
      final next = plan['next_skill_code'];
      if (next is! String || next.isEmpty || plan['completed'] == true) {
        return null;
      }
      for (final step in LearningRepository.items(plan, 'steps')) {
        if (step['skill_code'] == next &&
            step['ready'] == true &&
            step['completed'] != true) {
          return step;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<List<JsonMap>> _optional(Future<List<JsonMap>> Function() load) async {
    try {
      return await load();
    } catch (_) {
      return [];
    }
  }

  Future<List<JsonMap>> wrongAnswers() async {
    final data = await Future.wait([
      wrongRows(),
      _optional(
        () async => LearningRepository.items(
          await repo.get('/api/v1/me/review-queue', {'size': '100'}),
        ),
      ),
    ]);
    final due = data[1].map((r) => r['problem_id']).toSet();
    return [
      for (final row in data[0])
        if (row['problem_id'] is int)
          {
            'topic': '오답 복습',
            'completedAt': row['last_attempted_at'],
            'sourceLabel': row['problem_code'],
            'tags': <String>[
              if (row['wrong_count'] is int) '오답 ${row['wrong_count']}회',
              if (row['resolved'] == false && due.contains(row['problem_id']))
                '복습할 차례',
            ],
            'answer': <String, dynamic>{
              'problemId': row['problem_id'],
              'questionNumber': 1,
              'title': row['problem_code'],
              'question': row['question'],
              'isCorrect': false,
              'reviewCompleted': row['resolved'],
              'selectedAnswer': row['last_wrong_answer'],
              'correctAnswer': row['answer'],
              'explanation': row['explanation'],
            },
          },
    ];
  }

  Future<List<JsonMap>> history({DateTime? studyDate}) async {
    final data = await Future.wait([
      attempts(),
      _optional(() => repo.all('/api/v1/problems')),
      _optional(() => repo.all('/api/v1/concepts')),
      _optional(wrongRows),
      _optional(() => repo.all('/api/v1/captured-problems')),
    ]);
    final problems = {for (final row in data[1]) row['id']: row};
    final subjects = {for (final row in data[2]) row['code']: row['subject']};
    final wrong = {for (final row in data[3]) row['problem_id']: row};
    final captures = {
      for (final row in data[4])
        if (row['attempt_id'] is int && row['id'] is int)
          row['attempt_id']: row,
    };
    final groups = <int, List<JsonMap>>{};
    for (final row in data[0]) {
      if (studyDate != null) {
        final time = DateTime.tryParse('${row['attempted_at']}');
        final target = DateTime.utc(
          studyDate.year,
          studyDate.month,
          studyDate.day,
        );
        if (time == null ||
            StudentLearningOverview.studyDay(time) !=
                StudentLearningOverview.studyDay(target)) {
          continue;
        }
      }
      if (row['session_id'] is int) {
        groups.putIfAbsent(row['session_id'], () => []).add(row);
      }
    }
    final records = <JsonMap>[];
    for (final group in groups.entries) {
      final rows = group.value
        ..sort(
          (a, b) =>
              _date(a['attempted_at']).compareTo(_date(b['attempted_at'])),
        );
      final topics = <String>{}, answers = <JsonMap>[];
      for (final row in rows) {
        final id = row['problem_id'],
            p = problems[row['problem_id']],
            w = wrong[row['problem_id']];
        final capture = captures[row['id']];
        final codes = p?['concept_codes'];
        if (codes is List) {
          topics.addAll(codes.map((c) => subjects[c]).whereType<String>());
        }
        if (id == null) topics.add('사진 풀이');
        answers.add({
          'problemId': id,
          'attemptedAt': row['attempted_at'],
          'capturedProblemId': capture?['id'],
          'questionNumber': answers.length + 1,
          'title': row['problem_code'] ?? (id == null ? '사진 풀이' : '서버 문제'),
          'question':
              p?['question'] ??
              w?['question'] ??
              capture?['problem_text'] ??
              (id == null ? '사진 풀이 기록이에요.' : '문제 본문을 불러오지 못했어요.'),
          'selectedAnswer': row['student_answer'] ?? capture?['solution_text'],
          'isCorrect': row['is_correct'],
          'isPartialSolution':
              row['is_correct'] == null &&
              capture?['latest_analysis'] is Map &&
              CaptureService.isPartial(
                Map<String, dynamic>.from(capture!['latest_analysis']),
              ),
          'reviewCompleted': w?['resolved'],
          'correctAnswer': w?['answer'],
          'explanation': w?['explanation'],
        });
      }
      records.add({
        'sessionId': group.key,
        'completedAt': rows.last['attempted_at'],
        'topic': topics.length == 1 ? topics.single : '학습 기록',
        'answers': answers,
        'totalCount': answers.length,
        'correctCount': answers.where((a) => a['isCorrect'] == true).length,
      });
    }
    records.sort(
      (a, b) => _date(b['completedAt']).compareTo(_date(a['completedAt'])),
    );
    return records;
  }

  static DateTime _date(Object? value) =>
      DateTime.tryParse('$value') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

class StudentLearningOverview {
  final int today, todaySessions, xp, streak, attempts, correct;
  final Set<int> days;
  const StudentLearningOverview({
    required this.today,
    required this.days,
    required this.todaySessions,
    required this.xp,
    required this.streak,
    required this.attempts,
    required this.correct,
  });

  static int studyDay(DateTime date) =>
      date.toUtc().add(const Duration(hours: 9)).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
