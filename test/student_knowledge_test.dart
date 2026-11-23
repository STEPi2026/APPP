import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/screens/learning_tab.dart';
import 'package:stepi/screens/knowledge_widgets.dart';
import 'package:stepi/screens/problem_screen.dart';
import 'package:stepi/screens/skill_tree_tab.dart';
import 'package:stepi/screens/student_report_panel.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/services/question_service.dart';
import 'package:stepi/services/student_knowledge.dart';

List<JsonMap> concepts = [
  {
    'id': 1,
    'code': 'STP-1-001',
    'name': '다항식의 덧셈과 뺄셈',
    'subject': '다항식',
    'grade_level': '고등학교 / 공통수학1·2022 개정',
  },
  {
    'id': 2,
    'code': 'C-UNASSESSED',
    'name': '처음 만나는 개념',
    'subject': '다항식',
    'grade_level': '고등학교 / 공통수학1·2022 개정',
  },
];
List<JsonMap> skills = [
  {
    'id': 11,
    'code': 'CANONICAL-SKILL',
    'name': '동류항 정리하기',
    'concept_code': 'STP-1-001',
    'description': '같은 문자와 차수를 가진 항을 모아요.',
  },
];
JsonMap map(double value) => {
  'nodes': [
    {
      'code': 'STP-1-001',
      'type': 'CONCEPT',
      'mastery_score': value,
      'level': 2,
    },
    {
      'code': 'CANONICAL-SKILL',
      'type': 'SKILL',
      'mastery_score': .4,
      'level': 2,
    },
    // A stale numeric value must never override the server's UNASSESSED state.
    {
      'code': 'C-UNASSESSED',
      'type': 'CONCEPT',
      'mastery_score': 1,
      'level': 'UNASSESSED',
    },
  ],
};
Future<dynamic> read(String path, Map<String, String> query) async =>
    switch (path) {
      '/api/v1/concepts' => {'items': concepts},
      '/api/v1/skills' => {'items': skills},
      '/api/v1/curriculum/graph' => {
        'edges': [
          {
            'type': 'CONCEPT_SKILL',
            'source': 'concept:STP-1-001',
            'target': 'skill:CANONICAL-SKILL',
          },
        ],
      },
      '/api/v1/me/knowledge-map' => map(.7),
      '/api/v1/skills/CANONICAL-SKILL/contents' => {'items': []},
      '/api/v1/me/learning-summary' => {
        'total_attempts': 0,
        'correct_attempts': 0,
        'incorrect_attempts': 0,
      },
      '/api/v1/me/gamification' => {'xp': 0, 'level': 1, 'current_streak': 0},
      '/api/v1/me/knowledge-map/summary' => {
        'grades': [
          {
            'grade_level': '공통수학1',
            'concept_count': 42,
            'assessed_concept_count': 1,
            'average_mastery_score': .7,
          },
        ],
      },
      '/api/v1/friends/leaderboard' => {
        'items': [
          {
            'user_id': 1,
            'display_name': '나의 계정',
            'level': 1,
            'current_streak': 0,
            'weekly_xp': 0,
            'rank': null,
            'is_me': true,
          },
        ],
      },
      '/api/v1/me/roadmap' => throw const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: '',
      ),
      _ => throw StateError(path),
    };
LearningRepository repo({ApiRead? loader}) => LearningRepository(
  read: loader ?? read,
  write: (method, path, body) async =>
      throw StateError('Unexpected write $path'),
);

Future<void> tap(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 500));
}

Widget app(Widget child) => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFA)),
  ),
  home: Scaffold(body: child),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  test('only canonical evaluated state produces a score', () async {
    final knowledge = await StudentKnowledge.load(repo());
    expect(StudentKnowledge.score(knowledge.conceptStates['STP-1-001']), .7);
    expect(
      StudentKnowledge.score(knowledge.conceptStates['C-UNASSESSED']),
      isNull,
    );
    expect(StudentKnowledge.score(null), isNull);
    expect(StudentKnowledge.score({'mastery_score': 70, 'level': 2}), isNull);
    expect(knowledge.skillsFor('STP-1-001').single['code'], 'CANONICAL-SKILL');
  });
  test('failed knowledge does not fabricate an unassessed success', () async {
    await expectLater(
      StudentKnowledge.load(
        repo(
          loader: (path, query) async => path.endsWith('knowledge-map')
              ? <String, dynamic>{}
              : await read(path, query),
        ),
      ),
      throwsFormatException,
    );
  });
  testWidgets(
    'learning shows server mastery and refreshes after accepted work',
    (tester) async {
      double value = .7;
      final repository = repo(
        loader: (path, query) async => path.endsWith('knowledge-map')
            ? map(value)
            : await read(path, query),
      );
      await tester.pumpWidget(
        app(LearningTab(onExperienceChanged: () {}, repository: repository)),
      );
      await tester.pumpAndSettle();
      expect(find.text('숙련도 70%'), findsOneWidget);
      expect(find.text('아직 평가 전'), findsOneWidget);
      expect(find.textContaining('완료'), findsNothing);
      value = .2;
      LearningRepository.notifyProgressChanged();
      await tester.pumpAndSettle();
      expect(find.text('숙련도 20%'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('offline uses retry and never demo progress or fake exams', (
    tester,
  ) async {
    bool offline = true;
    await tester.pumpWidget(
      app(
        LearningTab(
          onExperienceChanged: () {},
          repository: repo(
            loader: (path, query) async {
              if (offline) throw StateError('offline');
              return await read(path, query);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('다시 불러오기'), findsOneWidget);
    expect(find.textContaining('숙련도 70%'), findsNothing);
    offline = false;
    await tap(tester, '다시 불러오기');
    await tester.pumpAndSettle();
    expect(find.text('숙련도 70%'), findsOneWidget);
    await tap(tester, '기출문제');
    expect(find.text('기출문제를 준비하고 있어요'), findsOneWidget);
    expect(find.textContaining('2026학년도 9월'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'skill practice receives exact server Skill, without local completion',
    (tester) async {
      final paths = <String>[];
      await tester.pumpWidget(
        app(
          LearningTab(
            onExperienceChanged: () {},
            repository: repo(
              loader: (path, query) async {
                paths.add(path);
                return await read(path, query);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, '다항식의 덧셈과 뺄셈');
      await tap(tester, '동류항 정리하기');
      await tester.pumpAndSettle();
      expect(find.text('숙련도 40%'), findsWidgets);
      await tester.scrollUntilVisible(
        find.textContaining('학습 자료를 준비'),
        150,
        scrollable: find
            .ancestor(of: find.text('개념 학습'), matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('학습 자료를 준비'), findsOneWidget);
      expect(paths, contains('/api/v1/skills/CANONICAL-SKILL/contents'));
      expect(find.textContaining('시청 완료'), findsNothing);
      await tap(tester, '이 개념 문제 풀기');
      await tester.pumpAndSettle();
      final screen = tester.widget<ProblemScreen>(find.byType(ProblemScreen));
      expect(
        (screen.questionService as ServerQuestionService).skillCode,
        'CANONICAL-SKILL',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('390 wide report has zero counts and survives ranking failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = repo(
      loader: (path, query) async {
        if (path.contains('leaderboard')) throw StateError('ranking offline');
        return await read(path, query);
      },
    );
    final knowledge = await StudentKnowledge.load(repository);
    await tester.pumpWidget(
      app(
        StudentReportPanel(
          repository: repository,
          knowledge: knowledge,
          loading: false,
          onRefresh: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0'), findsWidgets);
    expect(find.textContaining('14.2%'), findsNothing);
    expect(find.textContaining('78%'), findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('다시 불러오기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('old response cannot replace newer knowledge', (tester) async {
    final initial = Completer<dynamic>();
    int calls = 0;
    await tester.pumpWidget(
      app(
        LearningTab(
          onExperienceChanged: () {},
          repository: repo(
            loader: (path, query) async {
              if (path.endsWith('knowledge-map')) {
                calls++;
                return calls == 1 ? initial.future : map(.2);
              }
              return await read(path, query);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    LearningRepository.notifyProgressChanged();
    await tester.pumpAndSettle();
    initial.complete(map(.9));
    await tester.pumpAndSettle();
    expect(find.text('숙련도 20%'), findsOneWidget);
    expect(find.text('숙련도 90%'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('satellites never use static mastered or locked status', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(SkillTreeTab(onExperienceChanged: () {}, repository: repo())),
    );
    await tester.pump(const Duration(seconds: 1));
    await tap(tester, '변화와 관계');
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('완료 ✓'), findsNothing);
    expect(find.textContaining('잠김'), findsNothing);
    expect(find.textContaining('여기를 하기'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  const capture = bool.fromEnvironment('CAPTURE_KNOWLEDGE_PREVIEW');
  const output = String.fromEnvironment('PREVIEW_OUTPUT_DIR');
  testWidgets('preview original card style with fixture responses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final family in ['PreviewKorean', 'Roboto', 'Ahem']) {
      await tester.runAsync(
        () =>
            (FontLoader(family)..addFont(
                  Future.value(
                    ByteData.sublistView(
                      File('C:/Windows/Fonts/malgun.ttf').readAsBytesSync(),
                    ),
                  ),
                ))
                .load(),
      );
    }
    await tester.runAsync(
      () =>
          (FontLoader('MaterialIcons')..addFont(
                Future.value(
                  ByteData.sublistView(
                    File(
                      'C:/Users/chohs/development/flutter_windows_3.47.6-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
                    ).readAsBytesSync(),
                  ),
                ),
              ))
              .load(),
    );
    const key = ValueKey('preview');
    Future<void> show(Widget child, String filename) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            key: ValueKey(filename),
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'PreviewKorean',
              colorScheme: ColorScheme.fromSeed(seedColor: knowledgePurple),
            ),
            home: Scaffold(
              appBar: AppBar(
                title: const Text(
                  'STEPi',
                  style: TextStyle(
                    color: knowledgePurple,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              body: child,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Redraw retained text layers before capturing multiple screens in one VM.
      for (final renderObject in tester.allRenderObjects) {
        renderObject.markNeedsPaint();
      }
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1.5),
      ))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.png),
      ))!;
      Directory(output).createSync(recursive: true);
      File('$output/$filename.png')
          .writeAsBytesSync(bytes.buffer.asUint8List());
      image.dispose();
    }

    final repository = repo();
    await show(
      LearningTab(onExperienceChanged: () {}, repository: repository),
      'STEPi_학습탭_숙련도',
    );
    await show(
      StudentReportPanel(
        repository: repository,
        knowledge: await StudentKnowledge.load(repository),
        loading: false,
        onRefresh: () {},
      ),
      'STEPi_학습리포트',
    );
    await show(
      LearningTab(
        key: const ValueKey('offline'),
        onExperienceChanged: () {},
        repository: repo(
          loader: (path, query) async => throw StateError('offline'),
        ),
      ),
      'STEPi_학습탭_연결안내',
    );
    expect(tester.takeException(), isNull);
  }, skip: !capture || output.isEmpty);
}
