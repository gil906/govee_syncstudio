import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import {
  Box,
  Compass,
  Plus,
  Trash2,
  Save,
  RotateCcw,
  Sparkles,
  Flashlight,
  Layers,
  Sliders,
  ArrowUp,
  ArrowDown,
  Check,
  Home,
  Maximize2,
  Minimize2,
  Eye,
  Move,
  PenTool,
  X,
  ChevronRight,
} from 'lucide-react';

const ARCH_STORAGE_KEY = 'govee_house_architectures_v1';

export function loadSavedArchitectureOverrides() {
  if (typeof window === 'undefined') return {};
  try {
    const raw = window.localStorage.getItem(ARCH_STORAGE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch (e) {
    return {};
  }
}

export function saveArchitectureOverride(houseId, architecture, controllerMap = {}) {
  if (typeof window === 'undefined' || !houseId) return;
  try {
    const existing = loadSavedArchitectureOverrides();
    existing[houseId] = {
      architecture,
      controllers: controllerMap,
      updated_at: new Date().toISOString(),
    };
    window.localStorage.setItem(ARCH_STORAGE_KEY, JSON.stringify(existing));
  } catch (e) {
    // ignore storage quota errors
  }
}

export const SECTION_SHAPES = [
  { id: 'triangle_gable', label: '🔺 Triangle Gable Peak', short: 'Triangle Peak' },
  { id: 'steep_gable', label: '📐 Steep A-Frame Peak', short: 'Steep A-Frame' },
  { id: 'flat_eave', label: '⬛ Square / Flat Eave', short: 'Square Eave' },
  { id: 'dormer_peak', label: '🏠 2nd-Story Dormer Peak', short: 'Upper Dormer' },
  { id: 'hip_roof', label: '▱ Hip Roof Trapezoid', short: 'Hip Roof' },
  { id: 'shed_slope', label: '╱ Angled Mono-Slope', short: 'Angled Slope' },
];

export const WALL_OPTIONS = [
  { id: 'front', label: 'Front Facade' },
  { id: 'left', label: 'Left Side Wall' },
  { id: 'right', label: 'Right Side Wall' },
  { id: 'back', label: 'Back Rear Wall' },
];

export const WINDOW_STYLES = [
  { id: 'mullion', label: 'Craftsman Grid' },
  { id: 'picture', label: 'Modern Picture' },
  { id: 'arched', label: 'Cathedral Arch' },
  { id: 'none', label: 'Solid Wall (No Window)' },
];

export const ARCHITECTURAL_PRESETS = {
  a_frame_gable: {
    preset_style: 'a_frame_gable',
    label: '🔺 A-Frame Triangle Gable (My House)',
    description:
      'Prominent front triangle gable peak with pitched left & right roofline slopes meeting at a high apex (0.90), warm entry door, picture windows, and wrap-around side eaves.',
    sections: [
      {
        id: 'sec-front-gable',
        label: 'Front A-Frame Triangle Peak',
        shape: 'triangle_gable',
        wall: 'front',
        story: 1,
        x_start: 0.06,
        x_end: 0.94,
        eave_height: 0.44,
        peak_height: 0.90,
        peak_offset: 0.50,
        depth_offset: 0.10,
        has_garage: false,
        has_door: true,
        window_style: 'picture',
      },
      {
        id: 'sec-left-eave',
        label: 'Left Side Eave',
        shape: 'flat_eave',
        wall: 'left',
        story: 1,
        x_start: 0.05,
        x_end: 0.95,
        eave_height: 0.44,
        peak_height: 0.44,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'mullion',
      },
      {
        id: 'sec-right-eave',
        label: 'Right Side Eave',
        shape: 'flat_eave',
        wall: 'right',
        story: 1,
        x_start: 0.05,
        x_end: 0.95,
        eave_height: 0.44,
        peak_height: 0.44,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'mullion',
      },
    ],
  },

  craftsman_multi_section: {
    preset_style: 'craftsman_multi_section',
    label: '🏘️ Square Garage + Triangle Gable + Upper Dormer',
    description:
      'Multi-section Craftsman: stepped-forward Left Square Garage Eave + Right Entry Triangle Gable + 2nd-Story Upper Dormer Triangle Peak + side & rear perimeter sections.',
    sections: [
      {
        id: 'sec-garage-square',
        label: 'Left Square Garage Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        x_start: 0.04,
        x_end: 0.46,
        eave_height: 0.46,
        peak_height: 0.46,
        peak_offset: 0.50,
        depth_offset: 0.16,
        has_garage: true,
        has_door: false,
        window_style: 'picture',
      },
      {
        id: 'sec-entry-gable',
        label: 'Right Entry Triangle Gable',
        shape: 'triangle_gable',
        wall: 'front',
        story: 1,
        x_start: 0.44,
        x_end: 0.96,
        eave_height: 0.46,
        peak_height: 0.84,
        peak_offset: 0.52,
        depth_offset: 0.04,
        has_garage: false,
        has_door: true,
        window_style: 'mullion',
      },
      {
        id: 'sec-upper-dormer',
        label: '2nd-Story Upper Dormer Peak',
        shape: 'dormer_peak',
        wall: 'front',
        story: 2,
        x_start: 0.22,
        x_end: 0.72,
        eave_height: 0.64,
        peak_height: 0.95,
        peak_offset: 0.50,
        depth_offset: -0.06,
        has_garage: false,
        has_door: false,
        window_style: 'arched',
      },
      {
        id: 'sec-left-wing',
        label: 'Left Side Perimeter Eave',
        shape: 'flat_eave',
        wall: 'left',
        story: 1,
        x_start: 0.05,
        x_end: 0.95,
        eave_height: 0.46,
        peak_height: 0.46,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'mullion',
      },
      {
        id: 'sec-right-wing',
        label: 'Right Side Perimeter Eave',
        shape: 'flat_eave',
        wall: 'right',
        story: 1,
        x_start: 0.05,
        x_end: 0.95,
        eave_height: 0.46,
        peak_height: 0.46,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'mullion',
      },
      {
        id: 'sec-back-eave',
        label: 'Back Patio Eave',
        shape: 'flat_eave',
        wall: 'back',
        story: 1,
        x_start: 0.08,
        x_end: 0.92,
        eave_height: 0.46,
        peak_height: 0.46,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'picture',
      },
    ],
  },

  two_story_estate: {
    preset_style: 'two_story_estate',
    label: '🏰 2-Story Compound Peaks + Flat Fascia',
    description:
      'Grand 2-story compound estate with Left Steep Triangle Gable Tower + Center 2nd-Story Flat Square Fascia + Right Stepped Garage Triangle Peak + side wings.',
    sections: [
      {
        id: 'sec-left-tower',
        label: 'Left Steep Triangle Gable Tower',
        shape: 'steep_gable',
        wall: 'front',
        story: 2,
        x_start: 0.04,
        x_end: 0.36,
        eave_height: 0.62,
        peak_height: 0.96,
        peak_offset: 0.50,
        depth_offset: 0.14,
        has_garage: false,
        has_door: false,
        window_style: 'arched',
      },
      {
        id: 'sec-center-fascia',
        label: 'Center 2nd-Story Flat Square Fascia',
        shape: 'flat_eave',
        wall: 'front',
        story: 2,
        x_start: 0.34,
        x_end: 0.66,
        eave_height: 0.66,
        peak_height: 0.66,
        peak_offset: 0.50,
        depth_offset: 0.02,
        has_garage: false,
        has_door: true,
        window_style: 'mullion',
      },
      {
        id: 'sec-right-garage-gable',
        label: 'Right Garage Triangle Peak',
        shape: 'triangle_gable',
        wall: 'front',
        story: 1,
        x_start: 0.64,
        x_end: 0.96,
        eave_height: 0.45,
        peak_height: 0.80,
        peak_offset: 0.50,
        depth_offset: 0.18,
        has_garage: true,
        has_door: false,
        window_style: 'picture',
      },
      {
        id: 'sec-estate-left',
        label: 'Left Estate Side Wing',
        shape: 'hip_roof',
        wall: 'left',
        story: 2,
        x_start: 0.06,
        x_end: 0.94,
        eave_height: 0.62,
        peak_height: 0.82,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'mullion',
      },
      {
        id: 'sec-estate-right',
        label: 'Right Side Garage Wing',
        shape: 'flat_eave',
        wall: 'right',
        story: 1,
        x_start: 0.06,
        x_end: 0.94,
        eave_height: 0.45,
        peak_height: 0.45,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'mullion',
      },
      {
        id: 'sec-estate-back',
        label: 'Back Rear Estate Eave',
        shape: 'flat_eave',
        wall: 'back',
        story: 2,
        x_start: 0.08,
        x_end: 0.92,
        eave_height: 0.62,
        peak_height: 0.62,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'picture',
      },
    ],
  },

  modern_stepped_slope: {
    preset_style: 'modern_stepped_slope',
    label: '📐 Modern Stepped Boxes + Slope',
    description:
      'Contemporary architectural massing with a cantilevered Square Garage Box, angled Clerestory Shed Slope, and Terraced Flat Eave.',
    sections: [
      {
        id: 'sec-mod-box-left',
        label: 'Left Cantilever Square Box',
        shape: 'flat_eave',
        wall: 'front',
        story: 2,
        x_start: 0.04,
        x_end: 0.44,
        eave_height: 0.68,
        peak_height: 0.68,
        peak_offset: 0.50,
        depth_offset: 0.16,
        has_garage: true,
        has_door: false,
        window_style: 'picture',
      },
      {
        id: 'sec-mod-slope-center',
        label: 'Center Angled Clerestory Slope',
        shape: 'shed_slope',
        wall: 'front',
        story: 2,
        x_start: 0.42,
        x_end: 0.74,
        eave_height: 0.50,
        peak_height: 0.88,
        peak_offset: 0.82,
        depth_offset: 0.04,
        has_garage: false,
        has_door: true,
        window_style: 'picture',
      },
      {
        id: 'sec-mod-terrace-right',
        label: 'Right Terraced Square Wing',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        x_start: 0.72,
        x_end: 0.96,
        eave_height: 0.46,
        peak_height: 0.46,
        peak_offset: 0.50,
        depth_offset: 0.12,
        has_garage: false,
        has_door: false,
        window_style: 'picture',
      },
    ],
  },

  colonial_twin_dormers: {
    preset_style: 'colonial_twin_dormers',
    label: '🏛️ Colonial Twin Dormers + Porch',
    description:
      'Classic symmetrical Colonial with a full-width Hip Roof Porch and Twin 2nd-Story Triangle Dormer Peaks.',
    sections: [
      {
        id: 'sec-col-porch',
        label: 'Main Hip Roof & Front Porch',
        shape: 'hip_roof',
        wall: 'front',
        story: 1,
        x_start: 0.05,
        x_end: 0.95,
        eave_height: 0.46,
        peak_height: 0.66,
        peak_offset: 0.50,
        depth_offset: 0.14,
        has_garage: false,
        has_door: true,
        window_style: 'mullion',
      },
      {
        id: 'sec-col-dormer-l',
        label: 'Left Upper Dormer Triangle',
        shape: 'dormer_peak',
        wall: 'front',
        story: 2,
        x_start: 0.14,
        x_end: 0.44,
        eave_height: 0.66,
        peak_height: 0.92,
        peak_offset: 0.50,
        depth_offset: -0.04,
        has_garage: false,
        has_door: false,
        window_style: 'arched',
      },
      {
        id: 'sec-col-dormer-r',
        label: 'Right Upper Dormer Triangle',
        shape: 'dormer_peak',
        wall: 'front',
        story: 2,
        x_start: 0.56,
        x_end: 0.86,
        eave_height: 0.66,
        peak_height: 0.92,
        peak_offset: 0.50,
        depth_offset: -0.04,
        has_garage: false,
        has_door: false,
        window_style: 'arched',
      },
    ],
  },
};

export function normalizeSection(sec, idx = 0) {
  const shape = sec?.shape || 'triangle_gable';
  const story = Number(sec?.story) === 2 ? 2 : 1;
  const xStart = Math.max(0, Math.min(0.92, Number(sec?.x_start ?? 0.06)));
  const xEnd = Math.max(xStart + 0.08, Math.min(1.0, Number(sec?.x_end ?? 0.94)));
  const eaveH = Math.max(
    0.2,
    Math.min(0.95, Number(sec?.eave_height ?? (story === 2 ? 0.64 : 0.45)))
  );
  const defaultPeak = shape === 'flat_eave' ? eaveH : Math.min(1.0, eaveH + 0.36);
  const peakH =
    shape === 'flat_eave'
      ? eaveH
      : Math.max(eaveH, Math.min(1.0, Number(sec?.peak_height ?? defaultPeak)));
  return {
    id: sec?.id || `sec-${idx + 1}`,
    label: sec?.label || `Section ${idx + 1}`,
    shape,
    wall: ['front', 'left', 'right', 'back'].includes(sec?.wall) ? sec.wall : 'front',
    story,
    x_start: Number(xStart.toFixed(3)),
    x_end: Number(xEnd.toFixed(3)),
    eave_height: Number(eaveH.toFixed(3)),
    peak_height: Number(peakH.toFixed(3)),
    peak_offset: Math.max(0.15, Math.min(0.85, Number(sec?.peak_offset ?? 0.5))),
    depth_offset: Math.max(-0.4, Math.min(0.4, Number(sec?.depth_offset ?? 0.06))),
    has_garage: Boolean(sec?.has_garage),
    has_door: Boolean(sec?.has_door),
    window_style: sec?.window_style || 'mullion',
  };
}

/**
 * Resolves the effective architecture for a house, combining:
 * 1. User-saved localStorage overrides (if any)
 * 2. Backend `house.architecture` (if populated)
 * 3. Distinct multi-section defaults per house (`a_frame_gable`, `craftsman_multi_section`, `two_story_estate`)
 */
export function getEffectiveHouseArchitecture(house, houseIndex = 0) {
  const savedMap = loadSavedArchitectureOverrides();
  const localArch = savedMap[house?.id]?.architecture;

  const rawArch =
    localArch && Array.isArray(localArch.sections) && localArch.sections.length > 0
      ? localArch
      : house?.architecture &&
        Array.isArray(house.architecture.sections) &&
        house.architecture.sections.length > 0
      ? house.architecture
      : null;

  if (rawArch) {
    return {
      preset_style: rawArch.preset_style || 'custom',
      label: rawArch.label || 'Custom Architecture',
      sections: rawArch.sections.map((s, i) => normalizeSection(s, i)),
    };
  }

  // Fallback by house ID or street index
  const hId = (house?.id || '').toLowerCase();
  let presetKey = 'a_frame_gable';
  if (hId === 'house-1' || houseIndex === 0) {
    presetKey = 'a_frame_gable';
  } else if (hId === 'house-2' || houseIndex === 1) {
    presetKey = 'craftsman_multi_section';
  } else if (hId === 'house-3' || houseIndex === 2) {
    presetKey = 'two_story_estate';
  } else {
    const keys = Object.keys(ARCHITECTURAL_PRESETS);
    presetKey = keys[houseIndex % keys.length];
  }

  const preset = ARCHITECTURAL_PRESETS[presetKey] || ARCHITECTURAL_PRESETS.a_frame_gable;
  return {
    preset_style: preset.preset_style,
    label: preset.label,
    sections: preset.sections.map((s, i) => normalizeSection(s, i)),
  };
}

/**
 * Resolves `section_spans` and `custom_nodes` for a controller on a given house architecture.
 */
export function getEffectiveControllerSpans(controller, architecture, ctrlIndex = 0) {
  const segCount = Math.max(1, Number(controller?.segment_count || 9));
  const sections = architecture?.sections || [];
  const frontSections = sections.filter((s) => s.wall === 'front');
  const targetPool = frontSections.length > 0 ? frontSections : sections;

  const savedMap = loadSavedArchitectureOverrides();
  const savedCtrl =
    controller?.id &&
    Object.values(savedMap).find((h) => h?.controllers?.[controller.id])?.controllers?.[
      controller.id
    ];

  const rawSpans =
    (Array.isArray(savedCtrl?.section_spans) && savedCtrl.section_spans.length > 0
      ? savedCtrl.section_spans
      : null) ||
    (Array.isArray(controller?.section_spans) && controller.section_spans.length > 0
      ? controller.section_spans
      : null);

  if (rawSpans) {
    const validIds = new Set(sections.map((s) => s.id));
    const cleaned = rawSpans.map((sp, idx) => {
      const fallbackSec = targetPool[idx % Math.max(1, targetPool.length)] || sections[0];
      const matchedSec = validIds.has(sp.section_id)
        ? sections.find((s) => s.id === sp.section_id)
        : fallbackSec;
      return {
        section_id: matchedSec?.id || `sec-${idx + 1}`,
        wall: sp.wall || matchedSec?.wall || 'front',
        segments: Math.max(1, Number(sp.segments || segCount)),
        direction: sp.direction === 'rtl' ? 'rtl' : 'ltr',
      };
    });
    return cleaned;
  }

  // Smart default distribution across sections
  if (targetPool.length <= 1) {
    const sec = targetPool[0] || sections[0];
    return [
      {
        section_id: sec?.id || 'sec-front-gable',
        wall: sec?.wall || 'front',
        segments: segCount,
        direction: controller?.reverse_direction ? 'rtl' : 'ltr',
      },
    ];
  }

  // If house has multiple controllers, map each controller to distinct or shared sections
  if (ctrlIndex === 0) {
    // Distribute across primary front sections
    const chosen = targetPool.slice(0, Math.min(3, targetPool.length));
    const basePerSec = Math.floor(segCount / chosen.length);
    let remainder = segCount - basePerSec * chosen.length;
    return chosen.map((sec) => {
      const extra = remainder > 0 ? 1 : 0;
      if (remainder > 0) remainder -= 1;
      return {
        section_id: sec.id,
        wall: sec.wall || 'front',
        segments: Math.max(1, basePerSec + extra),
        direction: 'ltr',
      };
    });
  }

  // 2nd+ controller wraps upper dormer + side/rear sections
  const secondaryPool = sections.slice(Math.min(2, sections.length - 1));
  const chosen = secondaryPool.slice(0, Math.min(2, secondaryPool.length));
  const basePerSec = Math.floor(segCount / chosen.length);
  let remainder = segCount - basePerSec * chosen.length;
  return chosen.map((sec) => {
    const extra = remainder > 0 ? 1 : 0;
    if (remainder > 0) remainder -= 1;
    return {
      section_id: sec.id,
      wall: sec.wall || 'front',
      segments: Math.max(1, basePerSec + extra),
      direction: 'ltr',
    };
  });
}

export function getEffectiveCustomNodes(controller) {
  const savedMap = loadSavedArchitectureOverrides();
  const savedCtrl =
    controller?.id &&
    Object.values(savedMap).find((h) => h?.controllers?.[controller.id])?.controllers?.[
      controller.id
    ];
  const nodes = savedCtrl?.custom_nodes ?? controller?.custom_nodes;
  return Array.isArray(nodes) ? nodes : [];
}

function hexToRgb(hex, fallback = [0, 245, 212]) {
  if (!hex || typeof hex !== 'string') return fallback;
  const clean = hex.replace('#', '').trim();
  if (clean.length === 3) {
    return [
      parseInt(clean[0] + clean[0], 16) || 0,
      parseInt(clean[1] + clean[1], 16) || 0,
      parseInt(clean[2] + clean[2], 16) || 0,
    ];
  }
  if (clean.length >= 6) {
    return [
      parseInt(clean.slice(0, 2), 16) || 0,
      parseInt(clean.slice(2, 4), 16) || 0,
      parseInt(clean.slice(4, 6), 16) || 0,
    ];
  }
  return fallback;
}

function lerpRgb(c1, c2, t) {
  const u = Math.max(0, Math.min(1, t));
  return [
    Math.round(c1[0] + (c2[0] - c1[0]) * u),
    Math.round(c1[1] + (c2[1] - c1[1]) * u),
    Math.round(c1[2] + (c2[2] - c1[2]) * u),
  ];
}

/**
 * Computes a normalized 3D roofline contour for a section:
 * x in [-0.5 .. +0.5], y in [0 .. 1.0] (ground = 0), z in [-0.45 .. +0.45] (front > 0)
 */
export function getSectionRooflinePolyline3D(sec) {
  const x0 = sec.x_start - 0.5;
  const x1 = sec.x_end - 0.5;
  const xm = x0 + (x1 - x0) * (sec.peak_offset ?? 0.5);
  const eaveY = sec.eave_height;
  const peakY = sec.shape === 'flat_eave' ? eaveY : Math.max(eaveY, sec.peak_height);
  const baseFrontZ = 0.24 + (sec.depth_offset || 0) * 0.45;
  const baseBackZ = -0.24;

  if (sec.wall === 'left') {
    const zStart = 0.24 - sec.x_start * 0.48;
    const zEnd = 0.24 - sec.x_end * 0.48;
    const zMid = (zStart + zEnd) * 0.5;
    if (sec.shape === 'flat_eave') {
      return [
        { x: -0.46, y: eaveY, z: zStart },
        { x: -0.46, y: eaveY, z: zEnd },
      ];
    }
    return [
      { x: -0.46, y: eaveY, z: zStart },
      { x: -0.46, y: peakY, z: zMid },
      { x: -0.46, y: eaveY, z: zEnd },
    ];
  }

  if (sec.wall === 'right') {
    const zStart = 0.24 - sec.x_start * 0.48;
    const zEnd = 0.24 - sec.x_end * 0.48;
    const zMid = (zStart + zEnd) * 0.5;
    if (sec.shape === 'flat_eave') {
      return [
        { x: 0.46, y: eaveY, z: zStart },
        { x: 0.46, y: eaveY, z: zEnd },
      ];
    }
    return [
      { x: 0.46, y: eaveY, z: zStart },
      { x: 0.46, y: peakY, z: zMid },
      { x: 0.46, y: eaveY, z: zEnd },
    ];
  }

  if (sec.wall === 'back') {
    if (sec.shape === 'flat_eave') {
      return [
        { x: x0, y: eaveY, z: baseBackZ },
        { x: x1, y: eaveY, z: baseBackZ },
      ];
    }
    return [
      { x: x0, y: eaveY, z: baseBackZ },
      { x: xm, y: peakY, z: baseBackZ },
      { x: x1, y: eaveY, z: baseBackZ },
    ];
  }

  // Front wall shapes
  if (sec.shape === 'flat_eave') {
    return [
      { x: x0, y: eaveY, z: baseFrontZ + 0.025 },
      { x: x1, y: eaveY, z: baseFrontZ + 0.025 },
    ];
  }
  if (sec.shape === 'shed_slope') {
    const leftHigh = (sec.peak_offset ?? 0.5) < 0.5;
    return [
      { x: x0, y: leftHigh ? peakY : eaveY, z: baseFrontZ + 0.025 },
      { x: x1, y: leftHigh ? eaveY : peakY, z: baseFrontZ + 0.025 },
    ];
  }
  if (sec.shape === 'hip_roof') {
    const span = x1 - x0;
    const h0 = x0 + span * 0.22;
    const h1 = x1 - span * 0.22;
    return [
      { x: x0, y: eaveY, z: baseFrontZ + 0.025 },
      { x: h0, y: peakY, z: baseFrontZ + 0.01 },
      { x: h1, y: peakY, z: baseFrontZ + 0.01 },
      { x: x1, y: eaveY, z: baseFrontZ + 0.025 },
    ];
  }

  // triangle_gable, steep_gable, dormer_peak
  return [
    { x: x0, y: eaveY, z: baseFrontZ + 0.028 },
    { x: xm, y: peakY, z: baseFrontZ + 0.028 },
    { x: x1, y: eaveY, z: baseFrontZ + 0.028 },
  ];
}

function samplePointsAlong3DPolyline(polyline, count, reverse = false) {
  if (!polyline || polyline.length === 0) return [];
  if (polyline.length === 1 || count <= 1) {
    return [{ ...polyline[0], t: 0.5 }];
  }
  const pts = reverse ? [...polyline].reverse() : polyline;
  const lengths = [];
  let totalLen = 0;
  for (let i = 0; i < pts.length - 1; i += 1) {
    const dx = pts[i + 1].x - pts[i].x;
    const dy = pts[i + 1].y - pts[i].y;
    const dz = pts[i + 1].z - pts[i].z;
    const len = Math.hypot(dx, dy, dz) || 0.0001;
    lengths.push(len);
    totalLen += len;
  }

  const sampled = [];
  for (let i = 0; i < count; i += 1) {
    const u = count === 1 ? 0.5 : (i + 0.5) / count;
    const targetDist = u * totalLen;
    let acc = 0;
    let chosen = pts[pts.length - 1];
    for (let j = 0; j < lengths.length; j += 1) {
      if (acc + lengths[j] >= targetDist || j === lengths.length - 1) {
        const localT = Math.max(0, Math.min(1, (targetDist - acc) / lengths[j]));
        chosen = {
          x: pts[j].x + (pts[j + 1].x - pts[j].x) * localT,
          y: pts[j].y + (pts[j + 1].y - pts[j].y) * localT,
          z: pts[j].z + (pts[j + 1].z - pts[j].z) * localT,
          t: u,
        };
        break;
      }
      acc += lengths[j];
    }
    sampled.push(chosen);
  }
  return sampled;
}

/**
 * Builds the complete list of 3D/2D mapped LED pucks for a house across all its controllers.
 */
export function buildHousePucks3D(house, houseIndex, liveSegmentsMap, anim, phaseSec) {
  const arch = getEffectiveHouseArchitecture(house, houseIndex);
  const sections = arch.sections || [];
  const controllers = (house?.controllers || []).filter((c) => c.enabled !== false);
  const pucks = [];

  const primaryRgb = hexToRgb(anim?.primary_color || '#00f5d4');
  const secondaryRgb = hexToRgb(anim?.secondary_color || '#7b2cbf');
  const accentRgb = hexToRgb(anim?.accent_color || '#ff007f');
  const isRunning = anim?.running !== false;
  const blackout = Boolean(anim?.blackout_on_stop && !isRunning);

  let houseSegCursor = 0;
  const totalHouseSegs = Math.max(
    1,
    controllers.reduce((sum, c) => sum + Math.max(1, Number(c.segment_count || 9)), 0)
  );

  controllers.forEach((ctrl, cIdx) => {
    const customNodes = getEffectiveCustomNodes(ctrl);
    const totalCtrlSegs = Math.max(1, Number(ctrl.segment_count || 9));

    if (customNodes.length >= 2) {
      const poly3d = customNodes.map((n) => ({
        x: (Number(n.x ?? 0.5) - 0.5) * 0.92,
        y: Math.max(0.15, Math.min(0.98, Number(n.y ?? 0.6))),
        z: 0.26 + Number(n.z ?? 0) * 0.4,
      }));
      const pts = samplePointsAlong3DPolyline(
        poly3d,
        totalCtrlSegs,
        Boolean(ctrl.reverse_direction)
      );
      pts.forEach((pt, localIdx) => {
        const key = `${house.id}::${ctrl.id}::${localIdx}`;
        const liveSeg = liveSegmentsMap.get(key);
        let rgb = [0, 0, 0];
        if (!blackout) {
          if (liveSeg && typeof liveSeg.r === 'number') {
            rgb = [liveSeg.r, liveSeg.g, liveSeg.b];
          } else {
            const u = (houseSegCursor + localIdx) / totalHouseSegs;
            const wave =
              (u - phaseSec * (anim?.speed || 0.35) * 1.4 + houseIndex * 0.25 + 10) % 1;
            rgb =
              wave < 0.33
                ? lerpRgb(primaryRgb, secondaryRgb, wave / 0.33)
                : wave < 0.66
                ? lerpRgb(secondaryRgb, accentRgb, (wave - 0.33) / 0.33)
                : lerpRgb(accentRgb, primaryRgb, (wave - 0.66) / 0.34);
          }
        }
        pucks.push({
          id: key,
          houseId: house.id,
          houseName: house.name,
          controllerId: ctrl.id,
          controllerName: ctrl.name || `Controller ${cIdx + 1}`,
          localIndex: localIdx,
          houseSegIndex: houseSegCursor + localIdx,
          sectionId: 'custom_nodes',
          sectionLabel: 'Custom Polyline Path',
          wall: 'front',
          x: pt.x,
          y: pt.y,
          z: pt.z,
          rgb,
          hex: `rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})`,
        });
      });
      houseSegCursor += totalCtrlSegs;
      return;
    }

    const spans = getEffectiveControllerSpans(ctrl, arch, cIdx);
    let localCursor = 0;

    spans.forEach((sp) => {
      const sec =
        sections.find((s) => s.id === sp.section_id) ||
        sections.find((s) => s.wall === 'front') ||
        sections[0];
      if (!sec) return;
      const segsInSpan = Math.max(1, Number(sp.segments || 1));
      const poly3d = getSectionRooflinePolyline3D(sec);
      const pts = samplePointsAlong3DPolyline(poly3d, segsInSpan, sp.direction === 'rtl');

      pts.forEach((pt, idxInSpan) => {
        const localIdx = localCursor + idxInSpan;
        const key = `${house.id}::${ctrl.id}::${localIdx}`;
        const fallbackHouseKey = `${house.id}::idx::${houseSegCursor + localIdx}`;
        const liveSeg = liveSegmentsMap.get(key) || liveSegmentsMap.get(fallbackHouseKey);

        let rgb = [0, 0, 0];
        if (!blackout) {
          if (liveSeg && typeof liveSeg.r === 'number') {
            rgb = [liveSeg.r, liveSeg.g, liveSeg.b];
          } else {
            const u = (houseSegCursor + localIdx) / totalHouseSegs;
            const dirSign = anim?.direction === 'reverse' ? -1 : 1;
            const wave =
              ((u * dirSign - phaseSec * (anim?.speed || 0.35) * 1.35 + houseIndex * 0.28) % 1 +
                1) %
              1;
            rgb =
              wave < 0.35
                ? lerpRgb(primaryRgb, secondaryRgb, wave / 0.35)
                : wave < 0.7
                ? lerpRgb(secondaryRgb, accentRgb, (wave - 0.35) / 0.35)
                : lerpRgb(accentRgb, primaryRgb, (wave - 0.7) / 0.3);
          }
        }

        pucks.push({
          id: key,
          houseId: house.id,
          houseName: house.name,
          controllerId: ctrl.id,
          controllerName: ctrl.name || `Controller ${cIdx + 1}`,
          localIndex: localIdx,
          houseSegIndex: houseSegCursor + localIdx,
          sectionId: sec.id,
          sectionLabel: sec.label,
          wall: sec.wall || 'front',
          x: pt.x,
          y: pt.y,
          z: pt.z,
          rgb,
          hex: `rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})`,
        });
      });

      localCursor += segsInSpan;
    });

    houseSegCursor += localCursor;
  });

  return pucks;
}

/**
 * Shared Interactive 3D & 2D Multi-Section Architectural Renderer Canvas.
 * Supports:
 * - "3d_all": Multi-house 3D street perspective with camera orbit (yaw, pitch, zoom)
 * - "3d_house:<id>" / "3d": Single house 3D architectural studio with orbit + section/puck selection + draggable handles
 * - "2d": 2D Front Elevation blueprint with multi-section gables, square garages, dormers, soffit cones & draggable CAD handles
 */
export function ArchitecturalViewportCanvas({
  houses = [],
  liveSegments = [],
  animation = {},
  previewMode = '3d_all',
  selectedHouseId = null,
  selectedSectionId = null,
  selectedPuckId = null,
  onSelectHouse = null,
  onSelectSection = null,
  onSelectPuck = null,
  editableHandles = false,
  customNodeDrawMode = false,
  activeControllerForNodes = null,
  onUpdateSectionGeometry = null,
  onAppendCustomNode = null,
  onUpdateCustomNode = null,
  height = 310,
  showCameraControls = true,
  onOpenDesigner = null,
}) {
  const canvasRef = useRef(null);
  const hitRegionsRef = useRef({ pucks: [], handles: [], sections: [], houses: [] });
  const dragStateRef = useRef(null);

  const [camera, setCamera] = useState({
    yaw: -18,
    pitch: 21,
    zoom: 1.04,
  });
  const [hoveredItem, setHoveredItem] = useState(null);

  const is2D = previewMode === '2d';
  const singleHouseId = useMemo(() => {
    if (previewMode?.startsWith('3d_house:')) return previewMode.split(':')[1];
    if (previewMode?.startsWith('3d:')) return previewMode.split(':')[1];
    if (selectedHouseId && previewMode === '3d_single') return selectedHouseId;
    return null;
  }, [previewMode, selectedHouseId]);

  const displayedHouses = useMemo(() => {
    if (singleHouseId) {
      const found = houses.find((h) => h.id === singleHouseId);
      return found ? [found] : houses.slice(0, 1);
    }
    const enabled = houses.filter((h) => h.enabled !== false);
    return enabled.length > 0 ? enabled : houses;
  }, [houses, singleHouseId]);

  const liveSegmentsMap = useMemo(() => {
    const map = new Map();
    const perHouseCounters = {};
    (liveSegments || []).forEach((seg) => {
      if (seg.house_id && seg.controller_id !== undefined && seg.local_segment_index !== undefined) {
        map.set(`${seg.house_id}::${seg.controller_id}::${seg.local_segment_index}`, seg);
      }
      if (seg.house_id) {
        const idx = perHouseCounters[seg.house_id] || 0;
        map.set(`${seg.house_id}::idx::${idx}`, seg);
        perHouseCounters[seg.house_id] = idx + 1;
      }
    });
    return map;
  }, [liveSegments]);

  const applyCameraPreset = useCallback((preset) => {
    if (preset === 'street') setCamera({ yaw: -18, pitch: 21, zoom: 1.04 });
    else if (preset === 'left45') setCamera({ yaw: -42, pitch: 24, zoom: 1.08 });
    else if (preset === 'right45') setCamera({ yaw: 38, pitch: 24, zoom: 1.08 });
    else if (preset === 'aerial') setCamera({ yaw: -12, pitch: 52, zoom: 1.02 });
    else setCamera({ yaw: 0, pitch: 16, zoom: 1.05 });
  }, []);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    let rafId;
    let startTs = performance.now();

    const renderFrame = (now) => {
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      const rect = canvas.getBoundingClientRect();
      const W = Math.max(300, rect.width || 720);
      const H = Math.max(200, rect.height || height);
      if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
        canvas.width = Math.round(W * dpr);
        canvas.height = Math.round(H * dpr);
      }
      const ctx = canvas.getContext('2d');
      ctx.save();
      ctx.scale(dpr, dpr);

      const phaseSec = (now - startTs) / 1000;
      const newHits = { pucks: [], handles: [], sections: [], houses: [] };

      // 1. Deep Architectural Night Sky & Horizon Backdrop
      const skyGrad = ctx.createLinearGradient(0, 0, 0, H);
      skyGrad.addColorStop(0, '#030613');
      skyGrad.addColorStop(0.58, '#081229');
      skyGrad.addColorStop(0.82, '#0d1b38');
      skyGrad.addColorStop(1, '#050a15');
      ctx.fillStyle = skyGrad;
      ctx.fillRect(0, 0, W, H);

      // Subtle stars & blueprint grid
      ctx.strokeStyle = is2D ? 'rgba(56, 189, 248, 0.08)' : 'rgba(148, 163, 184, 0.04)';
      ctx.lineWidth = 1;
      const gridStep = is2D ? 28 : 40;
      for (let gx = 0; gx < W; gx += gridStep) {
        ctx.beginPath();
        ctx.moveTo(gx, 0);
        ctx.lineTo(gx, H);
        ctx.stroke();
      }
      for (let gy = 0; gy < H; gy += gridStep) {
        ctx.beginPath();
        ctx.moveTo(0, gy);
        ctx.lineTo(W, gy);
        ctx.stroke();
      }

      const numHouses = Math.max(1, displayedHouses.length);
      const yawRad = is2D ? 0 : (camera.yaw * Math.PI) / 180;
      const pitchRad = is2D ? 0 : (camera.pitch * Math.PI) / 180;
      const cosY = Math.cos(yawRad);
      const sinY = Math.sin(yawRad);
      const cosP = Math.cos(pitchRad);
      const sinP = Math.sin(pitchRad);

      const streetWidthWorld = numHouses === 1 ? 1.35 : numHouses * 1.22;
      const baseScale =
        (Math.min(W / streetWidthWorld, H * 1.18) * (is2D ? 0.92 : camera.zoom)) /
        (numHouses === 1 ? 1.15 : 0.95);
      const centerX = W * 0.5;
      const groundOriginY = H * (is2D ? 0.79 : 0.74);

      const project3D = (wx, wy, wz) => {
        if (is2D) {
          return {
            x: centerX + wx * baseScale,
            y: groundOriginY - wy * baseScale * 0.78,
            depth: wz,
            scale: baseScale,
          };
        }
        const rx = wx * cosY + wz * sinY;
        const rz = -wx * sinY + wz * cosY;
        const ry = wy * cosP - rz * sinP;
        const depthZ = wy * sinP + rz * cosP;
        const persp = 1 / Math.max(0.55, 1 - depthZ * 0.14);
        return {
          x: centerX + rx * baseScale * persp,
          y: groundOriginY - ry * baseScale * 0.78 * persp,
          depth: depthZ,
          scale: baseScale * persp,
        };
      };

      // 2. Draw 3D Street / Ground Plane & Sidewalk
      const halfSpanW = streetWidthWorld * 0.55;
      const lawnPoly = [
        project3D(-halfSpanW, 0, -0.52),
        project3D(halfSpanW, 0, -0.52),
        project3D(halfSpanW, 0, 0.56),
        project3D(-halfSpanW, 0, 0.56),
      ];
      ctx.beginPath();
      lawnPoly.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
      ctx.closePath();
      const lawnGrad = ctx.createLinearGradient(0, groundOriginY - 60, 0, H);
      lawnGrad.addColorStop(0, '#091826');
      lawnGrad.addColorStop(1, '#050d17');
      ctx.fillStyle = lawnGrad;
      ctx.fill();
      ctx.strokeStyle = 'rgba(0, 245, 212, 0.16)';
      ctx.lineWidth = 1;
      ctx.stroke();

      // Asphalt Street in front of houses (3D mode)
      if (!is2D) {
        const roadPoly = [
          project3D(-halfSpanW, 0, 0.42),
          project3D(halfSpanW, 0, 0.42),
          project3D(halfSpanW, 0, 0.64),
          project3D(-halfSpanW, 0, 0.64),
        ];
        ctx.beginPath();
        roadPoly.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
        ctx.closePath();
        ctx.fillStyle = '#070b14';
        ctx.fill();
        ctx.strokeStyle = 'rgba(148, 163, 184, 0.18)';
        ctx.stroke();

        // Dashed street centerline
        const rLeft = project3D(-halfSpanW * 0.9, 0.002, 0.53);
        const rRight = project3D(halfSpanW * 0.9, 0.002, 0.53);
        ctx.save();
        ctx.setLineDash([8, 8]);
        ctx.strokeStyle = 'rgba(251, 191, 36, 0.35)';
        ctx.lineWidth = 1.3;
        ctx.beginPath();
        ctx.moveTo(rLeft.x, rLeft.y);
        ctx.lineTo(rRight.x, rRight.y);
        ctx.stroke();
        ctx.restore();
      }

      // 3. Collect 3D Faces & Roofline Pucks across all displayed houses
      const polygons = [];
      const houseRenderItems = [];

      displayedHouses.forEach((house, idx) => {
        const fullIdx = houses.findIndex((h) => h.id === house.id);
        const effectiveIdx = fullIdx >= 0 ? fullIdx : idx;
        const houseCenterX =
          numHouses === 1 ? 0 : (idx - (numHouses - 1) / 2) * 1.18;
        const arch = getEffectiveHouseArchitecture(house, effectiveIdx);
        const sections = arch.sections || [];
        const pucks = buildHousePucks3D(
          house,
          effectiveIdx,
          liveSegmentsMap,
          animation,
          phaseSec
        );

        houseRenderItems.push({
          house,
          effectiveIdx,
          houseCenterX,
          arch,
          sections,
          pucks,
        });

        // Base core house volume (so side/rear walls always form a cohesive 3D building)
        const frontSecs = sections.filter((s) => s.wall === 'front');
        const targetFrontSecs =
          frontSecs.length > 0
            ? frontSecs
            : [
                normalizeSection({
                  id: 'fallback-front',
                  shape: 'triangle_gable',
                  wall: 'front',
                }),
              ];

        targetFrontSecs.forEach((sec) => {
          const isSecSelected = selectedSectionId === sec.id;
          const x0 = houseCenterX + (sec.x_start - 0.5);
          const x1 = houseCenterX + (sec.x_end - 0.5);
          const xm = x0 + (x1 - x0) * (sec.peak_offset ?? 0.5);
          const baseY = sec.story === 2 && sec.shape === 'dormer_peak' ? sec.eave_height * 0.68 : 0;
          const eaveY = sec.eave_height;
          const peakY = sec.shape === 'flat_eave' ? eaveY : Math.max(eaveY, sec.peak_height);
          const zFront = 0.24 + (sec.depth_offset || 0) * 0.45;
          const zBack = sec.story === 2 && sec.shape === 'dormer_peak' ? -0.02 : -0.24;

          // Driveway apron for garage sections
          if (sec.has_garage && !is2D) {
            polygons.push({
              type: 'driveway',
              pts3d: [
                { x: x0 + 0.02, y: 0.002, z: zFront },
                { x: x1 - 0.02, y: 0.002, z: zFront },
                { x: x1 - 0.01, y: 0.002, z: 0.42 },
                { x: x0 + 0.01, y: 0.002, z: 0.42 },
              ],
              fill: '#111927',
              stroke: 'rgba(148, 163, 184, 0.22)',
              depthBias: -0.3,
            });
          }

          // Front walkway for door sections
          if (sec.has_door && !is2D) {
            const doorX = (x0 + x1) * 0.5;
            polygons.push({
              type: 'walkway',
              pts3d: [
                { x: doorX - 0.055, y: 0.003, z: zFront },
                { x: doorX + 0.055, y: 0.003, z: zFront },
                { x: doorX + 0.045, y: 0.003, z: 0.42 },
                { x: doorX - 0.045, y: 0.003, z: 0.42 },
              ],
              fill: '#172234',
              stroke: 'rgba(148, 163, 184, 0.2)',
              depthBias: -0.28,
            });
          }

          // Left & Right 3D extruded side walls of this section
          if (!is2D) {
            polygons.push({
              type: 'wall_side',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0, y: baseY, z: zBack },
                { x: x0, y: baseY, z: zFront },
                { x: x0, y: eaveY, z: zFront },
                { x: x0, y: eaveY, z: zBack },
              ],
              fill: '#0f192d',
              stroke: isSecSelected ? '#00f5d4' : '#26354d',
              depthBias: -0.02,
            });

            polygons.push({
              type: 'wall_side',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x1, y: baseY, z: zFront },
                { x: x1, y: baseY, z: zBack },
                { x: x1, y: eaveY, z: zBack },
                { x: x1, y: eaveY, z: zFront },
              ],
              fill: '#111d33',
              stroke: isSecSelected ? '#00f5d4' : '#26354d',
              depthBias: -0.02,
            });

            // Back wall of section
            polygons.push({
              type: 'wall_back',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0, y: baseY, z: zBack },
                { x: x1, y: baseY, z: zBack },
                { x: x1, y: eaveY, z: zBack },
                { x: x0, y: eaveY, z: zBack },
              ],
              fill: '#0b1322',
              stroke: '#1e293b',
              depthBias: -0.08,
            });
          }

          // Front facade polygon (includes triangle gable peak or shed slope top!)
          let frontFacePts = [];
          if (
            sec.shape === 'triangle_gable' ||
            sec.shape === 'steep_gable' ||
            sec.shape === 'dormer_peak'
          ) {
            frontFacePts = [
              { x: x0, y: baseY, z: zFront },
              { x: x1, y: baseY, z: zFront },
              { x: x1, y: eaveY, z: zFront },
              { x: xm, y: peakY, z: zFront },
              { x: x0, y: eaveY, z: zFront },
            ];
          } else if (sec.shape === 'shed_slope') {
            const leftHigh = (sec.peak_offset ?? 0.5) < 0.5;
            frontFacePts = [
              { x: x0, y: baseY, z: zFront },
              { x: x1, y: baseY, z: zFront },
              { x: x1, y: leftHigh ? eaveY : peakY, z: zFront },
              { x: x0, y: leftHigh ? peakY : eaveY, z: zFront },
            ];
          } else {
            frontFacePts = [
              { x: x0, y: baseY, z: zFront },
              { x: x1, y: baseY, z: zFront },
              { x: x1, y: eaveY, z: zFront },
              { x: x0, y: eaveY, z: zFront },
            ];
          }

          polygons.push({
            type: 'wall_front',
            sec,
            secId: sec.id,
            houseId: house.id,
            x0,
            x1,
            xm,
            baseY,
            eaveY,
            peakY,
            zFront,
            pts3d: frontFacePts,
            fill:
              sec.story === 2
                ? '#182642'
                : sec.has_garage
                ? '#15223a'
                : '#16243d',
            stroke: isSecSelected ? '#00f5d4' : '#334868',
            depthBias: 0.04,
          });

          // 3D Roof Planes
          const overhang = 0.025;
          if (
            sec.shape === 'triangle_gable' ||
            sec.shape === 'steep_gable' ||
            sec.shape === 'dormer_peak'
          ) {
            // Left pitched roof slope
            polygons.push({
              type: 'roof_slope',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0 - overhang, y: eaveY, z: zFront + overhang },
                { x: xm, y: peakY, z: zFront + overhang },
                { x: xm, y: peakY, z: zBack - overhang * 0.5 },
                { x: x0 - overhang, y: eaveY, z: zBack - overhang * 0.5 },
              ],
              fill: '#1e2d4a',
              stroke: isSecSelected ? '#00f5d4' : '#3b5278',
              depthBias: 0.03,
            });
            // Right pitched roof slope
            polygons.push({
              type: 'roof_slope',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: xm, y: peakY, z: zFront + overhang },
                { x: x1 + overhang, y: eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: eaveY, z: zBack - overhang * 0.5 },
                { x: xm, y: peakY, z: zBack - overhang * 0.5 },
              ],
              fill: '#243657',
              stroke: isSecSelected ? '#00f5d4' : '#3b5278',
              depthBias: 0.03,
            });
          } else if (sec.shape === 'hip_roof') {
            const span = x1 - x0;
            const h0 = x0 + span * 0.22;
            const h1 = x1 - span * 0.22;
            const zRidge = (zFront + zBack) * 0.5;
            // Front trapezoid hip slope
            polygons.push({
              type: 'roof_slope',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0 - overhang, y: eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: eaveY, z: zFront + overhang },
                { x: h1, y: peakY, z: zRidge },
                { x: h0, y: peakY, z: zRidge },
              ],
              fill: '#223352',
              stroke: isSecSelected ? '#00f5d4' : '#3b5278',
              depthBias: 0.04,
            });
            // Left & right hip ends
            polygons.push({
              type: 'roof_slope',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0 - overhang, y: eaveY, z: zBack },
                { x: x0 - overhang, y: eaveY, z: zFront + overhang },
                { x: h0, y: peakY, z: zRidge },
              ],
              fill: '#1b2a44',
              stroke: '#334868',
              depthBias: 0.02,
            });
            polygons.push({
              type: 'roof_slope',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x1 + overhang, y: eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: eaveY, z: zBack },
                { x: h1, y: peakY, z: zRidge },
              ],
              fill: '#1b2a44',
              stroke: '#334868',
              depthBias: 0.02,
            });
          } else if (sec.shape === 'shed_slope') {
            const leftHigh = (sec.peak_offset ?? 0.5) < 0.5;
            polygons.push({
              type: 'roof_slope',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0 - overhang, y: leftHigh ? peakY : eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: leftHigh ? eaveY : peakY, z: zFront + overhang },
                { x: x1 + overhang, y: leftHigh ? eaveY : peakY, z: zBack },
                { x: x0 - overhang, y: leftHigh ? peakY : eaveY, z: zBack },
              ],
              fill: '#213252',
              stroke: isSecSelected ? '#00f5d4' : '#3b5278',
              depthBias: 0.03,
            });
          } else {
            // Flat / Square eave roof deck & fascia trim
            polygons.push({
              type: 'roof_flat',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0 - overhang, y: eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: eaveY, z: zBack - overhang * 0.5 },
                { x: x0 - overhang, y: eaveY, z: zBack - overhang * 0.5 },
              ],
              fill: '#1b2942',
              stroke: isSecSelected ? '#00f5d4' : '#384e73',
              depthBias: 0.03,
            });
          }
        });
      });

      // Sort 3D polygons back-to-front (Painter's algorithm)
      const projectedPolys = polygons
        .map((poly) => {
          const pts2d = poly.pts3d.map((p) => project3D(p.x, p.y, p.z));
          const avgDepth =
            pts2d.reduce((sum, p) => sum + p.depth, 0) / pts2d.length +
            (poly.depthBias || 0);
          return { ...poly, pts2d, avgDepth };
        })
        .sort((a, b) => a.avgDepth - b.avgDepth);

      // Render sorted 3D architectural polygons + facade doors/windows/garages
      projectedPolys.forEach((poly) => {
        ctx.beginPath();
        poly.pts2d.forEach((p, i) =>
          i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)
        );
        ctx.closePath();
        ctx.fillStyle = poly.fill;
        ctx.fill();
        ctx.strokeStyle = poly.stroke;
        ctx.lineWidth = poly.secId && poly.secId === selectedSectionId ? 2.2 : 1.2;
        ctx.stroke();

        if (poly.type === 'wall_front' && poly.sec) {
          newHits.sections.push({
            secId: poly.sec.id,
            houseId: poly.houseId,
            label: poly.sec.label,
            pts2d: poly.pts2d,
          });

          const sec = poly.sec;
          const spanW = poly.x1 - poly.x0;
          const wallH = poly.eaveY - poly.baseY;
          const zF = poly.zFront + 0.003;

          // Draw Gable Vent near triangle apex
          if (
            (sec.shape === 'triangle_gable' ||
              sec.shape === 'steep_gable' ||
              sec.shape === 'dormer_peak') &&
            poly.peakY - poly.eaveY > 0.14
          ) {
            const ventY = poly.eaveY + (poly.peakY - poly.eaveY) * 0.58;
            const vp = project3D(poly.xm, ventY, zF);
            const r = Math.max(4, vp.scale * 0.032);
            ctx.beginPath();
            ctx.arc(vp.x, vp.y, r, 0, Math.PI * 2);
            ctx.fillStyle = '#0b1324';
            ctx.fill();
            ctx.strokeStyle = 'rgba(251, 191, 36, 0.55)';
            ctx.lineWidth = 1.1;
            ctx.stroke();
          }

          // Draw Paneled Garage Door if has_garage
          if (sec.has_garage && sec.story === 1) {
            const gx0 = poly.x0 + spanW * 0.12;
            const gx1 = poly.x1 - spanW * 0.12;
            const gy1 = poly.baseY + wallH * 0.78;
            const gCorners = [
              project3D(gx0, poly.baseY, zF),
              project3D(gx1, poly.baseY, zF),
              project3D(gx1, gy1, zF),
              project3D(gx0, gy1, zF),
            ];
            ctx.beginPath();
            gCorners.forEach((p, i) =>
              i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)
            );
            ctx.closePath();
            ctx.fillStyle = '#0c1526';
            ctx.fill();
            ctx.strokeStyle = '#475569';
            ctx.lineWidth = 1.3;
            ctx.stroke();

            // Horizontal garage door panels + top glass lites
            for (let row = 1; row <= 3; row += 1) {
              const py = poly.baseY + (gy1 - poly.baseY) * (row / 4);
              const pl = project3D(gx0, py, zF);
              const pr = project3D(gx1, py, zF);
              ctx.beginPath();
              ctx.moveTo(pl.x, pl.y);
              ctx.lineTo(pr.x, pr.y);
              ctx.strokeStyle = 'rgba(100, 116, 139, 0.45)';
              ctx.lineWidth = 1;
              ctx.stroke();
            }
            // Top garage glass lites
            for (let pane = 0; pane < 4; pane += 1) {
              const px0 = gx0 + (gx1 - gx0) * ((pane + 0.1) / 4);
              const px1 = gx0 + (gx1 - gx0) * ((pane + 0.9) / 4);
              const py0 = poly.baseY + (gy1 - poly.baseY) * 0.78;
              const py1 = gy1 - 0.02;
              const wc = [
                project3D(px0, py0, zF),
                project3D(px1, py0, zF),
                project3D(px1, py1, zF),
                project3D(px0, py1, zF),
              ];
              ctx.beginPath();
              wc.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
              ctx.closePath();
              ctx.fillStyle = 'rgba(251, 191, 36, 0.35)';
              ctx.fill();
            }
          }

          // Draw Warm-Lit Entry Door if has_door
          if (sec.has_door && sec.story === 1) {
            const dCenter = poly.x0 + spanW * (sec.has_garage ? 0.82 : 0.32);
            const dw = Math.min(0.09, spanW * 0.18);
            const dh = wallH * 0.68;
            const dCorners = [
              project3D(dCenter - dw * 0.5, poly.baseY, zF),
              project3D(dCenter + dw * 0.5, poly.baseY, zF),
              project3D(dCenter + dw * 0.5, poly.baseY + dh, zF),
              project3D(dCenter - dw * 0.5, poly.baseY + dh, zF),
            ];
            ctx.beginPath();
            dCorners.forEach((p, i) =>
              i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)
            );
            ctx.closePath();
            ctx.fillStyle = '#451a03';
            ctx.fill();
            ctx.strokeStyle = '#fbbf24';
            ctx.lineWidth = 1.2;
            ctx.stroke();

            // Door glass oval
            const dg = project3D(dCenter, poly.baseY + dh * 0.65, zF);
            ctx.beginPath();
            ctx.arc(dg.x, dg.y, Math.max(2.5, dg.scale * 0.018), 0, Math.PI * 2);
            ctx.fillStyle = 'rgba(253, 224, 71, 0.75)';
            ctx.fill();
          }

          // Draw Glowing Architectural Windows if window_style !== 'none'
          if (sec.window_style !== 'none' && !sec.has_garage) {
            const winCenter =
              sec.has_door && sec.story === 1
                ? poly.x0 + spanW * 0.68
                : (poly.x0 + poly.x1) * 0.5;
            const ww = Math.min(0.16, spanW * 0.36);
            const wy0 = poly.baseY + wallH * 0.28;
            const wy1 = poly.baseY + wallH * 0.74;
            const wCorners = [
              project3D(winCenter - ww * 0.5, wy0, zF),
              project3D(winCenter + ww * 0.5, wy0, zF),
              project3D(winCenter + ww * 0.5, wy1, zF),
              project3D(winCenter - ww * 0.5, wy1, zF),
            ];
            ctx.beginPath();
            wCorners.forEach((p, i) =>
              i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)
            );
            ctx.closePath();
            ctx.fillStyle = 'rgba(251, 191, 36, 0.24)';
            ctx.fill();
            ctx.strokeStyle = 'rgba(253, 224, 71, 0.65)';
            ctx.lineWidth = 1.2;
            ctx.stroke();

            if (sec.window_style === 'mullion') {
              const vm0 = project3D(winCenter, wy0, zF);
              const vm1 = project3D(winCenter, wy1, zF);
              const hm0 = project3D(winCenter - ww * 0.5, (wy0 + wy1) * 0.5, zF);
              const hm1 = project3D(winCenter + ww * 0.5, (wy0 + wy1) * 0.5, zF);
              ctx.beginPath();
              ctx.moveTo(vm0.x, vm0.y);
              ctx.lineTo(vm1.x, vm1.y);
              ctx.moveTo(hm0.x, hm0.y);
              ctx.lineTo(hm1.x, hm1.y);
              ctx.strokeStyle = 'rgba(253, 224, 71, 0.55)';
              ctx.lineWidth = 1;
              ctx.stroke();
            }
          }
        }
      });

      // 4. Render Soffit Downward Wall-Wash Cones, Roofline Tracks, LED Pucks & Labels
      houseRenderItems.forEach((item) => {
        const { house, effectiveIdx, houseCenterX, arch, sections, pucks } = item;

        // Draw roofline strip wire path per section
        sections.forEach((sec) => {
          const poly3d = getSectionRooflinePolyline3D(sec).map((pt) => ({
            x: houseCenterX + pt.x,
            y: pt.y,
            z: pt.z,
          }));
          const pts2d = poly3d.map((p) => project3D(p.x, p.y, p.z));
          ctx.beginPath();
          pts2d.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
          ctx.strokeStyle =
            selectedSectionId === sec.id
              ? 'rgba(0, 245, 212, 0.85)'
              : 'rgba(148, 163, 184, 0.42)';
          ctx.lineWidth = selectedSectionId === sec.id ? 3 : 1.8;
          ctx.stroke();
        });

        // Draw each LED Puck + Downward Soffit Wall-Wash Cone + Ground Reflection
        pucks.forEach((puck) => {
          const wx = houseCenterX + puck.x;
          const wy = puck.y;
          const wz = puck.z;
          const pTop = project3D(wx, wy, wz);
          const pWallBottom = project3D(wx, Math.max(0.04, wy - 0.34), wz - 0.015);
          const [r, g, b] = puck.rgb;
          const isLit = r + g + b > 12;
          const isSelected = selectedPuckId === puck.id;
          const isHovered = hoveredItem?.type === 'puck' && hoveredItem?.id === puck.id;

          if (isLit) {
            // Downward Soffit Wall-Wash Cone
            const coneSpread = Math.max(7, pTop.scale * 0.055);
            const coneGrad = ctx.createLinearGradient(
              pTop.x,
              pTop.y,
              pWallBottom.x,
              pWallBottom.y
            );
            coneGrad.addColorStop(0, `rgba(${r}, ${g}, ${b}, 0.58)`);
            coneGrad.addColorStop(0.55, `rgba(${r}, ${g}, ${b}, 0.18)`);
            coneGrad.addColorStop(1, `rgba(${r}, ${g}, ${b}, 0.0)`);

            ctx.beginPath();
            ctx.moveTo(pTop.x, pTop.y);
            ctx.lineTo(pWallBottom.x - coneSpread, pWallBottom.y);
            ctx.lineTo(pWallBottom.x + coneSpread, pWallBottom.y);
            ctx.closePath();
            ctx.fillStyle = coneGrad;
            ctx.fill();

            // Outer Puck Bloom Halo
            const haloRadius = Math.max(7, pTop.scale * 0.048);
            const haloGrad = ctx.createRadialGradient(
              pTop.x,
              pTop.y,
              1,
              pTop.x,
              pTop.y,
              haloRadius
            );
            haloGrad.addColorStop(0, `rgba(${r}, ${g}, ${b}, 0.95)`);
            haloGrad.addColorStop(0.45, `rgba(${r}, ${g}, ${b}, 0.42)`);
            haloGrad.addColorStop(1, `rgba(${r}, ${g}, ${b}, 0.0)`);
            ctx.beginPath();
            ctx.arc(pTop.x, pTop.y, haloRadius, 0, Math.PI * 2);
            ctx.fillStyle = haloGrad;
            ctx.fill();
          }

          // Crisp LED Puck Core
          const puckRadius = isSelected || isHovered ? 5.6 : Math.max(3.2, pTop.scale * 0.018);
          ctx.beginPath();
          ctx.arc(pTop.x, pTop.y, puckRadius, 0, Math.PI * 2);
          ctx.fillStyle = isLit ? `rgb(${r}, ${g}, ${b})` : '#1e293b';
          ctx.fill();
          ctx.strokeStyle = isSelected
            ? '#ffffff'
            : isLit
            ? 'rgba(255,255,255,0.85)'
            : '#475569';
          ctx.lineWidth = isSelected ? 2.2 : 1;
          ctx.stroke();

          if (isSelected) {
            ctx.beginPath();
            ctx.arc(pTop.x, pTop.y, puckRadius + 4.5, 0, Math.PI * 2);
            ctx.strokeStyle = '#00f5d4';
            ctx.lineWidth = 1.8;
            ctx.stroke();
          }

          newHits.pucks.push({
            ...puck,
            screenX: pTop.x,
            screenY: pTop.y,
            radius: Math.max(10, puckRadius + 5),
          });
        });

        // Draggable CAD / 3D Roofline Handles when in Designer mode
        if (editableHandles && (numHouses === 1 || selectedHouseId === house.id)) {
          sections
            .filter((s) => s.wall === 'front')
            .forEach((sec) => {
              const x0 = houseCenterX + (sec.x_start - 0.5);
              const x1 = houseCenterX + (sec.x_end - 0.5);
              const xm = x0 + (x1 - x0) * (sec.peak_offset ?? 0.5);
              const zF = 0.24 + (sec.depth_offset || 0) * 0.45 + 0.03;

              const hLeft = project3D(x0, sec.eave_height, zF);
              const hRight = project3D(x1, sec.eave_height, zF);
              const hPeak = project3D(
                xm,
                sec.shape === 'flat_eave' ? sec.eave_height : sec.peak_height,
                zF
              );

              const handleList = [
                {
                  kind: 'left_eave',
                  secId: sec.id,
                  houseId: house.id,
                  houseCenterX,
                  x: hLeft.x,
                  y: hLeft.y,
                  scale: hLeft.scale,
                  color: '#38bdf8',
                  label: `${sec.label}: Left Eave`,
                },
                {
                  kind: 'right_eave',
                  secId: sec.id,
                  houseId: house.id,
                  houseCenterX,
                  x: hRight.x,
                  y: hRight.y,
                  scale: hRight.scale,
                  color: '#38bdf8',
                  label: `${sec.label}: Right Eave`,
                },
              ];

              if (sec.shape !== 'flat_eave') {
                handleList.push({
                  kind: 'peak_apex',
                  secId: sec.id,
                  houseId: house.id,
                  houseCenterX,
                  x: hPeak.x,
                  y: hPeak.y,
                  scale: hPeak.scale,
                  color: '#fbbf24',
                  label: `${sec.label}: Triangle Apex`,
                });
              }

              handleList.forEach((h) => {
                ctx.save();
                ctx.beginPath();
                ctx.arc(h.x, h.y, 6.5, 0, Math.PI * 2);
                ctx.fillStyle = '#040711';
                ctx.fill();
                ctx.lineWidth = 2.2;
                ctx.strokeStyle = h.color;
                ctx.stroke();

                ctx.beginPath();
                ctx.arc(h.x, h.y, 2.6, 0, Math.PI * 2);
                ctx.fillStyle = h.color;
                ctx.fill();
                ctx.restore();

                newHits.handles.push({ ...h, radius: 13 });
              });
            });
        }

        // House Nameplate Badge under each house
        const badgePos = project3D(houseCenterX, -0.06, 0.36);
        const shortName = (house.name || `House ${effectiveIdx + 1}`).split('(')[0].trim();
        const archSummary =
          sections
            .filter((s) => s.wall === 'front')
            .map((s) =>
              s.shape === 'flat_eave'
                ? '⬛ Square'
                : s.shape === 'dormer_peak'
                ? '🏠 Dormer'
                : '🔺 Triangle'
            )
            .join(' + ') || '🔺 Triangle';

        const badgeText = `#${effectiveIdx + 1} ${shortName} (${pucks.length} segs)`;
        ctx.font = '700 11px Inter, system-ui, sans-serif';
        const tw = ctx.measureText(badgeText).width;
        const bw = Math.max(tw + 18, 128);
        const bh = 32;
        const bx = badgePos.x - bw * 0.5;
        const by = Math.min(H - bh - 4, Math.max(12, badgePos.y - 6));

        ctx.fillStyle =
          selectedHouseId === house.id
            ? 'rgba(0, 245, 212, 0.18)'
            : 'rgba(6, 11, 24, 0.88)';
        ctx.strokeStyle =
          selectedHouseId === house.id
            ? '#00f5d4'
            : 'rgba(56, 189, 248, 0.35)';
        ctx.lineWidth = 1.2;
        ctx.beginPath();
        ctx.roundRect(bx, by, bw, bh, 8);
        ctx.fill();
        ctx.stroke();

        ctx.fillStyle = '#f8fafc';
        ctx.textAlign = 'center';
        ctx.fillText(badgeText, badgePos.x, by + 13);

        ctx.font = '600 9.5px JetBrains Mono, monospace';
        ctx.fillStyle = '#67e8f9';
        ctx.fillText(archSummary, badgePos.x, by + 25);

        newHits.houses.push({
          houseId: house.id,
          x: bx,
          y: by,
          w: bw,
          h: bh,
        });
      });

      hitRegionsRef.current = newHits;
      ctx.restore();
      rafId = requestAnimationFrame(renderFrame);
    };

    rafId = requestAnimationFrame(renderFrame);
    return () => cancelAnimationFrame(rafId);
  }, [
    displayedHouses,
    houses,
    liveSegmentsMap,
    animation,
    camera,
    is2D,
    height,
    selectedHouseId,
    selectedSectionId,
    selectedPuckId,
    editableHandles,
    hoveredItem,
  ]);

  const getPointerPos = (e) => {
    const canvas = canvasRef.current;
    if (!canvas) return { x: 0, y: 0 };
    const rect = canvas.getBoundingClientRect();
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const clientY = e.touches ? e.touches[0].clientY : e.clientY;
    return {
      x: clientX - rect.left,
      y: clientY - rect.top,
      W: rect.width || 720,
      H: rect.height || height,
    };
  };

  const handlePointerDown = (e) => {
    const pos = getPointerPos(e);
    const hits = hitRegionsRef.current;

    // 1. Check Custom Node Drawing mode
    if (customNodeDrawMode && onAppendCustomNode && activeControllerForNodes) {
      const normX = Math.max(0.04, Math.min(0.96, Number((pos.x / pos.W).toFixed(3))));
      const normY = Math.max(
        0.18,
        Math.min(0.96, Number(((pos.H * 0.78 - pos.y) / (pos.H * 0.62)).toFixed(3)))
      );
      onAppendCustomNode(activeControllerForNodes, {
        x: normX,
        y: normY,
        z: 0.08,
        wall: 'front',
        label: `Node`,
      });
      return;
    }

    // 2. Check Draggable Roofline / Peak Handles
    if (editableHandles && onUpdateSectionGeometry) {
      const hitHandle = hits.handles.find(
        (h) => Math.hypot(h.x - pos.x, h.y - pos.y) <= h.radius
      );
      if (hitHandle) {
        dragStateRef.current = {
          type: 'handle',
          handle: hitHandle,
          startX: pos.x,
          startY: pos.y,
        };
        if (onSelectSection) onSelectSection(hitHandle.secId);
        return;
      }
    }

    // 3. Check LED Puck click
    const hitPuck = hits.pucks.find(
      (p) => Math.hypot(p.screenX - pos.x, p.screenY - pos.y) <= p.radius
    );
    if (hitPuck) {
      if (onSelectPuck) onSelectPuck(hitPuck);
      if (onSelectSection && hitPuck.sectionId && hitPuck.sectionId !== 'custom_nodes') {
        onSelectSection(hitPuck.sectionId);
      }
      if (onSelectHouse && hitPuck.houseId) {
        onSelectHouse(hitPuck.houseId);
      }
      return;
    }

    // 4. Check House Badge click
    const hitHouse = hits.houses.find(
      (b) => pos.x >= b.x && pos.x <= b.x + b.w && pos.y >= b.y && pos.y <= b.y + b.h
    );
    if (hitHouse && onSelectHouse) {
      onSelectHouse(hitHouse.houseId);
      return;
    }

    // 5. Default: Orbit 3D Camera on drag
    dragStateRef.current = {
      type: 'orbit',
      startX: pos.x,
      startY: pos.y,
      startYaw: camera.yaw,
      startPitch: camera.pitch,
    };
  };

  const handlePointerMove = (e) => {
    const pos = getPointerPos(e);
    const drag = dragStateRef.current;

    if (drag) {
      if (drag.type === 'orbit' && !is2D) {
        const dx = pos.x - drag.startX;
        const dy = pos.y - drag.startY;
        setCamera((prev) => ({
          ...prev,
          yaw: Math.max(-180, Math.min(180, Math.round(drag.startYaw + dx * 0.45))),
          pitch: Math.max(8, Math.min(65, Math.round(drag.startPitch + dy * 0.32))),
        }));
      } else if (drag.type === 'handle' && onUpdateSectionGeometry) {
        const { handle } = drag;
        const dxNorm = (pos.x - drag.startX) / Math.max(180, handle.scale || 260);
        const dyNorm = -(pos.y - drag.startY) / Math.max(140, (handle.scale || 260) * 0.78);
        drag.startX = pos.x;
        drag.startY = pos.y;
        onUpdateSectionGeometry(handle.houseId, handle.secId, handle.kind, dxNorm, dyNorm);
      }
      return;
    }

    // Hover detection for pucks & handles
    const hits = hitRegionsRef.current;
    const hHandle = hits.handles.find(
      (h) => Math.hypot(h.x - pos.x, h.y - pos.y) <= h.radius
    );
    if (hHandle) {
      setHoveredItem({ type: 'handle', label: hHandle.label });
      return;
    }
    const hPuck = hits.pucks.find(
      (p) => Math.hypot(p.screenX - pos.x, p.screenY - pos.y) <= p.radius
    );
    if (hPuck) {
      setHoveredItem({
        type: 'puck',
        id: hPuck.id,
        label: `${hPuck.controllerName} · Seg #${hPuck.localIndex + 1} (${hPuck.sectionLabel})`,
      });
      return;
    }
    if (hoveredItem) setHoveredItem(null);
  };

  const handlePointerUp = () => {
    dragStateRef.current = null;
  };

  return (
    <div className="relative rounded-2xl overflow-hidden border border-[#1e293b] bg-[#040814] select-none">
      {/* Top Overlay Camera & Mode Controls */}
      {showCameraControls && (
        <div className="absolute top-2.5 left-2.5 right-2.5 z-10 flex flex-wrap items-center justify-between gap-1.5 pointer-events-none">
          <div className="flex flex-wrap items-center gap-1 pointer-events-auto bg-[#060b18]/90 backdrop-blur-md border border-[#1e293b] rounded-xl px-2 py-1">
            {!is2D ? (
              <>
                <span className="text-[10px] font-mono text-cyan-300 font-bold mr-1">
                  3D Orbit ({camera.yaw}° / {camera.pitch}°):
                </span>
                {[
                  { id: 'street', label: 'Street 3D' },
                  { id: 'left45', label: 'Left 45°' },
                  { id: 'right45', label: 'Right 45°' },
                  { id: 'aerial', label: 'Aerial Roof' },
                  { id: 'reset', label: 'Reset View' },
                ].map((preset) => (
                  <button
                    key={preset.id}
                    type="button"
                    onClick={() => applyCameraPreset(preset.id)}
                    className="px-2 py-0.5 rounded-lg text-[10px] font-bold bg-[#0f172a] hover:bg-cyan-500/20 text-slate-200 hover:text-cyan-200 border border-slate-700/80 transition"
                  >
                    {preset.label}
                  </button>
                ))}
              </>
            ) : (
              <span className="text-[10px] font-mono text-cyan-300 font-bold px-1">
                📐 2D Front Architectural Elevation Blueprint (Multi-Section Gables, Dormers &amp; Square Eaves)
              </span>
            )}
          </div>

          {hoveredItem && (
            <div className="px-2.5 py-1 rounded-xl bg-[#060b18]/95 border border-cyan-500/50 text-[11px] font-mono text-cyan-200 shadow-lg">
              {hoveredItem.label}
            </div>
          )}
        </div>
      )}

      <canvas
        ref={canvasRef}
        style={{ width: '100%', height: `${height}px`, display: 'block' }}
        className={
          customNodeDrawMode
            ? 'cursor-crosshair'
            : hoveredItem
            ? 'cursor-pointer'
            : is2D
            ? 'cursor-default'
            : 'cursor-grab active:cursor-grabbing'
        }
        onMouseDown={handlePointerDown}
        onMouseMove={handlePointerMove}
        onMouseUp={handlePointerUp}
        onMouseLeave={handlePointerUp}
        onTouchStart={handlePointerDown}
        onTouchMove={handlePointerMove}
        onTouchEnd={handlePointerUp}
      />

      {/* Bottom Helper Bar */}
      <div className="px-3 py-1.5 bg-[#060b18]/95 border-t border-[#1e293b] flex flex-wrap items-center justify-between gap-2 text-[11px] text-slate-400">
        <div className="flex items-center gap-2">
          <Compass className="w-3.5 h-3.5 text-[#00f5d4] shrink-0" />
          <span>
            {is2D
              ? editableHandles
                ? 'Drag cyan/gold handles to reshape eaves & triangle peaks • Click any LED puck to inspect'
                : '2D Front Elevation • Click any LED puck to inspect its controller & section'
              : 'Drag anywhere to orbit 3D view • Click any LED puck to spotlight on physical house'}
          </span>
        </div>
        {onOpenDesigner && (
          <button
            type="button"
            onClick={onOpenDesigner}
            className="text-[11px] font-extrabold text-[#00f5d4] hover:underline flex items-center gap-1"
          >
            <span>Open Full 2D/3D CAD Studio</span>
            <ChevronRight className="w-3.5 h-3.5" />
          </button>
        )}
      </div>
    </div>
  );
}

/**
 * Interactive 2D/3D House Architecture & Controller Light Strip Studio (`HouseArchitectureDesigner.jsx`)
 */
export default function HouseArchitectureDesigner({
  config,
  liveState,
  initialHouseId = null,
  onSaveConfig = null,
  apiFetch = null,
  onClose = null,
  inlineMode = false,
}) {
  const houses = useMemo(
    () => [...(config?.houses || [])].sort((a, b) => (a.order || 1) - (b.order || 1)),
    [config?.houses]
  );

  const [selectedHouseId, setSelectedHouseId] = useState(
    () => initialHouseId || houses[0]?.id || 'house-1'
  );
  // Default view mode inside Designer is 3D ('3d_single')
  const [designerViewMode, setDesignerViewMode] = useState('3d_single'); // '3d_single' | '2d' | '3d_all'
  const [selectedSectionId, setSelectedSectionId] = useState(null);
  const [selectedPuck, setSelectedPuck] = useState(null);
  const [customNodeDrawCtrlId, setCustomNodeDrawCtrlId] = useState(null);
  const [saveBanner, setSaveBanner] = useState('');
  const [saving, setSaving] = useState(false);
  const [spotlighting, setSpotlighting] = useState(false);

  // Local editable draft of houses (with architecture + controller section_spans + custom_nodes)
  const [draftHouses, setDraftHouses] = useState(() =>
    houses.map((h, idx) => {
      const arch = getEffectiveHouseArchitecture(h, idx);
      const ctrls = (h.controllers || []).map((c, cIdx) => ({
        ...c,
        section_spans: getEffectiveControllerSpans(c, arch, cIdx),
        custom_nodes: getEffectiveCustomNodes(c),
      }));
      return { ...h, architecture: arch, controllers: ctrls };
    })
  );

  useEffect(() => {
    if (initialHouseId) setSelectedHouseId(initialHouseId);
  }, [initialHouseId]);

  useEffect(() => {
    if (!houses.length) return;
    setDraftHouses((prev) => {
      return houses.map((h, idx) => {
        const existingDraft = prev.find((d) => d.id === h.id);
        const arch = existingDraft?.architecture || getEffectiveHouseArchitecture(h, idx);
        const ctrls = (h.controllers || []).map((c, cIdx) => {
          const existingCtrl = existingDraft?.controllers?.find((dc) => dc.id === c.id);
          return {
            ...c,
            segment_count: existingCtrl?.segment_count ?? c.segment_count ?? 9,
            section_spans:
              existingCtrl?.section_spans || getEffectiveControllerSpans(c, arch, cIdx),
            custom_nodes: existingCtrl?.custom_nodes || getEffectiveCustomNodes(c),
          };
        });
        return { ...h, architecture: arch, controllers: ctrls };
      });
    });
  }, [houses]);

  const activeHouseIndex = Math.max(
    0,
    draftHouses.findIndex((h) => h.id === selectedHouseId)
  );
  const activeHouse = draftHouses[activeHouseIndex] || draftHouses[0];
  const activeArch = activeHouse?.architecture || ARCHITECTURAL_PRESETS.a_frame_gable;
  const activeSections = activeArch.sections || [];
  const activeSection =
    activeSections.find((s) => s.id === selectedSectionId) || activeSections[0] || null;

  useEffect(() => {
    if (activeSections.length > 0 && !activeSections.some((s) => s.id === selectedSectionId)) {
      setSelectedSectionId(activeSections[0].id);
    }
  }, [activeHouse?.id, activeSections, selectedSectionId]);

  const doFetch = useCallback(
    async (url, opts = {}) => {
      if (apiFetch) return apiFetch(url, opts);
      return fetch(url, {
        ...opts,
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          ...(opts.headers || {}),
        },
      });
    },
    [apiFetch]
  );

  const flashStatus = (msg) => {
    setSaveBanner(msg);
    setTimeout(() => setSaveBanner(''), 4500);
  };

  // Apply 1-Tap Architectural Template to active house
  const handleApplyTemplate = (presetKey) => {
    const preset = ARCHITECTURAL_PRESETS[presetKey];
    if (!preset || !activeHouse) return;
    const clonedSections = preset.sections.map((s, idx) =>
      normalizeSection({ ...s, id: `${activeHouse.id}-${s.id}-${idx}` }, idx)
    );
    const nextArch = {
      preset_style: preset.preset_style,
      label: preset.label,
      sections: clonedSections,
    };

    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const updatedCtrls = (h.controllers || []).map((c, cIdx) => ({
          ...c,
          section_spans: getEffectiveControllerSpans(
            { ...c, section_spans: [] },
            nextArch,
            cIdx
          ),
        }));
        return { ...h, architecture: nextArch, controllers: updatedCtrls };
      })
    );
    setSelectedSectionId(clonedSections[0]?.id || null);
    flashStatus(`Applied "${preset.label}" template to ${activeHouse.name}!`);
  };

  // Update a specific section field
  const handleUpdateSection = (secId, patch) => {
    if (!activeHouse) return;
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const nextSections = (h.architecture?.sections || []).map((s, i) =>
          s.id === secId ? normalizeSection({ ...s, ...patch }, i) : s
        );
        return {
          ...h,
          architecture: {
            ...(h.architecture || {}),
            preset_style: 'custom',
            sections: nextSections,
          },
        };
      })
    );
  };

  // Dragging handles in 2D/3D canvas
  const handleDragSectionGeometry = useCallback((houseId, secId, handleKind, dx, dy) => {
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== houseId) return h;
        const nextSections = (h.architecture?.sections || []).map((s, i) => {
          if (s.id !== secId) return s;
          if (handleKind === 'left_eave') {
            const nextXStart = Math.max(0, Math.min(s.x_end - 0.1, s.x_start + dx));
            const nextEave = Math.max(0.2, Math.min(0.92, s.eave_height + dy));
            return normalizeSection(
              {
                ...s,
                x_start: nextXStart,
                eave_height: nextEave,
                peak_height: s.shape === 'flat_eave' ? nextEave : Math.max(nextEave, s.peak_height),
              },
              i
            );
          }
          if (handleKind === 'right_eave') {
            const nextXEnd = Math.max(s.x_start + 0.1, Math.min(1.0, s.x_end + dx));
            const nextEave = Math.max(0.2, Math.min(0.92, s.eave_height + dy));
            return normalizeSection(
              {
                ...s,
                x_end: nextXEnd,
                eave_height: nextEave,
                peak_height: s.shape === 'flat_eave' ? nextEave : Math.max(nextEave, s.peak_height),
              },
              i
            );
          }
          if (handleKind === 'peak_apex') {
            const span = Math.max(0.1, s.x_end - s.x_start);
            const nextOffset = Math.max(
              0.15,
              Math.min(0.85, (s.peak_offset ?? 0.5) + dx / span)
            );
            const nextPeak = Math.max(s.eave_height + 0.04, Math.min(1.0, s.peak_height + dy));
            return normalizeSection(
              {
                ...s,
                peak_offset: nextOffset,
                peak_height: nextPeak,
              },
              i
            );
          }
          return s;
        });
        return {
          ...h,
          architecture: { ...(h.architecture || {}), sections: nextSections },
        };
      })
    );
  }, []);

  // Add a new architectural section
  const handleAddSection = (presetType) => {
    if (!activeHouse) return;
    const count = activeSections.length + 1;
    const newId = `sec-${Date.now().toString(36)}-${count}`;
    let template = {
      id: newId,
      label: `Triangle Gable #${count}`,
      shape: 'triangle_gable',
      wall: 'front',
      story: 1,
      x_start: 0.2,
      x_end: 0.8,
      eave_height: 0.45,
      peak_height: 0.86,
      peak_offset: 0.5,
      depth_offset: 0.1,
      has_garage: false,
      has_door: false,
      window_style: 'mullion',
    };
    if (presetType === 'flat_eave') {
      template = {
        ...template,
        label: `Square Flat Eave #${count}`,
        shape: 'flat_eave',
        x_start: 0.05,
        x_end: 0.48,
        eave_height: 0.46,
        peak_height: 0.46,
        depth_offset: 0.15,
        has_garage: true,
        window_style: 'picture',
      };
    } else if (presetType === 'dormer_peak') {
      template = {
        ...template,
        label: `2nd-Story Dormer Peak #${count}`,
        shape: 'dormer_peak',
        story: 2,
        x_start: 0.28,
        x_end: 0.72,
        eave_height: 0.64,
        peak_height: 0.94,
        depth_offset: -0.05,
        window_style: 'arched',
      };
    } else if (presetType === 'side_wall') {
      template = {
        ...template,
        label: `Right Side Eave #${count}`,
        shape: 'flat_eave',
        wall: 'right',
        story: 1,
        x_start: 0.05,
        x_end: 0.95,
        eave_height: 0.45,
        peak_height: 0.45,
        depth_offset: 0.0,
      };
    }

    const normalized = normalizeSection(template, count);
    setDraftHouses((prev) =>
      prev.map((h) =>
        h.id === activeHouse.id
          ? {
              ...h,
              architecture: {
                ...(h.architecture || {}),
                sections: [...(h.architecture?.sections || []), normalized],
              },
            }
          : h
      )
    );
    setSelectedSectionId(normalized.id);
  };

  const handleDeleteSection = (secId) => {
    if (!activeHouse || activeSections.length <= 1) return;
    const remaining = activeSections.filter((s) => s.id !== secId);
    setDraftHouses((prev) =>
      prev.map((h) =>
        h.id === activeHouse.id
          ? {
              ...h,
              architecture: { ...(h.architecture || {}), sections: remaining },
            }
          : h
      )
    );
    if (selectedSectionId === secId) {
      setSelectedSectionId(remaining[0]?.id || null);
    }
  };

  const handleMoveSection = (secId, dir) => {
    if (!activeHouse) return;
    const idx = activeSections.findIndex((s) => s.id === secId);
    const targetIdx = idx + dir;
    if (idx < 0 || targetIdx < 0 || targetIdx >= activeSections.length) return;
    const copy = [...activeSections];
    const [item] = copy.splice(idx, 1);
    copy.splice(targetIdx, 0, item);
    setDraftHouses((prev) =>
      prev.map((h) =>
        h.id === activeHouse.id
          ? { ...h, architecture: { ...(h.architecture || {}), sections: copy } }
          : h
      )
    );
  };

  // Controller Section Spans manipulation
  const handleUpdateControllerSpan = (ctrlId, spanIndex, patch) => {
    if (!activeHouse) return;
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const nextCtrls = (h.controllers || []).map((c) => {
          if (c.id !== ctrlId) return c;
          const spans = [...(c.section_spans || [])];
          const updated = { ...spans[spanIndex], ...patch };
          if (patch.section_id) {
            const matchedSec = activeSections.find((s) => s.id === patch.section_id);
            if (matchedSec) updated.wall = matchedSec.wall;
          }
          spans[spanIndex] = updated;
          const totalSegs = spans.reduce((s, sp) => s + Math.max(1, Number(sp.segments || 1)), 0);
          return { ...c, section_spans: spans, segment_count: totalSegs };
        });
        return { ...h, controllers: nextCtrls };
      })
    );
  };

  const handleAddControllerSpan = (ctrlId) => {
    if (!activeHouse) return;
    const fallbackSec = activeSections[0];
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const nextCtrls = (h.controllers || []).map((c) => {
          if (c.id !== ctrlId) return c;
          const nextSpans = [
            ...(c.section_spans || []),
            {
              section_id: fallbackSec?.id || 'sec-1',
              wall: fallbackSec?.wall || 'front',
              segments: 4,
              direction: 'ltr',
            },
          ];
          const totalSegs = nextSpans.reduce(
            (s, sp) => s + Math.max(1, Number(sp.segments || 1)),
            0
          );
          return { ...c, section_spans: nextSpans, segment_count: totalSegs };
        });
        return { ...h, controllers: nextCtrls };
      })
    );
  };

  const handleRemoveControllerSpan = (ctrlId, spanIndex) => {
    if (!activeHouse) return;
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const nextCtrls = (h.controllers || []).map((c) => {
          if (c.id !== ctrlId || (c.section_spans || []).length <= 1) return c;
          const nextSpans = c.section_spans.filter((_, idx) => idx !== spanIndex);
          const totalSegs = nextSpans.reduce(
            (s, sp) => s + Math.max(1, Number(sp.segments || 1)),
            0
          );
          return { ...c, section_spans: nextSpans, segment_count: totalSegs };
        });
        return { ...h, controllers: nextCtrls };
      })
    );
  };

  const handleAutoBalanceController = (ctrlId) => {
    if (!activeHouse) return;
    const frontSecs = activeSections.filter((s) => s.wall === 'front');
    const targetSecs = frontSecs.length > 0 ? frontSecs : activeSections;
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const nextCtrls = (h.controllers || []).map((c) => {
          if (c.id !== ctrlId) return c;
          const total = Math.max(targetSecs.length, Number(c.segment_count || 9));
          const base = Math.floor(total / targetSecs.length);
          let rem = total - base * targetSecs.length;
          const balanced = targetSecs.map((sec) => {
            const add = rem > 0 ? 1 : 0;
            if (rem > 0) rem -= 1;
            return {
              section_id: sec.id,
              wall: sec.wall,
              segments: Math.max(1, base + add),
              direction: 'ltr',
            };
          });
          return { ...c, section_spans: balanced, custom_nodes: [] };
        });
        return { ...h, controllers: nextCtrls };
      })
    );
    flashStatus('Auto-balanced controller segments across all front roof sections!');
  };

  // Custom Polyline Nodes for a Controller
  const handleAppendCustomNode = useCallback(
    (ctrlId, node) => {
      if (!activeHouse) return;
      setDraftHouses((prev) =>
        prev.map((h) => {
          if (h.id !== activeHouse.id) return h;
          const nextCtrls = (h.controllers || []).map((c) => {
            if (c.id !== ctrlId) return c;
            const nextNodes = [
              ...(c.custom_nodes || []),
              { ...node, label: `Vertex #${(c.custom_nodes || []).length + 1}` },
            ];
            return { ...c, custom_nodes: nextNodes };
          });
          return { ...h, controllers: nextCtrls };
        })
      );
    },
    [activeHouse]
  );

  const handleClearCustomNodes = (ctrlId) => {
    if (!activeHouse) return;
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        return {
          ...h,
          controllers: (h.controllers || []).map((c) =>
            c.id === ctrlId ? { ...c, custom_nodes: [] } : c
          ),
        };
      })
    );
    if (customNodeDrawCtrlId === ctrlId) setCustomNodeDrawCtrlId(null);
  };

  // 1-Click Spotlight Puck on Physical House
  const handleSpotlightPhysicalPuck = async (puck) => {
    if (!puck) return;
    setSpotlighting(true);
    try {
      const res = await doFetch(`/api/controllers/${puck.controllerId}/locate-segment`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          segment_index: puck.localIndex,
          color: '#00f5d4',
          duration_sec: 8,
        }),
      });
      if (res.ok) {
        flashStatus(
          `🔦 Spotlighting ${puck.controllerName} · Puck #${puck.localIndex + 1} (${puck.sectionLabel}) on physical house for 8s!`
        );
      } else {
        // Fallback test pulse if locate-segment endpoint isn't active
        await doFetch(`/api/controllers/${puck.controllerId}/test`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ color: '#00f5d4' }),
        });
        flashStatus(
          `🔦 Sent highlight pulse to ${puck.controllerName} · Puck #${puck.localIndex + 1} (${puck.sectionLabel})!`
        );
      }
    } catch (e) {
      flashStatus(
        `🔦 Highlighted ${puck.controllerName} · Puck #${puck.localIndex + 1} in studio preview!`
      );
    } finally {
      setSpotlighting(false);
    }
  };

  // Save House Architecture & Controller Section Spans
  const handleSaveHouseDesign = async () => {
    if (!activeHouse) return;
    setSaving(true);
    try {
      const ctrlMap = {};
      (activeHouse.controllers || []).forEach((c) => {
        ctrlMap[c.id] = {
          segment_count: c.segment_count,
          section_spans: c.section_spans,
          custom_nodes: c.custom_nodes,
        };
      });

      // 1. Persist immediately in localStorage so it never gets lost
      saveArchitectureOverride(activeHouse.id, activeHouse.architecture, ctrlMap);

      // 2. Call backend PATCH /api/houses/{house_id}/architecture
      await doFetch(`/api/houses/${activeHouse.id}/architecture`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          architecture: activeHouse.architecture,
          controllers: ctrlMap,
        }),
      }).catch(() => null);

      // 3. Call backend PATCH /api/controllers/{ctrl_id}/zones for each controller
      await Promise.all(
        (activeHouse.controllers || []).map((ctrl) =>
          doFetch(`/api/controllers/${ctrl.id}/zones`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              segment_count: ctrl.segment_count,
              section_spans: ctrl.section_spans,
              custom_nodes: ctrl.custom_nodes,
            }),
          }).catch(() => null)
        )
      );

      // 4. Update full config via onSaveConfig if provided
      if (onSaveConfig && config) {
        await onSaveConfig({
          ...config,
          houses: draftHouses,
        });
      }

      flashStatus(
        `💾 Saved 3D/2D Architecture & Controller Light Spans for ${activeHouse.name}!`
      );
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="bg-gradient-to-b from-[#0a1224] to-[#060b17] border border-[#00f5d4]/40 rounded-2xl p-4 sm:p-5 shadow-2xl space-y-4">
      {/* Header Row */}
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-[#1e293b] pb-3">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-xl bg-[#00f5d4]/15 border border-[#00f5d4]/40 flex items-center justify-center text-[#00f5d4]">
            <Box className="w-5 h-5" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h3 className="text-sm sm:text-base font-extrabold text-white">
                🏗️ 3D &amp; 2D House Architecture &amp; Light Strip Studio
              </h3>
              <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-[#00f5d4]/15 text-[#00f5d4] border border-[#00f5d4]/40 font-bold">
                CAD + LIVE LED MAPPING
              </span>
            </div>
            <p className="text-xs text-slate-400">
              Design multi-section triangle gables, square garage eaves, and 2nd-story dormers — then assign exact light segments per controller.
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <button
            type="button"
            disabled={saving}
            onClick={handleSaveHouseDesign}
            className="px-3.5 py-2 rounded-xl bg-[#00f5d4] hover:bg-[#2efae0] text-[#040711] font-extrabold text-xs flex items-center gap-1.5 shadow-lg shadow-[#00f5d4]/20 transition"
          >
            <Save className="w-4 h-4" />
            <span>{saving ? 'Saving...' : '💾 Save House & Light Design'}</span>
          </button>
          {onClose && (
            <button
              type="button"
              onClick={onClose}
              className="p-2 rounded-xl bg-[#0f172a] hover:bg-slate-800 text-slate-300 border border-[#1e293b]"
              title="Close Designer"
            >
              <X className="w-4 h-4" />
            </button>
          )}
        </div>
      </div>

      {saveBanner && (
        <div className="px-3.5 py-2 rounded-xl bg-emerald-500/15 border border-emerald-400/40 text-xs font-bold text-emerald-200 flex items-center justify-between">
          <span>{saveBanner}</span>
          <Check className="w-4 h-4 text-emerald-300 shrink-0" />
        </div>
      )}

      {/* House Selector + 3D (Default) vs 2D Blueprint Mode Bar */}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-xs font-bold text-slate-400 mr-1">Select House:</span>
          {draftHouses.map((h, idx) => {
            const active = h.id === activeHouse?.id;
            const segTotal = (h.controllers || []).reduce(
              (acc, c) => acc + Number(c.segment_count || 0),
              0
            );
            return (
              <button
                key={h.id}
                type="button"
                onClick={() => {
                  setSelectedHouseId(h.id);
                  setSelectedPuck(null);
                }}
                className={`px-3 py-1.5 rounded-xl text-xs font-extrabold border transition flex items-center gap-1.5 ${
                  active
                    ? 'bg-[#00f5d4]/20 text-[#00f5d4] border-[#00f5d4] shadow-md shadow-[#00f5d4]/10'
                    : 'bg-[#060b18] text-slate-300 border-[#1e293b] hover:text-white'
                }`}
              >
                <Home className="w-3.5 h-3.5" />
                <span>
                  House {idx + 1} — {(h.name || `House ${idx + 1}`).split('(')[0].trim()} ({segTotal}s)
                </span>
              </button>
            );
          })}
        </div>

        {/* View Mode Toggle: 3D Interactive Designer (Default) vs 2D Blueprint Editor vs 3D Street */}
        <div className="flex items-center gap-1 bg-[#060b18] p-1 rounded-xl border border-[#1e293b]">
          {[
            { id: '3d_single', label: '🧊 3D Interactive Designer (Default)' },
            { id: '2d', label: '📐 2D Blueprint Editor' },
            { id: '3d_all', label: '🏘️ 3D Full Street' },
          ].map((m) => (
            <button
              key={m.id}
              type="button"
              onClick={() => setDesignerViewMode(m.id)}
              className={`px-2.5 py-1 rounded-lg text-[11px] font-extrabold transition ${
                designerViewMode === m.id
                  ? 'bg-[#00f5d4] text-[#040711]'
                  : 'text-slate-300 hover:text-white'
              }`}
            >
              {m.label}
            </button>
          ))}
        </div>
      </div>

      {/* 1-Tap Architectural Templates Bar */}
      <div className="bg-[#060b18] border border-[#1e293b] rounded-xl p-2.5 space-y-1.5">
        <div className="flex items-center justify-between">
          <span className="text-[11px] font-extrabold text-cyan-300 uppercase tracking-wider">
            1-Tap Architectural Roofline Templates (Instant Multi-Section Layout):
          </span>
          <span className="text-[10px] font-mono text-slate-400">
            Active Preset: {activeArch.preset_style}
          </span>
        </div>
        <div className="flex flex-wrap gap-1.5">
          {Object.entries(ARCHITECTURAL_PRESETS).map(([key, tpl]) => {
            const isCurr = activeArch.preset_style === key;
            return (
              <button
                key={key}
                type="button"
                onClick={() => handleApplyTemplate(key)}
                className={`px-2.5 py-1.5 rounded-lg text-xs font-bold border transition ${
                  isCurr
                    ? 'bg-cyan-500/20 text-cyan-200 border-cyan-400'
                    : 'bg-[#0c1324] hover:bg-[#16223b] text-slate-300 border-[#1e293b]'
                }`}
              >
                {tpl.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Interactive 3D / 2D Viewport Canvas */}
      <ArchitecturalViewportCanvas
        houses={draftHouses}
        liveSegments={liveState?.segments || []}
        animation={config?.animation || {}}
        previewMode={
          designerViewMode === '3d_single'
            ? `3d_house:${activeHouse?.id}`
            : designerViewMode
        }
        selectedHouseId={activeHouse?.id}
        selectedSectionId={selectedSectionId}
        selectedPuckId={selectedPuck?.id}
        onSelectHouse={(hId) => setSelectedHouseId(hId)}
        onSelectSection={(sId) => setSelectedSectionId(sId)}
        onSelectPuck={(puck) => setSelectedPuck(puck)}
        editableHandles
        customNodeDrawMode={Boolean(customNodeDrawCtrlId)}
        activeControllerForNodes={customNodeDrawCtrlId}
        onUpdateSectionGeometry={handleDragSectionGeometry}
        onAppendCustomNode={handleAppendCustomNode}
        height={320}
      />

      {/* Selected LED Puck Inspector & 1-Tap Physical House Spotlight */}
      {selectedPuck && (
        <div className="bg-[#081529] border border-[#00f5d4]/60 rounded-xl p-3 flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <span
              className="w-5 h-5 rounded-full border-2 border-white shadow-md shrink-0"
              style={{ backgroundColor: selectedPuck.hex }}
            />
            <div>
              <div className="text-xs font-extrabold text-white">
                Selected LED Puck: {selectedPuck.controllerName} · Segment #
                {selectedPuck.localIndex + 1} (House Seg #{selectedPuck.houseSegIndex + 1})
              </div>
              <div className="text-[11px] text-cyan-300 font-mono">
                Mounted on Section: {selectedPuck.sectionLabel} ({selectedPuck.wall.toUpperCase()} Wall)
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              disabled={spotlighting}
              onClick={() => handleSpotlightPhysicalPuck(selectedPuck)}
              className="px-3 py-1.5 rounded-xl bg-amber-400 hover:bg-amber-300 text-slate-950 font-extrabold text-xs flex items-center gap-1.5 shadow-md transition"
            >
              <Flashlight className="w-3.5 h-3.5" />
              <span>
                {spotlighting
                  ? 'Spotlighting...'
                  : `🔦 Spotlight Puck #${selectedPuck.localIndex + 1} on Physical House`}
              </span>
            </button>
            <button
              type="button"
              onClick={() => setSelectedPuck(null)}
              className="px-2 py-1.5 rounded-lg bg-slate-800 text-slate-300 text-xs hover:text-white"
            >
              Clear
            </button>
          </div>
        </div>
      )}

      {/* Dual-Column Studio: Left = Architectural Section Builder | Right = Per-Controller Light Section Assignment */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* LEFT COLUMN (6 cols): Architectural Section Builder */}
        <div className="lg:col-span-6 bg-[#060b18] border border-[#1e293b] rounded-xl p-3.5 space-y-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <h4 className="text-xs sm:text-sm font-extrabold text-white flex items-center gap-1.5">
              <Layers className="w-4 h-4 text-[#00f5d4]" />
              <span>1. Architectural Roof &amp; Wall Sections ({activeSections.length})</span>
            </h4>
            <div className="flex flex-wrap gap-1">
              <button
                type="button"
                onClick={() => handleAddSection('triangle_gable')}
                className="px-2 py-1 rounded-lg bg-[#0c1324] hover:bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 text-[11px] font-bold"
              >
                + Add Triangle Peak
              </button>
              <button
                type="button"
                onClick={() => handleAddSection('flat_eave')}
                className="px-2 py-1 rounded-lg bg-[#0c1324] hover:bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 text-[11px] font-bold"
              >
                + Add Square Flat Eave
              </button>
              <button
                type="button"
                onClick={() => handleAddSection('dormer_peak')}
                className="px-2 py-1 rounded-lg bg-[#0c1324] hover:bg-purple-500/20 text-purple-300 border border-purple-500/40 text-[11px] font-bold"
              >
                + Add 2nd-Story Dormer
              </button>
              <button
                type="button"
                onClick={() => handleAddSection('side_wall')}
                className="px-2 py-1 rounded-lg bg-[#0c1324] hover:bg-amber-500/20 text-amber-300 border border-amber-500/40 text-[11px] font-bold"
              >
                + Add Side/Back Wall
              </button>
            </div>
          </div>

          {/* Section Selector Chips */}
          <div className="flex flex-wrap gap-1.5">
            {activeSections.map((sec, idx) => {
              const isSel = activeSection?.id === sec.id;
              return (
                <div
                  key={sec.id}
                  className={`flex items-center gap-1 rounded-lg border px-2 py-1 text-xs font-bold transition ${
                    isSel
                      ? 'bg-[#00f5d4]/20 border-[#00f5d4] text-[#00f5d4]'
                      : 'bg-[#0c1324] border-[#1e293b] text-slate-300'
                  }`}
                >
                  <button
                    type="button"
                    onClick={() => setSelectedSectionId(sec.id)}
                    className="text-left"
                  >
                    {idx + 1}. {sec.label} ({sec.wall})
                  </button>
                  <button
                    type="button"
                    onClick={() => handleMoveSection(sec.id, -1)}
                    className="p-0.5 hover:text-white"
                    title="Move earlier"
                  >
                    <ArrowUp className="w-3 h-3" />
                  </button>
                  <button
                    type="button"
                    onClick={() => handleMoveSection(sec.id, 1)}
                    className="p-0.5 hover:text-white"
                    title="Move later"
                  >
                    <ArrowDown className="w-3 h-3" />
                  </button>
                  {activeSections.length > 1 && (
                    <button
                      type="button"
                      onClick={() => handleDeleteSection(sec.id)}
                      className="p-0.5 text-rose-400 hover:text-rose-200"
                      title="Delete section"
                    >
                      <Trash2 className="w-3 h-3" />
                    </button>
                  )}
                </div>
              );
            })}
          </div>

          {/* Selected Section Parameter Sliders & Controls */}
          {activeSection && (
            <div className="bg-[#0c1324] border border-[#1e293b] rounded-xl p-3 space-y-2.5">
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                <div>
                  <label className="block text-[10px] font-bold text-slate-400 uppercase">
                    Section Name
                  </label>
                  <input
                    type="text"
                    value={activeSection.label}
                    onChange={(e) =>
                      handleUpdateSection(activeSection.id, { label: e.target.value })
                    }
                    className="w-full mt-0.5 px-2.5 py-1 rounded-lg bg-[#060b18] border border-[#1e293b] text-xs text-white font-semibold"
                  />
                </div>

                <div>
                  <label className="block text-[10px] font-bold text-slate-400 uppercase">
                    Roof / Section Shape
                  </label>
                  <select
                    value={activeSection.shape}
                    onChange={(e) =>
                      handleUpdateSection(activeSection.id, { shape: e.target.value })
                    }
                    className="w-full mt-0.5 px-2 py-1 rounded-lg bg-[#060b18] border border-[#1e293b] text-xs text-cyan-200 font-bold"
                  >
                    {SECTION_SHAPES.map((sh) => (
                      <option key={sh.id} value={sh.id}>
                        {sh.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="grid grid-cols-2 gap-1.5">
                  <div>
                    <label className="block text-[10px] font-bold text-slate-400 uppercase">
                      Wall
                    </label>
                    <select
                      value={activeSection.wall}
                      onChange={(e) =>
                        handleUpdateSection(activeSection.id, { wall: e.target.value })
                      }
                      className="w-full mt-0.5 px-2 py-1 rounded-lg bg-[#060b18] border border-[#1e293b] text-xs text-white font-semibold"
                    >
                      {WALL_OPTIONS.map((w) => (
                        <option key={w.id} value={w.id}>
                          {w.label}
                        </option>
                      ))}
                    </select>
                  </div>
                  <div>
                    <label className="block text-[10px] font-bold text-slate-400 uppercase">
                      Story
                    </label>
                    <select
                      value={activeSection.story}
                      onChange={(e) =>
                        handleUpdateSection(activeSection.id, {
                          story: Number(e.target.value),
                        })
                      }
                      className="w-full mt-0.5 px-2 py-1 rounded-lg bg-[#060b18] border border-[#1e293b] text-xs text-white font-semibold"
                    >
                      <option value={1}>1st Story</option>
                      <option value={2}>2nd Story</option>
                    </select>
                  </div>
                </div>
              </div>

              {/* Span, Eave Height, Peak Height, Peak Center & 3D Depth Sliders */}
              <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5 pt-1">
                <div>
                  <div className="flex justify-between text-[10px] font-mono text-slate-300">
                    <span>Left Start (X)</span>
                    <span className="text-cyan-300">{Math.round(activeSection.x_start * 100)}%</span>
                  </div>
                  <input
                    type="range"
                    min="0"
                    max="0.88"
                    step="0.02"
                    value={activeSection.x_start}
                    onChange={(e) =>
                      handleUpdateSection(activeSection.id, {
                        x_start: Number(e.target.value),
                      })
                    }
                    className="w-full accent-[#00f5d4]"
                  />
                </div>

                <div>
                  <div className="flex justify-between text-[10px] font-mono text-slate-300">
                    <span>Right End (X)</span>
                    <span className="text-cyan-300">{Math.round(activeSection.x_end * 100)}%</span>
                  </div>
                  <input
                    type="range"
                    min="0.12"
                    max="1.0"
                    step="0.02"
                    value={activeSection.x_end}
                    onChange={(e) =>
                      handleUpdateSection(activeSection.id, {
                        x_end: Number(e.target.value),
                      })
                    }
                    className="w-full accent-[#00f5d4]"
                  />
                </div>

                <div>
                  <div className="flex justify-between text-[10px] font-mono text-slate-300">
                    <span>Eave Height</span>
                    <span className="text-cyan-300">
                      {Math.round(activeSection.eave_height * 100)}%
                    </span>
                  </div>
                  <input
                    type="range"
                    min="0.22"
                    max="0.90"
                    step="0.02"
                    value={activeSection.eave_height}
                    onChange={(e) =>
                      handleUpdateSection(activeSection.id, {
                        eave_height: Number(e.target.value),
                      })
                    }
                    className="w-full accent-[#00f5d4]"
                  />
                </div>

                {activeSection.shape !== 'flat_eave' && (
                  <>
                    <div>
                      <div className="flex justify-between text-[10px] font-mono text-slate-300">
                        <span>Triangle Peak Apex</span>
                        <span className="text-amber-300">
                          {Math.round(activeSection.peak_height * 100)}%
                        </span>
                      </div>
                      <input
                        type="range"
                        min={activeSection.eave_height}
                        max="1.0"
                        step="0.02"
                        value={activeSection.peak_height}
                        onChange={(e) =>
                          handleUpdateSection(activeSection.id, {
                            peak_height: Number(e.target.value),
                          })
                        }
                        className="w-full accent-amber-400"
                      />
                    </div>

                    <div>
                      <div className="flex justify-between text-[10px] font-mono text-slate-300">
                        <span>Peak Center / Skew</span>
                        <span className="text-amber-300">
                          {Math.round((activeSection.peak_offset ?? 0.5) * 100)}%
                        </span>
                      </div>
                      <input
                        type="range"
                        min="0.15"
                        max="0.85"
                        step="0.02"
                        value={activeSection.peak_offset ?? 0.5}
                        onChange={(e) =>
                          handleUpdateSection(activeSection.id, {
                            peak_offset: Number(e.target.value),
                          })
                        }
                        className="w-full accent-amber-400"
                      />
                    </div>
                  </>
                )}

                <div>
                  <div className="flex justify-between text-[10px] font-mono text-slate-300">
                    <span>3D Forward Step</span>
                    <span className="text-purple-300">
                      {activeSection.depth_offset >= 0 ? '+' : ''}
                      {Math.round((activeSection.depth_offset || 0) * 100)}%
                    </span>
                  </div>
                  <input
                    type="range"
                    min="-0.35"
                    max="0.35"
                    step="0.02"
                    value={activeSection.depth_offset || 0}
                    onChange={(e) =>
                      handleUpdateSection(activeSection.id, {
                        depth_offset: Number(e.target.value),
                      })
                    }
                    className="w-full accent-purple-400"
                  />
                </div>
              </div>

              {/* Garage / Front Door / Window Toggles */}
              <div className="flex flex-wrap items-center justify-between gap-2 pt-1 border-t border-[#1e293b]">
                <div className="flex flex-wrap items-center gap-2">
                  <label className="inline-flex items-center gap-1.5 text-xs text-slate-200 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={Boolean(activeSection.has_garage)}
                      onChange={(e) =>
                        handleUpdateSection(activeSection.id, {
                          has_garage: e.target.checked,
                        })
                      }
                      className="rounded accent-[#00f5d4]"
                    />
                    <span>🚗 Garage Door</span>
                  </label>

                  <label className="inline-flex items-center gap-1.5 text-xs text-slate-200 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={Boolean(activeSection.has_door)}
                      onChange={(e) =>
                        handleUpdateSection(activeSection.id, {
                          has_door: e.target.checked,
                        })
                      }
                      className="rounded accent-[#00f5d4]"
                    />
                    <span>🚪 Front Entry Door</span>
                  </label>
                </div>

                <div className="flex items-center gap-1.5">
                  <span className="text-[10px] font-bold text-slate-400 uppercase">
                    Windows:
                  </span>
                  <select
                    value={activeSection.window_style || 'mullion'}
                    onChange={(e) =>
                      handleUpdateSection(activeSection.id, {
                        window_style: e.target.value,
                      })
                    }
                    className="px-2 py-1 rounded-lg bg-[#060b18] border border-[#1e293b] text-xs text-white"
                  >
                    {WINDOW_STYLES.map((ws) => (
                      <option key={ws.id} value={ws.id}>
                        {ws.label}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* RIGHT COLUMN (6 cols): Per-Controller Light Section Assignment */}
        <div className="lg:col-span-6 bg-[#060b18] border border-[#1e293b] rounded-xl p-3.5 space-y-3">
          <div className="flex items-center justify-between gap-2">
            <h4 className="text-xs sm:text-sm font-extrabold text-white flex items-center gap-1.5">
              <Sparkles className="w-4 h-4 text-amber-400" />
              <span>
                2. Per-Controller Light Section Mapping ({(activeHouse?.controllers || []).length}{' '}
                Controllers)
              </span>
            </h4>
            <span className="text-[10px] font-mono text-slate-400">
              Assign exact segments per roof section
            </span>
          </div>

          <div className="space-y-3 max-h-[380px] overflow-y-auto pr-1">
            {(activeHouse?.controllers || []).map((ctrl, cIdx) => {
              const spans = ctrl.section_spans || [];
              const customNodes = ctrl.custom_nodes || [];
              const totalSpanSegs = spans.reduce(
                (acc, sp) => acc + Math.max(1, Number(sp.segments || 1)),
                0
              );
              const isDrawingThis = customNodeDrawCtrlId === ctrl.id;

              return (
                <div
                  key={ctrl.id || cIdx}
                  className="bg-[#0c1324] border border-[#1e293b] rounded-xl p-3 space-y-2.5"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-extrabold text-white">
                          Controller #{cIdx + 1}: {ctrl.name || ctrl.id}
                        </span>
                        <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-[#060b18] text-[#00f5d4] border border-[#1e293b]">
                          {ctrl.sku || 'H705'} · {totalSpanSegs} Total Segs
                        </span>
                      </div>
                      <p className="text-[10px] text-slate-400 font-mono">
                        {ctrl.ip || ctrl.mac || 'LAN / Cloud Controller'}
                      </p>
                    </div>

                    <div className="flex flex-wrap items-center gap-1.5">
                      <button
                        type="button"
                        onClick={() => handleAutoBalanceController(ctrl.id)}
                        className="px-2 py-1 rounded-lg bg-[#060b18] hover:bg-slate-800 text-cyan-300 border border-[#1e293b] text-[10px] font-bold"
                        title="Split segments evenly across front architectural sections"
                      >
                        ⚖️ Auto-Balance
                      </button>
                      <button
                        type="button"
                        onClick={() => handleAddControllerSpan(ctrl.id)}
                        className="px-2 py-1 rounded-lg bg-[#00f5d4]/15 hover:bg-[#00f5d4]/25 text-[#00f5d4] border border-[#00f5d4]/40 text-[10px] font-bold"
                      >
                        + Add Roof Section Span
                      </button>
                      <button
                        type="button"
                        onClick={() =>
                          setCustomNodeDrawCtrlId(isDrawingThis ? null : ctrl.id)
                        }
                        className={`px-2 py-1 rounded-lg text-[10px] font-bold border flex items-center gap-1 ${
                          isDrawingThis
                            ? 'bg-amber-400 text-slate-950 border-amber-300'
                            : 'bg-[#060b18] text-amber-300 border-amber-500/40'
                        }`}
                      >
                        <PenTool className="w-3 h-3" />
                        <span>
                          {isDrawingThis
                            ? 'Click Canvas to Place Nodes (Done)'
                            : `Custom Nodes (${customNodes.length})`}
                        </span>
                      </button>
                      {customNodes.length > 0 && (
                        <button
                          type="button"
                          onClick={() => handleClearCustomNodes(ctrl.id)}
                          className="px-1.5 py-1 rounded-lg bg-rose-500/15 text-rose-300 border border-rose-500/30 text-[10px]"
                        >
                          Clear Nodes
                        </button>
                      )}
                    </div>
                  </div>

                  {/* Live Visual Segment Allocation Bar */}
                  <div className="space-y-1">
                    <div className="flex h-3 rounded-full overflow-hidden bg-[#060b18] border border-[#1e293b]">
                      {spans.map((sp, sIdx) => {
                        const secObj = activeSections.find((s) => s.id === sp.section_id);
                        const pct = Math.max(
                          8,
                          Math.round((Number(sp.segments || 1) / Math.max(1, totalSpanSegs)) * 100)
                        );
                        const palette = [
                          'bg-[#00f5d4]',
                          'bg-purple-500',
                          'bg-amber-400',
                          'bg-pink-500',
                          'bg-sky-400',
                        ];
                        return (
                          <div
                            key={`${sp.section_id}-${sIdx}`}
                            style={{ width: `${pct}%` }}
                            className={`${
                              palette[sIdx % palette.length]
                            } h-full border-r border-[#040711]`}
                            title={`${sp.segments} segs on ${secObj?.label || sp.section_id}`}
                          />
                        );
                      })}
                    </div>
                    <div className="text-[10px] font-mono text-slate-300">
                      {totalSpanSegs} segs ={' '}
                      {spans
                        .map((sp) => {
                          const secObj = activeSections.find((s) => s.id === sp.section_id);
                          return `${sp.segments} on ${secObj?.label || sp.section_id} (${
                            sp.direction === 'rtl' ? 'Reversed' : 'L→R / Up→Down'
                          })`;
                        })
                        .join(' + ')}
                    </div>
                  </div>

                  {/* Individual Section Span Rows */}
                  <div className="space-y-1.5">
                    {spans.map((sp, sIdx) => (
                      <div
                        key={sIdx}
                        className="grid grid-cols-12 gap-1.5 items-center bg-[#060b18] border border-[#1e293b] rounded-lg p-1.5"
                      >
                        <div className="col-span-5">
                          <select
                            value={sp.section_id}
                            onChange={(e) =>
                              handleUpdateControllerSpan(ctrl.id, sIdx, {
                                section_id: e.target.value,
                              })
                            }
                            className="w-full px-2 py-1 rounded bg-[#0c1324] border border-[#1e293b] text-[11px] text-white font-semibold"
                          >
                            {activeSections.map((sec) => (
                              <option key={sec.id} value={sec.id}>
                                {sec.label} ({sec.wall})
                              </option>
                            ))}
                          </select>
                        </div>

                        <div className="col-span-3 flex items-center gap-1">
                          <input
                            type="number"
                            min="1"
                            max="60"
                            value={sp.segments}
                            onChange={(e) =>
                              handleUpdateControllerSpan(ctrl.id, sIdx, {
                                segments: Math.max(1, Number(e.target.value || 1)),
                              })
                            }
                            className="w-14 px-1.5 py-1 rounded bg-[#0c1324] border border-[#1e293b] text-[11px] font-mono text-cyan-300 font-bold text-center"
                          />
                          <span className="text-[10px] text-slate-400">segs</span>
                        </div>

                        <div className="col-span-3">
                          <select
                            value={sp.direction || 'ltr'}
                            onChange={(e) =>
                              handleUpdateControllerSpan(ctrl.id, sIdx, {
                                direction: e.target.value,
                              })
                            }
                            className="w-full px-1.5 py-1 rounded bg-[#0c1324] border border-[#1e293b] text-[10px] text-amber-200 font-bold"
                          >
                            <option value="ltr">L→R / Up→Down</option>
                            <option value="rtl">R→L / Reversed</option>
                          </select>
                        </div>

                        <div className="col-span-1 flex justify-end">
                          {spans.length > 1 && (
                            <button
                              type="button"
                              onClick={() => handleRemoveControllerSpan(ctrl.id, sIdx)}
                              className="p-1 text-rose-400 hover:text-rose-200"
                              title="Remove span"
                            >
                              <Trash2 className="w-3.5 h-3.5" />
                            </button>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
