import React, { useState } from 'react';
import {
  Home,
  Cpu,
  Activity,
  ArrowRight,
  ArrowLeft,
  Repeat,
  Sparkles,
  Play,
  Pause,
  Square,
  Zap,
  Globe,
  Wifi,
  Radio,
  Shield,
  Plus,
  Trash2,
  Power,
  Flame,
} from 'lucide-react';

const CONNECTION_BADGES = {
  local_lan: {
    label: 'Local Wi-Fi LAN (UDP :4003)',
    short: 'LOCAL LAN UDP',
    cls: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
    Icon: Wifi,
  },
  govee_cloud: {
    label: 'Govee Cloud API (Over Internet)',
    short: 'CLOUD INTERNET',
    cls: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
    Icon: Globe,
  },
  neighbor_bridge: {
    label: 'Neighbor 25-FPS WS Bridge',
    short: '25-FPS BRIDGE',
    cls: 'bg-purple-500/15 text-purple-300 border-purple-500/30',
    Icon: Radio,
  },
  tailscale_vpn: {
    label: 'WireGuard / Tailscale VPN',
    short: 'VPN DIRECT',
    cls: 'bg-cyan-500/15 text-cyan-300 border-cyan-500/30',
    Icon: Shield,
  },
};

const QUICK_BURST_CHIPS = [
  {
    type: 'touchdown',
    label: '🏈 Touchdown',
    cls: 'bg-emerald-500/15 hover:bg-emerald-500/30 text-emerald-200 border-emerald-400/40',
  },
  {
    type: 'lightning',
    label: '⚡ Lightning',
    cls: 'bg-cyan-500/15 hover:bg-cyan-500/30 text-cyan-200 border-cyan-400/40',
  },
  {
    type: 'new_year',
    label: '🎆 Finale',
    cls: 'bg-amber-500/15 hover:bg-amber-500/30 text-amber-200 border-amber-400/40',
  },
  {
    type: 'strobe',
    label: '🎉 Strobe',
    cls: 'bg-fuchsia-500/15 hover:bg-fuchsia-500/30 text-fuchsia-200 border-fuchsia-400/40',
  },
];

export function formatOrdinal(n) {
  const s = ['th', 'st', 'nd', 'rd'];
  const v = n % 100;
  return `${n}${s[(v - 20) % 10] || s[v] || s[0]}`;
}

export function getPositionLabel(idx, total) {
  const ord = formatOrdinal(idx + 1);
  if (total <= 1) return `${ord} House (Solo House Sync)`;
  if (idx === 0) return `${ord} House (Start of Chase)`;
  if (idx === total - 1) return `${ord} House (End of Chase)`;
  if (total === 3 && idx === 1) return '2nd House (Middle of Chase)';
  return `${ord} House (Stop #${idx + 1} of ${total})`;
}

export default function NeighborhoodPreview({
  liveState,
  config,
  onPlaySync,
  onPauseSync,
  onStopSync,
  onReorderHouses,
  onTestController,
  onToggleHouse,
  onAddHouse,
  onDeleteHouse,
  onUpdateHouseTimeWeight,
  onTriggerBurst,
  burstBusy,
}) {
  const [testingCtrlId, setTestingCtrlId] = useState(null);
  const [testedCtrlMsg, setTestedCtrlMsg] = useState({});
  const [busyHouseAction, setBusyHouseAction] = useState(null);

  const segments = liveState?.segments || [];
  const houses = config?.houses || [];
  const phase = liveState?.phase ?? 0;
  const isRunning = liveState?.running ?? config?.animation?.running ?? true;
  const blackoutOnStop =
    liveState?.blackout_on_stop ?? config?.animation?.blackout_on_stop ?? true;
  const direction = liveState?.direction || config?.animation?.direction || 'forward';
  const mappingMode =
    liveState?.mapping_mode || config?.animation?.mapping_mode || 'house_normalized';
  const speed = liveState?.speed || config?.animation?.speed || 0.25;
  const cycleSeconds = speed > 0 ? (1 / speed).toFixed(1) : '∞';
  const enabledHouses = houses.filter((h) => h.enabled !== false);
  const totalEnabledWeight = enabledHouses.reduce(
    (sum, h) => sum + Math.max(0.1, Number(h.time_weight || 1.0)),
    0
  );
  const totalEnabledSegs = enabledHouses.reduce(
    (sum, h) =>
      sum +
      (h.controllers || []).reduce(
        (acc, c) => acc + (c.enabled !== false ? Number(c.segment_count || 0) : 0),
        0
      ),
    0
  );
  const avgSegsPerHouse =
    enabledHouses.length > 0 ? totalEnabledSegs / enabledHouses.length : 12;
  const perHouseSeconds =
    speed > 0 && enabledHouses.length > 0
      ? (1 / speed / enabledHouses.length).toFixed(2)
      : '0.00';

  // Group live segments by house_id and controller_id
  const houseSegMap = {};
  const ctrlSegMap = {};
  for (const seg of segments) {
    if (!houseSegMap[seg.house_id]) houseSegMap[seg.house_id] = [];
    houseSegMap[seg.house_id].push(seg);
    const cKey = `${seg.house_id}::${seg.controller_id}`;
    if (!ctrlSegMap[cKey]) ctrlSegMap[cKey] = [];
    ctrlSegMap[cKey].push(seg);
  }

  const houseSummaries = liveState?.houses || [];

  const handleMoveHouseToIndex = (fromIndex, toIndex) => {
    if (!onReorderHouses || toIndex < 0 || toIndex >= houses.length || fromIndex === toIndex) {
      return;
    }
    const next = [...houses];
    const [moved] = next.splice(fromIndex, 1);
    next.splice(toIndex, 0, moved);
    onReorderHouses(next.map((h) => h.id));
  };

  const handleToggleHouseClick = async (house) => {
    setBusyHouseAction(house.id);
    try {
      if (onToggleHouse) {
        await onToggleHouse(house.id, !house.enabled);
      } else {
        await fetch(`/api/houses/${house.id}/toggle`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ enabled: !house.enabled }),
        });
      }
    } finally {
      setBusyHouseAction(null);
    }
  };

  const handleAddHouseClick = async () => {
    setBusyHouseAction('add');
    try {
      if (onAddHouse) {
        await onAddHouse();
      } else {
        await fetch('/api/houses/add', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        });
      }
    } finally {
      setBusyHouseAction(null);
    }
  };

  const handleDeleteHouseClick = async (house) => {
    if (houses.length <= 1) return;
    setBusyHouseAction(house.id);
    try {
      if (onDeleteHouse) {
        await onDeleteHouse(house.id);
      } else {
        await fetch(`/api/houses/${house.id}`, { method: 'DELETE' });
      }
    } finally {
      setBusyHouseAction(null);
    }
  };

  const handleHouseSpeedChange = async (house, nextTimeWeight, isReset = false) => {
    const clampedWeight = isReset
      ? 1.0
      : Math.max(0.1, Math.min(10.0, Number(nextTimeWeight.toFixed(3))));
    if (onUpdateHouseTimeWeight) {
      onUpdateHouseTimeWeight(house.id, clampedWeight, isReset);
    } else {
      await fetch(`/api/houses/${house.id}/speed`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ time_weight: clampedWeight, reset_default: isReset }),
      });
    }
  };

  const handleTestClick = async (ctrlId) => {
    if (!onTestController) return;
    setTestingCtrlId(ctrlId);
    try {
      const res = await onTestController(ctrlId);
      setTestedCtrlMsg((prev) => ({
        ...prev,
        [ctrlId]: res?.ip ? `Sent to ${res.ip}!` : 'Pulse Sent!',
      }));
      setTimeout(() => {
        setTestedCtrlMsg((prev) => {
          const copy = { ...prev };
          delete copy[ctrlId];
          return copy;
        });
      }, 2500);
    } finally {
      setTestingCtrlId(null);
    }
  };

  const gridColsCls =
    houses.length === 1
      ? 'grid-cols-1'
      : houses.length === 2
      ? 'grid-cols-1 md:grid-cols-2'
      : houses.length === 3
      ? 'grid-cols-1 md:grid-cols-2 xl:grid-cols-3'
      : 'grid-cols-1 md:grid-cols-2 xl:grid-cols-4';

  return (
    <div className="bg-[#0b1120]/95 backdrop-blur-xl border border-slate-800/90 rounded-2xl p-4 sm:p-5 shadow-2xl space-y-4">
      {/* Header row */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <span
              className={`inline-flex items-center justify-center w-2.5 h-2.5 rounded-full ${
                isRunning
                  ? 'bg-emerald-400 animate-pulse'
                  : blackoutOnStop
                  ? 'bg-rose-500'
                  : 'bg-amber-400'
              }`}
            />
            <h2 className="text-base sm:text-lg font-extrabold tracking-tight text-white">
              Live Multi-House Roofline Visualizer
            </h2>
            <span className="text-[11px] px-2.5 py-0.5 rounded-full bg-cyan-500/15 text-cyan-300 border border-cyan-500/30 font-mono font-bold">
              {enabledHouses.length}/{houses.length} Houses Active · {segments.length} Segs
            </span>

            {/* Explicit Running / Paused / Stopped Status Badge */}
            {isRunning ? (
              <span className="text-[11px] px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 font-mono font-bold">
                RUNNING ({liveState?.measured_fps || config?.animation?.fps || 25} FPS)
              </span>
            ) : blackoutOnStop ? (
              <span className="text-[11px] px-2.5 py-0.5 rounded-full bg-rose-500/25 text-rose-200 border border-rose-500/50 font-mono font-bold">
                STOPPED (LIGHTS OFF)
              </span>
            ) : (
              <span className="text-[11px] px-2.5 py-0.5 rounded-full bg-amber-500/25 text-amber-200 border border-amber-500/50 font-mono font-bold">
                PAUSED (FRAME FROZEN)
              </span>
            )}
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Toggle any house <strong className="text-emerald-300">Active / Disabled</strong> below to run animations on{' '}
            <strong className="text-white">1 house (My House only)</strong>,{' '}
            <strong className="text-white">2 houses</strong>,{' '}
            <strong className="text-white">3 houses</strong>, or click{' '}
            <strong className="text-cyan-300">+ Add Neighbor House</strong> to expand down the street!
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2 text-xs">
          {/* Instant Transport Buttons in Live Visualizer */}
          <div className="flex items-center gap-1.5 bg-slate-950/90 p-1 rounded-xl border border-slate-800">
            <button
              onClick={onPlaySync}
              className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition ${
                isRunning
                  ? 'bg-emerald-500 text-slate-950 shadow shadow-emerald-500/30'
                  : 'bg-emerald-500/15 hover:bg-emerald-500/30 text-emerald-300 border border-emerald-500/30'
              }`}
              title="Immediately start or resume the master animation clock"
            >
              <Play className="w-3.5 h-3.5 fill-current" />
              Start
            </button>

            <button
              onClick={onPauseSync}
              className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition ${
                !isRunning && !blackoutOnStop
                  ? 'bg-amber-400 text-slate-950 shadow shadow-amber-400/30'
                  : 'bg-amber-500/15 hover:bg-amber-500/30 text-amber-300 border border-amber-500/30'
              }`}
              title="Freeze the animation frame in place on both preview and physical lights"
            >
              <Pause className="w-3.5 h-3.5 fill-current" />
              Pause
            </button>

            <button
              onClick={onStopSync}
              className={`px-3 py-1.5 rounded-lg font-bold flex items-center gap-1.5 transition ${
                !isRunning && blackoutOnStop
                  ? 'bg-rose-500 text-slate-950 shadow shadow-rose-500/30'
                  : 'bg-rose-500/15 hover:bg-rose-500/30 text-rose-300 border border-rose-500/30'
              }`}
              title="Immediately stop animation, set preview to #000000, and turn off physical lights"
            >
              <Square className="w-3.5 h-3.5 fill-current" />
              Stop &amp; Off
            </button>
          </div>

          {/* + Add Neighbor House Button */}
          <button
            onClick={handleAddHouseClick}
            disabled={busyHouseAction === 'add'}
            className="px-3 py-2 rounded-xl bg-gradient-to-r from-cyan-500/20 to-indigo-500/25 hover:from-cyan-500/35 hover:to-indigo-500/40 text-cyan-200 border border-cyan-500/40 font-bold flex items-center gap-1.5 transition shadow"
            title="Add a 4th, 5th, or Nth Neighbor House to the street sync"
          >
            <Plus className="w-3.5 h-3.5 text-cyan-300 stroke-[2.5]" />
            <span>+ Add Neighbor House</span>
          </button>

          <div className="bg-slate-900/90 border border-slate-800 rounded-xl px-3 py-1.5 flex items-center gap-1.5">
            <Activity className="w-3.5 h-3.5 text-cyan-400" />
            <span className="text-slate-400">Cycle:</span>
            <span className="text-white font-mono font-semibold">{cycleSeconds}s</span>
            {mappingMode === 'house_normalized' && (
              <span className="text-emerald-400 font-mono">({perHouseSeconds}s/house)</span>
            )}
          </div>
          <div className="bg-slate-900/90 border border-slate-800 rounded-xl px-3 py-1.5 flex items-center gap-1.5">
            {direction === 'forward' && <ArrowRight className="w-3.5 h-3.5 text-emerald-400" />}
            {direction === 'reverse' && <ArrowLeft className="w-3.5 h-3.5 text-amber-400" />}
            {direction === 'pingpong' && <Repeat className="w-3.5 h-3.5 text-purple-400" />}
            <span className="text-slate-400">Flow:</span>
            <span className="text-white font-medium capitalize">{direction}</span>
          </div>
        </div>
      </div>

      {/* 1-Tap Celebration Burst Chips Bar */}
      {onTriggerBurst && (
        <div className="flex flex-wrap items-center justify-between gap-2 bg-slate-950/80 border border-slate-800/80 rounded-xl px-3 py-2">
          <div className="flex items-center gap-1.5 text-xs font-bold text-amber-300">
            <Flame className="w-3.5 h-3.5 text-amber-400" />
            <span>1-Tap 12s Celebration Bursts:</span>
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            {QUICK_BURST_CHIPS.map((chip) => (
              <button
                key={chip.type}
                type="button"
                onClick={() => onTriggerBurst(chip.type)}
                disabled={burstBusy === chip.type}
                className={`px-2.5 py-1 rounded-lg border text-xs font-bold transition ${chip.cls}`}
              >
                {chip.label}
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Architectural House Cards Side by Side (Dynamic 1, 2, 3, or N Houses) */}
      <div className={`grid ${gridColsCls} gap-4`}>
        {houses.map((house, hIdx) => {
          const summary = houseSummaries.find((s) => s.id === house.id);
          const isHouseEnabled = house.enabled !== false;
          const isChaseHere = isRunning && isHouseEnabled && liveState?.active_house_id === house.id;
          const hSegs = houseSegMap[house.id] || [];
          const repColor =
            hSegs.length > 0 ? hSegs[Math.floor(hSegs.length / 2)].hex_color : '#1e293b';
          const connMeta =
            CONNECTION_BADGES[house.connection_type || 'local_lan'] || CONNECTION_BADGES.local_lan;
          const ConnIcon = connMeta.Icon;
          const configuredSegCount =
            hSegs.length ||
            (house.controllers || []).reduce(
              (s, c) => s + (c.enabled !== false ? Number(c.segment_count || 0) : 0),
              0
            ) ||
            9;
          const autoCompByLights =
            avgSegsPerHouse > 0 ? (configuredSegCount / avgSegsPerHouse).toFixed(2) : '1.00';
          const houseTimeWeight = Math.max(0.1, Number(house.time_weight || 1.0));
          const houseSpeedMultiplier = Number((1.0 / houseTimeWeight).toFixed(2));
          const isDefaultHouseSpeed = Math.abs(houseTimeWeight - 1.0) <= 0.02;
          const houseTransitSec =
            speed > 0 && totalEnabledWeight > 0 && isHouseEnabled
              ? ((1 / speed) * (houseTimeWeight / totalEnabledWeight)).toFixed(2)
              : '0.00';

          return (
            <div
              key={house.id}
              className={`relative rounded-xl border transition-all duration-150 p-4 overflow-hidden ${
                !isHouseEnabled
                  ? 'border-slate-800/60 bg-slate-950/45 opacity-65'
                  : isChaseHere
                  ? 'border-cyan-500/70 bg-gradient-to-b from-slate-900/95 to-[#090f1d]'
                  : 'border-slate-800/90 bg-slate-950/75'
              }`}
              style={{
                boxShadow: isChaseHere ? `0 0 28px -8px ${repColor}55` : undefined,
              }}
            >
              {/* Street Sequence Order Bar (1st / 2nd / 3rd / Nth House Selector + Active/Disabled Toggle + Delete) */}
              <div className="flex flex-wrap items-center justify-between gap-2 pb-2.5 mb-3 border-b border-slate-800/80 bg-slate-900/60 -mx-4 -mt-4 px-3.5 py-2">
                <div className="flex items-center gap-1.5 min-w-0 flex-1">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 shrink-0">
                    Order:
                  </span>
                  <select
                    aria-label={`Street order for ${house.name}`}
                    value={hIdx}
                    onChange={(e) => handleMoveHouseToIndex(hIdx, parseInt(e.target.value, 10))}
                    className="bg-slate-950 border border-cyan-500/40 hover:border-cyan-400 rounded-lg px-2 py-1 text-[11px] font-bold text-cyan-300 focus:outline-none focus:border-cyan-300 cursor-pointer truncate"
                  >
                    {houses.map((_, optIdx) => (
                      <option key={optIdx} value={optIdx}>
                        {getPositionLabel(optIdx, houses.length)}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="flex items-center gap-1.5 shrink-0">
                  {/* Quick 1-Click Active / Disabled Toggle Switch */}
                  <button
                    type="button"
                    onClick={() => handleToggleHouseClick(house)}
                    disabled={busyHouseAction === house.id}
                    className={`px-2.5 py-1 rounded-lg text-[10px] font-mono font-bold flex items-center gap-1 border transition ${
                      isHouseEnabled
                        ? 'bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 border-emerald-500/40'
                        : 'bg-slate-900 hover:bg-slate-800 text-slate-400 border-slate-700'
                    }`}
                    title={
                      isHouseEnabled
                        ? `Click to disable ${house.name} (exclude from street sync)`
                        : `Click to enable ${house.name} (include in street sync)`
                    }
                  >
                    <Power className="w-3 h-3" />
                    {isHouseEnabled ? 'Active' : 'Disabled'}
                  </button>

                  <button
                    type="button"
                    onClick={() => handleMoveHouseToIndex(hIdx, hIdx - 1)}
                    disabled={hIdx === 0}
                    className="px-1.5 py-1 rounded-md bg-slate-950 hover:bg-slate-800 disabled:opacity-30 text-[10px] font-semibold text-slate-200 border border-slate-700/80 transition"
                    title="Move house left (earlier in chase sequence)"
                  >
                    ◀
                  </button>
                  <button
                    type="button"
                    onClick={() => handleMoveHouseToIndex(hIdx, hIdx + 1)}
                    disabled={hIdx === houses.length - 1}
                    className="px-1.5 py-1 rounded-md bg-slate-950 hover:bg-slate-800 disabled:opacity-30 text-[10px] font-semibold text-slate-200 border border-slate-700/80 transition"
                    title="Move house right (later in chase sequence)"
                  >
                    ▶
                  </button>

                  {houses.length > 1 && (
                    <button
                      type="button"
                      onClick={() => handleDeleteHouseClick(house)}
                      disabled={busyHouseAction === house.id}
                      className="p-1 rounded-md bg-rose-500/15 hover:bg-rose-500/30 text-rose-300 border border-rose-500/30 transition"
                      title={`Delete ${house.name}`}
                    >
                      <Trash2 className="w-3 h-3" />
                    </button>
                  )}
                </div>
              </div>

              {/* House Header */}
              <div className="flex items-start justify-between gap-2 mb-3">
                <div className="flex items-center gap-2 min-w-0">
                  <div
                    className="w-8 h-8 rounded-lg flex items-center justify-center border border-white/10 shrink-0"
                    style={{ backgroundColor: `${repColor}25` }}
                  >
                    <Home className="w-4 h-4 text-cyan-300" />
                  </div>
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="text-xs font-mono uppercase tracking-wider text-cyan-400 font-bold">
                        {formatOrdinal(hIdx + 1)} House
                      </span>
                      <span
                        className={`inline-flex items-center gap-1 text-[10px] font-mono px-2 py-0.5 rounded-full border ${connMeta.cls}`}
                      >
                        <ConnIcon className="w-2.5 h-2.5" />
                        {connMeta.short}
                      </span>
                      {isChaseHere && (
                        <span className="inline-flex items-center gap-1 text-[10px] font-semibold px-2 py-0.5 rounded-full bg-cyan-500/20 text-cyan-200 border border-cyan-400/40">
                          <Sparkles className="w-2.5 h-2.5" /> ACTIVE PULSE
                        </span>
                      )}
                      {!isHouseEnabled && (
                        <span className="inline-flex items-center gap-1 text-[10px] font-mono px-2 py-0.5 rounded-full bg-slate-800 text-slate-400 border border-slate-700">
                          BYPASSED
                        </span>
                      )}
                    </div>
                    <h3 className="text-sm font-bold text-white leading-tight mt-0.5 truncate">
                      {house.name}
                    </h3>
                  </div>
                </div>

                <div className="text-right shrink-0">
                  <div className="text-xs font-mono text-slate-300">
                    {house.controllers?.filter((c) => c.enabled).length || 0} ctrl ·{' '}
                    <span className="text-cyan-300 font-bold">
                      {hSegs.length ||
                        house.controllers?.reduce(
                          (s, c) => s + (c.enabled ? c.segment_count : 0),
                          0
                        ) ||
                        0}{' '}
                      segs
                    </span>
                  </div>
                  {summary?.compensation_factor && mappingMode === 'house_normalized' && (
                    <div
                      className="text-[11px] font-mono text-emerald-400/90"
                      title="Velocity scale factor applied so this house completes its chase in equal time"
                    >
                      {summary.compensation_factor}× density comp
                    </div>
                  )}
                </div>
              </div>

              {/* Architectural SVG Roofline Silhouette with Live Glowing LEDs */}
              <div className="relative bg-[#050811] border border-slate-800/80 rounded-xl p-3 mb-3">
                <svg viewBox="0 0 300 72" className="w-full h-16 overflow-visible">
                  {/* Pitched Roof + Gable Silhouette */}
                  <polygon
                    points="12,56 95,16 180,56"
                    fill="#0b1120"
                    stroke="#1e293b"
                    strokeWidth="1.5"
                  />
                  <polygon
                    points="135,56 215,22 288,56"
                    fill="#0f172a"
                    stroke="#1e293b"
                    strokeWidth="1.5"
                  />
                  <rect
                    x="22"
                    y="56"
                    width="256"
                    height="14"
                    fill="#090d16"
                    stroke="#1e293b"
                    strokeWidth="1"
                  />

                  {/* Render each segment along the roofline */}
                  {hSegs.map((seg, idx) => {
                    const total = Math.max(1, hSegs.length);
                    const t = (idx + 0.5) / total;
                    const x = 16 + t * 268;
                    let y = 52;
                    if (t < 0.3) {
                      y = 52 - (t / 0.3) * 34;
                    } else if (t < 0.56) {
                      y = 18 + ((t - 0.3) / 0.26) * 34;
                    } else if (t < 0.78) {
                      y = 52 - ((t - 0.56) / 0.22) * 28;
                    } else {
                      y = 24 + ((t - 0.78) / 0.22) * 28;
                    }
                    const dotRadius = Math.max(3.2, Math.min(6.5, 110 / total));

                    return (
                      <g key={`${seg.controller_id}-${seg.segment_index}`}>
                        <circle
                          cx={x}
                          cy={y}
                          r={dotRadius * 2.1}
                          fill={seg.hex_color}
                          opacity="0.28"
                        />
                        <circle
                          cx={x}
                          cy={y}
                          r={dotRadius}
                          fill={seg.hex_color}
                          stroke="#ffffff33"
                          strokeWidth="0.6"
                        />
                      </g>
                    );
                  })}
                </svg>
              </div>

              {/* Per-House Speed Tween Slider & Auto Default (By Light Count) */}
              <div className="bg-slate-900/90 border border-slate-800/90 rounded-xl p-2.5 mb-3 space-y-1.5">
                <div className="flex flex-wrap items-center justify-between gap-1.5 text-[11px]">
                  <div className="flex items-center gap-1.5">
                    <span className="font-bold text-slate-200">House Speed Tween:</span>
                    <span className="font-mono font-extrabold text-cyan-300">
                      {houseSpeedMultiplier.toFixed(2)}x
                    </span>
                    {isHouseEnabled && (
                      <span className="text-[10px] font-mono text-emerald-400">
                        ({houseTransitSec}s transit)
                      </span>
                    )}
                  </div>
                  <button
                    type="button"
                    onClick={() => handleHouseSpeedChange(house, 1.0, true)}
                    className={`px-2 py-0.5 rounded text-[10px] font-mono font-bold border transition ${
                      isDefaultHouseSpeed
                        ? 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40'
                        : 'bg-amber-500/20 hover:bg-amber-500/35 text-amber-200 border-amber-500/40'
                    }`}
                    title={`Reset ${house.name} to Auto Default speed based on its ${configuredSegCount} lights (${autoCompByLights}x density compensation)`}
                  >
                    {isDefaultHouseSpeed
                      ? `✓ Auto Default (${configuredSegCount} lights · ${summary?.compensation_factor || autoCompByLights}×)`
                      : '↺ Auto Default (By Light Count)'}
                  </button>
                </div>

                <div className="flex items-center gap-2">
                  <span className="text-[10px] font-mono text-slate-400">0.25x</span>
                  <input
                    type="range"
                    min="0.25"
                    max="3.00"
                    step="0.05"
                    value={Math.max(0.25, Math.min(3.0, houseSpeedMultiplier))}
                    onChange={(e) => {
                      const sVal = Math.max(0.25, parseFloat(e.target.value) || 1.0);
                      const nextTw = Number((1.0 / sVal).toFixed(3));
                      handleHouseSpeedChange(house, nextTw, false);
                    }}
                    className="flex-1 accent-cyan-400 cursor-pointer"
                    aria-label={`Speed tween slider for ${house.name}`}
                  />
                  <span className="text-[10px] font-mono text-slate-400">3.0x</span>
                </div>
              </div>

              {/* Per-Controller Segment Bars inside this House */}
              <div className="space-y-2.5">
                {house.controllers?.map((ctrl) => {
                  const cSegs = ctrlSegMap[`${house.id}::${ctrl.id}`] || [];
                  const ctrlRepHex = liveState?.controller_colors?.[ctrl.id] || '#0f172a';
                  const isTesting = testingCtrlId === ctrl.id;
                  const feedback = testedCtrlMsg[ctrl.id];

                  return (
                    <div
                      key={ctrl.id}
                      className="bg-slate-900/90 border border-slate-800/90 rounded-lg p-2.5"
                    >
                      <div className="flex items-center justify-between gap-2 text-xs mb-1.5">
                        <div className="flex items-center gap-1.5 truncate">
                          <Cpu className="w-3.5 h-3.5 text-slate-400 shrink-0" />
                          <span className="font-semibold text-slate-200 truncate">{ctrl.name}</span>
                          <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-cyan-300">
                            {ctrl.sku}
                          </span>
                        </div>
                        <div className="flex items-center gap-1.5 shrink-0 font-mono text-[11px]">
                          <span className="text-slate-300">
                            {ctrl.ip || (house.govee_api_key ? 'Cloud Key' : 'Cloud/Internet')}
                          </span>
                          <span className="text-cyan-400 font-semibold">{ctrl.segment_count}s</span>
                          <button
                            onClick={() => handleTestClick(ctrl.id)}
                            disabled={isTesting}
                            className="px-2 py-0.5 rounded bg-cyan-500/20 hover:bg-cyan-500/35 text-cyan-200 border border-cyan-500/40 text-[10px] font-sans font-bold flex items-center gap-1 transition"
                            title={`Send a test color pulse to ${ctrl.name} (${ctrl.ip || ctrl.mac})`}
                          >
                            <Zap className="w-2.5 h-2.5 text-cyan-300" />
                            {feedback || (isTesting ? 'Testing...' : 'Test Light')}
                          </button>
                          <span
                            className="w-3 h-3 rounded-full border border-white/30"
                            style={{ backgroundColor: ctrlRepHex }}
                            title={`Controller LAN colorwc representative output: ${ctrlRepHex}`}
                          />
                        </div>
                      </div>

                      {/* Individual segment pills */}
                      <div
                        className="grid gap-1"
                        style={{
                          gridTemplateColumns: `repeat(${Math.max(
                            1,
                            cSegs.length || ctrl.segment_count
                          )}, minmax(0, 1fr))`,
                        }}
                      >
                        {(cSegs.length > 0
                          ? cSegs
                          : Array.from({ length: ctrl.segment_count }, (_, i) => ({
                              segment_index: i,
                              hex_color: '#1e293b',
                              normalized_pos: 0,
                            }))
                        ).map((seg) => (
                          <div
                            key={seg.segment_index}
                            className="h-4 rounded-[3px] transition-colors duration-75 border border-black/30"
                            style={{
                              backgroundColor: seg.hex_color,
                              boxShadow: isHouseEnabled ? `0 0 8px ${seg.hex_color}66` : 'none',
                            }}
                            title={`Seg #${seg.segment_index + 1} · Pos ${(
                              seg.normalized_pos * 100
                            ).toFixed(1)}% · ${seg.hex_color}`}
                          />
                        ))}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>

      {/* Unified Normalized Virtual Strip Bar (shows how uneven segments map onto 0.0 -> 1.0) */}
      <div className="bg-slate-950/90 border border-slate-800/90 rounded-xl p-3.5">
        <div className="flex flex-wrap items-center justify-between gap-2 text-xs mb-2">
          <span className="font-semibold text-slate-300 flex items-center gap-2">
            Continuous Normalized Timeline Strip (0.00 → 1.00 across {enabledHouses.length} Active{' '}
            {enabledHouses.length === 1 ? 'House' : 'Houses'})
            <span className="hidden sm:inline text-[11px] font-normal text-slate-400">
              — Each segment’s width is automatically scaled to match its house’s time share
            </span>
          </span>
          <span className="font-mono text-cyan-400">
            Master Phase: {(phase * 100).toFixed(1)}%
          </span>
        </div>

        <div className="relative h-7 w-full bg-slate-900 rounded-lg overflow-hidden flex border border-slate-800">
          {segments.map((seg) => (
            <div
              key={seg.global_index}
              style={{
                width: `${Math.max(0.2, seg.normalized_width * 100)}%`,
                backgroundColor: seg.hex_color,
              }}
              className="h-full border-r border-slate-950/30"
              title={`${seg.house_name} · ${seg.controller_name} · Seg #${seg.segment_index + 1} (${(
                seg.normalized_pos * 100
              ).toFixed(1)}%)`}
            />
          ))}

          {/* House boundary markers respecting per-house time_weight */}
          {enabledHouses.length > 1 &&
            (() => {
              let cumW = 0;
              return enabledHouses.slice(0, -1).map((h) => {
                cumW += Math.max(0.1, Number(h.time_weight || 1.0));
                const posPct = (cumW / Math.max(0.1, totalEnabledWeight)) * 100;
                return (
                  <div
                    key={h.id}
                    style={{ left: `${posPct}%` }}
                    className="absolute top-0 bottom-0 w-0.5 bg-white/80 z-10 pointer-events-none"
                  />
                );
              });
            })()}
        </div>

        <div className="flex flex-wrap justify-between gap-2 text-[11px] font-mono text-slate-400 mt-1.5 px-1">
          <span>0% (Start Position #1)</span>
          {enabledHouses.map((h, i) => (
            <span key={h.id} className="text-slate-300">
              #{i + 1} {h.name} (
              {h.controllers?.reduce((a, c) => a + (c.enabled ? c.segment_count : 0), 0)} segs)
            </span>
          ))}
          <span>100% (End → Wrap)</span>
        </div>
      </div>
    </div>
  );
}
