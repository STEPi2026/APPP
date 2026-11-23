import 'dart:math' as math;
import 'dart:ui';

/// Hit-tests an entire pen stroke against the eraser's swept circle.
/// Segment tests also catch fast gestures that skip over an ink sample.
bool scratchpadStrokeHit(
  List<Offset> stroke,
  Offset from,
  Offset to, {
  double radius = 12,
}) {
  if (stroke.isEmpty) return false;
  final radiusSquared = radius * radius;
  if (stroke.length == 1) {
    return _pointDistanceSquared(stroke.single, from, to) <= radiusSquared;
  }
  for (var i = 1; i < stroke.length; i++) {
    if (_segmentDistanceSquared(stroke[i - 1], stroke[i], from, to) <=
        radiusSquared) {
      return true;
    }
  }
  return false;
}

double _pointDistanceSquared(Offset point, Offset a, Offset b) {
  final direction = b - a;
  if (direction.distanceSquared == 0) return (point - a).distanceSquared;
  final delta = point - a;
  final t =
      ((delta.dx * direction.dx + delta.dy * direction.dy) /
              direction.distanceSquared)
          .clamp(0.0, 1.0);
  return (point - (a + direction * t)).distanceSquared;
}

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

double _segmentDistanceSquared(Offset a, Offset b, Offset c, Offset d) {
  final ab = b - a, cd = d - c;
  final cross = _cross(ab, cd);
  if (cross.abs() > 1e-9) {
    final delta = c - a;
    final t = _cross(delta, cd) / cross, u = _cross(delta, ab) / cross;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return 0;
  }
  return math.min(
    math.min(_pointDistanceSquared(a, c, d), _pointDistanceSquared(b, c, d)),
    math.min(_pointDistanceSquared(c, a, b), _pointDistanceSquared(d, a, b)),
  );
}
