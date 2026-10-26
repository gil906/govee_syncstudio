import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/govee_models.dart';
import '../shaders/govee_shader.dart';

/// Renders all 3 houses side-by-side (`House #1 Left` -> `House #2 Middle (My House)` -> `House #3 Right`)
/// with pitched architectural rooflines, glowing LED segments, under-eave bloom, and flow indicators.
class ThreeHouseScenePainter extends CustomPainter {
  final AnimationConfig animation;
  final List<HouseConfig> houses;
  final double elapsedSec;
  final bool compact;
  final bool showLabels;
  final Map<String, List<Color>>? liveHouseColors;

  ThreeHouseScenePainter({
    required this.animation,
    required this.houses,
    required this.elapsedSec,
    this.compact = false,
    this.showLabels = true,
    this.liveHouseColors,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Night sky background with subtle horizon glow
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF040711),
          const Color(0xFF0A1124),
          const Color(0xFF070C18),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(compact ? 12 : 16)),
      skyPaint,
    );

    // Street / ground line
    final groundY = size.height * (compact ? 0.88 : 0.84);
    final streetPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.65)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(8, groundY),
      Offset(size.width - 8, groundY),
      streetPaint,
    );

    final ordered = (houses.isEmpty
            ? SystemConfig.defaultThreeHouses().houses
            : List<HouseConfig>.from(houses))
      ..sort((a, b) => a.order.compareTo(b.order));
    final enabledHouses = ordered.where((h) => h.enabled).toList();
    final houseList = enabledHouses.isNotEmpty ? enabledHouses : ordered;

    final count = math.max(1, houseList.length);
    final horizontalPad = compact ? 8.0 : 14.0;
    final gap = count <= 1
        ? 0.0
        : (compact ? 6.0 : (count > 3 ? 8.0 : 14.0));
    final usableW =
        math.max(40.0, size.width - horizontalPad * 2 - gap * (count - 1));
    final houseW = usableW / count;

    final totalWeight = houseList.fold<double>(
      0.0,
      (acc, h) => acc + (h.enabled ? math.max(0.1, h.timeWeight) : 0.0),
    );
    final totalAllSegs = houseList.fold<int>(
      0,
      (acc, h) => acc + (h.enabled ? h.totalSegments : 0),
    );

    final unwrappedPhase = elapsedSec * animation.speed;
    double cumulativeWeight = 0.0;
    int globalSegCursor = 0;

    for (int idx = 0; idx < count; idx++) {
      final house = houseList[idx];
      final left = horizontalPad + idx * (houseW + gap);
      final right = left + houseW;
      final centerX = (left + right) * 0.5;
      final isMiddleMe = house.isMyHouse || idx == 1;

      final roofPeakY = size.height *
          (compact
              ? (isMiddleMe ? 0.24 : 0.20)
              : (isMiddleMe ? 0.22 : 0.17));
      final eaveY = size.height * (compact ? 0.54 : 0.50);

      final segCount =
          compact ? math.min(18, math.max(7, house.totalSegments)) : house.totalSegments;
      final weight = math.max(0.1, house.timeWeight);
      final houseStartNorm =
          totalWeight > 0 ? cumulativeWeight / totalWeight : idx / count;
      final houseSpanNorm =
          totalWeight > 0 ? weight / totalWeight : 1.0 / count;
      if (house.enabled) {
        cumulativeWeight += weight;
      }

      // Compute segment colors for this house
      final liveColors = liveHouseColors?[house.id];
      final segColors = <Color>[];

      for (int s = 0; s < segCount; s++) {
        if (!house.enabled || !animation.running) {
          segColors.add(const Color(0xFF1E293B));
          continue;
        }
        if (liveColors != null && liveColors.isNotEmpty) {
          final mappedIdx =
              ((s / math.max(1, segCount)) * liveColors.length).floor().clamp(0, liveColors.length - 1);
          segColors.add(liveColors[mappedIdx]);
          continue;
        }

        final localPos = (s + 0.5) / math.max(1, segCount);
        double normX;
        if (animation.mappingMode == 'parallel_zones') {
          normX = localPos;
        } else if (animation.mappingMode == 'virtual_strip' &&
            totalAllSegs > 0) {
          normX = (globalSegCursor + s + 0.5) / totalAllSegs;
        } else {
          normX = houseStartNorm + localPos * houseSpanNorm;
        }

        segColors.add(
          evaluateEffectAtPoint(
            x: normX.clamp(0.0, 0.9999),
            unwrappedPhase: unwrappedPhase,
            elapsedSec: elapsedSec,
            anim: animation,
          ),
        );
      }
      if (house.enabled) {
        globalSegCursor += house.totalSegments;
      }

      // Representative house glow color for architectural under-eave bloom
      final midCol = segColors.isNotEmpty
          ? segColors[segColors.length ~/ 2]
          : const Color(0xFF00F5D4);

      // Draw house body silhouette
      final bodyLeft = left + houseW * 0.08;
      final bodyRight = right - houseW * 0.08;
      final houseBodyPath = Path()
        ..moveTo(bodyLeft, groundY)
        ..lineTo(bodyLeft, eaveY)
        ..lineTo(centerX, roofPeakY + 3)
        ..lineTo(bodyRight, eaveY)
        ..lineTo(bodyRight, groundY)
        ..close();

      final bodyFill = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            midCol.withValues(alpha: animation.running ? 0.20 : 0.05),
            isMiddleMe
                ? const Color(0xFF111C38)
                : const Color(0xFF0D1528),
          ],
        ).createShader(Rect.fromLTRB(bodyLeft, roofPeakY, bodyRight, groundY));
      canvas.drawPath(houseBodyPath, bodyFill);

      final bodyBorder = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isMiddleMe ? 1.4 : 1.0
        ..color = isMiddleMe
            ? const Color(0xFF00F5D4).withValues(alpha: 0.45)
            : const Color(0xFF334155).withValues(alpha: 0.65);
      canvas.drawPath(houseBodyPath, bodyBorder);

      // Draw windows / garage architectural details
      if (!compact) {
        final winW = (bodyRight - bodyLeft) * 0.20;
        final winH = (groundY - eaveY) * 0.34;
        final winY = eaveY + (groundY - eaveY) * 0.25;
        final winPaint = Paint()
          ..color = midCol.withValues(alpha: animation.running ? 0.22 : 0.06);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bodyLeft + (bodyRight - bodyLeft) * 0.16, winY, winW, winH),
            const Radius.circular(3),
          ),
          winPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bodyRight - (bodyRight - bodyLeft) * 0.16 - winW, winY, winW, winH),
            const Radius.circular(3),
          ),
          winPaint,
        );
      }

      // Draw pitched roof structural line
      final roofPath = Path()
        ..moveTo(left + 2, eaveY)
        ..lineTo(centerX, roofPeakY)
        ..lineTo(right - 2, eaveY);
      canvas.drawPath(
        roofPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 2.0 : 2.8
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0xFF334155),
      );

      // Draw glowing LED nodes along the pitched roofline
      final ledRadius = compact
          ? (segCount > 14 ? 2.4 : 3.0)
          : (segCount > 20 ? 3.2 : 4.2);
      final bloomPaint = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, compact ? 4.5 : 7.0);

      for (int s = 0; s < segCount; s++) {
        final u = segCount == 1 ? 0.5 : s / (segCount - 1);
        final px = (left + 3) + u * ((right - 3) - (left + 3));
        final roofFrac = 1.0 - (u - 0.5).abs() * 2.0; // 0 at eaves, 1 at peak
        final py = eaveY - roofFrac * (eaveY - roofPeakY);
        final col = segColors[s];

        if (animation.running && house.enabled) {
          bloomPaint.color = col.withValues(alpha: 0.75);
          canvas.drawCircle(Offset(px, py), ledRadius * 1.9, bloomPaint);
        }

        canvas.drawCircle(
          Offset(px, py),
          ledRadius,
          Paint()..color = col,
        );
      }

      // Draw inter-house flow chevron between houses
      if (idx < count - 1) {
        final midGapX = right + gap * 0.5;
        final arrowY = (roofPeakY + eaveY) * 0.52;
        final pulseGlow =
            0.35 + 0.65 * (0.5 * (1.0 + math.sin(elapsedSec * 5.0 - idx)));
        final arrowPaint = Paint()
          ..color = const Color(0xFF00F5D4).withValues(
              alpha: animation.running ? (0.35 + 0.45 * pulseGlow) : 0.18)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

        final dir = animation.effect == 'center_out_shockwave'
            ? (idx == 0 ? -1.0 : 1.0)
            : (animation.direction == 'reverse' ? -1.0 : 1.0);
        final dx = 2.5 * dir;
        canvas.drawLine(
            Offset(midGapX - dx, arrowY - 3), Offset(midGapX + dx, arrowY), arrowPaint);
        canvas.drawLine(
            Offset(midGapX - dx, arrowY + 3), Offset(midGapX + dx, arrowY), arrowPaint);
      }

      // House label + segment badge + speed multiplier
      if (showLabels) {
        final speedTag = house.isAutoDefaultSpeed
            ? '1.0x Auto'
            : '${house.speedMultiplier.toStringAsFixed(2)}x';
        final shortLabel = compact
            ? (isMiddleMe ? '#${idx + 1} ME (${house.totalSegments})' : '#${idx + 1} (${house.totalSegments})')
            : '#${idx + 1} ${house.name.split('(').first.trim()} • ${house.totalSegments} segs • $speedTag';

        final textPainter = TextPainter(
          text: TextSpan(
            text: shortLabel,
            style: TextStyle(
              color: isMiddleMe
                  ? const Color(0xFF00F5D4)
                  : const Color(0xFFCBD5E1),
              fontSize: compact ? 9.5 : 11.0,
              fontWeight: isMiddleMe ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: houseW - 4);

        textPainter.paint(
          canvas,
          Offset(
            centerX - textPainter.width * 0.5,
            compact ? groundY - 13 : groundY + 4,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ThreeHouseScenePainter oldDelegate) {
    if (oldDelegate.elapsedSec != elapsedSec ||
        oldDelegate.animation != animation ||
        oldDelegate.compact != compact ||
        oldDelegate.houses.length != houses.length) {
      return true;
    }
    for (int i = 0; i < houses.length; i++) {
      final a = oldDelegate.houses[i];
      final b = houses[i];
      if (a.id != b.id ||
          a.enabled != b.enabled ||
          a.order != b.order ||
          a.timeWeight != b.timeWeight ||
          a.totalSegments != b.totalSegments) {
        return true;
      }
    }
    return false;
  }
}

/// Reusable animated 3-house widget driven by a shared `Animation<double>` clock.
class ThreeHouseScenePreview extends StatelessWidget {
  final Animation<double> clock;
  final AnimationConfig animation;
  final List<HouseConfig> houses;
  final double height;
  final bool compact;
  final bool showLabels;
  final Map<String, List<Color>>? liveHouseColors;

  const ThreeHouseScenePreview({
    super.key,
    required this.clock,
    required this.animation,
    required this.houses,
    this.height = 88,
    this.compact = true,
    this.showLabels = true,
    this.liveHouseColors,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: clock,
        builder: (context, _) {
          // 60-second continuous phase loop from the master AnimationController
          final elapsedSec = clock.value * 60.0;
          return CustomPaint(
            painter: ThreeHouseScenePainter(
              animation: animation,
              houses: houses,
              elapsedSec: elapsedSec,
              compact: compact,
              showLabels: showLabels,
              liveHouseColors: liveHouseColors,
            ),
          );
        },
      ),
    );
  }
}

/// Custom in-app brand logo widget painted with `CustomPainter`:
/// Deep midnight obsidian rounded background (`#060B18`) with 3 glowing architectural
/// house rooflines side-by-side (Left `#00F5D4`, Middle `#A855F7` & `#FBBF24`, Right `#FF007F`)
/// and a bright synchronized neon light wave arcing across all 3 roofs.
class GoveeSyncLogoBadge extends StatelessWidget {
  final double size;

  const GoveeSyncLogoBadge({
    super.key,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoveeSyncLogoPainter(),
      ),
    );
  }
}

class _GoveeSyncLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.24));

    // 1. Deep midnight obsidian rounded background (#060B18)
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF060B18),
          Color(0xFF0B152C),
          Color(0xFF050914),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    // Subtle neon border rim
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.035)
      ..shader = const LinearGradient(
        colors: [
          Color(0xFF00F5D4),
          Color(0xFFA855F7),
          Color(0xFFFF007F),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(w * 0.02), borderPaint);

    // 2. Synchronized neon light wave arcing over all 3 roofs
    final wavePath = Path()
      ..moveTo(w * 0.11, h * 0.42)
      ..cubicTo(
        w * 0.34,
        h * 0.14,
        w * 0.66,
        h * 0.14,
        w * 0.89,
        h * 0.42,
      );
    final waveShader = const LinearGradient(
      colors: [
        Color(0xFF00F5D4),
        Color(0xFFA855F7),
        Color(0xFFFBBF24),
        Color(0xFFFF007F),
      ],
    ).createShader(rect);

    canvas.drawPath(
      wavePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, w * 0.09)
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.06)
        ..shader = waveShader,
    );
    canvas.drawPath(
      wavePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.3, w * 0.045)
        ..strokeCap = StrokeCap.round
        ..shader = waveShader,
    );

    // 3. Three glowing architectural house rooflines side-by-side
    final groundY = h * 0.82;
    canvas.drawLine(
      Offset(w * 0.10, groundY),
      Offset(w * 0.90, groundY),
      Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.40)
        ..strokeWidth = math.max(1.0, w * 0.025),
    );

    void drawNeonHouse({
      required double x0,
      required double x1,
      required double eaveY,
      required double peakY,
      required Color primary,
      required Color accent,
      required bool isMiddle,
    }) {
      final cx = (x0 + x1) * 0.5;
      final hw = x1 - x0;
      final bodyL = x0 + hw * 0.12;
      final bodyR = x1 - hw * 0.12;

      final bodyPath = Path()
        ..moveTo(bodyL, groundY)
        ..lineTo(bodyL, eaveY)
        ..lineTo(cx, peakY + h * 0.02)
        ..lineTo(bodyR, eaveY)
        ..lineTo(bodyR, groundY)
        ..close();

      canvas.drawPath(
        bodyPath,
        Paint()
          ..color = isMiddle
              ? const Color(0xFF131F3E)
              : const Color(0xFF0D162C),
      );

      // Glowing windows
      final winW = (bodyR - bodyL) * 0.24;
      final winH = (groundY - eaveY) * 0.34;
      final winY = eaveY + (groundY - eaveY) * 0.25;
      final winPaint = Paint()..color = accent.withValues(alpha: 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bodyL + (bodyR - bodyL) * 0.15, winY, winW, winH),
          Radius.circular(w * 0.02),
        ),
        winPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
              bodyR - (bodyR - bodyL) * 0.15 - winW, winY, winW, winH),
          Radius.circular(w * 0.02),
        ),
        winPaint,
      );

      // Pitched roofline + bloom
      final roofPath = Path()
        ..moveTo(x0, eaveY)
        ..lineTo(cx, peakY)
        ..lineTo(x1, eaveY);

      canvas.drawPath(
        roofPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.2, w * (isMiddle ? 0.095 : 0.08))
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.055)
          ..color = primary.withValues(alpha: 0.9),
      );
      canvas.drawPath(
        roofPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, w * (isMiddle ? 0.058 : 0.048))
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Color.lerp(primary, accent, isMiddle ? 0.45 : 0.20)!,
      );

      // Peak LED node
      canvas.drawCircle(
        Offset(cx, peakY),
        math.max(1.3, w * (isMiddle ? 0.036 : 0.028)),
        Paint()..color = Colors.white,
      );
    }

    // Left House (#1): Neon Cyan (#00F5D4)
    drawNeonHouse(
      x0: w * 0.09,
      x1: w * 0.36,
      eaveY: h * 0.60,
      peakY: h * 0.40,
      primary: const Color(0xFF00F5D4),
      accent: const Color(0xFF00F5D4),
      isMiddle: false,
    );
    // Right House (#3): Neon Magenta (#FF007F)
    drawNeonHouse(
      x0: w * 0.64,
      x1: w * 0.91,
      eaveY: h * 0.60,
      peakY: h * 0.40,
      primary: const Color(0xFFFF007F),
      accent: const Color(0xFFFF007F),
      isMiddle: false,
    );
    // Middle House (#2 - My House): Royal Violet (#A855F7) & Gold (#FBBF24)
    drawNeonHouse(
      x0: w * 0.34,
      x1: w * 0.66,
      eaveY: h * 0.56,
      peakY: h * 0.30,
      primary: const Color(0xFFA855F7),
      accent: const Color(0xFFFBBF24),
      isMiddle: true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
