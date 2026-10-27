import React, { useState } from 'react';
import {
  Play,
  Pause,
  Power,
  Plus,
  Sparkles,
  Check,
  Box,
  Flashlight,
} from 'lucide-react';
import HouseArchitectureDesigner, {
  ArchitecturalViewportCanvas,
  SUB_PUCKS_PER_SEGMENT,
} from './HouseArchitectureDesigner.jsx';

const QUICK_BURST_CHIPS = [
  {
    type: 'touchdown',
    label: '🏈 Touchdown',
    cls: 'border-[#69be28]/50 text-[#a7f3d0] hover:bg-[#69be28]/15',
  },
  {
    type: 'lightning',
    label: '⚡ Lightning',
    cls: 'border-[#38bdf8]/50 text-[#bae6fd] hover:bg-[#38bdf8]/15',
  },
  {
    type: 'new_year',
    label: '🎆 Finale',
    cls: 'border-[#fbbf24]/50 text-[#fde68a] hover:bg-[#fbbf24]/15',
  },
  {
    type: 'strobe',
    label: '🎉 Strobe',
    cls: 'border-[#f43f5e]/50 text-[#fecdd3] hover:bg-[#f43f5e]/15',
  },
];

const THREE_HOUSE_SYNC_MODES = [
  {
    id: 'all_segments',
    label: '⚡ Smart CCW + Street Sync',
    desc: 'Bottom-to-Top Counter-Clockwise (1st Story LTR → 2nd Story RTL) synced across House 1 → House 2 → House 3',
  },
  {
    id: 'ccw_loop',
    label: '↺ Bottom → Top CCW Loop',
    desc: 'Continuous Bottom-to-Top Counter-Clockwise loop (1F LTR → 2F RTL) simultaneously on each house',
  },
  {
    id: 'bottom_to_top',
    label: '⬆️ Bottom → Top Vertical Rise',
    desc: 'Vertical light wave rising from 1st-story garage/porch eaves up to 2nd-story gable peaks across all 3 houses',
  },
  {
    id: 'front_street_sync',
    label: '🔗 Street X-Lock (Top+Bottom Aligned)',
    desc: 'Locks Upper 2nd-story & Lower 1st-story front rooflines to horizontal street X coordinate across all 3 houses',
  },
  {
    id: 'perimeter_360',
    label: '🔄 360° Roof Orbit',
    desc: 'Orbits around Front → Right → Back → Left rooflines',
  },
  {
    id: 'depth_front_to_back',
    label: '🌊 Front → Back Depth',
    desc: 'Sweeps from stepped-forward front porch/garage eaves back to rear rooflines',
  },
];

export function formatOrdinal(n) {
  const s = ['th', 'st', 'nd', 'rd'];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

export function getPositionLabel(index, total = 3) {
  const ord = `${formatOrdinal(index + 1)} House`;
  if (total === 1) return '1st House (Solo Mode)';
  if (index === 0) return `${ord} (Start of Chase)`;
  if (index === total - 1) return `${ord} (End of Chase)`;
  if (total === 3 && index === 1) return `${ord} (Middle of Chase)`;
  return `${ord} (Mid #${index + 1})`;
}

export default function NeighborhoodPreview({
  liveState,
  config,
  onPlaySync,
  onPauseSync,
  onStopSync,
  onToggleHouse,
  onAddHouse,
  onTriggerBurst,
  onSaveConfig,
  apiFetch,
  onOpenDesigner,
  burstBusy = '',
}) {
  const [previewMode, setPreviewMode] = useState('3d_all');
  const [showInlineDesigner, setShowInlineDesigner] = useState(false);
  const [designerHouseId, setDesignerHouseId] = useState(null);
  const [selectedPuck, setSelectedPuck] = useState(null);
  const [optimisticZoneMode, setOptimisticZoneMode] = useState(null);
  const [syncModeSaving, setSyncModeSaving] = useState(false);

  const segments = liveState?.segments || [];
  const houses = [...(config?.houses || [])].sort((a, b) => (a.order || 1) - (b.order || 1));
  const enabledHouses = houses.filter((h) => h.enabled !== false);
  const targetHouses = enabledHouses.length > 0 ? enabledHouses : houses;
  const isRunning = liveState?.running ?? config?.animation?.running ?? true;
  const blackoutOnStop =
    liveState?.blackout_on_stop ?? config?.animation?.blackout_on_stop ?? false;
  const fps = liveState?.measured_fps ?? config?.animation?.fps ?? 25;
  const driftMs = liveState?.clock_drift_ms ?? 0.08;
  const activeZoneMode =
    optimisticZoneMode ||
    liveState?.zone_mode ||
    config?.animation?.zone_mode ||
    'all_segments';
  const totalSegCount = segments.length || 63;
  const totalPuckCount = totalSegCount * SUB_PUCKS_PER_SEGMENT;

  const handleSelectZoneMode = async (modeId) => {
    setOptimisticZoneMode(modeId);
    setSyncModeSaving(true);
    try {
      const doReq = apiFetch || fetch;
      await doReq('/api/animation', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ zone_mode: modeId }),
      });
      if (onSaveConfig && config) {
        onSaveConfig({
          ...config,
          animation: {
            ...(config.animation || {}),
            zone_mode: modeId,
          },
        });
      }
    } catch (e) {
      // keep optimistic mode in UI
    } finally {
      setSyncModeSaving(false);
    }
  };

  const viewModes = [
    { id: '3d_all', label: `🧊 3D Street (${enabledHouses.length || targetHouses.length} Houses)` },
    ...targetHouses.map((h) => ({
      id: `3d_house:${h.id}`,
      label: `🧊 3D: ${h.name || h.id}`,
    })),
    { id: '2d', label: '📐 2D Front Elevation' },
  ];

  const handleOpenDesignerClick = (houseId = null) => {
    const resolvedId =
      houseId ||
      (previewMode.startsWith('3d_house:') ? previewMode.split(':')[1] : null) ||
      targetHouses[0]?.id ||
      'house-1';
    setDesignerHouseId(resolvedId);
    setShowInlineDesigner((prev) => !prev);
    if (onOpenDesigner && typeof onOpenDesigner === 'function') {
      onOpenDesigner(resolvedId);
    }
  };

  return (
    <div className="bg-[#0c1324] border border-[#1e293b] rounded-2xl p-4 shadow-xl space-y-3">
      {/* Compact Header Row + Glowing Primary Action Button: 🏗️ Design House & Lights */}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2 min-w-0">
          <span
            className={`w-2.5 h-2.5 rounded-full shrink-0 ${
              isRunning
                ? 'bg-[#00f5d4] shadow-[0_0_10px_#00f5d4]'
                : blackoutOnStop
                ? 'bg-rose-500'
                : 'bg-amber-400'
            }`}
          />
          <h2 className="text-sm sm:text-base font-extrabold text-white truncate">
            Live Multi-House 3D &amp; 2D Roofline Studio
          </h2>
          <span className="text-[11px] font-mono px-2 py-0.5 rounded-md bg-[#060b18] text-[#00f5d4] border border-[#1e293b]">
            {enabledHouses.length}/{houses.length} Houses • {totalSegCount} Segs ({totalPuckCount} LEDs)
          </span>
        </div>

        <div className="flex flex-wrap items-center gap-1.5 text-[11px] font-mono">
          <button
            type="button"
            onClick={() => handleOpenDesignerClick()}
            className={`px-3 py-1 rounded-xl font-sans font-extrabold text-xs flex items-center gap-1.5 border transition shadow-lg ${
              showInlineDesigner
                ? 'bg-[#00f5d4] text-[#040711] border-[#00f5d4] shadow-[#00f5d4]/30'
                : 'bg-gradient-to-r from-[#00f5d4]/25 via-cyan-500/20 to-purple-500/25 hover:from-[#00f5d4]/35 hover:to-purple-500/35 text-[#00f5d4] border-[#00f5d4]/60 shadow-[#00f5d4]/15'
            }`}
          >
            <span>🏗️ Design House &amp; Lights</span>
          </button>

          <span
            className={`px-2 py-0.5 rounded-md font-bold border ${
              isRunning
                ? 'bg-[#00f5d4]/15 text-[#00f5d4] border-[#00f5d4]/40'
                : blackoutOnStop
                ? 'bg-rose-500/15 text-rose-300 border-rose-500/40'
                : 'bg-amber-500/15 text-amber-300 border-amber-500/40'
            }`}
          >
            {isRunning ? `LIVE ${fps} FPS` : blackoutOnStop ? 'STOPPED (OFF)' : 'PAUSED'}
          </span>
          <span className="hidden sm:inline-block px-2 py-0.5 rounded-md bg-[#060b18] text-slate-400 border border-[#1e293b]">
            Drift {driftMs}ms
          </span>
        </div>
      </div>

      {/* Top Mode Bar: 🧊 3D Street (Default) | 🧊 3D: House | 📐 2D Front Elevation */}
      <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5 no-scrollbar">
        {viewModes.map((vm) => {
          const active = previewMode === vm.id;
          return (
            <button
              key={vm.id}
              type="button"
              onClick={() => setPreviewMode(vm.id)}
              className={`px-2.5 py-1 rounded-full text-[11px] font-extrabold border shrink-0 transition ${
                active
                  ? 'bg-[#00f5d4]/20 text-[#00f5d4] border-[#00f5d4] shadow-sm shadow-[#00f5d4]/20'
                  : 'bg-[#060b18] text-slate-300 border-[#1e293b] hover:text-white'
              }`}
            >
              {vm.label}
            </button>
          );
        })}
      </div>

      {/* 🔗 3-House Sync Alignment Selector Pill Bar */}
      <div className="bg-[#060b18]/90 border border-[#1e293b] rounded-xl px-2.5 py-2 flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-1.5 text-[11px] font-extrabold text-cyan-300 shrink-0">
          <span>🔗 3-House Sync Alignment:</span>
          {syncModeSaving && (
            <span className="text-[10px] font-mono text-amber-300 animate-pulse">
              Syncing...
            </span>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-1.5">
          {THREE_HOUSE_SYNC_MODES.map((m) => {
            const isSel = activeZoneMode === m.id;
            return (
              <button
                key={m.id}
                type="button"
                title={m.desc}
                onClick={() => handleSelectZoneMode(m.id)}
                className={`px-2.5 py-1 rounded-lg text-[11px] font-bold border transition ${
                  isSel
                    ? 'bg-[#00f5d4]/20 text-[#00f5d4] border-[#00f5d4] shadow-sm shadow-[#00f5d4]/20'
                    : 'bg-[#0c1324] text-slate-300 border-[#1e293b] hover:text-white hover:border-slate-600'
                }`}
              >
                {m.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* True Multi-Section 3D & 2D Architectural Renderer */}
      <ArchitecturalViewportCanvas
        houses={houses}
        liveSegments={segments}
        animation={{
          ...(config?.animation || {}),
          zone_mode: activeZoneMode,
          running: isRunning,
          blackout_on_stop: blackoutOnStop,
        }}
        previewMode={previewMode}
        selectedPuckId={selectedPuck?.id}
        onSelectPuck={(puck) => setSelectedPuck(puck)}
        onSelectHouse={(hId) => {
          if (previewMode !== '2d') {
            setPreviewMode(`3d_house:${hId}`);
          }
        }}
        onOpenDesigner={() => handleOpenDesignerClick()}
        height={265}
      />

      {/* Quick Selected Puck Banner (if user clicked an LED puck in the 3D/2D preview) */}
      {selectedPuck && !showInlineDesigner && (
        <div className="px-3 py-2 rounded-xl bg-[#060b18] border border-cyan-500/40 flex flex-wrap items-center justify-between gap-2 text-xs">
          <div className="flex items-center gap-2">
            <span
              className="w-3.5 h-3.5 rounded-full border border-white"
              style={{ backgroundColor: selectedPuck.hex }}
            />
            <span className="font-bold text-white">
              {selectedPuck.houseName} · {selectedPuck.controllerName} · Seg #
              {selectedPuck.localIndex + 1}
            </span>
            <span className="text-cyan-300 font-mono text-[11px]">
              ({selectedPuck.sectionLabel})
            </span>
          </div>
          <div className="flex items-center gap-1.5">
            <button
              type="button"
              onClick={() => handleOpenDesignerClick(selectedPuck.houseId)}
              className="px-2.5 py-1 rounded-lg bg-[#00f5d4]/20 text-[#00f5d4] border border-[#00f5d4]/50 font-bold text-[11px]"
            >
              Edit Section &amp; Light Span
            </button>
            <button
              type="button"
              onClick={() => setSelectedPuck(null)}
              className="px-2 py-1 rounded-lg bg-slate-800 text-slate-400 hover:text-white text-[11px]"
            >
              Dismiss
            </button>
          </div>
        </div>
      )}

      {/* Expandable Inline 2D/3D House & Controller Light Strip Studio */}
      {showInlineDesigner && (
        <HouseArchitectureDesigner
          config={config}
          liveState={liveState}
          initialHouseId={designerHouseId}
          onSaveConfig={onSaveConfig}
          apiFetch={apiFetch}
          onClose={() => setShowInlineDesigner(false)}
          inlineMode
        />
      )}

      {/* Quick House Active Filter Chips + Add House */}
      <div className="flex flex-wrap items-center justify-between gap-2 pt-0.5">
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="text-[11px] font-bold text-slate-400 mr-1">Active Houses:</span>
          {houses.map((h, idx) => {
            const active = h.enabled !== false;
            const segCnt = (h.controllers || []).reduce(
              (acc, c) => acc + (c.enabled !== false ? Number(c.segment_count || 0) : 0),
              0
            );
            const shortName = (h.name || `House ${idx + 1}`).split('(')[0].trim();
            return (
              <button
                key={h.id}
                type="button"
                disabled={active && enabledHouses.length <= 1}
                onClick={() => onToggleHouse && onToggleHouse(h.id, !active)}
                className={`px-2.5 py-1 rounded-lg text-xs font-bold flex items-center gap-1.5 border transition ${
                  active
                    ? 'bg-[#00f5d4]/15 text-[#00f5d4] border-[#00f5d4]/50'
                    : 'bg-[#060b18] text-slate-500 border-[#1e293b] hover:text-slate-300'
                } disabled:opacity-60`}
                title="Toggle house in multi-house sync"
              >
                {active && <Check className="w-3 h-3 stroke-[3]" />}
                <span>
                  #{idx + 1} {shortName} ({segCnt}s)
                </span>
              </button>
            );
          })}
          {onAddHouse && (
            <button
              type="button"
              onClick={() => onAddHouse()}
              className="px-2.5 py-1 rounded-lg text-xs font-bold flex items-center gap-1 bg-[#060b18] hover:bg-slate-800 text-cyan-300 border border-[#1e293b] transition"
            >
              <Plus className="w-3 h-3" /> Add House
            </button>
          )}
        </div>
      </div>

      {/* 3 Primary Transport Buttons matching Flutter APK _buildTransportButtonsRow */}
      <div className="grid grid-cols-3 gap-2.5">
        <button
          type="button"
          onClick={onPlaySync}
          className={`py-2.5 px-3 rounded-xl font-extrabold text-xs sm:text-sm flex items-center justify-center gap-1.5 transition ${
            isRunning
              ? 'bg-[#00f5d4] text-[#040711] shadow-lg shadow-[#00f5d4]/20'
              : 'bg-[#1e293b] hover:bg-[#334155] text-white'
          }`}
        >
          <Play className="w-4 h-4 fill-current" />
          <span>Start Sync</span>
        </button>

        <button
          type="button"
          onClick={onPauseSync}
          className={`py-2.5 px-3 rounded-xl font-extrabold text-xs sm:text-sm flex items-center justify-center gap-1.5 transition ${
            !isRunning && !blackoutOnStop
              ? 'bg-[#f59e0b] text-[#040711] shadow-lg shadow-[#f59e0b]/20'
              : 'bg-[#1e293b] hover:bg-[#334155] text-white'
          }`}
        >
          <Pause className="w-4 h-4 fill-current" />
          <span>Pause Frame</span>
        </button>

        <button
          type="button"
          onClick={onStopSync}
          className={`py-2.5 px-3 rounded-xl font-extrabold text-xs sm:text-sm flex items-center justify-center gap-1.5 transition ${
            !isRunning && blackoutOnStop
              ? 'bg-[#ef4444] text-white shadow-lg shadow-[#ef4444]/25'
              : 'bg-[#3b1219] hover:bg-[#521822] text-rose-200 border border-rose-500/30'
          }`}
        >
          <Power className="w-4 h-4" />
          <span>Stop &amp; Turn Off</span>
        </button>
      </div>

      {/* 1-Tap Celebration Burst Chips matching Flutter APK */}
      {onTriggerBurst && (
        <div className="pt-2 border-t border-[#1e293b] flex flex-wrap items-center justify-between gap-2">
          <span className="text-xs font-extrabold text-amber-300 flex items-center gap-1.5">
            <Sparkles className="w-3.5 h-3.5" /> 1-Tap 12s Bursts:
          </span>
          <div className="flex flex-wrap items-center gap-1.5">
            {QUICK_BURST_CHIPS.map((b) => (
              <button
                key={b.type}
                type="button"
                disabled={burstBusy === b.type}
                onClick={() => onTriggerBurst(b.type)}
                className={`px-2.5 py-1 rounded-lg text-xs font-bold border bg-[#060b18] transition ${b.cls}`}
              >
                {burstBusy === b.type ? '⚡ Firing...' : b.label}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
