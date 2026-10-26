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
  final tail = anim.tailLength.clamp(0.03, 0.85);

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

  final effect = anim.effect;
  RgbTriplet out = primary;

  if (effect == 'multi_house_chase') {
    double bestIntensity = 0.0;
    RgbTriplet bestColor = primary;
    for (int p = 0; p < pulses; p++) {
      final pHead = posMod(headPos + p / pulses, 1.0);
      final distBehind =
          !reverseFlow ? posMod(pHead - x, 1.0) : posMod(x - pHead, 1.0);
      final distAhead =
          !reverseFlow ? posMod(x - pHead, 1.0) : posMod(pHead - x, 1.0);

      final leadWidth = math.max(0.02, tail * 0.18);
      double energy = 0.0;
      RgbTriplet col = primary;

      if (distAhead <= leadWidth) {
        final u = 1.0 - (distAhead / leadWidth);
        energy = (u * u) * (3.0 - 2.0 * u);
        col = lerpRgb(primary, const RgbTriplet(255, 255, 255), 0.35 * energy);
      } else if (distBehind <= tail) {
        final tNorm = distBehind / tail;
        energy =
            math.pow(0.5 * (1.0 + math.cos(math.pi * tNorm)), 1.35).toDouble();
        if (tNorm < 0.45) {
          col = lerpRgb(primary, secondary, tNorm / 0.45);
        } else {
          col = lerpRgb(secondary, accent, (tNorm - 0.45) / 0.55);
        }
      }
      if (energy > bestIntensity) {
        bestIntensity = energy;
        bestColor = col;
      }
    }
    out = addRgb(bgScaled, scaleRgb(bestColor, bestIntensity));
  } else if (effect == 'rainbow_wave') {
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final hue = posMod(x * pulses - dirSign * unwrappedPhase, 1.0);
    out = hsvToRgb(hue, 0.92, 1.0);
  } else if (effect == 'comet_meteor') {
    RgbTriplet bestRgb = bgScaled;
    for (int p = 0; p < pulses; p++) {
      final pHead = posMod(headPos + p / pulses, 1.0);
      final distBehind =
          !reverseFlow ? posMod(pHead - x, 1.0) : posMod(x - pHead, 1.0);
      final distAhead =
          !reverseFlow ? posMod(x - pHead, 1.0) : posMod(pHead - x, 1.0);

      final coreW = math.max(0.015, tail * 0.12);
      if (distAhead <= coreW) {
        final u = 1.0 - distAhead / coreW;
        final coreCol =
            lerpRgb(primary, const RgbTriplet(255, 255, 255), 0.75 * u);
        bestRgb = addRgb(bestRgb, scaleRgb(coreCol, u * u));
      } else if (distBehind <= tail) {
        final tNorm = distBehind / tail;
        final decay = math.exp(-3.2 * tNorm) * (1.0 - tNorm);
        final shimmer = 0.78 + 0.22 * math.sin(elapsedSec * 28.0 + x * 65.0);
        final tailCol =
            lerpRgb(primary, tNorm > 0.5 ? accent : secondary, tNorm);
        bestRgb = addRgb(bestRgb, scaleRgb(tailCol, decay * shimmer));
      }
    }
    out = bestRgb;
  } else if (effect == 'breathing_pulse') {
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final wave = 0.5 *
        (1.0 +
            math.sin(2.0 * math.pi * (unwrappedPhase - dirSign * x * 0.35) -
                math.pi / 2.0));
    final breath = math.pow(wave, 1.5).toDouble();
    final colorMix = 0.5 *
        (1.0 + math.sin(2.0 * math.pi * unwrappedPhase + x * math.pi * 1.25));
    final baseCol = lerpRgb(primary, secondary, colorMix);
    final accentGlow = 0.5 *
        (1.0 +
            math.cos(2.0 *
                math.pi *
                (x * math.max(1, pulses) - dirSign * unwrappedPhase)));
    final blendedCol = lerpRgb(baseCol, accent, 0.22 * accentGlow);
    out = addRgb(bgScaled, scaleRgb(blendedCol, 0.10 + 0.90 * breath));
  } else if (effect == 'color_wipe') {
    final palette = [primary, secondary, accent];
    final stage = unwrappedPhase.floor() % palette.length;
    final prevCol = palette[(stage - 1 + palette.length) % palette.length];
    final currCol = palette[(stage + palette.length) % palette.length];
    final prog = posMod(unwrappedPhase, 1.0);
    final pos = reverseFlow ? (1.0 - x) : x;
    const edgeSoftness = 0.025;
    if (pos < prog - edgeSoftness) {
      out = currCol;
    } else if (pos > prog + edgeSoftness) {
      out = prevCol;
    } else {
      final blend = 1.0 - ((pos - (prog - edgeSoftness)) / (2.0 * edgeSoftness));
      out = lerpRgb(prevCol, currCol, blend);
    }
  } else if (effect == 'theater_chase') {
    final totalSlots = math.max(18, pulses * 24);
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final virtualSlot =
        posMod(x * totalSlots - dirSign * unwrappedPhase * totalSlots, 3.0);
    final distFromSlotCenter =
        math.min((virtualSlot - 0.5).abs(), (virtualSlot - 3.5).abs());
    if (distFromSlotCenter < 0.55) {
      final strength = math.cos((distFromSlotCenter / 0.55) * (math.pi / 2.0));
      final col = ((x * totalSlots).floor() % 2 == 0) ? primary : secondary;
      out = addRgb(bgScaled, scaleRgb(col, strength));
    } else {
      out = bgScaled;
    }
  } else if (effect == 'fire_sparkle') {
    final n1 = valueNoise1d(x * 18.0 - elapsedSec * (3.5 + anim.speed * 4.0));
    final n2 = valueNoise1d(x * 37.0 + elapsedSec * 7.2);
    final heat = (0.62 * n1 + 0.38 * n2).clamp(0.0, 1.0);
    if (heat < 0.35) {
      out = lerpRgb(
          const RgbTriplet(20, 2, 0), const RgbTriplet(190, 25, 0), heat / 0.35);
    } else if (heat < 0.72) {
      out = lerpRgb(const RgbTriplet(190, 25, 0), const RgbTriplet(255, 135, 0),
          (heat - 0.35) / 0.37);
    } else {
      out = lerpRgb(const RgbTriplet(255, 135, 0),
          const RgbTriplet(255, 240, 160), (heat - 0.72) / 0.28);
    }
  } else if (effect == 'sparkle_twinkle') {
    final auroraPhase =
        0.5 * (1.0 + math.sin(2.0 * math.pi * (x * pulses - unwrappedPhase)));
    final auroraCol = lerpRgb(primary, secondary, auroraPhase);
    final base = addRgb(bgScaled, scaleRgb(auroraCol, 0.35));
    final cell = (x * 60.0).floor();
    final tick = (elapsedSec * (4.0 + anim.speed * 8.0)).floor();
    final rnd = deterministicHash(cell * 997 + tick * 131);
    if (rnd > 0.84) {
      final sub = posMod(elapsedSec * (4.0 + anim.speed * 8.0), 1.0);
      final twinkle = math.sin(sub * math.pi);
      final sparkCol =
          lerpRgb(accent, const RgbTriplet(255, 255, 255), 0.65);
      out = addRgb(base, scaleRgb(sparkCol, twinkle));
    } else {
      out = base;
    }
  } else if (effect == 'halloween_spooky') {
    final mistWave =
        0.5 * (1.0 + math.sin(2.0 * math.pi * (x * 2.0 - unwrappedPhase * 0.5)));
    final mistCol = lerpRgb(primary, secondary, mistWave);
    RgbTriplet baseRgb = addRgb(bgScaled, scaleRgb(mistCol, 0.16));
    final palette = [primary, secondary, accent];

    for (int p = 0; p < pulses; p++) {
      final pHead = posMod(headPos + p / pulses, 1.0);
      final distBehind =
          !reverseFlow ? posMod(pHead - x, 1.0) : posMod(x - pHead, 1.0);
      final distAhead =
          !reverseFlow ? posMod(x - pHead, 1.0) : posMod(pHead - x, 1.0);
      final orbCol = palette[p % palette.length];
      final nextCol = palette[(p + 1) % palette.length];

      final leadW = math.max(0.02, tail * 0.20);
      if (distAhead <= leadW) {
        final u = 1.0 - (distAhead / leadW);
        final wobble = 0.82 + 0.18 * math.sin(elapsedSec * 18.0 + x * 40.0);
        final core = lerpRgb(orbCol, accent, 0.45 * u);
        baseRgb = addRgb(baseRgb, scaleRgb(core, (u * u) * wobble));
      } else if (distBehind <= tail) {
        final tNorm = distBehind / tail;
        final decay =
            math.pow(0.5 * (1.0 + math.cos(math.pi * tNorm)), 1.5).toDouble();
        final flicker = 0.75 + 0.25 * valueNoise1d(x * 28.0 - elapsedSec * 9.0);
        final trailCol = lerpRgb(orbCol, nextCol, tNorm);
        baseRgb = addRgb(baseRgb, scaleRgb(trailCol, decay * flicker));
      }
    }

    final strikeSlot = (elapsedSec * 2.5).floor();
    final strikeRnd =
        deterministicHash(strikeSlot * 313 + (x * 3.0).floor() * 17);
    if (strikeRnd > 0.88) {
      final subT = posMod(elapsedSec * 2.5, 1.0);
      final bolt = math
              .pow(math.max(0.0, math.sin(subT * math.pi * 3.0)), 2.0)
              .toDouble() *
          (1.0 - subT);
      final lightningCol =
          lerpRgb(secondary, const RgbTriplet(235, 225, 255), 0.7);
      baseRgb = addRgb(baseRgb, scaleRgb(lightningCol, bolt * 0.95));
    }
    out = baseRgb;
  } else if (effect == 'christmas_magic') {
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final stripeFreq = math.max(6.0, pulses * 9.0);
    final ribbonPhase =
        posMod(x * stripeFreq - dirSign * unwrappedPhase * 2.0, 1.0);
    const snowWhite = RgbTriplet(255, 250, 245);

    RgbTriplet caneCol;
    if (ribbonPhase < 0.333) {
      final localU = ribbonPhase / 0.333;
      final edge =
          0.5 * (1.0 - math.cos(math.pi * math.min(1.0, localU * 4.0)));
      caneCol = lerpRgb(snowWhite, primary, edge);
    } else if (ribbonPhase < 0.666) {
      final localU = (ribbonPhase - 0.333) / 0.333;
      final edge =
          0.5 * (1.0 - math.cos(math.pi * math.min(1.0, localU * 4.0)));
      caneCol = lerpRgb(primary, snowWhite, edge);
    } else {
      final localU = (ribbonPhase - 0.666) / 0.334;
      final edge =
          0.5 * (1.0 - math.cos(math.pi * math.min(1.0, localU * 4.0)));
      caneCol = lerpRgb(snowWhite, secondary, edge);
    }

    RgbTriplet baseRgb = addRgb(bgScaled, scaleRgb(caneCol, 0.52));
    final sleighHead = headPos;
    final distBehind = !reverseFlow
        ? posMod(sleighHead - x, 1.0)
        : posMod(x - sleighHead, 1.0);
    final distAhead = !reverseFlow
        ? posMod(x - sleighHead, 1.0)
        : posMod(sleighHead - x, 1.0);
    final headW = math.max(0.025, tail * 0.22);

    if (distAhead <= headW) {
      final u = 1.0 - (distAhead / headW);
      final sleighCol =
          lerpRgb(accent, const RgbTriplet(255, 255, 255), 0.65 * u);
      baseRgb = addRgb(baseRgb, scaleRgb(sleighCol, u * u));
    } else if (distBehind <= tail) {
      final tNorm = distBehind / tail;
      final wake = math.exp(-2.6 * tNorm) * (1.0 - tNorm);
      final sparkle = 0.65 + 0.35 * math.sin(elapsedSec * 32.0 + x * 90.0);
      final wakeCol = lerpRgb(accent, snowWhite, 0.35 * (1.0 - tNorm));
      baseRgb = addRgb(baseRgb, scaleRgb(wakeCol, wake * sparkle));
    }
    out = baseRgb;
  } else if (effect == 'diwali_festival') {
    final dirSign = reverseFlow ? -1.0 : 1.0;
    final rangoliU =
        posMod(x * math.max(1, pulses) * 1.5 - dirSign * unwrappedPhase, 1.0);
    RgbTriplet rangoliCol;
    if (rangoliU < 0.333) {
      rangoliCol = lerpRgb(primary, secondary, rangoliU / 0.333);
    } else if (rangoliU < 0.666) {
      rangoliCol = lerpRgb(secondary, accent, (rangoliU - 0.333) / 0.333);
    } else {
      rangoliCol = lerpRgb(accent, primary, (rangoliU - 0.666) / 0.334);
    }

    const lampDensity = 18.0;
    final lampPos = posMod(x * lampDensity, 1.0);
    final lampArch = math.pow(math.sin(math.pi * lampPos), 1.8).toDouble();
    final flicker1 = valueNoise1d(x * 32.0 + elapsedSec * 8.5);
    final flicker2 = valueNoise1d(x * 64.0 - elapsedSec * 13.0);
    final flameFlicker = 0.58 + 0.42 * (0.65 * flicker1 + 0.35 * flicker2);

    final diyaGold = lerpRgb(primary, const RgbTriplet(255, 242, 175),
        0.55 * lampArch * flameFlicker);
    final combined = lerpRgb(rangoliCol, diyaGold, 0.55 * lampArch);
    out = addRgb(bgScaled, scaleRgb(combined, 0.35 + 0.65 * flameFlicker));
  } else if (effect == 'center_out_shockwave') {
    final radialDist = (x - 0.50).abs() * 2.0;
    double bestIntensity = 0.0;
    RgbTriplet bestColor = primary;

    for (int p = 0; p < pulses; p++) {
      final ringPos = posMod(headPos + p / pulses, 1.0);
      final distBehind = !reverseFlow
          ? posMod(ringPos - radialDist, 1.0)
          : posMod(radialDist - ringPos, 1.0);
      final distAhead = !reverseFlow
          ? posMod(radialDist - ringPos, 1.0)
          : posMod(ringPos - radialDist, 1.0);

      final leadW = math.max(0.025, tail * 0.22);
      double energy = 0.0;
      RgbTriplet col = primary;

      if (distAhead <= leadW) {
        final u = 1.0 - (distAhead / leadW);
        energy = (u * u) * (3.0 - 2.0 * u);
        col = lerpRgb(primary, const RgbTriplet(255, 255, 255), 0.45 * energy);
      } else if (distBehind <= tail) {
        final tNorm = distBehind / tail;
        energy =
            math.pow(0.5 * (1.0 + math.cos(math.pi * tNorm)), 1.3).toDouble();
        if (tNorm < 0.5) {
          col = lerpRgb(primary, secondary, tNorm / 0.5);
        } else {
          col = lerpRgb(secondary, accent, (tNorm - 0.5) / 0.5);
        }
      }
      if (energy > bestIntensity) {
        bestIntensity = energy;
        bestColor = col;
      }
    }

    final coreProximity = math.max(0.0, 1.0 - (radialDist / 0.18));
    final corePulse =
        0.45 + 0.55 * (0.5 * (1.0 + math.cos(2.0 * math.pi * headPos)));
    final coreRgb = scaleRgb(
        lerpRgb(primary, accent, 0.35), coreProximity * corePulse * 0.55);
    out = addRgb(addRgb(bgScaled, coreRgb), scaleRgb(bestColor, bestIntensity));
  } else if (effect == 'lightning_storm') {
    final cloudN = valueNoise1d(x * 10.0 - elapsedSec * 1.4);
    final cloudCol = lerpRgb(bgScaled, secondary, 0.35 * cloudN);
    RgbTriplet rgbOut = addRgb(bgScaled, scaleRgb(cloudCol, 0.55));

    for (int p = 0; p < pulses; p++) {
      final boltPos = posMod(headPos + p / pulses, 1.0);
      double dist = (x - boltPos).abs();
      dist = math.min(dist, 1.0 - dist);
      final boltW = math.max(0.03, tail * 0.35);
      if (dist <= boltW) {
        final u = 1.0 - (dist / boltW);
        final jagged = 0.65 +
            0.35 *
                deterministicHash(
                    (x * 80.0).floor() + (elapsedSec * 45.0).floor() * 31);
        final energy = math.pow(u, 1.6).toDouble() * jagged;
        final boltCol =
            lerpRgb(primary, const RgbTriplet(235, 250, 255), 0.72 * u);
        rgbOut = addRgb(rgbOut, scaleRgb(boltCol, energy));
      }
    }

    final houseZone = math.min(2, (x * 3.0).floor());
    final flashTick = (elapsedSec * (3.0 + anim.speed * 4.0)).floor();
    final flashHash = deterministicHash(flashTick * 199 + houseZone * 53);
    if (flashHash > 0.83) {
      final sub = posMod(elapsedSec * (3.0 + anim.speed * 4.0), 1.0);
      final flashAmp =
          math.pow(math.max(0.0, math.sin(sub * math.pi * 2.0)), 2.2).toDouble();
      final sheetCol =
          lerpRgb(accent, const RgbTriplet(245, 250, 255), 0.65);
      rgbOut = addRgb(rgbOut, scaleRgb(sheetCol, flashAmp));
    }
    out = rgbOut;
  } else if (effect == 'cyber_snake') {
    final s1Head = posMod(unwrappedPhase, 1.0);
    final s2Head = posMod(-unwrappedPhase, 1.0);
    RgbTriplet rgbOut = bgScaled;

    for (int p = 0; p < pulses; p++) {
      final offset = p / pulses;
      final h1 = posMod(s1Head + offset, 1.0);
      final h2 = posMod(s2Head + offset, 1.0);

      final d1Behind = posMod(h1 - x, 1.0);
      final d1Ahead = posMod(x - h1, 1.0);
      final headW = math.max(0.018, tail * 0.16);
      if (d1Ahead <= headW) {
        final u1 = 1.0 - (d1Ahead / headW);
        rgbOut = addRgb(
            rgbOut,
            scaleRgb(
                lerpRgb(primary, const RgbTriplet(255, 255, 255), 0.55 * u1),
                u1 * u1));
      } else if (d1Behind <= tail) {
        final t1 = d1Behind / tail;
        final e1 = math.pow(1.0 - t1, 1.4).toDouble();
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
      } else if (d2Behind <= tail) {
        final t2 = d2Behind / tail;
        final e2 = math.pow(1.0 - t2, 1.4).toDouble();
        rgbOut = addRgb(rgbOut, scaleRgb(lerpRgb(accent, secondary, t2), e2));
      }

      double headSep = (h1 - h2).abs();
      headSep = math.min(headSep, 1.0 - headSep);
      if (headSep < 0.14) {
        final clashCenter = (h1 - h2).abs() <= 0.5
            ? 0.5 * (h1 + h2)
            : posMod(0.5 * (h1 + h2 + 1.0), 1.0);
        double distClash = (x - clashCenter).abs();
        distClash = math.min(distClash, 1.0 - distClash);
        if (distClash < 0.16) {
          final clashStrength =
              (1.0 - headSep / 0.14) * (1.0 - distClash / 0.16);
          final spark = 0.7 + 0.3 * math.sin(elapsedSec * 45.0 + x * 120.0);
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
