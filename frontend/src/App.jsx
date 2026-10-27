import React, { useEffect, useState, useRef, useCallback } from 'react';
import {
  Play,
  Pause,
  Square,
  Sliders,
  Home,
  Radio,
  Sparkles,
  Zap,
  RefreshCw,
  Power,
  Layers,
  Gauge,
  Key,
  Globe,
  Terminal,
  CheckCircle2,
  Copy,
  Shield,
  Smartphone,
  Download,
  Users,
  LogOut,
  Lock,
  Clock,
  ListMusic,
  Flame,
  Plus,
  Trash2,
  MapPin,
  Calendar,
} from 'lucide-react';
import NeighborhoodPreview, { getPositionLabel } from './components/NeighborhoodPreview.jsx';
import HouseConfigEditor from './components/HouseConfigEditor.jsx';
import DiscoveryAndLogs from './components/DiscoveryAndLogs.jsx';
import LiveSceneCardPreview from './components/LiveSceneCardPreview.jsx';

/**
 * Custom 3-House Neon Roofline Brand Logo (`<BrandLogo />`).
 * Depicts 3 pitched house rooflines side-by-side bridged by a glowing
 * cyan (#00f5d4) -> violet (#a855f7) -> gold/magenta (#fbbf24 / #ff007f) light wave
 * on a deep obsidian rounded square.
 */
export function BrandLogo({ className = 'w-10 h-10' }) {
  return (
    <svg
      viewBox="0 0 64 64"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={`shrink-0 select-none ${className}`}
      aria-label="Govee Multi-House Light Sync Logo"
    >
      <defs>
        <linearGradient id="brandBgGrad" x1="0" y1="0" x2="64" y2="64" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stopColor="#070c1b" />
          <stop offset="55%" stopColor="#0a1022" />
          <stop offset="100%" stopColor="#040711" />
        </linearGradient>
        <linearGradient id="brandNeonWave" x1="4" y1="32" x2="60" y2="32" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stopColor="#00f5d4" />
          <stop offset="48%" stopColor="#a855f7" />
          <stop offset="78%" stopColor="#ff007f" />
          <stop offset="100%" stopColor="#fbbf24" />
        </linearGradient>
        <linearGradient id="brandBorderGrad" x1="0" y1="0" x2="64" y2="64" gradientUnits="userSpaceOnUse">
          <stop offset="0%" stopColor="#00f5d4" stopOpacity="0.75" />
          <stop offset="50%" stopColor="#a855f7" stopOpacity="0.6" />
          <stop offset="100%" stopColor="#fbbf24" stopOpacity="0.75" />
        </linearGradient>
      </defs>
      <rect
        x="2"
        y="2"
        width="60"
        height="60"
        rx="15"
        fill="url(#brandBgGrad)"
        stroke="url(#brandBorderGrad)"
        strokeWidth="2"
      />
      <circle cx="32" cy="28" r="17" fill="#a855f7" fillOpacity="0.14" />
      <circle cx="15" cy="34" r="10" fill="#00f5d4" fillOpacity="0.12" />
      <circle cx="49" cy="34" r="10" fill="#ff007f" fillOpacity="0.12" />
      {/* 3 Pitched House Silhouettes */}
      <path d="M6 37 L14.5 26.5 L23 37 V47 H6 Z" fill="#0b1328" stroke="#1e293b" strokeWidth="1.2" />
      <path d="M21 35 L32 20.5 L43 35 V47 H21 Z" fill="#101b37" stroke="#334155" strokeWidth="1.3" />
      <path d="M41 37 L49.5 26.5 L58 37 V47 H41 Z" fill="#0b1328" stroke="#1e293b" strokeWidth="1.2" />
      {/* 3-House Neon Roofline Strip */}
      <path
        d="M5.5 37 L14.5 26 L22 35.2 L32 20 L42 35.2 L49.5 26 L58.5 37"
        stroke="url(#brandNeonWave)"
        strokeWidth="3.2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* Bridging Street Light Wave */}
      <path
        d="M6 52 C 16 47.5, 24 56.5, 32 51.5 C 40 46.5, 48 55.5, 58 50.5"
        stroke="url(#brandNeonWave)"
        strokeWidth="2.4"
        strokeLinecap="round"
      />
      <circle cx="14.5" cy="26" r="2.3" fill="#00f5d4" />
      <circle cx="32" cy="20" r="2.7" fill="#a855f7" stroke="#ffffff" strokeWidth="0.8" />
      <circle cx="49.5" cy="26" r="2.3" fill="#fbbf24" />
    </svg>
  );
}

const CONNECTION_OPTIONS = [
  {
    value: 'local_lan',
    label: 'Local Wi-Fi LAN (UDP :4003)',
    badge: 'LOCAL LAN UDP',
    badgeCls: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
  },
  {
    value: 'govee_cloud',
    label: 'Govee Cloud API (Over Internet - Different Wi-Fi)',
    badge: 'CLOUD INTERNET',
    badgeCls: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
  },
  {
    value: 'neighbor_bridge',
    label: 'Neighbor 25-FPS WebSocket Bridge (Over Internet)',
    badge: '25-FPS BRIDGE',
    badgeCls: 'bg-purple-500/15 text-purple-300 border-purple-500/30',
  },
  {
    value: 'tailscale_vpn',
    label: 'WireGuard / Tailscale VPN IP',
    badge: 'VPN DIRECT',
    badgeCls: 'bg-cyan-500/15 text-cyan-300 border-cyan-500/30',
  },
];

const EFFECTS = [
  {
    id: 'multi_house_chase',
    name: 'Smooth Multi-House Chase',
    badge: 'MAIN · ZERO-DRIFT',
    desc: 'Continuous glowing chase head & gradient tail flowing seamlessly House 1 → House 2 → House 3',
    previewColors: ['#00f5d4', '#7b2cbf', '#ff007f'],
  },
  {
    id: 'center_out_shockwave',
    name: 'Center-Out Shockwave (My House → Out)',
    badge: 'MIDDLE → BOTH NEIGHBORS',
    desc: 'Symmetrical neon shockwave originating at My House (#2 Middle) and blasting outward to both neighbors!',
    previewColors: ['#00f5d4', '#8b5cf6', '#ff007f'],
  },
  {
    id: 'halloween_spooky',
    name: 'Halloween Phantom & Lightning',
    badge: 'HALLOWEEN',
    desc: 'Haunted purple, toxic green & pumpkin orange phantom orbs traveling across rooflines with lightning flashes',
    previewColors: ['#9333ea', '#22c55e', '#f97316'],
  },
  {
    id: 'christmas_magic',
    name: 'Christmas Candy Cane & Sleigh',
    badge: 'CHRISTMAS',
    desc: 'Rotating crimson, snow-white & emerald candy-cane ribbons with a sparkling gold sleigh head',
    previewColors: ['#ef4444', '#10b981', '#fbbf24'],
  },
  {
    id: 'diwali_festival',
    name: 'Diwali Diya & Rangoli Cascade',
    badge: 'DIWALI',
    desc: 'Warm saffron gold, marigold & royal magenta rangoli waves with flickering oil-lamp (diya) shimmer',
    previewColors: ['#f59e0b', '#fbbf24', '#ec4899'],
  },
  {
    id: 'lightning_storm',
    name: 'Rolling Thunder & Chain Lightning',
    badge: 'STORM',
    desc: 'Deep storm clouds with high-velocity electric chain lightning bolts jumping House 1 → 2 → 3',
    previewColors: ['#38bdf8', '#7e22ce', '#e0f2fe'],
  },
  {
    id: 'cyber_snake',
    name: 'Dual Neon Serpent Clash',
    badge: 'DUAL CLASH',
    desc: 'Two opposing neon serpents weaving through all 3 houses and bursting with sparks when they cross at My House',
    previewColors: ['#10b981', '#3b82f6', '#f43f5e'],
  },
  {
    id: 'rainbow_wave',
    name: 'Continuous Rainbow Wave',
    badge: 'SPECTRUM',
    desc: 'Full HSV rainbow wave spanning all houses with normalized phase alignment',
    previewColors: ['#ff0055', '#00ffcc', '#ffee00'],
  },
  {
    id: 'comet_meteor',
    name: 'Comet / Meteor Shower',
    badge: 'HIGH IMPACT',
    desc: 'White-hot meteor core with shimmering plasma tail streaking across houses',
    previewColors: ['#38bdf8', '#6366f1', '#f43f5e'],
  },
  {
    id: 'breathing_pulse',
    name: 'Synchronized Breathing',
    badge: 'LOCKSTEP',
    desc: 'Deep harmonic pulse synchronized across every house and controller',
    previewColors: ['#10b981', '#3b82f6', '#8b5cf6'],
  },
  {
    id: 'color_wipe',
    name: 'Multi-House Color Wipe',
    badge: 'PROGRESSIVE',
    desc: 'Anti-aliased color wipe filling House 1 → House 2 → House 3 in sequence',
    previewColors: ['#00f5d4', '#8b5cf6', '#f43f5e'],
  },
  {
    id: 'theater_chase',
    name: 'Compensated Theater Chase',
    badge: 'MARQUEE',
    desc: 'Classic marquee chase scaled to virtual strip density so uneven strips march in unison',
    previewColors: ['#fbbf24', '#ef4444', '#ffffff'],
  },
  {
    id: 'fire_sparkle',
    name: 'Fire & Rising Embers',
    badge: 'ORGANIC',
    desc: 'Deterministic Perlin/value noise hearth flame sweeping across all rooflines',
    previewColors: ['#ff5500', '#ffaa00', '#ffee88'],
  },
  {
    id: 'sparkle_twinkle',
    name: 'Starlight Sparkle & Aurora',
    badge: 'TWINKLE',
    desc: 'Glittering white/accent starlight bursts over a flowing aurora wave',
    previewColors: ['#38bdf8', '#f8fafc', '#3b82f6'],
  },
  {
    id: 'govee_rainbow1',
    name: 'Govee Rainbow 1 (Seamless Gradient)',
    badge: 'RAINBOW 1',
    desc: '100%-lit gapless 4-stop gradient ribbon gliding smoothly across all 3 houses',
    previewColors: ['#ff6b00', '#9333ea', '#22c55e'],
  },
  {
    id: 'govee_rainbow2',
    name: 'Govee Rainbow 2 (Stepped Color Blocks)',
    badge: 'RAINBOW 2',
    desc: 'Crisp marching holiday color blocks with anti-aliased edges and crystal shimmer',
    previewColors: ['#ef4444', '#10b981', '#fbbf24'],
  },
];

const SCENE_CATEGORIES = [
  { id: 'all', label: '✨ All Scenes' },
  { id: 'Halloween', label: '🎃 Halloween' },
  { id: 'Christmas', label: '🎄 Christmas' },
  { id: 'Diwali', label: '🪔 Diwali' },
  { id: 'Center-Out (My House)', label: '💥 Center-Out (From My House)' },
  { id: 'Cyber & Party', label: '⚡ Cyber & Party' },
  { id: 'Celebrations', label: '🏈 Celebrations' },
];

const BURST_BUTTONS = [
  {
    type: 'touchdown',
    label: '🏈 Seahawks Touchdown',
    sub: '12s Action Green & Navy Blitz',
    cls: 'from-emerald-500/25 to-blue-900/40 border-emerald-400/50 text-emerald-200 hover:border-emerald-300',
  },
  {
    type: 'lightning',
    label: '⚡ Lightning Strike',
    sub: '12s Megavolt Chain Storm',
    cls: 'from-cyan-500/25 to-purple-900/40 border-cyan-400/50 text-cyan-200 hover:border-cyan-300',
  },
  {
    type: 'new_year',
    label: '🎆 New Year Countdown',
    sub: '12s Grand Finale Skyrockets',
    cls: 'from-amber-500/25 to-rose-900/40 border-amber-400/50 text-amber-200 hover:border-amber-300',
  },
  {
    type: 'strobe',
    label: '🎉 Party Strobe',
    sub: '12s Hyper Neon Street Party',
    cls: 'from-fuchsia-500/25 to-indigo-900/40 border-fuchsia-400/50 text-fuchsia-200 hover:border-fuchsia-300',
  },
];

const MAPPING_MODES = [
  {
    id: 'house_normalized',
    name: 'House-Normalized Equal Time (Recommended)',
    desc: 'Each house takes the exact same transit time (e.g. 1/3 of cycle) regardless of controller or segment count.',
  },
  {
    id: 'virtual_strip',
    name: 'Continuous Virtual Strip (Uniform Per-Segment)',
    desc: 'Treats all segments across all houses as one uniform LED strip with constant speed per physical segment.',
  },
  {
    id: 'parallel_zones',
    name: 'Synchronized Parallel House Zones',
    desc: 'Every house runs the exact same [0..1] normalized effect simultaneously in lockstep.',
  },
];

const WEEKDAYS = [
  { id: 'mon', label: 'Mon' },
  { id: 'tue', label: 'Tue' },
  { id: 'wed', label: 'Wed' },
  { id: 'thu', label: 'Thu' },
  { id: 'fri', label: 'Fri' },
  { id: 'sat', label: 'Sat' },
  { id: 'sun', label: 'Sun' },
];

const TOKEN_STORAGE_KEY = 'govee_sync_token';

function getStoredToken() {
  if (typeof window === 'undefined') return '';
  try {
    return window.localStorage.getItem(TOKEN_STORAGE_KEY) || '';
  } catch (e) {
    return '';
  }
}

function detectBrowserTimezone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Los_Angeles';
  } catch (e) {
    return 'America/Los_Angeles';
  }
}

export default function App() {
  const [activeTab, setActiveTab] = useState('scenes');
  const [sceneCategory, setSceneCategory] = useState('all');
  const [activePresetId, setActivePresetId] = useState('cyber_chase');
  const [config, setConfig] = useState(null);
  const [liveState, setLiveState] = useState(null);
  const [presets, setPresets] = useState([]);
  const [discoveredDevices, setDiscoveredDevices] = useState([]);
  const [wsConnected, setWsConnected] = useState(false);
  const [houseKeyDrafts, setHouseKeyDrafts] = useState({});
  const [globalKeyDraft, setGlobalKeyDraft] = useState('');
  const [actionBanner, setActionBanner] = useState('');
  const [busyHouseId, setBusyHouseId] = useState(null);
  const [copiedHouseCmd, setCopiedHouseCmd] = useState(null);

  // Schedule state & server status
  const [scheduleStatus, setScheduleStatus] = useState(null);
  const [scheduleDraft, setScheduleDraft] = useState({
    enabled: false,
    start_time: '17:30',
    stop_time: '23:00',
    preset_id: 'cyber_chase',
    timezone: detectBrowserTimezone(),
    days_of_week: ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'],
    turn_off_lights_on_stop: true,
    override_govee_app_schedules: false,
  });
  const [savingSchedule, setSavingSchedule] = useState(false);

  // Auth & Users state
  const [authToken, setAuthToken] = useState(() => getStoredToken());
  const [authStatus, setAuthStatus] = useState({
    loading: true,
    authenticated: true,
    auth_required: false,
    user: null,
    owner: 'owner@example.com',
  });
  const [authorizedEmails, setAuthorizedEmails] = useState(['owner@example.com']);
  const [newEmailInput, setNewEmailInput] = useState('');
  const [authErrorMsg, setAuthErrorMsg] = useState('');
  const [apkInfo, setApkInfo] = useState({
    available: true,
    version_name: '3.1.0',
    version_code: 4,
    size_bytes: 0,
    sha256: '',
    released_at: '',
    filename: 'Govee-Sync-Studio-v3.1.0-b4.apk',
    download_url: '/api/apk/download?version=3.1.0',
    changelog: [],
    releases: [],
  });
  const [burstBusy, setBurstBusy] = useState('');

  const patchTimerRef = useRef(null);
  const houseSpeedTimerRef = useRef({});
  const autoSyncedTzRef = useRef(false);

  // Capture ?auth_token=... from OAuth redirect
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const params = new URLSearchParams(window.location.search);
    const urlTok = params.get('auth_token');
    const urlErr = params.get('error');
    if (urlTok) {
      try {
        window.localStorage.setItem(TOKEN_STORAGE_KEY, urlTok);
      } catch (e) {
        // ignore storage errors
      }
      setAuthToken(urlTok);
      params.delete('auth_token');
      const cleanSearch = params.toString();
      const nextUrl = window.location.pathname + (cleanSearch ? `?${cleanSearch}` : '');
      window.history.replaceState({}, '', nextUrl);
    }
    if (urlErr) {
      setAuthErrorMsg(`Authentication error: ${urlErr}`);
    }
  }, []);

  const apiFetch = useCallback(
    async (url, options = {}) => {
      const tok = authToken || getStoredToken();
      const headers = { ...(options.headers || {}) };
      if (tok) {
        headers.Authorization = `Bearer ${tok}`;
      }
      return fetch(url, {
        ...options,
        credentials: 'include',
        headers,
      });
    },
    [authToken]
  );

  const serverHost =
    typeof window !== 'undefined' && window.location?.host
      ? window.location.host
      : '192.168.1.100:8200';
  const wsProto =
    typeof window !== 'undefined' && window.location?.protocol === 'https:' ? 'wss' : 'ws';
  const httpProto =
    typeof window !== 'undefined' && window.location?.protocol === 'https:' ? 'https' : 'http';

  const showBanner = (msg) => {
    setActionBanner(msg);
    setTimeout(() => setActionBanner(''), 4200);
  };

  const fetchAuthorizedUsers = useCallback(async () => {
    try {
      const res = await apiFetch('/api/auth/users');
      if (res.ok) {
        const data = await res.json();
        setAuthorizedEmails(data.authorized_emails || [data.owner || 'owner@example.com']);
      }
    } catch (err) {
      // ignore if unauthenticated
    }
  }, [apiFetch]);

  const fetchInitialData = useCallback(async () => {
    try {
      const [authRes, apkRes] = await Promise.all([
        apiFetch('/api/auth/status'),
        apiFetch('/api/apk/info'),
      ]);
      if (apkRes.ok) {
        setApkInfo(await apkRes.json());
      }
      if (authRes.ok) {
        const st = await authRes.json();
        setAuthStatus({
          loading: false,
          authenticated: Boolean(st.authenticated || !st.auth_required),
          auth_required: Boolean(st.auth_required),
          user: st.user || null,
          owner: st.owner || 'owner@example.com',
        });
        if (st.auth_required && !st.authenticated) {
          return;
        }
      } else {
        setAuthStatus((prev) => ({ ...prev, loading: false }));
      }

      const [cfgRes, stateRes, presetsRes, discRes, schedRes] = await Promise.all([
        apiFetch('/api/config'),
        apiFetch('/api/state'),
        apiFetch('/api/presets'),
        apiFetch('/api/discover'),
        apiFetch('/api/schedule'),
      ]);
      if (cfgRes.status === 401 || cfgRes.status === 403) {
        setAuthStatus((prev) => ({
          ...prev,
          loading: false,
          authenticated: false,
          auth_required: true,
        }));
        return;
      }
      if (cfgRes.ok) {
        const c = await cfgRes.json();
        setConfig(c);
        setGlobalKeyDraft(c.govee_api_key || '');
        if (c.authorized_emails) {
          setAuthorizedEmails(c.authorized_emails);
        }
        const keyMap = {};
        (c.houses || []).forEach((h) => {
          keyMap[h.id] = h.govee_api_key || '';
        });
        setHouseKeyDrafts(keyMap);

        const detectedTz = detectBrowserTimezone();
        if (c.schedule) {
          setScheduleDraft({
            enabled: Boolean(c.schedule.enabled),
            start_time: c.schedule.start_time || '17:30',
            stop_time: c.schedule.stop_time || '23:00',
            preset_id: c.schedule.preset_id || 'cyber_chase',
            timezone: c.schedule.timezone || detectedTz,
            days_of_week:
              Array.isArray(c.schedule.days_of_week) && c.schedule.days_of_week.length > 0
                ? c.schedule.days_of_week
                : ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'],
            turn_off_lights_on_stop: c.schedule.turn_off_lights_on_stop ?? true,
            override_govee_app_schedules: Boolean(c.schedule.override_govee_app_schedules),
          });
        }
        // Automatically sync detected IANA timezone if config.schedule.timezone is empty
        if (!c.schedule?.timezone && detectedTz && !autoSyncedTzRef.current) {
          autoSyncedTzRef.current = true;
          apiFetch('/api/schedule', {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ timezone: detectedTz, apply_now_if_in_window: false }),
          })
            .then((r) => (r.ok ? r.json() : null))
            .then((d) => {
              if (d?.schedule_status) setScheduleStatus(d.schedule_status);
              if (d?.config) setConfig(d.config);
            })
            .catch(() => {});
        }
      }
      if (stateRes.ok) {
        const s = await stateRes.json();
        setLiveState(s);
        if (s.active_preset_id) setActivePresetId(s.active_preset_id);
        if (s.schedule_status) setScheduleStatus(s.schedule_status);
      }
      if (schedRes.ok) {
        setScheduleStatus(await schedRes.json());
      }
      if (presetsRes.ok) setPresets(await presetsRes.json());
      if (discRes.ok) {
        const d = await discRes.json();
        setDiscoveredDevices(d.devices || []);
      }
      fetchAuthorizedUsers();
    } catch (err) {
      console.error('Failed to fetch initial state:', err);
      setAuthStatus((prev) => ({ ...prev, loading: false }));
    }
  }, [apiFetch, fetchAuthorizedUsers]);

  useEffect(() => {
    fetchInitialData();
  }, [fetchInitialData]);

  useEffect(() => {
    if (config) {
      setGlobalKeyDraft(config.govee_api_key || '');
      setHouseKeyDrafts((prev) => {
        const next = { ...prev };
        (config.houses || []).forEach((h) => {
          if (next[h.id] === undefined || h.govee_api_key) {
            next[h.id] = h.govee_api_key || '';
          }
        });
        return next;
      });
      if (config.schedule) {
        setScheduleDraft((prev) => ({
          ...prev,
          enabled: Boolean(config.schedule.enabled),
          start_time: config.schedule.start_time || prev.start_time || '17:30',
          stop_time: config.schedule.stop_time || prev.stop_time || '23:00',
          preset_id: config.schedule.preset_id || prev.preset_id || 'cyber_chase',
          timezone: config.schedule.timezone || prev.timezone || detectBrowserTimezone(),
          days_of_week:
            Array.isArray(config.schedule.days_of_week) && config.schedule.days_of_week.length > 0
              ? config.schedule.days_of_week
              : prev.days_of_week,
          turn_off_lights_on_stop: config.schedule.turn_off_lights_on_stop ?? true,
          override_govee_app_schedules: Boolean(config.schedule.override_govee_app_schedules),
        }));
      }
    }
  }, [config]);

  // Connect live WebSocket stream (/ws/live) for 25 FPS preview & telemetry
  useEffect(() => {
    if (authStatus.auth_required && !authStatus.authenticated) return undefined;
    let ws;
    let reconnectTimer;
    const connectWs = () => {
      const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const tok = authToken || getStoredToken();
      const qs = tok ? `?token=${encodeURIComponent(tok)}` : '';
      ws = new WebSocket(`${proto}//${window.location.host}/ws/live${qs}`);
      ws.onopen = () => setWsConnected(true);
      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          setLiveState(data);
          if (data.active_preset_id) {
            setActivePresetId(data.active_preset_id);
          }
          if (data.schedule_status) {
            setScheduleStatus(data.schedule_status);
          }
        } catch (err) {
          // ignore parse error
        }
      };
      ws.onclose = () => {
        setWsConnected(false);
        reconnectTimer = setTimeout(connectWs, 1500);
      };
      ws.onerror = () => ws.close();
    };
    connectWs();
    return () => {
      clearTimeout(reconnectTimer);
      if (ws) ws.close();
    };
  }, [authToken, authStatus.auth_required, authStatus.authenticated]);

  const updateAnimation = (patch, targetPresetId = null) => {
    if (!config) return;
    const presetIdToUpdate = targetPresetId || activePresetId || config.active_preset_id;
    const updatedAnim = { ...config.animation, ...patch };
    setConfig({ ...config, animation: updatedAnim, active_preset_id: presetIdToUpdate });

    if (presetIdToUpdate) {
      setPresets((prev) =>
        prev.map((p) =>
          p.id === presetIdToUpdate
            ? {
                ...p,
                is_customized: true,
                animation: { ...p.animation, ...patch },
              }
            : p
        )
      );
    }

    if (patchTimerRef.current) clearTimeout(patchTimerRef.current);
    patchTimerRef.current = setTimeout(async () => {
      try {
        if (targetPresetId) {
          const res = await apiFetch(`/api/presets/${targetPresetId}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ ...patch, apply_now: true }),
          });
          if (res.ok) {
            const data = await res.json();
            if (data.config) setConfig(data.config);
            if (data.preset) {
              setPresets((prev) =>
                prev.map((p) => (p.id === targetPresetId ? data.preset : p))
              );
            }
          }
          return;
        }
        const res = await apiFetch('/api/animation', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(patch),
        });
        if (res.ok) {
          const savedAnim = await res.json();
          setConfig((prev) => ({ ...prev, animation: savedAnim }));
        }
      } catch (err) {
        console.error('Failed to update animation:', err);
      }
    }, 60);
  };

  const handleResetPreset = async (presetId, e) => {
    if (e) e.stopPropagation();
    try {
      const res = await apiFetch(`/api/presets/${presetId}/reset`, { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.preset) {
          setPresets((prev) => prev.map((p) => (p.id === presetId ? data.preset : p)));
        }
        showBanner('Restored default speed & colors for scene!');
      }
    } catch (err) {
      console.error('Failed to reset preset:', err);
    }
  };

  const handlePlaySync = async () => {
    if (patchTimerRef.current) clearTimeout(patchTimerRef.current);
    setConfig((prev) =>
      prev ? { ...prev, animation: { ...prev.animation, running: true } } : prev
    );
    setLiveState((prev) => (prev ? { ...prev, running: true } : prev));
    try {
      const res = await apiFetch('/api/animation/play', { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.live_state) setLiveState(data.live_state);
      }
    } catch (err) {
      console.error('Failed to start sync:', err);
    }
  };

  const handlePauseSync = async () => {
    if (patchTimerRef.current) clearTimeout(patchTimerRef.current);
    setConfig((prev) =>
      prev
        ? {
            ...prev,
            animation: { ...prev.animation, running: false, blackout_on_stop: false },
          }
        : prev
    );
    setLiveState((prev) =>
      prev ? { ...prev, running: false, blackout_on_stop: false } : prev
    );
    try {
      const res = await apiFetch('/api/animation/pause', { method: 'POST' });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.live_state) setLiveState(data.live_state);
      }
    } catch (err) {
      console.error('Failed to pause sync:', err);
    }
  };

  const handleStopSync = async () => {
    if (patchTimerRef.current) clearTimeout(patchTimerRef.current);
    setConfig((prev) =>
      prev
        ? {
            ...prev,
            animation: { ...prev.animation, running: false, blackout_on_stop: true },
          }
        : prev
    );
    setLiveState((prev) =>
      prev
        ? {
            ...prev,
            running: false,
            blackout_on_stop: true,
            segments: (prev.segments || []).map((s) => ({
              ...s,
              r: 0,
              g: 0,
              b: 0,
              hex_color: '#000000',
            })),
          }
        : prev
    );
    try {
      const res = await apiFetch('/api/animation/stop', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ blackout_on_stop: true, turn_off: true }),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.live_state) setLiveState(data.live_state);
      }
    } catch (err) {
      console.error('Failed to stop sync:', err);
    }
  };

  const handleToggleHouse = async (houseId, nextEnabled) => {
    try {
      const res = await apiFetch(`/api/houses/${houseId}/toggle`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(
          typeof nextEnabled === 'boolean' ? { enabled: nextEnabled } : {}
        ),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.live_state) setLiveState(data.live_state);
        const hName = data.house?.name || houseId;
        showBanner(
          data.enabled
            ? `Enabled ${hName} — now syncing across ${data.enabled_houses} active house(s)!`
            : `Disabled ${hName} — now syncing across ${data.enabled_houses} active house(s)!`
        );
      }
    } catch (err) {
      console.error('Failed to toggle house:', err);
    }
  };

  const handleAddHouse = async (payload = {}) => {
    try {
      const res = await apiFetch('/api/houses/add', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.live_state) setLiveState(data.live_state);
        showBanner(`Added ${data.house?.name || 'New Neighbor House'} to street sync!`);
      }
    } catch (err) {
      console.error('Failed to add house:', err);
    }
  };

  const handleDeleteHouse = async (houseId) => {
    try {
      const res = await apiFetch(`/api/houses/${houseId}`, { method: 'DELETE' });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.live_state) setLiveState(data.live_state);
        showBanner(`Removed house (${houseId}) from street sync.`);
      } else {
        const err = await res.json().catch(() => ({}));
        if (err.detail) showBanner(err.detail);
      }
    } catch (err) {
      console.error('Failed to delete house:', err);
    }
  };

  const handleUpdateHouseTimeWeight = (houseId, nextTimeWeight, isReset = false) => {
    const cleanTw = isReset
      ? 1.0
      : Math.max(0.1, Math.min(10.0, Number((nextTimeWeight || 1.0).toFixed(3))));
    setConfig((prev) => {
      if (!prev) return prev;
      return {
        ...prev,
        houses: (prev.houses || []).map((h) =>
          h.id === houseId ? { ...h, time_weight: cleanTw } : h
        ),
      };
    });

    if (houseSpeedTimerRef.current[houseId]) {
      clearTimeout(houseSpeedTimerRef.current[houseId]);
    }
    houseSpeedTimerRef.current[houseId] = setTimeout(async () => {
      try {
        const res = await apiFetch(`/api/houses/${houseId}/speed`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ time_weight: cleanTw, reset_default: isReset }),
        });
        if (res.ok) {
          const data = await res.json();
          if (data.config) setConfig(data.config);
          if (data.live_state) setLiveState(data.live_state);
          if (isReset) {
            showBanner(
              `Reset ${data.house?.name || houseId} to Auto Default speed (scaled by light count)!`
            );
          }
        }
      } catch (err) {
        console.error('Failed to update house speed:', err);
      }
    }, 80);
  };

  const handleReorderHouses = async (orderedHouseIds) => {
    if (!config?.houses || !Array.isArray(orderedHouseIds)) return;
    const houseMap = {};
    config.houses.forEach((h) => {
      houseMap[h.id] = h;
    });
    const reordered = orderedHouseIds
      .map((id, idx) => (houseMap[id] ? { ...houseMap[id], order: idx + 1 } : null))
      .filter(Boolean);
    setConfig((prev) => (prev ? { ...prev, houses: reordered } : prev));

    try {
      const res = await apiFetch('/api/houses/reorder', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ house_ids: orderedHouseIds }),
      });
      if (res.ok) {
        const savedCfg = await res.json();
        setConfig(savedCfg);
      }
    } catch (err) {
      console.error('Failed to reorder houses:', err);
    }
  };

  const handleDiscoverHouseCloud = async (houseId, apiKey) => {
    setBusyHouseId(houseId);
    try {
      const cleanKey = (apiKey ?? houseKeyDrafts[houseId] ?? globalKeyDraft ?? '').trim();
      const res = await apiFetch(`/api/houses/${houseId}/discover-cloud`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ api_key: cleanKey, auto_populate: true }),
      });
      if (res.ok) {
        const data = await res.json();
        const [cfgRes, discRes] = await Promise.all([
          apiFetch('/api/config'),
          apiFetch('/api/discover'),
        ]);
        if (cfgRes.ok) setConfig(await cfgRes.json());
        if (discRes.ok) {
          const d = await discRes.json();
          setDiscoveredDevices(d.devices || []);
        }
        showBanner(
          data.count > 0
            ? `Discovered & auto-populated ${data.count} Govee Cloud light(s) for ${data.house_name}!`
            : `Saved API Key for ${data.house_name}. (Cloud returned 0 devices — check key or enter MAC/SKU in Houses tab.)`
        );
        return data;
      } else {
        const errData = await res.json().catch(() => ({}));
        showBanner(errData.detail || 'Paste a valid Govee API Key first.');
      }
    } catch (err) {
      console.error('Failed to discover cloud devices for house:', err);
    } finally {
      setBusyHouseId(null);
    }
    return null;
  };

  const handleUpdateHouseConnection = async (houseId, updates) => {
    if (!config) return;
    const nextHouses = (config.houses || []).map((h) =>
      h.id === houseId ? { ...h, ...updates } : h
    );
    await handleSaveFullConfig({ ...config, houses: nextHouses });
    showBanner('Saved house connection & credentials!');
  };

  const handleSaveGlobalApiKey = async () => {
    if (!config) return;
    await handleSaveFullConfig({ ...config, govee_api_key: globalKeyDraft.trim() });
    showBanner('Saved Global Govee Cloud API Key!');
  };

  const handleTestController = async (controllerId, colorHex) => {
    try {
      const res = await apiFetch(`/api/controllers/${controllerId}/test`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          color: colorHex || config?.animation?.primary_color || '#00f5d4',
        }),
      });
      if (res.ok) {
        const data = await res.json();
        showBanner(
          `Test pulse (${data.color}) sent to ${data.controller_name} (${
            data.ip || data.mac
          }) via ${data.transport}!`
        );
        return data;
      }
    } catch (err) {
      console.error('Failed to test controller:', err);
    }
    return null;
  };

  const handleResyncClock = async () => {
    await apiFetch('/api/animation/sync-clock', { method: 'POST' });
    showBanner('Master phase clock re-synced to 0.00 across all active houses!');
  };

  const handleApplyPreset = async (presetId) => {
    setActivePresetId(presetId);
    const res = await apiFetch(`/api/presets/${presetId}`, { method: 'POST' });
    if (res.ok) {
      const saved = await res.json();
      setConfig(saved);
      const found = presets.find((p) => p.id === presetId);
      if (found) {
        showBanner(`Activated "${found.name}" across all active houses!`);
      }
    }
  };

  const handleTriggerBurst = async (burstType) => {
    setBurstBusy(burstType);
    try {
      const res = await apiFetch('/api/animation/burst', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: burstType, duration_sec: 12 }),
      });
      if (res.ok) {
        const data = await res.json();
        showBanner(`🎉 Fired "${data.label || burstType}" across all active houses for 12s!`);
        const cfgRes = await apiFetch('/api/config');
        if (cfgRes.ok) setConfig(await cfgRes.json());
      }
    } finally {
      setTimeout(() => setBurstBusy(''), 800);
    }
  };

  const handleUpdatePlaylist = async (patch) => {
    const res = await apiFetch('/api/playlist', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(patch),
    });
    if (res.ok) {
      const data = await res.json();
      if (data.config) setConfig(data.config);
      showBanner(
        data.enabled
          ? `Scene Jukebox enabled (rotating every ${data.interval_sec}s)!`
          : 'Scene Jukebox paused.'
      );
    }
  };

  const handleUpdateSchedule = async (patch) => {
    setSavingSchedule(true);
    try {
      const mergedPatch = { ...scheduleDraft, ...patch };
      setScheduleDraft(mergedPatch);
      const res = await apiFetch('/api/schedule', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(mergedPatch),
      });
      if (res.ok) {
        const data = await res.json();
        if (data.config) setConfig(data.config);
        if (data.schedule_status) setScheduleStatus(data.schedule_status);
        showBanner(
          data.enabled
            ? `24/7 Container Schedule saved (${data.start_time} → ${data.stop_time} ${
                data.tz_abbrev || data.timezone
              })!`
            : 'Schedule saved (currently disabled).'
        );
      }
    } finally {
      setSavingSchedule(false);
    }
  };

  const handleAutoDetectTimezone = async () => {
    const detected = detectBrowserTimezone();
    setScheduleDraft((prev) => ({ ...prev, timezone: detected }));
    await handleUpdateSchedule({ timezone: detected });
    showBanner(`Synced container schedule timezone to ${detected} (auto DST enabled)!`);
  };

  const toggleScheduleDay = (dayId) => {
    setScheduleDraft((prev) => {
      const current = Array.isArray(prev.days_of_week) ? prev.days_of_week : [];
      const exists = current.includes(dayId);
      const nextDays = exists
        ? current.filter((d) => d !== dayId)
        : [...current, dayId];
      return {
        ...prev,
        days_of_week: nextDays.length > 0 ? nextDays : [dayId],
      };
    });
  };

  const handleAddAuthorizedEmail = async (e) => {
    e?.preventDefault?.();
    const clean = newEmailInput.trim().toLowerCase();
    if (!clean || !clean.includes('@')) return;
    const res = await apiFetch('/api/auth/users', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: clean }),
    });
    if (res.ok) {
      const data = await res.json();
      setAuthorizedEmails(data.authorized_emails || []);
      setNewEmailInput('');
      showBanner(`Authorized ${clean} to access Govee Multi-House Light Sync!`);
    }
  };

  const handleRemoveAuthorizedEmail = async (email) => {
    const res = await apiFetch(`/api/auth/users/${encodeURIComponent(email)}`, {
      method: 'DELETE',
    });
    if (res.ok) {
      const data = await res.json();
      setAuthorizedEmails(data.authorized_emails || []);
      showBanner(`Removed ${email} from authorized access list.`);
    }
  };

  const handleLogout = async () => {
    await apiFetch('/api/auth/logout', { method: 'POST' });
    try {
      window.localStorage.removeItem(TOKEN_STORAGE_KEY);
    } catch (e) {
      // ignore
    }
    setAuthToken('');
    setAuthStatus((prev) => ({
      ...prev,
      authenticated: !prev.auth_required,
      user: null,
    }));
  };

  const handleSaveFullConfig = async (newConfig) => {
    const res = await apiFetch('/api/config', {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(newConfig),
    });
    if (res.ok) {
      setConfig(await res.json());
    }
  };

  const handleResetConfig = async () => {
    const res = await apiFetch('/api/config/reset', { method: 'POST' });
    if (res.ok) {
      setConfig(await res.json());
    }
  };

  const handleTriggerScan = async () => {
    const res = await apiFetch('/api/discover/scan', { method: 'POST' });
    if (res.ok) {
      const data = await res.json();
      setDiscoveredDevices(data.devices || []);
    }
  };

  const handleClearLogs = async () => {
    await apiFetch('/api/logs/clear', { method: 'POST' });
  };

  const handleAllPower = async (turnOn) => {
    await apiFetch('/api/power', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ turn_on: turnOn }),
    });
  };

  const anim = config?.animation || {};
  const playlist = config?.playlist || { enabled: false, interval_sec: 60, preset_ids: [] };
  const liveSched = liveState?.schedule_status || scheduleStatus || {};
  const isRunning = anim.running ?? true;
  const filteredPresets =
    sceneCategory === 'all'
      ? presets
      : presets.filter((p) => p.category === sceneCategory);
  const selectedPreset =
    presets.find((p) => p.id === activePresetId) || presets[0] || null;
  const selectedAnim = selectedPreset
    ? { ...(selectedPreset.animation || {}), ...anim }
    : anim;

  const apkSizeMb = apkInfo?.size_bytes
    ? `${(apkInfo.size_bytes / (1024 * 1024)).toFixed(1)} MB`
    : 'Android APK';

  const buildApkDownloadHref = (ver = '') => {
    const params = new URLSearchParams();
    if (ver) params.set('version', ver);
    if (authToken) params.set('token', authToken);
    const qs = params.toString();
    return qs ? `/api/apk/download?${qs}` : '/api/apk/download';
  };

  const apkVersionName = apkInfo?.version_name || '3.1.0';
  const apkVersionCode = apkInfo?.version_code || 4;
  const apkDownloadHref = buildApkDownloadHref(apkVersionName);
  const apkReleases =
    Array.isArray(apkInfo?.releases) && apkInfo.releases.length > 0
      ? apkInfo.releases
      : [
          {
            version_name: apkVersionName,
            version_code: apkVersionCode,
            filename: apkInfo?.filename || `Govee-Sync-Studio-v${apkVersionName}-b${apkVersionCode}.apk`,
            size_bytes: apkInfo?.size_bytes || 0,
            sha256: apkInfo?.sha256 || '',
            released_at: apkInfo?.released_at || '',
            changelog: apkInfo?.changelog || [],
          },
        ];

  const allHouses = config?.houses || [];
  const enabledHouseCount = allHouses.filter((h) => h.enabled !== false).length;

  // External OAuth Login Gate (when accessed externally and not signed in)
  if (!authStatus.loading && authStatus.auth_required && !authStatus.authenticated) {
    return (
      <div className="min-h-screen bg-[#050811] text-slate-100 flex items-center justify-center p-4 overflow-x-hidden">
        <div className="max-w-md w-full bg-[#0c1222]/95 border border-cyan-500/35 rounded-3xl p-6 sm:p-8 shadow-2xl space-y-6">
          <div className="flex items-center gap-3.5">
            <BrandLogo className="w-12 h-12 rounded-2xl shadow-lg shadow-cyan-500/20" />
            <div>
              <h1 className="text-xl font-extrabold tracking-tight text-white">
                Govee Multi-House Sync
              </h1>
              <p className="text-xs text-cyan-300 font-mono">
                {typeof window !== 'undefined' ? window.location.host : 'govee-sync.local'} · 3-House Roofline Studio
              </p>
            </div>
          </div>

          {/* Live 3-House Animated Preview right on the Login Card */}
          <div className="space-y-1.5">
            <div className="flex items-center justify-between text-[11px] text-slate-400">
              <span className="font-semibold text-cyan-300 flex items-center gap-1">
                <Sparkles className="w-3.5 h-3.5" /> Live 3-House Street Preview
              </span>
              <span className="font-mono text-[10px]">House #1 → #2 My House → #3</span>
            </div>
            <LiveSceneCardPreview
              height={104}
              animation={{
                effect: 'center_out_shockwave',
                speed: 0.28,
                direction: 'forward',
                mapping_mode: 'house_normalized',
                primary_color: '#00f5d4',
                secondary_color: '#8b5cf6',
                accent_color: '#ff007f',
                background_color: '#050714',
                background_dim: 0.08,
                tail_length: 0.26,
                pulse_count: 1,
              }}
            />
          </div>

          {authErrorMsg && (
            <div className="bg-rose-500/15 border border-rose-500/40 rounded-xl p-3 text-xs text-rose-200">
              {authErrorMsg}
            </div>
          )}

          <div className="space-y-3">
            <a
              href="/api/auth/google/login"
              className="w-full py-3 px-4 rounded-xl bg-white hover:bg-slate-100 text-slate-950 font-bold text-sm flex items-center justify-center gap-2.5 shadow-lg transition"
            >
              <Globe className="w-4 h-4 text-blue-600" />
              Sign in with Google
            </a>

            <a
              href="/api/auth/github/login"
              className="w-full py-3 px-4 rounded-xl bg-slate-900 hover:bg-slate-800 text-white border border-slate-700 font-bold text-sm flex items-center justify-center gap-2.5 shadow-lg transition"
            >
              <Shield className="w-4 h-4 text-cyan-400" />
              Sign in with GitHub
            </a>
          </div>

          <div className="pt-3 border-t border-slate-800/90 space-y-2.5">
            <div className="w-full py-2 px-3 rounded-xl bg-slate-900/90 border border-slate-800 text-slate-300 text-xs font-semibold flex items-center justify-center gap-2">
              <Smartphone className="w-4 h-4 text-cyan-400 shrink-0" />
              <span>📱 Android APK available after sign-in</span>
            </div>

            <p className="text-[11px] text-slate-400 text-center leading-relaxed">
              <Lock className="w-3 h-3 inline mr-1 text-amber-400" />
              Protected access restricted to{' '}
              <span className="text-slate-200 font-mono">{authStatus.owner}</span> and authorized
              family/neighbor emails.
            </p>
          </div>
        </div>
      </div>
    );
  }

  const [activeColorChannel, setActiveColorChannel] = useState('primary_color');
  const apkColorSwatches = [
    '#00f5d4',
    '#7b2cbf',
    '#ff007f',
    '#ef4444',
    '#10b981',
    '#fbbf24',
    '#38bdf8',
    '#f97316',
    '#9333ea',
    '#22c55e',
    '#ec4899',
    '#fde047',
    '#69be28',
    '#ffffff',
    '#060814',
  ];
  const currentChannelHex = selectedAnim[activeColorChannel] || '#00f5d4';

  const navItems = [
    { id: 'scenes', label: 'Studio', icon: Sparkles },
    { id: 'houses', label: 'Houses', icon: Home },
    { id: 'schedule', label: 'Schedule', icon: Clock },
    { id: 'discovery', label: 'Logs', icon: Radio },
    { id: 'users', label: 'Access', icon: Users },
  ];

  return (
    <div className="min-h-screen bg-[#040711] text-slate-100 flex flex-col overflow-x-hidden pb-20 md:pb-0">
      {/* Compact 1-Row AppBar matching Flutter APK */}
      <header className="sticky top-0 z-30 backdrop-blur-xl bg-[#040711]/95 border-b border-[#1e293b] px-3 sm:px-5 py-2.5">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2.5 min-w-0">
            <BrandLogo className="w-9 h-9 rounded-xl shadow-md shadow-cyan-500/15" />
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <h1 className="text-sm sm:text-base font-extrabold tracking-tight text-white truncate">
                  Govee Sync Studio
                </h1>
                <span className="px-2 py-0.5 rounded-md bg-[#00f5d4]/15 border border-[#00f5d4]/45 text-[#00f5d4] text-[10px] font-extrabold font-mono shrink-0">
                  v{apkInfo?.version_name || '3.1.0'} (b{apkInfo?.version_code || 4})
                </span>
                <span
                  className={`hidden sm:inline-flex items-center gap-1 text-[10px] font-mono px-2 py-0.5 rounded-md border shrink-0 ${
                    wsConnected
                      ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/35'
                      : 'bg-amber-500/15 text-amber-300 border-amber-500/35'
                  }`}
                >
                  ● {wsConnected ? `LIVE · ${liveState?.measured_fps ?? 25} FPS` : 'SYNCING'}
                </span>
              </div>
              <p className="text-[11px] text-slate-400 truncate">
                {enabledHouseCount}/{allHouses.length || 3} Houses Active • Drift{' '}
                {liveState?.clock_drift_ms ?? 0.08}ms
                {liveSched?.current_local_time
                  ? ` • ${liveSched.current_local_time} ${liveSched.tz_abbrev || ''}`
                  : ''}
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <a
              href={apkDownloadHref}
              download={
                apkInfo?.filename ||
                `Govee-Sync-Studio-v${apkVersionName}-b${apkVersionCode}.apk`
              }
              className="px-3 py-1.5 rounded-xl bg-[#0c1324] hover:bg-[#15223d] text-[#00f5d4] border border-[#00f5d4]/45 text-xs font-extrabold flex items-center gap-1.5 transition"
              title="Download the Native Android App (.apk) for Samsung Galaxy Z Fold 7 & Android phones"
            >
              <Download className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Download APK</span>
              <span className="font-mono">v{apkInfo?.version_name || '3.1.0'}</span>
            </a>

            <button
              type="button"
              onClick={handleResyncClock}
              className="p-2 rounded-xl bg-[#0c1324] hover:bg-slate-800 text-slate-300 border border-[#1e293b] transition"
              title="Re-sync master phase clock to 0%"
            >
              <RefreshCw className="w-4 h-4" />
            </button>

            {authStatus?.user && (
              <button
                type="button"
                onClick={handleLogout}
                className="p-2 rounded-xl bg-[#0c1324] hover:bg-rose-950/60 text-slate-300 hover:text-rose-300 border border-[#1e293b] transition"
                title={`Signed in as ${authStatus.user.email} — Sign out`}
              >
                <LogOut className="w-4 h-4" />
              </button>
            )}
          </div>
        </div>
      </header>

      {/* Body with Left NavigationRail (Tablet/PC, exact match to APK) + Main Workspace */}
      <div className="flex-1 flex min-h-0">
        {/* Left NavigationRail matching Flutter APK */}
        <aside className="hidden md:flex flex-col items-center w-20 shrink-0 bg-[#080e1e] border-r border-[#1e293b] py-3 gap-2">
          {navItems.map((item) => {
            const Icon = item.icon;
            const active =
              activeTab === item.id || (item.id === 'scenes' && activeTab === 'dashboard');
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => setActiveTab(item.id)}
                className={`w-16 py-2.5 rounded-2xl flex flex-col items-center justify-center gap-1 transition ${
                  active
                    ? 'bg-[#00f5d4]/15 text-[#00f5d4] border border-[#00f5d4]/40 shadow-sm'
                    : 'text-slate-400 hover:text-slate-200 hover:bg-slate-900/60'
                }`}
              >
                <Icon className="w-5 h-5" />
                <span className="text-[11px] font-bold">{item.label}</span>
              </button>
            );
          })}
        </aside>

        {/* Main Workspace */}
        <main className="flex-1 max-w-[1540px] w-full mx-auto px-3 sm:px-5 py-4 space-y-4 overflow-y-auto">
          {actionBanner && (
            <div className="bg-[#0c1324] border border-[#00f5d4]/50 text-[#00f5d4] px-4 py-2.5 rounded-xl text-xs font-bold flex items-center gap-2 shadow-lg">
              <CheckCircle2 className="w-4 h-4 shrink-0" />
              <span>{actionBanner}</span>
            </div>
          )}

          {liveState?.cloud_errors && Object.keys(liveState.cloud_errors).length > 0 && (
            <div className="bg-amber-950/60 border border-amber-500/50 text-amber-200 px-4 py-2.5 rounded-xl text-xs font-medium flex flex-wrap items-center justify-between gap-2 shadow-lg">
              <div>
                <span className="font-extrabold text-amber-300">Govee Cloud Notice: </span>
                {Object.entries(liveState.cloud_errors)
                  .map(([cid, err]) => `${cid}: ${err}`)
                  .join(' · ')}
              </div>
              <span className="text-[11px] text-amber-300/90 font-semibold">
                Auto-retrying every 15s until controller connects to 2.4 GHz Wi-Fi
              </span>
            </div>
          )}

          {/* TAB 1: ✨ STUDIO & SCENES (Exact 2-Up Hero Row + Scene Grid from APK) */}
          {(activeTab === 'scenes' || activeTab === 'dashboard') && (
            <div className="space-y-4">
              {/* Top 2-Column Hero Row matching Flutter APK _buildUnfoldedDualPaneStudio */}
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 items-stretch">
                {/* Left Hero (7 cols): Unified Night-Sky 3-House Visualizer + Transport + Bursts */}
                <div className="lg:col-span-7 flex flex-col">
                  <NeighborhoodPreview
                    liveState={liveState}
                    config={config}
                    onPlaySync={handlePlaySync}
                    onPauseSync={handlePauseSync}
                    onStopSync={handleStopSync}
                    onToggleHouse={handleToggleHouse}
                    onAddHouse={handleAddHouse}
                    onTriggerBurst={handleTriggerBurst}
                    burstBusy={burstBusy}
                  />
                </div>

                {/* Right Hero (5 cols): Active Scene Speed, Direction & Color Tuner matching APK _buildSelectedSceneInlineTuner */}
                <div className="lg:col-span-5 bg-[#0c1324] border border-[#1e293b] rounded-2xl p-4 shadow-xl flex flex-col justify-between space-y-3.5">
                  <div className="space-y-3">
                    <div className="flex items-center justify-between gap-2">
                      <div className="flex items-center gap-2 min-w-0">
                        <Sliders className="w-4 h-4 text-[#00f5d4] shrink-0" />
                        <h3 className="text-sm font-extrabold text-[#00f5d4] truncate">
                          Tune Scene: {selectedPreset ? selectedPreset.name : 'Custom Effect'}
                        </h3>
                      </div>
                      {selectedPreset?.is_customized && (
                        <button
                          type="button"
                          onClick={(e) => handleResetPreset(selectedPreset.id, e)}
                          className="text-[11px] font-bold px-2.5 py-1 rounded-lg bg-amber-500/15 hover:bg-amber-500/25 text-amber-300 border border-amber-500/40 shrink-0"
                        >
                          Reset Default
                        </button>
                      )}
                    </div>

                    {/* Segmented Direction Selector */}
                    <div className="grid grid-cols-3 gap-1.5 bg-[#060b18] p-1 rounded-xl border border-[#1e293b]">
                      {[
                        { id: 'forward', label: '1 → 2 → 3' },
                        { id: 'reverse', label: '3 → 2 → 1' },
                        { id: 'pingpong', label: 'Bounce ↔' },
                      ].map((d) => (
                        <button
                          key={d.id}
                          type="button"
                          onClick={() =>
                            updateAnimation({ direction: d.id }, selectedPreset?.id)
                          }
                          className={`py-1.5 rounded-lg text-xs font-extrabold transition ${
                            selectedAnim.direction === d.id
                              ? 'bg-[#00f5d4]/20 text-[#00f5d4] border border-[#00f5d4]/50'
                              : 'text-slate-400 hover:text-white'
                          }`}
                        >
                          {d.label}
                        </button>
                      ))}
                    </div>

                    {/* Speed Slider + Slow / Norm / Fast / Hyper Pills */}
                    <div className="space-y-1.5">
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-slate-300 font-semibold">
                          Speed: {Number(selectedAnim.speed || 0.25).toFixed(2)} Hz (
                          {(1 / Math.max(0.02, selectedAnim.speed || 0.25)).toFixed(1)}s cycle)
                        </span>
                        <div className="flex items-center gap-1">
                          {[
                            { label: 'Slow', val: 0.14 },
                            { label: 'Norm', val: 0.25 },
                            { label: 'Fast', val: 0.45 },
                            { label: 'Hyper', val: 0.8 },
                          ].map((sp) => (
                            <button
                              key={sp.label}
                              type="button"
                              onClick={() =>
                                updateAnimation({ speed: sp.val }, selectedPreset?.id)
                              }
                              className={`px-2 py-0.5 rounded-md border text-[10px] font-bold transition ${
                                Math.abs((selectedAnim.speed || 0.25) - sp.val) < 0.02
                                  ? 'bg-[#00f5d4]/20 border-[#00f5d4] text-[#00f5d4]'
                                  : 'bg-[#060b18] border-[#1e293b] text-slate-300 hover:text-white'
                              }`}
                            >
                              {sp.label}
                            </button>
                          ))}
                        </div>
                      </div>
                      <input
                        type="range"
                        min="0.05"
                        max="1.50"
                        step="0.01"
                        value={selectedAnim.speed || 0.25}
                        onChange={(e) =>
                          updateAnimation(
                            { speed: parseFloat(e.target.value) },
                            selectedPreset?.id
                          )
                        }
                        className="w-full accent-[#00f5d4]"
                      />
                    </div>

                    {/* Brightness Slider */}
                    <div className="space-y-1">
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-slate-300 font-semibold">
                          Master Brightness: {anim.intensity ?? 100}%
                        </span>
                        <div className="flex items-center gap-1.5">
                          <button
                            type="button"
                            onClick={() => handleAllPower(true)}
                            className="px-2 py-0.5 rounded-md bg-[#060b18] hover:bg-slate-800 text-emerald-400 border border-[#1e293b] text-[10px] font-bold"
                          >
                            All ON
                          </button>
                          <button
                            type="button"
                            onClick={() => handleAllPower(false)}
                            className="px-2 py-0.5 rounded-md bg-[#060b18] hover:bg-slate-800 text-rose-400 border border-[#1e293b] text-[10px] font-bold"
                          >
                            All OFF
                          </button>
                        </div>
                      </div>
                      <input
                        type="range"
                        min="5"
                        max="100"
                        step="1"
                        value={anim.intensity ?? 100}
                        onChange={(e) =>
                          updateAnimation({ intensity: parseInt(e.target.value, 10) })
                        }
                        className="w-full accent-purple-500"
                      />
                    </div>

                    {/* 3D House Wall Zone Mode (Front vs Sides vs Back) */}
                    <div className="flex items-center justify-between gap-2 text-xs">
                      <span className="text-slate-300 font-semibold shrink-0">
                        3D Wall Sync:
                      </span>
                      <select
                        value={anim.zone_mode || 'all_segments'}
                        onChange={(e) =>
                          updateAnimation(
                            { zone_mode: e.target.value },
                            selectedPreset?.id
                          )
                        }
                        className="flex-1 bg-[#060b18] border border-[#1e293b] rounded-lg px-2 py-1 text-[11px] font-bold text-[#00f5d4]"
                      >
                        <option value="all_segments">
                          Linear Strip (All Segments)
                        </option>
                        <option value="front_street_sync">
                          Street-Front Sync + Side/Back Echo
                        </option>
                        <option value="depth_front_to_back">
                          3D Depth Wave (Front → Sides → Back)
                        </option>
                        <option value="perimeter_360">
                          360° House Perimeter Orbit
                        </option>
                        <option value="front_only_quiet_sides">
                          Front Show Only (Dim Sides &amp; Back)
                        </option>
                      </select>
                    </div>

                    {/* Color Channel Chips + Swatches matching APK */}
                    <div className="space-y-2 pt-1 border-t border-[#1e293b]">
                      <div className="flex flex-wrap items-center gap-1.5">
                        {[
                          { key: 'primary_color', label: 'Lead 1' },
                          { key: 'secondary_color', label: 'Mid 2' },
                          { key: 'accent_color', label: 'Tail 3' },
                          { key: 'background_color', label: 'Base Glow' },
                        ].map((ch) => {
                          const hex = selectedAnim[ch.key] || '#00f5d4';
                          const sel = activeColorChannel === ch.key;
                          return (
                            <button
                              key={ch.key}
                              type="button"
                              onClick={() => setActiveColorChannel(ch.key)}
                              className={`px-2.5 py-1 rounded-lg text-[11px] font-bold flex items-center gap-1.5 border transition ${
                                sel
                                  ? 'bg-[#00f5d4]/20 border-[#00f5d4] text-white'
                                  : 'bg-[#060b18] border-[#1e293b] text-slate-300 hover:text-white'
                              }`}
                            >
                              <span
                                className="w-3 h-3 rounded-full border border-white/30"
                                style={{ backgroundColor: hex }}
                              />
                              <span>{ch.label}</span>
                            </button>
                          );
                        })}
                        <label
                          className="px-2 py-1 rounded-lg bg-[#060b18] border border-[#1e293b] text-[11px] font-bold text-cyan-300 flex items-center gap-1 cursor-pointer hover:border-cyan-400"
                          title="Pick custom RGB color"
                        >
                          <input
                            type="color"
                            value={currentChannelHex}
                            onChange={(e) =>
                              updateAnimation(
                                { [activeColorChannel]: e.target.value },
                                selectedPreset?.id
                              )
                            }
                            className="w-4 h-4 bg-transparent border-0 cursor-pointer"
                          />
                          <span>Custom</span>
                        </label>
                      </div>

                      <div className="flex flex-wrap items-center gap-2 pt-0.5">
                        {apkColorSwatches.map((hex) => {
                          const isSel =
                            currentChannelHex.toLowerCase() === hex.toLowerCase();
                          return (
                            <button
                              key={hex}
                              type="button"
                              onClick={() =>
                                updateAnimation(
                                  { [activeColorChannel]: hex },
                                  selectedPreset?.id
                                )
                              }
                              className="w-6 h-6 rounded-full transition-transform hover:scale-110"
                              style={{
                                backgroundColor: hex,
                                border: isSel
                                  ? '2.5px solid #ffffff'
                                  : '1px solid rgba(255,255,255,0.22)',
                              }}
                              title={hex}
                            />
                          );
                        })}
                      </div>

                      {/* Govee-Side Schedule Control Toggle Bar */}
                      <div className="pt-2 border-t border-[#1e293b] flex items-center justify-between gap-2">
                        <div className="min-w-0">
                          <div className="text-[11px] font-bold text-slate-200 truncate">
                            Govee App Schedules:{' '}
                            <span
                              className={
                                scheduleDraft.override_govee_app_schedules
                                  ? 'text-amber-300'
                                  : 'text-[#00f5d4]'
                              }
                            >
                              {scheduleDraft.override_govee_app_schedules
                                ? 'Blocked (Sync Studio Overrides)'
                                : 'Enabled (Coexist with App)'}
                            </span>
                          </div>
                        </div>
                        <button
                          type="button"
                          onClick={() => {
                            const nextVal = !scheduleDraft.override_govee_app_schedules;
                            const updated = {
                              ...scheduleDraft,
                              override_govee_app_schedules: nextVal,
                            };
                            setScheduleDraft(updated);
                            handleUpdateSchedule(updated);
                          }}
                          className={`px-2.5 py-1 rounded-lg text-[11px] font-extrabold border shrink-0 transition ${
                            scheduleDraft.override_govee_app_schedules
                              ? 'bg-amber-500/20 border-amber-400/60 text-amber-200 hover:bg-amber-500/30'
                              : 'bg-[#00f5d4]/15 border-[#00f5d4]/50 text-[#00f5d4] hover:bg-[#00f5d4]/25'
                          }`}
                        >
                          {scheduleDraft.override_govee_app_schedules
                            ? 'Allow Govee Schedules'
                            : 'Block Govee Schedules'}
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              {/* Immediately Below Hero Row: Full-Width Multi-House Scene Gallery matching APK _buildSceneGalleryCard */}
              <div className="bg-[#0c1324] border border-[#1e293b] rounded-2xl p-4 shadow-xl space-y-3.5">
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <Sparkles className="w-4 h-4 text-[#00f5d4]" />
                    <h2 className="text-sm sm:text-base font-extrabold text-white">
                      Multi-House Scene Gallery ({filteredPresets.length} Live Previews)
                    </h2>
                  </div>
                  <span className="text-xs text-slate-400">
                    Tap any card to sync across all active houses
                  </span>
                </div>

                {/* Category Filter Chips matching APK */}
                <div className="flex items-center gap-2 overflow-x-auto pb-1 no-scrollbar">
                  {SCENE_CATEGORIES.map((cat) => {
                    const active = sceneCategory === cat.id;
                    const count =
                      cat.id === 'all'
                        ? presets.length
                        : presets.filter((p) => p.category === cat.id).length;
                    return (
                      <button
                        key={cat.id}
                        type="button"
                        onClick={() => setSceneCategory(cat.id)}
                        className={`px-3 py-1.5 rounded-xl text-xs font-extrabold whitespace-nowrap border transition flex items-center gap-1.5 shrink-0 ${
                          active
                            ? 'bg-[#00f5d4]/20 text-[#00f5d4] border-[#00f5d4]'
                            : 'bg-[#060b18] hover:bg-slate-900 text-[#cbd5e1] border-[#1e293b]'
                        }`}
                      >
                        <span>{cat.label}</span>
                        <span className="text-[11px] opacity-80">({count})</span>
                      </button>
                    );
                  })}
                </div>

                {/* Scene Cards Grid — Exact match to APK _buildAnimatedSceneCard */}
                <div
                  className="scene-gallery-grid"
                  style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))',
                    gap: '0.75rem',
                  }}
                >
                  {filteredPresets.map((preset) => {
                    const isSelected = activePresetId === preset.id;
                    const pAnim = isSelected ? { ...(preset.animation || {}), ...anim } : preset.animation || {};
                    const primaryCol = pAnim.primary_color || '#00f5d4';

                    return (
                      <div
                        key={preset.id}
                        onClick={() => handleApplyPreset(preset.id)}
                        role="button"
                        tabIndex={0}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' || e.key === ' ') handleApplyPreset(preset.id);
                        }}
                        className={`text-left rounded-[14px] p-3 border transition-all flex flex-col justify-between gap-2 cursor-pointer group ${
                          isSelected
                            ? 'bg-[#0f243c] border-[#00f5d4] border-[1.8px] shadow-lg shadow-[#00f5d4]/10'
                            : 'bg-[#060b18] hover:bg-[#091226] border-[#1e293b]'
                        }`}
                      >
                        {/* 1. Top: Live 3-House Night-Sky Architectural Preview (exact match to APK) */}
                        <LiveSceneCardPreview
                          animation={{ ...pAnim, running: true }}
                          houses={config?.houses}
                          height={96}
                          compact={true}
                        />

                        {/* 2. Middle: Title + 3 Color Dots */}
                        <div className="flex items-center justify-between gap-2 pt-0.5">
                          <h3 className="text-[13.5px] font-extrabold text-white truncate">
                            {preset.name}
                          </h3>
                          <div className="flex items-center gap-1 shrink-0">
                            {[
                              pAnim.primary_color,
                              pAnim.secondary_color,
                              pAnim.accent_color,
                            ].map((hex, i) => (
                              <span
                                key={i}
                                className="w-2.5 h-2.5 rounded-full border border-white/25"
                                style={{ backgroundColor: hex }}
                              />
                            ))}
                          </div>
                        </div>

                        {/* 3. Description */}
                        <p className="text-[11px] text-[#94a3b8] leading-snug line-clamp-2">
                          {preset.description}
                        </p>

                        {/* 4. Bottom Row: Category • Badge pill on left + ACTIVE / TAP TO SYNC on right */}
                        <div className="flex items-center justify-between gap-2 pt-1">
                          <span
                            className="text-[10px] font-bold px-2 py-0.5 rounded-md truncate"
                            style={{
                              backgroundColor: `${primaryCol}26`,
                              color: primaryCol,
                            }}
                          >
                            {preset.category} • {preset.badge}
                            {preset.is_customized ? ' • Custom' : ''}
                          </span>
                          <span
                            className={`text-[10px] font-extrabold shrink-0 ${
                              isSelected ? 'text-[#00f5d4]' : 'text-[#64748b] group-hover:text-slate-300'
                            }`}
                          >
                            {isSelected ? '● ACTIVE' : 'TAP TO SYNC'}
                          </span>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
          )}

        {/* TAB 2: 🏠 HOUSES & API KEYS */}
        {activeTab === 'houses' && (
          <div className="space-y-6">
            {/* Quick Per-House API Key, Enable/Disable & Street Sequence Studio */}
            <div className="bg-gradient-to-b from-[#0e172a] to-[#0a1020] border border-cyan-500/40 rounded-2xl p-4 sm:p-6 shadow-2xl space-y-5">
              <div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-800/90 pb-4">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <Key className="w-5 h-5 text-amber-400" />
                    <h2 className="text-base sm:text-lg font-extrabold text-white">
                      Multi-House Street Order, Enable/Disable &amp; Neighbor Govee API Keys
                    </h2>
                    <span className="text-[10px] font-mono px-2.5 py-0.5 rounded-full bg-amber-500/20 text-amber-300 border border-amber-500/40 font-bold">
                      1, 2, 3, OR N HOUSES
                    </span>
                  </div>
                  <p className="text-xs text-slate-300 mt-1">
                    <strong>My House (Middle - Me)</strong> is pre-configured on your local Wi-Fi at{' '}
                    <code className="text-emerald-300 font-mono">
                      {allHouses.find((h) => h.id === 'house-2')?.controllers?.[0]?.ip || '192.168.1.83'}
                    </code>{' '}
                    (
                    <code className="text-cyan-300 font-mono">
                      {allHouses.find((h) => h.id === 'house-2')?.controllers?.[0]?.sku || 'H705E'} ·{' '}
                      {allHouses.find((h) => h.id === 'house-2')?.controllers?.[0]?.mac || 'AA:BB:CC:DD:EE:FF:00:02'} ·{' '}
                      {allHouses.find((h) => h.id === 'house-2')?.controllers?.[0]?.segment_count || 9} segs
                    </code>
                    ). Toggle any neighbor house off to run animations solo on your house, or paste
                    their <strong>Govee API Key</strong> / <strong>25-FPS Bridge</strong> to sync
                    across the street!
                  </p>
                </div>

                <div className="flex flex-wrap items-center gap-2">
                  <button
                    onClick={() => handleAddHouse()}
                    className="px-3.5 py-2 rounded-xl bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-extrabold text-xs flex items-center gap-1.5 shadow-lg transition"
                  >
                    <Plus className="w-4 h-4 stroke-[2.5]" /> + Add Neighbor House
                  </button>

                  {/* Global Govee Cloud API Key Quick Input */}
                  <div className="flex items-center gap-2 bg-slate-950/90 border border-slate-800 rounded-xl p-1.5">
                    <Key className="w-4 h-4 text-amber-400 shrink-0 ml-1.5" />
                    <input
                      type="password"
                      value={globalKeyDraft}
                      onChange={(e) => setGlobalKeyDraft(e.target.value)}
                      placeholder="Global Govee API Key"
                      className="bg-slate-900 border border-slate-700 rounded-lg px-2.5 py-1 text-xs font-mono text-white w-44"
                    />
                    <button
                      onClick={handleSaveGlobalApiKey}
                      className="px-3 py-1 rounded-lg bg-amber-500/20 hover:bg-amber-500/35 text-amber-200 border border-amber-500/40 text-xs font-bold shrink-0"
                    >
                      Save Key
                    </button>
                  </div>
                </div>
              </div>

              {/* Per-House Credentials, Enable/Disable, Street Order & Light Test Cards */}
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
                {allHouses.map((house, hIdx) => {
                  const connOpt =
                    CONNECTION_OPTIONS.find(
                      (o) => o.value === (house.connection_type || 'local_lan')
                    ) || CONNECTION_OPTIONS[0];
                  const draftKey = houseKeyDrafts[house.id] ?? house.govee_api_key ?? '';
                  const bridgeConnected = (liveState?.bridges || []).some(
                    (b) => b.house_id === house.id
                  );
                  const bridgeCmd = `curl -sSL ${httpProto}://${serverHost}/api/neighbor-bridge.py | python3 - --house-id ${house.id} --server ${wsProto}://${serverHost}`;
                  const isHouseEnabled = house.enabled !== false;

                  return (
                    <div
                      key={house.id}
                      className={`bg-slate-950/90 border rounded-xl p-4 flex flex-col justify-between space-y-3.5 transition ${
                        isHouseEnabled
                          ? 'border-slate-800/90'
                          : 'border-slate-800/50 opacity-65'
                      }`}
                    >
                      <div className="space-y-3">
                        {/* Top row: Street position selector + Active/Disabled switch + Delete */}
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <select
                            aria-label={`Street order for ${house.name}`}
                            value={hIdx}
                            onChange={(e) => {
                              const toIdx = parseInt(e.target.value, 10);
                              const next = [...allHouses];
                              const [moved] = next.splice(hIdx, 1);
                              next.splice(toIdx, 0, moved);
                              handleReorderHouses(next.map((h) => h.id));
                            }}
                            className="bg-slate-900 border border-cyan-500/40 rounded-lg px-2 py-1 text-[11px] font-bold text-cyan-300 cursor-pointer"
                          >
                            {allHouses.map((_, optIdx) => (
                              <option key={optIdx} value={optIdx}>
                                {getPositionLabel(optIdx, allHouses.length)}
                              </option>
                            ))}
                          </select>

                          <div className="flex items-center gap-1.5">
                            <button
                              type="button"
                              onClick={() => handleToggleHouse(house.id, !isHouseEnabled)}
                              className={`px-2.5 py-1 rounded-lg text-[10px] font-mono font-bold border transition flex items-center gap-1 ${
                                isHouseEnabled
                                  ? 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40'
                                  : 'bg-slate-900 text-slate-400 border-slate-700'
                              }`}
                            >
                              <Power className="w-3 h-3" />
                              {isHouseEnabled ? 'Active' : 'Disabled'}
                            </button>

                            {allHouses.length > 1 && (
                              <button
                                type="button"
                                onClick={() => handleDeleteHouse(house.id)}
                                className="p-1 rounded-lg bg-rose-500/15 hover:bg-rose-500/30 text-rose-300 border border-rose-500/30 transition"
                                title={`Delete ${house.name}`}
                              >
                                <Trash2 className="w-3.5 h-3.5" />
                              </button>
                            )}
                          </div>
                        </div>

                        <div className="flex items-center justify-between gap-2">
                          <div>
                            <h3 className="text-sm font-bold text-white">{house.name}</h3>
                            <p className="text-[11px] text-slate-400 mt-0.5">
                              {house.controllers?.length || 0} controller(s) ·{' '}
                              {house.controllers?.reduce(
                                (s, c) => s + (c.enabled ? c.segment_count : 0),
                                0
                              )}{' '}
                              segments
                            </p>
                          </div>
                          <span
                            className={`text-[10px] font-mono px-2 py-0.5 rounded-full border font-bold ${connOpt.badgeCls}`}
                          >
                            {connOpt.badge}
                          </span>
                        </div>

                        {/* Connection Method Selector */}
                        <div>
                          <label className="block text-[10px] uppercase tracking-wider text-slate-400 mb-1">
                            Connection Method
                          </label>
                          <select
                            value={house.connection_type || 'local_lan'}
                            onChange={(e) =>
                              handleUpdateHouseConnection(house.id, {
                                connection_type: e.target.value,
                              })
                            }
                            className="w-full bg-slate-900 border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs text-white font-medium"
                          >
                            {CONNECTION_OPTIONS.map((opt) => (
                              <option key={opt.value} value={opt.value}>
                                {opt.label}
                              </option>
                            ))}
                          </select>
                        </div>

                        {/* Govee API Key Input Box directly on each House Card */}
                        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-3 space-y-2">
                          <label className="flex items-center justify-between text-[11px] font-semibold text-amber-300">
                            <span className="flex items-center gap-1">
                              <Key className="w-3.5 h-3.5 text-amber-400" />
                              Govee Cloud API Key ({house.name.split('(')[0].trim()})
                            </span>
                            {house.govee_api_key && (
                              <span className="text-[10px] font-mono text-emerald-400">
                                KEY SAVED
                              </span>
                            )}
                          </label>
                          <input
                            type="password"
                            value={draftKey}
                            onChange={(e) =>
                              setHouseKeyDrafts((prev) => ({
                                ...prev,
                                [house.id]: e.target.value,
                              }))
                            }
                            placeholder={
                              house.connection_type === 'local_lan'
                                ? `Optional Govee API Key (LAN active at ${house.controllers?.[0]?.ip || '192.168.1.83'})`
                                : "Paste Neighbor's Govee API Key here..."
                            }
                            className="w-full bg-slate-950 border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs font-mono text-white"
                          />
                          <button
                            onClick={() => handleDiscoverHouseCloud(house.id, draftKey)}
                            disabled={busyHouseId === house.id}
                            className="w-full py-1.5 px-2.5 rounded-lg bg-gradient-to-r from-amber-400 to-orange-500 hover:from-amber-300 hover:to-orange-400 text-slate-950 font-bold text-[11px] flex items-center justify-center gap-1.5 shadow transition"
                          >
                            <Globe className="w-3.5 h-3.5" />
                            {busyHouseId === house.id
                              ? 'Fetching Cloud Lights...'
                              : "Save Key & Auto-Discover Neighbor's Cloud Lights"}
                          </button>
                        </div>

                        {/* If Neighbor Bridge selected, show 1-line bridge command */}
                        {house.connection_type === 'neighbor_bridge' && (
                          <div className="bg-purple-950/25 border border-purple-500/30 rounded-xl p-2.5 space-y-1.5 text-[11px]">
                            <div className="flex items-center justify-between">
                              <span className="font-semibold text-purple-200 flex items-center gap-1">
                                <Terminal className="w-3.5 h-3.5" /> 25-FPS Neighbor Bridge
                              </span>
                              <span
                                className={`font-mono text-[10px] px-1.5 py-0.5 rounded ${
                                  bridgeConnected
                                    ? 'bg-emerald-500/20 text-emerald-300'
                                    : 'bg-slate-800 text-slate-400'
                                }`}
                              >
                                {bridgeConnected ? 'ONLINE' : 'WAITING'}
                              </span>
                            </div>
                            <div className="font-mono text-[10px] text-slate-300 bg-slate-950 p-1.5 rounded border border-slate-800 break-all">
                              {bridgeCmd}
                            </div>
                            <button
                              onClick={() => {
                                if (navigator?.clipboard) {
                                  navigator.clipboard.writeText(bridgeCmd);
                                  setCopiedHouseCmd(house.id);
                                  setTimeout(() => setCopiedHouseCmd(null), 2000);
                                }
                              }}
                              className="w-full py-1 rounded bg-purple-500/20 hover:bg-purple-500/30 text-purple-200 border border-purple-500/40 font-semibold flex items-center justify-center gap-1"
                            >
                              <Copy className="w-3 h-3" />
                              {copiedHouseCmd === house.id
                                ? 'Copied Command!'
                                : 'Copy Bridge Command'}
                            </button>
                          </div>
                        )}
                      </div>

                      {/* Controllers & 1-Click Test Physical Light Button + 3D Wall Zone Split */}
                      <div className="pt-2.5 border-t border-slate-800/80 space-y-2.5">
                        <div className="flex items-center justify-between">
                          <span className="text-[10px] uppercase tracking-wider text-slate-400 font-semibold">
                            Controllers &amp; 3D Wall Zone Mapping (Front / Sides / Back)
                          </span>
                        </div>
                        {(house.controllers || []).map((ctrl) => {
                          const zones = Array.isArray(ctrl.wall_zones) && ctrl.wall_zones.length > 0
                            ? ctrl.wall_zones
                            : [{ wall: 'front', segments: ctrl.segment_count }];
                          const frontSegs = zones
                            .filter((z) => z.wall === 'front')
                            .reduce((s, z) => s + (Number(z.segments) || 0), 0);
                          const sideWall =
                            zones.find((z) => z.wall !== 'front')?.wall || 'right';
                          const sideSegs = Math.max(0, ctrl.segment_count - frontSegs);

                          return (
                            <div
                              key={ctrl.id}
                              className="bg-slate-900/90 border border-slate-800 rounded-xl p-2.5 space-y-2 text-xs"
                            >
                              <div className="flex items-center justify-between gap-2">
                                <div className="truncate">
                                  <div className="font-semibold text-slate-200 truncate">
                                    {ctrl.name}
                                  </div>
                                  <div className="text-[10px] font-mono text-slate-400">
                                    {ctrl.ip ? `LAN ${ctrl.ip}` : 'Cloud/Internet'} · {ctrl.sku} ·{' '}
                                    {ctrl.segment_count} segs
                                  </div>
                                </div>
                                <button
                                  onClick={() => handleTestController(ctrl.id)}
                                  className="px-2.5 py-1 rounded-lg bg-cyan-500/20 hover:bg-cyan-500/35 text-cyan-200 border border-cyan-500/40 text-[11px] font-bold flex items-center gap-1 shrink-0 transition"
                                  title={`Send test color pulse to ${ctrl.name}`}
                                >
                                  <Zap className="w-3 h-3 text-cyan-300" />
                                  Test Light
                                </button>
                              </div>

                              {/* Interactive Front vs Side/Back Corner Split Slider */}
                              <div className="bg-slate-950/90 border border-slate-800/80 rounded-lg p-2 space-y-1.5">
                                <div className="flex items-center justify-between text-[11px]">
                                  <span className="font-bold text-cyan-300">
                                    Front: {frontSegs} segs
                                  </span>
                                  <span className="text-slate-400 font-mono text-[10px]">
                                    Corner Split
                                  </span>
                                  <span className="font-bold text-purple-300">
                                    {sideWall.toUpperCase()}: {sideSegs} segs
                                  </span>
                                </div>
                                <input
                                  type="range"
                                  min="0"
                                  max={ctrl.segment_count}
                                  value={frontSegs}
                                  onChange={async (e) => {
                                    const newFront = Number(e.target.value);
                                    const rem = Math.max(0, ctrl.segment_count - newFront);
                                    const newZones = [];
                                    if (newFront > 0)
                                      newZones.push({ wall: 'front', segments: newFront });
                                    if (rem > 0)
                                      newZones.push({ wall: sideWall, segments: rem });
                                    const r = await apiFetch(`/api/controllers/${ctrl.id}/zones`, {
                                      method: 'PATCH',
                                      headers: { 'Content-Type': 'application/json' },
                                      body: JSON.stringify({ wall_zones: newZones }),
                                    });
                                    if (r.ok) {
                                      const d = await r.json();
                                      if (d.config) setConfig(d.config);
                                    }
                                  }}
                                  className="w-full accent-[#00f5d4] h-1.5 bg-slate-800 rounded-lg cursor-pointer"
                                />
                                <div className="flex items-center justify-between gap-1.5 pt-0.5">
                                  <div className="flex items-center gap-1 text-[10px] text-slate-400">
                                    <span>2nd Wall:</span>
                                    {['left', 'right', 'back'].map((wName) => (
                                      <button
                                        key={wName}
                                        type="button"
                                        onClick={async () => {
                                          const rem = Math.max(1, ctrl.segment_count - frontSegs);
                                          const fCnt = Math.max(0, ctrl.segment_count - rem);
                                          const newZones = [];
                                          if (fCnt > 0)
                                            newZones.push({ wall: 'front', segments: fCnt });
                                          newZones.push({ wall: wName, segments: rem });
                                          const r = await apiFetch(
                                            `/api/controllers/${ctrl.id}/zones`,
                                            {
                                              method: 'PATCH',
                                              headers: { 'Content-Type': 'application/json' },
                                              body: JSON.stringify({ wall_zones: newZones }),
                                            }
                                          );
                                          if (r.ok) {
                                            const d = await r.json();
                                            if (d.config) setConfig(d.config);
                                          }
                                        }}
                                        className={`px-1.5 py-0.5 rounded font-bold uppercase ${
                                          sideWall === wName && sideSegs > 0
                                            ? 'bg-purple-500/30 text-purple-200 border border-purple-400/50'
                                            : 'bg-slate-900 text-slate-400 border border-slate-800'
                                        }`}
                                      >
                                        {wName}
                                      </button>
                                    ))}
                                  </div>
                                  <button
                                    type="button"
                                    onClick={async () => {
                                      const cornerIdx = Math.max(
                                        0,
                                        Math.min(ctrl.segment_count - 1, frontSegs - 1)
                                      );
                                      await apiFetch(
                                        `/api/controllers/${ctrl.id}/locate-segment`,
                                        {
                                          method: 'POST',
                                          headers: { 'Content-Type': 'application/json' },
                                          body: JSON.stringify({ segment_index: cornerIdx }),
                                        }
                                      );
                                      showBanner(
                                        `Spotlighted Corner Segment #${cornerIdx + 1} on ${ctrl.name} in White!`
                                      );
                                    }}
                                    className="px-2 py-0.5 rounded bg-amber-500/20 hover:bg-amber-500/30 text-amber-200 border border-amber-500/40 text-[10px] font-bold"
                                    title="Light up the corner split segment in bright white on the physical house"
                                  >
                                    Spotlight Corner #{Math.max(1, frontSegs)}
                                  </button>
                                </div>
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

            {/* Full House & Controller Topology Editor */}
            <HouseConfigEditor
              config={config}
              liveState={liveState}
              discoveredDevices={discoveredDevices}
              onSaveConfig={handleSaveFullConfig}
              onResetConfig={handleResetConfig}
              onTriggerScan={handleTriggerScan}
              onReorderHouses={handleReorderHouses}
              onDiscoverHouseCloud={handleDiscoverHouseCloud}
              onTestController={handleTestController}
              onToggleHouse={handleToggleHouse}
              onAddHouse={handleAddHouse}
              onDeleteHouse={handleDeleteHouse}
              onUpdateHouseTimeWeight={handleUpdateHouseTimeWeight}
            />
          </div>
        )}

        {/* TAB 3: 🕒 SCHEDULE & JUKEBOX (+ ADVANCED SHADERS) */}
        {activeTab === 'schedule' && (
          <div className="space-y-6">
            {/* Autonomous 24/7 Container Schedule Studio */}
            <div className="bg-gradient-to-b from-[#0d1629] to-[#090f1d] border border-emerald-500/40 rounded-2xl p-5 sm:p-6 shadow-2xl space-y-5">
              <div className="flex flex-wrap items-start justify-between gap-4 border-b border-slate-800/90 pb-4">
                <div className="space-y-1.5">
                  <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-emerald-500/15 border border-emerald-500/40 text-emerald-300 text-xs font-extrabold">
                    <span>
                      🟢 24/7 Autonomous Container Schedule — Runs on Server Even When App/Browser is Closed
                    </span>
                  </div>
                  <h2 className="text-lg sm:text-xl font-extrabold text-white flex items-center gap-2 pt-1">
                    <Clock className="w-5 h-5 text-cyan-400" />
                    Autonomous Night Schedule &amp; Automatic Daylight Saving Time (DST)
                  </h2>
                  <p className="text-xs text-slate-300">
                    The Docker container on Raspberry Pi 5 evaluates this schedule every second
                    using Python <code className="text-cyan-300 font-mono">zoneinfo</code>,
                    automatically adjusting for Daylight Saving Time transitions (`PDT` ↔ `PST`) and
                    powering your physical Govee lights ON and OFF on schedule even when your phone
                    or PC is off.
                  </p>
                </div>

                {/* Live Server Clock + Timezone + DST Status Card */}
                <div className="bg-slate-950/95 border border-cyan-500/35 rounded-2xl p-3.5 min-w-[260px] space-y-1.5">
                  <div className="flex items-center justify-between text-[11px]">
                    <span className="text-slate-400 font-semibold">Server Local Clock:</span>
                    <span className="font-mono font-extrabold text-cyan-300 text-sm">
                      {liveSched.current_local_time || '--:--:--'}{' '}
                      {liveSched.tz_abbrev || ''}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-[11px]">
                    <span className="text-slate-400 font-semibold">IANA Timezone:</span>
                    <span className="font-mono text-white font-bold">
                      {liveSched.timezone || scheduleDraft.timezone || 'America/Los_Angeles'}
                    </span>
                  </div>
                  <div className="flex items-center justify-between text-[11px]">
                    <span className="text-slate-400 font-semibold">DST / Offset Status:</span>
                    <span className="font-mono text-emerald-300 font-bold">
                      {liveSched.tz_abbrev || 'PT'} ·{' '}
                      {liveSched.dst_active ? 'DST Active' : 'Standard Time'}{' '}
                      {liveSched.utc_offset ? `(${liveSched.utc_offset})` : ''}
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={handleAutoDetectTimezone}
                    className="w-full mt-1.5 py-1.5 px-3 rounded-xl bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-200 border border-cyan-400/40 text-xs font-bold flex items-center justify-center gap-1.5 transition"
                  >
                    <MapPin className="w-3.5 h-3.5 text-cyan-300" />
                    📍 Auto-Detect My Timezone &amp; DST
                  </button>
                </div>
              </div>

              {/* Schedule Controls Form */}
              <div className="grid grid-cols-1 md:grid-cols-12 gap-4 items-end">
                {/* Enable Daily Schedule Switch (3 cols) */}
                <div className="md:col-span-3 bg-slate-950/90 border border-slate-800 rounded-xl p-3.5 flex items-center justify-between">
                  <div>
                    <div className="text-xs font-extrabold text-white">Enable Daily Schedule</div>
                    <div className="text-[11px] text-slate-400">
                      {scheduleDraft.enabled ? 'Active on Server' : 'Currently Paused'}
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() =>
                      setScheduleDraft((prev) => ({ ...prev, enabled: !prev.enabled }))
                    }
                    className={`px-3.5 py-2 rounded-xl text-xs font-mono font-extrabold border transition ${
                      scheduleDraft.enabled
                        ? 'bg-emerald-400 text-slate-950 border-emerald-300 shadow-lg shadow-emerald-500/20'
                        : 'bg-slate-900 text-slate-400 border-slate-700 hover:text-white'
                    }`}
                  >
                    {scheduleDraft.enabled ? 'ENABLED' : 'OFF'}
                  </button>
                </div>

                {/* Turn ON Time (2 cols) */}
                <div className="md:col-span-2 bg-slate-950/90 border border-slate-800 rounded-xl p-3">
                  <label className="block text-[11px] font-bold text-emerald-300 mb-1">
                    Turn ON Time ({liveSched.tz_abbrev || 'Local'})
                  </label>
                  <input
                    type="time"
                    value={scheduleDraft.start_time}
                    onChange={(e) =>
                      setScheduleDraft((prev) => ({ ...prev, start_time: e.target.value }))
                    }
                    className="w-full bg-slate-900 border border-slate-700 rounded-lg px-2.5 py-1.5 text-sm font-mono font-bold text-white"
                  />
                </div>

                {/* Turn OFF Time (2 cols) */}
                <div className="md:col-span-2 bg-slate-950/90 border border-slate-800 rounded-xl p-3">
                  <label className="block text-[11px] font-bold text-rose-300 mb-1">
                    Turn OFF Time ({liveSched.tz_abbrev || 'Local'})
                  </label>
                  <input
                    type="time"
                    value={scheduleDraft.stop_time}
                    onChange={(e) =>
                      setScheduleDraft((prev) => ({ ...prev, stop_time: e.target.value }))
                    }
                    className="w-full bg-slate-900 border border-slate-700 rounded-lg px-2.5 py-1.5 text-sm font-mono font-bold text-white"
                  />
                </div>

                {/* Scene Preset to Activate Dropdown (all 71 scenes!) (5 cols) */}
                <div className="md:col-span-5 bg-slate-950/90 border border-slate-800 rounded-xl p-3">
                  <label className="block text-[11px] font-bold text-cyan-300 mb-1">
                    Scene Preset to Activate ({presets.length} Scenes Available)
                  </label>
                  <select
                    value={scheduleDraft.preset_id}
                    onChange={(e) =>
                      setScheduleDraft((prev) => ({ ...prev, preset_id: e.target.value }))
                    }
                    className="w-full bg-slate-900 border border-slate-700 rounded-lg px-3 py-2 text-xs font-semibold text-white"
                  >
                    {presets.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name} ({p.category} · {p.badge})
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              {/* Active Days of Week + Turn Off Physical Lights Toggle + Save Button */}
              <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 items-center pt-2">
                {/* Active Days of Week Pills (6 cols) */}
                <div className="lg:col-span-6 bg-slate-950/90 border border-slate-800 rounded-xl p-3.5 space-y-2">
                  <div className="flex items-center justify-between text-xs">
                    <span className="font-bold text-slate-300 flex items-center gap-1.5">
                      <Calendar className="w-3.5 h-3.5 text-cyan-400" />
                      Active Days of Week
                    </span>
                    <span className="text-[11px] font-mono text-cyan-300">
                      {(scheduleDraft.days_of_week || []).length}/7 days active
                    </span>
                  </div>
                  <div className="grid grid-cols-7 gap-1.5">
                    {WEEKDAYS.map((day) => {
                      const active = (scheduleDraft.days_of_week || []).includes(day.id);
                      return (
                        <button
                          key={day.id}
                          type="button"
                          onClick={() => toggleScheduleDay(day.id)}
                          className={`py-2 rounded-xl text-xs font-mono font-extrabold border transition ${
                            active
                              ? 'bg-cyan-500/25 border-cyan-400 text-cyan-200 shadow'
                              : 'bg-slate-900 border-slate-800 text-slate-500 hover:text-slate-300'
                          }`}
                        >
                          {day.label}
                        </button>
                      );
                    })}
                  </div>
                </div>

                {/* Turn Off Physical Govee Lights at Stop Time Toggle (3 cols) */}
                <label className="lg:col-span-3 bg-slate-950/90 border border-slate-800 rounded-xl p-3.5 flex items-center justify-between gap-3 cursor-pointer">
                  <div>
                    <div className="text-xs font-bold text-white">
                      Turn Off Physical Govee Lights at Stop Time
                    </div>
                    <div className="text-[11px] text-slate-400">
                      Sends hardware power OFF &amp; RGB blackout (`#000000`)
                    </div>
                  </div>
                  <input
                    type="checkbox"
                    checked={scheduleDraft.turn_off_lights_on_stop ?? true}
                    onChange={(e) =>
                      setScheduleDraft((prev) => ({
                        ...prev,
                        turn_off_lights_on_stop: e.target.checked,
                      }))
                    }
                    className="w-4 h-4 rounded border-slate-700 text-cyan-500 shrink-0"
                  />
                </label>

                {/* Govee-Side Schedule Control (Allow vs Override Govee Home App Timers) */}
                <div className="lg:col-span-9 bg-slate-950/90 border border-slate-800 rounded-xl p-3.5 flex flex-wrap items-center justify-between gap-3">
                  <div>
                    <div className="text-xs font-bold text-white flex items-center gap-2">
                      <span>Govee Home App Schedule Control</span>
                      <span
                        className={`px-2 py-0.5 rounded-full text-[10px] font-extrabold ${
                          scheduleDraft.override_govee_app_schedules
                            ? 'bg-amber-500/20 text-amber-300 border border-amber-500/40'
                            : 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/40'
                        }`}
                      >
                        {scheduleDraft.override_govee_app_schedules
                          ? 'GOVEE APP TIMERS BLOCKED / OVERRIDDEN'
                          : 'GOVEE APP TIMERS ENABLED'}
                      </span>
                    </div>
                    <div className="text-[11px] text-slate-400 mt-0.5">
                      {scheduleDraft.override_govee_app_schedules
                        ? 'Sync Studio watchdog re-asserts its active scene / off state every 45s so Govee Home app timers cannot override your lights.'
                        : 'Govee Home app timers are allowed to trigger scenes or turn lights on/off between Sync Studio start & stop times.'}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      type="button"
                      onClick={() => {
                        const updated = {
                          ...scheduleDraft,
                          override_govee_app_schedules: false,
                        };
                        setScheduleDraft(updated);
                        handleUpdateSchedule(updated);
                      }}
                      className={`px-3 py-1.5 rounded-lg text-xs font-extrabold border transition ${
                        !scheduleDraft.override_govee_app_schedules
                          ? 'bg-emerald-500/25 border-emerald-400 text-emerald-200'
                          : 'bg-slate-900 border-slate-700 text-slate-400 hover:text-white'
                      }`}
                    >
                      Enable Govee Schedules
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        const updated = {
                          ...scheduleDraft,
                          override_govee_app_schedules: true,
                        };
                        setScheduleDraft(updated);
                        handleUpdateSchedule(updated);
                      }}
                      className={`px-3 py-1.5 rounded-lg text-xs font-extrabold border transition ${
                        scheduleDraft.override_govee_app_schedules
                          ? 'bg-amber-500/25 border-amber-400 text-amber-200'
                          : 'bg-slate-900 border-slate-700 text-slate-400 hover:text-white'
                      }`}
                    >
                      Disable / Override Govee Schedules
                    </button>
                  </div>
                </div>

                {/* Save Schedule to Container Button (3 cols) */}
                <div className="lg:col-span-3">
                  <button
                    type="button"
                    onClick={() => handleUpdateSchedule(scheduleDraft)}
                    disabled={savingSchedule}
                    className="w-full py-3.5 px-4 rounded-xl bg-gradient-to-r from-emerald-400 via-cyan-400 to-blue-500 hover:opacity-95 text-slate-950 font-extrabold text-xs sm:text-sm flex items-center justify-center gap-2 shadow-xl shadow-cyan-500/20 transition"
                  >
                    <CheckCircle2 className="w-4 h-4 stroke-[2.5]" />
                    {savingSchedule ? 'Saving Schedule...' : 'Save Schedule to Container'}
                  </button>
                </div>
              </div>
            </div>

            {/* Scene Playlist Jukebox + 1-Tap Celebration Bursts */}
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
              {/* Scene Playlist Jukebox (6 cols) */}
              <div className="lg:col-span-6 bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 flex flex-col justify-between space-y-4">
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <ListMusic className="w-5 h-5 text-purple-400" />
                    <div>
                      <h3 className="text-base font-extrabold text-white">
                        🎵 Scene Playlist Jukebox
                      </h3>
                      <p className="text-xs text-slate-400">
                        Automatically rotates through holiday &amp; street scenes across all active
                        houses
                      </p>
                    </div>
                  </div>
                  <button
                    onClick={() => handleUpdatePlaylist({ enabled: !playlist.enabled })}
                    className={`px-3 py-1.5 rounded-xl text-xs font-mono font-bold border transition ${
                      playlist.enabled
                        ? 'bg-emerald-400 text-slate-950 border-emerald-300'
                        : 'bg-slate-900 text-slate-400 border-slate-700 hover:text-white'
                    }`}
                  >
                    {playlist.enabled ? 'AUTO-ROTATING' : 'OFF'}
                  </button>
                </div>

                <div>
                  <label className="block text-xs font-semibold text-slate-300 mb-2">
                    Rotation Interval
                  </label>
                  <div className="grid grid-cols-4 gap-2">
                    {[30, 60, 120, 300].map((sec) => (
                      <button
                        key={sec}
                        onClick={() =>
                          handleUpdatePlaylist({ interval_sec: sec, enabled: true })
                        }
                        className={`py-2 rounded-xl text-xs font-mono font-bold border transition ${
                          Number(playlist.interval_sec) === sec && playlist.enabled
                            ? 'bg-purple-500/25 border-purple-400 text-purple-200'
                            : 'bg-slate-950 border-slate-800 text-slate-400 hover:text-white'
                        }`}
                      >
                        {sec < 60 ? `${sec}s` : `${sec / 60}m`}
                      </button>
                    ))}
                  </div>
                </div>
              </div>

              {/* 1-Tap Celebration Bursts (6 cols) */}
              <div className="lg:col-span-6 bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Flame className="w-5 h-5 text-amber-400" />
                    <h3 className="text-base font-extrabold text-white">
                      🎉 1-Tap Street Celebration Bursts (12s)
                    </h3>
                  </div>
                  <span className="text-xs font-mono text-slate-400">Auto-Resumes Scene</span>
                </div>
                <div className="grid grid-cols-2 gap-2.5">
                  {BURST_BUTTONS.map((b) => (
                    <button
                      key={b.type}
                      onClick={() => handleTriggerBurst(b.type)}
                      disabled={burstBusy === b.type}
                      className={`p-3 rounded-xl bg-gradient-to-br border text-left transition shadow ${b.cls}`}
                    >
                      <div className="text-xs font-extrabold">{b.label}</div>
                      <div className="text-[10px] opacity-80 mt-0.5">{b.sub}</div>
                    </button>
                  ))}
                </div>
              </div>
            </div>

            {/* Advanced Shader Engine & Uneven Segment Count Compensation */}
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
              <div className="lg:col-span-7 bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 space-y-4">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <Sparkles className="w-5 h-5 text-cyan-400" />
                    <h2 className="text-base font-bold text-white">
                      16 Analytical Multi-House Shaders
                    </h2>
                  </div>
                  <span className="text-xs text-slate-400">Zero-Drift Shader Engine</span>
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 gap-3.5">
                  {EFFECTS.map((eff) => {
                    const selected = anim.effect === eff.id;
                    const previewAnim = {
                      ...anim,
                      effect: eff.id,
                      primary_color: eff.previewColors?.[0] || anim.primary_color || '#00f5d4',
                      secondary_color:
                        eff.previewColors?.[1] || anim.secondary_color || '#7b2cbf',
                      accent_color: eff.previewColors?.[2] || anim.accent_color || '#ff007f',
                    };
                    return (
                      <button
                        key={eff.id}
                        onClick={() => updateAnimation({ effect: eff.id, running: true })}
                        className={`text-left p-3.5 rounded-xl border transition-all space-y-2 ${
                          selected
                            ? 'bg-gradient-to-br from-cyan-500/20 to-blue-600/15 border-cyan-400 shadow-lg shadow-cyan-500/10'
                            : 'bg-slate-950/70 hover:bg-slate-900/90 border-slate-800/90'
                        }`}
                      >
                        <div className="flex items-center justify-between gap-2">
                          <span className="text-xs font-bold text-white truncate">
                            {eff.name}
                          </span>
                          <span
                            className={`text-[10px] font-mono px-2 py-0.5 rounded-full shrink-0 ${
                              selected
                                ? 'bg-cyan-400 text-slate-950 font-bold'
                                : 'bg-slate-800 text-slate-400'
                            }`}
                          >
                            {eff.badge}
                          </span>
                        </div>

                        <LiveSceneCardPreview
                          animation={previewAnim}
                          houses={config?.houses}
                          height={88}
                        />

                        <p className="text-[11px] text-slate-400 leading-relaxed">{eff.desc}</p>
                      </button>
                    );
                  })}
                </div>
              </div>

              <div className="lg:col-span-5 space-y-6">
                {/* Advanced Shader Sliders */}
                <div className="bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 space-y-4">
                  <div className="flex items-center gap-2">
                    <Gauge className="w-5 h-5 text-cyan-400" />
                    <h2 className="text-base font-bold text-white">
                      Advanced Shader &amp; Clock Parameters
                    </h2>
                  </div>

                  {/* Tail Length */}
                  <div>
                    <div className="flex justify-between text-xs mb-1">
                      <span className="font-semibold text-slate-300">Chase / Comet Tail Length</span>
                      <span className="font-mono text-cyan-300">
                        {Math.round((anim.tail_length || 0.22) * 100)}% of strip
                      </span>
                    </div>
                    <input
                      type="range"
                      min="0.05"
                      max="0.75"
                      step="0.01"
                      value={anim.tail_length || 0.22}
                      onChange={(e) =>
                        updateAnimation({ tail_length: parseFloat(e.target.value) })
                      }
                      className="w-full accent-cyan-400"
                    />
                  </div>

                  {/* Simultaneous Pulses */}
                  <div>
                    <div className="flex justify-between text-xs mb-1">
                      <span className="font-semibold text-slate-300">Simultaneous Chase Heads</span>
                      <span className="font-mono text-cyan-300">{anim.pulse_count || 1}</span>
                    </div>
                    <input
                      type="range"
                      min="1"
                      max="6"
                      step="1"
                      value={anim.pulse_count || 1}
                      onChange={(e) =>
                        updateAnimation({ pulse_count: parseInt(e.target.value, 10) })
                      }
                      className="w-full accent-cyan-400"
                    />
                  </div>

                  {/* Background Glow Level */}
                  <div>
                    <div className="flex justify-between text-xs mb-1">
                      <span className="font-semibold text-slate-300">Ambient Background Glow</span>
                      <span className="font-mono text-cyan-300">
                        {Math.round((anim.background_dim ?? 0.08) * 100)}%
                      </span>
                    </div>
                    <input
                      type="range"
                      min="0"
                      max="0.5"
                      step="0.01"
                      value={anim.background_dim ?? 0.08}
                      onChange={(e) =>
                        updateAnimation({ background_dim: parseFloat(e.target.value) })
                      }
                      className="w-full accent-cyan-400"
                    />
                  </div>

                  {/* Frame Rate (FPS) */}
                  <div>
                    <div className="flex justify-between text-xs mb-1">
                      <span className="font-semibold text-slate-300">Update Frequency (FPS)</span>
                      <span className="font-mono text-cyan-300">{anim.fps || 25} FPS</span>
                    </div>
                    <input
                      type="range"
                      min="10"
                      max="50"
                      step="5"
                      value={anim.fps || 25}
                      onChange={(e) => updateAnimation({ fps: parseInt(e.target.value, 10) })}
                      className="w-full accent-cyan-400"
                    />
                  </div>

                  {/* Sub-segment supersampling toggle */}
                  <label className="flex items-center justify-between p-3 rounded-xl bg-slate-950/90 border border-slate-800 cursor-pointer text-xs">
                    <div>
                      <div className="font-semibold text-white">
                        5-Point Sub-Segment Anti-Aliasing
                      </div>
                      <div className="text-slate-400 text-[11px]">
                        Smooths narrow pulses across wider segments on houses with fewer controllers
                      </div>
                    </div>
                    <input
                      type="checkbox"
                      checked={anim.supersample ?? true}
                      onChange={(e) => updateAnimation({ supersample: e.target.checked })}
                      className="rounded border-slate-700 text-cyan-500"
                    />
                  </label>
                </div>

                {/* Segment Compensation Mode Selector */}
                <div className="bg-[#0c1222]/90 border border-slate-800 rounded-2xl p-5 space-y-3">
                  <div className="flex items-center gap-2">
                    <Layers className="w-5 h-5 text-emerald-400" />
                    <div>
                      <h3 className="text-base font-bold text-white">
                        Uneven Segment Count Compensation Mode
                      </h3>
                      <p className="text-xs text-slate-400">
                        Keeps My House (9 segs) locked with Neighbor 1 (24 segs) &amp; Neighbor 2
                        (30 segs)
                      </p>
                    </div>
                  </div>

                  <div className="space-y-2.5">
                    {MAPPING_MODES.map((m) => {
                      const active = anim.mapping_mode === m.id;
                      return (
                        <button
                          key={m.id}
                          onClick={() => updateAnimation({ mapping_mode: m.id })}
                          className={`w-full text-left p-3 rounded-xl border transition flex items-start justify-between gap-3 ${
                            active
                              ? 'bg-emerald-500/15 border-emerald-400/80 text-white'
                              : 'bg-slate-950/70 border-slate-800 text-slate-300 hover:bg-slate-900'
                          }`}
                        >
                          <div>
                            <div className="text-xs font-bold">{m.name}</div>
                            <div className="text-[11px] text-slate-400 mt-0.5">{m.desc}</div>
                          </div>
                          <span
                            className={`mt-0.5 w-4 h-4 rounded-full border flex items-center justify-center shrink-0 ${
                              active ? 'border-emerald-400 bg-emerald-400' : 'border-slate-600'
                            }`}
                          >
                            {active && <span className="w-1.5 h-1.5 rounded-full bg-slate-950" />}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 4: 📡 DISCOVERY & LOGS */}
        {activeTab === 'discovery' && (
          <DiscoveryAndLogs
            config={config}
            liveState={liveState}
            discoveredDevices={discoveredDevices}
            onTriggerScan={handleTriggerScan}
            onSaveConfig={handleSaveFullConfig}
            onClearLogs={handleClearLogs}
          />
        )}

        {/* TAB 5: 👥 ACCESS */}
        {activeTab === 'users' && (
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
            {/* Authorized Emails Management Card */}
            <div className="lg:col-span-7 bg-[#0c1222]/95 border border-cyan-500/40 rounded-2xl p-5 sm:p-6 shadow-2xl space-y-5">
              <div className="flex items-start justify-between gap-4 border-b border-slate-800 pb-4">
                <div>
                  <div className="flex items-center gap-2">
                    <Users className="w-5 h-5 text-cyan-400" />
                    <h2 className="text-lg font-extrabold text-white">
                      Authorized Users &amp; OAuth Access Control
                    </h2>
                  </div>
                  <p className="text-xs text-slate-400 mt-1">
                    When accessed externally via{' '}
                    <code className="text-cyan-300 font-mono">
                      {typeof window !== 'undefined' ? window.location.origin : 'https://govee-sync.local'}
                    </code>{' '}
                    or
                    the Android App, only Google &amp; GitHub accounts matching the emails below are
                    granted control.
                  </p>
                </div>
                <span className="text-[10px] font-mono px-2.5 py-1 rounded-full bg-emerald-500/15 text-emerald-300 border border-emerald-500/30 font-bold shrink-0">
                  {authorizedEmails.length} AUTHORIZED
                </span>
              </div>

              {/* Add Email Form */}
              <form onSubmit={handleAddAuthorizedEmail} className="flex flex-wrap gap-2.5">
                <input
                  type="email"
                  required
                  value={newEmailInput}
                  onChange={(e) => setNewEmailInput(e.target.value)}
                  placeholder="Enter family or neighbor email (e.g. neighbor@example.com)..."
                  className="flex-1 min-w-[220px] bg-slate-950 border border-slate-700 rounded-xl px-3.5 py-2.5 text-xs text-white font-mono focus:outline-none focus:border-cyan-400"
                />
                <button
                  type="submit"
                  className="px-4 py-2.5 rounded-xl bg-gradient-to-r from-cyan-400 to-blue-500 hover:from-cyan-300 hover:to-blue-400 text-slate-950 font-extrabold text-xs flex items-center gap-1.5 shadow-lg transition"
                >
                  <Plus className="w-4 h-4 stroke-[2.5]" /> + Authorize Email
                </button>
              </form>

              {/* Authorized Emails List */}
              <div className="space-y-2">
                {authorizedEmails.map((email) => {
                  const isOwner = email.toLowerCase() === (authStatus.owner || 'owner@example.com');
                  return (
                    <div
                      key={email}
                      className="flex items-center justify-between gap-3 bg-slate-950/90 border border-slate-800 rounded-xl px-4 py-3"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <Shield
                          className={`w-4 h-4 shrink-0 ${
                            isOwner ? 'text-emerald-400' : 'text-cyan-400'
                          }`}
                        />
                        <span className="text-xs sm:text-sm font-mono font-bold text-white truncate">
                          {email}
                        </span>
                        {isOwner && (
                          <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 font-bold">
                            OWNER (PERMANENT)
                          </span>
                        )}
                      </div>

                      {!isOwner && (
                        <button
                          onClick={() => handleRemoveAuthorizedEmail(email)}
                          className="px-2.5 py-1 rounded-lg bg-rose-500/15 hover:bg-rose-500/30 text-rose-300 border border-rose-500/30 text-xs font-semibold flex items-center gap-1 transition shrink-0"
                        >
                          <Trash2 className="w-3.5 h-3.5" /> Remove
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Authenticated Android App Download, Version Archive & OAuth Sign-In Card */}
            <div className="lg:col-span-5 space-y-5">
              <div className="bg-[#0c1222]/95 border border-purple-500/35 rounded-2xl p-5 sm:p-6 shadow-2xl space-y-4">
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <BrandLogo className="w-11 h-11 rounded-xl" />
                    <div>
                      <h3 className="text-base font-extrabold text-white">
                        Android APK Version &amp; Release History Center
                      </h3>
                      <p className="text-xs text-slate-400">
                        Optimized for Samsung Galaxy Z Fold 7 (Cover &amp; Unfolded Split-Screen)
                      </p>
                    </div>
                  </div>
                  <span className="px-2.5 py-1 rounded-full bg-cyan-500/15 border border-cyan-400/40 text-cyan-300 text-[11px] font-extrabold font-mono shrink-0">
                    v{apkVersionName} · Build {apkVersionCode}
                  </span>
                </div>

                {/* Latest Release Highlights */}
                <div className="p-3.5 rounded-xl bg-slate-900/85 border border-slate-800 space-y-2">
                  <div className="flex flex-wrap items-center justify-between gap-2 text-[11px] text-slate-300">
                    <span className="font-bold text-emerald-300">
                      Latest Release: v{apkVersionName} (Build {apkVersionCode})
                    </span>
                    <span className="font-mono text-slate-400">
                      {apkSizeMb}
                      {apkInfo?.released_at ? ` · ${apkInfo.released_at.slice(0, 10)}` : ''}
                    </span>
                  </div>
                  {apkInfo?.sha256 && (
                    <div className="text-[10px] font-mono text-slate-400 truncate">
                      SHA-256: {apkInfo.sha256.slice(0, 24)}…
                    </div>
                  )}
                  {Array.isArray(apkInfo?.changelog) && apkInfo.changelog.length > 0 && (
                    <ul className="text-[11px] text-slate-300 list-disc list-inside space-y-0.5 pt-1">
                      {apkInfo.changelog.map((note, idx) => (
                        <li key={idx}>{note}</li>
                      ))}
                    </ul>
                  )}
                </div>

                <a
                  href={apkDownloadHref}
                  download={apkInfo?.filename || `Govee-Sync-Studio-v${apkVersionName}-b${apkVersionCode}.apk`}
                  className="w-full py-3 px-4 rounded-xl bg-gradient-to-r from-cyan-400 via-blue-500 to-purple-600 hover:opacity-95 text-slate-950 font-extrabold text-xs sm:text-sm flex items-center justify-center gap-2 shadow-lg transition"
                >
                  <Download className="w-4 h-4 stroke-[2.5]" />
                  📱 Download Latest APK v{apkVersionName} ({apkSizeMb})
                </a>

                {/* Archived APK Versions List (Download Any Version / Rollback) */}
                <div className="pt-3 border-t border-slate-800 space-y-2">
                  <div className="text-xs font-bold text-slate-300 flex items-center justify-between">
                    <span>All Archived APK Releases ({apkReleases.length})</span>
                    <span className="text-[10px] text-slate-400 font-normal">
                      Install latest or roll back anytime
                    </span>
                  </div>
                  <div className="space-y-2 max-h-60 overflow-y-auto pr-1">
                    {apkReleases.map((rel, idx) => {
                      const isLatest = idx === 0;
                      const relSizeMb = rel.size_bytes
                        ? `${(rel.size_bytes / (1024 * 1024)).toFixed(1)} MB`
                        : '';
                      const dlHref = buildApkDownloadHref(rel.version_name);
                      return (
                        <div
                          key={`${rel.version_name}-${rel.version_code}`}
                          className="p-2.5 rounded-xl bg-slate-900/70 border border-slate-800/90 flex flex-col gap-1.5"
                        >
                          <div className="flex items-center justify-between gap-2">
                            <div>
                              <div className="text-xs font-bold text-white flex items-center gap-1.5">
                                <span>
                                  v{rel.version_name} (Build {rel.version_code}
                                  {isLatest ? ' - Latest' : ''})
                                </span>
                              </div>
                              <div className="text-[10px] text-slate-400 font-mono">
                                {relSizeMb}
                                {rel.released_at ? ` · ${rel.released_at.slice(0, 10)}` : ''}
                              </div>
                            </div>
                            <a
                              href={dlHref}
                              download={rel.filename || `Govee-Sync-Studio-v${rel.version_name}-b${rel.version_code}.apk`}
                              className="px-2.5 py-1.5 rounded-lg bg-cyan-500/20 hover:bg-cyan-500/35 text-cyan-200 border border-cyan-500/40 text-[11px] font-bold flex items-center gap-1 shrink-0 transition"
                            >
                              <Download className="w-3 h-3" />
                              <span>⬇ Download v{rel.version_name}</span>
                            </a>
                          </div>
                          {Array.isArray(rel.changelog) && rel.changelog.length > 0 && (
                            <ul className="text-[10px] text-slate-400 list-disc list-inside space-y-0.5">
                              {rel.changelog.map((item, cIdx) => (
                                <li key={cIdx}>{item}</li>
                              ))}
                            </ul>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>

                <div className="pt-3 border-t border-slate-800 space-y-2.5">
                  <div className="text-xs font-bold text-slate-300">
                    Google &amp; GitHub Single Sign-On
                  </div>
                  <div className="grid grid-cols-2 gap-2.5">
                    <a
                      href="/api/auth/google/login"
                      className="py-2.5 px-3 rounded-xl bg-white hover:bg-slate-100 text-slate-950 font-bold text-xs flex items-center justify-center gap-1.5 transition"
                    >
                      <Globe className="w-3.5 h-3.5 text-blue-600" /> Google Sign-In
                    </a>
                    <a
                      href="/api/auth/github/login"
                      className="py-2.5 px-3 rounded-xl bg-slate-900 hover:bg-slate-800 text-white border border-slate-700 font-bold text-xs flex items-center justify-center gap-1.5 transition"
                    >
                      <Shield className="w-3.5 h-3.5 text-cyan-400" /> GitHub Sign-In
                    </a>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
        </main>
      </div>

      {/* Fixed Thumb-Friendly 5-Tab Bottom Navigation Bar for Mobile & Galaxy Z Fold 7 Cover Screen (<768px) */}
      <nav className="md:hidden fixed bottom-0 left-0 right-0 z-40 bg-[#060a15]/95 backdrop-blur-2xl border-t border-slate-800 px-1.5 py-1.5 grid grid-cols-5 gap-1">
        {[
          { id: 'scenes', label: 'Scenes', Icon: Sparkles },
          { id: 'houses', label: 'Houses', Icon: Home },
          { id: 'schedule', label: 'Schedule', Icon: Clock },
          { id: 'discovery', label: 'Logs', Icon: Radio },
          { id: 'users', label: 'Access', Icon: Users },
        ].map(({ id, label, Icon }) => {
          const active =
            activeTab === id || (id === 'scenes' && activeTab === 'dashboard');
          return (
            <button
              key={id}
              onClick={() => setActiveTab(id)}
              className={`py-1.5 rounded-xl flex flex-col items-center justify-center gap-0.5 text-[10px] font-bold transition ${
                active
                  ? 'bg-cyan-500/20 text-cyan-300 border border-cyan-500/35'
                  : 'text-slate-400'
              }`}
            >
              <Icon className="w-4 h-4" />
              <span>{label}</span>
            </button>
          );
        })}
      </nav>
    </div>
  );
}
