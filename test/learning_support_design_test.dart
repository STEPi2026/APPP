import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepi/screens/learning_support_screen.dart';
import 'package:stepi/screens/space_cartoon_painters.dart';
import 'package:stepi/services/api.dart';
import 'package:stepi/services/tutor_help_service.dart';

void main() {
  for (final hint in [true, false]) {
    testWidgets(
      '${hint ? 'hint' : 'concept'} support fits narrow screens with enlarged text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: LearningSupportScreen(
              problemTitle: '나머지정리와 다항식의 연산',
              request: ({String? stage, String? skillCode}) async =>
                  TutorHelpResult(
                    actionId: 1,
                    actionType: hint ? 'SOCRATIC_HINT' : 'CONCEPT_REVIEW',
                    hintLevel: hint ? 3 : null,
                    message: '개념부터 천천히 살펴볼까요?',
                    explanation: hint
                        ? null
                        : '문제에서 주어진 조건을 먼저 확인해 보세요. 개념을 살펴본 뒤 다시 도전해 봐요.',
                    nextStage: hint ? null : 'example',
                  ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CrewmateMascotBadge), findsOneWidget);
        expect(find.text('원래 문제 다시 풀기').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text(hint ? '다음 도움 보기' : '다음 단계'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  const capture = bool.fromEnvironment('CAPTURE_SUPPORT_PREVIEW');
  const output = String.fromEnvironment('PREVIEW_OUTPUT_DIR');
  for (final error in [true, false]) {
    testWidgets(
      'export ${error ? 'error' : 'content'} support design preview',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final font = File('C:/Windows/Fonts/malgun.ttf');
        if (font.existsSync()) {
          final bytes = font.readAsBytesSync();
          for (final family in ['PreviewKorean', 'Roboto', 'Ahem']) {
            await tester.runAsync(
              () => (FontLoader(
                family,
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load(),
            );
          }
        }
        final icons = File(
          'C:/Users/chohs/development/flutter_windows_3.47.6-stable/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (icons.existsSync()) {
          final bytes = icons.readAsBytesSync();
          await tester.runAsync(
            () => (FontLoader(
              'MaterialIcons',
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load(),
          );
        }
        const key = ValueKey('support-preview');
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'PreviewKorean',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF9B7EFA),
                ),
              ),
              home: LearningSupportScreen(
                problemTitle: '나머지정리',
                request: ({String? stage, String? skillCode}) async {
                  if (error) {
                    throw const ApiException(
                      statusCode: 503,
                      code: 'AI_CATALOG_NOT_READY',
                      message: 'pending',
                    );
                  }
                  return const TutorHelpResult(
                    actionId: 1,
                    actionType: 'CONCEPT_REVIEW',
                    message: '나머지정리의 핵심부터 함께 볼까요?',
                    explanation: '다항식 P(x)를 x − a로 나눈 나머지는 P(a)와 같아요.\n\n나누는 식을 0으로 만드는 값을 찾아, 다항식에 대입해 보세요.',
                    nextStage: 'example',
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(key),
        );
        final image = (await tester.runAsync(
          () => boundary.toImage(pixelRatio: 2),
        ))!;
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        );
        final directory = Directory(output);
        directory.createSync(recursive: true);
        File('${directory.path}/STEPi_학습도움_${error ? '오류' : '개념'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        expect(tester.takeException(), isNull);
      },
      skip: !capture || output.isEmpty,
    );
  }
}
