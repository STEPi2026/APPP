import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/screens/problem_screen.dart';
import 'package:stepi/screens/problem_result_dialog.dart';
import 'package:stepi/services/learning_repository.dart';

import 'normal_problem_flow_test.dart' as fixture;

void main() {
  const capture = bool.fromEnvironment('CAPTURE_PROBLEM_PREVIEW');
  const output = String.fromEnvironment('PREVIEW_OUTPUT_DIR');
  testWidgets('preview original workspace with server completion card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = File('C:/Windows/Fonts/malgun.ttf');
    if (font.existsSync()) {
      for (final family in ['PreviewKorean', 'Roboto', 'Ahem']) {
        await tester.runAsync(
          () =>
              (FontLoader(family)..addFont(
                    Future.value(ByteData.sublistView(font.readAsBytesSync())),
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
                  Future.value(ByteData.sublistView(icons.readAsBytesSync())),
                ))
                .load(),
      );
    }
    final repo = LearningRepository(
      read: fixture.read,
      write: (method, path, body) async =>
          path.endsWith('/learning-sessions') ? {'id': 51} : fixture.accepted(),
    );
    const key = ValueKey('server-problem-preview');
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
          home: ProblemScreen(
            repository: repo,
            questionService: fixture.FixedQuestions(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> save(String filename) async {
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

    await save('STEPi_서버풀이_문제');
    await fixture.enterAnswer(tester, '5');
    await fixture.tapText(tester, '제출하기');
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('img/badges/BDG-085.png'),
        tester.element(find.byType(ProblemResultDialog)),
      ),
    );
    await tester.pumpAndSettle();
    await save('STEPi_서버풀이_결과');
    expect(tester.takeException(), isNull);
  }, skip: !capture || output.isEmpty);
}
