from __future__ import annotations

import asyncio
import datetime as dt
import hashlib
import json
import logging
import os
import time
import urllib.parse
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import Body, Depends, FastAPI, HTTPException, Request, Response, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, PlainTextResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from .animation_engine import MasterAnimationEngine, build_virtual_strip_map, compute_schedule_status, hex_to_rgb
from .auth import AuthManager, access_denied_message, is_external_request
from .config_store import ConfigStore
from .govee_protocol import GoveeProtocolDriver
from .models import (
    OWNER_EMAIL,
    AnimationConfig,
    ControllerConfig,
    DiscoveredDevice,
    HouseConfig,
    PlaylistConfig,
    ProtocolMode,
    ScheduleConfig,
    SystemConfig,
    normalize_authorized_emails,
)

logging.basicConfig(
    level=getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper(), logging.INFO),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("govee_sync.main")

store = ConfigStore()
driver = GoveeProtocolDriver()
engine = MasterAnimationEngine(store=store, driver=driver)
auth_manager = AuthManager(store=store)


def _seed_configured_lan_devices(cfg: SystemConfig) -> None:
    """Ensure configured LAN controllers with real IPs/MACs are registered in discovered_devices."""
    for h in cfg.houses:
        for c in h.controllers:
            if c.ip and c.mac and not c.mac.upper().startswith("AA:BB:CC:DD:EE:"):
                mac = c.mac.upper()
                if mac not in driver.discovered_devices:
                    driver.discovered_devices[mac] = DiscoveredDevice(
                        ip=c.ip,
                        mac=mac,
                        sku=c.sku or "H705E",
                        name=c.name or f"{c.sku} ({c.ip})",
                        source="lan",
                        online=True,
                    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    await driver.start()
    await engine.start()
    # Trigger an initial background LAN + Cloud scan and apply active Cloud scene if running
    cfg = store.get()
    _seed_configured_lan_devices(cfg)
    known_ips = [c.ip for h in cfg.houses for c in h.controllers if c.ip]
    house_keys = [h.govee_api_key for h in cfg.houses if h.govee_api_key]

    async def _startup_sync() -> None:
        await driver.scan_lan_and_cloud(
            known_ips=known_ips,
            api_key=cfg.govee_api_key,
            extra_api_keys=house_keys,
        )
        if cfg.animation.running and cfg.active_preset_id:
            preset = next((p for p in engine.PRESETS if p["id"] == cfg.active_preset_id), None)
            await driver.apply_cloud_scene_to_all(
                cfg,
                preset_id=cfg.active_preset_id,
                effect=str(cfg.animation.effect.value if hasattr(cfg.animation.effect, "value") else cfg.animation.effect),
                category=str(preset.get("category", "")) if preset else "",
            )

    asyncio.create_task(_startup_sync())
    yield
    await engine.stop()
    await driver.stop()


app = FastAPI(
    title="Govee Multi-House Light Sync",
    description="Zero-drift monotonic multi-house Govee LAN + Cloud + Neighbor Bridge light synchronization controller",
    version="1.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

PUBLIC_API_PREFIXES = (
    "/api/health",
    "/api/auth/status",
    "/api/auth/logout",
    "/api/auth/bridge-callback",
    "/api/auth/bridge-poll/",
    "/api/auth/google/",
    "/api/auth/github/",
    "/api/neighbor-bridge.py",
)
PUBLIC_PATHS = PUBLIC_API_PREFIXES


def _is_public_api_path(path: str) -> bool:
    if not path.startswith("/api/"):
        return True
    for prefix in PUBLIC_API_PREFIXES:
        if path == prefix or path.startswith(prefix):
            return True
    return False


@app.middleware("http")
async def external_auth_middleware(request: Request, call_next):
    if request.method == "OPTIONS" or _is_public_api_path(request.url.path):
        return await call_next(request)

    has_token = bool(auth_manager.extract_token_from_request(request))
    if is_external_request(request) or has_token:
        try:
            user = auth_manager.require_authenticated_user(request)
            request.state.user = user
        except HTTPException as exc:
            return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})

    return await call_next(request)


class PowerRequest(BaseModel):
    turn_on: bool
    house_id: Optional[str] = None
    controller_id: Optional[str] = None


class StopAnimationRequest(BaseModel):
    blackout_on_stop: bool = True
    turn_off: bool = True


class DiscoverCloudRequest(BaseModel):
    api_key: Optional[str] = None
    auto_populate: bool = True


class TestControllerRequest(BaseModel):
    color: str = "#00f5d4"


class BurstRequest(BaseModel):
    preset_id: Optional[str] = None
    type: Optional[str] = None
    duration_sec: float = 12.0


class GoogleIdTokenRequest(BaseModel):
    id_token: Optional[str] = None
    credential: Optional[str] = None
    token: Optional[str] = None


class AddAuthorizedUserRequest(BaseModel):
    email: str


def _default_segments_for_sku(sku: str) -> int:
    s = (sku or "").upper()
    if s.startswith("H706"):
        return 15
    if s.startswith("H705"):
        return 12
    if s.startswith("H619") or s.startswith("H61A"):
        return 15
    return 12


@app.get("/api/health")
async def health_check() -> Dict[str, Any]:
    cfg = store.get()
    return {
        "status": "ok",
        "service": "govee-multi-house-light-sync",
        "running": cfg.animation.running,
        "effect": cfg.animation.effect,
        "mapping_mode": cfg.animation.mapping_mode,
        "measured_fps": engine.measured_fps if cfg.animation.running else 0.0,
        "clock_drift_ms": engine.clock_drift_ms,
        "houses": len(cfg.houses),
        "controllers": sum(len(h.controllers) for h in cfg.houses),
        "total_segments": sum(h.total_segments for h in cfg.houses if h.enabled),
        "connected_bridges": list(driver.connected_bridges.keys()),
        "stats": driver.stats,
    }


@app.get("/api/config", response_model=SystemConfig)
async def get_config() -> SystemConfig:
    return store.get()


@app.put("/api/config", response_model=SystemConfig)
async def update_config(new_config: SystemConfig) -> SystemConfig:
    prev_running = store.get().animation.running
    if prev_running and not new_config.animation.running:
        engine.pause_clock(blackout=new_config.animation.blackout_on_stop)
    elif not prev_running and new_config.animation.running:
        engine.resume_clock()
    saved = store.save(new_config)
    await engine.broadcast_snapshot(saved)
    return saved


@app.post("/api/config/reset", response_model=SystemConfig)
async def reset_config() -> SystemConfig:
    saved = store.reset_to_example()
    engine.reset_clock()
    if saved.animation.running:
        engine.resume_clock()
    else:
        engine.pause_clock(blackout=saved.animation.blackout_on_stop)
    await engine.broadcast_snapshot(saved)
    return saved


@app.put("/api/houses", response_model=SystemConfig)
async def update_houses(houses: List[HouseConfig]) -> SystemConfig:
    cfg = store.get()
    cfg.houses = houses
    saved = store.save(cfg)
    await engine.broadcast_snapshot(saved)
    return saved


@app.patch("/api/houses/{house_id}/toggle")
async def toggle_house_enabled(
    house_id: str,
    payload: Optional[Dict[str, Any]] = Body(default=None),
) -> Dict[str, Any]:
    """
    Enable or disable a house dynamically so animations scale seamlessly across 1, 2, 3, or N houses.
    When a house is disabled while running, sends a one-time blackout (`colorwc 0,0,0`) to that house's
    controllers so its physical strips do not stay stuck on the last frame color.
    """
    cfg = store.get()
    target = next((h for h in cfg.houses if h.id == house_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail=f"House '{house_id}' not found")

    if payload and "enabled" in payload and payload["enabled"] is not None:
        target.enabled = bool(payload["enabled"])
    else:
        target.enabled = not target.enabled

    saved = store.save(cfg)

    if not target.enabled:
        blackout_tasks = []
        for ctrl in target.controllers:
            if not ctrl.enabled:
                continue
            blackout_tasks.append(
                driver.dispatch_controller_frame(
                    house=target,
                    ctrl=ctrl,
                    segment_colors=[(0, 0, 0)] * max(1, ctrl.segment_count),
                    master_intensity=0,
                    lan_enabled=saved.lan_enabled,
                    cloud_fallback_enabled=saved.cloud_fallback_enabled,
                    api_key=saved.govee_api_key,
                    verbose_logging=saved.verbose_packet_logging,
                    force_send=True,
                )
            )
            engine.latest_controller_colors[ctrl.id] = "#000000"
        if blackout_tasks:
            await asyncio.gather(*blackout_tasks, return_exceptions=True)

    slots = build_virtual_strip_map(saved)
    snapshot = await engine.broadcast_snapshot(saved)
    updated_target = next((h for h in saved.houses if h.id == house_id), target)
    return {
        **saved.model_dump(mode="json"),
        "house_id": updated_target.id,
        "enabled": updated_target.enabled,
        "house": updated_target.model_dump(mode="json"),
        "enabled_houses": len([h for h in saved.houses if h.enabled]),
        "active_segments": len(slots),
        "config": saved.model_dump(mode="json"),
        "live_state": snapshot,
    }


@app.patch("/api/houses/{house_id}/speed")
async def update_house_speed(
    house_id: str,
    payload: Dict[str, Any] = Body(...),
) -> Dict[str, Any]:
    """
    Adjust per-house speed tweening (`speed_multiplier` in [0.25..3.0] or `time_weight` in [0.1..10.0]),
    or reset to `time_weight = 1.0` (Auto Default by light/segment count).
    """
    cfg = store.get()
    target = next((h for h in cfg.houses if h.id == house_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail=f"House '{house_id}' not found")

    if payload.get("reset_default"):
        target.time_weight = 1.0
    elif "time_weight" in payload and payload["time_weight"] is not None:
        target.time_weight = max(0.1, min(10.0, round(float(payload["time_weight"]), 3)))
    elif "speed_multiplier" in payload and payload["speed_multiplier"] is not None:
        spd = max(0.1, min(5.0, float(payload["speed_multiplier"])))
        target.time_weight = max(0.1, min(10.0, round(1.0 / spd, 3)))

    saved = store.save(cfg)
    snapshot = await engine.broadcast_snapshot(saved)
    updated_target = next((h for h in saved.houses if h.id == house_id), target)
    return {
        **saved.model_dump(mode="json"),
        "house_id": updated_target.id,
        "time_weight": updated_target.time_weight,
        "speed_multiplier": round(1.0 / max(0.1, updated_target.time_weight), 2),
        "house": updated_target.model_dump(mode="json"),
        "config": saved.model_dump(mode="json"),
        "live_state": snapshot,
    }


@app.post("/api/houses/add")
async def add_house(payload: Optional[Dict[str, Any]] = Body(default=None)) -> Dict[str, Any]:
    """
    Append a new house (4th, 5th, ..., Nth neighbor house) to the multi-house sync strip.
    """
    cfg = store.get()
    data = payload or {}

    existing_ids = {h.id for h in cfg.houses}
    next_num = len(cfg.houses) + 1
    while f"house-{next_num}" in existing_ids:
        next_num += 1
    new_house_id = str(data.get("id") or f"house-{next_num}").strip()
    if new_house_id in existing_ids:
        raise HTTPException(status_code=400, detail=f"House '{new_house_id}' already exists")

    conn_type = str(data.get("connection_type") or "govee_cloud").strip()
    if conn_type not in ("local_lan", "govee_cloud", "neighbor_bridge", "tailscale_vpn"):
        conn_type = "govee_cloud"

    seg_count = max(1, min(200, int(data.get("segment_count", 12) or 12)))
    ctrl_count = max(1, min(10, int(data.get("controller_count", 1) or 1)))
    sku = str(data.get("sku") or "H705A").strip() or "H705A"
    house_name = str(data.get("name") or f"Neighbor {next_num} (House #{next_num})").strip()

    controllers: List[ControllerConfig] = []
    for c_idx in range(1, ctrl_count + 1):
        controllers.append(
            ControllerConfig(
                id=f"h{next_num}-ctrl-{c_idx}",
                name=f"{house_name} - Strip #{c_idx} ({sku})",
                ip=str(data.get("ip") or "").strip() if c_idx == 1 else "",
                mac=str(data.get("mac") or f"AA:BB:CC:DD:EE:{next_num:02X}:{c_idx:02X}:01").strip().upper(),
                sku=sku,
                segment_count=seg_count,
                enabled=True,
                reversed=False,
                protocol_mode=ProtocolMode.CLOUD_API if conn_type == "govee_cloud" else ProtocolMode.AUTO,
            )
        )

    new_house = HouseConfig(
        id=new_house_id,
        name=house_name,
        order=len(cfg.houses) + 1,
        enabled=bool(data.get("enabled", True)),
        time_weight=float(data.get("time_weight", 1.0) or 1.0),
        connection_type=conn_type,  # type: ignore[arg-type]
        govee_api_key=str(data.get("govee_api_key") or "").strip(),
        bridge_token=str(data.get("bridge_token") or "").strip(),
        notes=str(data.get("notes") or "Added dynamically via Multi-House Manager").strip(),
        controllers=controllers,
    )
    cfg.houses.append(new_house)
    for idx, h in enumerate(sorted(cfg.houses, key=lambda item: (item.order, item.id)), start=1):
        h.order = idx

    saved = store.save(cfg)
    snapshot = await engine.broadcast_snapshot(saved)
    return {
        **saved.model_dump(mode="json"),
        "house": new_house.model_dump(mode="json"),
        "config": saved.model_dump(mode="json"),
        "live_state": snapshot,
    }


@app.delete("/api/houses/{house_id}")
async def delete_house(house_id: str) -> Dict[str, Any]:
    """
    Delete a house (as long as at least 1 house remains), re-number `order = 1..N`,
    save config, and broadcast over `/ws/live`.
    """
    cfg = store.get()
    if len(cfg.houses) <= 1:
        raise HTTPException(status_code=400, detail="At least 1 house must remain configured.")

    target = next((h for h in cfg.houses if h.id == house_id), None)
    if target is None:
        raise HTTPException(status_code=404, detail=f"House '{house_id}' not found")

    cfg.houses = [h for h in cfg.houses if h.id != house_id]
    for idx, h in enumerate(sorted(cfg.houses, key=lambda item: (item.order, item.id)), start=1):
        h.order = idx

    saved = store.save(cfg)
    snapshot = await engine.broadcast_snapshot(saved)
    return {
        **saved.model_dump(mode="json"),
        "deleted_house_id": house_id,
        "config": saved.model_dump(mode="json"),
        "live_state": snapshot,
    }


@app.post("/api/houses/reorder", response_model=SystemConfig)
async def reorder_houses(payload: Any = Body(...)) -> SystemConfig:
    """
    Re-order houses immediately (`order = 1, 2, 3...`), sort `cfg.houses`, persist to disk,
    re-render the virtual strip map, and broadcast over `/ws/live`.
    Accepts either:
    - `{"house_ids": ["house-1", "house-2", "house-3"]}`
    - `{"orders": [{"id": "house-1", "order": 1}, ...]}`
    - `[{"id": "house-1", "order": 1}, ...]`
    - `["house-1", "house-2", "house-3"]`
    """
    cfg = store.get()
    house_map = {h.id: h for h in cfg.houses}
    ordered_ids: List[str] = []

    if isinstance(payload, dict):
        if "house_ids" in payload and isinstance(payload["house_ids"], list):
            ordered_ids = [str(x) for x in payload["house_ids"]]
        elif "orders" in payload and isinstance(payload["orders"], list):
            pairs = sorted(
                payload["orders"],
                key=lambda item: int(item.get("order", 999)) if isinstance(item, dict) else 999,
            )
            ordered_ids = [str(item["id"]) for item in pairs if isinstance(item, dict) and "id" in item]
    elif isinstance(payload, list):
        if payload and isinstance(payload[0], dict):
            pairs = sorted(
                payload,
                key=lambda item: int(item.get("order", 999)) if isinstance(item, dict) else 999,
            )
            ordered_ids = [str(item["id"]) for item in pairs if isinstance(item, dict) and "id" in item]
        else:
            ordered_ids = [str(x) for x in payload]

    if not ordered_ids:
        raise HTTPException(status_code=400, detail="Provide 'house_ids' list or [{'id': ..., 'order': ...}]")

    new_houses: List[HouseConfig] = []
    seen = set()
    for hid in ordered_ids:
        if hid in house_map and hid not in seen:
            seen.add(hid)
            new_houses.append(house_map[hid])

    for h in sorted(cfg.houses, key=lambda item: (item.order, item.id)):
        if h.id not in seen:
            new_houses.append(h)

    for idx, h in enumerate(new_houses, start=1):
        h.order = idx

    cfg.houses = new_houses
    saved = store.save(cfg)
    await engine.broadcast_snapshot(saved)
    return saved


@app.post("/api/houses/{house_id}/discover-cloud")
async def discover_house_cloud_devices(
    house_id: str,
    req: Optional[DiscoverCloudRequest] = Body(default=None),
) -> Dict[str, Any]:
    """
    Query Govee Cloud OpenAPI v1 `/user/devices` using this specific house's `govee_api_key`
    (or an API key supplied in the request body) so a neighbor on a different Wi-Fi network
    can have their Govee controllers discovered and auto-populated into their house slot.
    """
    cfg = store.get()
    house = next((h for h in cfg.houses if h.id == house_id), None)
    if house is None:
        raise HTTPException(status_code=404, detail=f"House '{house_id}' not found")

    if req and req.api_key is not None and req.api_key.strip():
        house.govee_api_key = req.api_key.strip()
        if house.connection_type == "local_lan":
            house.connection_type = "govee_cloud"

    effective_key = (house.govee_api_key or cfg.govee_api_key or "").strip()
    if not effective_key:
        raise HTTPException(
            status_code=400,
            detail=f"No Govee API key configured for house '{house.name}'. Provide 'api_key' in request or set house.govee_api_key.",
        )

    devices = await driver.discover_cloud_devices(effective_key)
    auto_pop = True if req is None else req.auto_populate

    if auto_pop and devices:
        new_ctrls: List[ControllerConfig] = []
        existing_by_mac = {c.mac.upper(): c for c in house.controllers if c.mac}
        for idx, dev in enumerate(devices, start=1):
            prev = existing_by_mac.get(dev.mac.upper())
            fallback_prev = house.controllers[idx - 1] if idx - 1 < len(house.controllers) else None
            seg_cnt = (
                prev.segment_count
                if prev is not None
                else (
                    fallback_prev.segment_count
                    if fallback_prev is not None
                    else _default_segments_for_sku(dev.sku)
                )
            )
            new_ctrls.append(
                ControllerConfig(
                    id=prev.id if prev is not None else f"{house.id}-ctrl-{idx}",
                    name=dev.name or f"{house.name} - {dev.sku} #{idx}",
                    ip=dev.ip or (prev.ip if prev else ""),
                    mac=dev.mac.upper(),
                    sku=dev.sku or "H705A",
                    segment_count=seg_cnt,
                    enabled=True if prev is None else prev.enabled,
                    reversed=False if prev is None else prev.reversed,
                    protocol_mode=ProtocolMode.CLOUD_API if not dev.ip else ProtocolMode.AUTO,
                    brightness_override=prev.brightness_override if prev else None,
                )
            )
        house.controllers = new_ctrls
        if house.connection_type == "local_lan":
            house.connection_type = "govee_cloud"

    saved = store.save(cfg)
    await engine.broadcast_snapshot(saved)
    updated_house = next((h for h in saved.houses if h.id == house_id), house)
    return {
        "house_id": updated_house.id,
        "house_name": updated_house.name,
        "connection_type": updated_house.connection_type,
        "count": len(devices),
        "devices": [d.model_dump() for d in devices],
        "controllers": [c.model_dump() for c in updated_house.controllers],
    }


@app.patch("/api/animation", response_model=AnimationConfig)
async def patch_animation(patch: Dict[str, Any]) -> AnimationConfig:
    cfg = store.get()
    was_running = cfg.animation.running
    merged = cfg.animation.model_dump()
    merged.update(patch)
    cfg.animation = AnimationConfig.model_validate(merged)

    # Persist per-scene speed/color/direction adjustments to the currently active preset
    tunable_keys = {
        "speed",
        "direction",
        "primary_color",
        "secondary_color",
        "accent_color",
        "background_color",
        "background_dim",
        "tail_length",
        "pulse_count",
        "mapping_mode",
    }
    active_id = cfg.active_preset_id or engine.active_preset_id
    if active_id and any(k in patch for k in tunable_keys):
        overrides = dict(cfg.preset_overrides.get(active_id, {}))
        for k in tunable_keys:
            if k in patch:
                overrides[k] = getattr(cfg.animation, k)
                if hasattr(overrides[k], "value"):
                    overrides[k] = overrides[k].value
        cfg.preset_overrides[active_id] = overrides

    if was_running and not cfg.animation.running:
        engine.pause_clock(blackout=cfg.animation.blackout_on_stop)
    elif not was_running and cfg.animation.running:
        engine.resume_clock()

    # If the user explicitly changed primary_color or secondary_color (e.g. clicked a color swatch),
    # exit hardware lightScene mode so the chosen static/custom color is sent directly to the strip.
    if "primary_color" in patch or "secondary_color" in patch or "accent_color" in patch:
        driver.clear_active_cloud_scenes()
        driver._last_sent_rgb.clear()
        driver._last_sent_sig.clear()

    saved = store.save(cfg)
    if was_running and not saved.animation.running and saved.animation.blackout_on_stop:
        await driver.blackout_all_controllers(saved, turn_off=True)
    elif not was_running and saved.animation.running:
        await driver.power_on_all_controllers(saved)
    if saved.animation.running and (
        "primary_color" in patch
        or "secondary_color" in patch
        or "accent_color" in patch
        or "effect" in patch
    ):
        await driver.apply_cloud_scene_to_all(
            saved,
            preset_id=active_id or "custom",
            effect=str(saved.animation.effect.value if hasattr(saved.animation.effect, "value") else saved.animation.effect),
        )
    await engine.broadcast_snapshot(saved)
    return saved.animation


@app.post("/api/animation/play")
async def play_animation() -> Dict[str, Any]:
    cfg = store.get()
    cfg.animation.running = True
    engine.resume_clock()
    driver._last_sent_rgb.clear()
    driver._last_sent_sig.clear()
    driver._last_sent_time.clear()
    saved = store.save(cfg)
    active_pid = saved.active_preset_id or engine.active_preset_id or ""
    preset = next((p for p in engine.PRESETS if p["id"] == active_pid), None)
    await driver.power_on_all_controllers(saved)
    if preset is not None:
        await driver.apply_cloud_scene_to_all(
            saved,
            preset_id=preset["id"],
            effect=str(preset.get("animation", {}).get("effect", "")),
            category=str(preset.get("category", "")),
        )
    snapshot = await engine.broadcast_snapshot(saved)
    return {
        "running": True,
        "blackout_on_stop": saved.animation.blackout_on_stop,
        "phase": round(engine.current_phase, 4),
        "frame": snapshot["frame"],
        "config": saved.model_dump(mode="json"),
        "live_state": snapshot,
    }


@app.post("/api/animation/stop")
async def stop_animation(
    blackout_on_stop: Optional[bool] = None,
    req: Optional[StopAnimationRequest] = Body(default=None),
) -> Dict[str, Any]:
    """
    Immediately stop the master animation clock, freeze `_anchor_phase`, blackout physical
    Govee strips (`colorwc` 0,0,0 + `turn` 0), set live preview segments to `#000000`,
    and push the stopped snapshot over `/ws/live` in <10ms.
    """
    cfg = store.get()
    use_blackout = (
        blackout_on_stop
        if blackout_on_stop is not None
        else (req.blackout_on_stop if req is not None else True)
    )
    turn_off = req.turn_off if req is not None else True

    cfg.animation.running = False
    cfg.animation.blackout_on_stop = use_blackout
    engine.pause_clock(blackout=use_blackout)
    saved = store.save(cfg)

    if use_blackout:
        await driver.blackout_all_controllers(saved, turn_off=turn_off)

    snapshot = await engine.broadcast_snapshot(saved)
    return {
        "running": False,
        "blackout_on_stop": use_blackout,
        "phase": round(engine.current_phase, 4),
        "frame": snapshot["frame"],
        "config": saved.model_dump(mode="json"),
        "live_state": snapshot,
    }


@app.post("/api/animation/pause")
async def pause_animation() -> Dict[str, Any]:
    """
    Freeze the current animation frame in place (`running=False, blackout_on_stop=False`)
    without turning off or blacking out the strips.
    """
    cfg = store.get()
    cfg.animation.running = False
    cfg.animation.blackout_on_stop = False
    engine.pause_clock(blackout=False)
    saved = store.save(cfg)
    snapshot = await engine.broadcast_snapshot(saved)
    return {
        "running": False,
        "paused": True,
        "blackout_on_stop": False,
        "phase": round(engine.current_phase, 4),
        "frame": snapshot["frame"],
        "config": saved.model_dump(mode="json"),
        "live_state": snapshot,
    }


@app.post("/api/animation/sync-clock")
async def resync_master_clock() -> Dict[str, Any]:
    engine.reset_clock()
    await engine.broadcast_snapshot()
    return {"status": "clock_reset", "phase": 0.0, "clock_drift_ms": 0.0}


@app.post("/api/animation/burst")
async def trigger_celebration_burst(req: Optional[BurstRequest] = Body(default=None)) -> Dict[str, Any]:
    """
    One-Tap Street Celebration Burst:
    Temporarily runs a high-speed celebratory effect across all 3 houses for `duration_sec`
    (default 12s), then automatically restores the previous AnimationConfig.
    """
    preset_id = req.preset_id if req else None
    burst_type = req.type if req else "touchdown"
    duration_sec = req.duration_sec if req else 12.0
    return await engine.trigger_burst(
        preset_id=preset_id,
        burst_type=burst_type,
        duration_sec=duration_sec,
    )


@app.get("/api/playlist", response_model=PlaylistConfig)
async def get_playlist() -> PlaylistConfig:
    return store.get().playlist


@app.patch("/api/playlist")
async def patch_playlist(patch: Dict[str, Any] = Body(...)) -> Dict[str, Any]:
    cfg = store.get()
    merged = cfg.playlist.model_dump()
    merged.update(patch)
    cfg.playlist = PlaylistConfig.model_validate(merged)
    engine._last_playlist_switch_mono = time.monotonic_ns() / 1e9
    saved = store.save(cfg)
    await engine.broadcast_snapshot(saved)
    return {
        **saved.playlist.model_dump(),
        "playlist": saved.playlist.model_dump(),
        "config": saved.model_dump(mode="json"),
    }


@app.get("/api/schedule")
async def get_schedule() -> Dict[str, Any]:
    cfg = store.get()
    return engine.compute_schedule_status(cfg.schedule)


@app.patch("/api/schedule")
async def patch_schedule(patch: Dict[str, Any] = Body(...)) -> Dict[str, Any]:
    cfg = store.get()
    patch_copy = dict(patch)
    apply_now_if_in_window = bool(patch_copy.pop("apply_now_if_in_window", True))

    merged = cfg.schedule.model_dump()
    merged.update(patch_copy)
    cfg.schedule = ScheduleConfig.model_validate(merged)
    engine._last_schedule_minute_key = ""
    saved = store.save(cfg)

    status = engine.compute_schedule_status(saved.schedule)
    if saved.schedule.enabled and apply_now_if_in_window and status["is_within_active_window"]:
        saved = await engine.apply_scheduled_start(
            saved,
            trigger_label=f"active_window_start ({status['current_local_hhmm']} {status['tz_abbrev']})",
        )
        status = engine.compute_schedule_status(saved.schedule)
    else:
        await engine.broadcast_snapshot(saved)

    return {
        **status,
        "schedule": status,
        "schedule_status": status,
        "config": saved.model_dump(mode="json"),
    }


def _build_enriched_presets(cfg: SystemConfig) -> List[Dict[str, Any]]:
    enriched: List[Dict[str, Any]] = []
    for p in engine.PRESETS:
        pid = p["id"]
        default_anim = dict(p["animation"])
        override = cfg.preset_overrides.get(pid, {})
        merged_anim = {**default_anim, **override}
        govee_scene = driver.resolve_govee_light_scene(
            pid,
            effect=str(merged_anim.get("effect", "")),
            category=str(p.get("category", "")),
        )
        enriched.append(
            {
                **p,
                "animation": merged_anim,
                "default_animation": default_anim,
                "is_customized": bool(override),
                "govee_scene": govee_scene,
            }
        )
    return enriched


@app.get("/api/presets")
async def list_presets() -> List[Dict[str, Any]]:
    cfg = store.get()
    return _build_enriched_presets(cfg)


@app.post("/api/presets/{preset_id}", response_model=SystemConfig)
async def apply_preset(preset_id: str) -> SystemConfig:
    preset = next((p for p in engine.PRESETS if p["id"] == preset_id), None)
    if not preset:
        raise HTTPException(status_code=404, detail=f"Preset '{preset_id}' not found")
    cfg = store.get()
    merged = cfg.animation.model_dump()
    merged.update(preset["animation"])
    merged.update(cfg.preset_overrides.get(preset_id, {}))
    merged["running"] = True
    cfg.animation = AnimationConfig.model_validate(merged)
    cfg.active_preset_id = preset_id
    engine.active_preset_id = preset_id
    engine._last_playlist_switch_mono = time.monotonic_ns() / 1e9
    engine.resume_clock()
    driver._last_sent_rgb.clear()
    driver._last_sent_sig.clear()
    saved = store.save(cfg)

    # Power on and trigger native Govee Cloud hardware `lightScene` across all enabled houses/controllers
    await driver.apply_cloud_scene_to_all(
        saved,
        preset_id=preset_id,
        effect=str(merged.get("effect", "")),
        category=str(preset.get("category", "")),
    )

    await engine.broadcast_snapshot(saved)
    return saved


@app.patch("/api/presets/{preset_id}")
async def customize_preset(preset_id: str, patch: Dict[str, Any] = Body(...)) -> Dict[str, Any]:
    preset = next((p for p in engine.PRESETS if p["id"] == preset_id), None)
    if not preset:
        raise HTTPException(status_code=404, detail=f"Preset '{preset_id}' not found")
    cfg = store.get()
    allowed = {
        "speed",
        "direction",
        "primary_color",
        "secondary_color",
        "accent_color",
        "background_color",
        "background_dim",
        "tail_length",
        "pulse_count",
        "mapping_mode",
    }
    current_ovr = dict(cfg.preset_overrides.get(preset_id, {}))
    for k, v in patch.items():
        if k in allowed and v is not None:
            current_ovr[k] = v
    cfg.preset_overrides[preset_id] = current_ovr

    if "primary_color" in patch or "secondary_color" in patch or "accent_color" in patch:
        driver.clear_active_cloud_scenes()
        driver._last_sent_rgb.clear()
        driver._last_sent_sig.clear()

    # Also apply immediately if this preset is active (or if apply_now is set)
    if cfg.active_preset_id == preset_id or engine.active_preset_id == preset_id or patch.get("apply_now", True):
        merged = cfg.animation.model_dump()
        merged.update(preset["animation"])
        merged.update(current_ovr)
        cfg.animation = AnimationConfig.model_validate(merged)
        cfg.active_preset_id = preset_id
        engine.active_preset_id = preset_id
        driver._last_sent_rgb.clear()

    saved = store.save(cfg)
    if saved.animation.running and (
        "primary_color" in patch or "secondary_color" in patch or "accent_color" in patch
    ):
        await driver.apply_cloud_scene_to_all(
            saved,
            preset_id=preset_id,
            effect=str(saved.animation.effect.value if hasattr(saved.animation.effect, "value") else saved.animation.effect),
            category=str(preset.get("category", "")),
        )
    await engine.broadcast_snapshot(saved)
    enriched = next((p for p in _build_enriched_presets(saved) if p["id"] == preset_id), None)
    return {
        "preset_id": preset_id,
        "preset": enriched,
        "config": saved.model_dump(mode="json"),
    }


@app.post("/api/presets/{preset_id}/reset")
async def reset_preset_customization(preset_id: str) -> Dict[str, Any]:
    preset = next((p for p in engine.PRESETS if p["id"] == preset_id), None)
    if not preset:
        raise HTTPException(status_code=404, detail=f"Preset '{preset_id}' not found")
    cfg = store.get()
    cfg.preset_overrides.pop(preset_id, None)
    if cfg.active_preset_id == preset_id or engine.active_preset_id == preset_id:
        merged = cfg.animation.model_dump()
        merged.update(preset["animation"])
        cfg.animation = AnimationConfig.model_validate(merged)
        driver._last_sent_rgb.clear()
    saved = store.save(cfg)
    await engine.broadcast_snapshot(saved)
    enriched = next((p for p in _build_enriched_presets(saved) if p["id"] == preset_id), None)
    return {
        "preset_id": preset_id,
        "preset": enriched,
        "config": saved.model_dump(mode="json"),
    }


@app.get("/api/state")
async def get_live_state() -> Dict[str, Any]:
    cfg = store.get()
    if not engine.latest_segments:
        engine.render_frame_at(cfg)
    return engine.build_live_snapshot(cfg)


@app.get("/api/logs")
async def get_packet_logs(limit: int = 100) -> Dict[str, Any]:
    entries = [e.model_dump() for e in list(driver.packet_logs)[: max(1, min(300, limit))]]
    return {"count": len(entries), "stats": driver.stats, "logs": entries}


@app.post("/api/logs/clear")
async def clear_packet_logs() -> Dict[str, Any]:
    driver.packet_logs.clear()
    return {"status": "cleared"}


@app.get("/api/discover")
async def list_discovered_devices() -> Dict[str, Any]:
    _seed_configured_lan_devices(store.get())
    devices = sorted(driver.discovered_devices.values(), key=lambda d: (d.ip or "zzz", d.mac))
    return {"count": len(devices), "devices": [d.model_dump() for d in devices]}


@app.post("/api/discover/scan")
async def trigger_device_scan() -> Dict[str, Any]:
    cfg = store.get()
    _seed_configured_lan_devices(cfg)
    known_ips = [c.ip for h in cfg.houses for c in h.controllers if c.ip]
    house_keys = [h.govee_api_key for h in cfg.houses if h.govee_api_key]
    devices = await driver.scan_lan_and_cloud(
        known_ips=known_ips,
        api_key=cfg.govee_api_key,
        extra_api_keys=house_keys,
    )
    return {"count": len(devices), "devices": [d.model_dump() for d in devices]}


@app.post("/api/controllers/{controller_id}/test")
async def test_controller(
    controller_id: str,
    req: Optional[TestControllerRequest] = Body(default=None),
) -> Dict[str, Any]:
    """
    Send a quick 1-click test color pulse (`turn(1)` + `brightness(100)` + `colorwc` + `devStatus`)
    to a specific controller so the user can verify physical light connectivity immediately.
    """
    cfg = store.get()
    target_house: Optional[HouseConfig] = None
    target_ctrl: Optional[ControllerConfig] = None
    for h in cfg.houses:
        for c in h.controllers:
            if c.id == controller_id:
                target_house = h
                target_ctrl = c
                break
        if target_ctrl is not None:
            break

    if target_house is None or target_ctrl is None:
        raise HTTPException(status_code=404, detail=f"Controller '{controller_id}' not found")

    color_hex = (req.color if req and req.color else cfg.animation.primary_color) or "#00f5d4"
    rgb = hex_to_rgb(color_hex)
    result = await driver.test_controller_pulse(
        house=target_house,
        ctrl=target_ctrl,
        rgb=rgb,
        api_key=cfg.govee_api_key,
        verbose_logging=cfg.verbose_packet_logging,
    )
    await engine.broadcast_snapshot(cfg)
    return result


@app.patch("/api/controllers/{controller_id}/zones")
async def update_controller_wall_zones(
    controller_id: str,
    patch: Dict[str, Any] = Body(...),
) -> Dict[str, Any]:
    """
    Update a controller's 3D house wall segment distribution (`wall_zones`, e.g.
    `[{"wall": "front", "segments": 8}, {"wall": "right", "segments": 7}]`).
    """
    cfg = store.get()
    target_ctrl: Optional[ControllerConfig] = None
    for h in cfg.houses:
        for c in h.controllers:
            if c.id == controller_id:
                target_ctrl = c
                break
        if target_ctrl is not None:
            break

    if target_ctrl is None:
        raise HTTPException(status_code=404, detail=f"Controller '{controller_id}' not found")

    raw_zones = patch.get("wall_zones", [])
    cleaned_zones: List[Dict[str, Any]] = []
    valid_walls = {"front", "left", "right", "back"}
    for item in raw_zones if isinstance(raw_zones, list) else []:
        if not isinstance(item, dict):
            continue
        w = str(item.get("wall", "front")).strip().lower()
        if w not in valid_walls:
            w = "front"
        cnt = max(0, int(item.get("segments", 0) or 0))
        if cnt > 0:
            cleaned_zones.append({"wall": w, "segments": cnt})

    target_ctrl.wall_zones = cleaned_zones
    if "reversed" in patch and isinstance(patch["reversed"], bool):
        target_ctrl.reversed = patch["reversed"]

    saved = store.save(cfg)
    await engine.broadcast_snapshot(saved)
    return {
        "controller_id": controller_id,
        "wall_zones": target_ctrl.wall_zones,
        "segment_walls": target_ctrl.get_segment_walls(),
        "config": saved.model_dump(mode="json"),
    }


@app.post("/api/controllers/{controller_id}/locate-segment")
async def locate_controller_segment(
    controller_id: str,
    body: Dict[str, Any] = Body(...),
) -> Dict[str, Any]:
    """
    Corner Calibration Finder: Lights up a single `segment_index` (`0..N-1`) in bright
    spotlight White/Red (`#ffffff`) and all other segments in dim Blue (`#001b44`) via
    Govee Cloud `segmentedColorRgb` so the user can visually identify where the physical
    light strip turns the corner from Front -> Left/Right Side -> Back.
    """
    cfg = store.get()
    target_house: Optional[HouseConfig] = None
    target_ctrl: Optional[ControllerConfig] = None
    for h in cfg.houses:
        for c in h.controllers:
            if c.id == controller_id:
                target_house = h
                target_ctrl = c
                break
        if target_ctrl is not None:
            break

    if target_house is None or target_ctrl is None:
        raise HTTPException(status_code=404, detail=f"Controller '{controller_id}' not found")

    n_segs = max(1, int(target_ctrl.segment_count or 12))
    seg_idx = max(0, min(n_segs - 1, int(body.get("segment_index", 0) or 0)))
    effective_key = (target_house.govee_api_key or cfg.govee_api_key or "").strip()

    driver.clear_active_cloud_scenes()
    sent_cloud = False
    if effective_key and target_ctrl.mac and driver._http_client:
        headers = {"Govee-API-Key": effective_key, "Content-Type": "application/json"}
        other_segs = [i for i in range(n_segs) if i != seg_idx]
        try:
            if other_segs:
                await driver._http_client.post(
                    f"{driver.CLOUD_BASE_URL}/device/control",
                    headers=headers,
                    json={
                        "requestId": str(uuid.uuid4()),
                        "payload": {
                            "sku": target_ctrl.sku or "H705E",
                            "device": target_ctrl.mac,
                            "capability": {
                                "type": "devices.capabilities.segment_color_setting",
                                "instance": "segmentedColorRgb",
                                "value": {"segment": other_segs, "rgb": 0x001845},
                            },
                        },
                    },
                )
            resp = await driver._http_client.post(
                f"{driver.CLOUD_BASE_URL}/device/control",
                headers=headers,
                json={
                    "requestId": str(uuid.uuid4()),
                    "payload": {
                        "sku": target_ctrl.sku or "H705E",
                        "device": target_ctrl.mac,
                        "capability": {
                            "type": "devices.capabilities.segment_color_setting",
                            "instance": "segmentedColorRgb",
                            "value": {"segment": [seg_idx], "rgb": 0xFFFFFF},
                        },
                    },
                },
            )
            sent_cloud = resp.status_code == 200
        except Exception:
            pass

    return {
        "controller_id": controller_id,
        "segment_index": seg_idx,
        "total_segments": n_segs,
        "sent_cloud": sent_cloud,
    }



@app.get("/api/bridges")
async def list_neighbor_bridges() -> Dict[str, Any]:
    return {
        "connected_count": len(driver.connected_bridges),
        "connected_house_ids": list(driver.connected_bridges.keys()),
        "bridges": list(driver.bridge_info.values()),
    }


@app.get("/api/neighbor-bridge.py", response_class=PlainTextResponse)
async def download_neighbor_bridge_script(
    request: Request,
    house_id: str = "house-1",
    server: str = "",
    token: str = "",
) -> PlainTextResponse:
    """
    Generate a lightweight standalone Python script that a neighbor can run on any computer
    or Raspberry Pi on their Wi-Fi network. It connects outbound to `/ws/neighbor-bridge/{house_id}`,
    auto-discovers Govee LAN controllers on the neighbor's Wi-Fi, reports them to the master
    server, and relays 25 FPS UDP `:4003` (`colorwc` / `ptReal`) packets locally.
    """
    if not server:
        scheme = "wss" if request.url.scheme == "https" else "ws"
        host = request.headers.get("host", "localhost:8098")
        server = f"{scheme}://{host}"
    server = server.rstrip("/")

    script = f'''#!/usr/bin/env python3
"""
Govee Multi-House Sync — Lightweight Neighbor Bridge Agent
House ID : {house_id}
Server   : {server}/ws/neighbor-bridge/{house_id}

Run on any computer / Raspberry Pi on the neighbor's Wi-Fi:
    pip install websockets
    python3 neighbor-bridge-{house_id}.py
"""
import argparse
import asyncio
import json
import socket
import struct
import sys
import time

HOUSE_ID = {json.dumps(house_id)}
DEFAULT_SERVER_BASE = {json.dumps(server)}
DEFAULT_TOKEN = {json.dumps(token)}
SERVER_WS_URL = {json.dumps(f"{server}/ws/neighbor-bridge/{house_id}" + (f"?token={token}" if token else ""))}
MULTICAST_GROUP = "239.255.255.250"
SCAN_PORT = 4001
LISTEN_PORT = 4002
CONTROL_PORT = 4003


def _resolve_cli_config() -> tuple:
    parser = argparse.ArgumentParser(description="Govee Multi-House Neighbor Bridge Agent", add_help=False)
    parser.add_argument("--house-id", default=HOUSE_ID)
    parser.add_argument("--server", default=DEFAULT_SERVER_BASE)
    parser.add_argument("--token", default=DEFAULT_TOKEN)
    args, _ = parser.parse_known_args()
    hid = str(args.house_id or HOUSE_ID).strip()
    srv = str(args.server or DEFAULT_SERVER_BASE).strip().rstrip("/")
    tok = str(args.token or DEFAULT_TOKEN).strip()
    if srv.startswith("http://"):
        srv = "ws://" + srv[len("http://"):]
    elif srv.startswith("https://"):
        srv = "wss://" + srv[len("https://"):]
    ws_url = f"{{srv}}/ws/neighbor-bridge/{{hid}}" + (f"?token={{tok}}" if tok else "")
    return hid, ws_url



def discover_local_govee_devices(timeout: float = 1.2) -> list:
    devices = {{}}
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.settimeout(0.25)
    try:
        sock.bind(("0.0.0.0", LISTEN_PORT))
    except OSError:
        pass

    scan_pkt = json.dumps({{"msg": {{"cmd": "scan", "data": {{"account_topic": "reserve"}}}}}}).encode("utf-8")
    for target in (MULTICAST_GROUP, "255.255.255.255"):
        try:
            sock.sendto(scan_pkt, (target, SCAN_PORT))
        except OSError:
            pass

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data, addr = sock.recvfrom(4096)
            payload = json.loads(data.decode("utf-8", errors="ignore"))
            msg = payload.get("msg", {{}})
            if msg.get("cmd") == "scan":
                d = msg.get("data", {{}})
                ip = d.get("ip") or addr[0]
                mac = (d.get("device") or ip).upper()
                sku = d.get("sku") or "Govee-LAN"
                devices[mac] = {{"ip": ip, "mac": mac, "sku": sku, "name": f"{{sku}} ({{ip}})"}}
        except socket.timeout:
            continue
        except Exception:
            break
    sock.close()
    return list(devices.values())


async def run_bridge() -> None:
    try:
        import websockets
    except ImportError:
        print("Installing websockets package...", file=sys.stderr)
        import subprocess
        subprocess.check_call([sys.executable, "-m", "pip", "install", "websockets"])
        import websockets

    global HOUSE_ID, SERVER_WS_URL
    HOUSE_ID, SERVER_WS_URL = _resolve_cli_config()
    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    udp_sock.setblocking(False)
    mac_to_ip = {{}}

    while True:
        try:
            print(f"[Bridge:{{HOUSE_ID}}] Connecting to {{SERVER_WS_URL}} ...")
            async with websockets.connect(SERVER_WS_URL, ping_interval=20, ping_timeout=20) as ws:
                print(f"[Bridge:{{HOUSE_ID}}] Connected! Scanning local Wi-Fi for Govee controllers...")
                found = discover_local_govee_devices()
                for d in found:
                    mac_to_ip[d["mac"].upper()] = d["ip"]
                await ws.send(json.dumps({{"type": "discovered_devices", "house_id": HOUSE_ID, "devices": found}}))
                print(f"[Bridge:{{HOUSE_ID}}] Reported {{len(found)}} local Govee controller(s): {{found}}")

                async for raw_msg in ws:
                    msg = json.loads(raw_msg)
                    mtype = msg.get("type")
                    if mtype in ("udp_relay", "udp_send"):
                        target_ip = msg.get("ip") or mac_to_ip.get(str(msg.get("mac", "")).upper(), "")
                        port = int(msg.get("port", CONTROL_PORT))
                        if not target_ip and mac_to_ip:
                            target_ip = next(iter(mac_to_ip.values()))
                        if target_ip:
                            for pkt in msg.get("messages", []):
                                raw_bytes = json.dumps(pkt, separators=(",", ":")).encode("utf-8")
                                try:
                                    udp_sock.sendto(raw_bytes, (target_ip, port))
                                except OSError:
                                    pass
                    elif mtype in ("scan", "welcome"):
                        found = discover_local_govee_devices()
                        for d in found:
                            mac_to_ip[d["mac"].upper()] = d["ip"]
                        await ws.send(json.dumps({{"type": "discovered_devices", "house_id": HOUSE_ID, "devices": found}}))
        except Exception as exc:
            print(f"[Bridge:{{HOUSE_ID}}] Reconnecting in 3s ({{exc}})...")
            await asyncio.sleep(3.0)


if __name__ == "__main__":
    asyncio.run(run_bridge())
'''
    return PlainTextResponse(content=script, media_type="text/x-python")


@app.post("/api/power")
async def control_power(req: PowerRequest) -> Dict[str, Any]:
    cfg = store.get()
    results = []
    for h in cfg.houses:
        if req.house_id and h.id != req.house_id:
            continue
        effective_key = (h.govee_api_key or cfg.govee_api_key or "").strip()
        for c in h.controllers:
            if req.controller_id and c.id != req.controller_id:
                continue
            ok = await driver.send_power_command(
                c, turn_on=req.turn_on, api_key=effective_key, house_id=h.id
            )
            results.append({"house_id": h.id, "controller_id": c.id, "ip": c.ip, "sent": ok})
    return {"turn_on": req.turn_on, "results": results}


# --- Authentication (Google OAuth2 + GIS ID Token + GitHub OAuth2) & Authorized Users ---


@app.get("/api/auth/status")
async def auth_status(request: Request) -> Dict[str, Any]:
    user = auth_manager.get_current_user(request)
    external = is_external_request(request)
    return {
        "authenticated": user is not None,
        "user": user,
        "google_enabled": auth_manager.google_enabled,
        "github_enabled": auth_manager.github_enabled,
        "google_client_id": auth_manager.google_client_id,
        "google_gsi_client_id": auth_manager.google_gsi_client_id,
        "github_client_id": auth_manager.github_client_id,
        "oauth_bridge_base": auth_manager.oauth_bridge_base,
        "owner": OWNER_EMAIL,
        "auth_required": external,
    }


@app.post("/api/auth/logout")
async def auth_logout(response: Response) -> Dict[str, Any]:
    auth_manager.clear_session_cookie(response)
    return {"status": "logged_out", "authenticated": False}


@app.get("/api/auth/bridge-callback")
async def auth_bridge_callback(
    request: Request,
    handoff: str = "",
    mobile: int = 0,
    redirect_scheme: str = "",
) -> Response:
    result = await auth_manager.poll_or_consume_bridge_handoff(handoff)
    status = result.get("status")
    if status == "pending":
        raise HTTPException(status_code=400, detail="OAuth handoff session expired or not found")
    if status == "denied" or not result.get("authorized"):
        return auth_manager.build_access_denied_response(request, str(result.get("email") or "unknown"))

    is_mobile = bool(mobile or redirect_scheme or result.get("mobile") or handoff.startswith("govee_mob_"))
    scheme = redirect_scheme or str(result.get("redirect_scheme") or ("goveesync://auth" if is_mobile else ""))
    next_path = str(result.get("next") or "/")
    return auth_manager.build_oauth_success_response(
        request=request,
        token=str(result["token"]),
        user=result["user"],
        mobile=is_mobile,
        redirect_scheme=scheme,
        next_path=next_path,
        handoff=handoff,
    )


@app.get("/api/auth/bridge-poll/{handoff}")
async def auth_bridge_poll(
    request: Request,
    response: Response,
    handoff: str,
) -> Dict[str, Any]:
    result = await auth_manager.poll_or_consume_bridge_handoff(handoff)
    status = result.get("status", "pending")
    if status == "completed" and result.get("token"):
        auth_manager.set_session_cookie(response, str(result["token"]), request)
        return {
            "ready": True,
            "status": "completed",
            "authenticated": True,
            "token": result["token"],
            "user": result["user"],
        }
    if status == "denied":
        email = str(result.get("email") or "unknown")
        return {
            "ready": False,
            "status": "denied",
            "authenticated": False,
            "email": email,
            "detail": access_denied_message(email),
        }
    return {"ready": False, "status": "pending", "authenticated": False}


@app.get("/api/auth/google/login")
async def auth_google_login(
    request: Request,
    mobile: int = 0,
    redirect_scheme: str = "",
    next: str = "/",
    handoff: str = "",
    direct: str = "",
    bridge: str = "",
) -> Response:
    is_mobile = bool(mobile or redirect_scheme or handoff)
    if auth_manager.should_use_oauth_bridge("google", direct=direct, bridge=bridge):
        handoff_id, bridge_url = auth_manager.create_bridge_handoff(
            provider="google",
            mobile=is_mobile,
            redirect_scheme=redirect_scheme,
            next_path=next,
            custom_handoff=handoff,
        )
        resp = RedirectResponse(url=bridge_url, status_code=302)
        resp.headers["X-OAuth-Handoff"] = handoff_id
        return resp

    if not auth_manager.google_client_id:
        raise HTTPException(status_code=503, detail="Google OAuth2 client ID is not configured")

    base_url = auth_manager.resolve_public_base_url(request)
    callback_url = f"{base_url}/api/auth/google/callback"
    state = auth_manager.encode_oauth_state(
        mobile=is_mobile,
        redirect_scheme=redirect_scheme,
        next_path=next,
        handoff=handoff,
    )
    params = {
        "client_id": auth_manager.google_client_id,
        "redirect_uri": callback_url,
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "access_type": "online",
        "prompt": "select_account",
    }
    url = f"{auth_manager.GOOGLE_AUTH_URL}?{urllib.parse.urlencode(params)}"
    return RedirectResponse(url=url, status_code=302)


@app.get("/api/auth/google/callback")
async def auth_google_callback(
    request: Request,
    code: str = "",
    state: str = "",
    mobile: int = 0,
    redirect_scheme: str = "",
    error: str = "",
) -> Response:
    if error:
        raise HTTPException(status_code=400, detail=f"Google OAuth error: {error}")
    if not code:
        raise HTTPException(status_code=400, detail="Missing OAuth authorization code")

    state_info = auth_manager.decode_oauth_state(state)
    is_mobile = bool(mobile or redirect_scheme or state_info.get("mobile"))
    scheme = redirect_scheme or state_info.get("redirect_scheme", "")
    next_path = state_info.get("next", "/")
    handoff = state_info.get("handoff", "")

    base_url = auth_manager.resolve_public_base_url(request)
    callback_url = f"{base_url}/api/auth/google/callback"
    profile = await auth_manager.exchange_google_code(code=code, redirect_uri=callback_url)
    email = str(profile.get("email") or "").strip().lower()

    if not auth_manager.is_email_authorized(email):
        return auth_manager.build_access_denied_response(request, email)

    token = auth_manager.create_session_token(
        email=email,
        name=profile.get("name", ""),
        picture=profile.get("picture", ""),
        provider="google",
    )
    user = auth_manager.verify_session_token(token, check_authorized_list=False) or profile
    return auth_manager.build_oauth_success_response(
        request=request,
        token=token,
        user=user,
        mobile=is_mobile,
        redirect_scheme=scheme,
        next_path=next_path,
        handoff=handoff,
    )


@app.post("/api/auth/google/id-token")
async def auth_google_id_token(
    request: Request,
    response: Response,
    req: GoogleIdTokenRequest = Body(...),
) -> Dict[str, Any]:
    raw_tok = (req.id_token or req.credential or req.token or "").strip()
    profile = await auth_manager.verify_google_id_token(raw_tok)
    email = str(profile.get("email") or "").strip().lower()

    if not auth_manager.is_email_authorized(email):
        raise HTTPException(status_code=403, detail=access_denied_message(email))

    token = auth_manager.create_session_token(
        email=email,
        name=profile.get("name", ""),
        picture=profile.get("picture", ""),
        provider="google",
    )
    auth_manager.set_session_cookie(response, token, request)
    user = auth_manager.verify_session_token(token, check_authorized_list=False) or profile
    return {
        "authenticated": True,
        "token": token,
        "user": user,
    }


@app.get("/api/auth/github/login")
async def auth_github_login(
    request: Request,
    mobile: int = 0,
    redirect_scheme: str = "",
    next: str = "/",
    handoff: str = "",
    direct: str = "",
    bridge: str = "",
) -> Response:
    is_mobile = bool(mobile or redirect_scheme or handoff)
    if auth_manager.should_use_oauth_bridge("github", direct=direct, bridge=bridge):
        handoff_id, bridge_url = auth_manager.create_bridge_handoff(
            provider="github",
            mobile=is_mobile,
            redirect_scheme=redirect_scheme,
            next_path=next,
            custom_handoff=handoff,
        )
        resp = RedirectResponse(url=bridge_url, status_code=302)
        resp.headers["X-OAuth-Handoff"] = handoff_id
        return resp

    if not auth_manager.github_client_id:
        raise HTTPException(status_code=503, detail="GitHub OAuth2 client ID is not configured")

    base_url = auth_manager.resolve_public_base_url(request)
    callback_url = f"{base_url}/api/auth/github/callback"
    state = auth_manager.encode_oauth_state(
        mobile=is_mobile,
        redirect_scheme=redirect_scheme,
        next_path=next,
        handoff=handoff,
    )
    params = {
        "client_id": auth_manager.github_client_id,
        "redirect_uri": callback_url,
        "scope": "read:user user:email",
        "state": state,
    }
    url = f"{auth_manager.GITHUB_AUTH_URL}?{urllib.parse.urlencode(params)}"
    return RedirectResponse(url=url, status_code=302)


@app.get("/api/auth/github/callback")
async def auth_github_callback(
    request: Request,
    code: str = "",
    state: str = "",
    mobile: int = 0,
    redirect_scheme: str = "",
    error: str = "",
) -> Response:
    if error:
        raise HTTPException(status_code=400, detail=f"GitHub OAuth error: {error}")
    if not code:
        raise HTTPException(status_code=400, detail="Missing OAuth authorization code")

    state_info = auth_manager.decode_oauth_state(state)
    is_mobile = bool(mobile or redirect_scheme or state_info.get("mobile"))
    scheme = redirect_scheme or state_info.get("redirect_scheme", "")
    next_path = state_info.get("next", "/")
    handoff = state_info.get("handoff", "")

    base_url = auth_manager.resolve_public_base_url(request)
    callback_url = f"{base_url}/api/auth/github/callback"
    profile = await auth_manager.exchange_github_code(code=code, redirect_uri=callback_url)
    email = str(profile.get("email") or "").strip().lower()

    if not auth_manager.is_email_authorized(email):
        return auth_manager.build_access_denied_response(request, email)

    token = auth_manager.create_session_token(
        email=email,
        name=profile.get("name", ""),
        picture=profile.get("picture", ""),
        provider="github",
    )
    user = auth_manager.verify_session_token(token, check_authorized_list=False) or profile
    return auth_manager.build_oauth_success_response(
        request=request,
        token=token,
        user=user,
        mobile=is_mobile,
        redirect_scheme=scheme,
        next_path=next_path,
        handoff=handoff,
    )


@app.get("/api/auth/users")
async def list_authorized_users(request: Request) -> Dict[str, Any]:
    auth_manager.require_authenticated_user(request)
    cfg = store.get()
    return {
        "owner": OWNER_EMAIL,
        "authorized_emails": normalize_authorized_emails(cfg.authorized_emails),
    }


@app.post("/api/auth/users")
async def add_authorized_user(
    request: Request,
    req: AddAuthorizedUserRequest = Body(...),
) -> Dict[str, Any]:
    auth_manager.require_authenticated_user(request)
    email = (req.email or "").strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="Provide a valid email address")

    cfg = store.get()
    emails = normalize_authorized_emails(cfg.authorized_emails)
    if email not in emails:
        emails.append(email)
    cfg.authorized_emails = emails
    saved = store.save(cfg)
    return {
        "owner": OWNER_EMAIL,
        "added": email,
        "authorized_emails": saved.authorized_emails,
    }


@app.delete("/api/auth/users/{email}")
async def remove_authorized_user(request: Request, email: str) -> Dict[str, Any]:
    auth_manager.require_authenticated_user(request)
    target = urllib.parse.unquote(email or "").strip().lower()
    if target == OWNER_EMAIL:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot remove permanent owner email {OWNER_EMAIL}",
        )
    cfg = store.get()
    cfg.authorized_emails = [
        em for em in normalize_authorized_emails(cfg.authorized_emails) if em != target
    ]
    saved = store.save(cfg)
    return {
        "owner": OWNER_EMAIL,
        "removed": target,
        "authorized_emails": saved.authorized_emails,
    }


# --- Android APK Download, Versioning & Release Archive ---


def _resolve_apk_path() -> Path:
    candidate = store.data_dir / "govee-multi-house-sync.apk"
    if candidate.exists():
        return candidate
    return Path("/mnt/media/govee_lights_sync/data/govee-multi-house-sync.apk")


def _resolve_release_apk_path(filename: str) -> Optional[Path]:
    safe_name = Path(filename).name
    for base in (store.data_dir / "releases", Path("/mnt/media/govee_lights_sync/data/releases")):
        candidate = base / safe_name
        if candidate.exists() and candidate.is_file():
            return candidate
    return None


def _load_apk_releases_manifest() -> List[Dict[str, Any]]:
    manifest_candidates = [
        store.data_dir / "apk_releases.json",
        Path("/mnt/media/govee_lights_sync/data/apk_releases.json"),
    ]
    releases: List[Dict[str, Any]] = []
    for mpath in manifest_candidates:
        if mpath.exists() and mpath.is_file():
            try:
                raw = json.loads(mpath.read_text(encoding="utf-8"))
                items = raw.get("releases", []) if isinstance(raw, dict) else (raw if isinstance(raw, list) else [])
                for item in items:
                    if isinstance(item, dict) and item.get("version_name"):
                        ver_name = str(item.get("version_name")).strip()
                        ver_code = int(item.get("version_code") or 1)
                        fname = str(item.get("filename") or f"Govee-Sync-Studio-v{ver_name}-b{ver_code}.apk")
                        releases.append(
                            {
                                "version_name": ver_name,
                                "version_code": ver_code,
                                "filename": fname,
                                "size_bytes": int(item.get("size_bytes") or 0),
                                "sha256": str(item.get("sha256") or ""),
                                "released_at": str(item.get("released_at") or ""),
                                "changelog": list(item.get("changelog") or []),
                                "download_url": f"/api/apk/download?version={urllib.parse.quote(ver_name)}",
                            }
                        )
                if releases:
                    break
            except Exception:
                pass

    if not releases:
        apk_path = _resolve_apk_path()
        if apk_path.exists() and apk_path.is_file():
            st = apk_path.stat()
            h = hashlib.sha256()
            try:
                with apk_path.open("rb") as f:
                    for chunk in iter(lambda: f.read(1024 * 1024), b""):
                        h.update(chunk)
                sha_hex = h.hexdigest()
            except Exception:
                sha_hex = ""
            rel_at = dt.datetime.fromtimestamp(st.st_mtime, tz=dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            releases.append(
                {
                    "version_name": "3.1.0",
                    "version_code": 4,
                    "filename": "Govee-Sync-Studio-v3.1.0-b4.apk",
                    "size_bytes": st.st_size,
                    "sha256": sha_hex,
                    "released_at": rel_at,
                    "changelog": [
                        "APK versioning & release archive system",
                        "In-app OTA update checker & version rollback list",
                    ],
                    "download_url": "/api/apk/download?version=3.1.0",
                }
            )

    releases.sort(key=lambda r: int(r.get("version_code") or 0), reverse=True)
    return releases


@app.get("/api/apk/info")
async def get_apk_info(request: Request) -> Dict[str, Any]:
    auth_manager.require_authenticated_user(request)
    releases = _load_apk_releases_manifest()
    apk_path = _resolve_apk_path()
    exists = bool(releases) or (apk_path.exists() and apk_path.is_file())
    if releases:
        latest = releases[0]
        return {
            "available": exists,
            "version_name": latest["version_name"],
            "version_code": latest["version_code"],
            "size_bytes": latest["size_bytes"] or (apk_path.stat().st_size if apk_path.exists() else 0),
            "sha256": latest["sha256"],
            "released_at": latest["released_at"],
            "filename": latest["filename"],
            "download_url": f"/api/apk/download?version={urllib.parse.quote(latest['version_name'])}",
            "changelog": latest["changelog"],
            "requires_auth": True,
            "releases": releases,
        }

    size_bytes = apk_path.stat().st_size if (apk_path.exists() and apk_path.is_file()) else 0
    return {
        "available": exists,
        "version_name": "3.1.0",
        "version_code": 4,
        "size_bytes": size_bytes,
        "sha256": "",
        "released_at": "",
        "filename": "Govee-Sync-Studio-v3.1.0-b4.apk",
        "download_url": "/api/apk/download?version=3.1.0",
        "changelog": [],
        "requires_auth": True,
        "releases": [],
    }


@app.get("/api/apk/releases")
async def list_apk_releases(request: Request) -> Dict[str, Any]:
    auth_manager.require_authenticated_user(request)
    releases = _load_apk_releases_manifest()
    latest = releases[0] if releases else {}
    return {
        "latest_version_name": latest.get("version_name", "3.1.0"),
        "latest_version_code": latest.get("version_code", 4),
        "count": len(releases),
        "releases": releases,
    }


@app.api_route("/api/apk/download", methods=["GET", "HEAD"])
@app.api_route("/api/download/govee-sync.apk", methods=["GET", "HEAD"])
@app.api_route("/api/download/govee-multi-house-sync.apk", methods=["GET", "HEAD"])
async def download_android_apk(request: Request, version: str = "") -> Response:
    auth_manager.require_authenticated_user(request)
    releases = _load_apk_releases_manifest()
    clean_ver = version.strip().lstrip("v")

    if clean_ver:
        matched: Optional[Dict[str, Any]] = None
        for entry in releases:
            if (
                str(entry.get("version_name")) == clean_ver
                or str(entry.get("version_code")) == clean_ver
                or str(entry.get("filename")) == version.strip()
            ):
                matched = entry
                break
        if not matched:
            raise HTTPException(status_code=404, detail=f"APK version '{version}' is not available")
        rel_path = _resolve_release_apk_path(matched["filename"])
        if rel_path is None:
            # Fallback to latest APK pointer if requesting the latest version in a test environment
            fallback = _resolve_apk_path()
            if releases and matched["version_name"] == releases[0]["version_name"] and fallback.exists():
                rel_path = fallback
            else:
                raise HTTPException(status_code=404, detail=f"APK archive file '{matched['filename']}' not found")
        return FileResponse(
            path=str(rel_path),
            media_type="application/vnd.android.package-archive",
            filename=matched["filename"],
            headers={"Cache-Control": "private, no-store, no-cache, must-revalidate"},
        )

    latest = releases[0] if releases else None
    if latest:
        rel_path = _resolve_release_apk_path(latest["filename"])
        if rel_path is not None:
            return FileResponse(
                path=str(rel_path),
                media_type="application/vnd.android.package-archive",
                filename=latest["filename"],
                headers={"Cache-Control": "private, no-store, no-cache, must-revalidate"},
            )

    apk_path = _resolve_apk_path()
    if not apk_path.exists() or not apk_path.is_file():
        raise HTTPException(status_code=404, detail="Android APK is not available yet")
    dl_filename = (
        latest["filename"]
        if latest and latest.get("filename")
        else "Govee-Sync-Studio-v3.1.0-b4.apk"
    )
    return FileResponse(
        path=str(apk_path),
        media_type="application/vnd.android.package-archive",
        filename=dl_filename,
        headers={"Cache-Control": "private, no-store, no-cache, must-revalidate"},
    )


@app.websocket("/ws/neighbor-bridge/{house_id}")
async def websocket_neighbor_bridge(ws: WebSocket, house_id: str, token: str = "") -> None:
    """
    Internet Neighbor Bridge WebSocket endpoint (`/ws/neighbor-bridge/{house_id}`).
    Allows a lightweight Python relay script running on a neighbor's Wi-Fi to receive
    real-time 25 FPS UDP `:4003` (`colorwc` / `ptReal`) packets and report discovered LAN devices.
    """
    cfg = store.get()
    house = next((h for h in cfg.houses if h.id == house_id), None)
    if house and house.bridge_token and token != house.bridge_token:
        await ws.close(code=1008)
        return

    await ws.accept()
    remote_addr = ws.client.host if ws.client else "remote"
    driver.register_bridge(house_id, ws, remote_addr=remote_addr)
    await engine.broadcast_snapshot()

    try:
        await ws.send_json({"type": "welcome", "house_id": house_id, "command": "scan"})
        while True:
            msg = await ws.receive_json()
            if not isinstance(msg, dict):
                continue
            mtype = msg.get("type") or msg.get("cmd")
            if mtype in ("discovered_devices", "devices", "scan_result"):
                raw_devs = msg.get("devices", [])
                if house_id in driver.bridge_info:
                    driver.bridge_info[house_id]["devices"] = raw_devs
                    driver.bridge_info[house_id]["last_seen"] = asyncio.get_running_loop().time()

                # Register discovered devices and optionally bind IPs/MACs to house controllers
                cfg = store.get()
                target_house = next((h for h in cfg.houses if h.id == house_id), None)
                changed = False
                for idx, d in enumerate(raw_devs):
                    if not isinstance(d, dict):
                        continue
                    ip = str(d.get("ip", "")).strip()
                    mac = str(d.get("mac", ip)).strip().upper()
                    sku = str(d.get("sku", "H705A")).strip()
                    name = str(d.get("name", f"{sku} ({ip})")).strip()
                    if mac:
                        driver.discovered_devices[mac] = DiscoveredDevice(
                            ip=ip,
                            mac=mac,
                            sku=sku,
                            name=name,
                            source="lan",
                            last_seen=asyncio.get_running_loop().time(),
                            online=True,
                        )
                    if target_house and idx < len(target_house.controllers):
                        ctrl = target_house.controllers[idx]
                        if not ctrl.ip or ctrl.mac.startswith("AA:BB:CC:DD:EE:"):
                            ctrl.ip = ip
                            ctrl.mac = mac
                            if sku and sku != "Govee-LAN":
                                ctrl.sku = sku
                            changed = True
                if changed and target_house:
                    saved = store.save(cfg)
                    await engine.broadcast_snapshot(saved)
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.debug("Neighbor bridge %s closed: %s", house_id, exc)
    finally:
        driver.unregister_bridge(house_id, ws)
        await engine.broadcast_snapshot()


@app.websocket("/ws/live")
async def websocket_live(ws: WebSocket, token: str = "") -> None:
    host = (ws.headers.get("x-forwarded-host") or ws.headers.get("host") or "").lower()
    xff = ws.headers.get("x-forwarded-for", "").strip()
    public_domain = (urllib.parse.urlparse(os.environ.get("PUBLIC_BASE_URL", "")).hostname or "").strip().lower()
    external_ws = (
        (bool(public_domain) and public_domain in host)
        or "govee." in host
        or "govee-sync." in host
        or bool(xff and xff.split(",")[0].strip() not in ("127.0.0.1", "::1", "localhost"))
        or ws.headers.get("x-require-auth", "").strip() in ("1", "true", "yes")
    )
    ws_tok = (
        token
        or ws.cookies.get("govee_sync_session", "")
        or ws.headers.get("authorization", "")
        or ws.headers.get("x-auth-token", "")
    ).strip()
    if external_ws or ws_tok:
        if not ws_tok or auth_manager.verify_session_token(ws_tok) is None:
            await ws.close(code=1008)
            return

    await ws.accept()
    queue: asyncio.Queue[Dict[str, Any]] = asyncio.Queue(maxsize=2)

    async def push_frame(snapshot: Dict[str, Any]) -> None:
        if queue.full():
            try:
                queue.get_nowait()
            except asyncio.QueueEmpty:
                pass
        try:
            queue.put_nowait(snapshot)
        except asyncio.QueueFull:
            pass

    engine.register_ws_listener(push_frame)
    try:
        # Immediately send initial snapshot
        await ws.send_json(engine.build_live_snapshot())
        while True:
            snapshot = await queue.get()
            await ws.send_json(snapshot)
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        logger.debug("WebSocket client closed: %s", exc)
    finally:
        engine.unregister_ws_listener(push_frame)


# Serve built React frontend if available
FRONTEND_DIST = Path(__file__).resolve().parents[2] / "frontend" / "dist"
if FRONTEND_DIST.exists():
    assets_dir = FRONTEND_DIST / "assets"
    if assets_dir.exists():
        app.mount("/assets", StaticFiles(directory=str(assets_dir)), name="assets")

    @app.get("/{full_path:path}")
    async def serve_spa(full_path: str):
        if full_path.startswith("api/") or full_path.startswith("ws/"):
            raise HTTPException(status_code=404, detail="Not found")
        candidate = FRONTEND_DIST / full_path
        if full_path and candidate.exists() and candidate.is_file():
            return FileResponse(str(candidate))
        index_file = FRONTEND_DIST / "index.html"
        if index_file.exists():
            return FileResponse(str(index_file))
        return JSONResponse({"message": "Frontend build not found"}, status_code=404)
