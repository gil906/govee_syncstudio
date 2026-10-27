import React from 'react';
import {
  Play,
  Pause,
  Power,
  Plus,
  Sparkles,
  Check,
} from 'lucide-react';
import LiveSceneCardPreview from './LiveSceneCardPreview.jsx';

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
  burstBusy = '',
}) {
  const [viewMode, setViewMode] = React.useState('2d'); // '2d', '3d_all', or '3d:<houseId>'
  const segments = liveState?.segments || [];
  const houses = [...(config?.houses || [])].sort((a, b) => (a.order || 1) - (b.order || 1));
  const enabledHouses = houses.filter((h) => h.enabled !== false);
  const targetHouses = enabledHouses.length > 0 ? enabledHouses : houses;
  const isRunning = liveState?.running ?? config?.animation?.running ?? true;
  const blackoutOnStop =
    liveState?.blackout_on_stop ?? config?.animation?.blackout_on_stop ?? false;
  const fps = liveState?.measured_fps ?? config?.animation?.fps ?? 25;
  const driftMs = liveState?.clock_drift_ms ?? 0.08;

  const viewModes = [
    { id: '2d', label: '2D Front' },
    { id: '3d_all', label: `3D All (${targetHouses.length} Houses)` },
    ...targetHouses.map((h, i) => ({
      id: `3d:${h.id}`,
      label: `3D: #${i + 1} ${(h.name || `House ${i + 1}`).split('(')[0].trim()}`,
    })),
  ];

  return (
    <div className="bg-[#0c1324] border border-[#1e293b] rounded-2xl p-4 shadow-xl space-y-3">
      {/* Compact Header Row matching Flutter APK */}
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
            Live Multi-House Roofline Studio
          </h2>
          <span className="text-[11px] font-mono px-2 py-0.5 rounded-md bg-[#060b18] text-[#00f5d4] border border-[#1e293b]">
            {enabledHouses.length}/{houses.length} Houses • {segments.length || 63} Segs
          </span>
        </div>

        <div className="flex items-center gap-1.5 text-[11px] font-mono">
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

      {/* 2D Front vs 3D All Enabled Houses vs 3D Single House Mode Selector */}
      <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5 no-scrollbar">
        {viewModes.map((vm) => {
          const active = viewMode === vm.id;
          return (
            <button
              key={vm.id}
              type="button"
              onClick={() => setViewMode(vm.id)}
              className={`px-2.5 py-1 rounded-full text-[11px] font-extrabold border shrink-0 transition ${
                active
                  ? 'bg-[#00f5d4]/20 text-[#00f5d4] border-[#00f5d4]'
                  : 'bg-[#060b18] text-slate-300 border-[#1e293b] hover:text-white'
              }`}
            >
              {vm.label}
            </button>
          );
        })}
      </div>

      {/* Unified Night-Sky 2D or 3D Isometric Architectural Canvas */}
      <LiveSceneCardPreview
        animation={{ ...(config?.animation || {}), running: isRunning }}
        houses={houses}
        liveSegments={segments}
        viewMode={viewMode}
        height={165}
        compact={false}
      />

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
