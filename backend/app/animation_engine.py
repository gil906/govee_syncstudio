from __future__ import annotations

import asyncio
import colorsys
import datetime as dt
import logging
import math
import time
from typing import Any, Callable, Coroutine, Dict, List, Optional, Tuple
from zoneinfo import ZoneInfo

from .config_store import ConfigStore
from .govee_protocol import GoveeProtocolDriver, RGBTuple, compute_representative_controller_color
from .models import (
    AnimationConfig,
    ControllerConfig,
    DirectionMode,
    EffectType,
    HouseConfig,
    ScheduleConfig,
    SegmentRenderPoint,
    SpatialMappingMode,
    SystemConfig,
)

logger = logging.getLogger("govee_sync.engine")


def compute_schedule_status(
    sched: ScheduleConfig,
    last_triggered_action: str = "",
    now_dt: Optional[dt.datetime] = None,
) -> Dict[str, Any]:
    """
    Compute live schedule telemetry in the configured IANA timezone (`sched.timezone`,
    fallback `America/Los_Angeles`), including automatic Daylight Saving Time (DST) detection,
    active day-of-week check, and `[start_time, stop_time)` window evaluation (supporting
    both same-day and overnight windows where `start_time > stop_time`).
    """
    tz_name = (sched.timezone or "America/Los_Angeles").strip() or "America/Los_Angeles"
    try:
        tz = ZoneInfo(tz_name)
    except Exception:
        tz_name = "America/Los_Angeles"
        tz = ZoneInfo(tz_name)

    if now_dt is None:
        now_local = dt.datetime.now(tz)
    elif now_dt.tzinfo is None:
        now_local = now_dt.replace(tzinfo=tz)
    else:
        now_local = now_dt.astimezone(tz)

    dst_offset = now_local.dst()
    dst_active = bool(dst_offset and dst_offset.total_seconds() != 0)
    tz_abbrev = now_local.tzname() or tz_name
    utc_offset_str = now_local.strftime("%z")
    formatted_utc_offset = (
        f"{utc_offset_str[:3]}:{utc_offset_str[3:]}"
        if len(utc_offset_str) == 5
        else utc_offset_str
    )

    weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    today_day = weekdays[now_local.weekday()]
    yesterday_day = weekdays[(now_local.weekday() - 1) % 7]
    active_days = [str(d).strip().lower()[:3] for d in (sched.days_of_week or []) if str(d).strip()]
    if not active_days:
        active_days = list(weekdays)

    now_hhmm = now_local.strftime("%H:%M")
    start_hhmm = (sched.start_time or "17:30").strip()
    stop_hhmm = (sched.stop_time or "23:00").strip()

    if start_hhmm <= stop_hhmm:
        is_active_window = bool((today_day in active_days) and (start_hhmm <= now_hhmm < stop_hhmm))
    else:
        # Overnight window (e.g. 17:30 -> 01:00)
        if now_hhmm >= start_hhmm:
            is_active_window = today_day in active_days
        elif now_hhmm < stop_hhmm:
            is_active_window = (yesterday_day in active_days) or (today_day in active_days)
        else:
            is_active_window = False

    return {
        "enabled": sched.enabled,
        "start_time": sched.start_time,
        "stop_time": sched.stop_time,
        "preset_id": sched.preset_id,
        "timezone": tz_name,
        "days_of_week": sched.days_of_week,
        "turn_off_lights_on_stop": sched.turn_off_lights_on_stop,
        "override_govee_app_schedules": getattr(sched, "override_govee_app_schedules", False),
        "current_local_time": now_local.strftime("%I:%M:%S %p"),
        "current_local_hhmm": now_hhmm,
        "tz_abbrev": tz_abbrev,
        "dst_active": dst_active,
        "utc_offset": formatted_utc_offset,
        "is_within_active_window": is_active_window,
        "autonomous_container_daemon": True,
        "last_triggered_action": last_triggered_action,
    }


def hex_to_rgb(hex_str: str) -> RGBTuple:
    s = (hex_str or "#000000").strip().lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    if len(s) != 6:
        return (0, 245, 212)
    try:
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16))
    except ValueError:
        return (0, 245, 212)


def rgb_to_hex(rgb: RGBTuple) -> str:
    r, g, b = rgb
    return f"#{max(0, min(255, r)):02x}{max(0, min(255, g)):02x}{max(0, min(255, b)):02x}"


def lerp_rgb(c1: RGBTuple, c2: RGBTuple, t: float) -> RGBTuple:
    t_clamped = max(0.0, min(1.0, t))
    return (
        round(c1[0] + (c2[0] - c1[0]) * t_clamped),
        round(c1[1] + (c2[1] - c1[1]) * t_clamped),
        round(c1[2] + (c2[2] - c1[2]) * t_clamped),
    )


def scale_rgb(c: RGBTuple, factor: float) -> RGBTuple:
    f = max(0.0, min(1.0, factor))
    return (
        max(0, min(255, round(c[0] * f))),
        max(0, min(255, round(c[1] * f))),
        max(0, min(255, round(c[2] * f))),
    )


def add_rgb(c1: RGBTuple, c2: RGBTuple) -> RGBTuple:
    return (
        max(0, min(255, c1[0] + c2[0])),
        max(0, min(255, c1[1] + c2[1])),
        max(0, min(255, c1[2] + c2[2])),
    )


def deterministic_hash(n: int) -> float:
    """Fast deterministic pseudo-random float in [0, 1) for lockstep sparkle/fire effects."""
    n = (n << 13) ^ n
    nn = (n * (n * n * 15731 + 789221) + 1376312589) & 0x7FFFFFFF
    return nn / 2147483647.0


def value_noise_1d(x: float) -> float:
    i = math.floor(x)
    f = x - i
    u = f * f * (3.0 - 2.0 * f)
    a = deterministic_hash(i)
    b = deterministic_hash(i + 1)
    return a + (b - a) * u


class VirtualSegmentSlot:
    """Precomputed normalized coordinate slot for a single physical segment on a controller."""

    __slots__ = (
        "global_index",
        "house",
        "house_index",
        "controller",
        "controller_index",
        "segment_index",
        "wall",
        "normalized_pos",
        "normalized_width",
        "house_local_pos",
    )

    def __init__(
        self,
        global_index: int,
        house: HouseConfig,
        house_index: int,
        controller: ControllerConfig,
        controller_index: int,
        segment_index: int,
        normalized_pos: float,
        normalized_width: float,
        house_local_pos: float,
        wall: str = "front",
    ) -> None:
        self.global_index = global_index
        self.house = house
        self.house_index = house_index
        self.controller = controller
        self.controller_index = controller_index
        self.segment_index = segment_index
        self.wall = wall
        self.normalized_pos = normalized_pos
        self.normalized_width = normalized_width
        self.house_local_pos = house_local_pos


def build_virtual_strip_map(config: SystemConfig) -> List[VirtualSegmentSlot]:
    """
    Construct the continuous coordinate mapping across all enabled houses and controllers.
    Compensates in real time for houses having different numbers of controllers, segments,
    and 3D house wall zones (`front`, `left`, `right`, `back`).
    """
    active_houses: List[Tuple[HouseConfig, List[ControllerConfig]]] = []
    sorted_houses = sorted(config.houses, key=lambda h: (h.order, h.id))

    for house in sorted_houses:
        if not house.enabled:
            continue
        ctrls = [c for c in house.controllers if c.enabled and c.segment_count > 0]
        if ctrls:
            active_houses.append((house, ctrls))

    if not active_houses:
        return []

    mode = config.animation.mapping_mode
    zone_mode = getattr(config.animation, "zone_mode", "all_segments") or "all_segments"
    total_segments_all = sum(sum(c.segment_count for c in ctrls) for _, ctrls in active_houses)
    total_house_weight = sum(max(0.1, h.time_weight) for h, _ in active_houses)

    slots: List[VirtualSegmentSlot] = []
    global_idx = 0
    cumulative_house_weight = 0.0

    for h_idx, (house, ctrls) in enumerate(active_houses):
        house_seg_total = sum(c.segment_count for c in ctrls)
        h_weight = max(0.1, house.time_weight)
        house_start_norm = cumulative_house_weight / total_house_weight
        house_span_norm = h_weight / total_house_weight
        cumulative_house_weight += h_weight

        # Collect all segments for this house along with their 3D wall zone ('front', 'left', 'right', 'back')
        house_seg_items: List[Tuple[int, ControllerConfig, int, str]] = []
        for c_idx, ctrl in enumerate(ctrls):
            seg_walls = ctrl.get_segment_walls()
            seg_indices = list(range(ctrl.segment_count))
            if ctrl.reversed:
                seg_indices.reverse()
            for phys_seg_idx in seg_indices:
                w_label = seg_walls[phys_seg_idx] if phys_seg_idx < len(seg_walls) else "front"
                house_seg_items.append((c_idx, ctrl, phys_seg_idx, w_label))

        front_total = sum(1 for _, _, _, w in house_seg_items if w == "front")
        front_seen = 0
        side_seen = 0
        side_total = sum(1 for _, _, _, w in house_seg_items if w in ("left", "right"))
        back_seen = 0
        back_total = sum(1 for _, _, _, w in house_seg_items if w == "back")

        for house_seg_cursor, (c_idx, ctrl, phys_seg_idx, w_label) in enumerate(house_seg_items):
            if zone_mode in ("front_street_sync", "front_only_quiet_sides") and front_total > 0:
                if w_label == "front":
                    house_local_pos = (front_seen + 0.5) / max(1, front_total)
                    house_local_width = 1.0 / max(1, front_total)
                    front_seen += 1
                elif w_label == "left":
                    # Echo outward from left-front corner (0.0 -> 0.35 of house span)
                    side_u = (side_seen + 0.5) / max(1, side_total)
                    house_local_pos = max(0.0, min(1.0, 0.35 * side_u))
                    house_local_width = 1.0 / max(1, house_seg_total)
                    side_seen += 1
                elif w_label == "right":
                    # Echo outward from right-front corner (1.0 -> 0.65 of house span)
                    side_u = (side_seen + 0.5) / max(1, side_total)
                    house_local_pos = max(0.0, min(1.0, 1.0 - 0.35 * side_u))
                    house_local_width = 1.0 / max(1, house_seg_total)
                    side_seen += 1
                else:
                    # Back wall echoes center of house
                    back_u = (back_seen + 0.5) / max(1, back_total)
                    house_local_pos = 0.25 + 0.50 * back_u
                    house_local_width = 1.0 / max(1, house_seg_total)
                    back_seen += 1
            elif zone_mode == "depth_front_to_back":
                # 3D Street-to-Backyard Depth Wave: Front (0.0..0.33) -> Left/Right Sides (0.33..0.67) -> Back (0.67..1.0)
                if w_label == "front":
                    u = (front_seen + 0.5) / max(1, front_total)
                    front_seen += 1
                    house_local_pos = 0.33 * u
                elif w_label in ("left", "right"):
                    u = (side_seen + 0.5) / max(1, side_total)
                    side_seen += 1
                    house_local_pos = 0.33 + 0.34 * u
                else:
                    u = (back_seen + 0.5) / max(1, back_total)
                    back_seen += 1
                    house_local_pos = 0.67 + 0.33 * u
                house_local_width = 1.0 / max(1, house_seg_total)
            elif zone_mode == "perimeter_360":
                # 360° Clockwise Rooftop Orbit: Front (0..0.25) -> Right (0.25..0.50) -> Back (0.50..0.75) -> Left (0.75..1.0)
                wall_base = {"front": 0.0, "right": 0.25, "back": 0.50, "left": 0.75}.get(w_label, 0.0)
                u = (house_seg_cursor + 0.5) / max(1, house_seg_total)
                house_local_pos = (wall_base + 0.25 * u) % 1.0
                house_local_width = 1.0 / max(1, house_seg_total)
            else:
                house_local_pos = (house_seg_cursor + 0.5) / max(1, house_seg_total)
                house_local_width = 1.0 / max(1, house_seg_total)

            if zone_mode == "depth_front_to_back":
                norm_pos = house_local_pos
                norm_width = house_local_width
            elif mode == SpatialMappingMode.HOUSE_NORMALIZED:
                norm_pos = house_start_norm + house_local_pos * house_span_norm
                norm_width = house_span_norm * house_local_width
            elif mode == SpatialMappingMode.PARALLEL_ZONES:
                norm_pos = house_local_pos
                norm_width = house_local_width
            else:
                norm_pos = (global_idx + 0.5) / max(1, total_segments_all)
                norm_width = 1.0 / max(1, total_segments_all)

            slots.append(
                VirtualSegmentSlot(
                    global_index=global_idx,
                    house=house,
                    house_index=h_idx,
                    controller=ctrl,
                    controller_index=c_idx,
                    segment_index=phys_seg_idx,
                    normalized_pos=norm_pos,
                    normalized_width=norm_width,
                    house_local_pos=house_local_pos,
                    wall=w_label,
                )
            )
            global_idx += 1

    return slots


def evaluate_effect_at_point(
    x: float,
    unwrapped_phase: float,
    elapsed_sec: float,
    anim: AnimationConfig,
    primary: RGBTuple,
    secondary: RGBTuple,
    accent: RGBTuple,
    bg_scaled: RGBTuple,
) -> RGBTuple:
    """
    Pure analytical shader evaluating the RGB color at normalized position x in [0, 1)
    and master clock phase `unwrapped_phase`. Zero state accumulation -> zero drift.
    """
    effect = anim.effect
    pulses = max(1, anim.pulse_count)
    tail = max(0.03, min(0.85, anim.tail_length))

    # Resolve travel phase in [0, 1) according to direction mode
    if anim.direction == DirectionMode.PINGPONG:
        cycle = unwrapped_phase % 2.0
        head_pos = cycle if cycle <= 1.0 else (2.0 - cycle)
        reverse_flow = cycle > 1.0
    elif anim.direction == DirectionMode.REVERSE:
        head_pos = (-unwrapped_phase) % 1.0
        reverse_flow = True
    else:
        head_pos = unwrapped_phase % 1.0
        reverse_flow = False

    if effect == EffectType.MULTI_HOUSE_CHASE:
        # Smooth multi-house chase: anti-aliased glowing head + smooth exponential/cosine tail
        # flowing continuously from House 1 -> House 2 -> House 3
        best_intensity = 0.0
        best_color = primary
        for p in range(pulses):
            p_head = (head_pos + p / pulses) % 1.0
            # Signed distance behind the chase head along travel direction
            if not reverse_flow:
                dist_behind = (p_head - x) % 1.0
                dist_ahead = (x - p_head) % 1.0
            else:
                dist_behind = (x - p_head) % 1.0
                dist_ahead = (p_head - x) % 1.0

            # Soft leading glow + smooth trailing tail
            lead_width = max(0.02, tail * 0.18)
            if dist_ahead <= lead_width:
                u = 1.0 - (dist_ahead / lead_width)
                energy = (u * u) * (3.0 - 2.0 * u)
                col = lerp_rgb(primary, (255, 255, 255), 0.35 * energy)
            elif dist_behind <= tail:
                t_norm = dist_behind / tail
                # Raised cosine + power decay for silky tail across house boundaries
                energy = math.pow(0.5 * (1.0 + math.cos(math.pi * t_norm)), 1.35)
                if t_norm < 0.45:
                    col = lerp_rgb(primary, secondary, t_norm / 0.45)
                else:
                    col = lerp_rgb(secondary, accent, (t_norm - 0.45) / 0.55)
            else:
                energy = 0.0
                col = primary

            if energy > best_intensity:
                best_intensity = energy
                best_color = col

        return add_rgb(bg_scaled, scale_rgb(best_color, best_intensity))

    if effect == EffectType.RAINBOW_WAVE:
        dir_sign = -1.0 if reverse_flow else 1.0
        hue = (x * pulses - dir_sign * unwrapped_phase) % 1.0
        r, g, b = colorsys.hsv_to_rgb(hue, 0.92, 1.0)
        return (round(r * 255), round(g * 255), round(b * 255))

    if effect == EffectType.COMET_METEOR:
        best_rgb = bg_scaled
        for p in range(pulses):
            p_head = (head_pos + p / pulses) % 1.0
            dist_behind = ((p_head - x) % 1.0) if not reverse_flow else ((x - p_head) % 1.0)
            dist_ahead = ((x - p_head) % 1.0) if not reverse_flow else ((p_head - x) % 1.0)

            core_w = max(0.015, tail * 0.12)
            if dist_ahead <= core_w:
                u = 1.0 - dist_ahead / core_w
                core_col = lerp_rgb(primary, (255, 255, 255), 0.75 * u)
                best_rgb = add_rgb(best_rgb, scale_rgb(core_col, u * u))
            elif dist_behind <= tail:
                t_norm = dist_behind / tail
                decay = math.exp(-3.2 * t_norm) * (1.0 - t_norm)
                # Subtle meteor tail shimmer
                shimmer = 0.78 + 0.22 * math.sin(elapsed_sec * 28.0 + x * 65.0)
                tail_col = lerp_rgb(primary, accent if t_norm > 0.5 else secondary, t_norm)
                best_rgb = add_rgb(best_rgb, scale_rgb(tail_col, decay * shimmer))
        return best_rgb

    if effect == EffectType.BREATHING_PULSE:
        # Synchronized harmonic breathing across all houses with gentle spatial wave & shimmer
        dir_sign = -1.0 if reverse_flow else 1.0
        wave = 0.5 * (1.0 + math.sin(2.0 * math.pi * (unwrapped_phase - dir_sign * x * 0.35) - math.pi / 2.0))
        breath = math.pow(wave, 1.5)
        color_mix = 0.5 * (1.0 + math.sin(2.0 * math.pi * unwrapped_phase + x * math.pi * 1.25))
        base_col = lerp_rgb(primary, secondary, color_mix)
        accent_glow = 0.5 * (1.0 + math.cos(2.0 * math.pi * (x * max(1, pulses) - dir_sign * unwrapped_phase)))
        blended_col = lerp_rgb(base_col, accent, 0.22 * accent_glow)
        return add_rgb(bg_scaled, scale_rgb(blended_col, 0.10 + 0.90 * breath))

    if effect == EffectType.COLOR_WIPE:
        # Continuous 3-stage color wipe across all houses (Primary -> Secondary -> Accent)
        palette = [primary, secondary, accent]
        stage = int(math.floor(unwrapped_phase)) % len(palette)
        prev_col = palette[(stage - 1) % len(palette)]
        curr_col = palette[stage]
        prog = unwrapped_phase % 1.0
        pos = (1.0 - x) if reverse_flow else x
        edge_softness = 0.025
        if pos < prog - edge_softness:
            return curr_col
        if pos > prog + edge_softness:
            return prev_col
        blend = 1.0 - ((pos - (prog - edge_softness)) / (2.0 * edge_softness))
        return lerp_rgb(prev_col, curr_col, blend)

    if effect == EffectType.THEATER_CHASE:
        # Classic marquee theater chase scaled to normalized virtual strip coordinates
        total_slots = max(18, pulses * 24)
        dir_sign = -1.0 if reverse_flow else 1.0
        virtual_slot = (x * total_slots - dir_sign * unwrapped_phase * total_slots) % 3.0
        # Smooth slot window so uneven segment counts don't alias harshly
        dist_from_slot_center = min(abs(virtual_slot - 0.5), abs(virtual_slot - 3.5))
        if dist_from_slot_center < 0.55:
            strength = math.cos((dist_from_slot_center / 0.55) * (math.pi / 2.0))
            col = primary if (int(x * total_slots) % 2 == 0) else secondary
            return add_rgb(bg_scaled, scale_rgb(col, strength))
        return bg_scaled

    if effect == EffectType.FIRE_SPARKLE:
        # Continuous roaring fire + rising embers across houses
        n1 = value_noise_1d(x * 18.0 - elapsed_sec * (3.5 + anim.speed * 4.0))
        n2 = value_noise_1d(x * 37.0 + elapsed_sec * 7.2)
        heat = max(0.0, min(1.0, 0.62 * n1 + 0.38 * n2))
        if heat < 0.35:
            col = lerp_rgb((20, 2, 0), (190, 25, 0), heat / 0.35)
        elif heat < 0.72:
            col = lerp_rgb((190, 25, 0), (255, 135, 0), (heat - 0.35) / 0.37)
        else:
            col = lerp_rgb((255, 135, 0), (255, 240, 160), (heat - 0.72) / 0.28)
        return col

    if effect == EffectType.SPARKLE_TWINKLE:
        # Synchronized starlight sparkle over moving aurora wave
        aurora_phase = 0.5 * (1.0 + math.sin(2.0 * math.pi * (x * pulses - unwrapped_phase)))
        aurora_col = lerp_rgb(primary, secondary, aurora_phase)
        base = add_rgb(bg_scaled, scale_rgb(aurora_col, 0.35))
        cell = int(x * 60.0)
        tick = int(elapsed_sec * (4.0 + anim.speed * 8.0))
        rnd = deterministic_hash(cell * 997 + tick * 131)
        if rnd > 0.84:
            sub = (elapsed_sec * (4.0 + anim.speed * 8.0)) % 1.0
            twinkle = math.sin(sub * math.pi)
            spark_col = lerp_rgb(accent, (255, 255, 255), 0.65)
            return add_rgb(base, scale_rgb(spark_col, twinkle))
        return base

    if effect == EffectType.HALLOWEEN_SPOOKY:
        # Halloween Phantom & Lightning Chase:
        # Toxic green / haunted violet / pumpkin orange phantom orbs traveling House 1 -> 2 -> 3
        # with eerie ghostly mist and periodic rooftop lightning flashes.
        mist_wave = 0.5 * (1.0 + math.sin(2.0 * math.pi * (x * 2.0 - unwrapped_phase * 0.5)))
        mist_col = lerp_rgb(primary, secondary, mist_wave)
        base_rgb = add_rgb(bg_scaled, scale_rgb(mist_col, 0.16))

        palette = [primary, secondary, accent]
        for p in range(pulses):
            p_head = (head_pos + p / pulses) % 1.0
            dist_behind = ((p_head - x) % 1.0) if not reverse_flow else ((x - p_head) % 1.0)
            dist_ahead = ((x - p_head) % 1.0) if not reverse_flow else ((p_head - x) % 1.0)
            orb_col = palette[p % len(palette)]
            next_col = palette[(p + 1) % len(palette)]

            lead_w = max(0.02, tail * 0.20)
            if dist_ahead <= lead_w:
                u = 1.0 - (dist_ahead / lead_w)
                wobble = 0.82 + 0.18 * math.sin(elapsed_sec * 18.0 + x * 40.0)
                core = lerp_rgb(orb_col, accent, 0.45 * u)
                base_rgb = add_rgb(base_rgb, scale_rgb(core, (u * u) * wobble))
            elif dist_behind <= tail:
                t_norm = dist_behind / tail
                decay = math.pow(0.5 * (1.0 + math.cos(math.pi * t_norm)), 1.5)
                flicker = 0.75 + 0.25 * value_noise_1d(x * 28.0 - elapsed_sec * 9.0)
                trail_col = lerp_rgb(orb_col, next_col, t_norm)
                base_rgb = add_rgb(base_rgb, scale_rgb(trail_col, decay * flicker))

        # Periodic eerie lightning strike across rooflines
        strike_slot = int(elapsed_sec * 2.5)
        strike_rnd = deterministic_hash(strike_slot * 313 + int(x * 3.0) * 17)
        if strike_rnd > 0.88:
            sub_t = (elapsed_sec * 2.5) % 1.0
            bolt = math.pow(max(0.0, math.sin(sub_t * math.pi * 3.0)), 2.0) * (1.0 - sub_t)
            lightning_col = lerp_rgb(secondary, (235, 225, 255), 0.7)
            base_rgb = add_rgb(base_rgb, scale_rgb(lightning_col, bolt * 0.95))

        return base_rgb

    if effect == EffectType.CHRISTMAS_MAGIC:
        # Christmas Candy Cane & Sleigh Wave:
        # Crisp rotating red/white/emerald candy-cane ribbons with a sparkling gold sleigh head
        # gliding smoothly from house to house.
        dir_sign = -1.0 if reverse_flow else 1.0
        stripe_freq = max(6.0, pulses * 9.0)
        ribbon_phase = (x * stripe_freq - dir_sign * unwrapped_phase * 2.0) % 1.0
        snow_white: RGBTuple = (255, 250, 245)

        if ribbon_phase < 0.333:
            local_u = ribbon_phase / 0.333
            edge = 0.5 * (1.0 - math.cos(math.pi * min(1.0, local_u * 4.0)))
            cane_col = lerp_rgb(snow_white, primary, edge)
        elif ribbon_phase < 0.666:
            local_u = (ribbon_phase - 0.333) / 0.333
            edge = 0.5 * (1.0 - math.cos(math.pi * min(1.0, local_u * 4.0)))
            cane_col = lerp_rgb(primary, snow_white, edge)
        else:
            local_u = (ribbon_phase - 0.666) / 0.334
            edge = 0.5 * (1.0 - math.cos(math.pi * min(1.0, local_u * 4.0)))
            cane_col = lerp_rgb(snow_white, secondary, edge)

        base_rgb = add_rgb(bg_scaled, scale_rgb(cane_col, 0.52))

        # Sparkling gold sleigh head + magic dust wake gliding across all 3 houses
        sleigh_head = head_pos
        dist_behind = ((sleigh_head - x) % 1.0) if not reverse_flow else ((x - sleigh_head) % 1.0)
        dist_ahead = ((x - sleigh_head) % 1.0) if not reverse_flow else ((sleigh_head - x) % 1.0)
        head_w = max(0.025, tail * 0.22)
        if dist_ahead <= head_w:
            u = 1.0 - (dist_ahead / head_w)
            sleigh_col = lerp_rgb(accent, (255, 255, 255), 0.65 * u)
            base_rgb = add_rgb(base_rgb, scale_rgb(sleigh_col, u * u))
        elif dist_behind <= tail:
            t_norm = dist_behind / tail
            wake = math.exp(-2.6 * t_norm) * (1.0 - t_norm)
            sparkle = 0.65 + 0.35 * math.sin(elapsed_sec * 32.0 + x * 90.0)
            wake_col = lerp_rgb(accent, snow_white, 0.35 * (1.0 - t_norm))
            base_rgb = add_rgb(base_rgb, scale_rgb(wake_col, wake * sparkle))

        return base_rgb

    if effect == EffectType.DIWALI_FESTIVAL:
        # Diwali Diya & Rangoli Cascade:
        # Warm golden saffron, marigold, royal magenta, and turquoise rangoli waves
        # with flickering oil-lamp (diya) shimmer flowing across all 3 houses.
        dir_sign = -1.0 if reverse_flow else 1.0
        rangoli_u = (x * max(1, pulses) * 1.5 - dir_sign * unwrapped_phase) % 1.0
        if rangoli_u < 0.333:
            rangoli_col = lerp_rgb(primary, secondary, rangoli_u / 0.333)
        elif rangoli_u < 0.666:
            rangoli_col = lerp_rgb(secondary, accent, (rangoli_u - 0.333) / 0.333)
        else:
            rangoli_col = lerp_rgb(accent, primary, (rangoli_u - 0.666) / 0.334)

        # Diya oil-lamp warm flame flicker nodes along each house
        lamp_density = 18.0
        lamp_pos = (x * lamp_density) % 1.0
        lamp_arch = math.pow(math.sin(math.pi * lamp_pos), 1.8)
        flicker_1 = value_noise_1d(x * 32.0 + elapsed_sec * 8.5)
        flicker_2 = value_noise_1d(x * 64.0 - elapsed_sec * 13.0)
        flame_flicker = 0.58 + 0.42 * (0.65 * flicker_1 + 0.35 * flicker_2)

        diya_gold = lerp_rgb(primary, (255, 242, 175), 0.55 * lamp_arch * flame_flicker)
        combined = lerp_rgb(rangoli_col, diya_gold, 0.55 * lamp_arch)
        return add_rgb(bg_scaled, scale_rgb(combined, 0.35 + 0.65 * flame_flicker))

    if effect == EffectType.CENTER_OUT_SHOCKWAVE:
        # Center-Out Shockwave (From My Middle House #2 at x=0.50 -> Both Neighbors Simultaneously!):
        # Symmetrical dual wave originating at x = 0.50 and expanding outward left to Neighbor 1
        # and right to Neighbor 2 in exact lockstep.
        radial_dist = abs(x - 0.50) * 2.0  # 0.0 at center of My House (x=0.50), 1.0 at street outer edges
        best_intensity = 0.0
        best_color = primary

        for p in range(pulses):
            ring_pos = (head_pos + p / pulses) % 1.0
            if not reverse_flow:
                dist_behind = (ring_pos - radial_dist) % 1.0
                dist_ahead = (radial_dist - ring_pos) % 1.0
            else:
                dist_behind = (radial_dist - ring_pos) % 1.0
                dist_ahead = (ring_pos - radial_dist) % 1.0

            lead_w = max(0.025, tail * 0.22)
            if dist_ahead <= lead_w:
                u = 1.0 - (dist_ahead / lead_w)
                energy = (u * u) * (3.0 - 2.0 * u)
                col = lerp_rgb(primary, (255, 255, 255), 0.45 * energy)
            elif dist_behind <= tail:
                t_norm = dist_behind / tail
                energy = math.pow(0.5 * (1.0 + math.cos(math.pi * t_norm)), 1.3)
                if t_norm < 0.5:
                    col = lerp_rgb(primary, secondary, t_norm / 0.5)
                else:
                    col = lerp_rgb(secondary, accent, (t_norm - 0.5) / 0.5)
            else:
                energy = 0.0
                col = primary

            if energy > best_intensity:
                best_intensity = energy
                best_color = col

        # Heartbeat core glow at the center of My House (x = 0.50)
        core_proximity = max(0.0, 1.0 - (radial_dist / 0.18))
        core_pulse = 0.45 + 0.55 * (0.5 * (1.0 + math.cos(2.0 * math.pi * head_pos)))
        core_rgb = scale_rgb(lerp_rgb(primary, accent, 0.35), core_proximity * core_pulse * 0.55)

        return add_rgb(add_rgb(bg_scaled, core_rgb), scale_rgb(best_color, best_intensity))

    if effect == EffectType.LIGHTNING_STORM:
        # Rolling Thunder & Chain Lightning:
        # Deep storm clouds with high-velocity electric chain lightning bolts jumping House 1 -> 2 -> 3.
        cloud_n = value_noise_1d(x * 10.0 - elapsed_sec * 1.4)
        cloud_col = lerp_rgb(bg_scaled, secondary, 0.35 * cloud_n)
        rgb_out = add_rgb(bg_scaled, scale_rgb(cloud_col, 0.55))

        # High-velocity chain lightning bolt jumping across houses
        for p in range(pulses):
            bolt_pos = (head_pos + p / pulses) % 1.0
            dist = abs(x - bolt_pos)
            dist = min(dist, 1.0 - dist)
            bolt_w = max(0.03, tail * 0.35)
            if dist <= bolt_w:
                u = 1.0 - (dist / bolt_w)
                jagged = 0.65 + 0.35 * deterministic_hash(int(x * 80.0) + int(elapsed_sec * 45.0) * 31)
                energy = math.pow(u, 1.6) * jagged
                bolt_col = lerp_rgb(primary, (235, 250, 255), 0.72 * u)
                rgb_out = add_rgb(rgb_out, scale_rgb(bolt_col, energy))

        # Sequential house-wide sheet lightning flashes
        house_zone = min(2, int(x * 3.0))
        flash_tick = int(elapsed_sec * (3.0 + anim.speed * 4.0))
        flash_hash = deterministic_hash(flash_tick * 199 + house_zone * 53)
        if flash_hash > 0.83:
            sub = (elapsed_sec * (3.0 + anim.speed * 4.0)) % 1.0
            flash_amp = math.pow(max(0.0, math.sin(sub * math.pi * 2.0)), 2.2)
            sheet_col = lerp_rgb(accent, (245, 250, 255), 0.65)
            rgb_out = add_rgb(rgb_out, scale_rgb(sheet_col, flash_amp))

        return rgb_out

    if effect == EffectType.CYBER_SNAKE:
        # Dual Neon Serpent Bounce:
        # Two opposing multi-colored neon snakes weaving through all 3 houses and bursting
        # with bright white sparks when they pass through each other in the middle house.
        s1_head = (unwrapped_phase) % 1.0
        s2_head = (-unwrapped_phase) % 1.0

        rgb_out = bg_scaled
        for p in range(pulses):
            offset = p / pulses
            h1 = (s1_head + offset) % 1.0
            h2 = (s2_head + offset) % 1.0

            # Serpent 1 (forward: primary -> secondary)
            d1_behind = (h1 - x) % 1.0
            d1_ahead = (x - h1) % 1.0
            head_w = max(0.018, tail * 0.16)
            if d1_ahead <= head_w:
                u1 = 1.0 - (d1_ahead / head_w)
                rgb_out = add_rgb(rgb_out, scale_rgb(lerp_rgb(primary, (255, 255, 255), 0.55 * u1), u1 * u1))
            elif d1_behind <= tail:
                t1 = d1_behind / tail
                e1 = math.pow(1.0 - t1, 1.4)
                rgb_out = add_rgb(rgb_out, scale_rgb(lerp_rgb(primary, secondary, t1), e1))

            # Serpent 2 (reverse: accent -> secondary)
            d2_behind = (x - h2) % 1.0
            d2_ahead = (h2 - x) % 1.0
            if d2_ahead <= head_w:
                u2 = 1.0 - (d2_ahead / head_w)
                rgb_out = add_rgb(rgb_out, scale_rgb(lerp_rgb(accent, (255, 255, 255), 0.55 * u2), u2 * u2))
            elif d2_behind <= tail:
                t2 = d2_behind / tail
                e2 = math.pow(1.0 - t2, 1.4)
                rgb_out = add_rgb(rgb_out, scale_rgb(lerp_rgb(accent, secondary, t2), e2))

            # Collision spark burst when serpents cross each other (especially in middle house x ~ 0.50)
            head_sep = abs(h1 - h2)
            head_sep = min(head_sep, 1.0 - head_sep)
            if head_sep < 0.14:
                clash_center = 0.5 * (h1 + h2) if abs(h1 - h2) <= 0.5 else ((0.5 * (h1 + h2 + 1.0)) % 1.0)
                dist_clash = abs(x - clash_center)
                dist_clash = min(dist_clash, 1.0 - dist_clash)
                if dist_clash < 0.16:
                    clash_strength = (1.0 - head_sep / 0.14) * (1.0 - dist_clash / 0.16)
                    spark = 0.7 + 0.3 * math.sin(elapsed_sec * 45.0 + x * 120.0)
                    clash_col = lerp_rgb(secondary, (255, 255, 255), 0.8)
                    rgb_out = add_rgb(rgb_out, scale_rgb(clash_col, clash_strength * spark))

        return rgb_out

    if effect == EffectType.GOVEE_RAINBOW1:
        # Govee Rainbow 1 Style: 100%-lit gapless cosine-interpolated 4-stop color ribbon
        # gliding smoothly across all houses with at least 2 full color cycles and a traveling highlight wave.
        dir_sign = -1.0 if reverse_flow else 1.0
        bg_raw = hex_to_rgb(anim.background_color)
        fourth_col = bg_raw if max(bg_raw) > 45 else lerp_rgb(primary, accent, 0.5)
        stops = [primary, secondary, accent, fourth_col]
        cycles = max(2, pulses + 1)
        pos = ((x * cycles) - dir_sign * unwrapped_phase * 1.35) % 1.0
        scaled = pos * len(stops)
        idx = int(math.floor(scaled)) % len(stops)
        nxt = (idx + 1) % len(stops)
        frac = scaled - math.floor(scaled)
        # Cosine smoothstep so color transitions are silky across uneven segment densities
        smooth_t = 0.5 - 0.5 * math.cos(math.pi * frac)
        base_col = lerp_rgb(stops[idx], stops[nxt], smooth_t)
        highlight_wave = 0.5 * (1.0 + math.sin(2.0 * math.pi * (x * cycles - dir_sign * unwrapped_phase * 2.0)))
        crest = math.pow(highlight_wave, 3.0) * 0.28
        luminous = lerp_rgb(base_col, (255, 255, 255), crest)
        return scale_rgb(luminous, 0.86 + 0.14 * highlight_wave)

    if effect == EffectType.GOVEE_RAINBOW2:
        # Govee Rainbow 2 Style: Vivid stepped multi-color block bands marching across all houses
        # with anti-aliased block edges, at least 2 full color cycles, and Govee crystal highlight wave.
        dir_sign = -1.0 if reverse_flow else 1.0
        bg_raw = hex_to_rgb(anim.background_color)
        fourth_col = bg_raw if max(bg_raw) > 45 else lerp_rgb(secondary, (255, 255, 255), 0.38)
        stops = [primary, secondary, accent, fourth_col]
        cycles = max(2, pulses + 1)
        bands = cycles * len(stops)
        band_pos = ((x * bands) - dir_sign * unwrapped_phase * len(stops)) % len(stops)
        idx = int(math.floor(band_pos)) % len(stops)
        nxt = (idx + 1) % len(stops)
        frac = band_pos - math.floor(band_pos)
        # Hold solid vivid color block across 72% of the band, smooth-glide the remaining 28% border
        if frac < 0.72:
            base_col = stops[idx]
        else:
            edge_t = (frac - 0.72) / 0.28
            smooth_edge = 0.5 - 0.5 * math.cos(math.pi * edge_t)
            base_col = lerp_rgb(stops[idx], stops[nxt], smooth_edge)
        highlight_wave = 0.5 * (1.0 + math.sin(2.0 * math.pi * (x * cycles - dir_sign * unwrapped_phase * 2.0)))
        shimmer = 0.86 + 0.14 * math.sin(elapsed_sec * 14.0 + x * 36.0)
        luminous = lerp_rgb(base_col, (255, 255, 255), math.pow(highlight_wave, 3.2) * 0.24)
        return scale_rgb(luminous, shimmer)

    # Smooth moving 3-color gradient fallback so no effect can ever render static
    dir_sign = -1.0 if reverse_flow else 1.0
    fallback_u = ((x * max(2, pulses + 1)) - dir_sign * unwrapped_phase) % 1.0
    if fallback_u < 0.333:
        fallback_col = lerp_rgb(primary, secondary, fallback_u / 0.333)
    elif fallback_u < 0.666:
        fallback_col = lerp_rgb(secondary, accent, (fallback_u - 0.333) / 0.333)
    else:
        fallback_col = lerp_rgb(accent, primary, (fallback_u - 0.666) / 0.334)
    return add_rgb(bg_scaled, fallback_col)


class MasterAnimationEngine:
    """
    Central Monotonic Clock Animation Engine.
    Calculates exact time-locked RGB values for every segment of every controller across all houses
    and dispatches updates at high frequency without cumulative drift.
    """

    PRESETS: List[Dict[str, Any]] = [
        {
                "id": "diy_halloween_chasing",
                "name": "Halloween Chasing (My Govee DIY)",
                "category": "Halloween",
                "subcategory": "My Govee DIY",
                "scene_source": "diy",
                "badge": "DIY \u2022 Shared",
                "description": "Your custom Govee Home App DIY scene 'Halloween chasing' (synced on both your H705E and Neighbor 2's H805D/H705E).",
                "govee_diy_name": "halloween chasing",
                "govee_diy_id": 24908117,
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#0a0312",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "diy_spooky_halloween_ai",
                "name": "Spooky Halloween AI (My Govee DIY)",
                "category": "Halloween",
                "subcategory": "My Govee DIY",
                "scene_source": "diy",
                "badge": "DIY \u2022 H705E",
                "description": "Your custom Govee Home App DIY scene 'Spooky Halloween AI' (#25004667).",
                "govee_diy_name": "spooky halloween ai",
                "govee_diy_id": 25004667,
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.28,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#9333ea",
                        "secondary_color": "#22c55e",
                        "accent_color": "#ff6b00",
                        "background_color": "#080310",
                        "background_dim": 0.09,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "diy_orange_and_purple",
                "name": "Orange & Purple (My Govee DIY)",
                "category": "Halloween",
                "subcategory": "My Govee DIY",
                "scene_source": "diy",
                "badge": "DIY \u2022 H705E",
                "description": "Your custom Govee Home App DIY scene 'orange and purple' (#24907990).",
                "govee_diy_name": "orange and purple",
                "govee_diy_id": 24907990,
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#ff6b00",
                        "background_color": "#090312",
                        "background_dim": 0.08,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "diy_red_white_running",
                "name": "Red White Running (My Govee DIY)",
                "category": "Christmas",
                "subcategory": "My Govee DIY",
                "scene_source": "diy",
                "badge": "DIY \u2022 H705E",
                "description": "Your custom Govee Home App DIY scene 'red white running' (#25240693).",
                "govee_diy_name": "red white running",
                "govee_diy_id": 25240693,
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#ff5252",
                        "background_color": "#120306",
                        "background_dim": 0.08,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_meteor_14161",
                "name": "Govee: Meteor",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14161",
                "description": "Authentic Govee hardware dynamic scene 'Meteor' (sceneId 14161, paramId 22809).",
                "govee_scene": {
                        "name": "Meteor",
                        "id": 14161,
                        "paramId": 22809
                },
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_karst_cave_10747",
                "name": "Govee: Karst Cave",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10747",
                "description": "Authentic Govee hardware dynamic scene 'Karst Cave' (sceneId 10747, paramId 17952).",
                "govee_scene": {
                        "name": "Karst Cave",
                        "id": 10747,
                        "paramId": 17952
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_cornfield_10749",
                "name": "Govee: Cornfield",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10749",
                "description": "Authentic Govee hardware dynamic scene 'Cornfield' (sceneId 10749, paramId 17954).",
                "govee_scene": {
                        "name": "Cornfield",
                        "id": 10749,
                        "paramId": 17954
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_halloween_c_10766",
                "name": "Govee: Halloween C",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10766",
                "description": "Authentic Govee hardware dynamic scene 'Halloween C' (sceneId 10766, paramId 17971).",
                "govee_scene": {
                        "name": "Halloween C",
                        "id": 10766,
                        "paramId": 17971
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_halloween_d_10767",
                "name": "Govee: Halloween D",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10767",
                "description": "Authentic Govee hardware dynamic scene 'Halloween D' (sceneId 10767, paramId 17972).",
                "govee_scene": {
                        "name": "Halloween D",
                        "id": 10767,
                        "paramId": 17972
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_firefly_10752",
                "name": "Govee: Firefly",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10752",
                "description": "Authentic Govee hardware dynamic scene 'Firefly' (sceneId 10752, paramId 17957).",
                "govee_scene": {
                        "name": "Firefly",
                        "id": 10752,
                        "paramId": 17957
                },
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_fire_10753",
                "name": "Govee: Fire",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10753",
                "description": "Authentic Govee hardware dynamic scene 'Fire' (sceneId 10753, paramId 17958).",
                "govee_scene": {
                        "name": "Fire",
                        "id": 10753,
                        "paramId": 17958
                },
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_cherry_blossoms_10754",
                "name": "Govee: Cherry blossoms",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10754",
                "description": "Authentic Govee hardware dynamic scene 'Cherry blossoms' (sceneId 10754, paramId 17959).",
                "govee_scene": {
                        "name": "Cherry blossoms",
                        "id": 10754,
                        "paramId": 17959
                },
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_spring_10755",
                "name": "Govee: Spring",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10755",
                "description": "Authentic Govee hardware dynamic scene 'Spring' (sceneId 10755, paramId 17960).",
                "govee_scene": {
                        "name": "Spring",
                        "id": 10755,
                        "paramId": 17960
                },
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#facc15",
                        "secondary_color": "#f97316",
                        "accent_color": "#84cc16",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_summer_10756",
                "name": "Govee: Summer",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10756",
                "description": "Authentic Govee hardware dynamic scene 'Summer' (sceneId 10756, paramId 17961).",
                "govee_scene": {
                        "name": "Summer",
                        "id": 10756,
                        "paramId": 17961
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ec4899",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#06b6d4",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_fall_10757",
                "name": "Govee: Fall",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10757",
                "description": "Authentic Govee hardware dynamic scene 'Fall' (sceneId 10757, paramId 17962).",
                "govee_scene": {
                        "name": "Fall",
                        "id": 10757,
                        "paramId": 17962
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_winter_10758",
                "name": "Govee: Winter",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10758",
                "description": "Authentic Govee hardware dynamic scene 'Winter' (sceneId 10758, paramId 17963).",
                "govee_scene": {
                        "name": "Winter",
                        "id": 10758,
                        "paramId": 17963
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_downpour_10759",
                "name": "Govee: Downpour",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10759",
                "description": "Authentic Govee hardware dynamic scene 'Downpour' (sceneId 10759, paramId 17964).",
                "govee_scene": {
                        "name": "Downpour",
                        "id": 10759,
                        "paramId": 17964
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_thunderstorm_14158",
                "name": "Govee: Thunderstorm",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14158",
                "description": "Authentic Govee hardware dynamic scene 'Thunderstorm' (sceneId 14158, paramId 22806).",
                "govee_scene": {
                        "name": "Thunderstorm",
                        "id": 14158,
                        "paramId": 22806
                },
                "animation": {
                        "effect": "lightning_storm",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_milky_way_14159",
                "name": "Govee: Milky Way",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14159",
                "description": "Authentic Govee hardware dynamic scene 'Milky Way' (sceneId 14159, paramId 22807).",
                "govee_scene": {
                        "name": "Milky Way",
                        "id": 14159,
                        "paramId": 22807
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_earth_14160",
                "name": "Govee: Earth",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14160",
                "description": "Authentic Govee hardware dynamic scene 'Earth' (sceneId 14160, paramId 22808).",
                "govee_scene": {
                        "name": "Earth",
                        "id": 14160,
                        "paramId": 22808
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_lake_14162",
                "name": "Govee: Lake",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14162",
                "description": "Authentic Govee hardware dynamic scene 'Lake' (sceneId 14162, paramId 22810).",
                "govee_scene": {
                        "name": "Lake",
                        "id": 14162,
                        "paramId": 22810
                },
                "animation": {
                        "effect": "theater_chase",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_spring_wind_14163",
                "name": "Govee: Spring Wind",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14163",
                "description": "Authentic Govee hardware dynamic scene 'Spring Wind' (sceneId 14163, paramId 22811).",
                "govee_scene": {
                        "name": "Spring Wind",
                        "id": 14163,
                        "paramId": 22811
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#facc15",
                        "secondary_color": "#f97316",
                        "accent_color": "#84cc16",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_sky_15268",
                "name": "Govee: Sky",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #15268",
                "description": "Authentic Govee hardware dynamic scene 'Sky' (sceneId 15268, paramId 24085).",
                "govee_scene": {
                        "name": "Sky",
                        "id": 15268,
                        "paramId": 24085
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_sailboat_15269",
                "name": "Govee: Sailboat",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #15269",
                "description": "Authentic Govee hardware dynamic scene 'Sailboat' (sceneId 15269, paramId 24086).",
                "govee_scene": {
                        "name": "Sailboat",
                        "id": 15269,
                        "paramId": 24086
                },
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_sunrise_10737",
                "name": "Govee: Sunrise",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10737",
                "description": "Authentic Govee hardware dynamic scene 'Sunrise' (sceneId 10737, paramId 17942).",
                "govee_scene": {
                        "name": "Sunrise",
                        "id": 10737,
                        "paramId": 17942
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_sunset_10738",
                "name": "Govee: Sunset",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10738",
                "description": "Authentic Govee hardware dynamic scene 'Sunset' (sceneId 10738, paramId 17943).",
                "govee_scene": {
                        "name": "Sunset",
                        "id": 10738,
                        "paramId": 17943
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_sunset_glow_10739",
                "name": "Govee: Sunset Glow",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10739",
                "description": "Authentic Govee hardware dynamic scene 'Sunset Glow' (sceneId 10739, paramId 17944).",
                "govee_scene": {
                        "name": "Sunset Glow",
                        "id": 10739,
                        "paramId": 17944
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_nebula_10740",
                "name": "Govee: Nebula",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10740",
                "description": "Authentic Govee hardware dynamic scene 'Nebula' (sceneId 10740, paramId 17945).",
                "govee_scene": {
                        "name": "Nebula",
                        "id": 10740,
                        "paramId": 17945
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_moonlight_10741",
                "name": "Govee: Moonlight",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10741",
                "description": "Authentic Govee hardware dynamic scene 'Moonlight' (sceneId 10741, paramId 17946).",
                "govee_scene": {
                        "name": "Moonlight",
                        "id": 10741,
                        "paramId": 17946
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_star_10742",
                "name": "Govee: Star",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10742",
                "description": "Authentic Govee hardware dynamic scene 'Star' (sceneId 10742, paramId 17947).",
                "govee_scene": {
                        "name": "Star",
                        "id": 10742,
                        "paramId": 17947
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_universe_10743",
                "name": "Govee: Universe",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10743",
                "description": "Authentic Govee hardware dynamic scene 'Universe' (sceneId 10743, paramId 17948).",
                "govee_scene": {
                        "name": "Universe",
                        "id": 10743,
                        "paramId": 17948
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_rainbow_10744",
                "name": "Govee: Rainbow",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10744",
                "description": "Authentic Govee hardware dynamic scene 'Rainbow' (sceneId 10744, paramId 17949).",
                "govee_scene": {
                        "name": "Rainbow",
                        "id": 10744,
                        "paramId": 17949
                },
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff0055",
                        "secondary_color": "#00f5d4",
                        "accent_color": "#facc15",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_forest_10745",
                "name": "Govee: Forest",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10745",
                "description": "Authentic Govee hardware dynamic scene 'Forest' (sceneId 10745, paramId 17950).",
                "govee_scene": {
                        "name": "Forest",
                        "id": 10745,
                        "paramId": 17950
                },
                "animation": {
                        "effect": "theater_chase",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ec4899",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#06b6d4",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_aurora_10746",
                "name": "Govee: Aurora",
                "category": "Center-Out (My House)",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10746",
                "description": "Authentic Govee hardware dynamic scene 'Aurora' (sceneId 10746, paramId 17951).",
                "govee_scene": {
                        "name": "Aurora",
                        "id": 10746,
                        "paramId": 17951
                },
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#38bdf8",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_wave_10748",
                "name": "Govee: Wave",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10748",
                "description": "Authentic Govee hardware dynamic scene 'Wave' (sceneId 10748, paramId 17953).",
                "govee_scene": {
                        "name": "Wave",
                        "id": 10748,
                        "paramId": 17953
                },
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#7b2cbf",
                        "accent_color": "#ff007f",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_rustling_leaves_10750",
                "name": "Govee: Rustling leaves",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10750",
                "description": "Authentic Govee hardware dynamic scene 'Rustling leaves' (sceneId 10750, paramId 17955).",
                "govee_scene": {
                        "name": "Rustling leaves",
                        "id": 10750,
                        "paramId": 17955
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_flower_field_10751",
                "name": "Govee: Flower Field",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10751",
                "description": "Authentic Govee hardware dynamic scene 'Flower Field' (sceneId 10751, paramId 17956).",
                "govee_scene": {
                        "name": "Flower Field",
                        "id": 10751,
                        "paramId": 17956
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#06b6d4",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_christmas_10760",
                "name": "Govee: Christmas",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10760",
                "description": "Authentic Govee hardware dynamic scene 'Christmas' (sceneId 10760, paramId 17965).",
                "govee_scene": {
                        "name": "Christmas",
                        "id": 10760,
                        "paramId": 17965
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_christmas_tree_10761",
                "name": "Govee: Christmas Tree",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10761",
                "description": "Authentic Govee hardware dynamic scene 'Christmas Tree' (sceneId 10761, paramId 17966).",
                "govee_scene": {
                        "name": "Christmas Tree",
                        "id": 10761,
                        "paramId": 17966
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_christmas_gift_10762",
                "name": "Govee: Christmas Gift",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10762",
                "description": "Authentic Govee hardware dynamic scene 'Christmas Gift' (sceneId 10762, paramId 17967).",
                "govee_scene": {
                        "name": "Christmas Gift",
                        "id": 10762,
                        "paramId": 17967
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_sled_10763",
                "name": "Govee: Sled",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10763",
                "description": "Authentic Govee hardware dynamic scene 'Sled' (sceneId 10763, paramId 17968).",
                "govee_scene": {
                        "name": "Sled",
                        "id": 10763,
                        "paramId": 17968
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_halloween_10764",
                "name": "Govee: Halloween",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10764",
                "description": "Authentic Govee hardware dynamic scene 'Halloween' (sceneId 10764, paramId 17969).",
                "govee_scene": {
                        "name": "Halloween",
                        "id": 10764,
                        "paramId": 17969
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_halloween_b_10765",
                "name": "Govee: Halloween B",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10765",
                "description": "Authentic Govee hardware dynamic scene 'Halloween B' (sceneId 10765, paramId 17970).",
                "govee_scene": {
                        "name": "Halloween B",
                        "id": 10765,
                        "paramId": 17970
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_easter_10768",
                "name": "Govee: Easter",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10768",
                "description": "Authentic Govee hardware dynamic scene 'Easter' (sceneId 10768, paramId 17973).",
                "govee_scene": {
                        "name": "Easter",
                        "id": 10768,
                        "paramId": 17973
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_mother_s_day_10769",
                "name": "Govee: Mother's Day",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10769",
                "description": "Authentic Govee hardware dynamic scene 'Mother's Day' (sceneId 10769, paramId 17974).",
                "govee_scene": {
                        "name": "Mother's Day",
                        "id": 10769,
                        "paramId": 17974
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_mother_s_day_b_10770",
                "name": "Govee: Mother's Day B",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10770",
                "description": "Authentic Govee hardware dynamic scene 'Mother's Day B' (sceneId 10770, paramId 17975).",
                "govee_scene": {
                        "name": "Mother's Day B",
                        "id": 10770,
                        "paramId": 17975
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_father_s_day_10771",
                "name": "Govee: Father's Day",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10771",
                "description": "Authentic Govee hardware dynamic scene 'Father's Day' (sceneId 10771, paramId 17976).",
                "govee_scene": {
                        "name": "Father's Day",
                        "id": 10771,
                        "paramId": 17976
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_father_s_dayb_10772",
                "name": "Govee: Father's DayB",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10772",
                "description": "Authentic Govee hardware dynamic scene 'Father's DayB' (sceneId 10772, paramId 17977).",
                "govee_scene": {
                        "name": "Father's DayB",
                        "id": 10772,
                        "paramId": 17977
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_birthday_10773",
                "name": "Govee: Birthday",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10773",
                "description": "Authentic Govee hardware dynamic scene 'Birthday' (sceneId 10773, paramId 17978).",
                "govee_scene": {
                        "name": "Birthday",
                        "id": 10773,
                        "paramId": 17978
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_new_years_10774",
                "name": "Govee: New Years",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10774",
                "description": "Authentic Govee hardware dynamic scene 'New Years' (sceneId 10774, paramId 17979).",
                "govee_scene": {
                        "name": "New Years",
                        "id": 10774,
                        "paramId": 17979
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_thanksgiving_10775",
                "name": "Govee: Thanksgiving",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10775",
                "description": "Authentic Govee hardware dynamic scene 'Thanksgiving' (sceneId 10775, paramId 17980).",
                "govee_scene": {
                        "name": "Thanksgiving",
                        "id": 10775,
                        "paramId": 17980
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_carnival_10776",
                "name": "Govee: Carnival",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10776",
                "description": "Authentic Govee hardware dynamic scene 'Carnival' (sceneId 10776, paramId 17981).",
                "govee_scene": {
                        "name": "Carnival",
                        "id": 10776,
                        "paramId": 17981
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_valentine_s_day_10777",
                "name": "Govee: Valentine's Day",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10777",
                "description": "Authentic Govee hardware dynamic scene 'Valentine's Day' (sceneId 10777, paramId 17982).",
                "govee_scene": {
                        "name": "Valentine's Day",
                        "id": 10777,
                        "paramId": 17982
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_dance_party_10778",
                "name": "Govee: Dance Party",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10778",
                "description": "Authentic Govee hardware dynamic scene 'Dance Party' (sceneId 10778, paramId 17983).",
                "govee_scene": {
                        "name": "Dance Party",
                        "id": 10778,
                        "paramId": 17983
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_party_10779",
                "name": "Govee: Party",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10779",
                "description": "Authentic Govee hardware dynamic scene 'Party' (sceneId 10779, paramId 17984).",
                "govee_scene": {
                        "name": "Party",
                        "id": 10779,
                        "paramId": 17984
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_dine_together_10780",
                "name": "Govee: Dine Together",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10780",
                "description": "Authentic Govee hardware dynamic scene 'Dine Together' (sceneId 10780, paramId 17985).",
                "govee_scene": {
                        "name": "Dine Together",
                        "id": 10780,
                        "paramId": 17985
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_fireworks_10781",
                "name": "Govee: Fireworks",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10781",
                "description": "Authentic Govee hardware dynamic scene 'Fireworks' (sceneId 10781, paramId 17986).",
                "govee_scene": {
                        "name": "Fireworks",
                        "id": 10781,
                        "paramId": 17986
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_candlelight_10782",
                "name": "Govee: Candlelight",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10782",
                "description": "Authentic Govee hardware dynamic scene 'Candlelight' (sceneId 10782, paramId 17987).",
                "govee_scene": {
                        "name": "Candlelight",
                        "id": 10782,
                        "paramId": 17987
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_saint_patrick_s_day_10783",
                "name": "Govee: Saint Patrick's Day",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10783",
                "description": "Authentic Govee hardware dynamic scene 'Saint Patrick's Day' (sceneId 10783, paramId 17988).",
                "govee_scene": {
                        "name": "Saint Patrick's Day",
                        "id": 10783,
                        "paramId": 17988
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_hanukkah_10784",
                "name": "Govee: Hanukkah",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10784",
                "description": "Authentic Govee hardware dynamic scene 'Hanukkah' (sceneId 10784, paramId 17989).",
                "govee_scene": {
                        "name": "Hanukkah",
                        "id": 10784,
                        "paramId": 17989
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_game_day_10785",
                "name": "Govee: Game Day",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10785",
                "description": "Authentic Govee hardware dynamic scene 'Game Day' (sceneId 10785, paramId 17990).",
                "govee_scene": {
                        "name": "Game Day",
                        "id": 10785,
                        "paramId": 17990
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_baby_shower_10786",
                "name": "Govee: Baby Shower",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10786",
                "description": "Authentic Govee hardware dynamic scene 'Baby Shower' (sceneId 10786, paramId 17991).",
                "govee_scene": {
                        "name": "Baby Shower",
                        "id": 10786,
                        "paramId": 17991
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_winter_wonderland_10787",
                "name": "Govee: Winter Wonderland",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10787",
                "description": "Authentic Govee hardware dynamic scene 'Winter Wonderland' (sceneId 10787, paramId 17992).",
                "govee_scene": {
                        "name": "Winter Wonderland",
                        "id": 10787,
                        "paramId": 17992
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_leprechaun_10788",
                "name": "Govee: Leprechaun",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10788",
                "description": "Authentic Govee hardware dynamic scene 'Leprechaun' (sceneId 10788, paramId 17993).",
                "govee_scene": {
                        "name": "Leprechaun",
                        "id": 10788,
                        "paramId": 17993
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_christmas_bell_14164",
                "name": "Govee: Christmas Bell",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14164",
                "description": "Authentic Govee hardware dynamic scene 'Christmas Bell' (sceneId 14164, paramId 22812).",
                "govee_scene": {
                        "name": "Christmas Bell",
                        "id": 14164,
                        "paramId": 22812
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_candy_cane_14165",
                "name": "Govee: Candy Cane",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14165",
                "description": "Authentic Govee hardware dynamic scene 'Candy Cane' (sceneId 14165, paramId 22813).",
                "govee_scene": {
                        "name": "Candy Cane",
                        "id": 14165,
                        "paramId": 22813
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_christmas_eve_14166",
                "name": "Govee: Christmas Eve",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14166",
                "description": "Authentic Govee hardware dynamic scene 'Christmas Eve' (sceneId 14166, paramId 22814).",
                "govee_scene": {
                        "name": "Christmas Eve",
                        "id": 14166,
                        "paramId": 22814
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_christmas_wreath_14167",
                "name": "Govee: Christmas Wreath",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14167",
                "description": "Authentic Govee hardware dynamic scene 'Christmas Wreath' (sceneId 14167, paramId 22815).",
                "govee_scene": {
                        "name": "Christmas Wreath",
                        "id": 14167,
                        "paramId": 22815
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_easter_egg_14168",
                "name": "Govee: Easter Egg",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14168",
                "description": "Authentic Govee hardware dynamic scene 'Easter Egg' (sceneId 14168, paramId 22816).",
                "govee_scene": {
                        "name": "Easter Egg",
                        "id": 14168,
                        "paramId": 22816
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_children_s_day_14169",
                "name": "Govee: Children's Day",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14169",
                "description": "Authentic Govee hardware dynamic scene 'Children's Day' (sceneId 14169, paramId 22817).",
                "govee_scene": {
                        "name": "Children's Day",
                        "id": 14169,
                        "paramId": 22817
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_beer_festival_14170",
                "name": "Govee: Beer Festival",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14170",
                "description": "Authentic Govee hardware dynamic scene 'Beer Festival' (sceneId 14170, paramId 22818).",
                "govee_scene": {
                        "name": "Beer Festival",
                        "id": 14170,
                        "paramId": 22818
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_music_show_14171",
                "name": "Govee: Music Show",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14171",
                "description": "Authentic Govee hardware dynamic scene 'Music Show' (sceneId 14171, paramId 22819).",
                "govee_scene": {
                        "name": "Music Show",
                        "id": 14171,
                        "paramId": 22819
                },
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#7b2cbf",
                        "accent_color": "#ff007f",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_amusement_14172",
                "name": "Govee: Amusement",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14172",
                "description": "Authentic Govee hardware dynamic scene 'Amusement' (sceneId 14172, paramId 22820).",
                "govee_scene": {
                        "name": "Amusement",
                        "id": 14172,
                        "paramId": 22820
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#818cf8",
                        "accent_color": "#f472b6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_confetti_14173",
                "name": "Govee: Confetti",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14173",
                "description": "Authentic Govee hardware dynamic scene 'Confetti' (sceneId 14173, paramId 22821).",
                "govee_scene": {
                        "name": "Confetti",
                        "id": 14173,
                        "paramId": 22821
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_flower_parade_14174",
                "name": "Govee: Flower Parade",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14174",
                "description": "Authentic Govee hardware dynamic scene 'Flower Parade' (sceneId 14174, paramId 22822).",
                "govee_scene": {
                        "name": "Flower Parade",
                        "id": 14174,
                        "paramId": 22822
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#06b6d4",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_halloween_14491",
                "name": "Govee: Halloween II",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14491",
                "description": "Authentic Govee hardware dynamic scene 'Halloween' (sceneId 14491, paramId 23302).",
                "govee_scene": {
                        "name": "Halloween",
                        "id": 14491,
                        "paramId": 23302
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_delivering_gifts_14492",
                "name": "Govee: Delivering Gifts",
                "category": "Christmas",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14492",
                "description": "Authentic Govee hardware dynamic scene 'Delivering Gifts' (sceneId 14492, paramId 23303).",
                "govee_scene": {
                        "name": "Delivering Gifts",
                        "id": 14492,
                        "paramId": 23303
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_white_light_10789",
                "name": "Govee: White Light",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10789",
                "description": "Authentic Govee hardware dynamic scene 'White Light' (sceneId 10789, paramId 17994).",
                "govee_scene": {
                        "name": "White Light",
                        "id": 10789,
                        "paramId": 17994
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#facc15",
                        "secondary_color": "#f97316",
                        "accent_color": "#84cc16",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_bright_10791",
                "name": "Govee: Bright",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10791",
                "description": "Authentic Govee hardware dynamic scene 'Bright' (sceneId 10791, paramId 17996).",
                "govee_scene": {
                        "name": "Bright",
                        "id": 10791,
                        "paramId": 17996
                },
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_morning_10792",
                "name": "Govee: Morning",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10792",
                "description": "Authentic Govee hardware dynamic scene 'Morning' (sceneId 10792, paramId 17997).",
                "govee_scene": {
                        "name": "Morning",
                        "id": 10792,
                        "paramId": 17997
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#fbbf24",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_afternoon_10793",
                "name": "Govee: Afternoon",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10793",
                "description": "Authentic Govee hardware dynamic scene 'Afternoon' (sceneId 10793, paramId 17998).",
                "govee_scene": {
                        "name": "Afternoon",
                        "id": 10793,
                        "paramId": 17998
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#7b2cbf",
                        "accent_color": "#ff007f",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_twilight_10794",
                "name": "Govee: Twilight",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10794",
                "description": "Authentic Govee hardware dynamic scene 'Twilight' (sceneId 10794, paramId 17999).",
                "govee_scene": {
                        "name": "Twilight",
                        "id": 10794,
                        "paramId": 17999
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_night_10795",
                "name": "Govee: Night",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10795",
                "description": "Authentic Govee hardware dynamic scene 'Night' (sceneId 10795, paramId 18000).",
                "govee_scene": {
                        "name": "Night",
                        "id": 10795,
                        "paramId": 18000
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_leisure_10796",
                "name": "Govee: Leisure",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10796",
                "description": "Authentic Govee hardware dynamic scene 'Leisure' (sceneId 10796, paramId 18001).",
                "govee_scene": {
                        "name": "Leisure",
                        "id": 10796,
                        "paramId": 18001
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#06b6d4",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_refreshing_10797",
                "name": "Govee: Refreshing",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10797",
                "description": "Authentic Govee hardware dynamic scene 'Refreshing' (sceneId 10797, paramId 18002).",
                "govee_scene": {
                        "name": "Refreshing",
                        "id": 10797,
                        "paramId": 18002
                },
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#d946ef",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#00f5d4",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_candy_10798",
                "name": "Govee: Candy",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10798",
                "description": "Authentic Govee hardware dynamic scene 'Candy' (sceneId 10798, paramId 18003).",
                "govee_scene": {
                        "name": "Candy",
                        "id": 10798,
                        "paramId": 18003
                },
                "animation": {
                        "effect": "rainbow_wave",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_spin_10799",
                "name": "Govee: Spin",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10799",
                "description": "Authentic Govee hardware dynamic scene 'Spin' (sceneId 10799, paramId 18004).",
                "govee_scene": {
                        "name": "Spin",
                        "id": 10799,
                        "paramId": 18004
                },
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#facc15",
                        "secondary_color": "#f97316",
                        "accent_color": "#84cc16",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_dancing_10800",
                "name": "Govee: Dancing",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10800",
                "description": "Authentic Govee hardware dynamic scene 'Dancing' (sceneId 10800, paramId 18005).",
                "govee_scene": {
                        "name": "Dancing",
                        "id": 10800,
                        "paramId": 18005
                },
                "animation": {
                        "effect": "theater_chase",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ec4899",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#06b6d4",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_sports_10801",
                "name": "Govee: Sports",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10801",
                "description": "Authentic Govee hardware dynamic scene 'Sports' (sceneId 10801, paramId 18006).",
                "govee_scene": {
                        "name": "Sports",
                        "id": 10801,
                        "paramId": 18006
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_swing_10802",
                "name": "Govee: Swing",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10802",
                "description": "Authentic Govee hardware dynamic scene 'Swing' (sceneId 10802, paramId 18007).",
                "govee_scene": {
                        "name": "Swing",
                        "id": 10802,
                        "paramId": 18007
                },
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#fbbf24",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_colorful_10803",
                "name": "Govee: Colorful",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10803",
                "description": "Authentic Govee hardware dynamic scene 'Colorful' (sceneId 10803, paramId 18008).",
                "govee_scene": {
                        "name": "Colorful",
                        "id": 10803,
                        "paramId": 18008
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#7b2cbf",
                        "accent_color": "#ff007f",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_flow_10804",
                "name": "Govee: Flow",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10804",
                "description": "Authentic Govee hardware dynamic scene 'Flow' (sceneId 10804, paramId 18009).",
                "govee_scene": {
                        "name": "Flow",
                        "id": 10804,
                        "paramId": 18009
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#818cf8",
                        "accent_color": "#f472b6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_fluctuate_10805",
                "name": "Govee: Fluctuate",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10805",
                "description": "Authentic Govee hardware dynamic scene 'Fluctuate' (sceneId 10805, paramId 18010).",
                "govee_scene": {
                        "name": "Fluctuate",
                        "id": 10805,
                        "paramId": 18010
                },
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#ef4444",
                        "accent_color": "#fde047",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_stacking_10806",
                "name": "Govee: Stacking",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10806",
                "description": "Authentic Govee hardware dynamic scene 'Stacking' (sceneId 10806, paramId 18011).",
                "govee_scene": {
                        "name": "Stacking",
                        "id": 10806,
                        "paramId": 18011
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#06b6d4",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_beer_14493",
                "name": "Govee: Beer",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14493",
                "description": "Authentic Govee hardware dynamic scene 'Beer' (sceneId 14493, paramId 23304).",
                "govee_scene": {
                        "name": "Beer",
                        "id": 14493,
                        "paramId": 23304
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_gradient_10807",
                "name": "Govee: Gradient",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10807",
                "description": "Authentic Govee hardware dynamic scene 'Gradient' (sceneId 10807, paramId 18012).",
                "govee_scene": {
                        "name": "Gradient",
                        "id": 10807,
                        "paramId": 18012
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_romantic_10808",
                "name": "Govee: Romantic",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10808",
                "description": "Authentic Govee hardware dynamic scene 'Romantic' (sceneId 10808, paramId 18013).",
                "govee_scene": {
                        "name": "Romantic",
                        "id": 10808,
                        "paramId": 18013
                },
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#facc15",
                        "secondary_color": "#f97316",
                        "accent_color": "#84cc16",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_quiet_10809",
                "name": "Govee: Quiet",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10809",
                "description": "Authentic Govee hardware dynamic scene 'Quiet' (sceneId 10809, paramId 18014).",
                "govee_scene": {
                        "name": "Quiet",
                        "id": 10809,
                        "paramId": 18014
                },
                "animation": {
                        "effect": "rainbow_wave",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ec4899",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#06b6d4",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_happy_10810",
                "name": "Govee: Happy",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10810",
                "description": "Authentic Govee hardware dynamic scene 'Happy' (sceneId 10810, paramId 18015).",
                "govee_scene": {
                        "name": "Happy",
                        "id": 10810,
                        "paramId": 18015
                },
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_profound_10811",
                "name": "Govee: Profound",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10811",
                "description": "Authentic Govee hardware dynamic scene 'Profound' (sceneId 10811, paramId 18016).",
                "govee_scene": {
                        "name": "Profound",
                        "id": 10811,
                        "paramId": 18016
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_enthusiastic_10812",
                "name": "Govee: Enthusiastic",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10812",
                "description": "Authentic Govee hardware dynamic scene 'Enthusiastic' (sceneId 10812, paramId 18017).",
                "govee_scene": {
                        "name": "Enthusiastic",
                        "id": 10812,
                        "paramId": 18017
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#7b2cbf",
                        "accent_color": "#ff007f",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_mysterious_10813",
                "name": "Govee: Mysterious",
                "category": "Halloween",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10813",
                "description": "Authentic Govee hardware dynamic scene 'Mysterious' (sceneId 10813, paramId 18018).",
                "govee_scene": {
                        "name": "Mysterious",
                        "id": 10813,
                        "paramId": 18018
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_soothing_10814",
                "name": "Govee: Soothing",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10814",
                "description": "Authentic Govee hardware dynamic scene 'Soothing' (sceneId 10814, paramId 18019).",
                "govee_scene": {
                        "name": "Soothing",
                        "id": 10814,
                        "paramId": 18019
                },
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#ef4444",
                        "accent_color": "#fde047",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_dreamlike_10815",
                "name": "Govee: Dreamlike",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10815",
                "description": "Authentic Govee hardware dynamic scene 'Dreamlike' (sceneId 10815, paramId 18020).",
                "govee_scene": {
                        "name": "Dreamlike",
                        "id": 10815,
                        "paramId": 18020
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#06b6d4",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_warm_10816",
                "name": "Govee: Warm",
                "category": "Diwali",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10816",
                "description": "Authentic Govee hardware dynamic scene 'Warm' (sceneId 10816, paramId 18021).",
                "govee_scene": {
                        "name": "Warm",
                        "id": 10816,
                        "paramId": 18021
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_leisurely_10817",
                "name": "Govee: Leisurely",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10817",
                "description": "Authentic Govee hardware dynamic scene 'Leisurely' (sceneId 10817, paramId 18022).",
                "govee_scene": {
                        "name": "Leisurely",
                        "id": 10817,
                        "paramId": 18022
                },
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_dreamland_10818",
                "name": "Govee: Dreamland",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10818",
                "description": "Authentic Govee hardware dynamic scene 'Dreamland' (sceneId 10818, paramId 18023).",
                "govee_scene": {
                        "name": "Dreamland",
                        "id": 10818,
                        "paramId": 18023
                },
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#facc15",
                        "secondary_color": "#f97316",
                        "accent_color": "#84cc16",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_active_10819",
                "name": "Govee: Active",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #10819",
                "description": "Authentic Govee hardware dynamic scene 'Active' (sceneId 10819, paramId 18024).",
                "govee_scene": {
                        "name": "Active",
                        "id": 10819,
                        "paramId": 18024
                },
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ec4899",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#06b6d4",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_hooray_14175",
                "name": "Govee: Hooray",
                "category": "Celebrations",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #14175",
                "description": "Authentic Govee hardware dynamic scene 'Hooray' (sceneId 14175, paramId 22823).",
                "govee_scene": {
                        "name": "Hooray",
                        "id": 14175,
                        "paramId": 22823
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_flash_23504",
                "name": "Govee: Flash",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #23504",
                "description": "Authentic Govee hardware dynamic scene 'Flash' (sceneId 23504, paramId 34012).",
                "govee_scene": {
                        "name": "Flash",
                        "id": 23504,
                        "paramId": 34012
                },
                "animation": {
                        "effect": "lightning_storm",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#fbbf24",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_gary_23505",
                "name": "Govee: Gary",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #23505",
                "description": "Authentic Govee hardware dynamic scene 'Gary' (sceneId 23505, paramId 34013).",
                "govee_scene": {
                        "name": "Gary",
                        "id": 23505,
                        "paramId": 34013
                },
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#7b2cbf",
                        "accent_color": "#ff007f",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_judy_23506",
                "name": "Govee: Judy",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #23506",
                "description": "Authentic Govee hardware dynamic scene 'Judy' (sceneId 23506, paramId 34014).",
                "govee_scene": {
                        "name": "Judy",
                        "id": 23506,
                        "paramId": 34014
                },
                "animation": {
                        "effect": "theater_chase",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#818cf8",
                        "accent_color": "#f472b6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_nick_23507",
                "name": "Govee: Nick",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #23507",
                "description": "Authentic Govee hardware dynamic scene 'Nick' (sceneId 23507, paramId 34015).",
                "govee_scene": {
                        "name": "Nick",
                        "id": 23507,
                        "paramId": 34015
                },
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#ef4444",
                        "accent_color": "#fde047",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_zdp_duo_23508",
                "name": "Govee: ZDP Duo",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #23508",
                "description": "Authentic Govee hardware dynamic scene 'ZDP Duo' (sceneId 23508, paramId 34016).",
                "govee_scene": {
                        "name": "ZDP Duo",
                        "id": 23508,
                        "paramId": 34016
                },
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.23,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#06b6d4",
                        "accent_color": "#3b82f6",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_zdp_trio_23509",
                "name": "Govee: ZDP Trio",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #23509",
                "description": "Authentic Govee hardware dynamic scene 'ZDP Trio' (sceneId 23509, paramId 34017).",
                "govee_scene": {
                        "name": "ZDP Trio",
                        "id": 23509,
                        "paramId": 34017
                },
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#d946ef",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#00f5d4",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "govee_official_a_m_33896",
                "name": "Govee: A&M",
                "category": "Cyber & Party",
                "subcategory": "Official Govee",
                "scene_source": "official",
                "badge": "Official #33896",
                "description": "Authentic Govee hardware dynamic scene 'A&M' (sceneId 33896, paramId 46134).",
                "govee_scene": {
                        "name": "A&M",
                        "id": 33896,
                        "paramId": 46134
                },
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.29,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#060814",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "halloween_haunted_chase",
                "name": "Haunted Street Phantom Chase",
                "category": "Halloween",
                "badge": "AI \u2022 Spooky",
                "description": "Haunted purple, toxic green, and pumpkin orange phantom orbs traveling House 1 -> 2 -> 3 with rooftop lightning flashes.",
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#9333ea",
                        "secondary_color": "#22c55e",
                        "accent_color": "#f97316",
                        "background_color": "#0d0417",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_witch_cauldron",
                "name": "Witch's Cauldron & Thunder",
                "category": "Halloween",
                "badge": "AI \u2022 Storm",
                "description": "Bubbling toxic green cauldron mist and ultraviolet storm clouds with blood-red chain lightning jumping across houses.",
                "animation": {
                        "effect": "lightning_storm",
                        "speed": 0.34,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#7e22ce",
                        "accent_color": "#ef4444",
                        "background_color": "#06110c",
                        "background_dim": 0.12,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_blood_meteor",
                "name": "Vampire Blood Moon Meteor",
                "category": "Halloween",
                "badge": "AI \u2022 Gothic",
                "description": "Piercing bone-white and crimson blood-moon meteors streaking across the neighborhood with smoldering ember tails.",
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#dc2626",
                        "secondary_color": "#ea580c",
                        "accent_color": "#fef2f2",
                        "background_color": "#140303",
                        "background_dim": 0.08,
                        "tail_length": 0.3,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_pumpkin_marquee",
                "name": "Jack-O'-Lantern Marquee",
                "category": "Halloween",
                "badge": "AI \u2022 Classic",
                "description": "Crisp pumpkin orange, witch purple, and lantern gold theater marquee synchronized across all three houses.",
                "animation": {
                        "effect": "theater_chase",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#a855f7",
                        "accent_color": "#facc15",
                        "background_color": "#120700",
                        "background_dim": 0.1,
                        "tail_length": 0.22,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_poltergeist_portal",
                "name": "Poltergeist Portal (From My House)",
                "category": "Halloween",
                "badge": "AI \u2022 Center-Out",
                "description": "Spectral ectoplasm cyan and ghostly violet dimensional rifts erupting from My Middle House (#2) outward into both neighbors.",
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#070210",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_zombie_outbreak",
                "name": "Zombie Biohazard Breach",
                "category": "Halloween",
                "badge": "AI \u2022 Dual Snake",
                "description": "Radioactive toxic-lime and hazard-yellow serpents slithering from opposite ends of the street and clashing in blood-red sparks at the middle house.",
                "animation": {
                        "effect": "cyber_snake",
                        "speed": 0.28,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#84cc16",
                        "secondary_color": "#eab308",
                        "accent_color": "#dc2626",
                        "background_color": "#050d02",
                        "background_dim": 0.09,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_frankenstein_lab",
                "name": "Frankenstein's Tesla Coil Lab",
                "category": "Halloween",
                "badge": "AI \u2022 High Voltage",
                "description": "Crackling laboratory cyan and monster-green voltage surging down the street with blinding white-violet Jacob's Ladder arcs.",
                "animation": {
                        "effect": "lightning_storm",
                        "speed": 0.42,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#22c55e",
                        "accent_color": "#e879f9",
                        "background_color": "#020814",
                        "background_dim": 0.1,
                        "tail_length": 0.22,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_headless_horseman",
                "name": "Gallop of the Headless Horseman",
                "category": "Halloween",
                "badge": "AI \u2022 Fast Bounce",
                "description": "Relentless flaming pumpkin-orange and shadow-crimson comet galloping back and forth across all three rooflines.",
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.44,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff5500",
                        "secondary_color": "#dc2626",
                        "accent_color": "#fde047",
                        "background_color": "#0c030c",
                        "background_dim": 0.06,
                        "tail_length": 0.34,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_beetlejuice_sandworm",
                "name": "Sandworm Graveyard Stripes",
                "category": "Halloween",
                "badge": "AI \u2022 Twisted",
                "description": "Hypnotic rotating neon-lime, ghost-white, and ultraviolet carnival stripes twisting continuously from house to house.",
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.27,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#a855f7",
                        "secondary_color": "#22c55e",
                        "accent_color": "#f8fafc",
                        "background_color": "#06020a",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_hellfire_brimstone",
                "name": "Underworld Hellfire & Brimstone",
                "category": "Halloween",
                "badge": "AI \u2022 Inferno",
                "description": "Roaring abyssal blood-crimson, molten magma orange, and sulfur-gold flames licking across all three houses.",
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.36,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#dc2626",
                        "secondary_color": "#ea580c",
                        "accent_color": "#facc15",
                        "background_color": "#140202",
                        "background_dim": 0.14,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_phantom_ghost_train",
                "name": "Midnight Phantom Ghost Train",
                "category": "Halloween",
                "badge": "AI \u2022 3 Carriages",
                "description": "Three glowing ectoplasm-teal and spectral-blue train carriages chugging in sequence across Neighbor 1 -> My House -> Neighbor 2.",
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#2dd4bf",
                        "secondary_color": "#6366f1",
                        "accent_color": "#c084fc",
                        "background_color": "#030712",
                        "background_dim": 0.07,
                        "tail_length": 0.2,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_shadow_possession",
                "name": "Creeping Shadow Possession Wipe",
                "category": "Halloween",
                "badge": "AI \u2022 Takeover",
                "description": "Slow, ominous supernatural color wipe overtaking the street in waves of pumpkin amber, cursed emerald, and midnight purple.",
                "animation": {
                        "effect": "color_wipe",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f97316",
                        "secondary_color": "#7e22ce",
                        "accent_color": "#10b981",
                        "background_color": "#08020f",
                        "background_dim": 0.08,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_black_widow_lair",
                "name": "Black Widow Venom & Webs",
                "category": "Halloween",
                "badge": "AI \u2022 Venomous",
                "description": "Velvet obsidian-violet spiderweb glow punctured by sudden venomous scarlet and ruby fangs across every eave.",
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#6b21a8",
                        "accent_color": "#f43f5e",
                        "background_color": "#09010d",
                        "background_dim": 0.12,
                        "tail_length": 0.22,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_haunted_heartbeat",
                "name": "Tell-Tale Heartbeat Pulse",
                "category": "Halloween",
                "badge": "AI \u2022 Lockstep",
                "description": "Throbbing crimson-to-amethyst heartbeat pulsing across all three houses in eerie synchronized lockstep.",
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "parallel_zones",
                        "primary_color": "#e11d48",
                        "secondary_color": "#581c87",
                        "accent_color": "#ff6b00",
                        "background_color": "#0a0106",
                        "background_dim": 0.08,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_candy_corn_parade",
                "name": "Trick-or-Treat Candy Corn Parade",
                "category": "Halloween",
                "badge": "AI \u2022 Family Fun",
                "description": "Playful harvest orange, buttercup yellow, and marshmallow white tri-color wave marching down the neighborhood.",
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff7b00",
                        "secondary_color": "#facc15",
                        "accent_color": "#ffffff",
                        "background_color": "#140800",
                        "background_dim": 0.1,
                        "tail_length": 0.32,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_pharaoh_curse",
                "name": "Curse of the Ancient Mummy",
                "category": "Halloween",
                "badge": "AI \u2022 Mystic",
                "description": "Swirling cursed sarcophagus gold, scarab emerald, and mystic violet sandstorm sweeping across all three houses.",
                "animation": {
                        "effect": "halloween_spooky",
                        "speed": 0.24,
                        "direction": "reverse",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#eab308",
                        "secondary_color": "#14b8a6",
                        "accent_color": "#a855f7",
                        "background_color": "#120c02",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow1_spooky_prism",
                "name": "Halloween Rainbow 1: Haunted Prism Flow",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Govee Rainbow 1 style: 100%-lit seamless gradient ribbon of pumpkin orange, witch purple, toxic green, and blood crimson gliding across all 3 houses.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#e11d48",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow2_monster_blocks",
                "name": "Halloween Rainbow 2: Monster Mash Blocks",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Govee Rainbow 2 style: Crisp marching color blocks of carved pumpkin, ultraviolet, slime green, and bone gold stepping cleanly roof to roof.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.24,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#a855f7",
                        "accent_color": "#10b981",
                        "background_color": "#facc15",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow1_hocus_pocus",
                "name": "Halloween Rainbow 1: Sanderson Sisters Silk",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Continuous gapless velvet gradient of Winifred emerald, Sarah amethyst, Mary crimson, and harvest gold flowing across the street.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#ef4444",
                        "background_color": "#f59e0b",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow2_candy_corn_blocks",
                "name": "Halloween Rainbow 2: Candy Corn Ribbon",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Govee Rainbow 2 segmented blocks of bright candy-corn orange, lemon yellow, marshmallow white, and royal purple marching in unison.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff7b00",
                        "secondary_color": "#facc15",
                        "accent_color": "#ffffff",
                        "background_color": "#7e22ce",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow1_ectoplasm_wave",
                "name": "Halloween Rainbow 1: Ectoplasm Neon Spectrum",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "100%-lit supernatural neon spectrum blending ghost cyan, radioactive green, ultraviolet, and hot magenta across all 3 houses.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.28,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#84cc16",
                        "accent_color": "#9333ea",
                        "background_color": "#ff007f",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow2_dracula_castle",
                "name": "Halloween Rainbow 2: Dracula's Crimson Court",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Stepped Gothic blocks of blood crimson, royal plum, candle gold, and midnight indigo gliding across every gable.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#dc2626",
                        "secondary_color": "#6b21a8",
                        "accent_color": "#fbbf24",
                        "background_color": "#312e81",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow1_pumpkin_spice",
                "name": "Halloween Rainbow 1: Harvest Moon Gradient",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Warm autumn sunset gradient of harvest pumpkin, golden cider, crimson maple, and twilight violet spanning the whole block.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.18,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f97316",
                        "secondary_color": "#eab308",
                        "accent_color": "#dc2626",
                        "background_color": "#7c3aed",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow2_goblin_parade",
                "name": "Halloween Rainbow 2: Goblin Neon Parade",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "High-contrast Govee Rainbow 2 bands of goblin green, electric violet, tangerine orange, and laser magenta.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.3,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#22c55e",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#ff6b00",
                        "background_color": "#ec4899",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow1_witches_brew",
                "name": "Halloween Rainbow 1: Swirling Witches' Brew",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Continuous bubbling potion gradient of emerald, teal, deep amethyst, and chartreuse flowing seamlessly house to house.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.26,
                        "direction": "reverse",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#06b6d4",
                        "accent_color": "#9333ea",
                        "background_color": "#a3e635",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow2_skeleton_rave",
                "name": "Halloween Rainbow 2: Skeleton Dance Party",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Fast, punchy Rainbow 2 color blocks of bone white, neon purple, pumpkin orange, and cyber cyan.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.38,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f8fafc",
                        "secondary_color": "#a855f7",
                        "accent_color": "#f97316",
                        "background_color": "#00f5d4",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow1_full_spectrum",
                "name": "Halloween Rainbow 1: Haunted Full Spectrum",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Classic 360-degree Govee HSV Rainbow 1 spectrum gliding across all three houses with spooky dual-wave density.",
                "animation": {
                        "effect": "rainbow_wave",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#9333ea",
                        "accent_color": "#22c55e",
                        "background_color": "#000000",
                        "background_dim": 0.0,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "halloween_rainbow2_warlock_crystal",
                "name": "Halloween Rainbow 2: Warlock Crystal Bands",
                "category": "Halloween",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Shimmering crystal color blocks of mystic magenta, midnight blue, toxic lime, and fiery amber.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.22,
                        "direction": "reverse",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#d946ef",
                        "secondary_color": "#3b82f6",
                        "accent_color": "#84cc16",
                        "background_color": "#f59e0b",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_sleigh_ride",
                "name": "Santa's Sleigh Across the Street",
                "category": "Christmas",
                "badge": "AI \u2022 Holiday Magic",
                "description": "Rotating crimson, snow-white, and emerald candy-cane ribbons with a sparkling gold sleigh gliding House 1 -> 2 -> 3.",
                "animation": {
                        "effect": "christmas_magic",
                        "speed": 0.24,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#fbbf24",
                        "background_color": "#04120a",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_candy_cane",
                "name": "Peppermint Candy Cane Flow",
                "category": "Christmas",
                "badge": "AI \u2022 Festive",
                "description": "Silky candy-red, crisp snow-white, and holly-green chase flowing seamlessly from rooftop to rooftop.",
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#120306",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_frozen_aurora",
                "name": "Winter Wonderland & Falling Snow",
                "category": "Christmas",
                "badge": "AI \u2022 Snowfall",
                "description": "Glacier ice-blue and royal-blue northern lights with synchronized diamond-white snow sparkles across every eave.",
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#f8fafc",
                        "accent_color": "#3b82f6",
                        "background_color": "#020b18",
                        "background_dim": 0.1,
                        "tail_length": 0.24,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_nutcracker_marquee",
                "name": "Nutcracker Gold & Ruby Marquee",
                "category": "Christmas",
                "badge": "AI \u2022 Royal",
                "description": "Warm holiday gold, ruby red, and evergreen marquee lights dancing in lockstep across all three houses.",
                "animation": {
                        "effect": "theater_chase",
                        "speed": 0.18,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#dc2626",
                        "accent_color": "#059669",
                        "background_color": "#140802",
                        "background_dim": 0.1,
                        "tail_length": 0.2,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rudolph_dash",
                "name": "Rudolph's Glowing Red-Nose Dash",
                "category": "Christmas",
                "badge": "AI \u2022 Reindeer Run",
                "description": "Bright cherry-red leading nose followed by golden reindeer antlers and shimmering stardust leaping from roof to roof.",
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.34,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#10b981",
                        "background_color": "#080f08",
                        "background_dim": 0.08,
                        "tail_length": 0.34,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_north_pole_beacon",
                "name": "North Pole Beacon (From My House)",
                "category": "Christmas",
                "badge": "AI \u2022 Center-Out",
                "description": "Festive candy-red, snow-white, and evergreen waves radiating outward from My Middle House (#2) to both neighbors!",
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#ffffff",
                        "background_color": "#041008",
                        "background_dim": 0.1,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_grinch_heist",
                "name": "The Grinch Stole the Street Lights",
                "category": "Christmas",
                "badge": "AI \u2022 Dual Snake",
                "description": "Mischievous Grinch lime-green and Santa suit crimson snakes slithering from opposite houses and colliding in snowy sparks.",
                "animation": {
                        "effect": "cyber_snake",
                        "speed": 0.28,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#65a30d",
                        "secondary_color": "#ef4444",
                        "accent_color": "#fef08a",
                        "background_color": "#061004",
                        "background_dim": 0.08,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_polar_express",
                "name": "The Polar Express Steam Train",
                "category": "Christmas",
                "badge": "AI \u2022 3 Coaches",
                "description": "Three warm golden-lantern passenger coaches with frost-blue steam trails chugging steadily across all three homes.",
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fde047",
                        "accent_color": "#38bdf8",
                        "background_color": "#040814",
                        "background_dim": 0.1,
                        "tail_length": 0.22,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_gingerbread_village",
                "name": "Gingerbread & Gumdrop Village",
                "category": "Christmas",
                "badge": "AI \u2022 Sweet",
                "description": "Warm cinnamon amber, royal icing white, and sugar-plum magenta gumdrops twinkling across the three rooflines.",
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#d97706",
                        "secondary_color": "#ec4899",
                        "accent_color": "#22c55e",
                        "background_color": "#140904",
                        "background_dim": 0.12,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_arctic_blizzard",
                "name": "Arctic Blizzard & Frostbite Gust",
                "category": "Christmas",
                "badge": "AI \u2022 Snow Squall",
                "description": "Swirling sub-zero cyan and cobalt wind gusts with crystalline diamond-white snow-squall flashes sweeping the street.",
                "animation": {
                        "effect": "lightning_storm",
                        "speed": 0.36,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#06b6d4",
                        "secondary_color": "#3b82f6",
                        "accent_color": "#ffffff",
                        "background_color": "#020b18",
                        "background_dim": 0.12,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_yule_log_hearth",
                "name": "Cozy Christmas Eve Yule Log",
                "category": "Christmas",
                "badge": "AI \u2022 Fireside",
                "description": "Crackling chestnut-red, warm hearth-amber, and golden pine embers glowing across every roofline.",
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.24,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ea580c",
                        "secondary_color": "#f59e0b",
                        "accent_color": "#fef08a",
                        "background_color": "#140502",
                        "background_dim": 0.14,
                        "tail_length": 0.24,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_elf_workshop_ribbon",
                "name": "Santa's Workshop Gift-Wrap Wipe",
                "category": "Christmas",
                "badge": "AI \u2022 Progressive",
                "description": "Playful ribbon wipe wrapping Neighbor 1 -> My House -> Neighbor 2 in alternating bows of holly red, elf green, and gold.",
                "animation": {
                        "effect": "color_wipe",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#fbbf24",
                        "background_color": "#061008",
                        "background_dim": 0.08,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_star_of_bethlehem",
                "name": "Star of Bethlehem Silent Night",
                "category": "Christmas",
                "badge": "AI \u2022 Center Star",
                "description": "Radiant celestial gold and champagne starlight shining outward from My Middle House (#2) across a midnight-blue sky.",
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.18,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fde047",
                        "secondary_color": "#f59e0b",
                        "accent_color": "#38bdf8",
                        "background_color": "#020617",
                        "background_dim": 0.14,
                        "tail_length": 0.3,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_sugar_plum_fairy",
                "name": "Dance of the Sugar Plum Fairy",
                "category": "Christmas",
                "badge": "AI \u2022 Enchanted",
                "description": "Whimsical lavender, rose-pink, and silver-tiara fairy dust dancing and twinkling across all three houses.",
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.26,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#c084fc",
                        "secondary_color": "#f472b6",
                        "accent_color": "#ffffff",
                        "background_color": "#0f0418",
                        "background_dim": 0.1,
                        "tail_length": 0.24,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_mistletoe_harmony",
                "name": "Under the Mistletoe Harmonic Glow",
                "category": "Christmas",
                "badge": "AI \u2022 Lockstep",
                "description": "Deep synchronized pine-emerald and holly-berry crimson breathing glow uniting all three homes in calm holiday warmth.",
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "parallel_zones",
                        "primary_color": "#10b981",
                        "secondary_color": "#ef4444",
                        "accent_color": "#fde047",
                        "background_color": "#041208",
                        "background_dim": 0.1,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow1_classic_C9",
                "name": "Christmas Rainbow 1: Vintage C9 Bulb Flow",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Govee Rainbow 1 style: 100%-lit nostalgic C9 holiday gradient of ruby red, emerald green, royal blue, and warm amber gold gliding across all 3 houses.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#3b82f6",
                        "background_color": "#f59e0b",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow2_c9_blocks",
                "name": "Christmas Rainbow 2: Classic C9 Color Blocks",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Govee Rainbow 2 style: Crisp marching C9 holiday blocks of cherry red, pine green, sapphire blue, and warm gold stepping cleanly roof to roof.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#2563eb",
                        "background_color": "#fbbf24",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow1_peppermint_silk",
                "name": "Christmas Rainbow 1: Peppermint Ribbon Silk",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Gapless, buttery-smooth Govee Rainbow 1 gradient of candy-cane red, pure snow white, holly emerald, and champagne gold.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.24,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#00e676",
                        "background_color": "#fde047",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow2_candy_shoppe",
                "name": "Christmas Rainbow 2: North Pole Candy Shoppe",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Vivid Govee Rainbow 2 color bands of peppermint red, frosting white, mint green, and gumdrop magenta marching across all three homes.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff1744",
                        "secondary_color": "#ffffff",
                        "accent_color": "#10b981",
                        "background_color": "#ec4899",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow1_arctic_aurora",
                "name": "Christmas Rainbow 1: Lapland Aurora Ribbon",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "100%-lit northern lights ribbon blending glacier cyan, aurora emerald, royal sapphire, and polar violet across the street.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.18,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#10b981",
                        "accent_color": "#3b82f6",
                        "background_color": "#8b5cf6",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow2_glacier_blocks",
                "name": "Christmas Rainbow 2: Crystal Icicle Blocks",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Stepped Govee Rainbow 2 blocks of diamond white, sky blue, deep cobalt, and frost teal with subtle crystal shimmer.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ffffff",
                        "secondary_color": "#38bdf8",
                        "accent_color": "#1d4ed8",
                        "background_color": "#2dd4bf",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow1_royal_nativity",
                "name": "Christmas Rainbow 1: Three Kings Royal Gold",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Luxurious continuous gradient of frankincense gold, royal purple, ruby crimson, and warm starlight white.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.18,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#7e22ce",
                        "accent_color": "#dc2626",
                        "background_color": "#fef3c7",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow2_toy_soldier",
                "name": "Christmas Rainbow 2: Toy Soldier Parade",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Crisp marching Rainbow 2 blocks of regiment red, trumpet gold, uniform blue, and emerald green across all three rooflines.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#dc2626",
                        "secondary_color": "#facc15",
                        "accent_color": "#2563eb",
                        "background_color": "#059669",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow1_pastel_macaron",
                "name": "Christmas Rainbow 1: Pastel Sugar-Plum Flow",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Soft, dreamy Govee Rainbow 1 gradient of rose pink, lavender, mint cream, and ice blue flowing down the street.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f472b6",
                        "secondary_color": "#c084fc",
                        "accent_color": "#6ee7b7",
                        "background_color": "#7dd3fc",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow2_jingle_bell_rock",
                "name": "Christmas Rainbow 2: Jingle Bell Rock Party",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Upbeat, fast-stepping Rainbow 2 color blocks of holly red, lime green, electric cyan, and gold bouncing across the houses.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.36,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#22c55e",
                        "accent_color": "#00f5d4",
                        "background_color": "#facc15",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow1_full_spectrum",
                "name": "Christmas Rainbow 1: Holiday Prism Spectrum",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 1 Style",
                "description": "Full 360-degree Govee Rainbow 1 HSV spectrum ribbon wrapping all three houses in continuous holiday color.",
                "animation": {
                        "effect": "rainbow_wave",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#10b981",
                        "accent_color": "#fbbf24",
                        "background_color": "#000000",
                        "background_dim": 0.0,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_rainbow2_wreath_and_holly",
                "name": "Christmas Rainbow 2: Evergreen & Berry Bands",
                "category": "Christmas",
                "badge": "AI \u2022 Rainbow 2 Style",
                "description": "Rich Govee Rainbow 2 bands of deep forest pine, bright holly green, crimson berry, and warm candle gold.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.2,
                        "direction": "reverse",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#059669",
                        "secondary_color": "#22c55e",
                        "accent_color": "#dc2626",
                        "background_color": "#fbbf24",
                        "background_dim": 0.15,
                        "tail_length": 0.25,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "xmas_frost_vs_flame",
                "name": "Jack Frost vs. Heat Miser Clash",
                "category": "Christmas",
                "badge": "AI \u2022 Epic Clash",
                "description": "Glacier ice-blue and blazing holiday-red waves racing from opposite ends of the block and bursting into gold at the middle house!",
                "animation": {
                        "effect": "cyber_snake",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#ef4444",
                        "accent_color": "#fde047",
                        "background_color": "#050914",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "diwali_golden_diya",
                "name": "Golden Diya Oil Lamp Cascade",
                "category": "Diwali",
                "badge": "AI \u2022 Shubh Deepavali",
                "description": "Warm saffron gold, glowing amber, and vermilion diya oil-lamp shimmer cascading across all three homes.",
                "animation": {
                        "effect": "diwali_festival",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f59e0b",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#ef4444",
                        "background_color": "#170902",
                        "background_dim": 0.14,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "diwali_rangoli_wave",
                "name": "Royal Rangoli Jewel Wave",
                "category": "Diwali",
                "badge": "AI \u2022 Rangoli",
                "description": "Vibrant rani pink, marigold orange, and peacock turquoise silk wave inspired by traditional festival rangoli art.",
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.26,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ec4899",
                        "secondary_color": "#f97316",
                        "accent_color": "#06b6d4",
                        "background_color": "#140410",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "diwali_firecracker_sparkle",
                "name": "Festival of Lights Sparkle",
                "category": "Diwali",
                "badge": "AI \u2022 Phuljhari",
                "description": "Dazzling golden sparkler bursts over a royal magenta and violet festival wave.",
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fde047",
                        "secondary_color": "#d946ef",
                        "accent_color": "#8b5cf6",
                        "background_color": "#11051c",
                        "background_dim": 0.1,
                        "tail_length": 0.24,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "diwali_aarti_flame",
                "name": "Sacred Aarti Flame Flow",
                "category": "Diwali",
                "badge": "AI \u2022 Aarti",
                "description": "Warm flickering temple flame and golden ember glow radiating across the entire street.",
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.28,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ea580c",
                        "secondary_color": "#facc15",
                        "accent_color": "#dc2626",
                        "background_color": "#180600",
                        "background_dim": 0.14,
                        "tail_length": 0.24,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "center_supernova",
                "name": "Middle House Supernova Blast",
                "category": "Center-Out (My House)",
                "badge": "AI \u2022 Middle -> Out",
                "description": "Symmetrical neon shockwave originating at My House (#2 in the middle) and blasting outward to both neighbors simultaneously!",
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.28,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#8b5cf6",
                        "accent_color": "#ff007f",
                        "background_color": "#050714",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "center_golden_ripple",
                "name": "Heart of the Street Golden Ripple",
                "category": "Center-Out (My House)",
                "badge": "AI \u2022 Symmetrical",
                "description": "Warm golden-amber waves radiating outward from the center of My House into Neighbor 1 (Left) and Neighbor 2 (Right).",
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.22,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#f97316",
                        "accent_color": "#ffffff",
                        "background_color": "#120902",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "center_serpent_clash",
                "name": "Twin Serpent Collision at My House",
                "category": "Center-Out (My House)",
                "badge": "AI \u2022 Dual Clash",
                "description": "Opposing neon green and electric blue serpents racing from Neighbor 1 and Neighbor 2 to collide in a white-hot burst at My House!",
                "animation": {
                        "effect": "cyber_snake",
                        "speed": 0.28,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#10b981",
                        "secondary_color": "#3b82f6",
                        "accent_color": "#f43f5e",
                        "background_color": "#040814",
                        "background_dim": 0.08,
                        "tail_length": 0.24,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "cyber_chase",
                "name": "Cyberpunk 3-House Chase",
                "category": "Cyber & Party",
                "badge": "AI \u2022 Signature",
                "description": "Silky neon cyan -> violet -> magenta chase flowing House 1 -> House 2 -> House 3 with equal-time house compensation.",
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#00f5d4",
                        "secondary_color": "#7b2cbf",
                        "accent_color": "#ff007f",
                        "background_color": "#060814",
                        "background_dim": 0.08,
                        "tail_length": 0.24,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "dual_comet_pingpong",
                "name": "Twin Comet Bounce",
                "category": "Cyber & Party",
                "badge": "AI \u2022 Ping-Pong",
                "description": "High-energy white-hot comets bouncing back and forth across all three houses.",
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.32,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#6366f1",
                        "accent_color": "#f43f5e",
                        "background_color": "#05070f",
                        "background_dim": 0.05,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "seamless_rainbow",
                "name": "Seamless Neighborhood Rainbow",
                "category": "Cyber & Party",
                "badge": "AI \u2022 Spectrum",
                "description": "Continuous spectrum wave spanning all houses with zero seam or phase drift.",
                "animation": {
                        "effect": "rainbow_wave",
                        "speed": 0.2,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff0055",
                        "secondary_color": "#00ffcc",
                        "accent_color": "#ffee00",
                        "background_color": "#000000",
                        "background_dim": 0.0,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "harmonic_pulse",
                "name": "Lockstep Breathing Pulse",
                "category": "Cyber & Party",
                "badge": "AI \u2022 Ambient",
                "description": "Deep synchronized breathing glow across all houses simultaneously.",
                "animation": {
                        "effect": "breathing_pulse",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "parallel_zones",
                        "primary_color": "#10b981",
                        "secondary_color": "#3b82f6",
                        "accent_color": "#8b5cf6",
                        "background_color": "#030712",
                        "background_dim": 0.06,
                        "tail_length": 0.25,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "seahawks_gameday",
                "name": "Seahawks 12th Man Touchdown",
                "category": "Celebrations",
                "badge": "AI \u2022 Game Day",
                "description": "Action Green, College Navy, and Wolf Grey stadium wave roaring across all three houses for game day!",
                "animation": {
                        "effect": "multi_house_chase",
                        "speed": 0.34,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#69be28",
                        "secondary_color": "#002244",
                        "accent_color": "#a5acaf",
                        "background_color": "#001122",
                        "background_dim": 0.12,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "july4_fireworks",
                "name": "4th of July / New Year Skyrocket",
                "category": "Celebrations",
                "badge": "AI \u2022 Fireworks",
                "description": "Patriotic crimson, starlight white, and liberty blue skyrockets bursting across the rooflines.",
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#ffffff",
                        "accent_color": "#3b82f6",
                        "background_color": "#040816",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 3,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "holiday_marquee",
                "name": "Synchronized Theater Marquee",
                "category": "Celebrations",
                "badge": "AI \u2022 Marquee",
                "description": "Crisp gold & crimson marquee lights compensated for uneven controller lengths.",
                "animation": {
                        "effect": "theater_chase",
                        "speed": 0.18,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fbbf24",
                        "secondary_color": "#ef4444",
                        "accent_color": "#ffffff",
                        "background_color": "#120604",
                        "background_dim": 0.1,
                        "tail_length": 0.2,
                        "pulse_count": 2,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "hearth_fire",
                "name": "Neighborhood Bonfire",
                "category": "Celebrations",
                "badge": "AI \u2022 Warm Hearth",
                "description": "Organic flickering ember & flame wave across all rooflines.",
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.3,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff5500",
                        "secondary_color": "#ffaa00",
                        "accent_color": "#ffee88",
                        "background_color": "#140400",
                        "background_dim": 0.12,
                        "tail_length": 0.22,
                        "pulse_count": 1,
                        "supersample": True
                },
                "scene_source": "ai_custom",
                "subcategory": "AI & Custom"
        },
        {
                "id": "ai_halloween_upside_down_rift",
                "name": "Stranger Upside-Down Rift",
                "category": "Halloween",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Sci-Fi Horror",
                "description": "Dimensional crimson lightning and deep shadow-portal indigo tearing across House 1 -> 2 -> 3.",
                "animation": {
                        "effect": "lightning_storm",
                        "speed": 0.36,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#6366f1",
                        "accent_color": "#38bdf8",
                        "background_color": "#09020a",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 3,
                        "supersample": True
                }
        },
        {
                "id": "ai_halloween_proton_stream",
                "name": "Ghostbusters Proton Stream",
                "category": "Halloween",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Plasma",
                "description": "Crossed high-energy proton-pack orange-red beams with electric blue and Slimer green containment arcs.",
                "animation": {
                        "effect": "cyber_snake",
                        "speed": 0.38,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff4500",
                        "secondary_color": "#00f5d4",
                        "accent_color": "#84cc16",
                        "background_color": "#050814",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "ai_halloween_salem_blood_moon",
                "name": "Salem Coven Blood Eclipse",
                "category": "Halloween",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Coven",
                "description": "Deep eclipse crimson, witchcraft violet, and candlelit gold shockwaves radiating from the middle house.",
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.24,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#dc2626",
                        "secondary_color": "#7e22ce",
                        "accent_color": "#fbbf24",
                        "background_color": "#110308",
                        "background_dim": 0.1,
                        "tail_length": 0.3,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "ai_halloween_cyber_jack",
                "name": "Cyberpunk Jack-O'-Lantern 2099",
                "category": "Halloween",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Neon",
                "description": "Hyper-saturated neon orange, ultraviolet magenta, and acid green Govee Rainbow 2 blocks.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.32,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff6b00",
                        "secondary_color": "#f43f5e",
                        "accent_color": "#39ff14",
                        "background_color": "#080312",
                        "background_dim": 0.09,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                }
        },
        {
                "id": "ai_halloween_banshee_mist",
                "name": "Banshee Graveyard Fog",
                "category": "Halloween",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Haunt",
                "description": "Silky spectral cyan, ghostly lavender, and pale moonlight breathing wave across all three rooflines.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.19,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#2dd4bf",
                        "secondary_color": "#a855f7",
                        "accent_color": "#e2e8f0",
                        "background_color": "#040d12",
                        "background_dim": 0.1,
                        "tail_length": 0.32,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "ai_xmas_griswold_overload",
                "name": "Griswold 25,000-Bulb Overload",
                "category": "Christmas",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Classic",
                "description": "Dazzling high-density C9 warm white, ruby red, emerald green, and royal gold theater sparkle.",
                "animation": {
                        "effect": "sparkle_twinkle",
                        "speed": 0.35,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#fef08a",
                        "secondary_color": "#ef4444",
                        "accent_color": "#10b981",
                        "background_color": "#0d0804",
                        "background_dim": 0.12,
                        "tail_length": 0.24,
                        "pulse_count": 3,
                        "supersample": True
                }
        },
        {
                "id": "ai_xmas_krampus_vs_santa",
                "name": "Krampus vs. Santa Showdown",
                "category": "Christmas",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Duel",
                "description": "Opposing icy North Pole cyan-white and fiery underworld crimson-gold serpents clashing at your middle house.",
                "animation": {
                        "effect": "cyber_snake",
                        "speed": 0.34,
                        "direction": "pingpong",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ef4444",
                        "secondary_color": "#38bdf8",
                        "accent_color": "#fbbf24",
                        "background_color": "#070b16",
                        "background_dim": 0.09,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "ai_xmas_elsa_ice_palace",
                "name": "Frozen Ice Palace Crystal",
                "category": "Christmas",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Glacial",
                "description": "Diamond-white, arctic cyan, and sapphire-violet crystal waves radiating outward from your house.",
                "animation": {
                        "effect": "center_out_shockwave",
                        "speed": 0.25,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#38bdf8",
                        "secondary_color": "#e0f2fe",
                        "accent_color": "#818cf8",
                        "background_color": "#030b18",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "ai_xmas_hot_cocoa_hearth",
                "name": "Cinnamon & Fireside Cocoa",
                "category": "Christmas",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Cozy",
                "description": "Warm marshmallow cream, cinnamon amber, and crackling hearth crimson embers.",
                "animation": {
                        "effect": "fire_sparkle",
                        "speed": 0.22,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#f97316",
                        "secondary_color": "#fde68a",
                        "accent_color": "#dc2626",
                        "background_color": "#120602",
                        "background_dim": 0.1,
                        "tail_length": 0.26,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "ai_xmas_nutcracker_finale",
                "name": "Nutcracker Sugar-Plum Finale",
                "category": "Christmas",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Ballet",
                "description": "Regal velvet crimson, imperial gold, and sugar-plum violet stepped Govee Rainbow 2 blocks.",
                "animation": {
                        "effect": "govee_rainbow2",
                        "speed": 0.28,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#dc2626",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#a855f7",
                        "background_color": "#0c0410",
                        "background_dim": 0.09,
                        "tail_length": 0.25,
                        "pulse_count": 3,
                        "supersample": True
                }
        },
        {
                "id": "ai_diwali_lotus_mandala",
                "name": "Golden Lotus Mandala",
                "category": "Diwali",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Mandala",
                "description": "Luminous lotus pink, saffron gold, and royal turquoise silk gradient flowing across all houses.",
                "animation": {
                        "effect": "govee_rainbow1",
                        "speed": 0.24,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ec4899",
                        "secondary_color": "#fbbf24",
                        "accent_color": "#06b6d4",
                        "background_color": "#12040c",
                        "background_dim": 0.1,
                        "tail_length": 0.28,
                        "pulse_count": 2,
                        "supersample": True
                }
        },
        {
                "id": "ai_cyber_tokyo_drift",
                "name": "Neo-Tokyo Midnight Drift",
                "category": "Cyber & Party",
                "subcategory": "AI & Custom",
                "scene_source": "ai_custom",
                "badge": "AI \u2022 Synthwave",
                "description": "High-velocity synthwave laser magenta, electric cyan, and sunset orange comets.",
                "animation": {
                        "effect": "comet_meteor",
                        "speed": 0.42,
                        "direction": "forward",
                        "mapping_mode": "house_normalized",
                        "primary_color": "#ff007f",
                        "secondary_color": "#00f5d4",
                        "accent_color": "#f97316",
                        "background_color": "#050414",
                        "background_dim": 0.08,
                        "tail_length": 0.26,
                        "pulse_count": 3,
                        "supersample": True
                }
        }
]

    BURST_PROFILES: Dict[str, Dict[str, Any]] = {
        "touchdown": {
            "label": "Seahawks Touchdown Blitz",
            "animation": {
                "effect": "center_out_shockwave",
                "speed": 0.95,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#69be28",
                "secondary_color": "#002244",
                "accent_color": "#ffffff",
                "background_color": "#00152b",
                "background_dim": 0.18,
                "tail_length": 0.30,
                "pulse_count": 3,
                "intensity": 100,
                "supersample": True,
            },
        },
        "strobe": {
            "label": "Hyper Neon Party Burst",
            "animation": {
                "effect": "theater_chase",
                "speed": 1.15,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ffffff",
                "secondary_color": "#00f5d4",
                "accent_color": "#ff007f",
                "background_color": "#080214",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 4,
                "intensity": 100,
                "supersample": True,
            },
        },
        "lightning": {
            "label": "Rolling Megavolt Storm Burst",
            "animation": {
                "effect": "lightning_storm",
                "speed": 1.05,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#e0f2fe",
                "secondary_color": "#38bdf8",
                "accent_color": "#a855f7",
                "background_color": "#030712",
                "background_dim": 0.12,
                "tail_length": 0.32,
                "pulse_count": 3,
                "intensity": 100,
                "supersample": True,
            },
        },
        "new_year": {
            "label": "Grand Finale Skyrocket Burst",
            "animation": {
                "effect": "comet_meteor",
                "speed": 0.90,
                "direction": "pingpong",
                "mapping_mode": "house_normalized",
                "primary_color": "#fbbf24",
                "secondary_color": "#ef4444",
                "accent_color": "#38bdf8",
                "background_color": "#090414",
                "background_dim": 0.12,
                "tail_length": 0.30,
                "pulse_count": 4,
                "intensity": 100,
                "supersample": True,
            },
        },
    }

    def __init__(self, store: ConfigStore, driver: GoveeProtocolDriver) -> None:
        self.store = store
        self.driver = driver

        now_mono = time.monotonic_ns() / 1e9
        init_cfg = self.store.get()
        self._engine_start_mono = now_mono
        self._anchor_mono = now_mono
        self._anchor_phase = 0.0
        self._last_speed = init_cfg.animation.speed
        self._paused_at_mono: Optional[float] = None if init_cfg.animation.running else now_mono
        self._stopped_blackout: bool = (not init_cfg.animation.running) and bool(
            init_cfg.animation.blackout_on_stop
        )

        self._task: Optional[asyncio.Task] = None
        self._stop_event = asyncio.Event()

        # Playlist, Schedule & Celebration Burst state
        self.active_preset_id: str = "cyber_chase"
        self._playlist_index: int = 0
        self._last_playlist_switch_mono: float = now_mono
        self._last_schedule_check_mono: float = 0.0
        self._last_schedule_minute_key: str = ""
        self._last_schedule_action: str = ""

        self._pre_burst_animation: Optional[AnimationConfig] = None
        self._burst_ends_at_mono: Optional[float] = None
        self._burst_label: str = ""
        self._burst_task: Optional[asyncio.Task] = None

        # Latest rendered frame state for WebSocket broadcast & REST snapshot
        self.latest_segments: List[SegmentRenderPoint] = []
        self.latest_controller_colors: Dict[str, str] = {}
        self.frame_counter: int = 0
        self.measured_fps: float = 0.0
        self.clock_drift_ms: float = 0.0
        self.current_phase: float = 0.0
        self.active_house_id: str = ""
        self.active_house_name: str = ""

        self._ws_listeners: List[Callable[[Dict[str, Any]], Coroutine[Any, Any, None]]] = []

    def register_ws_listener(self, cb: Callable[[Dict[str, Any]], Coroutine[Any, Any, None]]) -> None:
        self._ws_listeners.append(cb)

    def unregister_ws_listener(self, cb: Callable[[Dict[str, Any]], Coroutine[Any, Any, None]]) -> None:
        if cb in self._ws_listeners:
            self._ws_listeners.remove(cb)

    def pause_clock(self, now_mono: Optional[float] = None, blackout: Optional[bool] = None) -> float:
        """
        Freeze `_anchor_phase` at the current monotonic timestamp so phase stops advancing
        while `animation.running == False`.
        """
        if now_mono is None:
            now_mono = time.monotonic_ns() / 1e9
        if self._paused_at_mono is None:
            self._anchor_phase = self._anchor_phase + (now_mono - self._anchor_mono) * self._last_speed
            self._anchor_mono = now_mono
            self._paused_at_mono = now_mono
        if blackout is not None:
            self._stopped_blackout = blackout
        self.current_phase = self._anchor_phase % 1.0
        self.measured_fps = 0.0
        return self.current_phase

    def resume_clock(self, now_mono: Optional[float] = None) -> float:
        """
        Resume the monotonic clock from the frozen `_anchor_phase` with zero phase jump.
        """
        if now_mono is None:
            now_mono = time.monotonic_ns() / 1e9
        if self._paused_at_mono is not None:
            self._anchor_mono = now_mono
            self._paused_at_mono = None
        self._stopped_blackout = False
        self.current_phase = self._anchor_phase % 1.0
        return self.current_phase

    def get_unwrapped_phase(
        self,
        now_mono: Optional[float] = None,
        speed: Optional[float] = None,
        running: Optional[bool] = None,
    ) -> float:
        """
        Return the exact monotonic unwrapped phase.
        When `running == False`, freezes `_anchor_phase` and does NOT advance phase.
        When speed changes, `_anchor_phase` and `_anchor_mono` are re-anchored so phase is C0-continuous
        and never drifts over arbitrary uptime.
        """
        if now_mono is None:
            now_mono = time.monotonic_ns() / 1e9
        cfg = self.store.get()
        is_running = cfg.animation.running if running is None else running
        spd = speed if speed is not None else cfg.animation.speed

        if not is_running:
            if self._paused_at_mono is None:
                self._anchor_phase = self._anchor_phase + (now_mono - self._anchor_mono) * self._last_speed
                self._anchor_mono = now_mono
                self._paused_at_mono = now_mono
            self._last_speed = spd
            return self._anchor_phase

        if self._paused_at_mono is not None:
            self._anchor_mono = now_mono
            self._paused_at_mono = None
            self._stopped_blackout = False

        if abs(spd - self._last_speed) > 1e-6:
            self._anchor_phase = self._anchor_phase + (now_mono - self._anchor_mono) * self._last_speed
            self._anchor_mono = now_mono
            self._last_speed = spd
        return self._anchor_phase + (now_mono - self._anchor_mono) * spd

    def reset_clock(self) -> None:
        now_mono = time.monotonic_ns() / 1e9
        self._anchor_mono = now_mono
        self._anchor_phase = 0.0
        self._engine_start_mono = now_mono
        if self._paused_at_mono is not None:
            self._paused_at_mono = now_mono
        self.current_phase = 0.0

    def render_frame_at(
        self, config: SystemConfig, now_mono: Optional[float] = None
    ) -> Tuple[List[SegmentRenderPoint], Dict[Tuple[str, str], List[RGBTuple]]]:
        """
        Compute the RGB colors for every segment across all houses at monotonic timestamp `now_mono`.
        When `not config.animation.running`:
        - Freezes phase and does NOT advance `self.current_phase` or `self.frame_counter`.
        - If `config.animation.blackout_on_stop` is True, renders all segments in stopped/off state
          (`r=0, g=0, b=0, hex_color="#000000"`).
        - If `config.animation.blackout_on_stop` is False (paused), renders the frozen frame at `_anchor_phase`.
        """
        if now_mono is None:
            now_mono = time.monotonic_ns() / 1e9

        anim = config.animation
        unwrapped_phase = self.get_unwrapped_phase(now_mono, anim.speed, running=anim.running)
        if not anim.running:
            effective_mono = self._paused_at_mono if self._paused_at_mono is not None else now_mono
            elapsed_sec = max(0.0, effective_mono - self._engine_start_mono)
        else:
            elapsed_sec = now_mono - self._engine_start_mono
        self.current_phase = unwrapped_phase % 1.0

        slots = build_virtual_strip_map(config)
        if not slots:
            self.latest_segments = []
            self.latest_controller_colors = {}
            self.active_house_id = ""
            self.active_house_name = ""
            return [], {}

        # If stopped with blackout enabled, render all segments off (#000000) immediately
        if not anim.running and anim.blackout_on_stop:
            rendered_points: List[SegmentRenderPoint] = []
            ordered_ctrl_colors: Dict[Tuple[str, str], List[RGBTuple]] = {}
            for slot in slots:
                rendered_points.append(
                    SegmentRenderPoint(
                        global_index=slot.global_index,
                        house_id=slot.house.id,
                        house_name=slot.house.name,
                        house_index=slot.house_index,
                        controller_id=slot.controller.id,
                        controller_name=slot.controller.name,
                        controller_index=slot.controller_index,
                        segment_index=slot.segment_index,
                        wall=slot.wall,
                        normalized_pos=round(slot.normalized_pos, 5),
                        normalized_width=round(slot.normalized_width, 5),
                        r=0,
                        g=0,
                        b=0,
                        hex_color="#000000",
                    )
                )
                ordered_ctrl_colors.setdefault((slot.house.id, slot.controller.id), []).append((0, 0, 0))
                self.latest_controller_colors[slot.controller.id] = "#000000"

            self.active_house_id = ""
            self.active_house_name = "Stopped"
            self.latest_segments = rendered_points
            return rendered_points, ordered_ctrl_colors

        primary = hex_to_rgb(anim.primary_color)
        secondary = hex_to_rgb(anim.secondary_color)
        accent = hex_to_rgb(anim.accent_color)
        bg_raw = hex_to_rgb(anim.background_color)
        bg_scaled = scale_rgb(bg_raw, anim.background_dim)

        intensity_scale = max(0.01, min(1.0, anim.intensity / 100.0))
        sub_offsets = (0.0,)

        rendered_points: List[SegmentRenderPoint] = []
        controller_segments: Dict[Tuple[str, str], List[Tuple[int, RGBTuple]]] = {}

        # Determine which house currently holds the primary chase head
        if anim.direction == DirectionMode.PINGPONG:
            cyc = unwrapped_phase % 2.0
            head_norm = cyc if cyc <= 1.0 else (2.0 - cyc)
        elif anim.direction == DirectionMode.REVERSE:
            head_norm = (-unwrapped_phase) % 1.0
        else:
            head_norm = unwrapped_phase % 1.0

        probe_norm = (0.50 + 0.50 * head_norm) if anim.effect == EffectType.CENTER_OUT_SHOCKWAVE else head_norm
        closest_slot = min(slots, key=lambda sl: abs(sl.normalized_pos - probe_norm))
        self.active_house_id = closest_slot.house.id
        self.active_house_name = closest_slot.house.name

        for slot in slots:
            acc_r = 0.0
            acc_g = 0.0
            acc_b = 0.0
            for off in sub_offsets:
                sample_x = (slot.normalized_pos + off * slot.normalized_width) % 1.0
                sr, sg, sb = evaluate_effect_at_point(
                    sample_x,
                    unwrapped_phase,
                    elapsed_sec,
                    anim,
                    primary,
                    secondary,
                    accent,
                    bg_scaled,
                )
                acc_r += sr
                acc_g += sg
                acc_b += sb

            n_samples = len(sub_offsets)
            ctrl_bri = (
                (slot.controller.brightness_override / 100.0)
                if slot.controller.brightness_override is not None
                else intensity_scale
            )
            if getattr(anim, "zone_mode", "all_segments") == "front_only_quiet_sides" and slot.wall != "front":
                ctrl_bri *= 0.14
            final_r = max(0, min(255, round((acc_r / n_samples) * ctrl_bri)))
            final_g = max(0, min(255, round((acc_g / n_samples) * ctrl_bri)))
            final_b = max(0, min(255, round((acc_b / n_samples) * ctrl_bri)))
            rgb = (final_r, final_g, final_b)

            rendered_points.append(
                SegmentRenderPoint(
                    global_index=slot.global_index,
                    house_id=slot.house.id,
                    house_name=slot.house.name,
                    house_index=slot.house_index,
                    controller_id=slot.controller.id,
                    controller_name=slot.controller.name,
                    controller_index=slot.controller_index,
                    segment_index=slot.segment_index,
                    wall=slot.wall,
                    normalized_pos=round(slot.normalized_pos, 5),
                    normalized_width=round(slot.normalized_width, 5),
                    r=final_r,
                    g=final_g,
                    b=final_b,
                    hex_color=rgb_to_hex(rgb),
                )
            )
            controller_segments.setdefault((slot.house.id, slot.controller.id), []).append(
                (slot.segment_index, rgb)
            )

        # Sort each controller's segments by physical segment_index for hardware dispatch
        ordered_ctrl_colors: Dict[Tuple[str, str], List[RGBTuple]] = {}
        for key, indexed_list in controller_segments.items():
            indexed_list.sort(key=lambda item: item[0])
            ordered_ctrl_colors[key] = [rgb for _, rgb in indexed_list]
            rep = compute_representative_controller_color(ordered_ctrl_colors[key])
            self.latest_controller_colors[key[1]] = rgb_to_hex(rep)

        self.latest_segments = rendered_points
        return rendered_points, ordered_ctrl_colors

    async def start(self) -> None:
        if self._task is not None and not self._task.done():
            return
        self._stop_event.clear()
        self._task = asyncio.create_task(self._run_master_loop(), name="govee-master-clock")
        logger.info("Started Govee Master Animation Clock loop")

    async def stop(self) -> None:
        self._stop_event.set()
        if self._burst_task is not None and not self._burst_task.done():
            self._burst_task.cancel()
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

    def is_burst_active(self, now_mono: Optional[float] = None) -> bool:
        if self._burst_ends_at_mono is None:
            return False
        if now_mono is None:
            now_mono = time.monotonic_ns() / 1e9
        return now_mono < self._burst_ends_at_mono

    async def restore_from_burst(self) -> Optional[SystemConfig]:
        """Restore the pre-burst AnimationConfig after a celebration burst finishes."""
        if self._pre_burst_animation is None:
            self._burst_ends_at_mono = None
            self._burst_label = ""
            return None
        restored_anim = self._pre_burst_animation.model_copy(deep=True)
        self._pre_burst_animation = None
        self._burst_ends_at_mono = None
        self._burst_label = ""

        cfg = self.store.get()
        cfg.animation = restored_anim
        if restored_anim.running:
            self.resume_clock()
        else:
            self.pause_clock(blackout=restored_anim.blackout_on_stop)
        self.driver._last_sent_rgb.clear()
        saved = self.store.save(cfg)
        if not restored_anim.running and restored_anim.blackout_on_stop:
            await self.driver.blackout_all_controllers(saved, turn_off=True)
        await self.broadcast_snapshot(saved)
        return saved

    async def trigger_burst(
        self,
        preset_id: Optional[str] = None,
        burst_type: Optional[str] = None,
        duration_sec: float = 12.0,
    ) -> Dict[str, Any]:
        """
        Temporarily run a high-speed celebratory effect across all 3 houses for `duration_sec`,
        then automatically restore the previous AnimationConfig.
        """
        duration = max(1.0, min(120.0, float(duration_sec or 12.0)))
        cfg = self.store.get()

        # Save original animation only if not already in a burst
        if self._pre_burst_animation is None:
            self._pre_burst_animation = cfg.animation.model_copy(deep=True)

        if self._burst_task is not None and not self._burst_task.done():
            self._burst_task.cancel()

        merged = cfg.animation.model_dump()
        label = "Street Celebration Burst"

        btype_key = (burst_type or preset_id or "touchdown").strip().lower()
        preset_match = next(
            (p for p in self.PRESETS if p["id"].lower() == (preset_id or burst_type or "").strip().lower()),
            None,
        )

        if preset_match is not None:
            merged.update(preset_match["animation"])
            merged["speed"] = min(2.5, max(0.75, float(preset_match["animation"].get("speed", 0.35)) * 2.4))
            merged["intensity"] = 100
            label = f"Burst: {preset_match['name']}"
        elif btype_key in self.BURST_PROFILES:
            prof = self.BURST_PROFILES[btype_key]
            merged.update(prof["animation"])
            label = prof["label"]
        else:
            prof = self.BURST_PROFILES["touchdown"]
            merged.update(prof["animation"])
            label = prof["label"]

        merged["running"] = True
        cfg.animation = AnimationConfig.model_validate(merged)

        now_mono = time.monotonic_ns() / 1e9
        self._burst_ends_at_mono = now_mono + duration
        self._burst_label = label
        self.resume_clock(now_mono)
        self.driver._last_sent_rgb.clear()
        saved = self.store.save(cfg)
        snapshot = await self.broadcast_snapshot(saved)

        async def _auto_restore() -> None:
            try:
                await asyncio.sleep(duration)
                await self.restore_from_burst()
            except asyncio.CancelledError:
                pass

        self._burst_task = asyncio.create_task(_auto_restore(), name="govee-burst-restore")
        return {
            "status": "burst_started",
            "label": label,
            "duration_sec": duration,
            "animation": saved.animation.model_dump(),
            "live_state": snapshot,
        }

    def advance_playlist_if_due(self, now_mono: Optional[float] = None) -> Optional[str]:
        """
        If `playlist.enabled` and `animation.running` (and not in a temporary burst),
        advance to the next preset in `playlist.preset_ids` when `interval_sec` has elapsed.
        """
        if now_mono is None:
            now_mono = time.monotonic_ns() / 1e9
        if self.is_burst_active(now_mono):
            return None

        cfg = self.store.get()
        if not cfg.playlist.enabled or not cfg.animation.running:
            self._last_playlist_switch_mono = now_mono
            return None

        valid_ids = [
            pid
            for pid in cfg.playlist.preset_ids
            if any(p["id"] == pid for p in self.PRESETS)
        ]
        if not valid_ids:
            return None

        interval = max(5, int(cfg.playlist.interval_sec))
        if (now_mono - self._last_playlist_switch_mono) < interval:
            return None

        self._last_playlist_switch_mono = now_mono
        if self.active_preset_id in valid_ids:
            curr_idx = valid_ids.index(self.active_preset_id)
            next_idx = (curr_idx + 1) % len(valid_ids)
        else:
            next_idx = self._playlist_index % len(valid_ids)

        self._playlist_index = next_idx
        next_preset_id = valid_ids[next_idx]
        preset = next((p for p in self.PRESETS if p["id"] == next_preset_id), None)
        if preset is None:
            return None

        merged = cfg.animation.model_dump()
        merged.update(preset["animation"])
        merged["running"] = True
        cfg.animation = AnimationConfig.model_validate(merged)
        self.active_preset_id = next_preset_id
        self.driver._last_sent_rgb.clear()
        self.store.save(cfg)
        logger.info("Playlist Jukebox rotated to preset '%s'", next_preset_id)
        return next_preset_id

    def compute_schedule_status(
        self,
        sched: Optional[ScheduleConfig] = None,
        now_dt: Optional[dt.datetime] = None,
    ) -> Dict[str, Any]:
        if sched is None:
            sched = self.store.get().schedule
        return compute_schedule_status(
            sched=sched,
            last_triggered_action=self._last_schedule_action,
            now_dt=now_dt,
        )

    async def apply_scheduled_start(
        self,
        cfg: Optional[SystemConfig] = None,
        trigger_label: str = "started",
    ) -> SystemConfig:
        """
        Power ON all enabled controllers across all enabled houses, activate `sched.preset_id`
        (including any `cfg.preset_overrides`), resume the master animation clock, save config,
        and broadcast the updated snapshot.
        """
        if cfg is None:
            cfg = self.store.get()
        sched = cfg.schedule

        # Send hardware power ON (turn:1) to every enabled controller across all enabled houses
        power_tasks = []
        for h in cfg.houses:
            if not h.enabled:
                continue
            effective_key = (h.govee_api_key or cfg.govee_api_key or "").strip()
            for ctrl in h.controllers:
                if not ctrl.enabled:
                    continue
                power_tasks.append(
                    self.driver.send_power_command(
                        ctrl,
                        turn_on=True,
                        api_key=effective_key,
                        house_id=h.id,
                    )
                )
        if power_tasks:
            await asyncio.gather(*power_tasks, return_exceptions=True)

        preset = next((p for p in self.PRESETS if p["id"] == sched.preset_id), None)
        merged = cfg.animation.model_dump()
        if preset is not None:
            merged.update(preset["animation"])
            merged.update(cfg.preset_overrides.get(sched.preset_id, {}))
            self.active_preset_id = preset["id"]
            cfg.active_preset_id = preset["id"]
        merged["running"] = True
        cfg.animation = AnimationConfig.model_validate(merged)
        self._last_playlist_switch_mono = time.monotonic_ns() / 1e9
        self.resume_clock()
        self.driver._last_sent_rgb.clear()
        self.driver._last_sent_sig.clear()
        self._last_schedule_action = trigger_label
        saved = self.store.save(cfg)
        if preset is not None:
            await self.driver.apply_cloud_scene_to_all(
                saved,
                preset_id=preset["id"],
                effect=str(merged.get("effect", "")),
                category=str(preset.get("category", "")),
            )
        await self.broadcast_snapshot(saved)
        return saved

    async def apply_scheduled_stop(
        self,
        cfg: Optional[SystemConfig] = None,
        trigger_label: str = "stopped",
    ) -> SystemConfig:
        """
        Stop the master animation clock, blackout all controllers, and optionally power OFF
        all physical Govee strips (`sched.turn_off_lights_on_stop`).
        """
        if cfg is None:
            cfg = self.store.get()
        sched = cfg.schedule
        cfg.animation.running = False
        cfg.animation.blackout_on_stop = True
        self.pause_clock(blackout=True)
        self._last_schedule_action = trigger_label
        saved = self.store.save(cfg)
        await self.driver.blackout_all_controllers(
            saved,
            turn_off=bool(sched.turn_off_lights_on_stop),
        )
        await self.broadcast_snapshot(saved)
        return saved

    async def _check_schedule_tick(
        self,
        cfg: Optional[SystemConfig] = None,
        now_dt: Optional[dt.datetime] = None,
    ) -> Optional[str]:
        """
        Autonomous 24/7 container schedule daemon tick.
        Evaluates the daily schedule in `cfg.schedule.timezone` (with automatic DST handling).
        Triggers start (`preset_id`, power ON, `running=True`) at `start_time` on active days,
        and stop (`running=False`, blackout + power OFF) at `stop_time`.
        """
        if cfg is None:
            cfg = self.store.get()
        sched = cfg.schedule
        if not sched.enabled:
            return None

        tz_name = (sched.timezone or "America/Los_Angeles").strip() or "America/Los_Angeles"
        try:
            tz = ZoneInfo(tz_name)
        except Exception:
            tz_name = "America/Los_Angeles"
            tz = ZoneInfo(tz_name)

        if now_dt is None:
            local_now = dt.datetime.now(tz)
        elif now_dt.tzinfo is None:
            local_now = now_dt.replace(tzinfo=tz)
        else:
            local_now = now_dt.astimezone(tz)

        hh_mm = local_now.strftime("%H:%M")
        minute_key = local_now.strftime("%Y-%m-%d %H:%M")
        if minute_key == self._last_schedule_minute_key:
            return None
        self._last_schedule_minute_key = minute_key

        weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        today_day = weekdays[local_now.weekday()]
        yesterday_day = weekdays[(local_now.weekday() - 1) % 7]
        active_days = [str(d).strip().lower()[:3] for d in (sched.days_of_week or []) if str(d).strip()]
        if not active_days:
            active_days = list(weekdays)

        start_hhmm = (sched.start_time or "").strip()
        stop_hhmm = (sched.stop_time or "").strip()

        if hh_mm == start_hhmm and today_day in active_days:
            tz_abbrev = local_now.tzname() or tz_name
            await self.apply_scheduled_start(
                cfg,
                trigger_label=f"started at {hh_mm} {tz_abbrev}",
            )
            logger.info("Daily schedule started preset '%s' at %s (%s)", sched.preset_id, hh_mm, tz_name)
            return "started"

        if hh_mm == stop_hhmm and (today_day in active_days or yesterday_day in active_days):
            tz_abbrev = local_now.tzname() or tz_name
            await self.apply_scheduled_stop(
                cfg,
                trigger_label=f"stopped at {hh_mm} {tz_abbrev}",
            )
            logger.info("Daily schedule stopped animation at %s (%s)", hh_mm, tz_name)
            return "stopped"

        return None

    async def check_schedule(self, now_dt: Optional[dt.datetime] = None) -> Optional[str]:
        """
        Evaluate the daily schedule in `cfg.schedule.timezone` (default `America/Los_Angeles`).
        Triggers start (`preset_id`, `running=True`) at `start_time` and stop (`running=False`) at `stop_time`.
        """
        return await self._check_schedule_tick(now_dt=now_dt)

    async def enforce_govee_schedule_guard(
        self,
        cfg: Optional[SystemConfig] = None,
        now_mono: Optional[float] = None,
    ) -> None:
        """
        When `cfg.schedule.override_govee_app_schedules` is True ("Block/Disable Govee App Schedules"),
        periodically re-assert Sync Studio's active scene (while running) or blackout/off state
        (while stopped) so any timer configured inside the Govee Home mobile app is immediately overridden.
        """
        if cfg is None:
            cfg = self.store.get()
        if not getattr(cfg.schedule, "override_govee_app_schedules", False):
            return
        if now_mono is None:
            now_mono = time.monotonic_ns() / 1e9

        last_guard = getattr(self, "_last_govee_guard_mono", 0.0)
        if (now_mono - last_guard) < 45.0:
            return
        self._last_govee_guard_mono = now_mono

        if cfg.animation.running:
            active_pid = cfg.active_preset_id or self.active_preset_id or cfg.schedule.preset_id
            preset = next((p for p in self.PRESETS if p["id"] == active_pid), None)
            await self.driver.apply_cloud_scene_to_all(
                cfg,
                preset_id=active_pid,
                effect=str(cfg.animation.effect.value if hasattr(cfg.animation.effect, "value") else cfg.animation.effect),
                category=str(preset.get("category", "")) if preset else "",
            )
        elif cfg.animation.blackout_on_stop and cfg.schedule.turn_off_lights_on_stop:
            await self.driver.blackout_all_controllers(cfg, turn_off=True)

    async def broadcast_snapshot(self, cfg: Optional[SystemConfig] = None) -> Dict[str, Any]:
        """
        Immediately render and push an updated state snapshot to all connected `/ws/live` clients
        so Play / Stop / Pause / Reorder / Patch actions update the UI in <10ms.
        """
        if cfg is None:
            cfg = self.store.get()
        segments, _ = self.render_frame_at(cfg)
        snapshot = self.build_live_snapshot(cfg, segments)
        if self._ws_listeners:
            await asyncio.gather(
                *(listener(snapshot) for listener in list(self._ws_listeners)),
                return_exceptions=True,
            )
        return snapshot

    async def _run_master_loop(self) -> None:
        """
        Deadline-scheduled monotonic master loop.
        Target wakeup time is anchored to `next_deadline` so frame execution time never accumulates drift.
        When `cfg.animation.running == False`, freezes phase and frame counter and stops hardware dispatch.
        """
        next_deadline = time.monotonic_ns() / 1e9
        fps_window_start = next_deadline
        frames_in_window = 0
        idle_ticks = 0

        while not self._stop_event.is_set():
            now_mono = time.monotonic_ns() / 1e9

            # 1. Check if a celebration burst expired
            if self._burst_ends_at_mono is not None and now_mono >= self._burst_ends_at_mono:
                await self.restore_from_burst()

            # 2. Check daily schedule once per ~15 seconds (triggers once per matching minute)
            if (now_mono - self._last_schedule_check_mono) >= 15.0:
                self._last_schedule_check_mono = now_mono
                await self.check_schedule()
                cfg_guard = self.store.get()
                if getattr(cfg_guard.schedule, "override_govee_app_schedules", False):
                    await self.enforce_govee_schedule_guard(cfg_guard, now_mono)

            # 3. Advance Playlist Jukebox if due
            self.advance_playlist_if_due(now_mono)

            cfg = self.store.get()
            target_fps = max(5, min(60, cfg.animation.fps))
            frame_period = 1.0 / target_fps

            drift_sec = now_mono - next_deadline

            if cfg.animation.running:
                idle_ticks = 0
                self.clock_drift_ms = round(abs(drift_sec) * 1000.0, 3)

                # Render current frame and advance counters only while running
                segments, ctrl_map = self.render_frame_at(cfg, now_mono)
                self.frame_counter += 1
                frames_in_window += 1

                if (now_mono - fps_window_start) >= 1.0:
                    self.measured_fps = round(frames_in_window / (now_mono - fps_window_start), 1)
                    fps_window_start = now_mono
                    frames_in_window = 0

                # Dispatch hardware commands across LAN, Neighbor Bridges, and Cloud
                if ctrl_map:
                    house_lookup = {h.id: h for h in cfg.houses}
                    dispatch_tasks = []
                    for (house_id, ctrl_id), seg_colors in ctrl_map.items():
                        house = house_lookup.get(house_id)
                        if not house:
                            continue
                        ctrl = next((c for c in house.controllers if c.id == ctrl_id), None)
                        if not ctrl:
                            continue
                        dispatch_tasks.append(
                            self.driver.dispatch_controller_frame(
                                house=house,
                                ctrl=ctrl,
                                segment_colors=seg_colors,
                                master_intensity=cfg.animation.intensity,
                                lan_enabled=cfg.lan_enabled,
                                cloud_fallback_enabled=cfg.cloud_fallback_enabled,
                                api_key=cfg.govee_api_key,
                                verbose_logging=cfg.verbose_packet_logging,
                            )
                        )
                    if dispatch_tasks:
                        await asyncio.gather(*dispatch_tasks, return_exceptions=True)

                # Broadcast live state to connected WebSocket GUI clients at full FPS
                if self._ws_listeners:
                    snapshot = self.build_live_snapshot(cfg, segments)
                    await asyncio.gather(
                        *(listener(snapshot) for listener in list(self._ws_listeners)),
                        return_exceptions=True,
                    )
            else:
                # Stopped / paused: freeze phase, do NOT advance frame_counter, and only send
                # low-rate status heartbeats (2 Hz) over WebSocket so the UI stays completely still
                self.pause_clock(now_mono, blackout=cfg.animation.blackout_on_stop)
                self.measured_fps = 0.0
                self.clock_drift_ms = 0.0
                fps_window_start = now_mono
                frames_in_window = 0
                segments, _ = self.render_frame_at(cfg, now_mono)
                idle_ticks += 1
                if self._ws_listeners and (idle_ticks % max(1, target_fps // 2) == 0):
                    snapshot = self.build_live_snapshot(cfg, segments)
                    await asyncio.gather(
                        *(listener(snapshot) for listener in list(self._ws_listeners)),
                        return_exceptions=True,
                    )

            # Advance deadline without cumulative drift
            next_deadline += frame_period
            after_work = time.monotonic_ns() / 1e9
            if next_deadline < after_work - frame_period:
                # If host was paused/stalled by >1 frame, resync deadline to avoid burst catch-up
                next_deadline = after_work + frame_period
            sleep_for = max(0.001, next_deadline - after_work)
            await asyncio.sleep(sleep_for)

    def build_live_snapshot(
        self, cfg: Optional[SystemConfig] = None, segments: Optional[List[SegmentRenderPoint]] = None
    ) -> Dict[str, Any]:
        if cfg is None:
            cfg = self.store.get()
        if segments is None:
            segments = self.latest_segments

        now_mono = time.monotonic_ns() / 1e9
        uptime_sec = round(now_mono - self._engine_start_mono, 1)
        burst_active = self.is_burst_active(now_mono)

        house_summaries = []
        total_houses = len([h for h in cfg.houses if h.enabled])
        for h_idx, h in enumerate(sorted(cfg.houses, key=lambda item: (item.order, item.id))):
            active_ctrls = [c for c in h.controllers if c.enabled]
            seg_count = sum(c.segment_count for c in active_ctrls)
            house_summaries.append(
                {
                    "id": h.id,
                    "name": h.name,
                    "order": h.order,
                    "enabled": h.enabled,
                    "connection_type": h.connection_type,
                    "has_api_key": bool((h.govee_api_key or cfg.govee_api_key or "").strip()),
                    "bridge_connected": h.id in self.driver.connected_bridges,
                    "controller_count": len(active_ctrls),
                    "total_segments": seg_count,
                    "time_weight": h.time_weight,
                    "is_chase_active": bool(cfg.animation.running and h.id == self.active_house_id),
                    "compensation_factor": round(
                        (1.0 / max(1, total_houses)) / max(0.001, seg_count / max(1, len(segments))),
                        2,
                    )
                    if segments and seg_count > 0
                    else 1.0,
                }
            )

        sched_status = self.compute_schedule_status(cfg.schedule)
        return {
            "type": "frame",
            "frame": self.frame_counter,
            "running": cfg.animation.running,
            "blackout_on_stop": cfg.animation.blackout_on_stop,
            "effect": cfg.animation.effect,
            "mapping_mode": cfg.animation.mapping_mode,
            "direction": cfg.animation.direction,
            "speed": cfg.animation.speed,
            "target_fps": cfg.animation.fps,
            "measured_fps": self.measured_fps if cfg.animation.running else 0.0,
            "clock_drift_ms": self.clock_drift_ms,
            "phase": round(self.current_phase, 4),
            "uptime_sec": uptime_sec,
            "active_preset_id": self.active_preset_id,
            "active_house_id": self.active_house_id if cfg.animation.running else "",
            "active_house_name": self.active_house_name if cfg.animation.running else "Stopped",
            "total_segments": len(segments),
            "houses": house_summaries,
            "controller_colors": self.latest_controller_colors,
            "segments": [s.model_dump() for s in segments],
            "playlist": cfg.playlist.model_dump(),
            "schedule": sched_status,
            "schedule_status": sched_status,
            "burst": {
                "active": burst_active,
                "label": self._burst_label if burst_active else "",
                "remaining_sec": round(max(0.0, (self._burst_ends_at_mono or now_mono) - now_mono), 1)
                if burst_active
                else 0.0,
            },
            "stats": self.driver.stats,
            "active_cloud_scenes": self.driver._active_cloud_scene,
            "cloud_errors": self.driver._cloud_last_error,
            "bridges": list(self.driver.bridge_info.values()),
            "recent_logs": [entry.model_dump() for entry in list(self.driver.packet_logs)[:25]],
        }
