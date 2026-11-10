import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';

/// Deliberately abstract shapes, not generated photographs or model output.
class PlateIllustration extends StatelessWidget {
  const PlateIllustration({
    super.key,
    required this.dish,
    this.changeIds = const [],
    required this.label,
    this.aspectRatio = 1.45,
  });
  final Dish dish;
  final List<String> changeIds;
  final String label;

  /// Width / height of the drawing area; 1.0 suits compact square thumbnails.
  final double aspectRatio;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label:
        '$label. Simulated plate illustration of ${dish.name}. Shapes are symbolic, not evidence of nutrition or food texture.',
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: CustomPaint(painter: _PlatePainter(dish.id, changeIds)),
      ),
    ),
  );
}

class _PlatePainter extends CustomPainter {
  _PlatePainter(this.dishId, this.changes);
  final String dishId;
  final List<String> changes;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2) * .88;

    // Soft plate shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, radius * .08),
        width: radius * 2.02,
        height: radius * 1.9,
      ),
      Paint()..color = const Color(0x18163D34),
    );

    // Outer ceramic rim and inner plate well
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFFDFCF7));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFFC5CFC2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, radius * 0.035),
    );
    canvas.drawCircle(
      center,
      radius * .84,
      Paint()
        ..color = const Color(0xFFE5EAE0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, radius * 0.025),
    );

    // Base portion (soup broth well vs white/brown rice mound)
    final isSoup = dishId == 'fish_soup';
    final isBrownRice = changes.contains('brown_rice');
    if (isSoup) {
      canvas.drawCircle(
        center,
        radius * .76,
        Paint()..color = const Color(0xFFF2D79E),
      );
    } else {
      final riceRect = Rect.fromCenter(
        center: center + Offset(radius * -.22, radius * .12),
        width: radius * 1.04,
        height: radius * 1.06,
      );
      canvas.drawOval(
        riceRect,
        Paint()
          ..color = isBrownRice
              ? const Color(0xFFC3925A)
              : const Color(0xFFF3E7C8),
      );
      canvas.drawOval(
        riceRect,
        Paint()
          ..color = isBrownRice
              ? const Color(0xFF9E6E3B)
              : const Color(0xFFDCCBA2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, radius * 0.02),
      );
    }

    // Protein portion (chicken slices, fish fillets, or golden tofu cubes)
    for (var i = 0; i < 3; i++) {
      final sliceRect = Rect.fromCenter(
        center: center + Offset(radius * .25, radius * (-.32 + i * .25)),
        width: radius * .68,
        height: radius * .19,
      );
      final rrect = RRect.fromRectAndRadius(
        sliceRect,
        Radius.circular(radius * .08),
      );
      if (dishId == 'fish_soup') {
        canvas.drawRRect(rrect, Paint()..color = const Color(0xFFFFFDF9));
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = const Color(0xFFB58E63)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, radius * 0.025),
        );
      } else if (dishId == 'tofu_rice') {
        canvas.drawRRect(rrect, Paint()..color = const Color(0xFFD89F48));
        canvas.drawRRect(
          rrect.deflate(radius * 0.03),
          Paint()..color = const Color(0xFFF6E6C2),
        );
      } else {
        canvas.drawRRect(rrect, Paint()..color = const Color(0xFFC87B42));
      }
    }

    // Leafy greens / broccoli florets (3 standard vs 8 with extra_vegetables)
    final vegetableCount = changes.contains('extra_vegetables') ? 8 : 3;
    for (var i = 0; i < vegetableCount; i++) {
      final angle = (i / vegetableCount) * 1.75 + 3.68;
      final point =
          center +
          Offset(
            math.cos(angle) * radius * .55,
            math.sin(angle) * radius * .55,
          );
      canvas.drawOval(
        Rect.fromCenter(
          center: point,
          width: radius * .25,
          height: radius * .31,
        ),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF3E7A40)
              : const Color(0xFF76A353),
      );
    }

    // Side saucer when sauce_on_side is selected
    if (changes.contains('sauce_on_side')) {
      final bowl = center + Offset(radius * .88, radius * .56);
      canvas.drawCircle(
        bowl,
        radius * .24,
        Paint()..color = const Color(0xFFFDFCF7),
      );
      canvas.drawCircle(
        bowl,
        radius * .24,
        Paint()
          ..color = const Color(0xFF718476)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, radius * 0.025),
      );
      canvas.drawCircle(
        bowl,
        radius * .15,
        Paint()..color = const Color(0xFF8E4A2E),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlatePainter oldDelegate) =>
      oldDelegate.dishId != dishId || !listEquals(oldDelegate.changes, changes);
}

bool listEquals(List<String> a, List<String> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((equal) => equal);
