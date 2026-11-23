import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/concept_check.dart';
import 'space_cartoon_painters.dart';

class GalaxyPlanetItem {
  final String id, name;
  final Color primaryColor, secondaryColor;
  final List<ConceptCheckItem> concepts;
  const GalaxyPlanetItem({
    required this.id,
    required this.name,
    required this.primaryColor,
    required this.secondaryColor,
    required this.concepts,
  });
}

class GalaxySelection {
  final int? planetIndex;
  final bool startTest;
  const GalaxySelection({this.planetIndex, this.startTest = false});
}

class ExpandedGalaxyDialog extends StatefulWidget {
  final List<GalaxyPlanetItem> planets;
  final ConceptCheckSnapshot snapshot;
  const ExpandedGalaxyDialog({
    super.key,
    required this.planets,
    this.snapshot = const ConceptCheckSnapshot(),
  });
  @override
  State<ExpandedGalaxyDialog> createState() => _ExpandedGalaxyDialogState();
}

class _ExpandedGalaxyDialogState extends State<ExpandedGalaxyDialog> {
  static const purple = Color(0xFF7C5CFA), light = Color(0xFFF3EEFF);
  final transform = TransformationController();
  Size? viewport;
  Size world = const Size(1000, 800);
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  void _fit() {
    final size = viewport;
    if (size == null) return;
    final scale =
        math.min(size.width / world.width, size.height / world.height) * 0.94;
    transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        (size.width - world.width * scale) / 2,
        (size.height - world.height * scale) / 2,
        0,
      );
  }

  void _zoom(double multiplier) {
    final size = viewport;
    if (size == null) return;
    final old = transform.value;
    final scale = old.getMaxScaleOnAxis();
    final next = (scale * multiplier).clamp(0.2, 2.5);
    final ratio = next / scale;
    transform.value = Matrix4.diagonal3Values(next, next, 1)
      ..setTranslationRaw(
        size.width / 2 - (size.width / 2 - old.storage[12]) * ratio,
        size.height / 2 - (size.height / 2 - old.storage[13]) * ratio,
        0,
      );
  }

  Widget _planet(int index, GalaxyPlanetItem planet, double width) {
    final ids = planet.concepts.map((c) => c.id).toSet();
    final records = widget.snapshot.answers.entries.where(
      (e) => ids.contains(e.key) || e.key.startsWith('${planet.id}:server:'),
    );
    final checked = records.length;
    final review = records
        .where((e) => ['unsure', 'unknown'].contains(e.value))
        .length;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () =>
              Navigator.pop(context, GalaxySelection(planetIndex: index)),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xDD211345),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: planet.primaryColor.withAlpha(210),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CartoonPlanetOrb(
                  planetId: planet.id,
                  primaryColor: planet.primaryColor,
                  secondaryColor: planet.secondaryColor,
                  size: 100,
                ),
                const SizedBox(height: 6),
                Text(
                  planet.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: light,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    checked == 0
                        ? '레벨테스트로 개념 확인'
                        : '자가 체크 $checked개 · 복습 $review개',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: purple,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  planet.concepts
                      .map((c) => c.unit)
                      .toSet()
                      .take(3)
                      .join(' · '),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE1D6F8),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: 1240,
      height: MediaQuery.sizeOf(context).height * 0.92,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 6),
            child: Row(
              children: [
                const CrewmateMascotBadge(
                  size: 34,
                  suitColor: Color(0xFFCBB2FC),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '나의 우주 전체 맵',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF171717),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '행성을 누르면 원래 계통도의 세부 단원으로 이동해요.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF777777),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: '전체 맵 닫기',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        const GalaxySelection(startTest: true),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                      style: FilledButton.styleFrom(
                        backgroundColor: purple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      label: const Text('레벨테스트'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _zoom(1 / 1.25),
                  tooltip: '맵 축소',
                  icon: const Icon(Icons.remove_circle_outline, color: purple),
                ),
                IconButton(
                  onPressed: () => _zoom(1.25),
                  tooltip: '맵 확대',
                  icon: const Icon(Icons.add_circle_outline, color: purple),
                ),
                IconButton(
                  onPressed: _fit,
                  tooltip: '전체 맵 맞추기',
                  icon: const Icon(Icons.fit_screen_rounded, color: purple),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  if (viewport != size) {
                    viewport = size;
                    world = Size(
                      math.max(size.width, 680),
                      math.max(size.height, 800),
                    );
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _fit();
                    });
                  }
                  final offsets = [
                    Offset(world.width * 0.25, world.height * 0.27),
                    Offset(world.width * 0.75, world.height * 0.27),
                    Offset(world.width * 0.25, world.height * 0.73),
                    Offset(world.width * 0.75, world.height * 0.73),
                  ];
                  final tileWidth = math.min(world.width * 0.42, 350.0);
                  return ColoredBox(
                    color: const Color(0xFF160F37),
                    child: GestureDetector(
                      onDoubleTap: () => _zoom(1.5),
                      child: InteractiveViewer(
                        key: const ValueKey('expanded-galaxy-viewer'),
                        transformationController: transform,
                        constrained: false,
                        minScale: 0.2,
                        maxScale: 2.5,
                        boundaryMargin: const EdgeInsets.all(300),
                        child: SizedBox(
                          width: world.width,
                          height: world.height,
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: CustomPaint(
                                  painter: CartoonSpaceBackgroundPainter(
                                    twinkleValue: 0.55,
                                  ),
                                ),
                              ),
                              for (
                                int i = 0;
                                i < widget.planets.length && i < offsets.length;
                                i++
                              )
                                Positioned(
                                  left: offsets[i].dx - tileWidth / 2,
                                  top: offsets[i].dy - 150,
                                  child: _planet(
                                    i,
                                    widget.planets[i],
                                    tileWidth,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              '드래그로 이동 · 두 손가락/마우스 휠로 확대 · 자가 체크는 실제 숙련도와 구분돼요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: Color(0xFF777777),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
