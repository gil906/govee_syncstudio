import React, { useEffect, useRef } from 'react';

// Shared 20 FPS animation loop across all LiveSceneCardPreview instances
const subscribers = new Set();
let rafId = null;
let lastTickMs = 0;
const startWallMs = typeof performance !== 'undefined' ? performance.now() : Date.now();

function tickLoop(nowMs) {
  if (subscribers.size === 0) {
    rafId = null;
    return;
  }
  if (nowMs - lastTickMs >= 48) {
    lastTickMs = nowMs;
    const elapsedSec = (nowMs - startWallMs) / 1000.0;
    subscribers.forEach((fn) => {
      try {
        fn(elapsedSec);
      } catch (e) {
        // ignore individual canvas draw errors
      }
    });
  }
  rafId = window.requestAnimationFrame(tickLoop);
}

function subscribeTicker(fn) {
  subscribers.add(fn);
  if (rafId === null && typeof window !== 'undefined' && window.requestAnimationFrame) {
    lastTickMs = performance.now();
    rafId = window.requestAnimationFrame(tickLoop);
  }
  return () => {
    subscribers.delete(fn);
    if (subscribers.size === 0 && rafId !== null && typeof window !== 'undefined') {
      window.cancelAnimationFrame(rafId);
      rafId = null;
    }
  };
}

export function hexToRgb(hexStr) {
  const s = String(hexStr || '#00f5d4').trim().replace(/^#/, '');
  const full =
    s.length === 3
      ? s
          .split('')
          .map((c) => c + c)
          .join('')
      : s;
  if (full.length !== 6) return [0, 245, 212];
  const n = parseInt(full, 16);
  if (Number.isNaN(n)) return [0, 245, 212];
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function lerpRgb(c1, c2, t) {
  const u = Math.max(0, Math.min(1, t));
  return [
    Math.round(c1[0] + (c2[0] - c1[0]) * u),
    Math.round(c1[1] + (c2[1] - c1[1]) * u),
    Math.round(c1[2] + (c2[2] - c1[2]) * u),
  ];
}

function scaleRgb(c, factor) {
  const f = Math.max(0, Math.min(1, factor));
  return [
    Math.max(0, Math.min(255, Math.round(c[0] * f))),
    Math.max(0, Math.min(255, Math.round(c[1] * f))),
    Math.max(0, Math.min(255, Math.round(c[2] * f))),
  ];
}

function addRgb(c1, c2) {
  return [
    Math.max(0, Math.min(255, c1[0] + c2[0])),
    Math.max(0, Math.min(255, c1[1] + c2[1])),
    Math.max(0, Math.min(255, c1[2] + c2[2])),
  ];
}

function mod1(v) {
  return ((v % 1.0) + 1.0) % 1.0;
}

function modN(v, n) {
  return ((v % n) + n) % n;
}

function deterministicHash(n) {
  let x = (n << 13) ^ n;
  let nn = (Math.imul(x, Math.imul(x, Math.imul(x, 15731)) + 789221) + 1376312589) & 0x7fffffff;
  return nn / 2147483647.0;
}

function valueNoise1d(x) {
  const i = Math.floor(x);
  const f = x - i;
  const u = f * f * (3.0 - 2.0 * f);
  const a = deterministicHash(i);
  const b = deterministicHash(i + 1);
  return a + (b - a) * u;
}

function hsvToRgb(h, s, v) {
  const i = Math.floor(h * 6);
  const f = h * 6 - i;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f) * s);
  let r = 0,
    g = 0,
    b = 0;
  switch (i % 6) {
    case 0:
      r = v;
      g = t;
      b = p;
      break;
    case 1:
      r = q;
      g = v;
      b = p;
      break;
    case 2:
      r = p;
      g = v;
      b = t;
      break;
    case 3:
      r = p;
      g = q;
      b = v;
      break;
    case 4:
      r = t;
      g = p;
      b = v;
      break;
    case 5:
    default:
      r = v;
      g = p;
      b = q;
      break;
  }
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
}

/**
 * Exact JavaScript port of `evaluate_effect_at_point` from `backend/app/animation_engine.py`.
 * Evaluates RGB color at normalized coordinate `x` in [0, 1) and `unwrappedPhase`.
 */
export function evaluateEffectAtPoint(x, unwrappedPhase, elapsedSec, anim) {
  const effect = anim?.effect || 'multi_house_chase';
  const pulses = Math.max(1, Number(anim?.pulse_count || 1));
  const tail = Math.max(0.03, Math.min(0.85, Number(anim?.tail_length || 0.25)));
  const direction = anim?.direction || 'forward';
  const speed = Number(anim?.speed || 0.25);

  const primary = hexToRgb(anim?.primary_color || '#00f5d4');
  const secondary = hexToRgb(anim?.secondary_color || '#7b2cbf');
  const accent = hexToRgb(anim?.accent_color || '#ff007f');
  const bgRaw = hexToRgb(anim?.background_color || '#060814');
  const bgDim = Number(anim?.background_dim ?? 0.08);
  const bgScaled = scaleRgb(bgRaw, bgDim);

  let headPos = 0;
  let reverseFlow = false;
  if (direction === 'pingpong') {
    const cycle = modN(unwrappedPhase, 2.0);
    headPos = cycle <= 1.0 ? cycle : 2.0 - cycle;
    reverseFlow = cycle > 1.0;
  } else if (direction === 'reverse') {
    headPos = mod1(-unwrappedPhase);
    reverseFlow = true;
  } else {
    headPos = mod1(unwrappedPhase);
    reverseFlow = false;
  }

  if (effect === 'multi_house_chase') {
    let bestIntensity = 0.0;
    let bestColor = primary;
    for (let p = 0; p < pulses; p++) {
      const pHead = mod1(headPos + p / pulses);
      const distBehind = !reverseFlow ? mod1(pHead - x) : mod1(x - pHead);
      const distAhead = !reverseFlow ? mod1(x - pHead) : mod1(pHead - x);
      const leadWidth = Math.max(0.02, tail * 0.18);
      let energy = 0;
      let col = primary;
      if (distAhead <= leadWidth) {
        const u = 1.0 - distAhead / leadWidth;
        energy = u * u * (3.0 - 2.0 * u);
        col = lerpRgb(primary, [255, 255, 255], 0.35 * energy);
      } else if (distBehind <= tail) {
        const tNorm = distBehind / tail;
        energy = Math.pow(0.5 * (1.0 + Math.cos(Math.PI * tNorm)), 1.35);
        col =
          tNorm < 0.45
            ? lerpRgb(primary, secondary, tNorm / 0.45)
            : lerpRgb(secondary, accent, (tNorm - 0.45) / 0.55);
      }
      if (energy > bestIntensity) {
        bestIntensity = energy;
        bestColor = col;
      }
    }
    return addRgb(bgScaled, scaleRgb(bestColor, bestIntensity));
  }

  if (effect === 'rainbow_wave') {
    const dirSign = reverseFlow ? -1.0 : 1.0;
    const hue = mod1(x * pulses - dirSign * unwrappedPhase);
    return hsvToRgb(hue, 0.92, 1.0);
  }

  if (effect === 'comet_meteor') {
    let bestRgb = bgScaled;
    for (let p = 0; p < pulses; p++) {
      const pHead = mod1(headPos + p / pulses);
      const distBehind = !reverseFlow ? mod1(pHead - x) : mod1(x - pHead);
      const distAhead = !reverseFlow ? mod1(x - pHead) : mod1(pHead - x);
      const coreW = Math.max(0.015, tail * 0.12);
      if (distAhead <= coreW) {
        const u = 1.0 - distAhead / coreW;
        const coreCol = lerpRgb(primary, [255, 255, 255], 0.75 * u);
        bestRgb = addRgb(bestRgb, scaleRgb(coreCol, u * u));
      } else if (distBehind <= tail) {
        const tNorm = distBehind / tail;
        const decay = Math.exp(-3.2 * tNorm) * (1.0 - tNorm);
        const shimmer = 0.78 + 0.22 * Math.sin(elapsedSec * 28.0 + x * 65.0);
        const tailCol = lerpRgb(primary, tNorm > 0.5 ? accent : secondary, tNorm);
        bestRgb = addRgb(bestRgb, scaleRgb(tailCol, decay * shimmer));
      }
    }
    return bestRgb;
  }

  if (effect === 'breathing_pulse') {
    const dirSign = reverseFlow ? -1.0 : 1.0;
    const wave =
      0.5 *
      (1.0 + Math.sin(2.0 * Math.PI * (unwrappedPhase - dirSign * x * 0.35) - Math.PI / 2.0));
    const breath = Math.pow(wave, 1.5);
    const colorMix =
      0.5 * (1.0 + Math.sin(2.0 * Math.PI * unwrappedPhase + x * Math.PI * 1.25));
    const baseCol = lerpRgb(primary, secondary, colorMix);
    const accentGlow =
      0.5 *
      (1.0 + Math.cos(2.0 * Math.PI * (x * Math.max(1, pulses) - dirSign * unwrappedPhase)));
    const blendedCol = lerpRgb(baseCol, accent, 0.22 * accentGlow);
    return addRgb(bgScaled, scaleRgb(blendedCol, 0.1 + 0.9 * breath));
  }

  if (effect === 'color_wipe') {
    const palette = [primary, secondary, accent];
    const stage = modN(Math.floor(unwrappedPhase), palette.length);
    const prevCol = palette[modN(stage - 1, palette.length)];
    const currCol = palette[stage];
    const prog = mod1(unwrappedPhase);
    const pos = reverseFlow ? 1.0 - x : x;
    const edgeSoftness = 0.025;
    if (pos < prog - edgeSoftness) return currCol;
    if (pos > prog + edgeSoftness) return prevCol;
    const blend = 1.0 - (pos - (prog - edgeSoftness)) / (2.0 * edgeSoftness);
    return lerpRgb(prevCol, currCol, blend);
  }

  if (effect === 'theater_chase') {
    const totalSlots = Math.max(18, pulses * 24);
    const dirSign = reverseFlow ? -1.0 : 1.0;
    const virtualSlot = modN(x * totalSlots - dirSign * unwrappedPhase * totalSlots, 3.0);
    const dist = Math.min(Math.abs(virtualSlot - 0.5), Math.abs(virtualSlot - 3.5));
    if (dist < 0.55) {
      const strength = Math.cos((dist / 0.55) * (Math.PI / 2.0));
      const col = Math.floor(x * totalSlots) % 2 === 0 ? primary : secondary;
      return addRgb(bgScaled, scaleRgb(col, strength));
    }
    return bgScaled;
  }

  if (effect === 'fire_sparkle') {
    const n1 = valueNoise1d(x * 18.0 - elapsedSec * (3.5 + speed * 4.0));
    const n2 = valueNoise1d(x * 37.0 + elapsedSec * 7.2);
    const heat = Math.max(0.0, Math.min(1.0, 0.62 * n1 + 0.38 * n2));
    if (heat < 0.35) return lerpRgb([20, 2, 0], [190, 25, 0], heat / 0.35);
    if (heat < 0.72) return lerpRgb([190, 25, 0], [255, 135, 0], (heat - 0.35) / 0.37);
    return lerpRgb([255, 135, 0], [255, 240, 160], (heat - 0.72) / 0.28);
  }

  if (effect === 'sparkle_twinkle') {
    const auroraPhase = 0.5 * (1.0 + Math.sin(2.0 * Math.PI * (x * pulses - unwrappedPhase)));
    const auroraCol = lerpRgb(primary, secondary, auroraPhase);
    const base = addRgb(bgScaled, scaleRgb(auroraCol, 0.35));
    const cell = Math.floor(x * 60.0);
    const tick = Math.floor(elapsedSec * (4.0 + speed * 8.0));
    const rnd = deterministicHash(cell * 997 + tick * 131);
    if (rnd > 0.84) {
      const sub = mod1(elapsedSec * (4.0 + speed * 8.0));
      const twinkle = Math.sin(sub * Math.PI);
      const sparkCol = lerpRgb(accent, [255, 255, 255], 0.65);
      return addRgb(base, scaleRgb(sparkCol, twinkle));
    }
    return base;
  }

  if (effect === 'halloween_spooky') {
    const mistWave = 0.5 * (1.0 + Math.sin(2.0 * Math.PI * (x * 2.0 - unwrappedPhase * 0.5)));
    const mistCol = lerpRgb(primary, secondary, mistWave);
    let baseRgb = addRgb(bgScaled, scaleRgb(mistCol, 0.16));
    const palette = [primary, secondary, accent];
    for (let p = 0; p < pulses; p++) {
      const pHead = mod1(headPos + p / pulses);
      const distBehind = !reverseFlow ? mod1(pHead - x) : mod1(x - pHead);
      const distAhead = !reverseFlow ? mod1(x - pHead) : mod1(pHead - x);
      const orbCol = palette[p % palette.length];
      const nextCol = palette[(p + 1) % palette.length];
      const leadW = Math.max(0.02, tail * 0.2);
      if (distAhead <= leadW) {
        const u = 1.0 - distAhead / leadW;
        const wobble = 0.82 + 0.18 * Math.sin(elapsedSec * 18.0 + x * 40.0);
        const core = lerpRgb(orbCol, accent, 0.45 * u);
        baseRgb = addRgb(baseRgb, scaleRgb(core, u * u * wobble));
      } else if (distBehind <= tail) {
        const tNorm = distBehind / tail;
        const decay = Math.pow(0.5 * (1.0 + Math.cos(Math.PI * tNorm)), 1.5);
        const flicker = 0.75 + 0.25 * valueNoise1d(x * 28.0 - elapsedSec * 9.0);
        const trailCol = lerpRgb(orbCol, nextCol, tNorm);
        baseRgb = addRgb(baseRgb, scaleRgb(trailCol, decay * flicker));
      }
    }
    const strikeSlot = Math.floor(elapsedSec * 2.5);
    const strikeRnd = deterministicHash(strikeSlot * 313 + Math.floor(x * 3.0) * 17);
    if (strikeRnd > 0.88) {
      const subT = mod1(elapsedSec * 2.5);
      const bolt = Math.pow(Math.max(0.0, Math.sin(subT * Math.PI * 3.0)), 2.0) * (1.0 - subT);
      const lightningCol = lerpRgb(secondary, [235, 225, 255], 0.7);
      baseRgb = addRgb(baseRgb, scaleRgb(lightningCol, bolt * 0.95));
    }
    return baseRgb;
  }

  if (effect === 'christmas_magic') {
    const dirSign = reverseFlow ? -1.0 : 1.0;
    const stripeFreq = Math.max(6.0, pulses * 9.0);
    const ribbonPhase = mod1(x * stripeFreq - dirSign * unwrappedPhase * 2.0);
    const snowWhite = [255, 250, 245];
    let caneCol = primary;
    if (ribbonPhase < 0.333) {
      const localU = ribbonPhase / 0.333;
      const edge = 0.5 * (1.0 - Math.cos(Math.PI * Math.min(1.0, localU * 4.0)));
      caneCol = lerpRgb(snowWhite, primary, edge);
    } else if (ribbonPhase < 0.666) {
      const localU = (ribbonPhase - 0.333) / 0.333;
      const edge = 0.5 * (1.0 - Math.cos(Math.PI * Math.min(1.0, localU * 4.0)));
      caneCol = lerpRgb(primary, snowWhite, edge);
    } else {
      const localU = (ribbonPhase - 0.666) / 0.334;
      const edge = 0.5 * (1.0 - Math.cos(Math.PI * Math.min(1.0, localU * 4.0)));
      caneCol = lerpRgb(snowWhite, secondary, edge);
    }
    let baseRgb = addRgb(bgScaled, scaleRgb(caneCol, 0.52));
    const sleighHead = headPos;
    const distBehind = !reverseFlow ? mod1(sleighHead - x) : mod1(x - sleighHead);
    const distAhead = !reverseFlow ? mod1(x - sleighHead) : mod1(sleighHead - x);
    const headW = Math.max(0.025, tail * 0.22);
    if (distAhead <= headW) {
      const u = 1.0 - distAhead / headW;
      const sleighCol = lerpRgb(accent, [255, 255, 255], 0.65 * u);
      baseRgb = addRgb(baseRgb, scaleRgb(sleighCol, u * u));
    } else if (distBehind <= tail) {
      const tNorm = distBehind / tail;
      const wake = Math.exp(-2.6 * tNorm) * (1.0 - tNorm);
      const sparkle = 0.65 + 0.35 * Math.sin(elapsedSec * 32.0 + x * 90.0);
      const wakeCol = lerpRgb(accent, snowWhite, 0.35 * (1.0 - tNorm));
      baseRgb = addRgb(baseRgb, scaleRgb(wakeCol, wake * sparkle));
    }
    return baseRgb;
  }

  if (effect === 'diwali_festival') {
    const dirSign = reverseFlow ? -1.0 : 1.0;
    const rangoliU = mod1(x * Math.max(1, pulses) * 1.5 - dirSign * unwrappedPhase);
    let rangoliCol = primary;
    if (rangoliU < 0.333) {
      rangoliCol = lerpRgb(primary, secondary, rangoliU / 0.333);
    } else if (rangoliU < 0.666) {
      rangoliCol = lerpRgb(secondary, accent, (rangoliU - 0.333) / 0.333);
    } else {
      rangoliCol = lerpRgb(accent, primary, (rangoliU - 0.666) / 0.334);
    }
    const lampDensity = 18.0;
    const lampPos = mod1(x * lampDensity);
    const lampArch = Math.pow(Math.sin(Math.PI * lampPos), 1.8);
    const flicker1 = valueNoise1d(x * 32.0 + elapsedSec * 8.5);
    const flicker2 = valueNoise1d(x * 64.0 - elapsedSec * 13.0);
    const flameFlicker = 0.58 + 0.42 * (0.65 * flicker1 + 0.35 * flicker2);
    const diyaGold = lerpRgb(primary, [255, 242, 175], 0.55 * lampArch * flameFlicker);
    const combined = lerpRgb(rangoliCol, diyaGold, 0.55 * lampArch);
    return addRgb(bgScaled, scaleRgb(combined, 0.35 + 0.65 * flameFlicker));
  }

  if (effect === 'center_out_shockwave') {
    const radialDist = Math.abs(x - 0.5) * 2.0;
    let bestIntensity = 0.0;
    let bestColor = primary;
    for (let p = 0; p < pulses; p++) {
      const ringPos = mod1(headPos + p / pulses);
      const distBehind = !reverseFlow ? mod1(ringPos - radialDist) : mod1(radialDist - ringPos);
      const distAhead = !reverseFlow ? mod1(radialDist - ringPos) : mod1(ringPos - radialDist);
      const leadW = Math.max(0.025, tail * 0.22);
      let energy = 0.0;
      let col = primary;
      if (distAhead <= leadW) {
        const u = 1.0 - distAhead / leadW;
        energy = u * u * (3.0 - 2.0 * u);
        col = lerpRgb(primary, [255, 255, 255], 0.45 * energy);
      } else if (distBehind <= tail) {
        const tNorm = distBehind / tail;
        energy = Math.pow(0.5 * (1.0 + Math.cos(Math.PI * tNorm)), 1.3);
        col =
          tNorm < 0.5
            ? lerpRgb(primary, secondary, tNorm / 0.5)
            : lerpRgb(secondary, accent, (tNorm - 0.5) / 0.5);
      }
      if (energy > bestIntensity) {
        bestIntensity = energy;
        bestColor = col;
      }
    }
    const coreProximity = Math.max(0.0, 1.0 - radialDist / 0.18);
    const corePulse = 0.45 + 0.55 * (0.5 * (1.0 + Math.cos(2.0 * Math.PI * headPos)));
    const coreRgb = scaleRgb(lerpRgb(primary, accent, 0.35), coreProximity * corePulse * 0.55);
    return addRgb(addRgb(bgScaled, coreRgb), scaleRgb(bestColor, bestIntensity));
  }

  if (effect === 'lightning_storm') {
    const cloudN = valueNoise1d(x * 10.0 - elapsedSec * 1.4);
    const cloudCol = lerpRgb(bgScaled, secondary, 0.35 * cloudN);
    let rgbOut = addRgb(bgScaled, scaleRgb(cloudCol, 0.55));
    for (let p = 0; p < pulses; p++) {
      const boltPos = mod1(headPos + p / pulses);
      let dist = Math.abs(x - boltPos);
      dist = Math.min(dist, 1.0 - dist);
      const boltW = Math.max(0.03, tail * 0.35);
      if (dist <= boltW) {
        const u = 1.0 - dist / boltW;
        const jagged =
          0.65 + 0.35 * deterministicHash(Math.floor(x * 80.0) + Math.floor(elapsedSec * 45.0) * 31);
        const energy = Math.pow(u, 1.6) * jagged;
        const boltCol = lerpRgb(primary, [235, 250, 255], 0.72 * u);
        rgbOut = addRgb(rgbOut, scaleRgb(boltCol, energy));
      }
    }
    const houseZone = Math.min(2, Math.floor(x * 3.0));
    const flashTick = Math.floor(elapsedSec * (3.0 + speed * 4.0));
    const flashHash = deterministicHash(flashTick * 199 + houseZone * 53);
    if (flashHash > 0.83) {
      const sub = mod1(elapsedSec * (3.0 + speed * 4.0));
      const flashAmp = Math.pow(Math.max(0.0, Math.sin(sub * Math.PI * 2.0)), 2.2);
      const sheetCol = lerpRgb(accent, [245, 250, 255], 0.65);
      rgbOut = addRgb(rgbOut, scaleRgb(sheetCol, flashAmp));
    }
    return rgbOut;
  }

  if (effect === 'cyber_snake') {
    const s1Head = mod1(unwrappedPhase);
    const s2Head = mod1(-unwrappedPhase);
    let rgbOut = bgScaled;
    const headW = Math.max(0.018, tail * 0.16);
    for (let p = 0; p < pulses; p++) {
      const offset = p / pulses;
      const h1 = mod1(s1Head + offset);
      const h2 = mod1(s2Head + offset);

      const d1Behind = mod1(h1 - x);
      const d1Ahead = mod1(x - h1);
      if (d1Ahead <= headW) {
        const u1 = 1.0 - d1Ahead / headW;
        rgbOut = addRgb(
          rgbOut,
          scaleRgb(lerpRgb(primary, [255, 255, 255], 0.55 * u1), u1 * u1)
        );
      } else if (d1Behind <= tail) {
        const t1 = d1Behind / tail;
        const e1 = Math.pow(1.0 - t1, 1.4);
        rgbOut = addRgb(rgbOut, scaleRgb(lerpRgb(primary, secondary, t1), e1));
      }

      const d2Behind = mod1(x - h2);
      const d2Ahead = mod1(h2 - x);
      if (d2Ahead <= headW) {
        const u2 = 1.0 - d2Ahead / headW;
        rgbOut = addRgb(
          rgbOut,
          scaleRgb(lerpRgb(accent, [255, 255, 255], 0.55 * u2), u2 * u2)
        );
      } else if (d2Behind <= tail) {
        const t2 = d2Behind / tail;
        const e2 = Math.pow(1.0 - t2, 1.4);
        rgbOut = addRgb(rgbOut, scaleRgb(lerpRgb(accent, secondary, t2), e2));
      }

      let headSep = Math.abs(h1 - h2);
      headSep = Math.min(headSep, 1.0 - headSep);
      if (headSep < 0.14) {
        const clashCenter =
          Math.abs(h1 - h2) <= 0.5 ? 0.5 * (h1 + h2) : mod1(0.5 * (h1 + h2 + 1.0));
        let distClash = Math.abs(x - clashCenter);
        distClash = Math.min(distClash, 1.0 - distClash);
        if (distClash < 0.16) {
          const clashStrength = (1.0 - headSep / 0.14) * (1.0 - distClash / 0.16);
          const spark = 0.7 + 0.3 * Math.sin(elapsedSec * 45.0 + x * 120.0);
          const clashCol = lerpRgb(secondary, [255, 255, 255], 0.8);
          rgbOut = addRgb(rgbOut, scaleRgb(clashCol, clashStrength * spark));
        }
      }
    }
    return rgbOut;
  }

  if (effect === 'govee_rainbow1') {
    const dirSign = reverseFlow ? -1.0 : 1.0;
    const fourthCol =
      Math.max(bgRaw[0], bgRaw[1], bgRaw[2]) > 45
        ? bgRaw
        : lerpRgb(primary, accent, 0.5);
    const stops = [primary, secondary, accent, fourthCol];
    const cycles = Math.max(2, pulses + 1);
    const pos = mod1(x * cycles - dirSign * unwrappedPhase * 1.35);
    const scaled = pos * stops.length;
    const idx = Math.floor(scaled) % stops.length;
    const nxt = (idx + 1) % stops.length;
    const frac = scaled - Math.floor(scaled);
    const smoothT = 0.5 - 0.5 * Math.cos(Math.PI * frac);
    const baseCol = lerpRgb(stops[idx], stops[nxt], smoothT);
    const highlightWave =
      0.5 * (1.0 + Math.sin(2.0 * Math.PI * (x * cycles - dirSign * unwrappedPhase * 2.0)));
    const crest = Math.pow(highlightWave, 3.0) * 0.28;
    const luminous = lerpRgb(baseCol, [255, 255, 255], crest);
    const shimmer =
      0.88 + 0.12 * Math.sin(2.0 * Math.PI * (x * cycles + dirSign * unwrappedPhase * 1.5));
    return scaleRgb(luminous, shimmer);
  }

  if (effect === 'govee_rainbow2') {
    const dirSign = reverseFlow ? -1.0 : 1.0;
    const fourthCol =
      Math.max(bgRaw[0], bgRaw[1], bgRaw[2]) > 45
        ? bgRaw
        : lerpRgb(secondary, [255, 255, 255], 0.38);
    const stops = [primary, secondary, accent, fourthCol];
    const cycles = Math.max(2, pulses + 1);
    const bands = Math.max(2, pulses + 1) * stops.length;
    const bandPos =
      mod1((x * bands - dirSign * unwrappedPhase * stops.length) / stops.length) *
      stops.length;
    const idx = Math.floor(bandPos) % stops.length;
    const nxt = (idx + 1) % stops.length;
    const frac = bandPos - Math.floor(bandPos);
    let baseCol = stops[idx];
    if (frac >= 0.72) {
      const edgeT = (frac - 0.72) / 0.28;
      const smoothEdge = 0.5 - 0.5 * Math.cos(Math.PI * edgeT);
      baseCol = lerpRgb(stops[idx], stops[nxt], smoothEdge);
    }
    const highlightWave =
      0.5 * (1.0 + Math.sin(2.0 * Math.PI * (x * cycles - dirSign * unwrappedPhase * 2.0)));
    const shimmer =
      0.86 + 0.14 * Math.sin(2.0 * Math.PI * (x * 3.0 - dirSign * unwrappedPhase * 2.0));
    const luminous = lerpRgb(baseCol, [255, 255, 255], Math.pow(highlightWave, 3.2) * 0.24);
    return scaleRgb(luminous, shimmer);
  }

  // Smooth moving 3-stop gradient wave fallback so 100% of scenes are guaranteed to animate
  const dirSign = reverseFlow ? -1.0 : 1.0;
  const fallbackU = mod1(x * Math.max(2, pulses + 1) - dirSign * unwrappedPhase);
  let fallbackCol = primary;
  if (fallbackU < 0.333) {
    fallbackCol = lerpRgb(primary, secondary, fallbackU / 0.333);
  } else if (fallbackU < 0.666) {
    fallbackCol = lerpRgb(secondary, accent, (fallbackU - 0.333) / 0.333);
  } else {
    fallbackCol = lerpRgb(accent, primary, (fallbackU - 0.666) / 0.334);
  }
  return addRgb(bgScaled, fallbackCol);
}

const DEFAULT_HOUSE_LAYOUT = [
  { id: 'house-1', label: '#1 Left', segs: 16 },
  { id: 'house-2', label: '#2 My House', segs: 9, isCenter: true },
  { id: 'house-3', label: '#3 Right', segs: 18 },
];

/**
 * Real-Time Multi-House Animated Mini-Preview Canvas (`<LiveSceneCardPreview />`).
 * Dynamically renders all enabled houses (1, 2, 3, or 4+ houses) side-by-side with
 * architectural pitched rooflines, glowing LED dots, and a continuous bottom street timeline bar at 20 FPS.
 */
export default function LiveSceneCardPreview({
  animation,
  houses,
  height = 104,
  className = '',
}) {
  const canvasRef = useRef(null);
  const animRef = useRef(animation);
  const housesRef = useRef(houses);

  useEffect(() => {
    animRef.current = animation;
  }, [animation]);

  useEffect(() => {
    housesRef.current = houses;
  }, [houses]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const ctx = canvas.getContext('2d');
    if (!ctx) return undefined;

    const drawFrame = (elapsedSec) => {
      const W = canvas.width;
      const H = canvas.height;
      const anim = animRef.current || {};
      const speed = Math.max(0.12, Number(anim.speed || 0.25));
      // Slightly boost preview speed (~1.35x) so card previews feel lively and easy to read at a glance
      const unwrappedPhase = elapsedSec * speed * 1.35;
      const mappingMode = anim.mapping_mode || 'house_normalized';

      const enabledHouses = (housesRef.current || []).filter((h) => h.enabled !== false);
      const sourceHouses =
        Array.isArray(housesRef.current) && housesRef.current.length > 0
          ? enabledHouses.length > 0
            ? enabledHouses
            : housesRef.current.slice(0, 1)
          : null;

      const cfgHouses = sourceHouses
        ? sourceHouses.map((h, idx) => {
            const rawCount = (h.controllers || []).reduce(
              (acc, c) => acc + (c.enabled !== false ? Number(c.segment_count || 9) : 0),
              0
            );
            const isMyHouse =
              (h.name || '').toLowerCase().includes('my house') ||
              (h.name || '').toLowerCase().includes('middle') ||
              (sourceHouses.length === 3 && idx === 1) ||
              sourceHouses.length === 1;
            const tw = Math.max(0.1, Number(h.time_weight || 1.0));
            const spdMult = Number((1.0 / tw).toFixed(2));
            const speedTag = Math.abs(tw - 1.0) > 0.03 ? ` · ${spdMult}x` : '';
            const shortName = isMyHouse
              ? `#${idx + 1} My House (${rawCount || 9}s${speedTag})`
              : `#${idx + 1} ${(h.name || `House ${idx + 1}`).split('(')[0].trim().slice(0, 10)} (${rawCount || 12}s${speedTag})`;
            return {
              id: h.id || `h-${idx}`,
              label: shortName,
              segs: Math.max(
                6,
                Math.min(sourceHouses.length === 1 ? 28 : 20, rawCount || (isMyHouse ? 9 : 16))
              ),
              timeWeight: tw,
              isCenter: isMyHouse,
            };
          })
        : DEFAULT_HOUSE_LAYOUT.map((h) => ({ ...h, timeWeight: 1.0 }));

      const houseCount = Math.max(1, cfgHouses.length);
      const totalHouseWeight = cfgHouses.reduce(
        (sum, h) => sum + Math.max(0.1, Number(h.timeWeight || 1.0)),
        0
      );

      // Clear background
      ctx.fillStyle = '#040711';
      ctx.fillRect(0, 0, W, H);

      const padX = 8;
      const gap = houseCount > 3 ? 5 : 8;
      const houseW = (W - padX * 2 - gap * Math.max(0, houseCount - 1)) / houseCount;
      const roofBaseY = H - 22;
      const peak1Y = 17;
      const peak2Y = 23;

      const totalSegsAll = cfgHouses.reduce((s, h) => s + h.segs, 0);
      let globalCursor = 0;
      let cumulativeHouseWeight = 0;

      for (let hIdx = 0; hIdx < houseCount; hIdx++) {
        const hInfo = cfgHouses[hIdx];
        const hWeight = Math.max(0.1, Number(hInfo.timeWeight || 1.0));
        const houseStartNorm = cumulativeHouseWeight / Math.max(0.1, totalHouseWeight);
        const houseSpanNorm = hWeight / Math.max(0.1, totalHouseWeight);
        cumulativeHouseWeight += hWeight;

        const hx = padX + hIdx * (houseW + gap);

        // Subtle card frame per house
        ctx.fillStyle = hInfo.isCenter ? 'rgba(15, 29, 52, 0.55)' : 'rgba(10, 16, 30, 0.5)';
        ctx.strokeStyle = hInfo.isCenter ? 'rgba(34, 211, 238, 0.28)' : 'rgba(51, 65, 85, 0.4)';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.roundRect(hx, 3, houseW, H - 15, 6);
        ctx.fill();
        ctx.stroke();

        // House label
        ctx.fillStyle = hInfo.isCenter ? '#67e8f9' : '#94a3b8';
        ctx.font =
          houseCount >= 4
            ? 'bold 7.5px ui-monospace, SFMono-Regular, Menlo, monospace'
            : 'bold 8.5px ui-monospace, SFMono-Regular, Menlo, monospace';
        ctx.textAlign = 'center';
        ctx.fillText(hInfo.label, hx + houseW * 0.5, 12.5);

        // Architectural double-gable roofline silhouette
        const rx0 = hx + 6;
        const rxW = Math.max(16, houseW - 12);
        ctx.fillStyle = '#090e1c';
        ctx.strokeStyle = '#1e293b';
        ctx.lineWidth = 1.1;

        ctx.beginPath();
        ctx.moveTo(rx0, roofBaseY);
        ctx.lineTo(rx0 + rxW * 0.3, peak1Y);
        ctx.lineTo(rx0 + rxW * 0.56, roofBaseY - 4);
        ctx.lineTo(rx0 + rxW * 0.78, peak2Y);
        ctx.lineTo(rx0 + rxW, roofBaseY);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();

        // Subtle house wall base
        ctx.fillStyle = '#060a14';
        ctx.fillRect(rx0 + 4, roofBaseY, Math.max(8, rxW - 8), 8);

        // Draw glowing LED segments along the pitched roofline
        const segCount = hInfo.segs;
        const dotR = Math.max(2.0, Math.min(3.8, (rxW / segCount) * 0.36));

        for (let s = 0; s < segCount; s++) {
          const t = (s + 0.5) / segCount;
          let normPos = 0;
          if (mappingMode === 'parallel_zones') {
            normPos = t;
          } else if (mappingMode === 'virtual_strip') {
            normPos = (globalCursor + 0.5) / Math.max(1, totalSegsAll);
          } else {
            // house_normalized: each enabled house spans its time_weight share of [0, 1)
            normPos = houseStartNorm + t * houseSpanNorm;
          }
          globalCursor++;

          const [r, g, b] = evaluateEffectAtPoint(normPos, unwrappedPhase, elapsedSec, anim);
          const sx = rx0 + t * rxW;
          let sy = roofBaseY;
          if (t < 0.3) {
            sy = roofBaseY - (t / 0.3) * (roofBaseY - peak1Y);
          } else if (t < 0.56) {
            sy = peak1Y + ((t - 0.3) / 0.26) * (roofBaseY - 4 - peak1Y);
          } else if (t < 0.78) {
            sy = roofBaseY - 4 - ((t - 0.56) / 0.22) * (roofBaseY - 4 - peak2Y);
          } else {
            sy = peak2Y + ((t - 0.78) / 0.22) * (roofBaseY - peak2Y);
          }

          // Outer glow halo
          ctx.fillStyle = `rgba(${r}, ${g}, ${b}, 0.32)`;
          ctx.beginPath();
          ctx.arc(sx, sy, dotR * 2.1, 0, Math.PI * 2);
          ctx.fill();

          // Crisp LED emitter core
          ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
          ctx.beginPath();
          ctx.arc(sx, sy, dotR, 0, Math.PI * 2);
          ctx.fill();
        }
      }

      // Continuous 60-step normalized street strip along the bottom
      const stripY = H - 8;
      const stripH = 5;
      const stripX = padX;
      const stripW = W - padX * 2;
      const samples = 60;
      const cellW = stripW / samples;
      for (let i = 0; i < samples; i++) {
        const xNorm = (i + 0.5) / samples;
        const [r, g, b] = evaluateEffectAtPoint(xNorm, unwrappedPhase, elapsedSec, anim);
        ctx.fillStyle = `rgb(${r}, ${g}, ${b})`;
        ctx.fillRect(stripX + i * cellW, stripY, Math.ceil(cellW), stripH);
      }

      // House boundary divider ticks on the bottom strip respecting each house's time_weight
      if (houseCount > 1) {
        ctx.fillStyle = 'rgba(255,255,255,0.65)';
        let tickWeight = 0;
        for (let d = 0; d < houseCount - 1; d++) {
          tickWeight += Math.max(0.1, Number(cfgHouses[d].timeWeight || 1.0));
          const tickRatio = tickWeight / Math.max(0.1, totalHouseWeight);
          ctx.fillRect(stripX + stripW * tickRatio, stripY - 1, 1.2, stripH + 2);
        }
      }
    };

    // Draw initial frame immediately
    drawFrame((performance.now() - startWallMs) / 1000.0);
    return subscribeTicker(drawFrame);
  }, [height]);

  return (
    <div
      className={`relative rounded-xl overflow-hidden border border-slate-800/90 bg-[#040711] ${className}`}
    >
      <canvas
        ref={canvasRef}
        width={420}
        height={height}
        className="w-full block"
        style={{ height: `${height}px` }}
      />
    </div>
  );
}
