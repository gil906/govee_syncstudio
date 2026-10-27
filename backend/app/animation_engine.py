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
        # --- Halloween (4 scenes) ---
        {
            "id": "halloween_haunted_chase",
            "name": "Govee Halloween (Official)",
            "category": "Halloween",
            "badge": "Govee #10764",
            "description": "Official Govee Halloween dynamic scene: pumpkin orange, witch purple, and eerie green chasing across segments.",
            "animation": {
                "effect": "halloween_spooky",
                "speed": 0.26,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff6b00",
                "secondary_color": "#9333ea",
                "accent_color": "#22c55e",
                "background_color": "#0d0417",
                "background_dim": 0.10,
                "tail_length": 0.28,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_witch_cauldron",
            "name": "Govee Halloween B (Official)",
            "category": "Halloween",
            "badge": "Govee #10765",
            "description": "Official Govee Halloween B dynamic scene: bubbling cauldron green, ultraviolet purple, and ember glow.",
            "animation": {
                "effect": "lightning_storm",
                "speed": 0.34,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#10b981",
                "secondary_color": "#7e22ce",
                "accent_color": "#f97316",
                "background_color": "#06110c",
                "background_dim": 0.12,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_blood_meteor",
            "name": "Govee Halloween D (Official)",
            "category": "Halloween",
            "badge": "Govee #10767",
            "description": "Official Govee Halloween D dynamic scene: crimson blood red, dark amber, and bone-white flashes.",
            "animation": {
                "effect": "comet_meteor",
                "speed": 0.30,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#dc2626",
                "secondary_color": "#ea580c",
                "accent_color": "#fef2f2",
                "background_color": "#140303",
                "background_dim": 0.08,
                "tail_length": 0.30,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_pumpkin_marquee",
            "name": "Govee Halloween C (Official)",
            "category": "Halloween",
            "badge": "Govee #10766",
            "description": "Official Govee Halloween C dynamic scene: jack-o'-lantern orange, violet, and ghostly cyan marquee.",
            "animation": {
                "effect": "theater_chase",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff6b00",
                "secondary_color": "#a855f7",
                "accent_color": "#06b6d4",
                "background_color": "#120700",
                "background_dim": 0.10,
                "tail_length": 0.22,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_poltergeist_portal",
            "name": "Spooky Halloween AI (Govee DIY)",
            "category": "Halloween",
            "badge": "Govee DIY",
            "description": "Your custom Govee DIY scene 'Spooky Halloween AI' (with Thunderstorm fallback on neighbor controllers).",
            "animation": {
                "effect": "center_out_shockwave",
                "speed": 0.30,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#9333ea",
                "secondary_color": "#00f5d4",
                "accent_color": "#22c55e",
                "background_color": "#070210",
                "background_dim": 0.08,
                "tail_length": 0.26,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_zombie_outbreak",
            "name": "Govee Halloween II (Official)",
            "category": "Halloween",
            "badge": "Govee #14491",
            "description": "Official Govee Halloween II dynamic scene: toxic green, haunted purple, and pumpkin orange wave.",
            "animation": {
                "effect": "cyber_snake",
                "speed": 0.28,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#84cc16",
                "secondary_color": "#9333ea",
                "accent_color": "#f97316",
                "background_color": "#050d02",
                "background_dim": 0.09,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "halloween_frankenstein_lab",
            "name": "Govee Flash (Official)",
            "category": "Halloween",
            "badge": "Govee #23504",
            "description": "Official Govee Flash dynamic scene: high-voltage electric cyan, lime, and ultraviolet laboratory arcs.",
            "animation": {
                "effect": "lightning_storm",
                "speed": 0.42,
                "direction": "pingpong",
                "mapping_mode": "house_normalized",
                "primary_color": "#38bdf8",
                "secondary_color": "#22c55e",
                "accent_color": "#e879f9",
                "background_color": "#020814",
                "background_dim": 0.10,
                "tail_length": 0.22,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_headless_horseman",
            "name": "Govee Meteor (Official)",
            "category": "Halloween",
            "badge": "Govee #14161",
            "description": "Official Govee Meteor dynamic scene: streaking fiery orange, crimson, and gold meteor tails.",
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
                "supersample": True,
            },
        },
        {
            "id": "halloween_beetlejuice_sandworm",
            "name": "Govee Karst Cave (Official)",
            "category": "Halloween",
            "badge": "Govee #10747",
            "description": "Official Govee Karst Cave dynamic scene: deep cavern purple, emerald green, and mystic teal stripes.",
            "animation": {
                "effect": "christmas_magic",
                "speed": 0.27,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#a855f7",
                "secondary_color": "#22c55e",
                "accent_color": "#14b8a6",
                "background_color": "#06020a",
                "background_dim": 0.08,
                "tail_length": 0.26,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_hellfire_brimstone",
            "name": "Govee Fire (Official)",
            "category": "Halloween",
            "badge": "Govee #10753",
            "description": "Official Govee Fire dynamic scene: roaring crimson, flame orange, and golden ember flicker.",
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
                "supersample": True,
            },
        },
        {
            "id": "halloween_phantom_ghost_train",
            "name": "Halloween Chasing (Govee DIY)",
            "category": "Halloween",
            "badge": "Govee DIY",
            "description": "Your custom Govee DIY scene 'Halloween chasing' synchronized across your house and neighbor controllers.",
            "animation": {
                "effect": "multi_house_chase",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff6b00",
                "secondary_color": "#9333ea",
                "accent_color": "#22c55e",
                "background_color": "#030712",
                "background_dim": 0.07,
                "tail_length": 0.20,
                "pulse_count": 3,
                "supersample": True,
            },
        },
        {
            "id": "halloween_shadow_possession",
            "name": "Orange & Purple (Govee DIY)",
            "category": "Halloween",
            "badge": "Govee DIY",
            "description": "Your custom Govee DIY scene 'orange and purple': vivid pumpkin orange and royal purple chase.",
            "animation": {
                "effect": "color_wipe",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff6b00",
                "secondary_color": "#9333ea",
                "accent_color": "#a855f7",
                "background_color": "#08020f",
                "background_dim": 0.08,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "halloween_black_widow_lair",
            "name": "Govee Night (Official)",
            "category": "Halloween",
            "badge": "Govee #10795",
            "description": "Official Govee Night dynamic scene: midnight indigo, deep crimson, and dark violet glow.",
            "animation": {
                "effect": "sparkle_twinkle",
                "speed": 0.30,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#6b21a8",
                "secondary_color": "#ef4444",
                "accent_color": "#312e81",
                "background_color": "#09010d",
                "background_dim": 0.12,
                "tail_length": 0.22,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_haunted_heartbeat",
            "name": "Govee Profound (Official)",
            "category": "Halloween",
            "badge": "Govee #10811",
            "description": "Official Govee Profound dynamic scene: deep pulsing crimson, plum violet, and warm amber.",
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
                "supersample": True,
            },
        },
        {
            "id": "halloween_candy_corn_parade",
            "name": "Govee Fall (Official)",
            "category": "Halloween",
            "badge": "Govee #10757",
            "description": "Official Govee Fall dynamic scene: autumn harvest orange, golden yellow, and warm amber.",
            "animation": {
                "effect": "multi_house_chase",
                "speed": 0.25,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff7b00",
                "secondary_color": "#facc15",
                "accent_color": "#ea580c",
                "background_color": "#140800",
                "background_dim": 0.10,
                "tail_length": 0.32,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_pharaoh_curse",
            "name": "Govee Sunset Glow (Official)",
            "category": "Halloween",
            "badge": "Govee #10739",
            "description": "Official Govee Sunset Glow dynamic scene: desert gold, amber, and twilight purple.",
            "animation": {
                "effect": "halloween_spooky",
                "speed": 0.24,
                "direction": "reverse",
                "mapping_mode": "house_normalized",
                "primary_color": "#eab308",
                "secondary_color": "#f97316",
                "accent_color": "#a855f7",
                "background_color": "#120c02",
                "background_dim": 0.10,
                "tail_length": 0.28,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow1_spooky_prism",
            "name": "Govee Rainbow (Official)",
            "category": "Halloween",
            "badge": "Govee #10744",
            "description": "Official Govee Rainbow dynamic scene: smooth full-spectrum multi-segment rainbow wave.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff0055",
                "secondary_color": "#00f5d4",
                "accent_color": "#facc15",
                "background_color": "#e11d48",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow2_monster_blocks",
            "name": "Govee Stacking (Official)",
            "category": "Halloween",
            "badge": "Govee #10806",
            "description": "Official Govee Stacking dynamic scene: vivid color blocks stacking across the roofline.",
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
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow1_hocus_pocus",
            "name": "Govee Dreamlike (Official)",
            "category": "Halloween",
            "badge": "Govee #10815",
            "description": "Official Govee Dreamlike dynamic scene: silky violet, magenta, and turquoise gradient flow.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#a855f7",
                "secondary_color": "#ec4899",
                "accent_color": "#06b6d4",
                "background_color": "#f59e0b",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow2_candy_corn_blocks",
            "name": "Govee Cornfield (Official)",
            "category": "Halloween",
            "badge": "Govee #10749",
            "description": "Official Govee Cornfield dynamic scene: golden harvest yellow, amber, and autumn green bands.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.25,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#facc15",
                "secondary_color": "#f97316",
                "accent_color": "#84cc16",
                "background_color": "#7e22ce",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow1_ectoplasm_wave",
            "name": "Govee Forest (Official)",
            "category": "Halloween",
            "badge": "Govee #10745",
            "description": "Official Govee Forest dynamic scene: lush emerald green, mint, and canopy gold wave.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.28,
                "direction": "pingpong",
                "mapping_mode": "house_normalized",
                "primary_color": "#10b981",
                "secondary_color": "#84cc16",
                "accent_color": "#06b6d4",
                "background_color": "#ff007f",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow2_dracula_castle",
            "name": "Govee Sunset (Official)",
            "category": "Halloween",
            "badge": "Govee #10738",
            "description": "Official Govee Sunset dynamic scene: dusk crimson, fiery orange, and twilight violet.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#dc2626",
                "secondary_color": "#f97316",
                "accent_color": "#7e22ce",
                "background_color": "#312e81",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow1_pumpkin_spice",
            "name": "Govee Rustling Leaves (Official)",
            "category": "Halloween",
            "badge": "Govee #10750",
            "description": "Official Govee Rustling Leaves dynamic scene: warm amber, copper orange, and golden leaf shimmer.",
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
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow2_goblin_parade",
            "name": "Govee Spin (Official)",
            "category": "Halloween",
            "badge": "Govee #10799",
            "description": "Official Govee Spin dynamic scene: rotating multi-color carousel across all segments.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.30,
                "direction": "pingpong",
                "mapping_mode": "house_normalized",
                "primary_color": "#22c55e",
                "secondary_color": "#8b5cf6",
                "accent_color": "#ff6b00",
                "background_color": "#ec4899",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 3,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow1_witches_brew",
            "name": "Govee Twilight (Official)",
            "category": "Halloween",
            "badge": "Govee #10794",
            "description": "Official Govee Twilight dynamic scene: evening violet, deep cyan, and magenta horizon.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.26,
                "direction": "reverse",
                "mapping_mode": "house_normalized",
                "primary_color": "#8b5cf6",
                "secondary_color": "#06b6d4",
                "accent_color": "#ec4899",
                "background_color": "#a3e635",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow2_skeleton_rave",
            "name": "Govee Dancing (Official)",
            "category": "Halloween",
            "badge": "Govee #10800",
            "description": "Official Govee Dancing dynamic scene: upbeat rhythmic multi-color party blocks.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.38,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#f43f5e",
                "secondary_color": "#a855f7",
                "accent_color": "#38bdf8",
                "background_color": "#00f5d4",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 3,
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow1_full_spectrum",
            "name": "Govee Gradient (Official)",
            "category": "Halloween",
            "badge": "Govee #10807",
            "description": "Official Govee Gradient dynamic scene: seamless full-strip color-to-color gradient transition.",
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
                "supersample": True,
            },
        },
        {
            "id": "halloween_rainbow2_warlock_crystal",
            "name": "Govee Milky Way (Official)",
            "category": "Halloween",
            "badge": "Govee #14159",
            "description": "Official Govee Milky Way dynamic scene: cosmic starlight violet, blue, and nebula magenta.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.22,
                "direction": "reverse",
                "mapping_mode": "house_normalized",
                "primary_color": "#d946ef",
                "secondary_color": "#3b82f6",
                "accent_color": "#f8fafc",
                "background_color": "#f59e0b",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        # --- Christmas (28 scenes) ---
        {
            "id": "xmas_sleigh_ride",
            "name": "Govee Sled (Official)",
            "category": "Christmas",
            "badge": "Govee #10763",
            "description": "Official Govee Sled dynamic scene: high-speed sleigh red, icy cyan, and snow white dash.",
            "animation": {
                "effect": "christmas_magic",
                "speed": 0.24,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ef4444",
                "secondary_color": "#38bdf8",
                "accent_color": "#ffffff",
                "background_color": "#04120a",
                "background_dim": 0.10,
                "tail_length": 0.28,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "xmas_candy_cane",
            "name": "Govee Candy Cane (Official)",
            "category": "Christmas",
            "badge": "Govee #14165",
            "description": "Official Govee Candy Cane dynamic scene: peppermint red and pure snow white stripes.",
            "animation": {
                "effect": "multi_house_chase",
                "speed": 0.25,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff1744",
                "secondary_color": "#ffffff",
                "accent_color": "#ff5252",
                "background_color": "#120306",
                "background_dim": 0.08,
                "tail_length": 0.26,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_frozen_aurora",
            "name": "Govee Winter Wonderland (Official)",
            "category": "Christmas",
            "badge": "Govee #10787",
            "description": "Official Govee Winter Wonderland dynamic scene: sparkling ice blue, crystal white, and frost cyan.",
            "animation": {
                "effect": "sparkle_twinkle",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#38bdf8",
                "secondary_color": "#f8fafc",
                "accent_color": "#3b82f6",
                "background_color": "#020b18",
                "background_dim": 0.10,
                "tail_length": 0.24,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_nutcracker_marquee",
            "name": "Govee Christmas (Official)",
            "category": "Christmas",
            "badge": "Govee #10760",
            "description": "Official Govee Christmas dynamic scene: classic holiday red, evergreen, and warm gold.",
            "animation": {
                "effect": "theater_chase",
                "speed": 0.18,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ef4444",
                "secondary_color": "#10b981",
                "accent_color": "#fbbf24",
                "background_color": "#140802",
                "background_dim": 0.10,
                "tail_length": 0.20,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rudolph_dash",
            "name": "Govee Delivering Gifts (Official)",
            "category": "Christmas",
            "badge": "Govee #14492",
            "description": "Official Govee Delivering Gifts dynamic scene: Santa red, golden bells, and emerald green.",
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
                "supersample": True,
            },
        },
        {
            "id": "xmas_north_pole_beacon",
            "name": "Govee Christmas Tree (Official)",
            "category": "Christmas",
            "badge": "Govee #10761",
            "description": "Official Govee Christmas Tree dynamic scene: pine green canopy with red and gold ornaments.",
            "animation": {
                "effect": "center_out_shockwave",
                "speed": 0.25,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#10b981",
                "secondary_color": "#ef4444",
                "accent_color": "#fde047",
                "background_color": "#041008",
                "background_dim": 0.10,
                "tail_length": 0.26,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_grinch_heist",
            "name": "Govee Leprechaun (Official)",
            "category": "Christmas",
            "badge": "Govee #10788",
            "description": "Official Govee Leprechaun dynamic scene: vivid emerald green, lime, and shimmering gold.",
            "animation": {
                "effect": "cyber_snake",
                "speed": 0.28,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#22c55e",
                "secondary_color": "#84cc16",
                "accent_color": "#facc15",
                "background_color": "#061004",
                "background_dim": 0.08,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "xmas_polar_express",
            "name": "Govee Winter (Official)",
            "category": "Christmas",
            "badge": "Govee #10758",
            "description": "Official Govee Winter dynamic scene: crisp glacial blue, frost cyan, and snow white.",
            "animation": {
                "effect": "multi_house_chase",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#38bdf8",
                "secondary_color": "#e0f2fe",
                "accent_color": "#2563eb",
                "background_color": "#040814",
                "background_dim": 0.10,
                "tail_length": 0.22,
                "pulse_count": 3,
                "supersample": True,
            },
        },
        {
            "id": "xmas_gingerbread_village",
            "name": "Govee Christmas Gift (Official)",
            "category": "Christmas",
            "badge": "Govee #10762",
            "description": "Official Govee Christmas Gift dynamic scene: festive ribbon red, gold, and holly green.",
            "animation": {
                "effect": "diwali_festival",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ef4444",
                "secondary_color": "#f59e0b",
                "accent_color": "#22c55e",
                "background_color": "#140904",
                "background_dim": 0.12,
                "tail_length": 0.26,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_arctic_blizzard",
            "name": "Govee Downpour (Official)",
            "category": "Christmas",
            "badge": "Govee #10759",
            "description": "Official Govee Downpour dynamic scene: cascading ice-blue and silver-white winter flurries.",
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
                "supersample": True,
            },
        },
        {
            "id": "xmas_yule_log_hearth",
            "name": "Govee Warm (Official)",
            "category": "Christmas",
            "badge": "Govee #10816",
            "description": "Official Govee Warm dynamic scene: cozy hearth amber, soft gold, and warm orange glow.",
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
                "supersample": True,
            },
        },
        {
            "id": "xmas_elf_workshop_ribbon",
            "name": "Govee Children's Day (Official)",
            "category": "Christmas",
            "badge": "Govee #14169",
            "description": "Official Govee Children's Day dynamic scene: playful toy-shop red, yellow, green, and blue.",
            "animation": {
                "effect": "color_wipe",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ef4444",
                "secondary_color": "#facc15",
                "accent_color": "#10b981",
                "background_color": "#061008",
                "background_dim": 0.08,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "xmas_star_of_bethlehem",
            "name": "Govee Christmas Eve (Official)",
            "category": "Christmas",
            "badge": "Govee #14166",
            "description": "Official Govee Christmas Eve dynamic scene: peaceful starlight gold, warm white, and night blue.",
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
                "tail_length": 0.30,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "xmas_sugar_plum_fairy",
            "name": "Govee Dreamland (Official)",
            "category": "Christmas",
            "badge": "Govee #10818",
            "description": "Official Govee Dreamland dynamic scene: sugar-plum lavender, rose pink, and crystal white.",
            "animation": {
                "effect": "sparkle_twinkle",
                "speed": 0.26,
                "direction": "pingpong",
                "mapping_mode": "house_normalized",
                "primary_color": "#c084fc",
                "secondary_color": "#f472b6",
                "accent_color": "#ffffff",
                "background_color": "#0f0418",
                "background_dim": 0.10,
                "tail_length": 0.24,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_mistletoe_harmony",
            "name": "Govee Christmas Wreath (Official)",
            "category": "Christmas",
            "badge": "Govee #14167",
            "description": "Official Govee Christmas Wreath dynamic scene: evergreen holly, berry red, and warm gold.",
            "animation": {
                "effect": "breathing_pulse",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "parallel_zones",
                "primary_color": "#10b981",
                "secondary_color": "#ef4444",
                "accent_color": "#fde047",
                "background_color": "#041208",
                "background_dim": 0.10,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow1_classic_C9",
            "name": "Govee Christmas Bell (Official)",
            "category": "Christmas",
            "badge": "Govee #14164",
            "description": "Official Govee Christmas Bell dynamic scene: chiming golden bells, ruby red, and emerald.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#fbbf24",
                "secondary_color": "#ef4444",
                "accent_color": "#10b981",
                "background_color": "#f59e0b",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow2_c9_blocks",
            "name": "Govee Colorful (Official)",
            "category": "Christmas",
            "badge": "Govee #10803",
            "description": "Official Govee Colorful dynamic scene: classic multi-color C9 holiday bulb blocks.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ef4444",
                "secondary_color": "#10b981",
                "accent_color": "#3b82f6",
                "background_color": "#fbbf24",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow1_peppermint_silk",
            "name": "Red White Running (Govee DIY)",
            "category": "Christmas",
            "badge": "Govee DIY",
            "description": "Your custom Govee DIY scene 'red white running' (with Candy Cane fallback on neighbor controllers).",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.24,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff1744",
                "secondary_color": "#ffffff",
                "accent_color": "#ff5252",
                "background_color": "#fde047",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow2_candy_shoppe",
            "name": "Govee Amusement (Official)",
            "category": "Christmas",
            "badge": "Govee #14172",
            "description": "Official Govee Amusement dynamic scene: festive candy-shop red, cyan, yellow, and magenta.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.25,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff1744",
                "secondary_color": "#00f5d4",
                "accent_color": "#facc15",
                "background_color": "#ec4899",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 3,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow1_arctic_aurora",
            "name": "Govee Aurora (Official)",
            "category": "Christmas",
            "badge": "Govee #10746",
            "description": "Official Govee Aurora dynamic scene: northern lights emerald green, cyan, and arctic violet.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.18,
                "direction": "pingpong",
                "mapping_mode": "house_normalized",
                "primary_color": "#00f5d4",
                "secondary_color": "#10b981",
                "accent_color": "#8b5cf6",
                "background_color": "#8b5cf6",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow2_glacier_blocks",
            "name": "Govee Lake (Official)",
            "category": "Christmas",
            "badge": "Govee #14162",
            "description": "Official Govee Lake dynamic scene: rippling glacier blue, aqua, and crystal white.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#38bdf8",
                "secondary_color": "#06b6d4",
                "accent_color": "#ffffff",
                "background_color": "#2dd4bf",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow1_royal_nativity",
            "name": "Govee Star (Official)",
            "category": "Christmas",
            "badge": "Govee #10742",
            "description": "Official Govee Star dynamic scene: shimmering golden starlight and midnight sky.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.18,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#fbbf24",
                "secondary_color": "#fef08a",
                "accent_color": "#3b82f6",
                "background_color": "#fef3c7",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow2_toy_soldier",
            "name": "Govee Swing (Official)",
            "category": "Christmas",
            "badge": "Govee #10802",
            "description": "Official Govee Swing dynamic scene: rhythmic pendulum of ruby red, gold, and royal blue.",
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
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow1_pastel_macaron",
            "name": "Govee Cherry Blossoms (Official)",
            "category": "Christmas",
            "badge": "Govee #10754",
            "description": "Official Govee Cherry Blossoms dynamic scene: soft pastel pink, lavender, and blossom white.",
            "animation": {
                "effect": "govee_rainbow1",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#f472b6",
                "secondary_color": "#e879f9",
                "accent_color": "#ffffff",
                "background_color": "#7dd3fc",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow2_jingle_bell_rock",
            "name": "Govee Music Show (Official)",
            "category": "Christmas",
            "badge": "Govee #14171",
            "description": "Official Govee Music Show dynamic scene: energetic stage lights in red, green, and cyan.",
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
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow1_full_spectrum",
            "name": "Govee Flower Parade (Official)",
            "category": "Christmas",
            "badge": "Govee #14174",
            "description": "Official Govee Flower Parade dynamic scene: vibrant holiday parade of rose, gold, and emerald.",
            "animation": {
                "effect": "rainbow_wave",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#f43f5e",
                "secondary_color": "#fbbf24",
                "accent_color": "#10b981",
                "background_color": "#000000",
                "background_dim": 0.0,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_rainbow2_wreath_and_holly",
            "name": "Govee St. Patrick's (Official)",
            "category": "Christmas",
            "badge": "Govee #10783",
            "description": "Official Govee Saint Patrick's Day dynamic scene: vivid shamrock green, emerald, and gold.",
            "animation": {
                "effect": "govee_rainbow2",
                "speed": 0.20,
                "direction": "reverse",
                "mapping_mode": "house_normalized",
                "primary_color": "#059669",
                "secondary_color": "#22c55e",
                "accent_color": "#facc15",
                "background_color": "#fbbf24",
                "background_dim": 0.15,
                "tail_length": 0.25,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "xmas_frost_vs_flame",
            "name": "Govee ZDP Duo (Official)",
            "category": "Christmas",
            "badge": "Govee #23508",
            "description": "Official Govee ZDP Duo dynamic scene: dual-tone ice blue and fiery orange contrast.",
            "animation": {
                "effect": "cyber_snake",
                "speed": 0.30,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#38bdf8",
                "secondary_color": "#ef4444",
                "accent_color": "#fde047",
                "background_color": "#050914",
                "background_dim": 0.08,
                "tail_length": 0.26,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        # --- Diwali (4 scenes) ---
        {
            "id": "diwali_golden_diya",
            "name": "Govee Candlelight (Official)",
            "category": "Diwali",
            "badge": "Govee #10782",
            "description": "Official Govee Candlelight dynamic scene: warm flickering golden diya oil lamp glow.",
            "animation": {
                "effect": "diwali_festival",
                "speed": 0.22,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#f59e0b",
                "secondary_color": "#fbbf24",
                "accent_color": "#ea580c",
                "background_color": "#170902",
                "background_dim": 0.14,
                "tail_length": 0.26,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "diwali_rangoli_wave",
            "name": "Govee Flower Field (Official)",
            "category": "Diwali",
            "badge": "Govee #10751",
            "description": "Official Govee Flower Field dynamic scene: vibrant rangoli magenta, marigold orange, and cyan.",
            "animation": {
                "effect": "multi_house_chase",
                "speed": 0.26,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ec4899",
                "secondary_color": "#f97316",
                "accent_color": "#06b6d4",
                "background_color": "#140410",
                "background_dim": 0.10,
                "tail_length": 0.28,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "diwali_firecracker_sparkle",
            "name": "Govee Hooray (Official)",
            "category": "Diwali",
            "badge": "Govee #14175",
            "description": "Official Govee Hooray dynamic scene: celebratory bursts of gold, magenta, and violet.",
            "animation": {
                "effect": "sparkle_twinkle",
                "speed": 0.30,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#fde047",
                "secondary_color": "#d946ef",
                "accent_color": "#8b5cf6",
                "background_color": "#11051c",
                "background_dim": 0.10,
                "tail_length": 0.24,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "diwali_aarti_flame",
            "name": "Govee Sunrise (Official)",
            "category": "Diwali",
            "badge": "Govee #10737",
            "description": "Official Govee Sunrise dynamic scene: sacred warm amber, saffron orange, and golden radiance.",
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
                "supersample": True,
            },
        },
        # --- Center-Out from My Middle House (3 scenes) ---
        {
            "id": "center_supernova",
            "name": "Govee Universe (Official)",
            "category": "Center-Out (My House)",
            "badge": "Govee #10743",
            "description": "Official Govee Universe dynamic scene: deep-space cyan, galaxy purple, and neon magenta.",
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
                "supersample": True,
            },
        },
        {
            "id": "center_golden_ripple",
            "name": "Govee Morning (Official)",
            "category": "Center-Out (My House)",
            "badge": "Govee #10792",
            "description": "Official Govee Morning dynamic scene: golden dawn ripple with warm white and amber.",
            "animation": {
                "effect": "center_out_shockwave",
                "speed": 0.22,
                "direction": "pingpong",
                "mapping_mode": "house_normalized",
                "primary_color": "#fbbf24",
                "secondary_color": "#f97316",
                "accent_color": "#ffffff",
                "background_color": "#120902",
                "background_dim": 0.10,
                "tail_length": 0.28,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "center_serpent_clash",
            "name": "Govee ZDP Trio (Official)",
            "category": "Center-Out (My House)",
            "badge": "Govee #23509",
            "description": "Official Govee ZDP Trio dynamic scene: triple-band emerald, electric blue, and crimson.",
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
                "supersample": True,
            },
        },
        # --- Cyber & Party (4 scenes) ---
        {
            "id": "cyber_chase",
            "name": "Govee Flow (Official)",
            "category": "Cyber & Party",
            "badge": "Govee #10804",
            "description": "Official Govee Flow dynamic scene: multi-color neon stream flowing across segments.",
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
                "supersample": True,
            },
        },
        {
            "id": "dual_comet_pingpong",
            "name": "Govee Active (Official)",
            "category": "Cyber & Party",
            "badge": "Govee #10819",
            "description": "Official Govee Active dynamic scene: high-speed bouncing cyan, indigo, and rose pulses.",
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
                "supersample": True,
            },
        },
        {
            "id": "seamless_rainbow",
            "name": "Govee Enthusiastic (Official)",
            "category": "Cyber & Party",
            "badge": "Govee #10812",
            "description": "Official Govee Enthusiastic dynamic scene: vibrant full-saturation spectrum wave.",
            "animation": {
                "effect": "rainbow_wave",
                "speed": 0.20,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff0055",
                "secondary_color": "#00ffcc",
                "accent_color": "#ffee00",
                "background_color": "#000000",
                "background_dim": 0.0,
                "tail_length": 0.25,
                "pulse_count": 1,
                "supersample": True,
            },
        },
        {
            "id": "harmonic_pulse",
            "name": "Govee Fluctuate (Official)",
            "category": "Cyber & Party",
            "badge": "Govee #10805",
            "description": "Official Govee Fluctuate dynamic scene: synchronized breathing wave in emerald, blue, and violet.",
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
                "supersample": True,
            },
        },
        # --- Celebrations (4 scenes) ---
        {
            "id": "seahawks_gameday",
            "name": "Govee Game Day (Official)",
            "category": "Celebrations",
            "badge": "Govee #10785",
            "description": "Official Govee Game Day dynamic scene: stadium action chase in green, navy, and gold.",
            "animation": {
                "effect": "multi_house_chase",
                "speed": 0.34,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#69be28",
                "secondary_color": "#002244",
                "accent_color": "#facc15",
                "background_color": "#001122",
                "background_dim": 0.12,
                "tail_length": 0.26,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "july4_fireworks",
            "name": "Govee Fireworks (Official)",
            "category": "Celebrations",
            "badge": "Govee #10781",
            "description": "Official Govee Fireworks dynamic scene: skyrocket bursts in red, white, and royal blue.",
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
                "supersample": True,
            },
        },
        {
            "id": "holiday_marquee",
            "name": "Govee Carnival (Official)",
            "category": "Celebrations",
            "badge": "Govee #10776",
            "description": "Official Govee Carnival dynamic scene: festive marquee in gold, crimson, and purple.",
            "animation": {
                "effect": "theater_chase",
                "speed": 0.18,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#fbbf24",
                "secondary_color": "#ef4444",
                "accent_color": "#a855f7",
                "background_color": "#120604",
                "background_dim": 0.10,
                "tail_length": 0.20,
                "pulse_count": 2,
                "supersample": True,
            },
        },
        {
            "id": "hearth_fire",
            "name": "Govee Firefly (Official)",
            "category": "Celebrations",
            "badge": "Govee #10752",
            "description": "Official Govee Firefly dynamic scene: warm glowing amber and golden fireflies.",
            "animation": {
                "effect": "fire_sparkle",
                "speed": 0.30,
                "direction": "forward",
                "mapping_mode": "house_normalized",
                "primary_color": "#ff5500",
                "secondary_color": "#ffaa00",
                "accent_color": "#ffee88",
                "background_color": "#140400",
                "background_dim": 0.12,
                "tail_length": 0.22,
                "pulse_count": 1,
                "supersample": True,
            },
        },
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
