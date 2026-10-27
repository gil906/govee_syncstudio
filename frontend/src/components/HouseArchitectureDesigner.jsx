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

const ARCH_STORAGE_KEY = 'govee_house_architectures_v2';

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

export function clearSavedArchitectureOverrides(houseId = null) {
  if (typeof window === 'undefined') return;
  try {
    if (!houseId) {
      window.localStorage.removeItem(ARCH_STORAGE_KEY);
      return;
    }
    const existing = loadSavedArchitectureOverrides();
    delete existing[houseId];
    window.localStorage.setItem(ARCH_STORAGE_KEY, JSON.stringify(existing));
  } catch (e) {
    // ignore
  }
}

export const SECTION_SHAPES = [
  { id: 'triangle_gable', label: '🔺 Triangle Gable Peak', short: 'Triangle Peak' },
  { id: 'steep_gable', label: '📐 Steep A-Frame Peak', short: 'Steep Gable' },
  { id: 'flat_eave', label: '⬛ Square / Flat Eave', short: 'Flat Eave' },
  { id: 'dormer_peak', label: '🏠 2nd-Story Dormer Peak', short: 'Dormer Nook' },
  { id: 'hip_roof', label: '▱ Hip Roof Trapezoid', short: 'Hip Fascia' },
  { id: 'shed_slope', label: '╱ Angled Mono-Slope', short: 'Angled Slope' },
];

export const WALL_OPTIONS = [
  { id: 'front', label: 'Front Facade' },
  { id: 'left', label: 'Left Side Wall' },
  { id: 'right', label: 'Right Side Wall' },
  { id: 'back', label: 'Back Rear Wall' },
];

export const WINDOW_STYLES = [
  { id: 'modern_grid', label: 'Modern Craftsman Grid' },
  { id: 'double_hung', label: 'Double-Hung Sash' },
  { id: 'picture', label: 'Modern Picture' },
  { id: 'arched', label: 'Dormer / Cathedral Arch' },
  { id: 'mullion', label: 'Classic Mullion Grid' },
  { id: 'none', label: 'Solid Wall (No Window)' },
];

export const WIRING_ROUTE_PRESETS = [
  {
    id: 'front_upper_to_lower',
    label: 'Upper Front → Lower Front',
    subtitle: 'Front 2-Tier Only',
  },
  {
    id: 'upper_front_right_back',
    label: 'Upper Front → Right Side → Back',
    subtitle: 'Perimeter Half A',
  },
  {
    id: 'lower_front_left_back',
    label: 'Lower Front → Left Side → Back',
    subtitle: 'Perimeter Half B',
  },
  {
    id: 'full_360_clockwise',
    label: 'Full 360° Clockwise (Front → Right → Back → Left)',
    subtitle: 'Full Perimeter',
  },
  {
    id: 'equal_split_all',
    label: 'Equal Split Across All House Sections',
    subtitle: 'Balanced All Sections',
  },
];

export const ARCHITECTURAL_PRESETS = {
  craftsman_multi_section: {
    preset_style: 'craftsman_multi_section',
    label: '🏘️ House 1 (Left Neighbor): Steep Gable + Flat Eave + Porch & 2-Car Garage',
    description:
      'Exact House 1 from photos: 2nd-story Left Steep Gable (3 narrow windows) + Upper Right Flat Eave (1 window); stepped-forward 1st-story Left Entry Porch Eave + Right 2-Car Garage Flat Eave + Left/Right/Back perimeter eaves.',
    sections: [
      {
        id: 'sec-upper-dormer',
        label: 'Upper Left Steep Gable (3 Windows)',
        shape: 'steep_gable',
        wall: 'front',
        story: 2,
        x_start: 0.04,
        x_end: 0.58,
        eave_height: 0.60,
        peak_height: 0.95,
        peak_offset: 0.50,
        depth_offset: 0.04,
        has_garage: false,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-upper-right-eave',
        label: 'Upper Right Flat Eave (1 Window)',
        shape: 'flat_eave',
        wall: 'front',
        story: 2,
        x_start: 0.58,
        x_end: 0.96,
        eave_height: 0.60,
        peak_height: 0.60,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'double_hung',
      },
      {
        id: 'sec-entry-gable',
        label: 'Lower Left Entry Porch Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        x_start: 0.02,
        x_end: 0.28,
        eave_height: 0.38,
        peak_height: 0.38,
        peak_offset: 0.50,
        depth_offset: 0.14,
        has_door: true,
        has_garage: false,
        window_style: 'none',
      },
      {
        id: 'sec-garage-square',
        label: 'Lower Right 2-Car Garage Flat Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        x_start: 0.28,
        x_end: 0.92,
        eave_height: 0.38,
        peak_height: 0.38,
        peak_offset: 0.50,
        depth_offset: 0.18,
        has_garage: true,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-left-eave',
        label: 'Left Side 2nd-Story Eave',
        shape: 'flat_eave',
        wall: 'left',
        story: 2,
        x_start: 0.04,
        x_end: 0.96,
        eave_height: 0.58,
        peak_height: 0.58,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-right-eave',
        label: 'Right Side 2nd-Story Eave',
        shape: 'flat_eave',
        wall: 'right',
        story: 2,
        x_start: 0.04,
        x_end: 0.96,
        eave_height: 0.58,
        peak_height: 0.58,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-back-eave',
        label: 'Back Rear Hip Roof Eave',
        shape: 'hip_roof',
        wall: 'back',
        story: 2,
        x_start: 0.06,
        x_end: 0.94,
        eave_height: 0.56,
        peak_height: 0.74,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'modern_grid',
      },
    ],
  },

  a_frame_gable: {
    preset_style: 'a_frame_gable',
    label: '🔺 House 2 (My House — Middle): Full Triangle Gable + Garage + Porch Peak',
    description:
      'Exact House 2 (My House, Front Only): 2nd-story Full-Width Symmetric Triangle Gable Peak (4 windows + apex vent); stepped-forward 1st-story Left 2-Car Garage Flat Eave (stone pillars & sconces) + Right Covered Porch Triangle Peak (Craftsman columns on stone pedestals + 4 driveway path lights).',
    sections: [
      {
        id: 'sec-main-gable',
        label: 'Upper 2nd-Story Full-Width Triangle Peak (4 Windows)',
        shape: 'triangle_gable',
        wall: 'front',
        story: 2,
        x_start: 0.05,
        x_end: 0.95,
        eave_height: 0.58,
        peak_height: 0.93,
        peak_offset: 0.50,
        depth_offset: 0.04,
        has_garage: false,
        has_door: false,
        window_style: 'picture',
      },
      {
        id: 'sec-lower-garage-eave',
        label: 'Lower Left 2-Car Garage Flat Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        x_start: 0.05,
        x_end: 0.58,
        eave_height: 0.36,
        peak_height: 0.36,
        peak_offset: 0.50,
        depth_offset: 0.16,
        has_garage: true,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-lower-porch-gable',
        label: 'Lower Right Covered Porch Triangle Peak',
        shape: 'triangle_gable',
        wall: 'front',
        story: 1,
        x_start: 0.58,
        x_end: 0.96,
        eave_height: 0.36,
        peak_height: 0.53,
        peak_offset: 0.50,
        depth_offset: 0.22,
        has_garage: false,
        has_door: true,
        window_style: 'double_hung',
      },
    ],
  },

  two_story_estate: {
    preset_style: 'two_story_estate',
    label: '🏰 House 3 (Right Neighbor): Recessed Dormer + 3-Window Hip Fascia + Full Porch/Garage',
    description:
      'Exact House 3 from photos: 2nd-story Recessed Left Dormer Nook + Right 3-Window Hip Fascia; stepped-forward 1st-story Full-Width Porch & 2-Car Garage Flat Eave (tapered column on stone pedestal) + Left/Right/Back wing eaves.',
    sections: [
      {
        id: 'sec-left-tower-gable',
        label: 'Upper Left Recessed Dormer Nook',
        shape: 'dormer_peak',
        wall: 'front',
        story: 2,
        x_start: 0.06,
        x_end: 0.26,
        eave_height: 0.56,
        peak_height: 0.66,
        peak_offset: 0.50,
        depth_offset: -0.06,
        has_garage: false,
        has_door: false,
        window_style: 'arched',
      },
      {
        id: 'sec-center-flat-fascia',
        label: 'Upper Right 3-Window Hip Fascia',
        shape: 'flat_eave',
        wall: 'front',
        story: 2,
        x_start: 0.24,
        x_end: 0.96,
        eave_height: 0.68,
        peak_height: 0.72,
        peak_offset: 0.50,
        depth_offset: 0.06,
        has_garage: false,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-right-garage-gable',
        label: 'Lower Full-Width Porch & Garage Flat Eave',
        shape: 'flat_eave',
        wall: 'front',
        story: 1,
        x_start: 0.04,
        x_end: 0.98,
        eave_height: 0.38,
        peak_height: 0.38,
        peak_offset: 0.50,
        depth_offset: 0.18,
        has_garage: true,
        has_door: true,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-left-wing',
        label: 'Left Side Upper & Lower Eave',
        shape: 'flat_eave',
        wall: 'left',
        story: 2,
        x_start: 0.04,
        x_end: 0.96,
        eave_height: 0.58,
        peak_height: 0.58,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-right-wing',
        label: 'Right Side Wing Eave',
        shape: 'flat_eave',
        wall: 'right',
        story: 2,
        x_start: 0.04,
        x_end: 0.96,
        eave_height: 0.58,
        peak_height: 0.58,
        peak_offset: 0.50,
        depth_offset: 0.0,
        has_garage: false,
        has_door: false,
        window_style: 'modern_grid',
      },
      {
        id: 'sec-back-wing',
        label: 'Back Rear Wing Eave',
        shape: 'flat_eave',
        wall: 'back',
        story: 2,
        x_start: 0.06,
        x_end: 0.94,
        eave_height: 0.54,
        peak_height: 0.54,
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

export function getRealPhotoPresetKeyForHouse(house, houseIndex = 0) {
  const hId = (house?.id || '').toLowerCase();
  if (hId === 'house-1' || houseIndex === 0) return 'craftsman_multi_section';
  if (hId === 'house-2' || houseIndex === 1) return 'a_frame_gable';
  if (hId === 'house-3' || houseIndex === 2) return 'two_story_estate';
  const keys = ['craftsman_multi_section', 'a_frame_gable', 'two_story_estate'];
  return keys[houseIndex % keys.length];
}

/**
 * Resolves the effective architecture for a house, combining:
 * 1. User-saved localStorage overrides (v2, if any)
 * 2. Backend `house.architecture` (if populated and already 2-story photo-accurate or custom)
 * 3. Exact 3 Real House Models (`craftsman_multi_section`, `a_frame_gable`, `two_story_estate`)
 */
export function getEffectiveHouseArchitecture(house, houseIndex = 0) {
  const savedMap = loadSavedArchitectureOverrides();
  const localArch = savedMap[house?.id]?.architecture;

  if (localArch && Array.isArray(localArch.sections) && localArch.sections.length > 0) {
    return {
      preset_style: localArch.preset_style || 'custom',
      label: localArch.label || 'Custom Architecture',
      sections: localArch.sections.map((s, i) => normalizeSection(s, i)),
    };
  }

  const backendArch =
    house?.architecture &&
    Array.isArray(house.architecture.sections) &&
    house.architecture.sections.length > 0
      ? house.architecture
      : null;

  // Use backendArch if it has both story=2 and story=1 sections or is explicitly custom
  if (backendArch) {
    const hasStory2 = backendArch.sections.some((s) => Number(s.story) === 2);
    const hasStory1 = backendArch.sections.some((s) => Number(s.story) === 1);
    if ((hasStory2 && hasStory1) || backendArch.preset_style === 'custom') {
      return {
        preset_style: backendArch.preset_style || 'custom',
        label: backendArch.label || 'Custom Architecture',
        sections: backendArch.sections.map((s, i) => normalizeSection(s, i)),
      };
    }
  }

  // Exact fallback by house ID or street index
  const presetKey = getRealPhotoPresetKeyForHouse(house, houseIndex);
  const preset = ARCHITECTURAL_PRESETS[presetKey] || ARCHITECTURAL_PRESETS.a_frame_gable;
  return {
    preset_style: preset.preset_style,
    label: preset.label,
    sections: preset.sections.map((s, i) => normalizeSection(s, i)),
  };
}

function distributeSegmentsEvenly(targetSections, segCount, direction = 'ltr') {
  if (!targetSections || targetSections.length === 0) return [];
  const chosen = targetSections.slice(0, Math.max(1, Math.min(targetSections.length, segCount)));
  const basePerSec = Math.max(1, Math.floor(segCount / chosen.length));
  let remainder = Math.max(0, segCount - basePerSec * chosen.length);
  return chosen.map((sec) => {
    const extra = remainder > 0 ? 1 : 0;
    if (remainder > 0) remainder -= 1;
    return {
      section_id: sec.id,
      wall: sec.wall || 'front',
      segments: Math.max(1, basePerSec + extra),
      direction,
    };
  });
}

/**
 * Builds a 1-tap wiring route preset (`WIRING_ROUTE_PRESETS`) for a controller on a house architecture.
 */
export function buildWiringRoutePresetSpans(routeId, architecture, segCount = 9) {
  const sections = architecture?.sections || [];
  if (!sections.length) return [];

  const upperFront = sections.filter((s) => s.wall === 'front' && Number(s.story) === 2);
  const lowerFront = sections.filter((s) => s.wall === 'front' && Number(s.story) !== 2);
  const allFront = sections.filter((s) => s.wall === 'front');
  const leftSecs = sections.filter((s) => s.wall === 'left');
  const rightSecs = sections.filter((s) => s.wall === 'right');
  const backSecs = sections.filter((s) => s.wall === 'back');

  let pool = [];
  if (routeId === 'front_upper_to_lower') {
    pool = [...upperFront, ...lowerFront];
  } else if (routeId === 'upper_front_right_back') {
    pool = [...upperFront, ...rightSecs, ...backSecs];
  } else if (routeId === 'lower_front_left_back') {
    pool = [...lowerFront, ...leftSecs, ...backSecs];
  } else if (routeId === 'full_360_clockwise') {
    pool = [...upperFront, ...lowerFront, ...rightSecs, ...backSecs, ...leftSecs];
  } else if (routeId === 'equal_split_all') {
    pool = [...sections];
  }

  if (pool.length === 0) {
    pool = allFront.length > 0 ? allFront : sections;
  }

  return distributeSegmentsEvenly(pool, Math.max(1, Number(segCount || 9)), 'ltr');
}

/**
 * Builds photo-accurate default controller `section_spans` across Upper Front, Lower Front, and Sides/Back.
 */
export function buildPhotoDefaultControllerSpans(
  controller,
  architecture,
  ctrlIndex = 0,
  totalControllers = 1
) {
  const segCount = Math.max(1, Number(controller?.segment_count || 9));
  const sections = architecture?.sections || [];
  const upperFront = sections.filter((s) => s.wall === 'front' && Number(s.story) === 2);
  const lowerFront = sections.filter((s) => s.wall === 'front' && Number(s.story) !== 2);
  const sideBack = sections.filter((s) => s.wall !== 'front');
  const allFront = [...upperFront, ...lowerFront];
  const dir = controller?.reverse_direction ? 'rtl' : 'ltr';

  if (totalControllers <= 1) {
    // Single controller (e.g. House 2 My House — 9 segs across Upper Gable + Lower Garage + Lower Porch)
    const pool = allFront.length > 0 ? allFront : sections;
    if (
      architecture?.preset_style === 'a_frame_gable' &&
      pool.length === 3 &&
      segCount >= 5
    ) {
      const upperSegs = Math.max(2, Math.round(segCount * 0.55));
      const rem = Math.max(2, segCount - upperSegs);
      const garageSegs = Math.max(1, Math.ceil(rem / 2));
      const porchSegs = Math.max(1, rem - garageSegs);
      return [
        { section_id: pool[0].id, wall: pool[0].wall, segments: upperSegs, direction: dir },
        { section_id: pool[1].id, wall: pool[1].wall, segments: garageSegs, direction: dir },
        { section_id: pool[2].id, wall: pool[2].wall, segments: porchSegs, direction: dir },
      ];
    }
    return distributeSegmentsEvenly(pool, segCount, dir);
  }

  if (totalControllers === 2) {
    if (ctrlIndex === 0) {
      return distributeSegmentsEvenly(allFront.length > 0 ? allFront : sections, segCount, dir);
    }
    return distributeSegmentsEvenly(
      sideBack.length > 0 ? sideBack : lowerFront.length > 0 ? lowerFront : sections,
      segCount,
      dir
    );
  }

  // 3+ controllers (e.g. House 1 & House 3: Ctrl 0 = Upper Front, Ctrl 1 = Lower Front, Ctrl 2 = Sides & Back)
  if (ctrlIndex === 0 && upperFront.length > 0) {
    return distributeSegmentsEvenly(upperFront, segCount, dir);
  }
  if (ctrlIndex === 1 && lowerFront.length > 0) {
    return distributeSegmentsEvenly(lowerFront, segCount, dir);
  }
  if (sideBack.length > 0) {
    return distributeSegmentsEvenly(sideBack, segCount, dir);
  }
  return distributeSegmentsEvenly(allFront.length > 0 ? allFront : sections, segCount, dir);
}

/**
 * Resolves `section_spans` and `custom_nodes` for a controller on a given house architecture.
 */
export function getEffectiveControllerSpans(
  controller,
  architecture,
  ctrlIndex = 0,
  totalControllers = 1
) {
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

  const validIds = new Set(sections.map((s) => s.id));

  if (Array.isArray(savedCtrl?.section_spans) && savedCtrl.section_spans.length > 0) {
    return savedCtrl.section_spans.map((sp, idx) => {
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
  }

  if (Array.isArray(controller?.section_spans) && controller.section_spans.length > 0) {
    const allMatch = controller.section_spans.every((sp) => validIds.has(sp.section_id));
    // Avoid legacy 1-span fallback when the house has multiple 2-story photo sections on a single controller
    const isLegacySingleSpan =
      totalControllers === 1 &&
      sections.length >= 3 &&
      controller.section_spans.length === 1;
    if (allMatch && !isLegacySingleSpan) {
      return controller.section_spans.map((sp, idx) => {
        const matchedSec = sections.find((s) => s.id === sp.section_id) || sections[0];
        return {
          section_id: matchedSec?.id || `sec-${idx + 1}`,
          wall: sp.wall || matchedSec?.wall || 'front',
          segments: Math.max(1, Number(sp.segments || segCount)),
          direction: sp.direction === 'rtl' ? 'rtl' : 'ltr',
        };
      });
    }
  }

  return buildPhotoDefaultControllerSpans(controller, architecture, ctrlIndex, totalControllers);
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
  const zoneMode = anim?.zone_mode || 'front_street_sync';

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
          story: 1,
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

    const spans = getEffectiveControllerSpans(ctrl, arch, cIdx, controllers.length);
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
            // Respect 3-House Sync Alignment mode (`zoneMode`)
            let u = (houseSegCursor + localIdx) / totalHouseSegs;
            if (zoneMode === 'front_street_sync') {
              // Both Upper (story 2) and Lower (story 1) front sections lock to horizontal X!
              u = Math.max(0, Math.min(1, pt.x + 0.5));
            } else if (zoneMode === 'depth_front_to_back') {
              u = Math.max(0, Math.min(1, (0.38 - pt.z) / 0.65));
            } else if (zoneMode === 'perimeter_360') {
              const angle = Math.atan2(pt.z, pt.x);
              u = (angle + Math.PI) / (2 * Math.PI);
            }
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
            if (zoneMode === 'front_only_quiet_sides' && (sec.wall || 'front') !== 'front') {
              rgb = [
                Math.round(rgb[0] * 0.35),
                Math.round(rgb[1] * 0.35),
                Math.round(rgb[2] * 0.35),
              ];
            }
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
          story: Number(sec.story) === 2 ? 2 : 1,
          uInSection: pt.t ?? 0.5,
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

        // Base core house volume (so side/rear walls always form a cohesive 2-story 3D building)
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

        const story1FrontSecs = targetFrontSecs.filter((s) => Number(s.story) !== 2);
        const story2FrontSecs = targetFrontSecs.filter((s) => Number(s.story) === 2);
        const lowerStoryRoofY =
          story1FrontSecs.length > 0
            ? Math.max(...story1FrontSecs.map((s) => s.eave_height))
            : 0.37;
        const maxUpperEaveY =
          story2FrontSecs.length > 0
            ? Math.max(...story2FrontSecs.map((s) => s.eave_height))
            : Math.max(...targetFrontSecs.map((s) => s.eave_height));

        // Cohesive 2-story core side & rear enclosure in 3D mode
        if (!is2D) {
          const coreX0 = houseCenterX - 0.46;
          const coreX1 = houseCenterX + 0.46;
          const coreZFront = 0.25;
          const coreZBack = -0.24;
          polygons.push({
            type: 'core_side_left',
            houseId: house.id,
            pts3d: [
              { x: coreX0, y: 0, z: coreZBack },
              { x: coreX0, y: 0, z: coreZFront },
              { x: coreX0, y: maxUpperEaveY, z: coreZFront },
              { x: coreX0, y: maxUpperEaveY, z: coreZBack },
            ],
            fill: '#0d172a',
            stroke: '#23324a',
            depthBias: -0.06,
          });
          polygons.push({
            type: 'core_side_right',
            houseId: house.id,
            pts3d: [
              { x: coreX1, y: 0, z: coreZFront },
              { x: coreX1, y: 0, z: coreZBack },
              { x: coreX1, y: maxUpperEaveY, z: coreZBack },
              { x: coreX1, y: maxUpperEaveY, z: coreZFront },
            ],
            fill: '#0f1b30',
            stroke: '#23324a',
            depthBias: -0.06,
          });
          polygons.push({
            type: 'core_back',
            houseId: house.id,
            pts3d: [
              { x: coreX0, y: 0, z: coreZBack },
              { x: coreX1, y: 0, z: coreZBack },
              { x: coreX1, y: maxUpperEaveY, z: coreZBack },
              { x: coreX0, y: maxUpperEaveY, z: coreZBack },
            ],
            fill: '#091120',
            stroke: '#1e293b',
            depthBias: -0.12,
          });
        }

        targetFrontSecs.forEach((sec) => {
          const isSecSelected = selectedSectionId === sec.id;
          const x0 = houseCenterX + (sec.x_start - 0.5);
          const x1 = houseCenterX + (sec.x_end - 0.5);
          const xm = x0 + (x1 - x0) * (sec.peak_offset ?? 0.5);
          // True 2-story vertical stacking: story 2 starts at the 1st-story roofline (0.36..0.38)!
          const baseY =
            Number(sec.story) === 2 && story1FrontSecs.length > 0
              ? Math.min(sec.eave_height - 0.12, lowerStoryRoofY)
              : 0;
          const eaveY = sec.eave_height;
          const peakY = sec.shape === 'flat_eave' ? eaveY : Math.max(eaveY, sec.peak_height);
          const zFront = 0.24 + (sec.depth_offset || 0) * 0.45;
          const zBack =
            Number(sec.story) === 2
              ? sec.shape === 'dormer_peak'
                ? 0.04
                : -0.24
              : 0.18;

          // Driveway apron for garage sections
          if (sec.has_garage && !is2D) {
            const driveX0 =
              sec.id === 'sec-right-garage-gable' ? x0 + (x1 - x0) * 0.36 : x0 + 0.01;
            const driveX1 = x1 - 0.01;
            polygons.push({
              type: 'driveway',
              pts3d: [
                { x: driveX0, y: 0.002, z: zFront },
                { x: driveX1, y: 0.002, z: zFront },
                { x: driveX1, y: 0.002, z: 0.43 },
                { x: driveX0, y: 0.002, z: 0.43 },
              ],
              fill: '#101826',
              stroke: 'rgba(148, 163, 184, 0.24)',
              depthBias: -0.3,
            });
          }

          // Front walkway for door sections
          if (sec.has_door && !is2D) {
            const doorX =
              sec.id === 'sec-right-garage-gable'
                ? x0 + (x1 - x0) * 0.20
                : (x0 + x1) * 0.5;
            polygons.push({
              type: 'walkway',
              pts3d: [
                { x: doorX - 0.055, y: 0.003, z: zFront },
                { x: doorX + 0.055, y: 0.003, z: zFront },
                { x: doorX + 0.045, y: 0.003, z: 0.43 },
                { x: doorX - 0.045, y: 0.003, z: 0.43 },
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
              fill: '#111c32',
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
              fill: '#132038',
              stroke: isSecSelected ? '#00f5d4' : '#26354d',
              depthBias: -0.02,
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
            houseCenterX,
            archPreset: arch.preset_style,
            x0,
            x1,
            xm,
            baseY,
            eaveY,
            peakY,
            zFront,
            pts3d: frontFacePts,
            fill:
              Number(sec.story) === 2
                ? '#1b2b4a'
                : sec.has_garage
                ? '#16243d'
                : '#182742',
            stroke: isSecSelected ? '#00f5d4' : '#435b82',
            depthBias: Number(sec.story) === 1 ? 0.06 : 0.03,
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
              stroke: isSecSelected ? '#00f5d4' : '#47628c',
              depthBias: Number(sec.story) === 1 ? 0.055 : 0.025,
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
              stroke: isSecSelected ? '#00f5d4' : '#47628c',
              depthBias: Number(sec.story) === 1 ? 0.055 : 0.025,
            });
          } else if (sec.shape === 'hip_roof') {
            const span = x1 - x0;
            const h0 = x0 + span * 0.22;
            const h1 = x1 - span * 0.22;
            const zRidge = (zFront + zBack) * 0.5;
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
              stroke: isSecSelected ? '#00f5d4' : '#47628c',
              depthBias: 0.04,
            });
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
              stroke: isSecSelected ? '#00f5d4' : '#47628c',
              depthBias: 0.03,
            });
          } else {
            // Flat / Hip fascia roof deck (for 1st-story garage/porch eaves, slopes slightly up toward 2nd-story wall)
            const roofBackY =
              Number(sec.story) === 1 ? eaveY + 0.045 : Math.max(eaveY, sec.peak_height);
            polygons.push({
              type: 'roof_flat',
              secId: sec.id,
              houseId: house.id,
              pts3d: [
                { x: x0 - overhang, y: eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: eaveY, z: zFront + overhang },
                { x: x1 + overhang, y: roofBackY, z: zBack },
                { x: x0 - overhang, y: roofBackY, z: zBack },
              ],
              fill: Number(sec.story) === 1 ? '#1a2740' : '#1f304f',
              stroke: isSecSelected ? '#00f5d4' : '#4a648f',
              depthBias: Number(sec.story) === 1 ? 0.05 : 0.03,
            });
          }
        });
      });

      // Helper to draw a framed window with mullions/grids
      const drawFramedWindow = (wx0, wx1, wy0, wy1, zF, style = 'modern_grid') => {
        const wCorners = [
          project3D(wx0, wy0, zF),
          project3D(wx1, wy0, zF),
          project3D(wx1, wy1, zF),
          project3D(wx0, wy1, zF),
        ];
        ctx.beginPath();
        wCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
        ctx.closePath();
        ctx.fillStyle = 'rgba(251, 191, 36, 0.25)';
        ctx.fill();
        ctx.strokeStyle = 'rgba(241, 245, 249, 0.85)';
        ctx.lineWidth = 1.25;
        ctx.stroke();

        const midX = (wx0 + wx1) * 0.5;
        const midY = (wy0 + wy1) * 0.5;
        if (style === 'modern_grid' || style === 'mullion' || style === 'double_hung') {
          const hm0 = project3D(wx0, midY, zF);
          const hm1 = project3D(wx1, midY, zF);
          ctx.beginPath();
          ctx.moveTo(hm0.x, hm0.y);
          ctx.lineTo(hm1.x, hm1.y);
          if (style !== 'double_hung') {
            const vm0 = project3D(midX, wy0, zF);
            const vm1 = project3D(midX, wy1, zF);
            ctx.moveTo(vm0.x, vm0.y);
            ctx.lineTo(vm1.x, vm1.y);
          }
          ctx.strokeStyle = 'rgba(241, 245, 249, 0.55)';
          ctx.lineWidth = 0.9;
          ctx.stroke();
        }
      };

      // Helper to draw a Craftsman column on a stone-veneer pedestal
      const drawCraftsmanColumnWithPedestal = (colX, baseY, topY, zF, hasSconce = false) => {
        const pedH = (topY - baseY) * 0.36;
        const pedW = 0.032;
        const colW = 0.018;

        // Stone-veneer pedestal base
        const pedCorners = [
          project3D(colX - pedW, baseY, zF),
          project3D(colX + pedW, baseY, zF),
          project3D(colX + pedW * 0.92, baseY + pedH, zF),
          project3D(colX - pedW * 0.92, baseY + pedH, zF),
        ];
        ctx.beginPath();
        pedCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
        ctx.closePath();
        ctx.fillStyle = '#334155';
        ctx.fill();
        ctx.strokeStyle = '#94a3b8';
        ctx.lineWidth = 1;
        ctx.stroke();

        // Tapered white Craftsman column shaft
        const shaftCorners = [
          project3D(colX - colW, baseY + pedH, zF),
          project3D(colX + colW, baseY + pedH, zF),
          project3D(colX + colW * 0.78, topY, zF),
          project3D(colX - colW * 0.78, topY, zF),
        ];
        ctx.beginPath();
        shaftCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
        ctx.closePath();
        ctx.fillStyle = '#e2e8f0';
        ctx.fill();
        ctx.strokeStyle = '#64748b';
        ctx.lineWidth = 0.9;
        ctx.stroke();

        if (hasSconce) {
          const sp = project3D(colX, baseY + pedH + (topY - baseY) * 0.25, zF + 0.005);
          const sr = Math.max(5, sp.scale * 0.028);
          const sGrad = ctx.createRadialGradient(sp.x, sp.y, 0.5, sp.x, sp.y, sr);
          sGrad.addColorStop(0, 'rgba(253, 224, 71, 0.95)');
          sGrad.addColorStop(0.5, 'rgba(251, 146, 60, 0.45)');
          sGrad.addColorStop(1, 'rgba(251, 146, 60, 0)');
          ctx.beginPath();
          ctx.arc(sp.x, sp.y, sr, 0, Math.PI * 2);
          ctx.fillStyle = sGrad;
          ctx.fill();
        }
      };

      // Helper to draw a 2-car garage door with 4 top window panes & stone pillars + warm carriage sconces
      const drawTwoCarGarage = (gx0, gx1, baseY, gy1, zF, withStonePillars = true) => {
        if (withStonePillars) {
          const pilW = 0.026;
          [gx0 - pilW * 0.6, gx1 + pilW * 0.6].forEach((px) => {
            const pCorners = [
              project3D(px - pilW * 0.5, baseY, zF),
              project3D(px + pilW * 0.5, baseY, zF),
              project3D(px + pilW * 0.5, gy1 * 0.55, zF),
              project3D(px - pilW * 0.5, gy1 * 0.55, zF),
            ];
            ctx.beginPath();
            pCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
            ctx.closePath();
            ctx.fillStyle = '#334155';
            ctx.fill();
            ctx.strokeStyle = '#64748b';
            ctx.lineWidth = 0.9;
            ctx.stroke();

            // Warm amber carriage sconce above stone pillar
            const sp = project3D(px, gy1 * 0.72, zF + 0.004);
            const sr = Math.max(5.5, sp.scale * 0.03);
            const sGrad = ctx.createRadialGradient(sp.x, sp.y, 0.5, sp.x, sp.y, sr);
            sGrad.addColorStop(0, 'rgba(254, 240, 138, 0.95)');
            sGrad.addColorStop(0.5, 'rgba(245, 158, 11, 0.45)');
            sGrad.addColorStop(1, 'rgba(245, 158, 11, 0)');
            ctx.beginPath();
            ctx.arc(sp.x, sp.y, sr, 0, Math.PI * 2);
            ctx.fillStyle = sGrad;
            ctx.fill();
          });
        }

        const gCorners = [
          project3D(gx0, baseY, zF),
          project3D(gx1, baseY, zF),
          project3D(gx1, gy1, zF),
          project3D(gx0, gy1, zF),
        ];
        ctx.beginPath();
        gCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
        ctx.closePath();
        ctx.fillStyle = '#1e293b';
        ctx.fill();
        ctx.strokeStyle = '#cbd5e1';
        ctx.lineWidth = 1.3;
        ctx.stroke();

        // Horizontal garage door panel seams
        for (let row = 1; row <= 3; row += 1) {
          const py = baseY + (gy1 - baseY) * (row / 4);
          const pl = project3D(gx0, py, zF);
          const pr = project3D(gx1, py, zF);
          ctx.beginPath();
          ctx.moveTo(pl.x, pl.y);
          ctx.lineTo(pr.x, pr.y);
          ctx.strokeStyle = 'rgba(148, 163, 184, 0.45)';
          ctx.lineWidth = 0.9;
          ctx.stroke();
        }

        // 4 top window panes across top row of 2-car garage door
        for (let pane = 0; pane < 4; pane += 1) {
          const px0 = gx0 + (gx1 - gx0) * ((pane + 0.1) / 4);
          const px1 = gx0 + (gx1 - gx0) * ((pane + 0.9) / 4);
          const py0 = baseY + (gy1 - baseY) * 0.77;
          const py1 = gy1 - 0.016;
          const wc = [
            project3D(px0, py0, zF),
            project3D(px1, py0, zF),
            project3D(px1, py1, zF),
            project3D(px0, py1, zF),
          ];
          ctx.beginPath();
          wc.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
          ctx.closePath();
          ctx.fillStyle = 'rgba(251, 191, 36, 0.42)';
          ctx.fill();
          ctx.strokeStyle = 'rgba(226, 232, 240, 0.7)';
          ctx.lineWidth = 0.8;
          ctx.stroke();
        }
      };

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

      // Render sorted 3D architectural polygons + authentic photo facade details
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

          // Subtle horizontal Craftsman lap-siding lines on 2nd-story walls
          if (Number(sec.story) === 2 && wallH > 0.12) {
            for (let sRow = 1; sRow <= 3; sRow += 1) {
              const sy = poly.baseY + wallH * (sRow / 4);
              const sl = project3D(poly.x0 + 0.01, sy, zF);
              const sr = project3D(poly.x1 - 0.01, sy, zF);
              ctx.beginPath();
              ctx.moveTo(sl.x, sl.y);
              ctx.lineTo(sr.x, sr.y);
              ctx.strokeStyle = 'rgba(148, 163, 184, 0.14)';
              ctx.lineWidth = 0.8;
              ctx.stroke();
            }
          }

          // Vertical / Louvered Gable Vent Slot near triangle apex (matching House 1 & House 2 photos!)
          if (
            (sec.shape === 'triangle_gable' ||
              sec.shape === 'steep_gable' ||
              sec.shape === 'dormer_peak') &&
            poly.peakY - poly.eaveY > 0.12
          ) {
            const ventCenterY = poly.eaveY + (poly.peakY - poly.eaveY) * 0.56;
            const vw = 0.016;
            const vh = Math.min(0.075, (poly.peakY - poly.eaveY) * 0.34);
            const vCorners = [
              project3D(poly.xm - vw, ventCenterY - vh * 0.5, zF),
              project3D(poly.xm + vw, ventCenterY - vh * 0.5, zF),
              project3D(poly.xm + vw, ventCenterY + vh * 0.5, zF),
              project3D(poly.xm - vw, ventCenterY + vh * 0.5, zF),
            ];
            ctx.beginPath();
            vCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
            ctx.closePath();
            ctx.fillStyle = '#09101f';
            ctx.fill();
            ctx.strokeStyle = 'rgba(226, 232, 240, 0.78)';
            ctx.lineWidth = 1.1;
            ctx.stroke();
          }

          // Photo-Exact Section Architectural Features:
          if (sec.id === 'sec-upper-dormer' || (poly.archPreset === 'craftsman_multi_section' && Number(sec.story) === 2 && sec.shape === 'steep_gable')) {
            // House 1 Upper Left Steep Gable: 3 narrow vertical rectangular windows
            const wy0 = poly.baseY + wallH * 0.22;
            const wy1 = poly.baseY + wallH * 0.82;
            const ww = spanW * 0.14;
            [0.24, 0.50, 0.76].forEach((u) => {
              const cx = poly.x0 + spanW * u;
              drawFramedWindow(cx - ww * 0.5, cx + ww * 0.5, wy0, wy1, zF, 'modern_grid');
            });
          } else if (sec.id === 'sec-upper-right-eave') {
            // House 1 Upper Right Flat Eave: 1 wider window
            const wy0 = poly.baseY + wallH * 0.24;
            const wy1 = poly.baseY + wallH * 0.78;
            const cx = (poly.x0 + poly.x1) * 0.5;
            const ww = spanW * 0.34;
            drawFramedWindow(cx - ww * 0.5, cx + ww * 0.5, wy0, wy1, zF, 'double_hung');
          } else if (sec.id === 'sec-main-gable' || (poly.archPreset === 'a_frame_gable' && Number(sec.story) === 2)) {
            // House 2 (My House) Upper 2nd-Story Full-Width Triangle Peak: 4 evenly spaced vertical rectangular windows
            const wy0 = poly.baseY + wallH * 0.22;
            const wy1 = poly.baseY + wallH * 0.82;
            const ww = spanW * 0.115;
            [0.18, 0.39, 0.61, 0.82].forEach((u) => {
              const cx = poly.x0 + spanW * u;
              drawFramedWindow(cx - ww * 0.5, cx + ww * 0.5, wy0, wy1, zF, 'modern_grid');
            });
          } else if (sec.id === 'sec-left-tower-gable') {
            // House 3 Upper Left Recessed Dormer Nook: 1 vertical window
            const wy0 = poly.baseY + wallH * 0.20;
            const wy1 = poly.baseY + wallH * 0.82;
            const cx = (poly.x0 + poly.x1) * 0.5;
            const ww = spanW * 0.42;
            drawFramedWindow(cx - ww * 0.5, cx + ww * 0.5, wy0, wy1, zF, 'arched');
          } else if (sec.id === 'sec-center-flat-fascia' || (poly.archPreset === 'two_story_estate' && Number(sec.story) === 2 && sec.shape === 'flat_eave')) {
            // House 3 Upper Right 3-Window Hip Fascia: 3 evenly spaced vertical windows
            const wy0 = poly.baseY + wallH * 0.22;
            const wy1 = poly.baseY + wallH * 0.78;
            const ww = spanW * 0.16;
            [0.22, 0.50, 0.78].forEach((u) => {
              const cx = poly.x0 + spanW * u;
              drawFramedWindow(cx - ww * 0.5, cx + ww * 0.5, wy0, wy1, zF, 'modern_grid');
            });
          } else if (sec.id === 'sec-lower-porch-gable') {
            // House 2 Lower Right Covered Porch Triangle Peak: white Craftsman columns on stone pedestals + warm entry door + window
            drawCraftsmanColumnWithPedestal(poly.x0 + spanW * 0.08, poly.baseY, poly.eaveY, zF + 0.005, false);
            drawCraftsmanColumnWithPedestal(poly.x1 - spanW * 0.08, poly.baseY, poly.eaveY, zF + 0.005, true);

            // Warm front entry door inside covered porch
            const dCenter = poly.x0 + spanW * 0.34;
            const dw = spanW * 0.20;
            const dh = wallH * 0.76;
            const dCorners = [
              project3D(dCenter - dw * 0.5, poly.baseY, zF),
              project3D(dCenter + dw * 0.5, poly.baseY, zF),
              project3D(dCenter + dw * 0.5, poly.baseY + dh, zF),
              project3D(dCenter - dw * 0.5, poly.baseY + dh, zF),
            ];
            ctx.beginPath();
            dCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
            ctx.closePath();
            ctx.fillStyle = '#451a03';
            ctx.fill();
            ctx.strokeStyle = '#fbbf24';
            ctx.lineWidth = 1.2;
            ctx.stroke();

            // Porch window next to door
            const wxCenter = poly.x0 + spanW * 0.68;
            drawFramedWindow(
              wxCenter - spanW * 0.12,
              wxCenter + spanW * 0.12,
              poly.baseY + wallH * 0.28,
              poly.baseY + wallH * 0.76,
              zF,
              'double_hung'
            );
          } else if (sec.id === 'sec-right-garage-gable') {
            // House 3 Lower Full-Width Porch (left) & 2-Car Garage (right) Flat Eave
            drawCraftsmanColumnWithPedestal(poly.x0 + spanW * 0.07, poly.baseY, poly.eaveY, zF + 0.005, true);
            drawCraftsmanColumnWithPedestal(poly.x0 + spanW * 0.34, poly.baseY, poly.eaveY, zF + 0.005, false);

            // Left porch door & window
            const dCenter = poly.x0 + spanW * 0.18;
            const dw = spanW * 0.085;
            const dh = wallH * 0.74;
            const dCorners = [
              project3D(dCenter - dw * 0.5, poly.baseY, zF),
              project3D(dCenter + dw * 0.5, poly.baseY, zF),
              project3D(dCenter + dw * 0.5, poly.baseY + dh, zF),
              project3D(dCenter - dw * 0.5, poly.baseY + dh, zF),
            ];
            ctx.beginPath();
            dCorners.forEach((p, i) => (i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)));
            ctx.closePath();
            ctx.fillStyle = '#451a03';
            ctx.fill();
            ctx.strokeStyle = '#fbbf24';
            ctx.lineWidth = 1.2;
            ctx.stroke();

            // Right 2-car garage door
            drawTwoCarGarage(
              poly.x0 + spanW * 0.42,
              poly.x1 - spanW * 0.06,
              poly.baseY,
              poly.baseY + wallH * 0.80,
              zF,
              true
            );
          } else {
            // Standard Garage / Entry Door / Window rendering for other sections
            if (sec.has_garage && Number(sec.story) === 1) {
              drawTwoCarGarage(
                poly.x0 + spanW * 0.10,
                poly.x1 - spanW * 0.10,
                poly.baseY,
                poly.baseY + wallH * 0.80,
                zF,
                true
              );
            }

            if (sec.has_door && Number(sec.story) === 1) {
              drawCraftsmanColumnWithPedestal(
                poly.x0 + spanW * 0.14,
                poly.baseY,
                poly.eaveY,
                zF + 0.004,
                true
              );
              const dCenter = poly.x0 + spanW * (sec.has_garage ? 0.82 : 0.52);
              const dw = Math.min(0.085, spanW * 0.28);
              const dh = wallH * 0.74;
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
            }

            if (sec.window_style !== 'none' && !sec.has_garage) {
              const winCenter =
                sec.has_door && Number(sec.story) === 1
                  ? poly.x0 + spanW * 0.72
                  : (poly.x0 + poly.x1) * 0.5;
              const ww = Math.min(0.15, spanW * 0.34);
              const wy0 = poly.baseY + wallH * 0.25;
              const wy1 = poly.baseY + wallH * 0.76;
              drawFramedWindow(
                winCenter - ww * 0.5,
                winCenter + ww * 0.5,
                wy0,
                wy1,
                zF,
                sec.window_style
              );
            }
          }
        }
      });

      // Helper to project a 3D puck or side-wing point, including 2D Side/Back Wing Indicator Strips!
      const projectSectionPoint = (houseCenterX, wall, uInSec, wx, wy, wz) => {
        if (is2D && wall !== 'front') {
          if (wall === 'left') {
            const stripX = houseCenterX - 0.50;
            const stripY = 0.22 + (1 - uInSec) * 0.56;
            return project3D(stripX, stripY, 0.3);
          }
          if (wall === 'right') {
            const stripX = houseCenterX + 0.50;
            const stripY = 0.22 + (1 - uInSec) * 0.56;
            return project3D(stripX, stripY, 0.3);
          }
          if (wall === 'back') {
            const stripX = houseCenterX + (uInSec - 0.5) * 0.76;
            const stripY = 0.97;
            return project3D(stripX, stripY, 0.3);
          }
        }
        return project3D(wx, wy, wz);
      };

      // 4. Render Soffit Downward Wall-Wash Cones, Roofline Tracks, LED Pucks & Labels
      houseRenderItems.forEach((item) => {
        const { house, effectiveIdx, houseCenterX, arch, sections, pucks } = item;

        // House 2 (My House — a_frame_gable): Render 4 glowing white driveway path lights along left driveway edge!
        if (arch.preset_style === 'a_frame_gable' || house.id === 'house-2') {
          const pathX = houseCenterX - 0.43;
          [0, 1, 2, 3].forEach((bIdx) => {
            const bz = 0.32 + bIdx * 0.045;
            const by = is2D ? 0.02 + bIdx * 0.035 : 0.022;
            const bx = is2D ? pathX - bIdx * 0.015 : pathX;
            const bp = project3D(bx, by, bz);
            const groundP = project3D(bx, 0, bz);
            const haloR = Math.max(5.5, bp.scale * 0.028);
            const gGrad = ctx.createRadialGradient(bp.x, bp.y, 0.5, bp.x, bp.y, haloR);
            gGrad.addColorStop(0, 'rgba(255, 255, 255, 0.95)');
            gGrad.addColorStop(0.45, 'rgba(186, 230, 253, 0.45)');
            gGrad.addColorStop(1, 'rgba(186, 230, 253, 0)');
            ctx.beginPath();
            ctx.arc(bp.x, bp.y, haloR, 0, Math.PI * 2);
            ctx.fillStyle = gGrad;
            ctx.fill();

            // Bollard stem & white cap
            ctx.beginPath();
            ctx.moveTo(groundP.x, groundP.y);
            ctx.lineTo(bp.x, bp.y);
            ctx.strokeStyle = '#94a3b8';
            ctx.lineWidth = 1.4;
            ctx.stroke();

            ctx.beginPath();
            ctx.arc(bp.x, bp.y, 2.2, 0, Math.PI * 2);
            ctx.fillStyle = '#ffffff';
            ctx.fill();
          });
        }

        // In 2D Front Elevation mode, draw subtle Side/Back Wing Indicator Strips for Houses 1 & 3
        if (is2D) {
          const hasLeft = sections.some((s) => s.wall === 'left');
          const hasRight = sections.some((s) => s.wall === 'right');
          const hasBack = sections.some((s) => s.wall === 'back');

          if (hasLeft) {
            const p0 = project3D(houseCenterX - 0.50, 0.20, 0.3);
            const p1 = project3D(houseCenterX - 0.50, 0.80, 0.3);
            ctx.save();
            ctx.setLineDash([3, 3]);
            ctx.strokeStyle = 'rgba(56, 189, 248, 0.45)';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(p0.x, p0.y);
            ctx.lineTo(p1.x, p1.y);
            ctx.stroke();
            ctx.font = '700 8.5px JetBrains Mono, monospace';
            ctx.fillStyle = '#38bdf8';
            ctx.textAlign = 'center';
            ctx.fillText('L-WING', p1.x, p1.y - 5);
            ctx.restore();
          }

          if (hasRight) {
            const p0 = project3D(houseCenterX + 0.50, 0.20, 0.3);
            const p1 = project3D(houseCenterX + 0.50, 0.80, 0.3);
            ctx.save();
            ctx.setLineDash([3, 3]);
            ctx.strokeStyle = 'rgba(56, 189, 248, 0.45)';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(p0.x, p0.y);
            ctx.lineTo(p1.x, p1.y);
            ctx.stroke();
            ctx.font = '700 8.5px JetBrains Mono, monospace';
            ctx.fillStyle = '#38bdf8';
            ctx.textAlign = 'center';
            ctx.fillText('R-WING', p1.x, p1.y - 5);
            ctx.restore();
          }

          if (hasBack) {
            const p0 = project3D(houseCenterX - 0.38, 0.97, 0.3);
            const p1 = project3D(houseCenterX + 0.38, 0.97, 0.3);
            ctx.save();
            ctx.setLineDash([3, 3]);
            ctx.strokeStyle = 'rgba(168, 85, 247, 0.45)';
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.moveTo(p0.x, p0.y);
            ctx.lineTo(p1.x, p1.y);
            ctx.stroke();
            ctx.font = '700 8.5px JetBrains Mono, monospace';
            ctx.fillStyle = '#c084fc';
            ctx.textAlign = 'center';
            ctx.fillText('BACK EAVE', (p0.x + p1.x) * 0.5, p0.y - 4);
            ctx.restore();
          }
        }

        // Draw roofline strip wire path per section
        sections.forEach((sec) => {
          if (is2D && sec.wall !== 'front') return;
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
              ? 'rgba(0, 245, 212, 0.9)'
              : 'rgba(148, 163, 184, 0.48)';
          ctx.lineWidth = selectedSectionId === sec.id ? 3 : 1.8;
          ctx.stroke();
        });

        // Draw each LED Puck + Downward Soffit Wall-Wash Cone + Halo
        pucks.forEach((puck) => {
          const wx = houseCenterX + puck.x;
          const wy = puck.y;
          const wz = puck.z;
          const pTop = projectSectionPoint(
            houseCenterX,
            puck.wall || 'front',
            puck.uInSection ?? 0.5,
            wx,
            wy,
            wz
          );
          const coneDrop = puck.story === 2 ? 0.22 : 0.26;
          const pWallBottom =
            is2D && puck.wall !== 'front'
              ? { x: pTop.x, y: pTop.y + 14 }
              : project3D(wx, Math.max(0.03, wy - coneDrop), wz - 0.012);
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
      const totalCtrls = (h.controllers || []).length;
      const ctrls = (h.controllers || []).map((c, cIdx) => {
        const spans = getEffectiveControllerSpans(c, arch, cIdx, totalCtrls);
        const spanSum = spans.reduce((s, sp) => s + Math.max(1, Number(sp.segments || 1)), 0);
        return {
          ...c,
          target_segment_count: Number(c.segment_count || spanSum || 9),
          segment_count: Number(c.segment_count || spanSum || 9),
          section_spans: spans,
          custom_nodes: getEffectiveCustomNodes(c),
        };
      });
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
        const totalCtrls = (h.controllers || []).length;
        const ctrls = (h.controllers || []).map((c, cIdx) => {
          const existingCtrl = existingDraft?.controllers?.find((dc) => dc.id === c.id);
          const spans =
            existingCtrl?.section_spans ||
            getEffectiveControllerSpans(c, arch, cIdx, totalCtrls);
          const spanSum = spans.reduce((s, sp) => s + Math.max(1, Number(sp.segments || 1)), 0);
          return {
            ...c,
            target_segment_count:
              existingCtrl?.target_segment_count ?? c.segment_count ?? spanSum ?? 9,
            segment_count: existingCtrl?.segment_count ?? c.segment_count ?? spanSum ?? 9,
            section_spans: spans,
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

  // Apply 1-Tap Architectural Template to active house (preserving exact backend section IDs)
  const handleApplyTemplate = (presetKey) => {
    const preset = ARCHITECTURAL_PRESETS[presetKey];
    if (!preset || !activeHouse) return;
    const clonedSections = preset.sections.map((s, idx) =>
      normalizeSection({ ...s, id: s.id || `${activeHouse.id}-sec-${idx + 1}` }, idx)
    );
    const nextArch = {
      preset_style: preset.preset_style,
      label: preset.label,
      sections: clonedSections,
    };

    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const totalCtrls = (h.controllers || []).length;
        const updatedCtrls = (h.controllers || []).map((c, cIdx) => {
          const targetSegs = Number(c.target_segment_count || c.segment_count || 9);
          const spans = buildPhotoDefaultControllerSpans(
            { ...c, segment_count: targetSegs, section_spans: [] },
            nextArch,
            cIdx,
            totalCtrls
          );
          const sumSegs = spans.reduce((acc, sp) => acc + Number(sp.segments || 1), 0);
          return {
            ...c,
            segment_count: sumSegs,
            target_segment_count: targetSegs,
            section_spans: spans,
            custom_nodes: [],
          };
        });
        return { ...h, architecture: nextArch, controllers: updatedCtrls };
      })
    );
    setSelectedSectionId(clonedSections[0]?.id || null);
    flashStatus(`Applied "${preset.label}" template to ${activeHouse.name}!`);
  };

  // 📸 Reset Active House (or All 3 Houses) to Exact Real Photo Layout
  const handleResetToRealPhotoLayout = (resetAllHouses = false) => {
    if (resetAllHouses) {
      clearSavedArchitectureOverrides(null);
      setDraftHouses((prev) =>
        prev.map((h, idx) => {
          const presetKey = getRealPhotoPresetKeyForHouse(h, idx);
          const preset = ARCHITECTURAL_PRESETS[presetKey] || ARCHITECTURAL_PRESETS.a_frame_gable;
          const nextArch = {
            preset_style: preset.preset_style,
            label: preset.label,
            sections: preset.sections.map((s, sIdx) => normalizeSection({ ...s }, sIdx)),
          };
          const totalCtrls = (h.controllers || []).length;
          const nextCtrls = (h.controllers || []).map((c, cIdx) => {
            const targetSegs = Number(c.target_segment_count || c.segment_count || 9);
            const spans = buildPhotoDefaultControllerSpans(
              { ...c, segment_count: targetSegs, section_spans: [] },
              nextArch,
              cIdx,
              totalCtrls
            );
            const sumSegs = spans.reduce((acc, sp) => acc + Number(sp.segments || 1), 0);
            return {
              ...c,
              segment_count: sumSegs,
              target_segment_count: targetSegs,
              section_spans: spans,
              custom_nodes: [],
            };
          });
          return { ...h, architecture: nextArch, controllers: nextCtrls };
        })
      );
      flashStatus(
        '📸 Restored exact 2-story Real Photo Layout & Controller Spans for ALL 3 Houses!'
      );
      return;
    }

    if (!activeHouse) return;
    clearSavedArchitectureOverrides(activeHouse.id);
    const presetKey = getRealPhotoPresetKeyForHouse(activeHouse, activeHouseIndex);
    handleApplyTemplate(presetKey);
    flashStatus(
      `📸 Restored exact 2-story Real Photo Layout & Controller Spans for ${activeHouse.name}!`
    );
  };

  // ⚡ Apply 1-Tap Wiring Route Preset to a Controller
  const handleApplyWiringRoutePreset = (ctrlId, routeId) => {
    if (!activeHouse) return;
    const routeMeta = WIRING_ROUTE_PRESETS.find((r) => r.id === routeId);
    setDraftHouses((prev) =>
      prev.map((h) => {
        if (h.id !== activeHouse.id) return h;
        const nextCtrls = (h.controllers || []).map((c) => {
          if (c.id !== ctrlId) return c;
          const targetSegs = Math.max(
            1,
            Number(c.target_segment_count || c.segment_count || 9)
          );
          const spans = buildWiringRoutePresetSpans(routeId, activeArch, targetSegs);
          const sumSegs = spans.reduce((acc, sp) => acc + Number(sp.segments || 1), 0);
          return {
            ...c,
            segment_count: sumSegs,
            target_segment_count: targetSegs,
            section_spans: spans,
            custom_nodes: [],
          };
        });
        return { ...h, controllers: nextCtrls };
      })
    );
    flashStatus(
      `⚡ Applied "${routeMeta?.label || routeId}" wiring route to controller!`
    );
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

        <div className="flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => handleResetToRealPhotoLayout(false)}
            className="px-3 py-2 rounded-xl bg-amber-500/15 hover:bg-amber-500/25 text-amber-200 border border-amber-400/50 font-extrabold text-xs flex items-center gap-1.5 transition"
            title="Restore exact photo-accurate 2-story architecture & controller spans for this house"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            <span>📸 Reset to Real Photo Layout</span>
          </button>
          <button
            type="button"
            onClick={() => handleResetToRealPhotoLayout(true)}
            className="px-2.5 py-2 rounded-xl bg-purple-500/15 hover:bg-purple-500/25 text-purple-200 border border-purple-400/40 font-bold text-[11px] flex items-center gap-1 transition"
            title="Restore all 3 houses to exact real nighttime photo models"
          >
            <span>📸 Reset All 3 Houses</span>
          </button>
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

          <div className="space-y-3 max-h-[460px] overflow-y-auto pr-1">
            {(activeHouse?.controllers || []).map((ctrl, cIdx) => {
              const spans = ctrl.section_spans || [];
              const customNodes = ctrl.custom_nodes || [];
              const totalSpanSegs = spans.reduce(
                (acc, sp) => acc + Math.max(1, Number(sp.segments || 1)),
                0
              );
              const targetSegs = Number(
                ctrl.target_segment_count || ctrl.segment_count || totalSpanSegs || 9
              );
              const isDrawingThis = customNodeDrawCtrlId === ctrl.id;

              return (
                <div
                  key={ctrl.id || cIdx}
                  className="bg-[#0c1324] border border-[#1e293b] rounded-xl p-3 space-y-2.5"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-xs font-extrabold text-white">
                          Controller #{cIdx + 1}: {ctrl.name || ctrl.id}
                        </span>
                        <span
                          className={`text-[10px] font-mono px-2 py-0.5 rounded border font-bold ${
                            totalSpanSegs === targetSegs
                              ? 'bg-[#00f5d4]/15 text-[#00f5d4] border-[#00f5d4]/40'
                              : 'bg-amber-500/15 text-amber-300 border-amber-400/50'
                          }`}
                        >
                          Used {totalSpanSegs} / {targetSegs} segs
                        </span>
                        <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-[#060b18] text-slate-300 border border-[#1e293b]">
                          {ctrl.sku || 'H705'}
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

                  {/* ⚡ 1-Tap Wiring Route Presets */}
                  <div className="bg-[#060b18] border border-[#1e293b] rounded-lg p-2 space-y-1.5">
                    <div className="flex items-center justify-between">
                      <span className="text-[10px] font-extrabold text-amber-300 uppercase tracking-wide">
                        ⚡ 1-Tap Wiring Route Presets (Test Neighbor / Roofline Runs):
                      </span>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {WIRING_ROUTE_PRESETS.map((route) => (
                        <button
                          key={route.id}
                          type="button"
                          onClick={() => handleApplyWiringRoutePreset(ctrl.id, route.id)}
                          className="px-2 py-1 rounded-md bg-[#0c1324] hover:bg-cyan-500/20 text-slate-200 hover:text-cyan-200 border border-[#1e293b] hover:border-cyan-400/50 text-[10px] font-bold transition"
                          title={route.subtitle}
                        >
                          {route.label}
                        </button>
                      ))}
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
                      Used {totalSpanSegs} / {targetSegs} segs ={' '}
                      {spans
                        .map((sp) => {
                          const secObj = activeSections.find((s) => s.id === sp.section_id);
                          return `${sp.segments} on ${secObj?.label || sp.section_id} (${
                            sp.direction === 'rtl' ? 'RTL' : 'LTR'
                          })`;
                        })
                        .join(' + ')}
                    </div>
                  </div>

                  {/* Individual Section Span Rows with +/- Steppers, Slider, and LTR/RTL Toggle */}
                  <div className="space-y-1.5">
                    {spans.map((sp, sIdx) => {
                      const isRtl = sp.direction === 'rtl';
                      const segVal = Math.max(1, Number(sp.segments || 1));
                      return (
                        <div
                          key={sIdx}
                          className="grid grid-cols-12 gap-1.5 items-center bg-[#060b18] border border-[#1e293b] rounded-lg p-1.5"
                        >
                          <div className="col-span-12 sm:col-span-4">
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
                                  [{sec.story === 2 ? '2F' : '1F'} {sec.wall.toUpperCase()}]{' '}
                                  {sec.label}
                                </option>
                              ))}
                            </select>
                          </div>

                          <div className="col-span-7 sm:col-span-5 flex items-center gap-1">
                            <button
                              type="button"
                              onClick={() =>
                                handleUpdateControllerSpan(ctrl.id, sIdx, {
                                  segments: Math.max(1, segVal - 1),
                                })
                              }
                              className="w-6 h-6 rounded bg-[#0c1324] hover:bg-slate-800 border border-[#1e293b] text-xs font-extrabold text-slate-200 flex items-center justify-center shrink-0"
                              title="Decrease segments (-1)"
                            >
                              -
                            </button>
                            <input
                              type="range"
                              min="1"
                              max="30"
                              value={Math.min(30, segVal)}
                              onChange={(e) =>
                                handleUpdateControllerSpan(ctrl.id, sIdx, {
                                  segments: Math.max(1, Number(e.target.value || 1)),
                                })
                              }
                              className="w-full accent-[#00f5d4]"
                            />
                            <button
                              type="button"
                              onClick={() =>
                                handleUpdateControllerSpan(ctrl.id, sIdx, {
                                  segments: Math.min(60, segVal + 1),
                                })
                              }
                              className="w-6 h-6 rounded bg-[#0c1324] hover:bg-slate-800 border border-[#1e293b] text-xs font-extrabold text-cyan-300 flex items-center justify-center shrink-0"
                              title="Increase segments (+1)"
                            >
                              +
                            </button>
                            <span className="px-1.5 py-0.5 rounded bg-[#0c1324] border border-[#1e293b] text-[10px] font-mono text-cyan-300 font-bold shrink-0">
                              {segVal}s
                            </span>
                          </div>

                          <div className="col-span-4 sm:col-span-2 flex justify-end">
                            <button
                              type="button"
                              onClick={() =>
                                handleUpdateControllerSpan(ctrl.id, sIdx, {
                                  direction: isRtl ? 'ltr' : 'rtl',
                                })
                              }
                              className={`w-full px-2 py-1 rounded border text-[10px] font-mono font-bold transition ${
                                isRtl
                                  ? 'bg-amber-500/20 text-amber-200 border-amber-400/50'
                                  : 'bg-[#0c1324] text-cyan-200 border-[#1e293b] hover:border-cyan-400/50'
                              }`}
                              title="Toggle strip direction (Left-to-Right vs Right-to-Left)"
                            >
                              {isRtl ? 'RTL ←' : 'LTR →'}
                            </button>
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
                      );
                    })}
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
