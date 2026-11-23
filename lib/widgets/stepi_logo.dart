import 'package:flutter/material.dart';

/// Shared transparent wordmark for light and dark application backgrounds.
/// The display window keeps the existing wordmark layout and proportions.
class StepILogo extends StatelessWidget {
  final double width;
  final double borderRadius;
  const StepILogo({super.key, this.width = 104, this.borderRadius = 8});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'STEPi 로고',
    image: true,
    child: SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: 528 / 166,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Image.asset(
            'img/stepi_logo_transparent.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            excludeFromSemantics: true,
          ),
        ),
      ),
    ),
  );
}
