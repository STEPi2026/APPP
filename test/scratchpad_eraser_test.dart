import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stepi/models/scratchpad_strokes.dart';
import 'package:stepi/screens/problem_screen.dart';
import 'package:stepi/services/learning_repository.dart';

import 'normal_problem_flow_test.dart' as fixture;

Future<void> dragStroke(WidgetTester tester, Offset from, Offset to) async {
  final origin = tester.getTopLeft(
    find.byKey(const ValueKey('scratchpad-surface')),
  );
  final gesture = await tester.startGesture(origin + from);
  for (var i = 1; i <= 8; i++) {
    await gesture.moveTo(origin + Offset.lerp(from, to, i / 8)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<ui.Image> capture(WidgetTester tester, Key key) async =>
    (await tester.runAsync(
      () => tester
          .renderObject<RenderRepaintBoundary>(find.byKey(key))
          .toImage(pixelRatio: 1),
    ))!;

Future<List<int>> pixel(WidgetTester tester, Offset at) async {
  final image = await capture(tester, const ValueKey('scratchpad-canvas'));
  final data = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final index = (at.dy.round() * image.width + at.dx.round()) * 4;
  final result = data.buffer.asUint8List().sublist(index, index + 4);
  image.dispose();
  return result;
}

bool isInk(List<int> rgba) => rgba[3] > 240 && rgba[0] < 100;

void main() {
  test('eraser touches sparse stroke segments and sweeps across them', () {
    const stroke = [Offset(10, 50), Offset(250, 50)];
    expect(
      scratchpadStrokeHit(stroke, const Offset(130, 50), const Offset(130, 50)),
      isTrue,
    );
    expect(
      scratchpadStrokeHit(stroke, const Offset(130, 5), const Offset(130, 100)),
      isTrue,
    );
    expect(
      scratchpadStrokeHit(stroke, const Offset(130, 80), const Offset(130, 80)),
      isFalse,
    );
    expect(
      scratchpadStrokeHit(stroke, const Offset(90, 55), const Offset(190, 55)),
      isTrue,
    );
    expect(
      scratchpadStrokeHit(stroke, const Offset(300, 50), const Offset(350, 50)),
      isFalse,
    );
    expect(scratchpadStrokeHit(const [], Offset.zero, Offset.zero), isFalse);
    expect(
      scratchpadStrokeHit(
        const [Offset(50, 50)],
        const Offset(50, 0),
        const Offset(50, 100),
      ),
      isTrue,
    );
    expect(
      scratchpadStrokeHit(
        const [Offset(50, 50), Offset(50, 50)],
        const Offset(55, 55),
        const Offset(55, 55),
      ),
      isTrue,
    );
  });

  testWidgets(
    'stroke eraser removes whole touched stroke, keeps other ink and grid, and switches back to pen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(780, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const previewPath = String.fromEnvironment('SCRATCHPAD_PREVIEW_OUTPUT');
      if (previewPath.isNotEmpty) {
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
      }
      var writes = 0;
      final repo = LearningRepository(
        read: fixture.read,
        write: (m, p, b) async {
          writes++;
          return {};
        },
      );
      const frame = ValueKey('scratchpad-preview');
      await tester.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              fontFamily: previewPath.isEmpty ? null : 'PreviewKorean',
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
      await fixture.enterAnswer(tester, '5');
      final size = tester.getSize(
        find.byKey(const ValueKey('scratchpad-surface')),
      );
      final firstY = (size.height * .4).floorToDouble(),
          secondY = (size.height * .65).floorToDouble();
      final left = Offset(50, firstY),
          right = Offset(size.width - 50, firstY),
          other = Offset(100, secondY);
      await dragStroke(tester, left, right);
      await dragStroke(
        tester,
        Offset(50, secondY),
        Offset(size.width - 50, secondY),
      );
      expect(isInk(await pixel(tester, left + const Offset(10, 0))), isTrue);
      expect(isInk(await pixel(tester, right - const Offset(10, 0))), isTrue);
      expect(isInk(await pixel(tester, other)), isTrue);
      final gridBefore = await pixel(tester, const Offset(18, 72));
      await tester.tap(find.byKey(const ValueKey('scratchpad-eraser')));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(
        find.byKey(const ValueKey('scratchpad-surface')),
      );
      await tester.tapAt(origin + Offset(size.width / 2, firstY));
      await tester.pumpAndSettle();
      // Both ends disappear, even though the eraser touched only the middle.
      expect(isInk(await pixel(tester, left + const Offset(10, 0))), isFalse);
      expect(isInk(await pixel(tester, right - const Offset(10, 0))), isFalse);
      expect(isInk(await pixel(tester, other)), isTrue);
      expect(await pixel(tester, const Offset(18, 72)), gridBefore);
      expect(find.text('입력한 답: 5'), findsOneWidget);
      if (previewPath.isNotEmpty) {
        final image = await capture(tester, frame);
        final png = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        ))!;
        File(previewPath).parent.createSync(recursive: true);
        File(previewPath).writeAsBytesSync(png.buffer.asUint8List());
        image.dispose();
      }
      await tester.tap(find.byKey(const ValueKey('scratchpad-pen')));
      await tester.pumpAndSettle();
      await dragStroke(tester, left, left + const Offset(100, 0));
      expect(isInk(await pixel(tester, left + const Offset(10, 0))), isTrue);
      expect(isInk(await pixel(tester, other)), isTrue);
      // A fast erase crosses the second stroke between pointer samples.
      await tester.tap(find.byKey(const ValueKey('scratchpad-eraser')));
      await tester.pumpAndSettle();
      final swipe = await tester.startGesture(
        origin + Offset(size.width / 2, secondY - 30),
      );
      await swipe.moveTo(origin + Offset(size.width / 2, secondY + 30));
      await swipe.up();
      await tester.pumpAndSettle();
      expect(isInk(await pixel(tester, other)), isFalse);
      expect(isInk(await pixel(tester, left + const Offset(10, 0))), isTrue);
      await tester.tap(find.byKey(const ValueKey('scratchpad-clear')));
      await tester.pumpAndSettle();
      expect(isInk(await pixel(tester, left + const Offset(10, 0))), isFalse);
      expect(await pixel(tester, const Offset(18, 72)), gridBefore);
      expect(find.text('입력한 답: 5'), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
