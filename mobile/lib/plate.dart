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
  });
  final Dish dish;
  final List<String> changeIds;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label:
        '$label. Simulated plate illustration of ${dish.name}. Shapes are symbolic, not evidence of nutrition or food texture.',
    child: ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1.45,
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
    final radius = math.min(size.width / 2, size.height / 2) * .87;
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, radius * .1),
        width: radius * 2.05,
        height: radius * 1.87,
      ),
      Paint()..color = const Color(0x160D3F35),
    );
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFFDFDF8));
    canvas.drawCircle(
      center,
      radius * .88,
      Paint()
        ..color = const Color(0xFFE8EADF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final baseColor = dishId == 'fish_soup'
        ? const Color(0xFFE8C183)
        : changes.contains('brown_rice')
        ? const Color(0xFFC99A60)
        : const Color(0xFFF1E5C5);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(radius * -.2, radius * .13),
        width: radius * 1.05,
        height: radius * 1.08,
      ),
      Paint()..color = baseColor,
    );
    final foodPaint = Paint()
      ..color = dishId == 'tofu_rice'
          ? const Color(0xFFDCB56D)
          : dishId == 'fish_soup'
          ? const Color(0xFFFCF3DF)
          : const Color(0xFFCA814A);
    for (var i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center + Offset(radius * .24, radius * (-.35 + i * .25)),
            width: radius * .71,
            height: radius * .2,
          ),
          Radius.circular(radius * .09),
        ),
        foodPaint,
      );
    }
    final vegetableCount = changes.contains('extra_vegetables') ? 8 : 3;
    for (var i = 0; i < vegetableCount; i++) {
      final angle = (i / vegetableCount) * 1.7 + 3.7;
      final point =
          center +
          Offset(
            math.cos(angle) * radius * .56,
            math.sin(angle) * radius * .56,
          );
      canvas.drawOval(
        Rect.fromCenter(
          center: point,
          width: radius * .25,
          height: radius * .32,
        ),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF467D45)
              : const Color(0xFF82A85B),
      );
    }
    if (changes.contains('sauce_on_side')) {
      final bowl = center + Offset(radius * .92, radius * .58);
      canvas.drawCircle(
        bowl,
        radius * .24,
        Paint()..color = const Color(0xFFFDFDF8),
      );
      canvas.drawCircle(
        bowl,
        radius * .17,
        Paint()..color = const Color(0xFF925033),
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
