import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/concept_check.dart';
import 'package:stepi/services/learning_repository.dart';
import 'package:stepi/screens/concept_level_test_dialog.dart';
import 'package:stepi/screens/expanded_galaxy_dialog.dart';
import 'package:stepi/screens/skill_tree_tab.dart';

const concepts = [
  ConceptCheckItem(
    id: 'p1:c1',
    planetId: 'p1',
    area: '변화와 관계',
    unit: '일차방정식',
    title: '이항의 원리를 설명할 수 있어요.',
    grade: 7,
  ),
  ConceptCheckItem(
    id: 'p2:c2',
    planetId: 'p2',
    area: '수와 연산',
    unit: '다항식',
    title: '나머지정리를 활용할 수 있어요.',
    grade: 10,
  ),
];
List<GalaxyPlanetItem> get planets => [
  for (int i = 0; i < 4; i++)
    GalaxyPlanetItem(
      id: 'p${i + 1}',
      name: ['변화와 관계', '수와 연산', '자료와 가능성', '도형과 측정'][i],
      primaryColor: [
        const Color(0xFFB388FF),
        const Color(0xFF4DD0E1),
        const Color(0xFFFFD54F),
        const Color(0xFFFF8A80),
      ][i],
      secondaryColor: const Color(0xFF7652FF),
      concepts: concepts.where((c) => c.planetId == 'p${i + 1}').toList(),
    ),
];

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'curriculum concept identifiers are unique and include all four areas',
    () {
      final catalog = curriculumConceptChecklist();
      expect(catalog, isNotEmpty);
      expect(catalog.map((c) => c.id).toSet().length, catalog.length);
      expect(catalog.map((c) => c.planetId).toSet().length, 4);
      expect(catalog.any((c) => c.grade == 6), isTrue);
      expect(catalog.any((c) => c.grade == 10), isTrue);
    },
  );
  test(
    'self-check records are scoped to account and never imply mastery',
    () async {
      final store = ConceptCheckStore();
      await store.save(
        7,
        const ConceptCheckSnapshot(grade: 7, answers: {'p1:c1': 'unsure'}),
      );
      final first = await store.load(7);
      expect(first.answers['p1:c1'], 'unsure');
      expect(first.grade, 7);
      expect((await store.load(8)).answers, isEmpty);
      expect(first.count('known', concepts), 0);
    },
  );
  testWidgets(
    'self check persists selections without a server grading request',
    (tester) async {
      final writes = <String>[];
      final repo = LearningRepository(
        read: (path, query) async => {'id': 7},
        write: (method, path, body) async {
          writes.add(path);
          return {};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConceptLevelTestDialog(concepts: concepts, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tapText(tester, '개념 자가 체크');
      await tapText(tester, '배웠던 개념 체크하기');
      await tapText(tester, '알아요');
      await tapText(tester, '다음 개념');
      await tapText(tester, '모르겠어요');
      await tapText(tester, '체크 결과 보기');
      expect(find.text('알아요  1개'), findsOneWidget);
      expect(find.text('모르겠어요  1개'), findsOneWidget);
      final saved = await ConceptCheckStore().load(7);
      expect(saved.answers, {'p1:c1': 'known', 'p2:c2': 'unknown'});
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'verification uses real diagnostic IDs and does not send self confidence as answers',
    (tester) async {
      await ConceptCheckStore().save(
        7,
        const ConceptCheckSnapshot(answers: {'p1:c1': 'known'}),
      );
      final writes = <Map<String, dynamic>>[];
      final repo = LearningRepository(
        read: (path, query) async {
          if (path == '/api/v1/users/me') return {'id': 7};
          if (path.endsWith('/results')) {
            return {
              'assessed': [],
              'unassessed_skill_codes': [],
              'weak_skill_codes': [],
            };
          }
          return {'items': []};
        },
        write: (method, path, body) async {
          writes.add({'method': method, 'path': path, 'body': body});
          if (path == '/api/v1/me/student-profile') return {};
          if (path == '/api/v1/diagnostics') {
            return {
              'id': 22,
              'status': 'IN_PROGRESS',
              'answered_count': 0,
              'current_question': {'question_id': 'Q22', 'prompt': '실제 확인 문제'},
            };
          }
          return {'id': 22, 'status': 'COMPLETED', 'answered_count': 1};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ConceptLevelTestDialog(concepts: concepts, repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await tapText(tester, '기초 문제로 진단하기');
      expect(find.text('실제 확인 문제'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '42');
      await tapText(tester, '답안 제출');
      expect(writes.last, {
        'method': 'POST',
        'path': '/api/v1/diagnostics/22/answers',
        'body': {'question_id': 'Q22', 'answer': '42'},
      });
      expect(find.text('확인 문제 진단 완료!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('AI unavailable preserves completed self check', (tester) async {
    await ConceptCheckStore().save(
      7,
      const ConceptCheckSnapshot(answers: {'p1:c1': 'unknown'}),
    );
    final repo = LearningRepository(
      read: (path, q) async =>
          path == '/api/v1/users/me' ? {'id': 7} : {'items': []},
      write: (m, p, b) async {
        if (p == '/api/v1/me/student-profile') return {};
        throw const ApiException(
          statusCode: 503,
          code: 'AI_NOT_CONFIGURED',
          message: 'offline',
        );
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ConceptLevelTestDialog(concepts: concepts, repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tapText(tester, '기초 문제로 진단하기');
    expect(find.textContaining('AI 학습 지원이 아직 준비되지'), findsOneWidget);
    expect((await ConceptCheckStore().load(7)).answers['p1:c1'], 'unknown');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'expanded galaxy is wider than the old panel and zooms and selects a planet',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      GalaxySelection? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selection = await showDialog<GalaxySelection>(
                    context: context,
                    builder: (_) => ExpandedGalaxyDialog(planets: planets),
                  );
                },
                child: const Text('맵 열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('맵 열기'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Dialog)).width, greaterThan(640));
      final viewer = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('expanded-galaxy-viewer')),
      );
      final original = viewer.transformationController!.value
          .getMaxScaleOnAxis();
      await tester.tap(find.byTooltip('맵 확대'));
      await tester.pump();
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        greaterThan(original),
      );
      await tester.tap(find.byTooltip('전체 맵 맞추기'));
      await tester.pump();
      expect(
        viewer.transformationController!.value.getMaxScaleOnAxis(),
        closeTo(original, 0.001),
      );
      await tester.tap(find.text('변화와 관계'));
      await tester.pumpAndSettle();
      expect(selection!.planetIndex, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('compact dialogs preserve layout at enlarged text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(Widget child) => MaterialApp(
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: widget!,
      ),
      home: Scaffold(body: child),
    );
    final repo = LearningRepository(read: (p, q) async => {'id': 7});
    await tester.pumpWidget(
      app(ConceptLevelTestDialog(concepts: concepts, repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(app(ExpandedGalaxyDialog(planets: planets)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'existing space skill tree opens both new dialogs without changing its tabs',
    (tester) async {
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: TickerMode(
                  enabled: false,
                  child: SkillTreeTab(onExperienceChanged: () {}),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text('🪐 우주 계통도 스킬트리'), findsOneWidget);
          await tapText(tester, '우주 전체 맵 크게 보기');
          expect(find.byType(ExpandedGalaxyDialog), findsOneWidget);
          await tester.tap(find.byTooltip('전체 맵 닫기'));
          await tester.pumpAndSettle();
          await tapText(tester, '내 개념 레벨테스트');
          expect(find.byType(ConceptLevelTestDialog), findsOneWidget);
          await tester.tap(find.byTooltip('레벨테스트 닫기'));
          await tester.pumpAndSettle();
          expect(find.text('🪐 우주 계통도 스킬트리'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
        () => MockClient(
          (request) async => http.Response(
            request.url.path.endsWith('/users/me')
                ? '{"id":7}'
                : '{"xp":0,"level":1,"xp_to_next_level":50}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
    },
  );

  const capture = bool.fromEnvironment('CAPTURE_CONCEPT_PREVIEW');
  const output = String.fromEnvironment('PREVIEW_OUTPUT_DIR');
  for (final galaxy in [false, true]) {
    testWidgets(
      'preview ${galaxy ? 'expanded galaxy' : 'concept level test'}',
      (tester) async {
        tester.view.physicalSize = galaxy
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final font = File('C:/Windows/Fonts/malgun.ttf');
        if (font.existsSync()) {
          for (final family in ['PreviewKorean', 'Roboto', 'Ahem']) {
            await tester.runAsync(
              () =>
                  (FontLoader(family)..addFont(
                        Future.value(
                          ByteData.sublistView(font.readAsBytesSync()),
                        ),
                      ))
                      .load(),
            );
          }
        }
        final icons = File(
          'C:/Users/chohs/development/flutter_windows_3.47.6-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (icons.existsSync()) {
          await tester.runAsync(
            () =>
                (FontLoader('MaterialIcons')..addFont(
                      Future.value(
                        ByteData.sublistView(icons.readAsBytesSync()),
                      ),
                    ))
                    .load(),
          );
        }
        const key = ValueKey('concept-preview');
        const fixtureDir = String.fromEnvironment('CATALOG_FIXTURE_DIR');
        final repo = LearningRepository(
          read: (p, q) async {
            if (fixtureDir.isNotEmpty) {
              final filename = switch (p) {
                '/api/v1/concepts' => 'server_concepts.json',
                '/api/v1/skills' => 'server_skills.json',
                '/api/v1/curriculum/graph' => 'server_curriculum_graph.json',
                _ => null,
              };
              if (filename != null) {
                return jsonDecode(
                  File('$fixtureDir/$filename').readAsStringSync(),
                );
              }
            }
            return p == '/api/v1/users/me' ? {'id': 7} : {'items': []};
          },
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'PreviewKorean',
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF7C5CFA),
                ),
              ),
              home: Scaffold(
                backgroundColor: const Color(0xFFEEEAF8),
                body: galaxy
                    ? ExpandedGalaxyDialog(planets: planets)
                    : ConceptLevelTestDialog(
                        concepts: curriculumConceptChecklist(),
                        repository: repo,
                        satelliteId: fixtureDir.isEmpty ? null : 'sat_poly',
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
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
        File('$output/STEPi_${galaxy ? '우주전체맵' : '개념레벨테스트'}.png')
            .writeAsBytesSync(bytes.buffer.asUint8List());
        image.dispose();
        expect(tester.takeException(), isNull);
      },
      skip: !capture || output.isEmpty,
    );
  }
}
