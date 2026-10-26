# Govee Multi-House Light Sync

A complete Dockerized central controller and dark-themed Web Studio for synchronizing **Govee Wi-Fi / RGBIC lights across multiple houses** with **zero timing drift** and **real-time uneven segment compensation**.

Designed to live in `/mnt/media/govee_lights_sync` with persistent state in `/mnt/media/govee_lights_sync/data`.

---

## Why Multi-House Govee Animations Usually Drift (and How This Solves It)

When syncing lights across multiple houses with uneven hardware—for example:
- **House 1 (My House):** 1 Govee controller (9 segments)
- **House 2 (Neighbor 1):** 2 Govee controllers (12 + 12 = 24 segments)
- **House 3 (Neighbor 2):** 2 Govee controllers (15 + 15 = 30 segments)

standard segment-stepping loops fail in two ways:
1. **Cumulative Timer Drift:** Loops that do `sleep(1 / fps)` and increment `phase += speed` drift by the UDP/HTTP execution time on every tick, falling visibly out of sync after 30–60 seconds.
2. **Uneven Segment Density:** Stepping 1 segment at a time makes a 9-segment house finish 3.33× faster than a 30-segment house, breaking continuous cross-house chases.

### How Govee Multi-House Light Sync Solves Both
1. **Nanosecond Monotonic Master Clock (`time.monotonic_ns()`):**
   - Every frame is evaluated as a pure closed-form analytical function of monotonic time:
     $$\phi(t) = \phi_{\text{anchor}} + (t_{\text{monotonic}} - t_{\text{anchor}}) \cdot f_{\text{speed}}$$
   - When speed or direction is adjusted live, $\phi_{\text{anchor}}$ is re-anchored atomically ($C^0$ phase continuity) so animations never jump and **never accumulate drift over 60 seconds, 60 minutes, or 60 days**.
   - The frame loop uses **absolute deadline scheduling** (`next_deadline += frame_period`) and reports real-time clock jitter (`clock_drift_ms`) on the dashboard.
2. **Real-Time Segment Count Compensation (`house_normalized` mode):**
   - Each house $h \in \{1 \dots H\}$ is allocated an equal normalized span $[ \frac{h-1}{H}, \frac{h}{H} )$ on the master $[0, 1)$ timeline (or weighted by `time_weight`).
   - Inside house $h$, all of its controllers and segments $N_h$ are mapped across that house's span with exact normalized center $x_i$ and segment width $w_i = \frac{1}{H \cdot N_h}$.
   - **5-Point Sub-Segment Supersampling** integrates the animation shader across each segment's physical width $[x_i - 0.36w_i, x_i + 0.36w_i]$ so narrow comets and chase heads look equally smooth and vivid on a 1-controller house as on a 2-controller neighbor house.
   - You can also switch live between **House-Normalized Equal Time**, **Continuous Virtual Strip (Uniform Per-Segment)**, and **Synchronized Parallel House Zones**.

---

## Project Structure

```text
/mnt/media/govee_lights_sync/
├── Dockerfile                        # Multi-stage build (Node 22 Vite UI + Python 3.12 FastAPI)
├── docker-compose.yml                # Uses network_mode: host + /mnt/media/govee_lights_sync/data volume
├── .env.example                      # Optional environment variables (PORT, GOVEE_API_KEY, UDP ports)
├── README.md                         # Setup & architecture documentation
├── data/
│   └── config.json                   # Permanent configuration (auto-seeded on first start)
├── examples/
│   ├── default_3_houses.json         # Default 3-House topology (1 + 2 + 2 controllers)
│   └── uneven_segment_showcase.json  # Extreme 6 vs 24 vs 36 segment showcase
├── backend/
│   ├── requirements.txt
│   └── app/
│       ├── main.py                   # FastAPI REST API + /ws/live 25 FPS WebSocket broadcaster + SPA host
│       ├── animation_engine.py       # Monotonic Master Clock, Uneven Segment Compensator & 8 Effects
│       ├── govee_protocol.py         # Govee LAN UDP (4001/4002/4003, colorwc & ptReal) + Cloud API v1
│       ├── config_store.py           # Atomic JSON persistence & backup manager
│       └── models.py                 # Pydantic schemas
├── frontend/
│   ├── package.json
│   ├── vite.config.js
│   └── src/
│       ├── App.jsx                   # Dark-themed Live Studio, Controls, Presets & Tabs
│       └── components/
│           ├── NeighborhoodPreview.jsx # Live 3-house architectural roofline & timeline visualizer
│           ├── HouseConfigEditor.jsx   # GUI editor for houses, controllers, IPs/MACs & segment counts
│           └── DiscoveryAndLogs.jsx    # LAN/Cloud device scanner & real-time controller packet log
└── tests/
    └── test_sync_engine.py           # Pytest suite for zero-drift clock & uneven segment math
```

---

## Quick Start (Docker Compose)

```bash
cd /mnt/media/govee_lights_sync

# Build and start in the background (uses network_mode: host for Govee UDP multicast)
docker compose up -d --build

# If UFW is enabled on the host, allow the Web GUI (8200/tcp) and Govee LAN UDP (4001-4003/udp)
ufw allow from 192.168.1.0/24 to any port 8200 proto tcp comment 'govee-lights-sync GUI LAN'
ufw allow from 192.168.1.0/24 to any port 4001:4003 proto udp comment 'Govee LAN API UDP'

# Check container status and logs
docker compose ps
docker compose logs -f
```

Open the Web GUI in your browser (desktop or phone):
- **URL:** `http://<host-ip>:8200` (e.g. `http://192.168.1.100:8200`)
- **Health Check API:** `http://127.0.0.1:8200/api/health`

---

## Automatic Git Redaction Filter & Secret Guard

This repository includes an automatic Git clean filter and pre-commit/pre-push hooks (`scripts/git_redact_filter.py`, `.gitattributes`, and `.githooks/`) so future commits and pushes always redact local secrets, OAuth credentials, API keys, and personal LAN/domain identifiers:

```bash
# Enable repository git hooks and automatic clean filter (configured automatically)
git config core.hooksPath .githooks
git config filter.govee-redact.clean "python3 scripts/git_redact_filter.py --clean"
git config filter.govee-redact.smudge cat

# Run a manual verification scan at any time
python3 scripts/git_redact_filter.py --verify
```

---

## Enabling Govee LAN Control on Your Controllers

1. Open the **Govee Home** app on your phone and wait ~5 seconds on the device list screen.
2. Tap each controller → **Settings (gear icon)** → toggle **LAN Control** **ON**.
3. If your neighbors' controllers are on the same Wi-Fi / LAN subnet (or bridged VLAN/mesh), they will appear automatically when you click **Scan LAN / Cloud Devices**, or you can enter their **IP** and **MAC** directly in the **Houses & Segments** tab.
4. Choose the per-controller **Protocol Mode**:
   - `Auto (LAN UDP + Cloud Fallback)` *(Default)* — Sends low-latency UDP packets on port `4003` and optionally falls back to Govee Cloud API if configured.
   - `LAN UDP colorwc` — Official Govee LAN whole-controller RGB command using perceptual peak-preserving color weighting so chases across controllers are crisp and immediate.
   - `LAN UDP ptReal` — Sends base64-encoded XOR-checksummed BLE-over-LAN per-segment RGBIC packets (`0x33 0x05 0x15 0x01 ...`) over UDP `:4003`.
   - `Govee Cloud API` — Uses Govee OpenAPI v1 `segmentedColorRgb` (`https://openapi.api.govee.com/router/api/v1/device/control`) with automatic per-device rate limiting.
   - `Simulation` — Virtual preview mode for testing topologies before physical controllers are online.

---

## Included Animations

1. **Smooth Multi-House Chase (`multi_house_chase`)** — Glowing anti-aliased chase head with gradient tail flowing continuously `House 1 → House 2 → House 3`.
2. **Continuous Rainbow Wave (`rainbow_wave`)** — Seamless full-spectrum HSV wave locked across all houses.
3. **Comet / Meteor Shower (`comet_meteor`)** — White-hot meteor core with shimmering plasma decay tail.
4. **Synchronized Breathing (`breathing_pulse`)** — Harmonic lockstep breathing across all houses.
5. **Multi-House Color Wipe (`color_wipe`)** — Progressive anti-aliased color wipe across `House 1 → House 2 → House 3`.
6. **Compensated Theater Chase (`theater_chase`)** — Classic marquee triplets scaled to normalized virtual strip coordinates.
7. **Fire & Rising Embers (`fire_sparkle`)** — Deterministic value-noise hearth fire across all rooflines.
8. **Starlight Sparkle & Aurora (`sparkle_twinkle`)** — Glittering starlight bursts over a moving aurora wave.
