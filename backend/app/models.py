from __future__ import annotations

import os
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional
from pydantic import BaseModel, Field, field_validator


def _load_env_if_needed() -> None:
    if os.environ.get("OWNER_EMAIL"):
        return
    for candidate in (Path(__file__).resolve().parents[2] / ".env", Path("/mnt/media/govee_lights_sync/.env")):
        try:
            if not candidate.exists():
                continue
            for raw_line in candidate.read_text(encoding="utf-8", errors="ignore").splitlines():
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                if line.startswith("export "):
                    line = line[len("export ") :].strip()
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip()
                if len(v) >= 2 and ((v[0] == v[-1] == '"') or (v[0] == v[-1] == "'")):
                    v = v[1:-1]
                if k and v and not os.environ.get(k):
                    os.environ[k] = v
        except Exception:
            pass


_load_env_if_needed()


class ProtocolMode(str, Enum):
    AUTO = "auto"
    LAN_COLORWC = "lan_colorwc"
    LAN_PTREAL = "lan_ptreal"
    CLOUD_API = "cloud_api"
    SIMULATION = "simulation"


class SpatialMappingMode(str, Enum):
    HOUSE_NORMALIZED = "house_normalized"
    VIRTUAL_STRIP = "virtual_strip"
    PARALLEL_ZONES = "parallel_zones"


class DirectionMode(str, Enum):
    FORWARD = "forward"
    REVERSE = "reverse"
    PINGPONG = "pingpong"


class EffectType(str, Enum):
    MULTI_HOUSE_CHASE = "multi_house_chase"
    RAINBOW_WAVE = "rainbow_wave"
    COMET_METEOR = "comet_meteor"
    BREATHING_PULSE = "breathing_pulse"
    COLOR_WIPE = "color_wipe"
    THEATER_CHASE = "theater_chase"
    FIRE_SPARKLE = "fire_sparkle"
    SPARKLE_TWINKLE = "sparkle_twinkle"
    HALLOWEEN_SPOOKY = "halloween_spooky"
    CHRISTMAS_MAGIC = "christmas_magic"
    DIWALI_FESTIVAL = "diwali_festival"
    CENTER_OUT_SHOCKWAVE = "center_out_shockwave"
    LIGHTNING_STORM = "lightning_storm"
    CYBER_SNAKE = "cyber_snake"
    GOVEE_RAINBOW1 = "govee_rainbow1"
    GOVEE_RAINBOW2 = "govee_rainbow2"


class ControllerConfig(BaseModel):
    id: str = Field(..., description="Unique controller identifier")
    name: str = Field(..., description="Human-friendly controller name")
    ip: str = Field(default="", description="Controller LAN IPv4 address")
    mac: str = Field(default="", description="Govee device MAC / ID (e.g. AA:BB:CC:DD:EE:FF:00:11)")
    sku: str = Field(default="H705A", description="Govee model SKU (e.g. H705A, H706A, H619A)")
    segment_count: int = Field(default=12, ge=1, le=200, description="Number of addressable segments on this controller")
    enabled: bool = Field(default=True, description="Include this controller in sync")
    reversed: bool = Field(default=False, description="Reverse physical segment order on this controller")
    protocol_mode: ProtocolMode = Field(default=ProtocolMode.AUTO, description="Control transport mode")
    brightness_override: Optional[int] = Field(default=None, ge=1, le=100, description="Optional per-controller brightness cap")

    @field_validator("ip")
    @classmethod
    def strip_ip(cls, v: str) -> str:
        return v.strip()

    @field_validator("mac")
    @classmethod
    def normalize_mac(cls, v: str) -> str:
        return v.strip().upper()


class HouseConfig(BaseModel):
    id: str = Field(..., description="Unique house identifier")
    name: str = Field(..., description="House display name")
    order: int = Field(default=1, ge=1, description="Sequence order in multi-house chase (1 -> 2 -> 3)")
    enabled: bool = Field(default=True, description="Include this house in animations")
    time_weight: float = Field(
        default=1.0,
        ge=0.1,
        le=10.0,
        description="Relative transit time share in house_normalized mode (1.0 = equal time per house)",
    )
    connection_type: Literal["local_lan", "govee_cloud", "neighbor_bridge", "tailscale_vpn"] = Field(
        default="local_lan",
        description="Connection transport used to reach this house's controllers (local LAN or internet)",
    )
    govee_api_key: str = Field(
        default="",
        description="Optional per-house Govee Cloud OpenAPI Key (for neighbors on their own Wi-Fi)",
    )
    bridge_token: str = Field(
        default="",
        description="Optional shared secret token for Neighbor Bridge WebSocket relay",
    )
    notes: str = Field(default="", description="Optional notes about the house setup")
    controllers: List[ControllerConfig] = Field(default_factory=list, description="Controllers installed on this house")

    @property
    def total_segments(self) -> int:
        return sum(c.segment_count for c in self.controllers if c.enabled)


class AnimationConfig(BaseModel):
    running: bool = Field(default=True, description="Whether the master animation clock is actively transmitting")
    blackout_on_stop: bool = Field(
        default=True,
        description="When True, stopping sync sets segments to off (#000000) and sends blackout to controllers",
    )
    effect: EffectType = Field(default=EffectType.MULTI_HOUSE_CHASE, description="Active animation effect")
    speed: float = Field(
        default=0.25,
        ge=0.02,
        le=3.0,
        description="Cycles per second across the entire multi-house strip (e.g. 0.25 = 4.0s full 3-house traversal)",
    )
    direction: DirectionMode = Field(default=DirectionMode.FORWARD, description="Chase travel direction")
    mapping_mode: SpatialMappingMode = Field(
        default=SpatialMappingMode.HOUSE_NORMALIZED,
        description="How uneven segment counts are compensated across houses",
    )
    fps: int = Field(default=25, ge=5, le=60, description="Master loop update rate (frames per second)")
    intensity: int = Field(default=100, ge=1, le=100, description="Master brightness / intensity percentage")
    primary_color: str = Field(default="#00f5d4", description="Primary hex color")
    secondary_color: str = Field(default="#7b2cbf", description="Secondary hex color")
    accent_color: str = Field(default="#ff007f", description="Accent hex color")
    background_color: str = Field(default="#060814", description="Background / base hex color")
    background_dim: float = Field(default=0.08, ge=0.0, le=1.0, description="Background glow level (0..1)")
    tail_length: float = Field(default=0.22, ge=0.03, le=0.85, description="Normalized length of chase/comet tail")
    pulse_count: int = Field(default=1, ge=1, le=6, description="Number of simultaneous chase heads across the strip")
    supersample: bool = Field(
        default=True,
        description="Anti-aliased sub-segment integration so wide segments on smaller houses match high-density houses",
    )


class PlaylistConfig(BaseModel):
    enabled: bool = Field(default=False, description="Enable automatic playlist jukebox rotation")
    preset_ids: List[str] = Field(
        default_factory=lambda: [
            "cyber_chase",
            "xmas_sleigh_ride",
            "diwali_golden_diya",
            "halloween_haunted_chase",
        ],
        description="Ordered list of preset IDs to cycle through",
    )
    interval_sec: int = Field(default=60, ge=5, le=3600, description="Seconds per preset in playlist mode")


class ScheduleConfig(BaseModel):
    enabled: bool = Field(default=False, description="Enable daily automatic start/stop schedule")
    start_time: str = Field(default="17:30", description="Daily Turn-ON time in HH:MM (24-hour)")
    stop_time: str = Field(default="23:00", description="Daily Turn-OFF time in HH:MM (24-hour)")
    preset_id: str = Field(default="cyber_chase", description="Scene preset ID to run when schedule turns ON")
    timezone: str = Field(
        default="America/Los_Angeles",
        description="Auto-detected IANA timezone (handles DST automatically)",
    )
    days_of_week: List[str] = Field(
        default_factory=lambda: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
        description="Active days of week",
    )
    turn_off_lights_on_stop: bool = Field(
        default=True,
        description="Send hardware power OFF (turn:0) to all Govee controllers at stop_time",
    )
    override_govee_app_schedules: bool = Field(
        default=False,
        description="When True, block/override Govee Home app timers via active state watchdog so only Sync Studio's schedule applies",
    )


OWNER_EMAIL = (os.environ.get("OWNER_EMAIL") or "owner@example.com").strip().lower()


def normalize_authorized_emails(emails: Optional[List[str]]) -> List[str]:
    cleaned: List[str] = [OWNER_EMAIL]
    for raw in emails or []:
        if not isinstance(raw, str):
            continue
        em = raw.strip().lower()
        if em and "@" in em and em not in cleaned:
            cleaned.append(em)
    return cleaned


class SystemConfig(BaseModel):
    system_name: str = Field(default="Govee Multi-House Light Sync")
    govee_api_key: str = Field(default="", description="Optional Govee Cloud OpenAPI Key")
    lan_enabled: bool = Field(default=True, description="Enable Govee LAN UDP multicast/unicast control")
    cloud_fallback_enabled: bool = Field(default=True, description="Allow Cloud API fallback for segment control")
    verbose_packet_logging: bool = Field(default=True, description="Log packets dispatched to each controller")
    houses: List[HouseConfig] = Field(default_factory=list)
    animation: AnimationConfig = Field(default_factory=AnimationConfig)
    active_preset_id: str = Field(default="cyber_chase", description="Currently selected scene preset ID")
    preset_overrides: Dict[str, Dict[str, Any]] = Field(
        default_factory=dict,
        description="Per-scene saved overrides for speed, direction, colors, tail_length, and pulse_count",
    )
    playlist: PlaylistConfig = Field(default_factory=PlaylistConfig)
    schedule: ScheduleConfig = Field(default_factory=ScheduleConfig)
    authorized_emails: List[str] = Field(default_factory=lambda: [OWNER_EMAIL])

    @field_validator("authorized_emails", mode="before")
    @classmethod
    def ensure_owner_email(cls, v: object) -> List[str]:
        if isinstance(v, list):
            return normalize_authorized_emails([str(x) for x in v])
        return [OWNER_EMAIL]


class DiscoveredDevice(BaseModel):
    ip: str
    mac: str
    sku: str = "Unknown"
    name: str = ""
    source: Literal["lan", "cloud", "manual"] = "lan"
    ble_version_hard: str = ""
    ble_version_soft: str = ""
    wifi_version_hard: str = ""
    wifi_version_soft: str = ""
    last_seen: float = 0.0
    online: bool = True
    on_off: Optional[int] = None
    brightness: Optional[int] = None
    supports_segment_rgb: bool = True


class PacketLogEntry(BaseModel):
    timestamp: float
    iso_time: str
    house_id: str
    house_name: str
    controller_id: str
    controller_name: str
    target_ip: str
    protocol: str
    cmd: str
    summary: str
    rgb_preview: str
    latency_ms: float
    success: bool


class SegmentRenderPoint(BaseModel):
    global_index: int
    house_id: str
    house_name: str
    house_index: int
    controller_id: str
    controller_name: str
    controller_index: int
    segment_index: int
    normalized_pos: float
    normalized_width: float
    r: int
    g: int
    b: int
    hex_color: str
