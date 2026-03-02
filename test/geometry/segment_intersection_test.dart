import 'package:rally_map_app/features/routing/domain/geometry/segment_intersection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('segmentsIntersect', () {
    test('crossing segments intersect', () {
      final a0 = Point2(0, 0);
      final a1 = Point2(2, 2);
      final b0 = Point2(0, 2);
      final b1 = Point2(2, 0);
      expect(segmentsIntersect(a0, a1, b0, b1), isTrue);
    });

    test('parallel segments do not intersect', () {
      final a0 = Point2(0, 0);
      final a1 = Point2(1, 0);
      final b0 = Point2(0, 1);
      final b1 = Point2(1, 1);
      expect(segmentsIntersect(a0, a1, b0, b1), isFalse);
    });

    test('non-crossing segments do not intersect', () {
      final a0 = Point2(0, 0);
      final a1 = Point2(1, 0);
      final b0 = Point2(2, 0);
      final b1 = Point2(3, 0);
      expect(segmentsIntersect(a0, a1, b0, b1), isFalse);
    });

    test('with tolerance near-miss can count as intersect', () {
      final a0 = Point2(0, 0);
      final a1 = Point2(1, 0);
      final b0 = Point2(0.5, 0.001);
      final b1 = Point2(0.5, 1);
      expect(segmentsIntersect(a0, a1, b0, b1, tolerance: 0), isFalse);
      expect(segmentsIntersect(a0, a1, b0, b1, tolerance: 0.01), isTrue);
    });
  });

  group('distanceToSegment', () {
    test('point on segment has zero distance', () {
      final p = Point2(1, 1);
      final s0 = Point2(0, 0);
      final s1 = Point2(2, 2);
      expect(distanceToSegment(p, s0, s1), closeTo(0, 1e-10));
    });

    test('point off segment has positive distance', () {
      final p = Point2(0, 1);
      final s0 = Point2(0, 0);
      final s1 = Point2(2, 0);
      expect(distanceToSegment(p, s0, s1), closeTo(1, 1e-10));
    });
  });
}
