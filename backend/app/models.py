from __future__ import annotations

import os
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Literal, Optional, Tuple
from pydantic import BaseModel, Field, field_validator, model_validator


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


class ArchSection(BaseModel):
    id: str = Field(..., description="Unique section ID within the house (e.g. sec-main-gable)")
    label: str = Field(default="Roof Section", description="Human-readable section name")
    shape: Literal["triangle_gable", "steep_gable", "flat_eave", "hip_roof", "shed_slope", "dormer_peak"] = Field(
        default="triangle_gable",
        description="Roofline geometry shape for this section",
    )
    wall: Literal["front", "left", "right", "back"] = Field(default="front")
    story: int = Field(default=1, ge=1, le=3)
    x_start: float = Field(default=0.0, ge=0.0, le=1.0)
    x_end: float = Field(default=1.0, ge=0.0, le=1.0)
    eave_height: float = Field(default=0.52, ge=0.15, le=0.98)
    peak_height: float = Field(default=0.88, ge=0.15, le=1.0)
    peak_offset: float = Field(default=0.50, ge=0.10, le=0.90)
    depth_offset: float = Field(default=0.0, ge=-0.45, le=0.45)
    has_garage: bool = Field(default=False)
    has_door: bool = Field(default=False)
    window_style: Literal["modern_grid", "arched", "picture", "double_hung", "none"] = Field(default="modern_grid")


class HouseArchitecture(BaseModel):
    preset_style: str = Field(default="a_frame_gable")
    default_view_mode: Literal["3d", "2d"] = Field(default="3d")
    camera_yaw: float = Field(default=-26.0, ge=-180.0, le=180.0)
    camera_pitch: float = Field(default=20.0, ge=5.0, le=75.0)
    camera_zoom: float = Field(default=1.0, ge=0.5, le=2.5)
    siding_color: str = Field(default="#1a2438")
    trim_color: str = Field(default="#334768")
    roof_color: str = Field(default="#111827")
    sections: List[ArchSection] = Field(default_factory=list)


ARCHITECTURE_PRESETS: List[Dict[str, Any]] = [
    {
        "id": "a_frame_gable",
        "preset_style": "a_frame_gable",
        "name": "My House: Front A-Frame Triangle Peak",
        "label": "My House: Front A-Frame Triangle Peak",
        "description": "Prominent triangular gable roofline across the front elevation with picture window and entry door.",
        "default_view_mode": "3d",
        "camera_yaw": -24.0,
        "camera_pitch": 18.0,
        "camera_zoom": 1.0,
        "siding_color": "#1a2438",
        "trim_color": "#334768",
        "roof_color": "#111827",
        "sections": [
            {
                "id": "sec-main-gable",
                "label": "Front A-Frame Triangle Peak",
                "shape": "triangle_gable",
                "wall": "front",
                "story": 1,
                "x_start": 0.06,
                "x_end": 0.94,
                "eave_height": 0.50,
                "peak_height": 0.90,
                "peak_offset": 0.50,
                "depth_offset": 0.08,
                "has_garage": False,
                "has_door": True,
                "window_style": "picture",
            }
        ],
    },
    {
        "id": "craftsman_multi_section",
        "preset_style": "craftsman_multi_section",
        "name": "Neighbor 1: Craftsman Garage Square + Double Gable + Sides",
        "label": "Neighbor 1: Craftsman Garage Square + Double Gable + Sides",
        "description": "Craftsman multi-section home with flat-eave garage box, front entry triangle gable, upper dormer peak, and side/rear eaves.",
        "default_view_mode": "3d",
        "camera_yaw": -28.0,
        "camera_pitch": 21.0,
        "camera_zoom": 1.0,
        "siding_color": "#1e293b",
        "trim_color": "#3b5278",
        "roof_color": "#0f172a",
        "sections": [
            {
                "id": "sec-garage-square",
                "label": "Garage Square Flat Eave",
                "shape": "flat_eave",
                "wall": "front",
                "story": 1,
                "x_start": 0.04,
                "x_end": 0.44,
                "eave_height": 0.48,
                "peak_height": 0.48,
                "peak_offset": 0.50,
                "depth_offset": 0.16,
                "has_garage": True,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-entry-gable",
                "label": "Front Entry Gable",
                "shape": "triangle_gable",
                "wall": "front",
                "story": 1,
                "x_start": 0.44,
                "x_end": 0.96,
                "eave_height": 0.52,
                "peak_height": 0.84,
                "peak_offset": 0.52,
                "depth_offset": 0.06,
                "has_garage": False,
                "has_door": True,
                "window_style": "double_hung",
            },
            {
                "id": "sec-upper-dormer",
                "label": "Upper Story Dormer Peak",
                "shape": "dormer_peak",
                "wall": "front",
                "story": 2,
                "x_start": 0.14,
                "x_end": 0.68,
                "eave_height": 0.68,
                "peak_height": 0.95,
                "peak_offset": 0.50,
                "depth_offset": -0.06,
                "has_garage": False,
                "has_door": False,
                "window_style": "arched",
            },
            {
                "id": "sec-left-eave",
                "label": "Left Side Eave",
                "shape": "flat_eave",
                "wall": "left",
                "story": 1,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.50,
                "peak_height": 0.50,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-right-eave",
                "label": "Right Side Eave",
                "shape": "flat_eave",
                "wall": "right",
                "story": 1,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.52,
                "peak_height": 0.52,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-back-eave",
                "label": "Rear Hip Roof Eave",
                "shape": "hip_roof",
                "wall": "back",
                "story": 1,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.50,
                "peak_height": 0.72,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "modern_grid",
            },
        ],
    },
    {
        "id": "two_story_estate",
        "preset_style": "two_story_estate",
        "name": "Neighbor 2: 2-Story Compound Peaks + Flat Fascia + All Sides",
        "label": "Neighbor 2: 2-Story Compound Peaks + Flat Fascia + All Sides",
        "description": "Two-story estate with steep left tower gable, center flat fascia, right garage gable, and full perimeter wings.",
        "default_view_mode": "3d",
        "camera_yaw": -30.0,
        "camera_pitch": 22.0,
        "camera_zoom": 1.0,
        "siding_color": "#172033",
        "trim_color": "#385076",
        "roof_color": "#0d1322",
        "sections": [
            {
                "id": "sec-left-tower-gable",
                "label": "Left 2-Story Tower Steep Gable",
                "shape": "steep_gable",
                "wall": "front",
                "story": 2,
                "x_start": 0.03,
                "x_end": 0.38,
                "eave_height": 0.60,
                "peak_height": 0.96,
                "peak_offset": 0.50,
                "depth_offset": 0.14,
                "has_garage": False,
                "has_door": False,
                "window_style": "arched",
            },
            {
                "id": "sec-center-flat-fascia",
                "label": "Center 2-Story Flat Fascia",
                "shape": "flat_eave",
                "wall": "front",
                "story": 2,
                "x_start": 0.38,
                "x_end": 0.68,
                "eave_height": 0.66,
                "peak_height": 0.66,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": True,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-right-garage-gable",
                "label": "Right Garage Gable",
                "shape": "triangle_gable",
                "wall": "front",
                "story": 1,
                "x_start": 0.68,
                "x_end": 0.97,
                "eave_height": 0.48,
                "peak_height": 0.80,
                "peak_offset": 0.50,
                "depth_offset": 0.18,
                "has_garage": True,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-left-wing",
                "label": "Left Side Wing Eave",
                "shape": "flat_eave",
                "wall": "left",
                "story": 1,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.56,
                "peak_height": 0.56,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-right-wing",
                "label": "Right Side Wing Gable",
                "shape": "triangle_gable",
                "wall": "right",
                "story": 1,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.48,
                "peak_height": 0.76,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-back-wing",
                "label": "Back Wing Flat Eave",
                "shape": "flat_eave",
                "wall": "back",
                "story": 1,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.54,
                "peak_height": 0.54,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "modern_grid",
            },
        ],
    },
    {
        "id": "modern_stepped",
        "preset_style": "modern_stepped",
        "name": "Modern Stepped Boxes + Mono-Slope",
        "label": "Modern Stepped Boxes + Mono-Slope",
        "description": "Contemporary architectural layout with stepped flat-roof garage box and 2-story shed-slope clerestory wing.",
        "default_view_mode": "3d",
        "camera_yaw": -22.0,
        "camera_pitch": 19.0,
        "camera_zoom": 1.0,
        "siding_color": "#182232",
        "trim_color": "#38bdf8",
        "roof_color": "#0b1120",
        "sections": [
            {
                "id": "sec-modern-box",
                "label": "Stepped Garage Flat Box",
                "shape": "flat_eave",
                "wall": "front",
                "story": 1,
                "x_start": 0.04,
                "x_end": 0.46,
                "eave_height": 0.48,
                "peak_height": 0.48,
                "peak_offset": 0.50,
                "depth_offset": 0.15,
                "has_garage": True,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-modern-slope",
                "label": "Upper Mono-Slope Shed Roof",
                "shape": "shed_slope",
                "wall": "front",
                "story": 2,
                "x_start": 0.44,
                "x_end": 0.96,
                "eave_height": 0.58,
                "peak_height": 0.92,
                "peak_offset": 0.85,
                "depth_offset": 0.04,
                "has_garage": False,
                "has_door": True,
                "window_style": "picture",
            },
            {
                "id": "sec-modern-left",
                "label": "Left Flat Fascia",
                "shape": "flat_eave",
                "wall": "left",
                "story": 1,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.48,
                "peak_height": 0.48,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "modern_grid",
            },
            {
                "id": "sec-modern-right",
                "label": "Right Shed Fascia",
                "shape": "shed_slope",
                "wall": "right",
                "story": 2,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.58,
                "peak_height": 0.88,
                "peak_offset": 0.80,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "picture",
            },
        ],
    },
    {
        "id": "colonial_dormer",
        "preset_style": "colonial_dormer",
        "name": "Colonial Twin Dormers + Porch",
        "label": "Colonial Twin Dormers + Porch",
        "description": "Classic symmetric colonial home with full-width porch hip roof and twin upper-story peaked dormers.",
        "default_view_mode": "3d",
        "camera_yaw": -25.0,
        "camera_pitch": 20.0,
        "camera_zoom": 1.0,
        "siding_color": "#1c263b",
        "trim_color": "#475f88",
        "roof_color": "#111827",
        "sections": [
            {
                "id": "sec-colonial-porch",
                "label": "Full-Width Porch Hip Eave",
                "shape": "hip_roof",
                "wall": "front",
                "story": 1,
                "x_start": 0.05,
                "x_end": 0.95,
                "eave_height": 0.48,
                "peak_height": 0.64,
                "peak_offset": 0.50,
                "depth_offset": 0.12,
                "has_garage": False,
                "has_door": True,
                "window_style": "double_hung",
            },
            {
                "id": "sec-colonial-dormer-left",
                "label": "Left Upper Dormer Peak",
                "shape": "dormer_peak",
                "wall": "front",
                "story": 2,
                "x_start": 0.16,
                "x_end": 0.44,
                "eave_height": 0.68,
                "peak_height": 0.92,
                "peak_offset": 0.50,
                "depth_offset": -0.04,
                "has_garage": False,
                "has_door": False,
                "window_style": "arched",
            },
            {
                "id": "sec-colonial-dormer-right",
                "label": "Right Upper Dormer Peak",
                "shape": "dormer_peak",
                "wall": "front",
                "story": 2,
                "x_start": 0.56,
                "x_end": 0.84,
                "eave_height": 0.68,
                "peak_height": 0.92,
                "peak_offset": 0.50,
                "depth_offset": -0.04,
                "has_garage": False,
                "has_door": False,
                "window_style": "arched",
            },
            {
                "id": "sec-colonial-left-gable",
                "label": "Left Side Colonial Gable",
                "shape": "triangle_gable",
                "wall": "left",
                "story": 2,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.56,
                "peak_height": 0.88,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "double_hung",
            },
            {
                "id": "sec-colonial-right-gable",
                "label": "Right Side Colonial Gable",
                "shape": "triangle_gable",
                "wall": "right",
                "story": 2,
                "x_start": 0.0,
                "x_end": 1.0,
                "eave_height": 0.56,
                "peak_height": 0.88,
                "peak_offset": 0.50,
                "depth_offset": 0.0,
                "has_garage": False,
                "has_door": False,
                "window_style": "double_hung",
            },
        ],
    },
]


def default_house_architecture(house_id: str, order: int = 1) -> HouseArchitecture:
    """Return the default 2D/3D HouseArchitecture preset for a house ID or order."""
    hid = (house_id or "").strip().lower()
    preset_by_id = {p["preset_style"]: p for p in ARCHITECTURE_PRESETS}
    if hid in preset_by_id:
        chosen = preset_by_id[hid]
    elif hid == "house-1":
        chosen = preset_by_id["a_frame_gable"]
    elif hid == "house-2":
        chosen = preset_by_id["craftsman_multi_section"]
    elif hid == "house-3":
        chosen = preset_by_id["two_story_estate"]
    elif order == 1:
        chosen = preset_by_id["a_frame_gable"]
    elif order == 2:
        chosen = preset_by_id["craftsman_multi_section"]
    else:
        chosen = preset_by_id["two_story_estate"]

    return HouseArchitecture(
        preset_style=chosen["preset_style"],
        default_view_mode=chosen.get("default_view_mode", "3d"),
        camera_yaw=float(chosen.get("camera_yaw", -26.0)),
        camera_pitch=float(chosen.get("camera_pitch", 20.0)),
        camera_zoom=float(chosen.get("camera_zoom", 1.0)),
        siding_color=str(chosen.get("siding_color", "#1a2438")),
        trim_color=str(chosen.get("trim_color", "#334768")),
        roof_color=str(chosen.get("roof_color", "#111827")),
        sections=[ArchSection.model_validate(s) for s in chosen["sections"]],
    )


def evaluate_arch_section_point(
    section: Optional[ArchSection],
    t: float,
    wall: str = "front",
) -> Tuple[float, float, float]:
    """
    Evaluate 2D/3D normalized coordinates `(arch_x, arch_y, arch_z)` along an `ArchSection`
    at parameter `t` in `[0.0, 1.0]`.
    `arch_y` represents vertical elevation (`eave_height` at eaves up to `peak_height` at roof apex).
    """
    t_clamped = max(0.0, min(1.0, float(t)))
    w = (section.wall if section is not None else wall or "front").strip().lower()
    if section is None:
        arch_x = 0.06 + 0.88 * t_clamped
        arch_y = 0.52
        arch_z = {"front": 0.0, "left": -0.20, "right": 0.20, "back": -0.40}.get(w, 0.0)
        return round(arch_x, 4), round(arch_y, 4), round(arch_z, 4)

    eave = float(section.eave_height)
    peak = max(eave, float(section.peak_height))
    p_off = max(0.10, min(0.90, float(section.peak_offset)))
    shape = section.shape

    if shape in ("triangle_gable", "steep_gable", "dormer_peak"):
        if t_clamped <= p_off:
            u = t_clamped / max(1e-6, p_off)
            arch_y = eave + (peak - eave) * u
        else:
            u = (1.0 - t_clamped) / max(1e-6, 1.0 - p_off)
            arch_y = eave + (peak - eave) * u
    elif shape == "flat_eave":
        arch_y = eave
    elif shape == "hip_roof":
        if t_clamped < 0.25:
            arch_y = eave + (peak - eave) * (t_clamped / 0.25)
        elif t_clamped <= 0.75:
            arch_y = peak
        else:
            arch_y = eave + (peak - eave) * ((1.0 - t_clamped) / 0.25)
    elif shape == "shed_slope":
        if t_clamped <= p_off:
            arch_y = eave + (peak - eave) * (t_clamped / max(1e-6, p_off))
        else:
            arch_y = peak - 0.15 * (peak - eave) * ((t_clamped - p_off) / max(1e-6, 1.0 - p_off))
    else:
        arch_y = eave

    span_x = section.x_start + (section.x_end - section.x_start) * t_clamped
    if w == "front":
        arch_x = span_x
        arch_z = float(section.depth_offset)
    elif w == "back":
        arch_x = span_x
        arch_z = -0.40 + float(section.depth_offset)
    elif w == "left":
        arch_x = 0.04
        arch_z = float(section.depth_offset) - 0.40 * t_clamped
    elif w == "right":
        arch_x = 0.96
        arch_z = float(section.depth_offset) - 0.40 * t_clamped
    else:
        arch_x = span_x
        arch_z = float(section.depth_offset)

    return round(arch_x, 4), round(arch_y, 4), round(arch_z, 4)


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
    wall_zones: List[Dict[str, Any]] = Field(
        default_factory=list,
        description="Ordered 3D house wall spans on this controller, e.g. [{'wall': 'front', 'segments': 8}, {'wall': 'right', 'segments': 7}]",
    )
    section_spans: List[Dict[str, Any]] = Field(
        default_factory=list,
        description="Ordered roofline section assignments for this controller, e.g. [{'section_id': 'sec-main-gable', 'wall': 'front', 'segments': 9, 'direction': 'ltr'}]",
    )
    custom_nodes: List[Dict[str, Any]] = Field(
        default_factory=list,
        description="Optional user-placed 2D/3D polyline vertices [{'x': 0.08, 'y': 0.52, 'z': 0.08, 'wall': 'front', 'label': 'Start'}]",
    )

    def get_segment_walls(self) -> List[str]:
        """Return the wall label ('front', 'left', 'right', 'back') for each segment 0..segment_count-1."""
        walls: List[str] = []
        valid_walls = {"front", "left", "right", "back"}
        source_zones = self.wall_zones if self.wall_zones else self.section_spans
        for item in source_zones or []:
            if not isinstance(item, dict):
                continue
            w = str(item.get("wall", "front")).strip().lower()
            if w not in valid_walls:
                w = "front"
            cnt = max(0, int(item.get("segments", 0) or 0))
            walls.extend([w] * cnt)
        if len(walls) < self.segment_count:
            pad_wall = walls[-1] if walls else "front"
            walls.extend([pad_wall] * (self.segment_count - len(walls)))
        return walls[: self.segment_count]

    def get_segment_sections(self, house_sections: Optional[List[ArchSection]] = None) -> List[Dict[str, Any]]:
        """
        Return for each segment `0..segment_count-1` its assigned `section_id`, `wall`, and
        local `t` (`0.0..1.0` along that section), falling back gracefully to `wall_zones`
        and the house's sections if `section_spans` is empty.
        """
        valid_walls = {"front", "left", "right", "back"}
        sections_list: List[ArchSection] = []
        for s in house_sections or []:
            if isinstance(s, ArchSection):
                sections_list.append(s)
            elif isinstance(s, dict):
                try:
                    sections_list.append(ArchSection.model_validate(s))
                except Exception:
                    pass
        sec_by_id: Dict[str, ArchSection] = {s.id: s for s in sections_list}

        cleaned_spans: List[Dict[str, Any]] = []
        for item in self.section_spans or []:
            if not isinstance(item, dict):
                continue
            cnt = max(0, int(item.get("segments", 0) or 0))
            if cnt <= 0:
                continue
            sec_id = str(item.get("section_id") or "").strip()
            sec_obj = sec_by_id.get(sec_id)
            raw_wall = str(item.get("wall") or (sec_obj.wall if sec_obj else "front")).strip().lower()
            w = raw_wall if raw_wall in valid_walls else (sec_obj.wall if sec_obj else "front")
            if not sec_id:
                wall_matches = [s for s in sections_list if s.wall == w]
                if wall_matches:
                    sec_id = wall_matches[0].id
                elif sections_list:
                    sec_id = sections_list[0].id
                else:
                    sec_id = f"sec-{w}"
            direction = str(item.get("direction") or "ltr").strip().lower()
            cleaned_spans.append(
                {
                    "section_id": sec_id,
                    "wall": w,
                    "segments": cnt,
                    "direction": direction,
                }
            )

        if cleaned_spans:
            total_span_segs = sum(sp["segments"] for sp in cleaned_spans)
            if total_span_segs < self.segment_count:
                cleaned_spans[-1]["segments"] += self.segment_count - total_span_segs

            result: List[Dict[str, Any]] = []
            for sp in cleaned_spans:
                cnt = sp["segments"]
                sec_id = sp["section_id"]
                w = sp["wall"]
                direction = sp["direction"]
                for k in range(cnt):
                    if len(result) >= self.segment_count:
                        break
                    t = 0.5 if cnt == 1 else (k / (cnt - 1))
                    if direction in ("rtl", "reverse", "right_to_left"):
                        t = 1.0 - t
                    result.append(
                        {
                            "segment_index": len(result),
                            "section_id": sec_id,
                            "wall": w,
                            "t": round(t, 5),
                            "direction": direction,
                        }
                    )
                if len(result) >= self.segment_count:
                    break
            return result[: self.segment_count]

        # Fallback to wall_zones + house_sections
        seg_walls = self.get_segment_walls()
        runs: List[Tuple[str, int]] = []
        for w in seg_walls:
            if runs and runs[-1][0] == w:
                runs[-1] = (w, runs[-1][1] + 1)
            else:
                runs.append((w, 1))

        fallback_result: List[Dict[str, Any]] = []
        for w, run_len in runs:
            matching_secs = [s for s in sections_list if s.wall == w]
            if not matching_secs and sections_list:
                matching_secs = [sections_list[0]]
            if not matching_secs:
                for k in range(run_len):
                    t = 0.5 if run_len == 1 else (k / (run_len - 1))
                    fallback_result.append(
                        {
                            "segment_index": len(fallback_result),
                            "section_id": f"sec-{w}",
                            "wall": w,
                            "t": round(t, 5),
                            "direction": "ltr",
                        }
                    )
                continue

            if len(matching_secs) == 1:
                sec = matching_secs[0]
                for k in range(run_len):
                    t = 0.5 if run_len == 1 else (k / (run_len - 1))
                    fallback_result.append(
                        {
                            "segment_index": len(fallback_result),
                            "section_id": sec.id,
                            "wall": w,
                            "t": round(t, 5),
                            "direction": "ltr",
                        }
                    )
            else:
                # Partition run_len segments across matching_secs
                m = len(matching_secs)
                for k in range(run_len):
                    sec_idx = min(m - 1, int((k * m) / max(1, run_len)))
                    # Range of k that maps to sec_idx
                    k_In_sec = [ idx for idx in range(run_len) if min(m - 1, int((idx * m) / max(1, run_len))) == sec_idx ]
                    local_idx = k_In_sec.index(k)
                    local_cnt = len(k_In_sec)
                    local_t = 0.5 if local_cnt == 1 else (local_idx / (local_cnt - 1))
                    sec = matching_secs[sec_idx]
                    fallback_result.append(
                        {
                            "segment_index": len(fallback_result),
                            "section_id": sec.id,
                            "wall": w,
                            "t": round(local_t, 5),
                            "direction": "ltr",
                        }
                    )

        return fallback_result[: self.segment_count]

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
    architecture: Optional[HouseArchitecture] = Field(
        default=None,
        description="2D/3D architectural roofline & wall sections for this house",
    )
    controllers: List[ControllerConfig] = Field(default_factory=list, description="Controllers installed on this house")

    @model_validator(mode="after")
    def _ensure_default_architecture(self) -> "HouseConfig":
        if self.architecture is None or not self.architecture.sections:
            default_arch = default_house_architecture(self.id, self.order)
            if self.architecture is not None:
                preset_match = next(
                    (p for p in ARCHITECTURE_PRESETS if p["preset_style"] == self.architecture.preset_style),
                    None,
                )
                if preset_match:
                    self.architecture.sections = [ArchSection.model_validate(s) for s in preset_match["sections"]]
                else:
                    self.architecture.sections = default_arch.sections
            else:
                self.architecture = default_arch
        return self

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
    zone_mode: Literal[
        "all_segments",
        "front_street_sync",
        "depth_front_to_back",
        "perimeter_360",
        "front_only_quiet_sides",
    ] = Field(
        default="all_segments",
        description="How Front vs Left/Right/Back house walls are mapped in 3D space",
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
    wall: str = "front"
    section_id: str = ""
    arch_x: float = 0.5
    arch_y: float = 0.5
    arch_z: float = 0.0
    normalized_pos: float
    normalized_width: float
    r: int
    g: int
    b: int
    hex_color: str
