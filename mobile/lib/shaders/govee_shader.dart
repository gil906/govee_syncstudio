import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/govee_models.dart';

class RgbTriplet {
  final int r;
  final int g;
  final int b;

  const RgbTriplet(this.r, this.g, this.b);

  Color toColor([double opacity = 1.0]) =>
      Color.fromRGBO(r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), opacity);
}

RgbTriplet hexToRgb(String hexStr) {
  String s = hexStr.trim().replaceAll('#', '');
  if (s.length == 3) {
    s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
  }
  if (s.length != 6) {
    return const RgbTriplet(0, 245, 212);
  }
  try {
    return RgbTriplet(
      int.parse(s.substring(0, 2), radix: 16),
      int.parse(s.substring(2, 4), radix: 16),
      int.parse(s.substring(4, 6), radix: 16),
    );
  } catch (_) {
    return const RgbTriplet(0, 245, 212);
  }
}

Color hexToColor(String hexStr, [double opacity = 1.0]) =>
    hexToRgb(hexStr).toColor(opacity);

RgbTriplet lerpRgb(RgbTriplet c1, RgbTriplet c2, double t) {
  final tc = t.clamp(0.0, 1.0);
  return RgbTriplet(
    (c1.r + (c2.r - c1.r) * tc).round(),
    (c1.g + (c2.g - c1.g) * tc).round(),
    (c1.b + (c2.b - c1.b) * tc).round(),
  );
}

RgbTriplet scaleRgb(RgbTriplet c, double factor) {
  final f = factor.clamp(0.0, 1.0);
  return RgbTriplet(
    (c.r * f).round().clamp(0, 255),
    (c.g * f).round().clamp(0, 255),
    (c.b * f).round().clamp(0, 255),
  );
}

RgbTriplet addRgb(RgbTriplet c1, RgbTriplet c2) {
  return RgbTriplet(
    (c1.r + c2.r).clamp(0, 255),
    (c1.g + c2.g).clamp(0, 255),
    (c1.b + c2.b).clamp(0, 255),
  );
}

double posMod(double value, double mod) {
  final r = value % mod;
  return r < 0 ? r + mod : r;
}

double deterministicHash(int n) {
  int x = ((n << 13) ^ n) & 0x7FFFFFFF;
  int nn = (x * (x * x * 15731 + 789221) + 1376312589) & 0x7FFFFFFF;
  return nn / 2147483647.0;
}

double valueNoise1d(double x) {
  final int i = x.floor();
  final double f = x - i;
  final double u = f * f * (3.0 - 2.0 * f);
  final double a = deterministicHash(i);
  final double b = deterministicHash(i + 1);
  return a + (b - a) * u;
}

RgbTriplet hsvToRgb(double h, double s, double v) {
  final hsv = HSVColor.fromAHSV(1.0, (posMod(h, 1.0) * 360.0) % 360.0, s, v);
  final col = hsv.toColor();
  return RgbTriplet(
    (col.r * 255.0).round(),
    (col.g * 255.0).round(),
    (col.b * 255.0).round(),
  );
}

/// Pure analytical shader matching `backend/app/animation_engine.py:evaluate_effect_at_point`.
Color evaluateEffectAtPoint({
  required double x,
  required double unwrappedPhase,
  required double elapsedSec,
  required AnimationConfig anim,
}) {
  if (!anim.running) {
    return const Color(0xFF0A0F1D);
  }

  final primary = hexToRgb(anim.primaryColor);
  final secondary = hexToRgb(anim.secondaryColor);
  final accent = hexToRgb(anim.accentColor);
  final bgRaw = hexToRgb(anim.backgroundColor);
  final bgScaled = scaleRgb(bgRaw, anim.backgroundDim.clamp(0.0, 1.0));
  final pulses = math.max(1, anim.pulseCount);
  final effectivePulses = math.max(2, pulses + 1);
  final tail = anim.tailLength.clamp(0.03, 0.85);
  final effTail = math.max(0.36, tail * 1.45).clamp(0.28, 0.88);

  double headPos;
  bool reverseFlow;
  if (anim.direction == 'pingpong') {
    final cycle = posMod(unwrappedPhase, 2.0);
    headPos = cycle <= 1.0 ? cycle : (2.0 - cycle);
    reverseFlow = cycle > 1.0;
  } else if (anim.direction == 'reverse') {
    headPos = posMod(-unwrappedPhase, 1.0);
    reverseFlow = true;
  } else {
    headPos = posMod(unwrappedPhase, 1.0);
    reverseFlow = false;
  }

  final dirSign = reverseFlow ? -1.0 : 1.0;
  final effect = anim.effect;
  RgbTriplet out = primary;

  if (effect == 'multi_house_chase') {
    // Rich ambient secondary <-> accent wave in troughs so houses are never 70% dark
    final troughMix = 0.5 *
        (1.0 +
            math.sin(2.0 * math.pi * (x * 2.0 - dirSign * unwrappedPhase * 1.2)));
    final troughCol = lerpRgb(secondary, accent, troughMix);
    final troughBase = addRgb(
      bgScaled,
      scaleRgb(troughCol, 0.28 + 0.14 * troughMix),
    );

    double bestIntensity = 0.0;
    RgbTriplet bestColor = primary;
    final palette = <RgbTriplet>[primary, secondary, accent];
    for (int p = 0; p < effectivePulses; p++) {
      final pHead = posMod(headPos + p / effectivePulses, 1.0);
      final distBehind =
          !reverseFlow ? posMod(pHead - x, 1.0) : posMod(x - pHead, 1.0);
      final distAhead =
          !reverseFlow ? posMod(x - pHead, 1.0) : posMod(pHead - x, 1.0);

      final leadCol = palette[p % palette.length];
      final midCol = palette[(p + 1) % palette.length];
      final tailCol = palette[(p + 2) % palette.length];
      final leadWidth = math.max(0.035, effTail * 0.22);
      double energy = 0.0;
      RgbTriplet col = leadCol;

      if (distAhead <= leadWidth) {
        final u = 1.0 - (distAhead / leadWidth);
        energy = (u * u) * (3.0 - 2.0 * u);
        col = lerpRgb(leadCol, const RgbTriplet(255, 255, 255), 0.42 * energy);
      } else if (distBehind <= effTail) {
        final tNorm = distBehind / effTail;
        energy =
            math.pow(0.5 * (1.0 + math.cos(math.pi * tNorm)), 1.15).toDouble();
        if (tNorm < 0.48) {
          col = lerpRgb(leadCol, midCol, tNorm / 0.48);
        } else {
          col = lerpRgb(midCol, tailCol, (tNorm - 0.48) / 0.52);
        }
      }
      if (energy > bestIntensity) {
        bestIntensity = energy;
        bestColor = col;
      }
    }
    out = addRgb(troughBase, scaleRgb(bestColor, bestIntensity));
  } else if (effect == 'rainbow_wave') {
    final hue = posMod(x * effectivePulses - dirSign * unwrappedPhase, 1.0);
    out = hsvToRgb(hue, 0.94, 1.0);
  } else if (effect == 'comet_meteor') {
    final nebulaMix = 0.5 *
        (1.0 +
            math.sin(2.0 * math.pi * (x * 2.5 - dirSign * unwrappedPhase * 0.8)));
    final nebulaCol = lerpRgb(secondary, accent, nebulaMix);
    RgbTriplet bestRgb =
        addRgb(bgScaled, scaleRgb(nebulaCol, 0.26 + 0.12 * nebulaMix));
    final palette = <RgbTriplet>[primary, accent, secondary];

    for (int p = 0; p < effectivePulses; p++) {
      final pHead = posMod(headPos + p / effectivePulses, 1.0);
      final distBehind =
          !reverseFlow ? posMod(pHead - x, 1.0) : posMod(x - pHead, 1.0);
      final distAhead =
          !reverseFlow ? posMod(x - pHead, 1.0) : posMod(pHead - x, 1.0);

      final headTone = palette[p % palette.length];
      final midTone = palette[(p + 1) % palette.length];
      final endTone = palette[(p + 2) % palette.length];
      final coreW = math.max(0.03, effTail * 0.18);
      if (distAhead <= coreW) {
        final u = 1.0 - distAhead / coreW;
        final coreCol =
            lerpRgb(headTone, const RgbTriplet(255, 255, 255), 0.78 * u);
        bestRgb = addRgb(bestRgb, scaleRgb(coreCol, u * u));
      } else if (distBehind <= effTail) {
        final tNorm = distBehind / effTail;
        final decay = math.exp(-2.1 * tNorm) * (1.0 - 0.65 * tNorm);
        final shimmer = 0.80 + 0.20 * math.sin(elapsedSec * 28.0 + x * 65.0);
        final tailCol = tNorm < 0.5
            ? lerpRgb(headTone, midTone, tNorm / 0.5)
            : lerpRgb(midTone, endTone, (tNorm - 0.5) / 0.5);
        bestRgb = addRgb(bestRgb, scaleRgb(tailCol, decay * shimmer));
      }
    }
    out = bestRgb;
  } else if (effect == 'breathing_pulse') {
    final wave = 0.5 *
        (1.0 +
            math.sin(2.0 * math.pi * (unwrappedPhase - dirSign * x * 0.65) -
                math.pi / 2.0));
    final breath = math.pow(wave, 1.25).toDouble();
    final colorMix = 0.5 *
        (1.0 + math.sin(2.0 * math.pi * unwrappedPhase + x * math.pi * 2.2));
    final baseCol = lerpRgb(primary, secondary, colorMix);
    final accentGlow = 0.5 *
        (1.0 +
            math.cos(2.0 *
                math.pi *
                (x * effectivePulses - dirSign * unwrappedPhase * 1.4)));
    final blendedCol = lerpRgb(baseCol, accent, 0.38 * accentGlow);
    out = addRgb(bgScaled, scaleRgb(blendedCol, 0.34 + 0.66 * breath));
  } else if (effect == 'color_wipe') {
    final palette = [primary, secondary, accent];
    final stage = unwrappedPhase.floor() % palette.length;
    final prevCol = palette[(stage - 1 + palette.length) % palette.length];
    final currCol = palette[(stage + palette.length) % palette.length];
    final nextCol = palette[(stage + 1) % palette.length];
    final prog = posMod(unwrappedPhase, 1.0);
    final pos = reverseFlow ? (1.0 - x) : x;
    const edgeSoftness = 0.055;
    RgbTriplet baseWipe;
    if (pos < prog - edgeSoftness) {
      final ripple =
          0.5 * (1.0 + math.sin(2.0 * math.pi * (x * 3.0 - unwrappedPhase)));
      baseWipe = lerpRgb(currCol, nextCol, 0.22 * ripple);
    } else if (pos > prog + edgeSoftness) {
      final ripple =
          0.5 * (1.0 + math.cos(2.0 * math.pi * (x * 3.0 + unwrappedPhase)));
      baseWipe = lerpRgb(prevCol, nextCol, 0.22 * ripple);
    } else {
      final blend =
          1.0 - ((pos - (prog - edgeSoftness)) / (2.0 * edgeSoftness));
      final boundaryFlash = math.sin(blend.clamp(0.0, 1.0) * math.pi);
      baseWipe = lerpRgb(
        lerpRgb(prevCol, currCol, blend),
        const RgbTriplet(255, 255, 255),
        0.55 * boundaryFlash,
      );
    }
    out = baseWipe;
  } else if (effect == 'theater_chase') {
    final totalSlots = math.max(24, effectivePulses * 18);
    final shifted = x * totalSlots - dirSign * unwrappedPhase * totalSlots * 0.45;
    final slotIdx = shifted.floor();
    final localU = posMod(shifted, 1.0);
    final palette = <RgbTriplet>[primary, secondary, accent];
    final currCol = palette[slotIdx.abs() % 3];
    final nextCol = palette[(slotIdx.abs() + 1) % 3];
    final bulbShape = 0.48 + 0.52 * math.sin(localU * math.pi);
    final edgeBlend = localU > 0.75 ? (localU - 0.75) / 0.25 : 0.0;
    final col = lerpRgb(currCol, nextCol, edgeBlend);
    final highlight = math.pow(math.sin(localU * math.pi), 4.0).toDouble() * 0.30;
    final litBulb = lerpRgb(col, const RgbTriplet(255, 255, 255), highlight);
    out = addRgb(bgScaled, scaleRgb(litBulb, bulbShape));
  } else if (effect == 'fire_sparkle') {
    final n1 = valueNoise1d(x * 18.0 - elapsedSec * (3.8 + anim.speed * 4.5));
    final n2 = valueNoise1d(x * 37.0 + elapsedSec * 7.6);
    final n3 = 0.5 * (1.0 + math.sin(2.0 * math.pi * (x * 3.0 - unwrappedPhase)));
    final heat = (0.50 * n1 + 0.32 * n2 + 0.18 * n3).clamp(0.0, 1.0);
    RgbTriplet flameCol;
    if (heat < 0.38) {
      flameCol = lerpRgb(secondary, primary, heat / 0.38);
    } else if (heat < 0.74) {
      flameCol = lerpRgb(primary, accent, (heat - 0.38) / 0.36);
    } else {
      flameCol = lerpRgb(
        accent,
        const RgbTriplet(255, 245, 190),
        (heat - 0.74) / 0.26,
      );
    }
    out = addRgb(bgScaled, scaleRgb(flameCol, 0.48 + 0.52 * heat));
  } else if (effect == 'sparkle_twinkle') {
    final auroraU = posMod(
      x * effectivePulses * 1.2 - dirSign * unwrappedPhase * 1.1,
      1.0,
    );
    RgbTriplet auroraCol;
    if (auroraU < 0.333) {
      auroraCol = lerpRgb(primary, secondary, auroraU / 0.333);
    } else if (auroraU < 0.666) {
      auroraCol = lerpRgb(secondary, accent, (auroraU - 0.333) / 0.333);
    } else {
      auroraCol = lerpRgb(accent, primary, (auroraU - 0.666) / 0.334);
    }
    final waveGlow = 0.55 +
        0.25 *
            math.sin(2.0 * math.pi * (x * effectivePulses + unwrappedPhase));
    final base = addRgb(bgScaled, scaleRgb(auroraCol, waveGlow));
    final cell = (x * 64.0).floor();
    final tick = (elapsedSec * (4.5 + anim.speed * 8.5)).floor();
    final rnd = deterministicHash(cell * 997 + tick * 131);
    if (rnd > 0.62) {
      final sub = posMod(elapsedSec * (4.5 + anim.speed * 8.5) + rnd * 3.0, 1.0);
      final twinkle = math.sin(sub * math.pi);
      final sparkCol =
          lerpRgb(accent, const RgbTriplet(255, 255, 255), 0.70);
      out = addRgb(base, scaleRgb(sparkCol, twinkle));
    } else {
      out = base;
    }
  } else if (effect == 'halloween_spooky') {
    final mistU =
        posMod(x * 2.2 - dirSign * unwrappedPhase * 0.65, 1.0);
    RgbTriplet mistCol;
    if (mistU < 0.333) {
      mistCol = lerpRgb(primary, secondary, mistU / 0.333);
    } else if (mistU < 0.666) {
      mistCol = lerpRgb(secondary, accent, (mistU - 0.333) / 0.333);
    } else {
      mistCol = lerpRgb(accent, primary, (mistU - 0.666) / 0.334);
    }
    RgbTriplet baseRgb = addRgb(bgScaled, scaleRgb(mistCol, 0.38));
    final palette = [primary, secondary, accent];

    for (int p = 0; p < effectivePulses; p++) {
      final pHead = posMod(headPos + p / effectivePulses, 1.0);
      final distBehind =
          !reverseFlow ? posMod(pHead - x, 1.0) : posMod(x - pHead, 1.0);
      final distAhead =
          !reverseFlow ? posMod(x - pHead, 1.0) : posMod(pHead - x, 1.0);
      final orbCol = palette[p % palette.length];
      final nextCol = palette[(p + 1) % palette.length];

      final leadW = math.max(0.035, effTail * 0.24);
      if (distAhead <= leadW) {
        final u = 1.0 - (distAhead / leadW);
        final wobble = 0.85 + 0.15 * math.sin(elapsedSec * 18.0 + x * 40.0);
        final core = lerpRgb(orbCol, const RgbTriplet(255, 255, 255), 0.45 * u);
        baseRgb = addRgb(baseRgb, scaleRgb(core, (u * u) * wobble));
      } else if (distBehind <= effTail) {
        final tNorm = distBehind / effTail;
        final decay =
            math.pow(0.5 * (1.0 + math.cos(math.pi * tNorm)), 1.2).toDouble();
        final flicker = 0.78 + 0.22 * valueNoise1d(x * 28.0 - elapsedSec * 9.0);
        final trailCol = lerpRgb(orbCol, nextCol, tNorm);
        baseRgb = addRgb(baseRgb, scaleRgb(trailCol, decay * flicker));
      }
    }

    final strikeSlot = (elapsedSec * 2.8).floor();
    final strikeRnd =
        deterministicHash(strikeSlot * 313 + (x * 4.0).floor() * 17);
    if (strikeRnd > 0.76) {
      final subT = posMod(elapsedSec * 2.8, 1.0);
      final bolt = math
              .pow(math.max(0.0, math.sin(subT * math.pi * 3.0)), 1.8)
              .toDouble() *
          (1.0 - subT * 0.7);
      final lightningCol =
          lerpRgb(accent, const RgbTriplet(240, 230, 255), 0.65);
      baseRgb = addRgb(baseRgb, scaleRgb(lightningCol, bolt * 0.90));
    }
    out = baseRgb;
  } else if (effect == 'christmas_magic') {
    final stripeFreq = math.max(6.0, effectivePulses * 5.0);
    final ribbonPhase =
        posMod(x * stripeFreq - dirSign * unwrappedPhase * 2.0, 1.0);
    const snowWhite = RgbTriplet(255, 250, 245);

    RgbTriplet caneCol;
    if (ribbonPhase < 0.25) {
      final localU = ribbonPhase / 0.25;
      final edge =
          0.5 * (1.0 - math.cos(math.pi * math.min(1.0, localU * 3.0)));
      caneCol = lerpRgb(snowWhite, primary, edge);
    } else if (ribbonPhase < 0.50) {
      final localU = (ribbonPhase - 0.25) / 0.25;
      final edge =
          0.5 * (1.0 - math.cos(math.pi * math.min(1.0, localU * 3.0)));
      caneCol = lerpRgb(primary, accent, edge);
    } else if (ribbonPhase < 0.75) {
      final localU = (ribbonPhase - 0.50) / 0.25;
      final edge =
          0.5 * (1.0 - math.cos(math.pi * math.min(1.0, localU * 3.0)));
      caneCol = lerpRgb(accent, secondary, edge);
    } else {
      final localU = (ribbonPhase - 0.75) / 0.25;
      final edge =
          0.5 * (1.0 - math.cos(math.pi * math.min(1.0, localU * 3.0)));
      caneCol = lerpRgb(secondary, snowWhite, edge);
    }

    RgbTriplet baseRgb = addRgb(bgScaled, scaleRgb(caneCol, 0.72));
    for (int p = 0; p < effectivePulses; p++) {
      final sleighHead = posMod(headPos + p / effectivePulses, 1.0);
      final distBehind = !reverseFlow
          ? posMod(sleighHead - x, 1.0)
          : posMod(x - sleighHead, 1.0);
      final distAhead = !reverseFlow
          ? posMod(x - sleighHead, 1.0)
          : posMod(sleighHead - x, 1.0);
      final headW = math.max(0.03, effTail * 0.22);

      if (distAhead <= headW) {
        final u = 1.0 - (distAhead / headW);
        final sleighCol =
            lerpRgb(accent, const RgbTriplet(255, 255, 255), 0.70 * u);
        baseRgb = addRgb(baseRgb, scaleRgb(sleighCol, u * u));
      } else if (distBehind <= effTail) {
        final tNorm = distBehind / effTail;
        final wake = math.exp(-2.1 * tNorm) * (1.0 - 0.7 * tNorm);
        final sparkle = 0.72 + 0.28 * math.sin(elapsedSec * 32.0 + x * 90.0);
        final wakeCol = lerpRgb(accent, snowWhite, 0.45 * (1.0 - tNorm));
        baseRgb = addRgb(baseRgb, scaleRgb(wakeCol, wake * sparkle * 0.75));
      }
    }
    out = baseRgb;
  } else if (effect == 'diwali_festival') {
    final rangoliU =
        posMod(x * effectivePulses * 1.4 - dirSign * unwrappedPhase, 1.0);
    RgbTriplet rangoliCol;
    if (rangoliU < 0.333) {
      rangoliCol = lerpRgb(primary, secondary, rangoliU / 0.333);
    } else if (rangoliU < 0.666) {
      rangoliCol = lerpRgb(secondary, accent, (rangoliU - 0.333) / 0.333);
    } else {
      rangoliCol = lerpRgb(accent, primary, (rangoliU - 0.666) / 0.334);
    }

    const lampDensity = 24.0;
    final lampPos = posMod(x * lampDensity, 1.0);
    final lampArch = math.pow(math.sin(math.pi * lampPos), 1.4).toDouble();
    final flicker1 = valueNoise1d(x * 32.0 + elapsedSec * 8.5);
    final flicker2 = valueNoise1d(x * 64.0 - elapsedSec * 13.0);
    final flameFlicker = 0.68 + 0.32 * (0.65 * flicker1 + 0.35 * flicker2);

    final diyaGold = lerpRgb(secondary, const RgbTriplet(255, 245, 185),
        0.60 * lampArch * flameFlicker);
    final combined = lerpRgb(rangoliCol, diyaGold, 0.52 * lampArch);
    out = addRgb(bgScaled, scaleRgb(combined, 0.52 + 0.48 * flameFlicker));
  } else if (effect == 'center_out_shockwave') {
    final radialDist = (x - 0.50).abs() * 2.0;
    final radialWave = 0.5 *
        (1.0 +
            math.sin(
                2.0 * math.pi * (radialDist * 1.5 - dirSign * unwrappedPhase)));
    final ambientField = addRgb(
      bgScaled,
      scaleRgb(lerpRgb(secondary, accent, radialWave), 0.30 + 0.12 * radialWave),
    );

    double bestIntensity = 0.0;
    RgbTriplet bestColor = primary;
    final palette = <RgbTriplet>[primary, secondary, accent];

    for (int p = 0; p < effectivePulses; p++) {
      final ringPos = posMod(headPos + p / effectivePulses, 1.0);
      final distBehind = !reverseFlow
          ? posMod(ringPos - radialDist, 1.0)
          : posMod(radialDist - ringPos, 1.0);
      final distAhead = !reverseFlow
          ? posMod(radialDist - ringPos, 1.0)
          : posMod(ringPos - radialDist, 1.0);

      final leadTone = palette[p % palette.length];
      final midTone = palette[(p + 1) % palette.length];
      final endTone = palette[(p + 2) % palette.length];
      final leadW = math.max(0.04, effTail * 0.25);
      double energy = 0.0;
      RgbTriplet col = leadTone;

      if (distAhead <= leadW) {
        final u = 1.0 - (distAhead / leadW);
        energy = (u * u) * (3.0 - 2.0 * u);
        col =
            lerpRgb(leadTone, const RgbTriplet(255, 255, 255), 0.50 * energy);
      } else if (distBehind <= effTail) {
        final tNorm = distBehind / effTail;
        energy =
            math.pow(0.5 * (1.0 + math.cos(math.pi * tNorm)), 1.15).toDouble();
        if (tNorm < 0.5) {
          col = lerpRgb(leadTone, midTone, tNorm / 0.5);
        } else {
          col = lerpRgb(midTone, endTone, (tNorm - 0.5) / 0.5);
        }
      }
      if (energy > bestIntensity) {
        bestIntensity = energy;
        bestColor = col;
      }
    }

    final coreProximity = math.max(0.0, 1.0 - (radialDist / 0.28));
    final corePulse =
        0.55 + 0.45 * (0.5 * (1.0 + math.cos(2.0 * math.pi * headPos)));
    final coreRgb = scaleRgb(
        lerpRgb(primary, accent, 0.35), coreProximity * corePulse * 0.65);
    out = addRgb(
      addRgb(ambientField, coreRgb),
      scaleRgb(bestColor, bestIntensity),
    );
  } else if (effect == 'lightning_storm') {
    final cloudN = valueNoise1d(x * 10.0 - elapsedSec * 1.8);
    final cloudWave =
        0.5 * (1.0 + math.sin(2.0 * math.pi * (x * 2.0 - unwrappedPhase * 0.7)));
    final cloudCol = lerpRgb(secondary, primary, 0.48 * cloudN + 0.25 * cloudWave);
    RgbTriplet rgbOut = addRgb(bgScaled, scaleRgb(cloudCol, 0.44));

    for (int p = 0; p < effectivePulses; p++) {
      final boltPos = posMod(headPos + p / effectivePulses, 1.0);
      double dist = (x - boltPos).abs();
      dist = math.min(dist, 1.0 - dist);
      final boltW = math.max(0.08, effTail * 0.45);
      if (dist <= boltW) {
        final u = 1.0 - (dist / boltW);
        final jagged = 0.70 +
            0.30 *
                deterministicHash(
                    (x * 80.0).floor() + (elapsedSec * 45.0).floor() * 31);
        final energy = math.pow(u, 1.35).toDouble() * jagged;
        final boltCol = lerpRgb(
          p.isEven ? primary : accent,
          const RgbTriplet(240, 250, 255),
          0.72 * u,
        );
        rgbOut = addRgb(rgbOut, scaleRgb(boltCol, energy));
      }
    }

    final houseZone = math.min(2, (x * 3.0).floor());
    final flashTick = (elapsedSec * (3.5 + anim.speed * 4.5)).floor();
    final flashHash = deterministicHash(flashTick * 199 + houseZone * 53);
    if (flashHash > 0.72) {
      final sub = posMod(elapsedSec * (3.5 + anim.speed * 4.5), 1.0);
      final flashAmp =
          math.pow(math.max(0.0, math.sin(sub * math.pi * 2.0)), 1.8).toDouble();
      final sheetCol =
          lerpRgb(accent, const RgbTriplet(245, 250, 255), 0.65);
      rgbOut = addRgb(rgbOut, scaleRgb(sheetCol, flashAmp * 0.90));
    }
    out = rgbOut;
  } else if (effect == 'cyber_snake') {
    final s1Head = posMod(unwrappedPhase, 1.0);
    final s2Head = posMod(-unwrappedPhase, 1.0);
    final gridWave =
        0.5 * (1.0 + math.sin(2.0 * math.pi * (x * 3.0 - unwrappedPhase)));
    RgbTriplet rgbOut = addRgb(
      bgScaled,
      scaleRgb(lerpRgb(secondary, primary, gridWave), 0.24),
    );

    for (int p = 0; p < effectivePulses; p++) {
      final offset = p / effectivePulses;
      final h1 = posMod(s1Head + offset, 1.0);
      final h2 = posMod(s2Head + offset, 1.0);

      final d1Behind = posMod(h1 - x, 1.0);
      final d1Ahead = posMod(x - h1, 1.0);
      final headW = math.max(0.03, effTail * 0.20);
      if (d1Ahead <= headW) {
        final u1 = 1.0 - (d1Ahead / headW);
        rgbOut = addRgb(
            rgbOut,
            scaleRgb(
                lerpRgb(primary, const RgbTriplet(255, 255, 255), 0.55 * u1),
                u1 * u1));
      } else if (d1Behind <= effTail) {
        final t1 = d1Behind / effTail;
        final e1 = math.pow(1.0 - t1, 1.2).toDouble();
        rgbOut = addRgb(rgbOut, scaleRgb(lerpRgb(primary, secondary, t1), e1));
      }

      final d2Behind = posMod(x - h2, 1.0);
      final d2Ahead = posMod(h2 - x, 1.0);
      if (d2Ahead <= headW) {
        final u2 = 1.0 - (d2Ahead / headW);
        rgbOut = addRgb(
            rgbOut,
            scaleRgb(
                lerpRgb(accent, const RgbTriplet(255, 255, 255), 0.55 * u2),
                u2 * u2));
      } else if (d2Behind <= effTail) {
        final t2 = d2Behind / effTail;
        final e2 = math.pow(1.0 - t2, 1.2).toDouble();
        rgbOut = addRgb(rgbOut, scaleRgb(lerpRgb(accent, secondary, t2), e2));
      }

      double headSep = (h1 - h2).abs();
      headSep = math.min(headSep, 1.0 - headSep);
      if (headSep < 0.18) {
        final clashCenter = (h1 - h2).abs() <= 0.5
            ? 0.5 * (h1 + h2)
            : posMod(0.5 * (h1 + h2 + 1.0), 1.0);
        double distClash = (x - clashCenter).abs();
        distClash = math.min(distClash, 1.0 - distClash);
        if (distClash < 0.20) {
          final clashStrength =
              (1.0 - headSep / 0.18) * (1.0 - distClash / 0.20);
          final spark = 0.75 + 0.25 * math.sin(elapsedSec * 45.0 + x * 120.0);
          final clashCol =
              lerpRgb(secondary, const RgbTriplet(255, 255, 255), 0.8);
          rgbOut = addRgb(rgbOut, scaleRgb(clashCol, clashStrength * spark));
        }
      }
    }
    out = rgbOut;
  } else if (effect == 'govee_rainbow1') {
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final fourthCol = math.max(bgRaw.r, math.max(bgRaw.g, bgRaw.b)) > 45
        ? bgRaw
        : lerpRgb(primary, accent, 0.5);
    final stops = <RgbTriplet>[primary, secondary, accent, fourthCol];
    final cycles = math.max(2, pulses + 1);
    final pos = posMod(x * cycles - dirSign * unwrappedPhase * 1.35, 1.0);
    final scaled = pos * stops.length;
    final idx = scaled.floor() % stops.length;
    final nxt = (idx + 1) % stops.length;
    final frac = scaled - scaled.floor();
    final smoothT = 0.5 - 0.5 * math.cos(math.pi * frac);
    final baseCol = lerpRgb(stops[idx], stops[nxt], smoothT);
    final shimmerWave = 0.88 +
        0.12 *
            math.sin(
                2.0 * math.pi * (x * cycles + dirSign * unwrappedPhase * 1.5));
    final highlightWave = 0.5 *
        (1.0 +
            math.sin(
                2.0 * math.pi * (x * cycles - dirSign * unwrappedPhase * 2.0)));
    final crest = math.pow(highlightWave, 3.0).toDouble() * 0.28;
    final luminous =
        lerpRgb(baseCol, const RgbTriplet(255, 255, 255), crest);
    out = scaleRgb(luminous, shimmerWave);
  } else if (effect == 'govee_rainbow2') {
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final fourthCol = math.max(bgRaw.r, math.max(bgRaw.g, bgRaw.b)) > 45
        ? bgRaw
        : lerpRgb(secondary, const RgbTriplet(255, 255, 255), 0.38);
    final stops = <RgbTriplet>[primary, secondary, accent, fourthCol];
    final cycles = math.max(2, pulses + 1);
    final bands = math.max(2, pulses + 1) * stops.length;
    final bandPos = posMod(
            (x * bands - dirSign * unwrappedPhase * stops.length) /
                stops.length,
            1.0) *
        stops.length;
    final idx = bandPos.floor() % stops.length;
    final nxt = (idx + 1) % stops.length;
    final frac = bandPos - bandPos.floor();
    RgbTriplet baseCol = stops[idx];
    if (frac >= 0.72) {
      final edgeT = (frac - 0.72) / 0.28;
      final smoothEdge = 0.5 - 0.5 * math.cos(math.pi * edgeT);
      baseCol = lerpRgb(stops[idx], stops[nxt], smoothEdge);
    }
    final shimmer = 0.86 +
        0.14 *
            math.sin(
                2.0 * math.pi * (x * 3.0 - dirSign * unwrappedPhase * 2.0));
    final highlightWave = 0.5 *
        (1.0 +
            math.sin(
                2.0 * math.pi * (x * cycles - dirSign * unwrappedPhase * 2.0)));
    final luminous = lerpRgb(
      baseCol,
      const RgbTriplet(255, 255, 255),
      math.pow(highlightWave, 3.2).toDouble() * 0.24,
    );
    out = scaleRgb(luminous, shimmer);
  } else {
    // Moving 3-stop gradient wave fallback so 100% of scenes are guaranteed to animate
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final fallbackU =
        posMod((x * math.max(2, pulses + 1)) - dirSign * unwrappedPhase, 1.0);
    RgbTriplet fallbackCol;
    if (fallbackU < 0.333) {
      fallbackCol = lerpRgb(primary, secondary, fallbackU / 0.333);
    } else if (fallbackU < 0.666) {
      fallbackCol = lerpRgb(secondary, accent, (fallbackU - 0.333) / 0.333);
    } else {
      fallbackCol = lerpRgb(accent, primary, (fallbackU - 0.666) / 0.334);
    }
    final wave = 0.78 +
        0.22 * math.sin(2.0 * math.pi * (x * 2.0 - dirSign * unwrappedPhase));
    out = addRgb(bgScaled, scaleRgb(fallbackCol, wave));
  }

  final masterFactor = (anim.intensity.clamp(1, 100)) / 100.0;
  return scaleRgb(out, masterFactor).toColor();
}
