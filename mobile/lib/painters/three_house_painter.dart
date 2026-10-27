import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/govee_models.dart';
import '../shaders/govee_shader.dart';

Color _parseHexColor(String hex, Color fallback) {
  final clean = hex.trim().replaceAll('#', '');
  if (clean.length == 6) {
    final val = int.tryParse('FF$clean', radix: 16);
    if (val != null) return Color(val);
  }
  return fallback;
}

class _LedPlacement {
  final Offset pos;
  final Offset washBaseLeft;
  final Offset washBaseRight;
  final Color color;
  final String controllerId;
  final int controllerIndex;
  final int segmentIndex;
  final int subPuckIndex;
  final String sectionId;
  final String wall;
  final int story;

  const _LedPlacement({
    required this.pos,
    required this.washBaseLeft,
    required this.washBaseRight,
    required this.color,
    required this.controllerId,
    required this.controllerIndex,
    required this.segmentIndex,
    this.subPuckIndex = 0,
    required this.sectionId,
    required this.wall,
    this.story = 1,
  });
}

/// Returns the number of physical LED sub-pucks to render per logical Govee segment
/// so that:
/// - My House (#2, 9 logical segments) renders 45 physical glowing LED pucks (5 per segment)
/// - Neighbor 1 (#1, 24 segments) & Neighbor 2 (#3, 30 segments) render 72–90 physical glowing LED pucks
int physicalSubPucksPerSegment(
  int houseTotalSegments, {
  bool compact = false,
  String wall = 'front',
}) {
  if (compact) {
    return houseTotalSegments <= 12 ? 4 : 3;
  }
  if (houseTotalSegments <= 12) {
    return 5; // 9 segs * 5 = 45 physical LED pucks on My House
  }
  if (wall == 'front' && houseTotalSegments <= 24) {
    return 4; // 4 sub-pucks on front sections + 3 on sides = 84 pucks on Neighbor 1
  }
  return 3; // 30 segs * 3 = 90 physical LED pucks on Neighbor 2
}

/// Evaluates the shader color for a fractional segment / sub-puck position on a house,
/// supporting Bottom-to-Top Counter-Clockwise (`1F LTR -> 2F RTL`), `bottom_to_top`,
/// `ccw_loop`, `front_street_sync`, `perimeter_360`, `front_back_sync`, and `all_segments`.
Color evaluateHouseSubPuckColor({
  required HouseConfig house,
  required double fractionalSegIndex,
  required int segCount,
  required String wall,
  required int story,
  required double archX,
  required double houseStartNorm,
  required double houseSpanNorm,
  required int globalSegCursor,
  required int totalAllSegs,
  required double unwrappedPhase,
  required double elapsedSec,
  required AnimationConfig animation,
}) {
  if (!house.enabled || !animation.running) {
    return const Color(0xFF1E293B);
  }

  final localPos = (fractionalSegIndex / math.max(1, segCount)).clamp(0.0, 0.9999);
  final wName = wall;

  double effectiveLocalPos = localPos;
  if (animation.zoneMode == 'bottom_to_top') {
    // ⬆️ Bottom -> Top Rise: 1st Story (0.0..0.48 LTR) rises to 2nd Story (0.50..1.0 RTL)
    if (wName == 'front') {
      if (story <= 1) {
        effectiveLocalPos = (archX * 0.48).clamp(0.0, 0.48);
      } else {
        effectiveLocalPos = (0.50 + (1.0 - archX) * 0.50).clamp(0.50, 0.9999);
      }
    } else {
      effectiveLocalPos = (0.55 + localPos * 0.44).clamp(0.0, 0.9999);
    }
  } else if (animation.zoneMode == 'ccw_loop') {
    // ↺ Bottom -> Top Counter-Clockwise Loop: 1F Front LTR -> 2F Front RTL -> Right -> Back -> Left
    if (house.isMyHouse || wName == 'front') {
      if (story <= 1) {
        effectiveLocalPos = (archX * 0.44).clamp(0.0, 0.44);
      } else {
        effectiveLocalPos = (0.44 + (1.0 - archX) * 0.56).clamp(0.44, 0.9999);
      }
    } else if (wName == 'right') {
      effectiveLocalPos = 0.72 + localPos * 0.09;
    } else if (wName == 'back') {
      effectiveLocalPos = 0.81 + localPos * 0.09;
    } else {
      effectiveLocalPos = 0.90 + localPos * 0.099;
    }
  } else if (animation.zoneMode == 'front_street_sync') {
    effectiveLocalPos = archX;
  } else if (animation.zoneMode == 'front_back_sync') {
    if (wName == 'front' || wName == 'back') {
      effectiveLocalPos = archX;
    } else {
      effectiveLocalPos = 0.5;
    }
  } else if (animation.zoneMode == 'perimeter_360') {
    if (wName == 'front') {
      effectiveLocalPos = archX * 0.40;
    } else if (wName == 'right') {
      effectiveLocalPos = 0.40 + (archX - 0.96).clamp(0.0, 0.04) * 5.0;
    } else if (wName == 'back') {
      effectiveLocalPos = 0.60 + (1.0 - archX) * 0.20;
    } else {
      effectiveLocalPos = 0.80 + (1.0 - (archX / 0.04).clamp(0.0, 1.0)) * 0.20;
    }
  }

  double normX;
  if (animation.mappingMode == 'parallel_zones') {
    normX = effectiveLocalPos;
  } else if (animation.mappingMode == 'virtual_strip' &&
      totalAllSegs > 0 &&
      animation.zoneMode != 'front_street_sync' &&
      animation.zoneMode != 'bottom_to_top' &&
      animation.zoneMode != 'ccw_loop') {
    normX = (globalSegCursor + fractionalSegIndex) / totalAllSegs;
  } else {
    normX = houseStartNorm + effectiveLocalPos * houseSpanNorm;
  }

  Color col = evaluateEffectAtPoint(
    x: normX.clamp(0.0, 0.9999),
    unwrappedPhase: unwrappedPhase,
    elapsedSec: elapsedSec,
    anim: animation,
  );
  if (animation.zoneMode == 'front_only_quiet_sides' && wName != 'front') {
    col = Color.fromARGB(
      (col.a * 255.0).round(),
      (col.r * 255.0 * 0.22).round(),
      (col.g * 255.0 * 0.22).round(),
      (col.b * 255.0 * 0.22).round(),
    );
  }
  return col;
}

/// Computes the per-segment colors for a house at `elapsedSec`.
List<Color> computeHouseSegmentColors({
  required HouseConfig house,
  required int segCount,
  required double houseStartNorm,
  required double houseSpanNorm,
  required int globalSegCursor,
  required int totalAllSegs,
  required double unwrappedPhase,
  required double elapsedSec,
  required AnimationConfig animation,
  List<Color>? liveColors,
}) {
  final segColors = <Color>[];
  final segWalls = house.allSegmentWalls;
  final segArchPositions = house.allSegmentArchPositions;
  for (int s = 0; s < segCount; s++) {
    if (!house.enabled || !animation.running) {
      segColors.add(const Color(0xFF1E293B));
      continue;
    }
    if (liveColors != null && liveColors.isNotEmpty) {
      final mappedIdx = ((s / math.max(1, segCount)) * liveColors.length)
          .floor()
          .clamp(0, liveColors.length - 1);
      segColors.add(liveColors[mappedIdx]);
      continue;
    }

    final archInfo = s < segArchPositions.length ? segArchPositions[s] : null;
    final wName =
        archInfo?.wall ?? (s < segWalls.length ? segWalls[s] : 'front');
    final story = archInfo?.story ?? 1;
    final archX = archInfo?.archX ?? ((s + 0.5) / math.max(1, segCount));

    segColors.add(
      evaluateHouseSubPuckColor(
        house: house,
        fractionalSegIndex: s + 0.5,
        segCount: segCount,
        wall: wName,
        story: story,
        archX: archX,
        houseStartNorm: houseStartNorm,
        houseSpanNorm: houseSpanNorm,
        globalSegCursor: globalSegCursor,
        totalAllSegs: totalAllSegs,
        unwrappedPhase: unwrappedPhase,
        elapsedSec: elapsedSec,
        animation: animation,
      ),
    );
  }
  return segColors;
}

/// Samples a point `t` in `[0.0, 1.0]` along a poly-polyline of 2D screen points.
Offset _samplePolyline2D(List<Offset> pts, double t) {
  if (pts.isEmpty) return Offset.zero;
  if (pts.length == 1) return pts.first;
  final lengths = <double>[];
  double totalLen = 0.0;
  for (int i = 0; i < pts.length - 1; i++) {
    final d = (pts[i + 1] - pts[i]).distance;
    lengths.add(d);
    totalLen += d;
  }
  if (totalLen <= 0.0001) return pts.first;
  final target = t.clamp(0.0, 1.0) * totalLen;
  double acc = 0.0;
  for (int i = 0; i < lengths.length; i++) {
    final segLen = lengths[i];
    if (acc + segLen >= target || i == lengths.length - 1) {
      final localT = segLen > 0.0001 ? ((target - acc) / segLen).clamp(0.0, 1.0) : 0.0;
      return Offset.lerp(pts[i], pts[i + 1], localT)!;
    }
    acc += segLen;
  }
  return pts.last;
}

/// Renders all houses side-by-side in 2D architectural blueprint perspective
/// using each house's multi-section `HouseArchitecture` (`triangle_gable`, `flat_eave`,
/// `dormer_peak`, `steep_gable`, `shed_slope`, `hip_roof`), garage/door/window details,
/// downward soffit wall-wash cones, and interactive 2D designer handles.
class ThreeHouseScenePainter extends CustomPainter {
  final AnimationConfig animation;
  final List<HouseConfig> houses;
  final double elapsedSec;
  final bool compact;
  final bool showLabels;
  final String? focusHouseId;
  final String? selectedSectionId;
  final String? highlightedControllerId;
  final int? highlightedSegmentIndex;
  final bool designMode;
  final Map<String, List<Color>>? liveHouseColors;

  ThreeHouseScenePainter({
    required this.animation,
    required this.houses,
    required this.elapsedSec,
    this.compact = false,
    this.showLabels = true,
    this.focusHouseId,
    this.selectedSectionId,
    this.highlightedControllerId,
    this.highlightedSegmentIndex,
    this.designMode = false,
    this.liveHouseColors,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Night sky background with blueprint grid when in designMode
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF040711),
          Color(0xFF0A1226),
          Color(0xFF060B17),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(compact ? 12 : 16)),
      skyPaint,
    );

    if (designMode) {
      final gridPaint = Paint()
        ..color = const Color(0xFF1E293B).withValues(alpha: 0.35)
        ..strokeWidth = 0.8;
      for (double gx = 24; gx < size.width; gx += 28) {
        canvas.drawLine(Offset(gx, 0), Offset(gx, size.height), gridPaint);
      }
      for (double gy = 20; gy < size.height; gy += 24) {
        canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
      }
    }

    final groundY = size.height * (compact ? 0.88 : (designMode ? 0.82 : 0.84));
    final topCeilingY = size.height * (compact ? 0.14 : 0.10);
    final usableHeight = math.max(30.0, groundY - topCeilingY);

    final streetPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.75)
      ..strokeWidth = 1.4;
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
    final activeList = enabledHouses.isNotEmpty ? enabledHouses : ordered;

    final List<HouseConfig> houseList;
    if (focusHouseId != null && focusHouseId!.isNotEmpty) {
      final match = ordered.where((h) => h.id == focusHouseId).toList();
      houseList = match.isNotEmpty ? match : [activeList.first];
    } else {
      houseList = activeList;
    }

    final count = math.max(1, houseList.length);
    final horizontalPad =
        compact ? 8.0 : (count == 1 ? math.max(20.0, size.width * 0.08) : 14.0);
    final gap = count <= 1 ? 0.0 : (compact ? 6.0 : (count > 3 ? 8.0 : 14.0));
    final usableW =
        math.max(40.0, size.width - horizontalPad * 2 - gap * (count - 1));
    final houseW = usableW / count;

    final totalWeight = activeList.fold<double>(
      0.0,
      (acc, h) => acc + (h.enabled ? math.max(0.1, h.timeWeight) : 0.0),
    );
    final totalAllSegs = activeList.fold<int>(
      0,
      (acc, h) => acc + (h.enabled ? h.totalSegments : 0),
    );

    final unwrappedPhase = elapsedSec * animation.speed;

    for (int idx = 0; idx < count; idx++) {
      final house = houseList[idx];
      final orderIdx = activeList.indexWhere((h) => h.id == house.id);
      final effIdx = orderIdx >= 0 ? orderIdx : idx;
      double prevWeight = 0.0;
      int globalSegCursor = 0;
      for (int j = 0; j < effIdx && j < activeList.length; j++) {
        if (activeList[j].enabled) {
          prevWeight += math.max(0.1, activeList[j].timeWeight);
          globalSegCursor += activeList[j].totalSegments;
        }
      }

      final left = horizontalPad + idx * (houseW + gap);
      final right = left + houseW;
      final centerX = (left + right) * 0.5;
      final isMiddleMe = house.isMyHouse;

      final segCount = house.totalSegments;
      final weight = math.max(0.1, house.timeWeight);
      final houseStartNorm =
          totalWeight > 0 ? prevWeight / totalWeight : effIdx / math.max(1, activeList.length);
      final houseSpanNorm =
          totalWeight > 0 ? weight / totalWeight : 1.0 / math.max(1, activeList.length);

      final segColors = computeHouseSegmentColors(
        house: house,
        segCount: segCount,
        houseStartNorm: houseStartNorm,
        houseSpanNorm: houseSpanNorm,
        globalSegCursor: globalSegCursor,
        totalAllSegs: totalAllSegs,
        unwrappedPhase: unwrappedPhase,
        elapsedSec: elapsedSec,
        animation: animation,
        liveColors: liveHouseColors?[house.id],
      );

      final arch = house.architecture;
      final sidingBase =
          _parseHexColor(arch.sidingColor, const Color(0xFF14213D));
      final trimCol = _parseHexColor(arch.trimColor, const Color(0xFF475569));

      // Sort front sections so 2nd-story / background sections draw first and foreground 1st-story sections draw in front
      final frontSecs = arch.sections.where((s) => s.wall == 'front').toList();
      final renderSecs = frontSecs.isNotEmpty
          ? (List<ArchSection>.from(frontSecs)
            ..sort((a, b) {
              if (a.story != b.story) return b.story.compareTo(a.story);
              return a.depthOffset.compareTo(b.depthOffset);
            }))
          : HouseArchitecture.defaultForHouse(house.id, house.order)
              .frontSections;

      final sectionPolylines = <String, List<Offset>>{};
      final sectionBaseY = <String, double>{};

      // Populate side/rear eave polylines in 2D so side/back segments render along side/back eaves
      for (final sideSec in arch.sections.where((s) => s.wall != 'front')) {
        final eaveY = groundY - sideSec.eaveHeight.clamp(0.25, 0.92) * usableHeight;
        final peakY = groundY -
            math.max(sideSec.eaveHeight, sideSec.peakHeight).clamp(0.25, 0.98) *
                usableHeight;
        if (sideSec.wall == 'left') {
          sectionPolylines[sideSec.id] = [
            Offset(left + 2.5, eaveY),
            Offset(left + 2.5, groundY - 0.38 * usableHeight),
          ];
        } else if (sideSec.wall == 'right') {
          sectionPolylines[sideSec.id] = [
            Offset(right - 2.5, eaveY),
            Offset(right - 2.5, groundY - 0.38 * usableHeight),
          ];
        } else if (sideSec.wall == 'back') {
          sectionPolylines[sideSec.id] = [
            Offset(left + houseW * 0.16, peakY),
            Offset(right - houseW * 0.16, peakY),
          ];
        }
      }

      for (final sec in renderSecs) {
        final sx0 = left + sec.xStart.clamp(0.0, 0.98) * houseW;
        final sx1 = left + sec.xEnd.clamp(0.02, 1.0) * houseW;
        final sw = math.max(8.0, sx1 - sx0);
        final sApexX = sx0 + sw * sec.peakOffset.clamp(0.15, 0.85);
        final sEaveY = groundY - sec.eaveHeight.clamp(0.20, 0.95) * usableHeight;
        final sPeakY = groundY -
            math.max(sec.eaveHeight, sec.peakHeight).clamp(0.20, 1.0) *
                usableHeight;
        final sBottomY = sec.story == 2
            ? groundY - 0.36 * usableHeight
            : groundY;
        sectionBaseY[sec.id] = sBottomY;

        final isSelectedSec = designMode && selectedSectionId == sec.id;

        // Build wall polygon + roofline polyline
        final bodyPath = Path()..moveTo(sx0, sBottomY)..lineTo(sx0, sEaveY);
        final roofLine = <Offset>[];
        if (sec.isPitchedGable) {
          bodyPath.lineTo(sApexX, sPeakY);
          bodyPath.lineTo(sx1, sEaveY);
          roofLine.addAll([
            Offset(sx0, sEaveY),
            Offset(sApexX, sPeakY),
            Offset(sx1, sEaveY),
          ]);
        } else if (sec.shape == 'shed_slope') {
          final leftTop = sec.peakOffset < 0.5 ? sPeakY : sEaveY;
          final rightTop = sec.peakOffset >= 0.5 ? sPeakY : sEaveY;
          bodyPath.lineTo(sx0, leftTop);
          bodyPath.lineTo(sx1, rightTop);
          roofLine.addAll([Offset(sx0, leftTop), Offset(sx1, rightTop)]);
        } else if (sec.shape == 'hip_roof') {
          final hipL = sx0 + sw * 0.22;
          final hipR = sx1 - sw * 0.22;
          bodyPath.lineTo(hipL, sPeakY);
          bodyPath.lineTo(hipR, sPeakY);
          bodyPath.lineTo(sx1, sEaveY);
          roofLine.addAll([Offset(sx0, sEaveY), Offset(sx1, sEaveY)]);
        } else {
          bodyPath.lineTo(sx1, sEaveY);
          roofLine.addAll([Offset(sx0, sEaveY), Offset(sx1, sEaveY)]);
        }
        bodyPath.lineTo(sx1, sBottomY);
        bodyPath.close();
        sectionPolylines[sec.id] = roofLine;

        final repColor = segColors.isNotEmpty
            ? segColors[segColors.length ~/ 2]
            : const Color(0xFF00F5D4);

        canvas.drawPath(
          bodyPath,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  sidingBase,
                  repColor,
                  animation.running ? 0.24 : 0.06,
                )!,
                const Color(0xFF0A1122),
              ],
            ).createShader(Rect.fromLTRB(sx0, sPeakY, sx1, sBottomY)),
        );

        canvas.drawPath(
          bodyPath,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelectedSec ? 2.2 : (isMiddleMe ? 1.4 : 1.0)
            ..color = isSelectedSec
                ? const Color(0xFFFBBF24)
                : (isMiddleMe
                    ? const Color(0xFF00F5D4).withValues(alpha: 0.45)
                    : trimCol.withValues(alpha: 0.65)),
        );

        // Architectural details matching the 4 uploaded Craftsman house photos:
        if (!compact && sw > 16) {
          final secH = math.max(12.0, sBottomY - sEaveY);

          if (sec.story == 2) {
            // Vertical gable vent right under apex on pitched 2nd-story gables
            if (sec.isPitchedGable && (sEaveY - sPeakY) > 10) {
              final ventH = math.min(9.0, (sEaveY - sPeakY) * 0.36);
              final ventW = math.min(4.2, sw * 0.06);
              final ventY = sPeakY + (sEaveY - sPeakY) * 0.30;
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromCenter(
                    center: Offset(sApexX, ventY),
                    width: ventW,
                    height: ventH,
                  ),
                  const Radius.circular(1.5),
                ),
                Paint()..color = trimCol.withValues(alpha: 0.80),
              );
            }

            // Determine exact window count on story == 2:
            // - sec-main-gable (House 2, My House): 4 vertical rectangular windows
            // - sec-upper-dormer (House 1) or sec-center-flat-fascia (House 3): 3 vertical windows
            // - sec-upper-right-eave / sec-left-tower-gable: 1 window
            if (sec.windowStyle != 'none') {
              int winCount = 1;
              if (sec.id == 'sec-main-gable' ||
                  sec.label.contains('4 Windows') ||
                  (sec.windowStyle == 'picture' && sw > houseW * 0.65)) {
                winCount = 4;
              } else if (sec.id == 'sec-upper-dormer' ||
                  sec.id == 'sec-center-flat-fascia' ||
                  sec.label.contains('3 Windows') ||
                  sec.label.contains('3-Window')) {
                winCount = 3;
              }

              final winFill = Paint()
                ..color = const Color(0xFFFDE68A)
                    .withValues(alpha: animation.running ? 0.25 : 0.12);
              final winStroke = Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.0
                ..color = trimCol.withValues(alpha: 0.85);

              final totalPadX = sw * (winCount >= 3 ? 0.12 : 0.26);
              final usableWinSpan = math.max(10.0, sw - totalPadX * 2);
              final gapW = winCount > 1 ? usableWinSpan * 0.08 : 0.0;
              final singleW = math.min(
                18.0,
                (usableWinSpan - gapW * (winCount - 1)) / winCount,
              );
              final winH = (secH * 0.56).clamp(8.0, 22.0);
              final winY = sEaveY + (secH - winH) * 0.45;
              final rowStartX = sx0 +
                  (sw - (singleW * winCount + gapW * (winCount - 1))) * 0.5;

              for (int wi = 0; wi < winCount; wi++) {
                final wx = rowStartX + wi * (singleW + gapW);
                final wRect = Rect.fromLTWH(wx, winY, singleW, winH);
                final topRad = sec.windowStyle == 'arched'
                    ? Radius.circular(singleW * 0.48)
                    : const Radius.circular(2.0);
                final rrect = RRect.fromRectAndCorners(
                  wRect,
                  topLeft: topRad,
                  topRight: topRad,
                  bottomLeft: const Radius.circular(1.5),
                  bottomRight: const Radius.circular(1.5),
                );
                canvas.drawRRect(rrect, winFill);
                canvas.drawRRect(rrect, winStroke);
                // Vertical & horizontal Craftsman window mullions
                canvas.drawLine(
                  Offset(wx + singleW * 0.5, winY + 1),
                  Offset(wx + singleW * 0.5, winY + winH - 1),
                  Paint()
                    ..color = trimCol.withValues(alpha: 0.55)
                    ..strokeWidth = 0.7,
                );
                canvas.drawLine(
                  Offset(wx + 1, winY + winH * 0.42),
                  Offset(wx + singleW - 1, winY + winH * 0.42),
                  Paint()
                    ..color = trimCol.withValues(alpha: 0.55)
                    ..strokeWidth = 0.7,
                );
              }
            }
          } else {
            // Story == 1: Garage bays (with 4 top window panes + stone-veneer pillars + carriage sconces)
            // and/or Covered Entry Porch (with white Craftsman columns on stone pedestals)
            final bothPorchAndGarage = sec.hasGarage && sec.hasDoor;
            final porchRightX = bothPorchAndGarage ? sx0 + sw * 0.34 : sx1;
            final garageLeftX = bothPorchAndGarage ? sx0 + sw * 0.34 : sx0;

            if (sec.hasDoor) {
              final pSpanW = math.max(12.0, porchRightX - sx0);
              final dw = math.min(pSpanW * 0.36, 15.0);
              final dh = secH * 0.68;
              final dx = sx0 + (pSpanW - dw) * 0.42;
              final dy = sBottomY - dh;
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromLTWH(dx, dy, dw, dh),
                  const Radius.circular(2.0),
                ),
                Paint()..color = const Color(0xFF1E293B),
              );
              canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Rect.fromLTWH(dx, dy, dw, dh),
                  const Radius.circular(2.0),
                ),
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 0.9
                  ..color = trimCol.withValues(alpha: 0.75),
              );
              // Warm glass pane in door + glowing porch sconce
              canvas.drawRect(
                Rect.fromLTWH(dx + dw * 0.22, dy + dh * 0.12, dw * 0.56, dh * 0.28),
                Paint()
                  ..color = const Color(0xFFFDE68A).withValues(alpha: 0.55),
              );
              canvas.drawCircle(
                Offset(dx - 3.5, dy + dh * 0.28),
                2.2,
                Paint()
                  ..color = const Color(0xFFFBBF24).withValues(alpha: 0.90),
              );

              // White Craftsman porch column(s) on stone-veneer pedestals
              final colPositions = <double>[
                sx0 + 3.5,
                if (!bothPorchAndGarage) porchRightX - 3.5,
              ];
              for (final cxPos in colPositions) {
                final pedH = secH * 0.34;
                final colH = secH - pedH;
                // White tapered upper column
                canvas.drawRect(
                  Rect.fromLTWH(cxPos - 1.8, sEaveY, 3.6, colH),
                  Paint()..color = const Color(0xFFE2E8F0),
                );
                // Stone-veneer pedestal base
                final pedRect = Rect.fromLTWH(
                  cxPos - 3.0,
                  sBottomY - pedH,
                  6.0,
                  pedH,
                );
                canvas.drawRRect(
                  RRect.fromRectAndRadius(pedRect, const Radius.circular(1.5)),
                  Paint()..color = const Color(0xFF475569),
                );
                canvas.drawRRect(
                  RRect.fromRectAndRadius(pedRect, const Radius.circular(1.5)),
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 0.7
                    ..color = trimCol.withValues(alpha: 0.75),
                );
              }
            }

            if (sec.hasGarage) {
              final gSpanW = math.max(18.0, sx1 - garageLeftX);
              final gw = gSpanW * 0.76;
              final gh = secH * 0.74;
              final gx = garageLeftX + (gSpanW - gw) * 0.5;
              final gy = sBottomY - gh;

              // Stone-veneer side pillars flanking the garage door + warm carriage sconces
              final pillarW = math.max(3.5, (gSpanW - gw) * 0.42);
              final pillarH = gh * 0.72;
              for (final px in [gx - pillarW - 0.5, gx + gw + 0.5]) {
                final pRect = Rect.fromLTWH(
                  px,
                  sBottomY - pillarH,
                  pillarW,
                  pillarH,
                );
                canvas.drawRect(
                  pRect,
                  Paint()..color = const Color(0xFF334155),
                );
                // Warm carriage sconce above stone pillar
                final sconceCenter = Offset(
                  px + pillarW * 0.5,
                  gy + gh * 0.22,
                );
                canvas.drawCircle(
                  sconceCenter,
                  4.2,
                  Paint()
                    ..color = const Color(0xFFFBBF24).withValues(alpha: 0.28)
                    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
                );
                canvas.drawCircle(
                  sconceCenter,
                  1.7,
                  Paint()..color = const Color(0xFFFEF08A),
                );
              }

              // 2-car paneled garage door
              final gRect = RRect.fromRectAndRadius(
                Rect.fromLTWH(gx, gy, gw, gh),
                const Radius.circular(2.5),
              );
              canvas.drawRRect(
                gRect,
                Paint()..color = const Color(0xFF1E293B),
              );
              canvas.drawRRect(
                gRect,
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.1
                  ..color = trimCol.withValues(alpha: 0.85),
              );
              // Horizontal panel dividers + center bay seam
              for (int r = 1; r <= 3; r++) {
                final py = gy + (gh / 4.0) * r;
                canvas.drawLine(
                  Offset(gx + 1.5, py),
                  Offset(gx + gw - 1.5, py),
                  Paint()
                    ..color = trimCol.withValues(alpha: 0.45)
                    ..strokeWidth = 0.75,
                );
              }
              canvas.drawLine(
                Offset(gx + gw * 0.5, gy + gh * 0.25),
                Offset(gx + gw * 0.5, gy + gh - 1),
                Paint()
                  ..color = trimCol.withValues(alpha: 0.38)
                  ..strokeWidth = 0.75,
              );
              // 4 top glass window panes across the top row of the 2-car garage door
              final paneRowH = gh * 0.16;
              final paneY = gy + gh * 0.05;
              final paneMargin = gw * 0.06;
              final paneUsable = gw - paneMargin * 2;
              final paneGap = paneUsable * 0.05;
              final paneW = (paneUsable - paneGap * 3) / 4.0;
              for (int pi = 0; pi < 4; pi++) {
                final paneX = gx + paneMargin + pi * (paneW + paneGap);
                canvas.drawRRect(
                  RRect.fromRectAndRadius(
                    Rect.fromLTWH(paneX, paneY, paneW, paneRowH),
                    const Radius.circular(1.0),
                  ),
                  Paint()
                    ..color = const Color(0xFFBAE6FD)
                        .withValues(alpha: animation.running ? 0.38 : 0.20),
                );
              }
            }
          }
        }

        // Draw structural roofline path
        if (roofLine.length >= 2) {
          final rPath = Path()..moveTo(roofLine.first.dx, roofLine.first.dy);
          for (int k = 1; k < roofLine.length; k++) {
            rPath.lineTo(roofLine[k].dx, roofLine[k].dy);
          }
          canvas.drawPath(
            rPath,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSelectedSec ? 3.2 : (compact ? 2.0 : 2.6)
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = isSelectedSec
                  ? const Color(0xFFFBBF24)
                  : trimCol,
          );
        }

        // In 2D Design Mode, draw interactive touch handles for the selected section
        if (isSelectedSec) {
          final handlePositions = <Offset>[
            Offset(sx0, sEaveY),
            if (sec.isPitchedGable || sec.shape == 'shed_slope')
              Offset(sApexX, sPeakY),
            Offset(sx1, sEaveY),
          ];
          for (final hp in handlePositions) {
            canvas.drawCircle(
              hp,
              7.5,
              Paint()..color = const Color(0xFF040711),
            );
            canvas.drawCircle(
              hp,
              6.0,
              Paint()..color = const Color(0xFFFBBF24),
            );
          }
        }
      }

      // Driveway path bollard lights along the left foreground of House 2 (My House)
      if (isMiddleMe && !compact) {
        for (int bi = 0; bi < 4; bi++) {
          final bx = left + houseW * (0.04 + bi * 0.055);
          final by = groundY + 1.5 + (bi % 2) * 1.2;
          canvas.drawCircle(
            Offset(bx, by),
            4.0,
            Paint()
              ..color = const Color(0xFFFEF08A).withValues(alpha: 0.30)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
          );
          canvas.drawCircle(
            Offset(bx, by),
            1.6,
            Paint()..color = const Color(0xFFFEF9C3),
          );
        }
      }

      // Map each controller's segments & high-density physical sub-pucks onto its assigned sections' rooflines
      // following Bottom-to-Top Counter-Clockwise (1F LTR -> 2F RTL) wiring flow.
      final placements = <_LedPlacement>[];
      int colorCursor = 0;
      final secById = {for (final s in arch.sections) s.id: s};
      final houseLiveColors = liveHouseColors?[house.id];
      final activeCtrls = house.controllers.where((c) => c.enabled).toList();
      final ctrlsToMap = activeCtrls.isNotEmpty
          ? activeCtrls
          : [
              ControllerConfig(
                id: '${house.id}-ctrl-1',
                name: 'Main Controller',
                segmentCount: segCount,
              ),
            ];

      for (int ci = 0; ci < ctrlsToMap.length; ci++) {
        final ctrl = ctrlsToMap[ci];
        final spans = house.effectiveControllerSpans(ctrl);
        int localSegIdx = 0;
        for (final sp in spans) {
          final secObj = secById[sp.sectionId];
          final secWall = secObj?.wall ?? sp.wall;
          final secStory = secObj?.story ?? 1;
          final x0 = (secObj?.xStart ?? 0.05).clamp(0.0, 1.0);
          final x1 = (secObj?.xEnd ?? 0.95).clamp(0.0, 1.0);
          final poly = sectionPolylines[sp.sectionId] ??
              (sectionPolylines.values.isNotEmpty
                  ? sectionPolylines.values.first
                  : [
                      Offset(left + 4, groundY - usableHeight * 0.5),
                      Offset(right - 4, groundY - usableHeight * 0.5),
                    ]);
          final n = sp.segments;
          final subPucks = physicalSubPucksPerSegment(
            segCount,
            compact: compact,
            wall: secWall,
          );
          final isRev = sp.isReverseDirection != ctrl.reversed;

          for (int k = 0; k < n && localSegIdx < ctrl.segmentCount; k++) {
            for (int sub = 0; sub < subPucks; sub++) {
              final spanProgress =
                  (k + (sub + 0.5) / subPucks) / math.max(1, n);
              final u = isRev ? (1.0 - spanProgress) : spanProgress;
              final pt = _samplePolyline2D(poly, u);

              double subArchX;
              if (secWall == 'front') {
                subArchX = (x0 + u * (x1 - x0)).clamp(0.0, 1.0);
              } else if (secWall == 'left') {
                subArchX = (0.04 * (1.0 - u)).clamp(0.0, 1.0);
              } else if (secWall == 'right') {
                subArchX = (0.96 + 0.04 * u).clamp(0.0, 1.0);
              } else {
                subArchX = (1.0 - u).clamp(0.0, 1.0);
              }

              Color col;
              if (houseLiveColors != null &&
                  houseLiveColors.isNotEmpty &&
                  segColors.isNotEmpty) {
                final currCol =
                    segColors[colorCursor.clamp(0, segColors.length - 1)];
                final nextCol =
                    segColors[(colorCursor + 1).clamp(0, segColors.length - 1)];
                col = Color.lerp(currCol, nextCol, sub / subPucks) ?? currCol;
              } else {
                col = evaluateHouseSubPuckColor(
                  house: house,
                  fractionalSegIndex: colorCursor + (sub + 0.5) / subPucks,
                  segCount: segCount,
                  wall: secWall,
                  story: secStory,
                  archX: subArchX,
                  houseStartNorm: houseStartNorm,
                  houseSpanNorm: houseSpanNorm,
                  globalSegCursor: globalSegCursor,
                  totalAllSegs: totalAllSegs,
                  unwrappedPhase: unwrappedPhase,
                  elapsedSec: elapsedSec,
                  animation: animation,
                );
              }

              final washDrop = compact ? 10.0 : 20.0;
              final washSpread = compact ? 3.2 : 6.0;
              placements.add(
                _LedPlacement(
                  pos: pt,
                  washBaseLeft: Offset(pt.dx - washSpread, pt.dy + washDrop),
                  washBaseRight: Offset(pt.dx + washSpread, pt.dy + washDrop),
                  color: col,
                  controllerId: ctrl.id,
                  controllerIndex: ci,
                  segmentIndex: localSegIdx,
                  subPuckIndex: sub,
                  sectionId: sp.sectionId,
                  wall: secWall,
                  story: secStory,
                ),
              );
            }
            localSegIdx++;
            colorCursor++;
          }
        }
      }

      // 1. Draw downward conical soffit wall-wash cones under the high-density pucks
      if (animation.running && house.enabled) {
        for (int pi = 0; pi < placements.length; pi++) {
          final p = placements[pi];
          final conePath = Path()
            ..moveTo(p.pos.dx, p.pos.dy)
            ..lineTo(p.washBaseLeft.dx, p.washBaseLeft.dy)
            ..lineTo(p.washBaseRight.dx, p.washBaseRight.dy)
            ..close();
          canvas.drawPath(
            conePath,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  p.color.withValues(alpha: compact ? 0.24 : 0.34),
                  p.color.withValues(alpha: 0.0),
                ],
              ).createShader(
                Rect.fromLTRB(
                  p.washBaseLeft.dx,
                  p.pos.dy,
                  p.washBaseRight.dx,
                  p.washBaseRight.dy,
                ),
              ),
          );
        }
      }

      // 2. Draw high-density glowing physical Govee LED pucks along the multi-section roofline
      final ledRadius = compact
          ? 2.15
          : (designMode ? 3.2 : (placements.length > 65 ? 2.45 : 2.85));
      final bloomPaint = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, compact ? 3.8 : 5.2);

      for (final p in placements) {
        final isHighlighted = designMode &&
            highlightedControllerId == p.controllerId &&
            (highlightedSegmentIndex == null ||
                highlightedSegmentIndex == p.segmentIndex);

        if (animation.running && house.enabled) {
          bloomPaint.color =
              p.color.withValues(alpha: isHighlighted ? 0.95 : 0.72);
          canvas.drawCircle(
            p.pos,
            ledRadius * (isHighlighted ? 2.4 : 1.85),
            bloomPaint,
          );
        }
        canvas.drawCircle(
          p.pos,
          isHighlighted ? ledRadius * 1.35 : ledRadius,
          Paint()..color = isHighlighted ? Colors.white : p.color,
        );
        if (animation.running && house.enabled && !isHighlighted) {
          canvas.drawCircle(
            p.pos,
            ledRadius * 0.42,
            Paint()
              ..color = Color.lerp(p.color, Colors.white, 0.55)!
                  .withValues(alpha: 0.92),
          );
        }
        if (isHighlighted && p.subPuckIndex == 2) {
          canvas.drawCircle(
            p.pos,
            ledRadius * 1.85,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = const Color(0xFFFBBF24),
          );
        }
      }

      // 3. In Design Mode, draw subtle "↺ Bottom → Top CCW (1F → | ← 2F)" flow indicator
      if (designMode && !compact) {
        final ccwText = TextPainter(
          text: const TextSpan(
            text: '↺ Bottom→Top CCW (1F LTR →  •  ← 2F RTL)',
            style: TextStyle(
              color: Color(0xFFFDE68A),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: houseW - 8);
        final badgeRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerX, topCeilingY + 6),
            width: ccwText.width + 12,
            height: ccwText.height + 5,
          ),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          badgeRect,
          Paint()..color = const Color(0xFF060B18).withValues(alpha: 0.88),
        );
        canvas.drawRRect(
          badgeRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..color = const Color(0xFFFBBF24).withValues(alpha: 0.65),
        );
        ccwText.paint(
          canvas,
          Offset(
            centerX - ccwText.width * 0.5,
            topCeilingY + 6 - ccwText.height * 0.5,
          ),
        );
      }

      // Inter-house flow chevron
      if (idx < count - 1) {
        final midGapX = right + gap * 0.5;
        final arrowY = groundY - usableHeight * 0.48;
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

      if (showLabels) {
        final speedTag = house.isAutoDefaultSpeed
            ? '1.0x Auto'
            : '${house.speedMultiplier.toStringAsFixed(2)}x';
        final shortLabel = compact
            ? (isMiddleMe
                ? '#${effIdx + 1} ME (${house.totalSegments})'
                : '#${effIdx + 1} (${house.totalSegments})')
            : '#${effIdx + 1} ${house.name.split('(').first.trim()} • ${house.totalSegments} segs • $speedTag';

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
    return oldDelegate.elapsedSec != elapsedSec ||
        oldDelegate.animation != animation ||
        oldDelegate.compact != compact ||
        oldDelegate.focusHouseId != focusHouseId ||
        oldDelegate.selectedSectionId != selectedSectionId ||
        oldDelegate.highlightedControllerId != highlightedControllerId ||
        oldDelegate.highlightedSegmentIndex != highlightedSegmentIndex ||
        oldDelegate.designMode != designMode ||
        oldDelegate.houses != houses;
  }
}

/// Reusable animated 2D multi-section house widget driven by a shared `Animation<double>` clock.
class ThreeHouseScenePreview extends StatelessWidget {
  final Animation<double> clock;
  final AnimationConfig animation;
  final List<HouseConfig> houses;
  final double height;
  final bool compact;
  final bool showLabels;
  final String? focusHouseId;
  final String? selectedSectionId;
  final String? highlightedControllerId;
  final int? highlightedSegmentIndex;
  final bool designMode;
  final Map<String, List<Color>>? liveHouseColors;

  const ThreeHouseScenePreview({
    super.key,
    required this.clock,
    required this.animation,
    required this.houses,
    this.height = 88,
    this.compact = true,
    this.showLabels = true,
    this.focusHouseId,
    this.selectedSectionId,
    this.highlightedControllerId,
    this.highlightedSegmentIndex,
    this.designMode = false,
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
          final elapsedSec = clock.value * 60.0;
          return CustomPaint(
            painter: ThreeHouseScenePainter(
              animation: animation,
              houses: houses,
              elapsedSec: elapsedSec,
              compact: compact,
              showLabels: showLabels,
              focusHouseId: focusHouseId,
              selectedSectionId: selectedSectionId,
              highlightedControllerId: highlightedControllerId,
              highlightedSegmentIndex: highlightedSegmentIndex,
              designMode: designMode,
              liveHouseColors: liveHouseColors,
            ),
          );
        },
      ),
    );
  }
}

typedef ThreeHouse3DPainter = Isometric3DHousePainter;

/// True Multi-Section 3D Architectural House & Roofline LED Painter.
/// Extrudes every `ArchSection` (`triangle_gable`, `steep_gable`, `flat_eave`,
/// `dormer_peak`, `hip_roof`, `shed_slope`) in 3D space with `cameraYaw`, `cameraPitch`,
/// `cameraZoom`, `depthOffset`, 3D roof planes, ridge beams, garage/door/window details,
/// downward conical soffit wall-wash light beams, and per-controller LED mapping.
class Isometric3DHousePainter extends CustomPainter {
  final AnimationConfig animation;
  final List<HouseConfig> houses;
  final double elapsedSec;
  final String? focusHouseId;
  final double? cameraYawOverride;
  final double? cameraPitchOverride;
  final double? cameraZoomOverride;
  final String? selectedSectionId;
  final String? highlightedControllerId;
  final int? highlightedSegmentIndex;
  final bool designMode;
  final Map<String, List<Color>>? liveHouseColors;
  final void Function(Map<String, Path> sectionHitPaths)? onSectionHitPathsBuilt;

  Isometric3DHousePainter({
    required this.animation,
    required this.houses,
    required this.elapsedSec,
    this.focusHouseId,
    this.cameraYawOverride,
    this.cameraPitchOverride,
    this.cameraZoomOverride,
    this.selectedSectionId,
    this.highlightedControllerId,
    this.highlightedSegmentIndex,
    this.designMode = false,
    this.liveHouseColors,
    this.onSectionHitPathsBuilt,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF040711),
          Color(0xFF0A142C),
          Color(0xFF060A16),
        ],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(14)),
      skyPaint,
    );

    final streetY = size.height * (designMode ? 0.84 : 0.86);
    if (designMode) {
      final gridPaint = Paint()
        ..color = const Color(0xFF1E293B).withValues(alpha: 0.35)
        ..strokeWidth = 0.8;
      for (int i = -5; i <= 5; i++) {
        final gx = size.width * 0.5 + i * 38.0;
        canvas.drawLine(
          Offset(gx - 28, streetY),
          Offset(gx + 28, size.height * 0.25),
          gridPaint,
        );
      }
    }

    final streetPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.78)
      ..strokeWidth = 1.3;
    canvas.drawLine(
      Offset(10, streetY),
      Offset(size.width - 10, streetY),
      streetPaint,
    );

    final ordered = (houses.isEmpty
            ? SystemConfig.defaultThreeHouses().houses
            : List<HouseConfig>.from(houses))
      ..sort((a, b) => a.order.compareTo(b.order));
    final enabledList = ordered.where((h) => h.enabled).toList();
    final activeList = enabledList.isNotEmpty ? enabledList : ordered;

    final List<HouseConfig> renderHouses;
    if (focusHouseId != null && focusHouseId!.isNotEmpty) {
      final match = ordered.where((h) => h.id == focusHouseId).toList();
      renderHouses = match.isNotEmpty ? match : [activeList.first];
    } else {
      renderHouses = activeList;
    }

    final count = math.max(1, renderHouses.length);
    final singleZoom = count == 1;
    final padX = singleZoom ? math.max(18.0, size.width * 0.10) : 10.0;
    final gap = count <= 1 ? 0.0 : (count > 3 ? 8.0 : 14.0);
    final usableW =
        math.max(60.0, size.width - padX * 2 - gap * (count - 1));
    final slotW = usableW / count;

    final totalWeight = activeList.fold<double>(
      0.0,
      (acc, h) => acc + math.max(0.1, h.timeWeight),
    );
    final totalAllSegs = activeList.fold<int>(
      0,
      (acc, h) => acc + (h.enabled ? h.totalSegments : 0),
    );
    final unwrappedPhase = elapsedSec * animation.speed;
    final hitPaths = <String, Path>{};

    for (int idx = 0; idx < count; idx++) {
      final house = renderHouses[idx];
      final orderIdx = activeList.indexWhere((h) => h.id == house.id);
      final effIdx = orderIdx >= 0 ? orderIdx : idx;
      double prevWeight = 0.0;
      int globalSegCursor = 0;
      for (int j = 0; j < effIdx && j < activeList.length; j++) {
        if (activeList[j].enabled) {
          prevWeight += math.max(0.1, activeList[j].timeWeight);
          globalSegCursor += activeList[j].totalSegments;
        }
      }
      final houseStartNorm = totalWeight > 0
          ? prevWeight / totalWeight
          : effIdx / math.max(1, activeList.length);
      final houseSpanNorm = totalWeight > 0
          ? math.max(0.1, house.timeWeight) / totalWeight
          : 1.0 / math.max(1, activeList.length);

      final isMe = house.isMyHouse;
      final slotLeft = padX + idx * (slotW + gap);
      final slotCenterX = slotLeft + slotW * 0.5;

      final arch = house.architecture;
      final yawDeg = cameraYawOverride ?? arch.cameraYaw;
      final pitchDeg = cameraPitchOverride ?? arch.cameraPitch;
      final zoom = (cameraZoomOverride ?? arch.cameraZoom).clamp(0.65, 1.85);

      final yawRad = yawDeg * math.pi / 180.0;
      final pitchRad = pitchDeg * math.pi / 180.0;
      final cosY = math.cos(yawRad);
      final sinY = math.sin(yawRad);
      final sinP = math.sin(pitchRad);

      final scaleX = slotW * (singleZoom ? 0.78 : 0.80) * zoom;
      final scaleY = size.height * (singleZoom ? 0.58 : 0.54) * zoom;
      final scaleZ = slotW * (singleZoom ? 0.42 : 0.36) * zoom;
      final baseGroundY = streetY - size.height * (singleZoom ? 0.06 : 0.05);

      // 3D -> 2D projection helper:
      // x in [-0.5, 0.5] (left..right), y in [0, 1] (ground..peak), z in [-0.45, 0.45] (back..front)
      Offset project3D(double x, double y, double z) {
        final rx = x * cosY + z * sinY;
        final rz = -x * sinY + z * cosY;
        final sx = slotCenterX + rx * scaleX;
        final sy = baseGroundY - y * scaleY + rz * sinP * scaleZ;
        return Offset(sx, sy);
      }

      double depthKey(double x, double z) => -x * sinY + z * cosY;

      final segTotal = math.max(1, house.totalSegments);
      final segColors = computeHouseSegmentColors(
        house: house,
        segCount: segTotal,
        houseStartNorm: houseStartNorm,
        houseSpanNorm: houseSpanNorm,
        globalSegCursor: globalSegCursor,
        totalAllSegs: totalAllSegs,
        unwrappedPhase: unwrappedPhase,
        elapsedSec: elapsedSec,
        animation: animation,
        liveColors: liveHouseColors?[house.id],
      );

      final sidingBase =
          _parseHexColor(arch.sidingColor, const Color(0xFF15223B));
      final trimCol = _parseHexColor(arch.trimColor, const Color(0xFF475569));
      final roofCol = _parseHexColor(arch.roofColor, const Color(0xFF0E1729));

      // Sort front architectural sections back-to-front by camera depth so protruding garages/towers render in front
      final frontSecs = arch.sections.where((s) => s.wall == 'front').toList();
      final volumesToDraw = frontSecs.isNotEmpty
          ? List<ArchSection>.from(frontSecs)
          : HouseArchitecture.defaultForHouse(house.id, house.order)
              .frontSections;

      volumesToDraw.sort((a, b) {
        if (cosY >= 0 && a.story != b.story) {
          return b.story.compareTo(a.story); // story 2 first, story 1 in front
        }
        final za = 0.16 + a.depthOffset;
        final zb = 0.16 + b.depthOffset;
        final xa = ((a.xStart + a.xEnd) * 0.5) - 0.5;
        final xb = ((b.xStart + b.xEnd) * 0.5) - 0.5;
        return depthKey(xa, za).compareTo(depthKey(xb, zb));
      });

      final section3DPolylines = <String, List<Offset>>{};

      // Also compute 3D eave polylines for left, right, and back wall sections
      for (final sec in arch.sections.where((s) => s.wall != 'front')) {
        final yEave = sec.eaveHeight.clamp(0.25, 0.90);
        final yPeak = math.max(yEave, sec.peakHeight.clamp(0.25, 0.98));
        if (sec.wall == 'left') {
          final pFront = project3D(-0.46, yEave, 0.22);
          final pMid = sec.isPitchedGable
              ? project3D(-0.46, yPeak, 0.0)
              : project3D(-0.46, yEave, 0.0);
          final pBack = project3D(-0.46, yEave, -0.22);
          section3DPolylines[sec.id] = [pFront, pMid, pBack];
        } else if (sec.wall == 'right') {
          final pFront = project3D(0.46, yEave, 0.22);
          final pMid = sec.isPitchedGable
              ? project3D(0.46, yPeak, 0.0)
              : project3D(0.46, yEave, 0.0);
          final pBack = project3D(0.46, yEave, -0.22);
          section3DPolylines[sec.id] = [pFront, pMid, pBack];
        } else if (sec.wall == 'back') {
          final pLeft = project3D(-0.44, yEave, -0.24);
          final pMid = sec.isPitchedGable
              ? project3D(0.0, yPeak, -0.24)
              : project3D(0.0, yEave, -0.24);
          final pRight = project3D(0.44, yEave, -0.24);
          section3DPolylines[sec.id] = [pLeft, pMid, pRight];
        }
      }

      // Draw each 3D architectural volume (walls + 3D roof planes + garage/door/windows)
      for (final sec in volumesToDraw) {
        final x0 = sec.xStart.clamp(0.0, 0.98) - 0.5;
        final x1 = sec.xEnd.clamp(0.02, 1.0) - 0.5;
        final xApex = x0 + (x1 - x0) * sec.peakOffset.clamp(0.15, 0.85);
        final yBottom = sec.story == 2 ? 0.36 : 0.0;
        final yEave = sec.eaveHeight.clamp(0.22, 0.95);
        final yPeak = math.max(yEave, sec.peakHeight.clamp(0.22, 1.0));
        final zFront = (0.18 + sec.depthOffset).clamp(-0.25, 0.42);
        final zBack = (zFront - (sec.story == 2 ? 0.34 : 0.42)).clamp(-0.44, 0.15);

        final flBot = project3D(x0, yBottom, zFront);
        final frBot = project3D(x1, yBottom, zFront);
        final blBot = project3D(x0, yBottom, zBack);
        final brBot = project3D(x1, yBottom, zBack);

        final flEave = project3D(x0, yEave, zFront);
        final frEave = project3D(x1, yEave, zFront);
        final blEave = project3D(x0, yEave, zBack);
        final brEave = project3D(x1, yEave, zBack);

        final fApex = project3D(xApex, yPeak, zFront);
        final bApex = project3D(xApex, yPeak, zBack);

        final isSelectedSec = designMode && selectedSectionId == sec.id;
        final repCol = segColors.isNotEmpty
            ? segColors[segColors.length ~/ 2]
            : const Color(0xFF00F5D4);

        // 1. Side walls (Left & Right 3D extruded faces)
        final leftWallPath = Path()
          ..moveTo(flBot.dx, flBot.dy)
          ..lineTo(blBot.dx, blBot.dy)
          ..lineTo(blEave.dx, blEave.dy)
          ..lineTo(flEave.dx, flEave.dy)
          ..close();
        final rightWallPath = Path()
          ..moveTo(frBot.dx, frBot.dy)
          ..lineTo(brBot.dx, brBot.dy)
          ..lineTo(brEave.dx, brEave.dy)
          ..lineTo(frEave.dx, frEave.dy)
          ..close();

        // Draw whichever side wall is further back first
        final drawLeftFirst = sinY <= 0;
        void drawSideWalls() {
          final leftPaint = Paint()
            ..color = Color.lerp(sidingBase, Colors.black, 0.32)!
                .withValues(alpha: 0.94);
          final rightPaint = Paint()
            ..color = Color.lerp(sidingBase, Colors.black, 0.44)!
                .withValues(alpha: 0.94);
          final sideBorder = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..color = trimCol.withValues(alpha: 0.55);
          if (drawLeftFirst) {
            canvas.drawPath(rightWallPath, rightPaint);
            canvas.drawPath(rightWallPath, sideBorder);
            canvas.drawPath(leftWallPath, leftPaint);
            canvas.drawPath(leftWallPath, sideBorder);
          } else {
            canvas.drawPath(leftWallPath, leftPaint);
            canvas.drawPath(leftWallPath, sideBorder);
            canvas.drawPath(rightWallPath, rightPaint);
            canvas.drawPath(rightWallPath, sideBorder);
          }
        }

        drawSideWalls();

        // 2. 3D Roof Planes (pitched gables, flat parapet, hipped, or shed slope)
        final roofEdgePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelectedSec ? 1.8 : 1.15
          ..color = isSelectedSec
              ? const Color(0xFFFBBF24)
              : trimCol.withValues(alpha: 0.78);

        if (sec.isPitchedGable) {
          final leftSlope = Path()
            ..moveTo(flEave.dx, flEave.dy)
            ..lineTo(blEave.dx, blEave.dy)
            ..lineTo(bApex.dx, bApex.dy)
            ..lineTo(fApex.dx, fApex.dy)
            ..close();
          final rightSlope = Path()
            ..moveTo(frEave.dx, frEave.dy)
            ..lineTo(brEave.dx, brEave.dy)
            ..lineTo(bApex.dx, bApex.dy)
            ..lineTo(fApex.dx, fApex.dy)
            ..close();

          if (sinY <= 0) {
            canvas.drawPath(
              rightSlope,
              Paint()..color = Color.lerp(roofCol, Colors.black, 0.20)!,
            );
            canvas.drawPath(rightSlope, roofEdgePaint);
            canvas.drawPath(
              leftSlope,
              Paint()
                ..color = Color.lerp(
                  roofCol,
                  repCol,
                  animation.running ? 0.14 : 0.04,
                )!,
            );
            canvas.drawPath(leftSlope, roofEdgePaint);
          } else {
            canvas.drawPath(
              leftSlope,
              Paint()..color = Color.lerp(roofCol, Colors.black, 0.20)!,
            );
            canvas.drawPath(leftSlope, roofEdgePaint);
            canvas.drawPath(
              rightSlope,
              Paint()
                ..color = Color.lerp(
                  roofCol,
                  repCol,
                  animation.running ? 0.14 : 0.04,
                )!,
            );
            canvas.drawPath(rightSlope, roofEdgePaint);
          }
        } else if (sec.shape == 'shed_slope') {
          final fLeftTop = sec.peakOffset < 0.5
              ? project3D(x0, yPeak, zFront)
              : flEave;
          final fRightTop = sec.peakOffset >= 0.5
              ? project3D(x1, yPeak, zFront)
              : frEave;
          final bLeftTop = sec.peakOffset < 0.5
              ? project3D(x0, yPeak, zBack)
              : blEave;
          final bRightTop = sec.peakOffset >= 0.5
              ? project3D(x1, yPeak, zBack)
              : brEave;
          final slopeDeck = Path()
            ..moveTo(fLeftTop.dx, fLeftTop.dy)
            ..lineTo(fRightTop.dx, fRightTop.dy)
            ..lineTo(bRightTop.dx, bRightTop.dy)
            ..lineTo(bLeftTop.dx, bLeftTop.dy)
            ..close();
          canvas.drawPath(
            slopeDeck,
            Paint()
              ..color = Color.lerp(
                roofCol,
                repCol,
                animation.running ? 0.12 : 0.04,
              )!,
          );
          canvas.drawPath(slopeDeck, roofEdgePaint);
        } else {
          // Flat parapet deck or hip roof
          final flatDeck = Path()
            ..moveTo(flEave.dx, flEave.dy)
            ..lineTo(frEave.dx, frEave.dy)
            ..lineTo(brEave.dx, brEave.dy)
            ..lineTo(blEave.dx, blEave.dy)
            ..close();
          canvas.drawPath(
            flatDeck,
            Paint()
              ..color = Color.lerp(
                roofCol,
                repCol,
                animation.running ? 0.12 : 0.04,
              )!,
          );
          canvas.drawPath(flatDeck, roofEdgePaint);
        }

        // 3. Front Wall Face (Pentagon for triangle gables/dormers, Quad for flat/hipped, Angled for shed_slope)
        final frontFace = Path()
          ..moveTo(flBot.dx, flBot.dy)
          ..lineTo(flEave.dx, flEave.dy);
        final roofPolyline = <Offset>[];

        if (sec.isPitchedGable) {
          frontFace.lineTo(fApex.dx, fApex.dy);
          frontFace.lineTo(frEave.dx, frEave.dy);
          roofPolyline.addAll([flEave, fApex, frEave]);
        } else if (sec.shape == 'shed_slope') {
          final fLeftTop = sec.peakOffset < 0.5
              ? project3D(x0, yPeak, zFront)
              : flEave;
          final fRightTop = sec.peakOffset >= 0.5
              ? project3D(x1, yPeak, zFront)
              : frEave;
          frontFace.lineTo(fLeftTop.dx, fLeftTop.dy);
          frontFace.lineTo(fRightTop.dx, fRightTop.dy);
          roofPolyline.addAll([fLeftTop, fRightTop]);
        } else {
          frontFace.lineTo(frEave.dx, frEave.dy);
          roofPolyline.addAll([flEave, frEave]);
        }
        frontFace.lineTo(frBot.dx, frBot.dy);
        frontFace.close();

        section3DPolylines[sec.id] = roofPolyline;
        hitPaths[sec.id] = frontFace;

        canvas.drawPath(
          frontFace,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  sidingBase,
                  repCol,
                  animation.running ? 0.25 : 0.06,
                )!,
                const Color(0xFF0A1224),
              ],
            ).createShader(frontFace.getBounds()),
        );
        canvas.drawPath(
          frontFace,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSelectedSec ? 2.4 : (isMe ? 1.3 : 1.0)
            ..color = isSelectedSec
                ? const Color(0xFFFBBF24)
                : (isMe
                    ? const Color(0xFF00F5D4).withValues(alpha: 0.50)
                    : trimCol.withValues(alpha: 0.70)),
        );

        // 4. Draw 3D Architectural Details matching the 4 uploaded Craftsman photos:
        //    - Upper (story == 2): 4 vertical windows + apex gable vent on House 2; 3 vertical windows on House 1 & 3
        //    - Lower (story == 1): 2-car paneled garage doors with 4 top glass window panes + stone-veneer pillars + warm carriage sconces
        //    - Lower (story == 1): White Craftsman porch columns on stone-veneer pedestals + recessed entry door
        final secWidth3D = x1 - x0;
        final secHeight3D = yEave - yBottom;
        if (secWidth3D > 0.12 && secHeight3D > 0.10) {
          void draw3DQuad(
            double qx0,
            double qx1,
            double qy0,
            double qy1,
            double qz,
            Paint fill, [
            Paint? stroke,
          ]) {
            final pBL = project3D(qx0, qy0, qz);
            final pBR = project3D(qx1, qy0, qz);
            final pTR = project3D(qx1, qy1, qz);
            final pTL = project3D(qx0, qy1, qz);
            final path = Path()
              ..moveTo(pBL.dx, pBL.dy)
              ..lineTo(pTL.dx, pTL.dy)
              ..lineTo(pTR.dx, pTR.dy)
              ..lineTo(pBR.dx, pBR.dy)
              ..close();
            canvas.drawPath(path, fill);
            if (stroke != null) {
              canvas.drawPath(path, stroke);
            }
          }

          if (sec.story == 2) {
            // Vertical gable vent right under apex on pitched 2nd-story gables
            if (sec.isPitchedGable && (yPeak - yEave) > 0.12) {
              final vHalfW = math.min(0.018, secWidth3D * 0.03);
              final vy1 = yPeak - (yPeak - yEave) * 0.24;
              final vy0 = vy1 - (yPeak - yEave) * 0.34;
              draw3DQuad(
                xApex - vHalfW,
                xApex + vHalfW,
                vy0,
                vy1,
                zFront + 0.005,
                Paint()..color = trimCol.withValues(alpha: 0.85),
              );
            }

            if (sec.windowStyle != 'none') {
              int winCount = 1;
              if (sec.id == 'sec-main-gable' ||
                  sec.label.contains('4 Windows') ||
                  (sec.windowStyle == 'picture' && secWidth3D > 0.65)) {
                winCount = 4;
              } else if (sec.id == 'sec-upper-dormer' ||
                  sec.id == 'sec-center-flat-fascia' ||
                  sec.label.contains('3 Windows') ||
                  sec.label.contains('3-Window')) {
                winCount = 3;
              }

              final winFill = Paint()
                ..color = const Color(0xFFFDE68A)
                    .withValues(alpha: animation.running ? 0.26 : 0.12);
              final winStroke = Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.95
                ..color = trimCol.withValues(alpha: 0.85);
              final mullionPaint = Paint()
                ..color = trimCol.withValues(alpha: 0.55)
                ..strokeWidth = 0.7;

              final pad3D = secWidth3D * (winCount >= 3 ? 0.12 : 0.26);
              final usableSpan = math.max(0.08, secWidth3D - pad3D * 2);
              final gap3D = winCount > 1 ? usableSpan * 0.08 : 0.0;
              final singleW = math.min(
                0.11,
                (usableSpan - gap3D * (winCount - 1)) / winCount,
              );
              final wy0 = yBottom + secHeight3D * 0.24;
              final wy1 = yBottom + secHeight3D * 0.80;
              final rowStart = x0 +
                  (secWidth3D - (singleW * winCount + gap3D * (winCount - 1))) *
                      0.5;

              for (int wi = 0; wi < winCount; wi++) {
                final wx0 = rowStart + wi * (singleW + gap3D);
                final wx1 = wx0 + singleW;
                draw3DQuad(
                  wx0,
                  wx1,
                  wy0,
                  wy1,
                  zFront + 0.005,
                  winFill,
                  winStroke,
                );
                // Vertical & horizontal Craftsman window mullions
                final mX = (wx0 + wx1) * 0.5;
                final mY = wy0 + (wy1 - wy0) * 0.55;
                canvas.drawLine(
                  project3D(mX, wy0 + 0.01, zFront + 0.006),
                  project3D(mX, wy1 - 0.01, zFront + 0.006),
                  mullionPaint,
                );
                canvas.drawLine(
                  project3D(wx0 + 0.008, mY, zFront + 0.006),
                  project3D(wx1 - 0.008, mY, zFront + 0.006),
                  mullionPaint,
                );
              }
            }
          } else {
            // Story == 1: Garage bays (with 4 top window panes + stone-veneer pillars + carriage sconces)
            // and/or Covered Entry Porch (with white Craftsman columns on stone pedestals)
            final bothPorchAndGarage = sec.hasGarage && sec.hasDoor;
            final porchRightX =
                bothPorchAndGarage ? x0 + secWidth3D * 0.34 : x1;
            final garageLeftX =
                bothPorchAndGarage ? x0 + secWidth3D * 0.34 : x0;

            if (sec.hasDoor) {
              final pSpan = math.max(0.10, porchRightX - x0);
              final dw = math.min(pSpan * 0.38, 0.11);
              final dx0 = x0 + (pSpan - dw) * 0.42;
              final dx1 = dx0 + dw;
              final dyTop = yBottom + secHeight3D * 0.72;
              draw3DQuad(
                dx0,
                dx1,
                yBottom,
                dyTop,
                zFront + 0.005,
                Paint()..color = const Color(0xFF1E293B),
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 0.9
                  ..color = trimCol.withValues(alpha: 0.80),
              );
              // Warm door glass insert + glowing porch sconce
              draw3DQuad(
                dx0 + dw * 0.22,
                dx1 - dw * 0.22,
                yBottom + (dyTop - yBottom) * 0.55,
                dyTop - (dyTop - yBottom) * 0.12,
                zFront + 0.006,
                Paint()
                  ..color = const Color(0xFFFDE68A).withValues(alpha: 0.55),
              );
              final sconcePt = project3D(
                dx0 - 0.025,
                yBottom + secHeight3D * 0.55,
                zFront + 0.008,
              );
              canvas.drawCircle(
                sconcePt,
                singleZoom ? 4.2 : 3.0,
                Paint()
                  ..color = const Color(0xFFFBBF24).withValues(alpha: 0.32)
                  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
              );
              canvas.drawCircle(
                sconcePt,
                singleZoom ? 1.8 : 1.4,
                Paint()..color = const Color(0xFFFEF08A),
              );

              // White Craftsman porch columns on stone-veneer pedestals
              final colXs = <double>[
                x0 + 0.028,
                if (!bothPorchAndGarage) porchRightX - 0.028,
              ];
              final pedTopY = yBottom + secHeight3D * 0.36;
              for (final cx3D in colXs) {
                // Upper tapered white column
                draw3DQuad(
                  cx3D - 0.014,
                  cx3D + 0.014,
                  pedTopY,
                  yEave,
                  zFront + 0.012,
                  Paint()..color = const Color(0xFFE2E8F0),
                );
                // Lower stone-veneer pedestal
                draw3DQuad(
                  cx3D - 0.024,
                  cx3D + 0.024,
                  yBottom,
                  pedTopY,
                  zFront + 0.014,
                  Paint()..color = const Color(0xFF475569),
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 0.75
                    ..color = trimCol.withValues(alpha: 0.75),
                );
              }
            }

            if (sec.hasGarage) {
              final gSpan = math.max(0.14, x1 - garageLeftX);
              final gw = gSpan * 0.76;
              final gx0 = garageLeftX + (gSpan - gw) * 0.5;
              final gx1 = gx0 + gw;
              final gyTop = yBottom + secHeight3D * 0.76;

              // Stone-veneer side pillars flanking the garage + warm carriage sconces
              final pilW = math.max(0.026, (gSpan - gw) * 0.42);
              final pilTopY = yBottom + (gyTop - yBottom) * 0.72;
              for (final px0 in [gx0 - pilW - 0.004, gx1 + 0.004]) {
                draw3DQuad(
                  px0,
                  px0 + pilW,
                  yBottom,
                  pilTopY,
                  zFront + 0.008,
                  Paint()..color = const Color(0xFF334155),
                  Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 0.7
                    ..color = trimCol.withValues(alpha: 0.65),
                );
                final sconcePt = project3D(
                  px0 + pilW * 0.5,
                  gyTop * 0.82,
                  zFront + 0.012,
                );
                canvas.drawCircle(
                  sconcePt,
                  singleZoom ? 4.5 : 3.2,
                  Paint()
                    ..color = const Color(0xFFFBBF24).withValues(alpha: 0.34)
                    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
                );
                canvas.drawCircle(
                  sconcePt,
                  singleZoom ? 1.8 : 1.4,
                  Paint()..color = const Color(0xFFFEF08A),
                );
              }

              // 2-car paneled garage door
              draw3DQuad(
                gx0,
                gx1,
                yBottom,
                gyTop,
                zFront + 0.005,
                Paint()..color = const Color(0xFF1E293B),
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 1.0
                  ..color = trimCol.withValues(alpha: 0.85),
              );
              // Horizontal panel lines + center bay seam
              for (int r = 1; r <= 3; r++) {
                final py = yBottom + (gyTop - yBottom) * (r / 4.0);
                final pL = project3D(gx0 + 0.008, py, zFront + 0.006);
                final pR = project3D(gx1 - 0.008, py, zFront + 0.006);
                canvas.drawLine(
                  pL,
                  pR,
                  Paint()
                    ..color = trimCol.withValues(alpha: 0.45)
                    ..strokeWidth = 0.8,
                );
              }
              final midBayX = (gx0 + gx1) * 0.5;
              canvas.drawLine(
                project3D(midBayX, yBottom + 0.01, zFront + 0.006),
                project3D(
                  midBayX,
                  yBottom + (gyTop - yBottom) * 0.75,
                  zFront + 0.006,
                ),
                Paint()
                  ..color = trimCol.withValues(alpha: 0.38)
                  ..strokeWidth = 0.75,
              );

              // 4 top glass window panes across the top row of the 2-car garage door
              final paneY0 = yBottom + (gyTop - yBottom) * 0.79;
              final paneY1 = yBottom + (gyTop - yBottom) * 0.94;
              final paneMargin = gw * 0.06;
              final paneUsable = gw - paneMargin * 2;
              final paneGap = paneUsable * 0.05;
              final paneW = (paneUsable - paneGap * 3) / 4.0;
              final paneFill = Paint()
                ..color = const Color(0xFFBAE6FD)
                    .withValues(alpha: animation.running ? 0.38 : 0.20);
              for (int pi = 0; pi < 4; pi++) {
                final px0 = gx0 + paneMargin + pi * (paneW + paneGap);
                draw3DQuad(
                  px0,
                  px0 + paneW,
                  paneY0,
                  paneY1,
                  zFront + 0.007,
                  paneFill,
                );
              }
            }
          }
        }

        // Bold 3D fascia trim along the section's roofline
        if (roofPolyline.length >= 2) {
          final fasciaPath = Path()
            ..moveTo(roofPolyline.first.dx, roofPolyline.first.dy);
          for (int k = 1; k < roofPolyline.length; k++) {
            fasciaPath.lineTo(roofPolyline[k].dx, roofPolyline[k].dy);
          }
          canvas.drawPath(
            fasciaPath,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isSelectedSec ? 3.2 : (singleZoom ? 2.4 : 1.9)
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..color = isSelectedSec
                  ? const Color(0xFFFBBF24)
                  : trimCol,
          );
        }
      }

      // Driveway path bollard lights along the left foreground driveway of House 2 (My House)
      if (isMe) {
        for (int bi = 0; bi < 4; bi++) {
          final bx = -0.44 + bi * 0.035;
          final bz = 0.26 + bi * 0.045;
          final bTop = project3D(bx, 0.035, bz);
          final bBase = project3D(bx, 0.0, bz);
          canvas.drawLine(
            bBase,
            bTop,
            Paint()
              ..color = const Color(0xFF94A3B8)
              ..strokeWidth = singleZoom ? 2.0 : 1.4,
          );
          canvas.drawCircle(
            bTop,
            singleZoom ? 4.8 : 3.5,
            Paint()
              ..color = const Color(0xFFFEF08A).withValues(alpha: 0.32)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
          );
          canvas.drawCircle(
            bTop,
            singleZoom ? 1.9 : 1.4,
            Paint()..color = const Color(0xFFFEF9C3),
          );
        }
      }

      // 5. Map each controller's segments & high-density physical sub-pucks onto its assigned 3D section rooflines
      // following Bottom-to-Top Counter-Clockwise (1F LTR -> 2F RTL) wiring flow.
      final placements = <_LedPlacement>[];
      int colorCursor = 0;
      final secById = {for (final s in arch.sections) s.id: s};
      final houseLiveColors = liveHouseColors?[house.id];
      final activeCtrls = house.controllers.where((c) => c.enabled).toList();
      final ctrlsToMap = activeCtrls.isNotEmpty
          ? activeCtrls
          : [
              ControllerConfig(
                id: '${house.id}-ctrl-1',
                name: 'Main Controller',
                segmentCount: segTotal,
              ),
            ];

      for (int ci = 0; ci < ctrlsToMap.length; ci++) {
        final ctrl = ctrlsToMap[ci];
        final spans = house.effectiveControllerSpans(ctrl);
        int localSegIdx = 0;
        for (final sp in spans) {
          final secObj = secById[sp.sectionId];
          final secWall = secObj?.wall ?? sp.wall;
          final secStory = secObj?.story ?? 1;
          final x0 = (secObj?.xStart ?? 0.05).clamp(0.0, 1.0);
          final x1 = (secObj?.xEnd ?? 0.95).clamp(0.0, 1.0);

          List<Offset>? poly = section3DPolylines[sp.sectionId];
          if (poly == null || poly.isEmpty) {
            if (secWall == 'left') {
              poly = [
                project3D(-0.46, 0.50, 0.22),
                project3D(-0.46, 0.50, -0.22),
              ];
            } else if (secWall == 'right') {
              poly = [
                project3D(0.46, 0.50, 0.22),
                project3D(0.46, 0.50, -0.22),
              ];
            } else if (secWall == 'back') {
              poly = [
                project3D(-0.44, 0.50, -0.24),
                project3D(0.44, 0.50, -0.24),
              ];
            } else {
              poly = section3DPolylines.values.isNotEmpty
                  ? section3DPolylines.values.first
                  : [
                      project3D(-0.44, 0.52, 0.20),
                      project3D(0.0, 0.88, 0.20),
                      project3D(0.44, 0.52, 0.20),
                    ];
            }
          }
          final n = sp.segments;
          final subPucks = physicalSubPucksPerSegment(
            segTotal,
            compact: false,
            wall: secWall,
          );
          final isRev = sp.isReverseDirection != ctrl.reversed;

          for (int k = 0; k < n && localSegIdx < ctrl.segmentCount; k++) {
            for (int sub = 0; sub < subPucks; sub++) {
              final spanProgress =
                  (k + (sub + 0.5) / subPucks) / math.max(1, n);
              final u = isRev ? (1.0 - spanProgress) : spanProgress;
              final pt = _samplePolyline2D(poly, u);

              double subArchX;
              if (secWall == 'front') {
                subArchX = (x0 + u * (x1 - x0)).clamp(0.0, 1.0);
              } else if (secWall == 'left') {
                subArchX = (0.04 * (1.0 - u)).clamp(0.0, 1.0);
              } else if (secWall == 'right') {
                subArchX = (0.96 + 0.04 * u).clamp(0.0, 1.0);
              } else {
                subArchX = (1.0 - u).clamp(0.0, 1.0);
              }

              Color col;
              if (houseLiveColors != null &&
                  houseLiveColors.isNotEmpty &&
                  segColors.isNotEmpty) {
                final currCol =
                    segColors[colorCursor.clamp(0, segColors.length - 1)];
                final nextCol =
                    segColors[(colorCursor + 1).clamp(0, segColors.length - 1)];
                col = Color.lerp(currCol, nextCol, sub / subPucks) ?? currCol;
              } else {
                col = evaluateHouseSubPuckColor(
                  house: house,
                  fractionalSegIndex: colorCursor + (sub + 0.5) / subPucks,
                  segCount: segTotal,
                  wall: secWall,
                  story: secStory,
                  archX: subArchX,
                  houseStartNorm: houseStartNorm,
                  houseSpanNorm: houseSpanNorm,
                  globalSegCursor: globalSegCursor,
                  totalAllSegs: totalAllSegs,
                  unwrappedPhase: unwrappedPhase,
                  elapsedSec: elapsedSec,
                  animation: animation,
                );
              }

              final washDrop = singleZoom ? 22.0 : 14.0;
              final washSpread = singleZoom ? 6.5 : 4.2;
              placements.add(
                _LedPlacement(
                  pos: pt,
                  washBaseLeft: Offset(pt.dx - washSpread, pt.dy + washDrop),
                  washBaseRight: Offset(pt.dx + washSpread, pt.dy + washDrop),
                  color: col,
                  controllerId: ctrl.id,
                  controllerIndex: ci,
                  segmentIndex: localSegIdx,
                  subPuckIndex: sub,
                  sectionId: sp.sectionId,
                  wall: secWall,
                  story: secStory,
                ),
              );
            }
            localSegIdx++;
            colorCursor++;
          }
        }
      }

      // 6. Draw downward conical 3D soffit wall-wash light beams + high-density glowing LED pucks
      if (animation.running && house.enabled) {
        for (final p in placements) {
          final isFront = p.wall == 'front';
          final conePath = Path()
            ..moveTo(p.pos.dx, p.pos.dy)
            ..lineTo(p.washBaseLeft.dx, p.washBaseLeft.dy)
            ..lineTo(p.washBaseRight.dx, p.washBaseRight.dy)
            ..close();
          canvas.drawPath(
            conePath,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  p.color.withValues(alpha: isFront ? 0.34 : 0.18),
                  p.color.withValues(alpha: 0.0),
                ],
              ).createShader(
                Rect.fromLTRB(
                  p.washBaseLeft.dx,
                  p.pos.dy,
                  p.washBaseRight.dx,
                  p.washBaseRight.dy,
                ),
              ),
          );
        }
      }

      final ledR = singleZoom ? 3.25 : (count > 2 ? 2.35 : 2.75);
      final bloomPaint = Paint()
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, singleZoom ? 5.6 : 4.2);

      for (final p in placements) {
        final isFront = p.wall == 'front';
        final isHighlighted = designMode &&
            highlightedControllerId == p.controllerId &&
            (highlightedSegmentIndex == null ||
                highlightedSegmentIndex == p.segmentIndex);

        if (animation.running && house.enabled) {
          bloomPaint.color = p.color.withValues(
            alpha: isHighlighted ? 0.95 : (isFront ? 0.82 : 0.58),
          );
          canvas.drawCircle(
            p.pos,
            ledR * (isHighlighted ? 2.4 : (isFront ? 1.90 : 1.45)),
            bloomPaint,
          );
        }
        canvas.drawCircle(
          p.pos,
          isHighlighted ? ledR * 1.35 : (isFront ? ledR : ledR * 0.86),
          Paint()..color = isHighlighted ? Colors.white : p.color,
        );
        if (animation.running && house.enabled && !isHighlighted) {
          canvas.drawCircle(
            p.pos,
            ledR * 0.42,
            Paint()
              ..color = Color.lerp(p.color, Colors.white, 0.58)!
                  .withValues(alpha: isFront ? 0.92 : 0.72),
          );
        }
        if (isHighlighted && p.subPuckIndex == 2) {
          canvas.drawCircle(
            p.pos,
            ledR * 1.85,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = const Color(0xFFFBBF24),
          );
        }
      }

      // In Design Mode, draw subtle "↺ Bottom → Top CCW" flow indicator badge
      if (designMode) {
        final ccwTp = TextPainter(
          text: TextSpan(
            text: singleZoom
                ? '↺ Bottom → Top CCW (1F LTR →  •  ← 2F RTL  •  ${placements.length} LED Pucks)'
                : '↺ CCW (${placements.length} pucks)',
            style: const TextStyle(
              color: Color(0xFFFDE68A),
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: slotW - 8);
        final ccwCenter = Offset(slotCenterX, 14);
        final ccwRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: ccwCenter,
            width: ccwTp.width + 12,
            height: ccwTp.height + 5,
          ),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          ccwRect,
          Paint()..color = const Color(0xFF060B18).withValues(alpha: 0.88),
        );
        canvas.drawRRect(
          ccwRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.9
            ..color = const Color(0xFFFBBF24).withValues(alpha: 0.65),
        );
        ccwTp.paint(
          canvas,
          Offset(
            ccwCenter.dx - ccwTp.width * 0.5,
            ccwCenter.dy - ccwTp.height * 0.5,
          ),
        );
      }

      // 7. Section / Wall callout badges when zoomed into a single house
      final counts = house.wallSegmentCounts;
      if (singleZoom) {
        void drawBadge(String text, Offset center, Color accent) {
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(
                color: accent,
                fontSize: 10.0,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final bgRect = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center,
              width: tp.width + 12,
              height: tp.height + 6,
            ),
            const Radius.circular(6),
          );
          canvas.drawRRect(
            bgRect,
            Paint()..color = const Color(0xFF060B18).withValues(alpha: 0.88),
          );
          canvas.drawRRect(
            bgRect,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0
              ..color = accent.withValues(alpha: 0.6),
          );
          tp.paint(
            canvas,
            Offset(center.dx - tp.width * 0.5, center.dy - tp.height * 0.5),
          );
        }

        drawBadge(
          'FRONT (${volumesToDraw.length} sec): ${counts["front"]} segs',
          Offset(slotCenterX, streetY - 12),
          const Color(0xFF00F5D4),
        );
        if ((counts['left'] ?? 0) > 0 || !house.isMyHouse) {
          drawBadge(
            'LEFT: ${counts["left"]} segs',
            Offset(slotLeft + 38, size.height * 0.24),
            counts['left']! > 0
                ? const Color(0xFFC084FC)
                : const Color(0xFF64748B),
          );
        }
        if ((counts['right'] ?? 0) > 0 || !house.isMyHouse) {
          drawBadge(
            'RIGHT: ${counts["right"]} segs',
            Offset(slotLeft + slotW - 42, size.height * 0.24),
            counts['right']! > 0
                ? const Color(0xFFC084FC)
                : const Color(0xFF64748B),
          );
        }
      }

      // Bottom house label
      final sideTotal =
          (counts['left'] ?? 0) + (counts['right'] ?? 0) + (counts['back'] ?? 0);
      final wallSummary = sideTotal > 0
          ? 'Front:${counts["front"]} • Sides:$sideTotal'
          : '${volumesToDraw.length} Roof Sec (${counts["front"]} segs)';
      final labelText = singleZoom
          ? '${house.name} — 3D Architecture ($wallSummary)'
          : '#${effIdx + 1} ${house.name.split("(").first.trim()} ($wallSummary)';

      final tp = TextPainter(
        text: TextSpan(
          text: labelText,
          style: TextStyle(
            color: isMe ? const Color(0xFF00F5D4) : const Color(0xFFE2E8F0),
            fontSize: singleZoom ? 11.2 : 9.8,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: slotW - 4);
      tp.paint(
        canvas,
        Offset(
          slotLeft + (slotW - tp.width) * 0.5,
          streetY + 3,
        ),
      );
    }

    if (onSectionHitPathsBuilt != null) {
      onSectionHitPathsBuilt!(hitPaths);
    }
  }

  @override
  bool shouldRepaint(covariant Isometric3DHousePainter oldDelegate) {
    return oldDelegate.elapsedSec != elapsedSec ||
        oldDelegate.focusHouseId != focusHouseId ||
        oldDelegate.cameraYawOverride != cameraYawOverride ||
        oldDelegate.cameraPitchOverride != cameraPitchOverride ||
        oldDelegate.cameraZoomOverride != cameraZoomOverride ||
        oldDelegate.selectedSectionId != selectedSectionId ||
        oldDelegate.highlightedControllerId != highlightedControllerId ||
        oldDelegate.highlightedSegmentIndex != highlightedSegmentIndex ||
        oldDelegate.designMode != designMode ||
        oldDelegate.animation != animation ||
        oldDelegate.houses != houses;
  }
}

class Isometric3DScenePreview extends StatefulWidget {
  final Animation<double> clock;
  final AnimationConfig animation;
  final List<HouseConfig> houses;
  final String? focusHouseId;
  final double height;
  final double? cameraYawOverride;
  final double? cameraPitchOverride;
  final double? cameraZoomOverride;
  final String? selectedSectionId;
  final String? highlightedControllerId;
  final int? highlightedSegmentIndex;
  final bool designMode;
  final bool enableInteractiveOrbit;
  final ValueChanged<String>? onSectionTapped;
  final void Function(double yaw, double pitch)? onOrbitChanged;
  final Map<String, List<Color>>? liveHouseColors;

  const Isometric3DScenePreview({
    super.key,
    required this.clock,
    required this.animation,
    required this.houses,
    this.focusHouseId,
    this.height = 175,
    this.cameraYawOverride,
    this.cameraPitchOverride,
    this.cameraZoomOverride,
    this.selectedSectionId,
    this.highlightedControllerId,
    this.highlightedSegmentIndex,
    this.designMode = false,
    this.enableInteractiveOrbit = true,
    this.onSectionTapped,
    this.onOrbitChanged,
    this.liveHouseColors,
  });

  @override
  State<Isometric3DScenePreview> createState() =>
      _Isometric3DScenePreviewState();
}

class _Isometric3DScenePreviewState extends State<Isometric3DScenePreview> {
  double _dragYawOffset = 0.0;
  double _dragPitchOffset = 0.0;
  Map<String, Path> _lastHitPaths = const {};

  @override
  Widget build(BuildContext context) {
    final effectiveYaw = widget.cameraYawOverride != null
        ? widget.cameraYawOverride!
        : (-26.0 + _dragYawOffset).clamp(-75.0, 75.0);
    final effectivePitch = widget.cameraPitchOverride != null
        ? widget.cameraPitchOverride!
        : (20.0 + _dragPitchOffset).clamp(6.0, 58.0);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onSectionTapped == null
            ? null
            : (details) {
                final pos = details.localPosition;
                for (final entry in _lastHitPaths.entries.toList().reversed) {
                  if (entry.value.contains(pos)) {
                    widget.onSectionTapped!(entry.key);
                    break;
                  }
                }
              },
        onHorizontalDragUpdate: !widget.enableInteractiveOrbit
            ? null
            : (details) {
                final nextYaw =
                    (effectiveYaw + details.delta.dx * 0.45).clamp(-85.0, 85.0);
                if (widget.onOrbitChanged != null) {
                  widget.onOrbitChanged!(nextYaw, effectivePitch);
                } else {
                  setState(() {
                    _dragYawOffset =
                        (_dragYawOffset + details.delta.dx * 0.45)
                            .clamp(-60.0, 60.0);
                  });
                }
              },
        onVerticalDragUpdate: (!widget.enableInteractiveOrbit || !widget.designMode)
            ? null
            : (details) {
                final nextPitch =
                    (effectivePitch - details.delta.dy * 0.35).clamp(6.0, 60.0);
                if (widget.onOrbitChanged != null) {
                  widget.onOrbitChanged!(effectiveYaw, nextPitch);
                } else {
                  setState(() {
                    _dragPitchOffset =
                        (_dragPitchOffset - details.delta.dy * 0.35)
                            .clamp(-14.0, 35.0);
                  });
                }
              },
        child: AnimatedBuilder(
          animation: widget.clock,
          builder: (context, _) {
            final elapsedSec = widget.clock.value * 60.0;
            return CustomPaint(
              painter: Isometric3DHousePainter(
                animation: widget.animation,
                houses: widget.houses,
                elapsedSec: elapsedSec,
                focusHouseId: widget.focusHouseId,
                cameraYawOverride: effectiveYaw,
                cameraPitchOverride: effectivePitch,
                cameraZoomOverride: widget.cameraZoomOverride,
                selectedSectionId: widget.selectedSectionId,
                highlightedControllerId: widget.highlightedControllerId,
                highlightedSegmentIndex: widget.highlightedSegmentIndex,
                designMode: widget.designMode,
                liveHouseColors: widget.liveHouseColors,
                onSectionHitPathsBuilt: (paths) {
                  _lastHitPaths = paths;
                },
              ),
            );
          },
        ),
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
