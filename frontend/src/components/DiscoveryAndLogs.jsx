import React, { useState } from 'react';
import { Wifi, Terminal, Key, Trash2, RefreshCw, ShieldCheck, Radio } from 'lucide-react';

export default function DiscoveryAndLogs({
  config,
  liveState,
  discoveredDevices,
  onTriggerScan,
  onSaveConfig,
  onClearLogs,
}) {
  const [apiKey, setApiKey] = useState(config?.govee_api_key || '');
  const [lanEnabled, setLanEnabled] = useState(config?.lan_enabled ?? true);
  const [cloudFallback, setCloudFallback] = useState(config?.cloud_fallback_enabled ?? true);
  const [verboseLogs, setVerboseLogs] = useState(config?.verbose_packet_logging ?? true);
  const [scanning, setScanning] = useState(false);

  React.useEffect(() => {
    if (config) {
      setApiKey(config.govee_api_key || '');
      setLanEnabled(config.lan_enabled ?? true);
      setCloudFallback(config.cloud_fallback_enabled ?? true);
      setVerboseLogs(config.verbose_packet_logging ?? true);
    }
  }, [config]);

  const handleScan = async () => {
    setScanning(true);
    try {
      await onTriggerScan();
    } finally {
      setScanning(false);
    }
  };

  const handleSaveTransport = async () => {
    await onSaveConfig({
      ...config,
      govee_api_key: apiKey,
      lan_enabled: lanEnabled,
      cloud_fallback_enabled: cloudFallback,
      verbose_packet_logging: verboseLogs,
    });
  };

  const logs = liveState?.recent_logs || [];
  const stats = liveState?.stats || {};

  return (
    <div className="space-y-6">
      {/* Transport & Cloud API Key Settings + LAN Multicast Discovery */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Radio className="w-5 h-5 text-cyan-400" />
              <h3 className="text-base font-bold text-white">
                Govee LAN Multicast &amp; Cloud Transport Settings
              </h3>
            </div>
            <span className="text-xs font-mono px-2.5 py-0.5 rounded-full bg-emerald-500/15 text-emerald-300 border border-emerald-500/30">
              UDP :4001 / :4002 / :4003
            </span>
          </div>

          <div className="space-y-3 text-xs">
            <label className="flex items-center justify-between p-3 rounded-xl bg-slate-900/90 border border-slate-800 cursor-pointer">
              <div>
                <div className="font-semibold text-white">Enable Govee LAN API (UDP Multicast + Unicast)</div>
                <div className="text-slate-400">
                  Low-latency direct WiFi control via 239.255.255.250:4001 &amp; device :4003
                </div>
              </div>
              <input
                type="checkbox"
                checked={lanEnabled}
                onChange={(e) => setLanEnabled(e.target.checked)}
                className="rounded border-slate-700 text-cyan-500"
              />
            </label>

            <label className="flex items-center justify-between p-3 rounded-xl bg-slate-900/90 border border-slate-800 cursor-pointer">
              <div>
                <div className="font-semibold text-white">Enable Govee Cloud OpenAPI v1 Fallback</div>
                <div className="text-slate-400">
                  Fallback for <code className="text-cyan-300">segmentedColorRgb</code> &amp; cloud device discovery
                </div>
              </div>
              <input
                type="checkbox"
                checked={cloudFallback}
                onChange={(e) => setCloudFallback(e.target.checked)}
                className="rounded border-slate-700 text-cyan-500"
              />
            </label>

            <label className="flex items-center justify-between p-3 rounded-xl bg-slate-900/90 border border-slate-800 cursor-pointer">
              <div>
                <div className="font-semibold text-white">Verbose Controller Packet Logging</div>
                <div className="text-slate-400">
                  Record live telemetry for every UDP/Cloud command sent to each house controller
                </div>
              </div>
              <input
                type="checkbox"
                checked={verboseLogs}
                onChange={(e) => setVerboseLogs(e.target.checked)}
                className="rounded border-slate-700 text-cyan-500"
              />
            </label>

            <div className="p-3 rounded-xl bg-slate-900/90 border border-slate-800 space-y-1.5">
              <label className="flex items-center gap-1.5 font-semibold text-slate-200">
                <Key className="w-3.5 h-3.5 text-amber-400" />
                Govee Developer Cloud API Key (Optional)
              </label>
              <input
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder="Paste Govee-API-Key or set GOVEE_API_KEY in .env"
                className="w-full bg-slate-950 border border-slate-700 rounded-lg px-3 py-2 text-xs font-mono text-white"
              />
            </div>

            <button
              onClick={handleSaveTransport}
              className="w-full py-2.5 rounded-xl bg-cyan-500 hover:bg-cyan-400 text-slate-950 font-bold text-xs transition"
            >
              Save Transport &amp; API Settings
            </button>
          </div>
        </div>

        {/* Discovered Devices Panel */}
        <div className="bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <Wifi className="w-5 h-5 text-emerald-400" />
                <h3 className="text-base font-bold text-white">Discovered Govee Devices</h3>
              </div>
              <button
                onClick={handleScan}
                disabled={scanning}
                className="px-3.5 py-1.5 rounded-xl bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 border border-emerald-500/40 text-xs font-semibold flex items-center gap-1.5 transition"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${scanning ? 'animate-spin' : ''}`} />
                {scanning ? 'Scanning LAN & Cloud...' : 'Scan Network Now'}
              </button>
            </div>

            {discoveredDevices?.length === 0 ? (
              <div className="bg-slate-950/70 border border-slate-800/80 rounded-xl p-6 text-center text-xs text-slate-400 space-y-2">
                <p className="text-slate-300 font-medium">
                  No automatic broadcast responses received yet on UDP port 4002.
                </p>
                <p>
                  Make sure <strong>LAN Control</strong> is toggled ON in the Govee Home mobile app for each controller,
                  or enter controller IPs/MACs manually in the <strong>Houses &amp; Controllers</strong> tab.
                </p>
              </div>
            ) : (
              <div className="space-y-2.5 max-h-64 overflow-y-auto pr-1">
                {discoveredDevices.map((dev) => (
                  <div
                    key={dev.mac}
                    className="bg-slate-900/90 border border-slate-800 rounded-xl p-3 flex items-center justify-between text-xs"
                  >
                    <div>
                      <div className="font-bold text-white flex items-center gap-2">
                        {dev.name || dev.sku}
                        <span className="px-2 py-0.5 rounded bg-cyan-500/15 text-cyan-300 font-mono text-[10px]">
                          {dev.sku}
                        </span>
                      </div>
                      <div className="text-slate-400 font-mono text-[11px] mt-0.5">
                        IP: <span className="text-slate-200">{dev.ip || 'Cloud'}</span> · MAC:{' '}
                        <span className="text-slate-200">{dev.mac}</span>
                      </div>
                    </div>
                    <span className="px-2 py-1 rounded-lg bg-emerald-500/15 text-emerald-300 font-mono text-[10px] uppercase">
                      {dev.source}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Protocol Telemetry Counters */}
          <div className="grid grid-cols-4 gap-2 pt-4 mt-4 border-t border-slate-800/80 text-center">
            <div className="bg-slate-950/80 rounded-xl p-2 border border-slate-800/80">
              <div className="text-[10px] text-slate-400 uppercase">LAN colorwc</div>
              <div className="text-sm font-mono font-bold text-cyan-300">
                {stats.lan_packets_sent || 0}
              </div>
            </div>
            <div className="bg-slate-950/80 rounded-xl p-2 border border-slate-800/80">
              <div className="text-[10px] text-slate-400 uppercase">LAN ptReal</div>
              <div className="text-sm font-mono font-bold text-purple-300">
                {stats.lan_ptreal_packets_sent || 0}
              </div>
            </div>
            <div className="bg-slate-950/80 rounded-xl p-2 border border-slate-800/80">
              <div className="text-[10px] text-slate-400 uppercase">Cloud API</div>
              <div className="text-sm font-mono font-bold text-amber-300">
                {stats.cloud_requests_sent || 0}
              </div>
            </div>
            <div className="bg-slate-950/80 rounded-xl p-2 border border-slate-800/80">
              <div className="text-[10px] text-slate-400 uppercase">Dedup Saved</div>
              <div className="text-sm font-mono font-bold text-emerald-300">
                {stats.dedup_skipped || 0}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Live Controller Packet Dispatch Log */}
      <div className="bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <Terminal className="w-5 h-5 text-cyan-400" />
            <div>
              <h3 className="text-base font-bold text-white">
                Real-Time Controller Dispatch Log
              </h3>
              <p className="text-xs text-slate-400">
                Live stream of UDP &amp; Cloud commands sent to each house controller
              </p>
            </div>
          </div>

          <button
            onClick={onClearLogs}
            className="px-3 py-1.5 rounded-xl bg-slate-900 hover:bg-slate-800 text-slate-300 border border-slate-800 text-xs flex items-center gap-1.5"
          >
            <Trash2 className="w-3.5 h-3.5" />
            Clear Log
          </button>
        </div>

        <div className="bg-[#060912] border border-slate-800/90 rounded-xl overflow-hidden">
          <div className="max-h-96 overflow-y-auto font-mono text-xs divide-y divide-slate-900">
            {logs.length === 0 ? (
              <div className="p-6 text-center text-slate-500">
                Waiting for controller packet dispatches...
              </div>
            ) : (
              logs.map((entry, idx) => (
                <div
                  key={`${entry.timestamp}-${entry.controller_id}-${idx}`}
                  className="px-3.5 py-2 flex flex-wrap items-center justify-between gap-2 hover:bg-slate-900/50"
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    <span className="text-slate-500 shrink-0">{entry.iso_time}</span>
                    <span
                      className="w-3 h-3 rounded-full shrink-0 border border-white/20"
                      style={{ backgroundColor: entry.rgb_preview }}
                    />
                    <span className="px-1.5 py-0.5 rounded bg-slate-800 text-cyan-300 text-[10px] shrink-0">
                      {entry.protocol}
                    </span>
                    <span className="text-slate-200 font-semibold shrink-0">
                      {entry.house_name}
                    </span>
                    <span className="text-slate-400 shrink-0">→ {entry.controller_name}</span>
                    <span className="text-emerald-300 truncate">{entry.summary}</span>
                  </div>
                  <div className="text-[11px] text-slate-500 shrink-0">
                    {entry.latency_ms}ms
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
