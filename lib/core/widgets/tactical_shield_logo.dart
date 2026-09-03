import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TacticalShieldLogo extends StatelessWidget {
  final double size;
  final bool showGlow;
  final double iconSize;

  const TacticalShieldLogo({
    super.key,
    this.size = 72,
    this.showGlow = true,
    this.iconSize = 34,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF141923),
        border: Border.all(
          color: AppColors.primaryRed,
          width: 1.8,
        ),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppColors.primaryRed.withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.shield_outlined,
              size: iconSize,
              color: AppColors.primaryRed,
            ),
            Positioned(
              top: iconSize * 0.22,
              child: Container(
                width: 2.2,
                height: iconSize * 0.32,
                decoration: BoxDecoration(
                  color: AppColors.primaryRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Positioned(
              bottom: iconSize * 0.22,
              child: Container(
                width: 2.4,
                height: 2.4,
                decoration: const BoxDecoration(
                  color: AppColors.primaryRed,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SkylineBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF1B2433).withValues(alpha: 0.7)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final glowPaint = Paint()
      ..color = AppColors.primaryRed.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 25);

    // Subtle background glow behind the shield
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.45),
      size.width * 0.35,
      glowPaint,
    );

    // City skyline silhouette paths
    final path = Path();
    final h = size.height;
    final w = size.width;

    path.moveTo(0, h * 0.85);
    path.lineTo(w * 0.08, h * 0.85);
    path.lineTo(w * 0.08, h * 0.70);
    path.lineTo(w * 0.16, h * 0.70);
    path.lineTo(w * 0.16, h * 0.78);
    path.lineTo(w * 0.24, h * 0.78);
    path.lineTo(w * 0.24, h * 0.60);
    path.lineTo(w * 0.32, h * 0.60);
    path.lineTo(w * 0.32, h * 0.75);
    path.lineTo(w * 0.40, h * 0.75);
    path.lineTo(w * 0.45, h * 0.52);
    path.lineTo(w * 0.50, h * 0.52);
    path.lineTo(w * 0.50, h * 0.68);
    path.lineTo(w * 0.58, h * 0.68);
    path.lineTo(w * 0.58, h * 0.56);
    path.lineTo(w * 0.66, h * 0.56);
    path.lineTo(w * 0.72, h * 0.76);
    path.lineTo(w * 0.80, h * 0.76);
    path.lineTo(w * 0.80, h * 0.62);
    path.lineTo(w * 0.90, h * 0.62);
    path.lineTo(w * 0.90, h * 0.80);
    path.lineTo(w, h * 0.80);

    canvas.drawPath(path, linePaint);

    // Secondary subtle grid lines
    for (double y = h * 0.55; y <= h * 0.9; y += 18) {
      final gridPaint = Paint()
        ..color = const Color(0xFF172030).withValues(alpha: 0.35)
        ..strokeWidth = 0.8;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
