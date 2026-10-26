import React, { useState } from 'react';
import {
  Home,
  Plus,
  Trash2,
  Save,
  RotateCcw,
  Cpu,
  CheckCircle2,
  Wifi,
  Key,
  Globe,
  Zap,
  Terminal,
  Copy,
} from 'lucide-react';
import { getPositionLabel } from './NeighborhoodPreview.jsx';

const PROTOCOL_OPTIONS = [
  { value: 'auto', label: 'Auto (LAN UDP + Cloud Fallback)' },
  { value: 'lan_colorwc', label: 'LAN UDP colorwc (Fastest Whole-Controller)' },
  { value: 'lan_ptreal', label: 'LAN UDP ptReal (BLE-over-LAN Per-Segment)' },
  { value: 'cloud_api', label: 'Govee Cloud API (segmentedColorRgb)' },
  { value: 'simulation', label: 'Simulation / Virtual Only' },
];

const CONNECTION_TYPE_OPTIONS = [
  {
    value: 'local_lan',
    label: 'Local Wi-Fi LAN (UDP :4003) — My House on Same Wi-Fi',
  },
  {
    value: 'govee_cloud',
    label: 'Govee Cloud API (Over Internet — Neighbor on Different Wi-Fi)',
  },
  {
    value: 'neighbor_bridge',
    label: 'Neighbor 25-FPS WebSocket Bridge (Over Internet)',
  },
  {
    value: 'tailscale_vpn',
    label: 'WireGuard / Tailscale VPN IP',
  },
];

export default function HouseConfigEditor({
  config,
  liveState,
  discoveredDevices,
  onSaveConfig,
  onResetConfig,
  onTriggerScan,
  onReorderHouses,
  onDiscoverHouseCloud,
  onTestController,
  onToggleHouse,
  onAddHouse,
  onDeleteHouse,
  onUpdateHouseTimeWeight,
}) {
  const [draftHouses, setDraftHouses] = useState(() =>
    JSON.parse(JSON.stringify(config?.houses || []))
  );
  const [globalApiKey, setGlobalApiKey] = useState(config?.govee_api_key || '');
  const [saving, setSaving] = useState(false);
  const [savedBanner, setSavedBanner] = useState('');
  const [cloudDiscoveringId, setCloudDiscoveringId] = useState(null);
  const [testingCtrlId, setTestingCtrlId] = useState(null);
  const [copiedBridgeHouse, setCopiedBridgeHouse] = useState(null);

  const serverHost =
    typeof window !== 'undefined' && window.location?.host
      ? window.location.host
      : '192.168.1.100:8200';
  const wsProto =
    typeof window !== 'undefined' && window.location?.protocol === 'https:' ? 'wss' : 'ws';
  const httpProto =
    typeof window !== 'undefined' && window.location?.protocol === 'https:' ? 'https' : 'http';

  // Sync draft if parent config changes externally
  React.useEffect(() => {
    if (config?.houses) {
      setDraftHouses(JSON.parse(JSON.stringify(config.houses)));
    }
    if (config) {
      setGlobalApiKey(config.govee_api_key || '');
    }
  }, [config]);

  const updateHouseField = (hIndex, field, value) => {
    setDraftHouses((prev) => {
      const next = [...prev];
      next[hIndex] = { ...next[hIndex], [field]: value };
      return next;
    });
  };

  const moveHouseToIndex = async (fromIndex, toIndex) => {
    if (toIndex < 0 || toIndex >= draftHouses.length || fromIndex === toIndex) return;
    const next = [...draftHouses];
    const [removed] = next.splice(fromIndex, 1);
    next.splice(toIndex, 0, removed);
    const reindexed = next.map((h, i) => ({ ...h, order: i + 1 }));
    setDraftHouses(reindexed);
    if (onReorderHouses) {
      await onReorderHouses(reindexed.map((h) => h.id));
    }
  };

  const addHouse = async () => {
    if (onAddHouse) {
      await onAddHouse();
      return;
    }
    setDraftHouses((prev) => {
      const idx = prev.length + 1;
      return [
        ...prev,
        {
          id: `house-${Date.now()}`,
          name: `Neighbor ${idx} (House #${idx})`,
          order: idx,
          enabled: true,
          time_weight: 1.0,
          connection_type: 'govee_cloud',
          govee_api_key: '',
          bridge_token: '',
          notes: '',
          controllers: [
            {
              id: `h${idx}-ctrl-1`,
              name: `House ${idx} - Controller 1`,
              ip: '',
              mac: `AA:BB:CC:DD:EE:0${idx}`,
              sku: 'H705A',
              segment_count: 12,
              enabled: true,
              reversed: false,
              protocol_mode: 'auto',
              brightness_override: null,
            },
          ],
        },
      ];
    });
  };

  const removeHouse = async (hIndex) => {
    const target = draftHouses[hIndex];
    if (target && onDeleteHouse && draftHouses.length > 1) {
      await onDeleteHouse(target.id);
      return;
    }
    setDraftHouses((prev) =>
      prev.filter((_, i) => i !== hIndex).map((h, i) => ({ ...h, order: i + 1 }))
    );
  };

  const toggleHouseImmediate = async (hIndex) => {
    const target = draftHouses[hIndex];
    if (!target) return;
    const nextEnabled = !target.enabled;
    updateHouseField(hIndex, 'enabled', nextEnabled);
    if (onToggleHouse) {
      await onToggleHouse(target.id, nextEnabled);
    }
  };

  const addController = (hIndex) => {
    setDraftHouses((prev) => {
      const next = [...prev];
      const house = { ...next[hIndex] };
      const cIdx = (house.controllers?.length || 0) + 1;
      house.controllers = [
        ...(house.controllers || []),
        {
          id: `${house.id}-ctrl-${Date.now().toString().slice(-4)}`,
          name: `${house.name.split('(')[0].trim()} - Controller ${cIdx}`,
          ip: '',
          mac: '',
          sku: 'H705A',
          segment_count: 12,
          enabled: true,
          reversed: false,
          protocol_mode: 'auto',
          brightness_override: null,
        },
      ];
      next[hIndex] = house;
      return next;
    });
  };

  const removeController = (hIndex, cIndex) => {
    setDraftHouses((prev) => {
      const next = [...prev];
      const house = { ...next[hIndex] };
      house.controllers = house.controllers.filter((_, i) => i !== cIndex);
      next[hIndex] = house;
      return next;
    });
  };

  const updateControllerField = (hIndex, cIndex, field, value) => {
    setDraftHouses((prev) => {
      const next = [...prev];
      const house = { ...next[hIndex] };
      const ctrls = [...house.controllers];
      ctrls[cIndex] = { ...ctrls[cIndex], [field]: value };
      house.controllers = ctrls;
      next[hIndex] = house;
      return next;
    });
  };

  const assignDiscoveredDevice = (hIndex, cIndex, deviceMac) => {
    const dev = discoveredDevices.find((d) => d.mac === deviceMac);
    if (!dev) return;
    setDraftHouses((prev) => {
      const next = [...prev];
      const house = { ...next[hIndex] };
      const ctrls = [...house.controllers];
      ctrls[cIndex] = {
        ...ctrls[cIndex],
        ip: dev.ip || ctrls[cIndex].ip,
        mac: dev.mac || ctrls[cIndex].mac,
        sku: dev.sku || ctrls[cIndex].sku,
        name: dev.name || ctrls[cIndex].name,
      };
      house.controllers = ctrls;
      next[hIndex] = house;
      return next;
    });
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      await onSaveConfig({
        ...config,
        govee_api_key: globalApiKey,
        houses: draftHouses.map((h, i) => ({ ...h, order: i + 1 })),
      });
      setSavedBanner(
        'Configuration saved permanently to /mnt/media/govee_lights_sync/data/config.json and applied to the real-time animation clock!'
      );
      setTimeout(() => setSavedBanner(''), 3500);
    } finally {
      setSaving(false);
    }
  };

  const handleCloudDiscoverClick = async (hIdx) => {
    const house = draftHouses[hIdx];
    if (!house || !onDiscoverHouseCloud) return;
    setCloudDiscoveringId(house.id);
    try {
      // Save any draft edits first so the house exists & retains connection_type
      await onSaveConfig({
        ...config,
        govee_api_key: globalApiKey,
        houses: draftHouses.map((h, i) => ({ ...h, order: i + 1 })),
      });
      const res = await onDiscoverHouseCloud(house.id, house.govee_api_key || globalApiKey);
      if (res) {
        setSavedBanner(
          res.count > 0
            ? `Discovered and auto-populated ${res.count} Govee Cloud light(s) for ${house.name}!`
            : `Saved API Key for ${house.name}. (Cloud returned 0 devices — check key or enter controller MAC/SKU below.)`
        );
        setTimeout(() => setSavedBanner(''), 4500);
      }
    } finally {
      setCloudDiscoveringId(null);
    }
  };

  const handleTestControllerClick = async (ctrl) => {
    if (!onTestController) return;
    setTestingCtrlId(ctrl.id);
    try {
      const res = await onTestController(ctrl.id);
      setSavedBanner(
        `Sent test color pulse (${res?.color || '#00f5d4'}) to ${ctrl.name} (${
          ctrl.ip || ctrl.mac
        }) via ${res?.transport || 'LAN/Cloud'}!`
      );
      setTimeout(() => setSavedBanner(''), 3500);
    } finally {
      setTestingCtrlId(null);
    }
  };

  const copyBridgeCmd = (houseId) => {
    const cmd = `curl -sSL ${httpProto}://${serverHost}/api/neighbor-bridge.py | python3 - --house-id ${houseId} --server ${wsProto}://${serverHost}`;
    if (navigator?.clipboard) {
      navigator.clipboard.writeText(cmd);
      setCopiedBridgeHouse(houseId);
      setTimeout(() => setCopiedBridgeHouse(null), 2000);
    }
  };

  return (
    <div className="space-y-6">
      {/* Top Action Bar */}
      <div className="bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 className="text-lg font-bold text-white">
            Houses, Street Sequence Order, API Keys &amp; Segment Topology
          </h2>
          <p className="text-xs text-slate-400 mt-0.5">
            Stored permanently in <code className="text-cyan-300">/mnt/media/govee_lights_sync/data/config.json</code>.
            Position #2 is pre-configured with your local{' '}
            <code className="text-emerald-300">
              {draftHouses.find((h) => h.id === 'house-2')?.controllers?.[0]?.ip || '192.168.1.83'} (
              {draftHouses.find((h) => h.id === 'house-2')?.controllers?.[0]?.sku || 'H705E'})
            </code>{' '}
            controller.
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2.5">
          <button
            onClick={onTriggerScan}
            className="px-3.5 py-2 rounded-xl bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-medium flex items-center gap-1.5 border border-slate-700 transition"
          >
            <Wifi className="w-3.5 h-3.5 text-cyan-400" />
            Scan LAN / Cloud Devices ({discoveredDevices?.length || 0})
          </button>

          <button
            onClick={addHouse}
            className="px-3.5 py-2 rounded-xl bg-indigo-600/20 hover:bg-indigo-600/30 text-indigo-300 text-xs font-semibold flex items-center gap-1.5 border border-indigo-500/40 transition"
          >
            <Plus className="w-3.5 h-3.5" />
            Add House
          </button>

          <button
            onClick={onResetConfig}
            className="px-3.5 py-2 rounded-xl bg-slate-900 hover:bg-slate-800 text-slate-400 hover:text-slate-200 text-xs font-medium flex items-center gap-1.5 border border-slate-800 transition"
            title="Restore default 3-house topology (Neighbor 1 -> My House -> Neighbor 2)"
          >
            <RotateCcw className="w-3.5 h-3.5" />
            Reset 3-House Default
          </button>

          <button
            onClick={handleSave}
            disabled={saving}
            className="px-4 py-2 rounded-xl bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 text-slate-950 font-bold text-xs flex items-center gap-1.5 shadow-lg shadow-cyan-500/20 transition"
          >
            <Save className="w-3.5 h-3.5" />
            {saving ? 'Saving...' : 'Save Configuration Permanently'}
          </button>
        </div>
      </div>

      {savedBanner && (
        <div className="bg-emerald-500/15 border border-emerald-500/40 text-emerald-300 px-4 py-3 rounded-xl text-xs flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <span>{savedBanner}</span>
        </div>
      )}

      {/* Global Fallback API Key Bar */}
      <div className="bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2.5">
          <Key className="w-4 h-4 text-amber-400 shrink-0" />
          <div>
            <div className="text-xs font-bold text-white">
              Global Govee Cloud OpenAPI Key (Optional Default Key)
            </div>
            <div className="text-[11px] text-slate-400">
              Used for Cloud discovery &amp; fallback when a house does not specify its own per-house API key below.
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-1 max-w-md">
          <input
            type="password"
            value={globalApiKey}
            onChange={(e) => setGlobalApiKey(e.target.value)}
            placeholder="Paste Global Govee-API-Key (UUID)..."
            className="w-full bg-slate-950 border border-slate-700 rounded-xl px-3 py-1.5 text-xs font-mono text-white"
          />
          <button
            onClick={handleSave}
            className="px-3.5 py-1.5 rounded-xl bg-amber-500/20 hover:bg-amber-500/30 text-amber-200 border border-amber-500/40 text-xs font-bold shrink-0"
          >
            Save Key
          </button>
        </div>
      </div>

      {/* House List */}
      <div className="space-y-5">
        {draftHouses.map((house, hIdx) => {
          const totalSegs = (house.controllers || []).reduce(
            (sum, c) => sum + (c.enabled ? Number(c.segment_count || 0) : 0),
            0
          );
          const isBridgeConnected = (liveState?.bridges || []).some(
            (b) => b.house_id === house.id
          );

          return (
            <div
              key={house.id}
              className="bg-[#0c1222]/90 border border-slate-800/90 rounded-2xl p-5 shadow-xl space-y-4"
            >
              {/* House Top Row: Street Order Selector + Name + Actions */}
              <div className="flex flex-wrap items-center justify-between gap-4 pb-4 border-b border-slate-800/80">
                <div className="flex flex-wrap items-center gap-3 flex-1 min-w-[260px]">
                  {/* Street Order Selector Dropdown */}
                  <div className="flex items-center gap-1.5 bg-slate-950 border border-cyan-500/40 rounded-xl px-2.5 py-1">
                    <span className="text-[10px] font-mono uppercase text-slate-400">
                      Street Order:
                    </span>
                    <select
                      value={hIdx}
                      onChange={(e) => moveHouseToIndex(hIdx, parseInt(e.target.value, 10))}
                      className="bg-transparent text-xs font-bold text-cyan-300 focus:outline-none cursor-pointer"
                    >
                      {draftHouses.map((_, optIdx) => (
                        <option key={optIdx} value={optIdx} className="bg-slate-950 text-white">
                          {getPositionLabel(optIdx, draftHouses.length)}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => moveHouseToIndex(hIdx, hIdx - 1)}
                      disabled={hIdx === 0}
                      className="px-2.5 py-1.5 rounded-lg bg-slate-900 hover:bg-slate-800 disabled:opacity-30 text-slate-200 border border-slate-800 text-xs font-semibold"
                      title="Move House Left (Earlier in Chase Order)"
                    >
                      ◀ Move Left
                    </button>
                    <button
                      onClick={() => moveHouseToIndex(hIdx, hIdx + 1)}
                      disabled={hIdx === draftHouses.length - 1}
                      className="px-2.5 py-1.5 rounded-lg bg-slate-900 hover:bg-slate-800 disabled:opacity-30 text-slate-200 border border-slate-800 text-xs font-semibold"
                      title="Move House Right (Later in Chase Order)"
                    >
                      Move Right ▶
                    </button>
                  </div>

                  <input
                    type="text"
                    value={house.name}
                    onChange={(e) => updateHouseField(hIdx, 'name', e.target.value)}
                    className="bg-slate-900 border border-slate-700/80 rounded-xl px-3 py-1.5 text-sm font-bold text-white focus:outline-none focus:border-cyan-400 w-64"
                    placeholder="House Name"
                  />

                  <button
                    type="button"
                    onClick={() => toggleHouseImmediate(hIdx)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-mono font-bold border transition ${
                      house.enabled
                        ? 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40'
                        : 'bg-slate-900 text-slate-400 border-slate-700'
                    }`}
                  >
                    {house.enabled ? '● Active in Sync' : '○ Disabled'}
                  </button>

                  <div className="flex flex-wrap items-center gap-2 bg-slate-950/90 border border-slate-800 rounded-xl px-3 py-1.5 text-xs">
                    <span className="text-slate-300 font-semibold">House Speed Tween:</span>
                    <span className="font-mono font-extrabold text-cyan-300 w-11">
                      {Number(1.0 / Math.max(0.1, Number(house.time_weight || 1.0))).toFixed(2)}x
                    </span>
                    <input
                      type="range"
                      min="0.25"
                      max="3.00"
                      step="0.05"
                      value={Math.max(
                        0.25,
                        Math.min(3.0, Number((1.0 / Math.max(0.1, Number(house.time_weight || 1.0))).toFixed(2)))
                      )}
                      onChange={(e) => {
                        const s = Math.max(0.25, parseFloat(e.target.value) || 1.0);
                        const tw = Number((1.0 / s).toFixed(3));
                        updateHouseField(hIdx, 'time_weight', tw);
                        if (onUpdateHouseTimeWeight) {
                          onUpdateHouseTimeWeight(house.id, tw, false);
                        }
                      }}
                      className="w-28 accent-cyan-400 cursor-pointer"
                      title="Adjust chase speed across this house relative to its light count"
                    />
                    <button
                      type="button"
                      onClick={() => {
                        updateHouseField(hIdx, 'time_weight', 1.0);
                        if (onUpdateHouseTimeWeight) {
                          onUpdateHouseTimeWeight(house.id, 1.0, true);
                        }
                      }}
                      className={`px-2 py-0.5 rounded text-[10px] font-mono font-bold border transition ${
                        Math.abs(Number(house.time_weight || 1.0) - 1.0) <= 0.02
                          ? 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40'
                          : 'bg-amber-500/20 hover:bg-amber-500/35 text-amber-200 border-amber-500/40'
                      }`}
                      title="Reset to Auto Default speed scaled by this house's number of lights/segments"
                    >
                      {Math.abs(Number(house.time_weight || 1.0) - 1.0) <= 0.02
                        ? `Auto Default (${totalSegs} lights)`
                        : '↺ Auto Default (By Light Count)'}
                    </button>
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <span className="text-xs font-mono px-3 py-1 rounded-lg bg-slate-900 border border-slate-800 text-slate-300">
                    {house.controllers?.length || 0} Controllers ·{' '}
                    <strong className="text-cyan-300">{totalSegs} Segments</strong>
                  </span>

                  <button
                    onClick={() => addController(hIdx)}
                    className="px-3 py-1.5 rounded-lg bg-cyan-500/15 hover:bg-cyan-500/25 text-cyan-300 border border-cyan-500/30 text-xs font-semibold flex items-center gap-1"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    Add Controller
                  </button>

                  {draftHouses.length > 1 && (
                    <button
                      onClick={() => removeHouse(hIdx)}
                      className="p-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-400 border border-rose-500/20"
                      title="Remove House"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  )}
                </div>
              </div>

              {/* Per-House Connection Transport & Neighbor Cloud API Key Row */}
              <div className="bg-slate-950/90 border border-slate-800/90 rounded-xl p-3.5 grid grid-cols-1 lg:grid-cols-12 gap-3 items-end">
                <div className="lg:col-span-4">
                  <label className="block text-[11px] font-semibold text-slate-300 mb-1 flex items-center gap-1.5">
                    <Globe className="w-3.5 h-3.5 text-cyan-400" />
                    House Network / Internet Connection Method
                  </label>
                  <select
                    value={house.connection_type || 'local_lan'}
                    onChange={(e) => updateHouseField(hIdx, 'connection_type', e.target.value)}
                    className="w-full bg-slate-900 border border-slate-700 rounded-lg px-2.5 py-2 text-xs text-white font-medium"
                  >
                    {CONNECTION_TYPE_OPTIONS.map((opt) => (
                      <option key={opt.value} value={opt.value}>
                        {opt.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="lg:col-span-5">
                  <label className="block text-[11px] font-semibold text-amber-300 mb-1 flex items-center gap-1.5">
                    <Key className="w-3.5 h-3.5 text-amber-400" />
                    {house.connection_type === 'local_lan'
                      ? 'Optional Govee Cloud API Key (For Cloud Segment Fallback)'
                      : `Neighbor's Govee Cloud API Key (For ${house.name} on Different Wi-Fi)`}
                  </label>
                  <input
                    type="password"
                    value={house.govee_api_key || ''}
                    onChange={(e) => updateHouseField(hIdx, 'govee_api_key', e.target.value)}
                    placeholder="Paste Neighbor's Govee API Key (Apply for API Key in Govee Home App)..."
                    className="w-full bg-slate-900 border border-amber-500/40 rounded-lg px-3 py-1.5 text-xs font-mono text-white"
                  />
                </div>

                <div className="lg:col-span-3">
                  <button
                    onClick={() => handleCloudDiscoverClick(hIdx)}
                    disabled={cloudDiscoveringId === house.id}
                    className="w-full py-2 px-3 rounded-lg bg-gradient-to-r from-amber-400 to-orange-500 hover:from-amber-300 hover:to-orange-400 text-slate-950 font-bold text-xs flex items-center justify-center gap-1.5 shadow transition"
                  >
                    <Key className="w-3.5 h-3.5" />
                    {cloudDiscoveringId === house.id
                      ? 'Discovering Cloud Lights...'
                      : "Save Key & Auto-Discover Neighbor's Cloud Lights"}
                  </button>
                </div>

                {house.connection_type === 'neighbor_bridge' && (
                  <div className="lg:col-span-12 pt-2 border-t border-slate-800/80 flex flex-wrap items-center justify-between gap-2 text-xs">
                    <div className="flex items-center gap-2 text-purple-300 font-mono text-[11px] truncate">
                      <Terminal className="w-3.5 h-3.5 shrink-0" />
                      <span className="truncate">
                        curl -sSL {httpProto}://{serverHost}/api/neighbor-bridge.py | python3 - --house-id {house.id} --server {wsProto}://{serverHost}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 shrink-0">
                      <span
                        className={`px-2 py-0.5 rounded text-[10px] font-mono ${
                          isBridgeConnected
                            ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                            : 'bg-slate-800 text-slate-400'
                        }`}
                      >
                        {isBridgeConnected ? 'BRIDGE CONNECTED' : 'AWAITING BRIDGE'}
                      </span>
                      <button
                        onClick={() => copyBridgeCmd(house.id)}
                        className="px-2.5 py-1 rounded bg-purple-500/20 hover:bg-purple-500/30 text-purple-200 border border-purple-500/40 text-[11px] font-semibold flex items-center gap-1"
                      >
                        <Copy className="w-3 h-3" />
                        {copiedBridgeHouse === house.id ? 'Copied!' : 'Copy Bridge Command'}
                      </button>
                    </div>
                  </div>
                )}
              </div>

              {/* Controllers Table / Cards */}
              <div className="space-y-3">
                {(house.controllers || []).map((ctrl, cIdx) => (
                  <div
                    key={ctrl.id}
                    className="bg-slate-950/80 border border-slate-800/90 rounded-xl p-3.5 grid grid-cols-1 md:grid-cols-12 gap-3 items-center"
                  >
                    <div className="md:col-span-3">
                      <label className="block text-[10px] uppercase tracking-wider text-slate-400 mb-1">
                        Controller Name
                      </label>
                      <div className="flex items-center gap-2">
                        <Cpu className="w-4 h-4 text-cyan-400 shrink-0" />
                        <input
                          type="text"
                          value={ctrl.name}
                          onChange={(e) =>
                            updateControllerField(hIdx, cIdx, 'name', e.target.value)
                          }
                          className="w-full bg-slate-900 border border-slate-700/80 rounded-lg px-2.5 py-1.5 text-xs text-white"
                        />
                      </div>
                    </div>

                    <div className="md:col-span-2">
                      <label className="block text-[10px] uppercase tracking-wider text-slate-400 mb-1">
                        LAN IPv4 Address
                      </label>
                      <input
                        type="text"
                        value={ctrl.ip}
                        onChange={(e) =>
                          updateControllerField(hIdx, cIdx, 'ip', e.target.value)
                        }
                        placeholder="192.168.1.83 (or blank for Cloud)"
                        className="w-full bg-slate-900 border border-slate-700/80 rounded-lg px-2.5 py-1.5 text-xs font-mono text-cyan-300"
                      />
                    </div>

                    <div className="md:col-span-2">
                      <label className="block text-[10px] uppercase tracking-wider text-slate-400 mb-1">
                        Device MAC / ID
                      </label>
                      <input
                        type="text"
                        value={ctrl.mac}
                        onChange={(e) =>
                          updateControllerField(hIdx, cIdx, 'mac', e.target.value)
                        }
                        placeholder="AA:BB:CC:DD:EE:FF:00:02"
                        className="w-full bg-slate-900 border border-slate-700/80 rounded-lg px-2.5 py-1.5 text-xs font-mono text-slate-200"
                      />
                    </div>

                    <div className="md:col-span-1">
                      <label className="block text-[10px] uppercase tracking-wider text-slate-400 mb-1">
                        Model SKU
                      </label>
                      <input
                        type="text"
                        value={ctrl.sku}
                        onChange={(e) =>
                          updateControllerField(hIdx, cIdx, 'sku', e.target.value)
                        }
                        placeholder="H705E"
                        className="w-full bg-slate-900 border border-slate-700/80 rounded-lg px-2 py-1.5 text-xs font-mono text-slate-200"
                      />
                    </div>

                    <div className="md:col-span-1">
                      <label className="block text-[10px] uppercase tracking-wider text-cyan-400 font-semibold mb-1">
                        Segments
                      </label>
                      <input
                        type="number"
                        min="1"
                        max="200"
                        value={ctrl.segment_count}
                        onChange={(e) =>
                          updateControllerField(
                            hIdx,
                            cIdx,
                            'segment_count',
                            Math.max(1, Math.min(200, parseInt(e.target.value, 10) || 1))
                          )
                        }
                        className="w-full bg-slate-900 border border-cyan-500/40 rounded-lg px-2 py-1.5 text-xs font-mono font-bold text-white text-center"
                      />
                    </div>

                    <div className="md:col-span-2">
                      <label className="block text-[10px] uppercase tracking-wider text-slate-400 mb-1">
                        Protocol Mode
                      </label>
                      <select
                        value={ctrl.protocol_mode}
                        onChange={(e) =>
                          updateControllerField(hIdx, cIdx, 'protocol_mode', e.target.value)
                        }
                        className="w-full bg-slate-900 border border-slate-700/80 rounded-lg px-2 py-1.5 text-xs text-slate-200"
                      >
                        {PROTOCOL_OPTIONS.map((opt) => (
                          <option key={opt.value} value={opt.value}>
                            {opt.label}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="md:col-span-1 flex items-center justify-end gap-1.5 pt-4">
                      <button
                        onClick={() => handleTestControllerClick(ctrl)}
                        disabled={testingCtrlId === ctrl.id}
                        className="px-2 py-1.5 rounded-lg bg-cyan-500/20 hover:bg-cyan-500/35 text-cyan-200 border border-cyan-500/40 text-[10px] font-bold flex items-center gap-1"
                        title="Send a test color pulse to this physical controller"
                      >
                        <Zap className="w-3 h-3" />
                        {testingCtrlId === ctrl.id ? '...' : 'Test'}
                      </button>

                      <label
                        className="flex items-center gap-1 text-[11px] text-slate-400 cursor-pointer"
                        title="Reverse physical segment direction on this controller"
                      >
                        <input
                          type="checkbox"
                          checked={ctrl.reversed}
                          onChange={(e) =>
                            updateControllerField(hIdx, cIdx, 'reversed', e.target.checked)
                          }
                          className="rounded border-slate-700"
                        />
                        Rev
                      </label>

                      {house.controllers.length > 1 && (
                        <button
                          onClick={() => removeController(hIdx, cIdx)}
                          className="p-1.5 rounded-lg bg-rose-500/10 hover:bg-rose-500/20 text-rose-400"
                          title="Delete Controller"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      )}
                    </div>

                    {/* Quick fill from discovered LAN/Cloud devices if available */}
                    {discoveredDevices?.length > 0 && (
                      <div className="md:col-span-12 flex items-center gap-2 pt-1 border-t border-slate-800/50 text-xs">
                        <span className="text-slate-400">Assign discovered Govee device:</span>
                        <select
                          defaultValue=""
                          onChange={(e) => {
                            if (e.target.value) assignDiscoveredDevice(hIdx, cIdx, e.target.value);
                          }}
                          className="bg-slate-900 border border-slate-700 rounded-lg px-2 py-1 text-xs text-cyan-300"
                        >
                          <option value="">
                            -- Select discovered device to autofill IP/MAC/SKU --
                          </option>
                          {discoveredDevices.map((d) => (
                            <option key={d.mac} value={d.mac}>
                              {d.name} · IP: {d.ip || 'Cloud'} · MAC: {d.mac} ({d.sku})
                            </option>
                          ))}
                        </select>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
