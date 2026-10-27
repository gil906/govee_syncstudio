from __future__ import annotations

import asyncio
import base64
from pathlib import Path
from typing import Any, Dict, List

import pytest
from fastapi.testclient import TestClient

import backend.app.auth as auth_mod
import backend.app.main as main_mod
import backend.app.models as models_mod
from backend.app.animation_engine import MasterAnimationEngine, build_virtual_strip_map


@pytest.fixture(autouse=True)
def _isolate_live_store(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OWNER_EMAIL", "owner@example.com")
    monkeypatch.setenv("OWNER_GITHUB_USER", "owner_github")
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://govee-sync.example.com")
    monkeypatch.setenv("OAUTH_BRIDGE_BASE", "https://auth-bridge.example.com")
    monkeypatch.setattr(models_mod, "OWNER_EMAIL", "owner@example.com")
    monkeypatch.setattr(auth_mod, "OWNER_EMAIL", "owner@example.com")
    monkeypatch.setattr(main_mod, "OWNER_EMAIL", "owner@example.com")
    isolated = ConfigStore(data_dir=str(tmp_path))
    monkeypatch.setattr(main_mod, "store", isolated)
    monkeypatch.setattr(main_mod.engine, "store", isolated)
    monkeypatch.setattr(main_mod.auth_manager, "store", isolated)
from backend.app.config_store import ConfigStore
from backend.app.govee_protocol import (
    GoveeProtocolDriver,
    build_ptreal_segment_packet,
    compute_representative_controller_color,
    get_arp_neighbor_ips,
    get_local_subnet_targets,
)
from backend.app.models import EffectType, ProtocolMode, SpatialMappingMode


def test_house_normalized_uneven_segment_compensation(tmp_path: Path) -> None:
    """
    Verify that Neighbor 1 (Left House, order 1, 24 segments), My House (Middle - Me, order 2, 9 segments),
    and Neighbor 2 (Right House, order 3, 30 segments) each receive an exact 1/3 share of the [0, 1)
    normalized timeline in `house_normalized` mode, with My House in the middle position #2.
    """
    store = ConfigStore(data_dir=str(tmp_path))
    cfg = store.get()
    cfg.animation.mapping_mode = SpatialMappingMode.HOUSE_NORMALIZED

    assert [h.id for h in cfg.houses] == ["house-1", "house-2", "house-3"]
    assert cfg.houses[0].name == "Neighbor 1 (Left House)"
    assert cfg.houses[1].name == "My House (Middle - Me)"
    assert cfg.houses[2].name == "Neighbor 2 (Right House)"
    assert cfg.houses[0].connection_type == "govee_cloud"
    assert cfg.houses[1].connection_type == "local_lan"
    assert cfg.houses[2].connection_type == "govee_cloud"
    assert cfg.houses[1].controllers[0].id == "h2-ctrl-1"
    assert cfg.houses[1].controllers[0].name == "Govee Outdoor Lights 2 (H705E)"
    assert cfg.houses[1].controllers[0].ip == "192.168.1.83"
    assert cfg.houses[1].controllers[0].mac == "AA:BB:CC:DD:EE:FF:00:02"
    assert cfg.houses[1].controllers[0].sku == "H705E"
    assert cfg.houses[1].controllers[0].segment_count == 9

    slots = build_virtual_strip_map(cfg)
    assert len(slots) == 24 + 9 + 30

    h1_slots = [s for s in slots if s.house.id == "house-1"]
    h2_slots = [s for s in slots if s.house.id == "house-2"]
    h3_slots = [s for s in slots if s.house.id == "house-3"]

    assert len(h1_slots) == 24
    assert len(h2_slots) == 9
    assert len(h3_slots) == 30

    # House 1 (Neighbor 1) spans [0, 1/3), House 2 (My House - Middle) spans [1/3, 2/3), House 3 spans [2/3, 1.0)
    assert abs(sum(s.normalized_width for s in h1_slots) - (1.0 / 3.0)) < 1e-6
    assert abs(sum(s.normalized_width for s in h2_slots) - (1.0 / 3.0)) < 1e-6
    assert abs(sum(s.normalized_width for s in h3_slots) - (1.0 / 3.0)) < 1e-6

    assert all(0.0 <= s.normalized_pos < (1.0 / 3.0) for s in h1_slots)
    assert all((1.0 / 3.0) <= s.normalized_pos < (2.0 / 3.0) for s in h2_slots)
    assert all((2.0 / 3.0) <= s.normalized_pos < 1.0 for s in h3_slots)


def test_stop_and_start_sync_freezes_phase_and_blackouts(tmp_path: Path) -> None:
    """
    Verify that stopping sync immediately freezes `_anchor_phase` (so phase does NOT advance
    even as `now_mono` increases), renders `#000000` when `blackout_on_stop=True` (or frozen
    colors when `blackout_on_stop=False`), and resumes smoothly from the frozen phase on play.
    """
    store = ConfigStore(data_dir=str(tmp_path))
    driver = GoveeProtocolDriver()
    engine = MasterAnimationEngine(store=store, driver=driver)
    cfg = store.get()

    t0 = 2000.0
    engine._anchor_mono = t0
    engine._anchor_phase = 0.0
    engine._last_speed = 0.25
    engine._paused_at_mono = None

    # Advance 1.0s at 0.25 Hz -> phase = 0.25
    pts_running, _ = engine.render_frame_at(cfg, now_mono=t0 + 1.0)
    assert abs(engine.current_phase - 0.25) < 1e-6
    assert any(p.r > 0 or p.g > 0 or p.b > 0 for p in pts_running)

    # Stop sync at t0 + 1.0s with blackout_on_stop=True
    cfg.animation.running = False
    cfg.animation.blackout_on_stop = True
    store.save(cfg)
    engine.pause_clock(now_mono=t0 + 1.0, blackout=True)

    # Even 50 seconds later, phase must remain frozen at 0.25 and all segments must be #000000
    pts_stopped, _ = engine.render_frame_at(cfg, now_mono=t0 + 51.0)
    assert abs(engine.current_phase - 0.25) < 1e-6
    assert all(p.r == 0 and p.g == 0 and p.b == 0 and p.hex_color == "#000000" for p in pts_stopped)

    # Pause mode (blackout_on_stop=False) keeps frozen frame visible without advancing phase
    cfg.animation.blackout_on_stop = False
    store.save(cfg)
    pts_paused_1, _ = engine.render_frame_at(cfg, now_mono=t0 + 60.0)
    pts_paused_2, _ = engine.render_frame_at(cfg, now_mono=t0 + 120.0)
    assert [p.hex_color for p in pts_paused_1] == [p.hex_color for p in pts_running]
    assert [p.hex_color for p in pts_paused_1] == [p.hex_color for p in pts_paused_2]

    # Resume at t0 + 120.0s -> phase starts from 0.25 with zero jump
    cfg.animation.running = True
    store.save(cfg)
    engine.resume_clock(now_mono=t0 + 120.0)
    p_resumed = engine.get_unwrapped_phase(now_mono=t0 + 120.0, speed=0.25, running=True)
    assert abs((p_resumed % 1.0) - 0.25) < 1e-6
    p_after_1s = engine.get_unwrapped_phase(now_mono=t0 + 121.0, speed=0.25, running=True)
    assert abs((p_after_1s % 1.0) - 0.50) < 1e-6


def test_zero_drift_monotonic_clock_and_phase_continuity(tmp_path: Path) -> None:
    """
    Verify that the master clock has 0.0ms drift after 60s and 3600s and preserves C0 phase
    continuity when speed is changed dynamically.
    """
    store = ConfigStore(data_dir=str(tmp_path))
    driver = GoveeProtocolDriver()
    engine = MasterAnimationEngine(store=store, driver=driver)

    t0 = 1000.0
    engine._anchor_mono = t0
    engine._anchor_phase = 0.0
    engine._last_speed = 0.25
    engine._paused_at_mono = None

    # At 0.25 Hz (4.0s per cycle), t0 + 60.0s is exactly 15.0 cycles, t0 + 3600.0s is 900.0 cycles
    p_60 = engine.get_unwrapped_phase(now_mono=t0 + 60.0, speed=0.25, running=True)
    p_3600 = engine.get_unwrapped_phase(now_mono=t0 + 3600.0, speed=0.25, running=True)
    assert abs((p_60 % 1.0) - 0.0) < 1e-9
    assert abs((p_3600 % 1.0) - 0.0) < 1e-9

    # Change speed mid-flight at t = t0 + 1.3s and verify no phase jump
    phase_before = engine.get_unwrapped_phase(now_mono=t0 + 1.3, speed=0.25, running=True)
    phase_after = engine.get_unwrapped_phase(now_mono=t0 + 1.3, speed=0.60, running=True)
    assert abs(phase_before - phase_after) < 1e-9


def test_all_effects_render_cleanly(tmp_path: Path) -> None:
    store = ConfigStore(data_dir=str(tmp_path))
    driver = GoveeProtocolDriver()
    engine = MasterAnimationEngine(store=store, driver=driver)
    cfg = store.get()

    for effect in EffectType:
        cfg.animation.effect = effect
        points, ctrl_map = engine.render_frame_at(cfg, now_mono=1050.25)
        assert len(points) == 63
        assert len(ctrl_map) == 5
        for pt in points:
            assert 0 <= pt.r <= 255
            assert 0 <= pt.g <= 255
            assert 0 <= pt.b <= 255
            assert pt.hex_color.startswith("#") and len(pt.hex_color) == 7


def test_per_house_cloud_api_key_and_neighbor_bridge_routing(tmp_path: Path) -> None:
    """
    Verify that per-house `govee_api_key` and Neighbor Bridge WebSocket relay route
    frames to neighbors on separate Wi-Fi networks properly.
    """
    store = ConfigStore(data_dir=str(tmp_path))
    driver = GoveeProtocolDriver()
    cfg = store.get()

    house1 = cfg.houses[0]  # Neighbor 1 (Left House)
    ctrl1 = house1.controllers[0]

    # 1. Neighbor Bridge WebSocket Relay test
    relayed_payloads: List[Dict[str, Any]] = []

    class DummyBridgeWS:
        async def send_json(self, data: Dict[str, Any]) -> None:
            relayed_payloads.append(data)

    driver.register_bridge(house1.id, DummyBridgeWS(), remote_addr="203.0.113.10")
    assert driver.stats["connected_bridges"] == 1

    asyncio.run(
        driver.dispatch_controller_frame(
            house=house1,
            ctrl=ctrl1,
            segment_colors=[(0, 245, 212)] * 12,
            master_intensity=100,
            lan_enabled=True,
            cloud_fallback_enabled=True,
            api_key="",
            verbose_logging=True,
            force_send=True,
        )
    )
    assert len(relayed_payloads) == 1
    assert relayed_payloads[0]["type"] == "udp_relay"
    assert relayed_payloads[0]["house_id"] == "house-1"
    assert driver.stats["bridge_packets_sent"] == 1
    driver.unregister_bridge(house1.id)
    assert driver.stats["connected_bridges"] == 0

    # 2. Per-house Govee Cloud API key with segmentedColorRgb -> colorRgb fallback
    house1.connection_type = "govee_cloud"
    house1.govee_api_key = "neighbor-1-secret-api-key"
    sent_requests: List[Dict[str, Any]] = []

    class DummyResp:
        def __init__(self, status_code: int, body: Dict[str, Any]) -> None:
            self.status_code = status_code
            self._body = body
            self.text = str(body)

        def json(self) -> Dict[str, Any]:
            return self._body

    class DummyHttpClient:
        async def post(self, url: str, headers: Dict[str, str], json: Dict[str, Any]) -> DummyResp:
            sent_requests.append({"url": url, "headers": headers, "json": json})
            cap_instance = json["payload"]["capability"]["instance"]
            if cap_instance == "segmentedColorRgb":
                # Simulate a device that rejects segment capability so driver falls back to colorRgb
                return DummyResp(400, {"code": 400, "message": "Capability not supported"})
            return DummyResp(200, {"code": 200, "message": "success"})

        async def aclose(self) -> None:
            pass

    driver._http_client = DummyHttpClient()  # type: ignore[assignment]
    asyncio.run(
        driver.dispatch_controller_frame(
            house=house1,
            ctrl=ctrl1,
            segment_colors=[(255, 0, 128)] * 12,
            master_intensity=100,
            lan_enabled=True,
            cloud_fallback_enabled=True,
            api_key="global-fallback-key",
            verbose_logging=True,
            force_send=True,
        )
    )
    # Should have used house1.govee_api_key, sent powerSwitch=1, tried segmentedColorRgb, then succeeded with colorRgb fallback
    assert len(sent_requests) == 3
    assert sent_requests[0]["headers"]["Govee-API-Key"] == "neighbor-1-secret-api-key"
    assert sent_requests[0]["json"]["payload"]["capability"]["instance"] == "powerSwitch"
    assert sent_requests[1]["json"]["payload"]["capability"]["instance"] == "segmentedColorRgb"
    assert sent_requests[2]["json"]["payload"]["capability"]["instance"] == "colorRgb"


def test_api_reorder_houses_and_bridge_endpoints() -> None:
    from backend.app.main import app, store

    with TestClient(app) as client:
        # Reset to default 3 houses (house-1, house-2, house-3)
        r_reset = client.post("/api/config/reset")
        assert r_reset.status_code == 200
        houses = r_reset.json()["houses"]
        assert [h["id"] for h in houses] == ["house-1", "house-2", "house-3"]
        assert houses[1]["name"] == "My House (Middle - Me)"

        # Reorder houses via POST /api/houses/reorder
        r_reorder = client.post(
            "/api/houses/reorder",
            json={"house_ids": ["house-3", "house-2", "house-1"]},
        )
        assert r_reorder.status_code == 200
        reordered = r_reorder.json()["houses"]
        assert [h["id"] for h in reordered] == ["house-3", "house-2", "house-1"]
        assert [h["order"] for h in reordered] == [1, 2, 3]

        # Restore default order
        client.post("/api/houses/reorder", json={"house_ids": ["house-1", "house-2", "house-3"]})

        # Test 1-click controller test endpoint on My House (192.168.1.83 / H705E)
        r_test_ctrl = client.post("/api/controllers/h2-ctrl-1/test", json={"color": "#00f5d4"})
        assert r_test_ctrl.status_code == 200
        test_body = r_test_ctrl.json()
        assert test_body["controller_id"] == "h2-ctrl-1"
        assert test_body["ip"] == "192.168.1.83"
        assert test_body["sku"] == "H705E"
        assert test_body["color"] == "#00f5d4"

        # Test Stop / Pause / Play endpoints
        r_stop = client.post("/api/animation/stop")
        assert r_stop.status_code == 200
        assert r_stop.json()["running"] is False
        state_stopped = client.get("/api/state").json()
        assert state_stopped["running"] is False
        assert all(s["hex_color"] == "#000000" for s in state_stopped["segments"])

        r_play = client.post("/api/animation/play")
        assert r_play.status_code == 200
        assert r_play.json()["running"] is True

        # Test Neighbor Bridge script download and WebSocket connection
        r_script = client.get("/api/neighbor-bridge.py?house_id=house-1")
        assert r_script.status_code == 200
        assert "HOUSE_ID = \"house-1\"" in r_script.text

        with client.websocket_connect("/ws/neighbor-bridge/house-1") as ws:
            welcome = ws.receive_json()
            assert welcome["type"] == "welcome"
            assert welcome["house_id"] == "house-1"
            ws.send_json(
                {
                    "type": "discovered_devices",
                    "house_id": "house-1",
                    "devices": [{"ip": "192.168.1.55", "mac": "11:22:33:44:55:66:77:88", "sku": "H705A"}],
                }
            )
            bridges = client.get("/api/bridges").json()
            assert "house-1" in bridges["connected_house_ids"]

        # Test Pause endpoint (freezes frame in place with blackout_on_stop=False)
        r_pause = client.post("/api/animation/pause")
        assert r_pause.status_code == 200
        assert r_pause.json()["running"] is False
        assert r_pause.json()["blackout_on_stop"] is False

        # Clean up back to default example
        store.reset_to_example()


def test_lan_discovery_helpers_and_ptreal() -> None:
    arp_ips = get_arp_neighbor_ips()
    assert isinstance(arp_ips, list)
    subnet_ips, bcast_ips = get_local_subnet_targets(max_hosts=256)
    assert isinstance(subnet_ips, list)
    assert isinstance(bcast_ips, list)

    b64 = build_ptreal_segment_packet(255, 128, 64, [0, 1, 2, 8])
    raw = base64.b64decode(b64)
    assert len(raw) == 20
    assert raw[0] == 0x33 and raw[1] == 0x05 and raw[2] == 0x15
    xor_check = 0
    for b in raw[:19]:
        xor_check ^= b
    assert raw[19] == xor_check

    # Verify bright chase pulse on 2 segments of a 12-segment strip isn't washed out
    segs = [(0, 245, 212), (0, 245, 212)] + [(0, 0, 0)] * 10
    rep = compute_representative_controller_color(segs)
    assert rep[1] > 150


def test_new_holiday_and_center_out_effects_and_20_plus_presets(tmp_path: Path) -> None:
    """
    Verify all 6 new effects (`halloween_spooky`, `christmas_magic`, `diwali_festival`,
    `center_out_shockwave`, `lightning_storm`, `cyber_snake`), symmetrical center-out wave
    from My House (x=0.50), and 20+ categorized presets.
    """
    from backend.app.animation_engine import evaluate_effect_at_point

    store = ConfigStore(data_dir=str(tmp_path))
    driver = GoveeProtocolDriver()
    engine = MasterAnimationEngine(store=store, driver=driver)
    cfg = store.get()

    required_effects = {
        "multi_house_chase",
        "rainbow_wave",
        "comet_meteor",
        "breathing_pulse",
        "color_wipe",
        "theater_chase",
        "fire_sparkle",
        "sparkle_twinkle",
        "halloween_spooky",
        "christmas_magic",
        "diwali_festival",
        "center_out_shockwave",
        "lightning_storm",
        "cyber_snake",
        "govee_rainbow1",
        "govee_rainbow2",
    }
    assert {e.value for e in EffectType} == required_effects

    # Verify center_out_shockwave is 100% symmetrical around x = 0.50 (My House #2 in the middle)
    cfg.animation.effect = EffectType.CENTER_OUT_SHOCKWAVE
    for phase in (0.05, 0.25, 0.55, 0.85):
        for offset in (0.0, 0.08, 0.18, 0.35, 0.48):
            left_rgb = evaluate_effect_at_point(
                0.50 - offset,
                phase,
                12.5,
                cfg.animation,
                (0, 245, 212),
                (139, 92, 246),
                (255, 0, 127),
                (5, 7, 20),
            )
            right_rgb = evaluate_effect_at_point(
                0.50 + offset,
                phase,
                12.5,
                cfg.animation,
                (0, 245, 212),
                (139, 92, 246),
                (255, 0, 127),
                (5, 7, 20),
            )
            assert left_rgb == right_rgb

    # Verify 20+ presets with required categories, badges, descriptions, and animation parameters
    assert len(engine.PRESETS) >= 20
    required_preset_ids = {
        "halloween_haunted_chase",
        "halloween_witch_cauldron",
        "halloween_blood_meteor",
        "halloween_pumpkin_marquee",
        "xmas_sleigh_ride",
        "xmas_candy_cane",
        "xmas_frozen_aurora",
        "xmas_nutcracker_marquee",
        "diwali_golden_diya",
        "diwali_rangoli_wave",
        "diwali_firecracker_sparkle",
        "diwali_aarti_flame",
        "center_supernova",
        "center_golden_ripple",
        "center_serpent_clash",
        "cyber_chase",
        "dual_comet_pingpong",
        "seamless_rainbow",
        "seahawks_gameday",
        "july4_fireworks",
    }
    actual_ids = {p["id"] for p in engine.PRESETS}
    assert required_preset_ids.issubset(actual_ids)

    valid_categories = {
        "Halloween",
        "Christmas",
        "Diwali",
        "Center-Out (My House)",
        "Cyber & Party",
        "Celebrations",
    }
    required_anim_keys = {
        "effect",
        "speed",
        "direction",
        "mapping_mode",
        "primary_color",
        "secondary_color",
        "accent_color",
        "background_color",
        "background_dim",
        "tail_length",
        "pulse_count",
        "supersample",
    }
    for preset in engine.PRESETS:
        assert preset.get("id")
        assert preset.get("name")
        assert preset.get("category") in valid_categories
        assert preset.get("badge")
        assert preset.get("description")
        assert required_anim_keys.issubset(set(preset["animation"].keys()))


def test_playlist_schedule_and_celebration_burst() -> None:
    import datetime as dt
    from zoneinfo import ZoneInfo
    from backend.app.main import app, engine, store

    with TestClient(app) as client:
        store.reset_to_example()

        # 1. Playlist Jukebox Mode
        r_pl = client.patch(
            "/api/playlist",
            json={
                "enabled": True,
                "preset_ids": ["xmas_sleigh_ride", "diwali_golden_diya", "halloween_haunted_chase"],
                "interval_sec": 10,
            },
        )
        assert r_pl.status_code == 200
        assert r_pl.json()["enabled"] is True
        assert r_pl.json()["interval_sec"] == 10

        import time as _time
        now_m = _time.monotonic_ns() / 1e9
        engine.active_preset_id = "xmas_sleigh_ride"
        engine._last_playlist_switch_mono = now_m - 12.0
        next_pid = engine.advance_playlist_if_due(now_mono=now_m)
        assert next_pid == "diwali_golden_diya"
        assert store.get().animation.effect == EffectType.DIWALI_FESTIVAL

        # 2. Daily Schedule / Sunset Timer (America/Los_Angeles)
        r_sch = client.patch(
            "/api/schedule",
            json={
                "enabled": True,
                "start_time": "17:30",
                "stop_time": "23:00",
                "preset_id": "halloween_haunted_chase",
                "timezone": "America/Los_Angeles",
            },
        )
        assert r_sch.status_code == 200
        assert r_sch.json()["enabled"] is True

        la_tz = ZoneInfo("America/Los_Angeles")
        res_start = asyncio.run(engine.check_schedule(dt.datetime(2026, 10, 31, 17, 30, 0, tzinfo=la_tz)))
        assert res_start == "started"
        assert store.get().animation.running is True
        assert store.get().animation.effect == EffectType.HALLOWEEN_SPOOKY

        res_stop = asyncio.run(engine.check_schedule(dt.datetime(2026, 10, 31, 23, 0, 0, tzinfo=la_tz)))
        assert res_stop == "stopped"
        assert store.get().animation.running is False

        # 3. One-Tap Street Celebration Burst + auto restore
        client.post("/api/presets/cyber_chase")
        before_burst = store.get().animation
        assert before_burst.effect == EffectType.MULTI_HOUSE_CHASE

        r_burst = client.post("/api/animation/burst", json={"type": "touchdown", "duration_sec": 5})
        assert r_burst.status_code == 200
        b_data = r_burst.json()
        assert b_data["status"] == "burst_started"
        assert store.get().animation.effect == EffectType.CENTER_OUT_SHOCKWAVE

        # Restore from burst and confirm previous AnimationConfig is restored
        asyncio.run(engine.restore_from_burst())
        after_burst = store.get().animation
        assert after_burst.effect == EffectType.MULTI_HOUSE_CHASE
        assert after_burst.primary_color == before_burst.primary_color

        store.reset_to_example()


def test_google_and_github_oauth_authorized_emails_and_apk_endpoints(tmp_path: Path, monkeypatch: Any) -> None:
    from backend.app.main import app, auth_manager, store

    monkeypatch.setenv("GOOGLE_CLIENT_ID", "test-google-client-id.apps.googleusercontent.com")
    monkeypatch.setenv("GOOGLE_CLIENT_SECRET", "test-google-secret")
    monkeypatch.setenv("GITHUB_CLIENT_ID", "test-github-client-id")
    monkeypatch.setenv("GITHUB_CLIENT_SECRET", "test-github-secret")

    class MockOAuthHttpClient:
        def __init__(self, mode: str = "owner_google") -> None:
            self.mode = mode

        async def post(self, url: str, data: Any = None, headers: Any = None, json: Any = None) -> Any:
            class Resp:
                def __init__(self, status_code: int, payload: Dict[str, Any]) -> None:
                    self.status_code = status_code
                    self._payload = payload

                def json(self) -> Dict[str, Any]:
                    return self._payload

            if "oauth2.googleapis.com/token" in url:
                return Resp(200, {"access_token": f"google-access-{self.mode}"})
            if "github.com/login/oauth/access_token" in url:
                return Resp(200, {"access_token": f"gh-access-{self.mode}"})
            return Resp(400, {})

        async def get(self, url: str, headers: Any = None, params: Any = None) -> Any:
            class Resp:
                def __init__(self, status_code: int, payload: Any) -> None:
                    self.status_code = status_code
                    self._payload = payload

                def json(self) -> Any:
                    return self._payload

            if "googleapis.com/oauth2/v3/userinfo" in url:
                if self.mode == "intruder":
                    return Resp(200, {"email": "intruder@example.com", "name": "Intruder"})
                return Resp(200, {"email": "owner@example.com", "name": "Owner"})
            if "oauth2.googleapis.com/tokeninfo" in url:
                tok = (params or {}).get("id_token", "")
                if tok == "valid-owner-id-token":
                    return Resp(
                        200,
                        {
                            "email": "owner@example.com",
                            "name": "Owner",
                            "aud": "test-google-client-id.apps.googleusercontent.com",
                        },
                    )
                if tok == "unauthorized-id-token":
                    return Resp(
                        200,
                        {
                            "email": "stranger@example.com",
                            "name": "Stranger",
                            "aud": "test-google-client-id.apps.googleusercontent.com",
                        },
                    )
                return Resp(401, {"error": "invalid_token"})
            if url.endswith("/user"):
                if self.mode == "github_private_owner":
                    return Resp(200, {"login": "owner_github", "name": "Owner", "email": None})
                if self.mode == "github_neighbor_emails_api":
                    return Resp(200, {"login": "neighbor1", "name": "Neighbor One", "email": None})
                if self.mode == "github_unauthorized":
                    return Resp(200, {"login": "hacker", "name": "Hacker", "email": "hacker@evil.org"})
            if url.endswith("/user/emails"):
                if self.mode == "github_neighbor_emails_api":
                    return Resp(
                        200,
                        [{"email": "neighbor@example.com", "primary": True, "verified": True}],
                    )
                return Resp(200, [])
            if "/api/auth/oauth/mobile-poll/" in url:
                if self.mode == "bridge_owner":
                    return Resp(
                        200,
                        {
                            "status": "completed",
                            "token": "bridge-tok",
                            "refresh_token": "bridge-ref",
                            "user": {"email": "owner@example.com", "name": "Owner"},
                        },
                    )
                if self.mode == "bridge_intruder":
                    return Resp(
                        200,
                        {
                            "status": "completed",
                            "token": "bridge-tok",
                            "refresh_token": "bridge-ref",
                            "user": {"email": "intruder@example.com", "name": "Intruder"},
                        },
                    )
                return Resp(200, {"status": "pending"})
            return Resp(404, {})

        async def aclose(self) -> None:
            pass

    with TestClient(app) as client:
        store.reset_to_example()

        # 1. Verify default authorized_emails has owner@example.com and cannot be removed
        r_users = client.get("/api/auth/users")
        assert r_users.status_code == 200
        assert r_users.json()["owner"] == "owner@example.com"
        assert "owner@example.com" in r_users.json()["authorized_emails"]

        r_del_owner = client.delete("/api/auth/users/owner@example.com")
        assert r_del_owner.status_code == 400

        # 2. Add neighbor@example.com to authorized_emails
        r_add = client.post("/api/auth/users", json={"email": "Neighbor@Example.com"})
        assert r_add.status_code == 200
        assert "neighbor@example.com" in r_add.json()["authorized_emails"]

        # 3. External internet requests (Host: govee-sync.example.com) block control & APK endpoints without token
        ext_headers = {"Host": "govee-sync.example.com", "X-Forwarded-For": "198.51.100.42"}
        assert client.get("/api/health", headers=ext_headers).status_code == 200
        assert client.get("/api/auth/status", headers=ext_headers).status_code == 200
        assert client.get("/api/neighbor-bridge.py", headers=ext_headers).status_code == 200
        assert client.get("/api/apk/info", headers=ext_headers).status_code == 401
        assert client.get("/api/download/govee-sync.apk", headers=ext_headers).status_code == 401
        assert client.get("/api/config", headers=ext_headers).status_code == 401
        assert client.get("/api/auth/users", headers=ext_headers).status_code == 401

        # 4. Google OAuth mobile login + callback handoff for authorized owner
        auth_manager._http_client = MockOAuthHttpClient("owner_google")  # type: ignore[assignment]
        r_g_login = client.get("/api/auth/google/login?mobile=1", follow_redirects=False)
        assert r_g_login.status_code == 302
        loc = r_g_login.headers["location"]
        assert "accounts.google.com" in loc
        state_param = loc.split("state=")[1].split("&")[0]

        r_g_cb = client.get(
            f"/api/auth/google/callback?code=test-code&state={state_param}",
            follow_redirects=False,
        )
        assert r_g_cb.status_code == 302
        assert r_g_cb.headers["location"].startswith("goveesync://auth?token=")
        assert "Return to Govee Sync Android App" in r_g_cb.text
        assert "govee_sync_session" in r_g_cb.cookies

        # 5. Google OAuth callback rejects unauthorized email with 403
        auth_manager._http_client = MockOAuthHttpClient("intruder")  # type: ignore[assignment]
        r_g_denied = client.get(
            f"/api/auth/google/callback?code=bad-code&state={state_param}",
            follow_redirects=False,
        )
        assert r_g_denied.status_code == 403
        assert (
            "Access denied for intruder@example.com. Only authorized emails (configured by owner@example.com) can access Govee Multi-House Light Sync."
            in r_g_denied.text
        )

        # 6. Google ID token endpoint (authorized vs unauthorized)
        r_id_ok = client.post("/api/auth/google/id-token", json={"id_token": "valid-owner-id-token"})
        assert r_id_ok.status_code == 200
        bearer_token = r_id_ok.json()["token"]
        assert r_id_ok.json()["user"]["email"] == "owner@example.com"

        # Use Bearer token from external internet to access protected endpoints
        r_ext_cfg = client.get(
            "/api/config",
            headers={**ext_headers, "Authorization": f"Bearer {bearer_token}"},
        )
        assert r_ext_cfg.status_code == 200

        r_id_denied = client.post("/api/auth/google/id-token", json={"id_token": "unauthorized-id-token"})
        assert r_id_denied.status_code == 403
        assert "Access denied for stranger@example.com" in r_id_denied.json()["detail"]

        # 7. GitHub OAuth callback with private email (/user/emails) and OWNER_GITHUB_USER mapping
        auth_manager._http_client = MockOAuthHttpClient("github_neighbor_emails_api")  # type: ignore[assignment]
        r_gh_cb = client.get("/api/auth/github/callback?code=gh-code&mobile=1", follow_redirects=False)
        assert r_gh_cb.status_code == 302
        assert "email=neighbor%40example.com" in r_gh_cb.headers["location"]

        auth_manager._http_client = MockOAuthHttpClient("github_private_owner")  # type: ignore[assignment]
        r_gh_gil = client.get("/api/auth/github/callback?code=gh-code&mobile=1", follow_redirects=False)
        assert r_gh_gil.status_code == 302
        assert "email=owner%40example.com" in r_gh_gil.headers["location"]

        # 8. Remove neighbor@example.com and clean up
        r_del = client.delete("/api/auth/users/neighbor@example.com")
        assert r_del.status_code == 200
        assert "neighbor@example.com" not in r_del.json()["authorized_emails"]

        # 8b. OAuth Bridge Handoff (OAUTH_BRIDGE_BASE -> /api/auth/bridge-callback)
        r_b_login = client.get("/api/auth/google/login?bridge=1", follow_redirects=False)
        assert r_b_login.status_code == 302
        b_loc = r_b_login.headers["location"]
        assert "/api/auth/google?mobile_session=govee_web_" in b_loc
        web_handoff = b_loc.split("mobile_session=")[1]

        auth_manager._http_client = MockOAuthHttpClient("bridge_owner")  # type: ignore[assignment]
        r_b_cb = client.get(f"/api/auth/bridge-callback?handoff={web_handoff}", follow_redirects=False)
        assert r_b_cb.status_code == 302
        assert "auth_token=" in r_b_cb.headers["location"]
        assert "govee_sync_session" in r_b_cb.cookies

        # Mobile bridge poll works and caches token
        r_b_poll = client.get(f"/api/auth/bridge-poll/{web_handoff}")
        assert r_b_poll.status_code == 200
        assert r_b_poll.json()["status"] == "completed"
        assert r_b_poll.json()["user"]["email"] == "owner@example.com"

        # Unauthorized bridge login returns 403
        r_b_mob = client.get("/api/auth/github/login?bridge=1&mobile=1", follow_redirects=False)
        mob_handoff = r_b_mob.headers["location"].split("mobile_session=")[1]
        assert mob_handoff.startswith("govee_mob_")
        auth_manager._http_client = MockOAuthHttpClient("bridge_intruder")  # type: ignore[assignment]
        r_b_denied = client.get(f"/api/auth/bridge-callback?handoff={mob_handoff}", follow_redirects=False)
        assert r_b_denied.status_code == 403

        # 9. APK download endpoint test (requires authentication on external or x-require-auth requests)
        apk_file = store.data_dir / "govee-multi-house-sync.apk"
        created_dummy_apk = False
        if not apk_file.exists():
            apk_file.write_bytes(b"PK\x03\x04dummy-apk-payload")
            created_dummy_apk = True
        try:
            client.cookies.clear()
            r_apk_unauth = client.get("/api/download/govee-sync.apk", headers={"x-require-auth": "1"})
            assert r_apk_unauth.status_code == 401
            assert (
                r_apk_unauth.json()["detail"]
                == "Authentication required to download the Android APK. Please sign in first."
            )

            r_apk_info_unauth = client.get("/api/apk/info", headers={"x-require-auth": "1"})
            assert r_apk_info_unauth.status_code == 401

            r_apk_info = client.get(
                "/api/apk/info",
                headers={"x-require-auth": "1", "Authorization": f"Bearer {bearer_token}"},
            )
            assert r_apk_info.status_code == 200
            assert r_apk_info.json()["available"] is True
            assert r_apk_info.json()["download_url"].startswith(("/api/apk/download", "/api/download/govee-sync.apk"))

            r_apk_dl = client.get(
                "/api/download/govee-sync.apk",
                headers={**ext_headers, "Authorization": f"Bearer {bearer_token}"},
            )
            assert r_apk_dl.status_code == 200
            assert "application/vnd.android.package-archive" in r_apk_dl.headers["content-type"]

            r_apk_dl_query = client.get(
                f"/api/download/govee-sync.apk?token={bearer_token}",
                headers={"x-require-auth": "1"},
            )
            assert r_apk_dl_query.status_code == 200
        finally:
            if created_dummy_apk and apk_file.exists():
                apk_file.unlink()
            auth_manager._http_client = None
            store.reset_to_example()


def test_all_71_presets_produce_lively_non_static_animations(tmp_path: Path) -> None:
    """
    Loop through all 71 presets in `MasterAnimationEngine.PRESETS`, render each preset
    at `t = 1000.0` and `t = 1000.7`, and assert that every single preset (71/71) produces
    moving, non-static RGB values across the segments.
    """
    from backend.app.models import AnimationConfig

    store = ConfigStore(data_dir=str(tmp_path))
    driver = GoveeProtocolDriver()
    engine = MasterAnimationEngine(store=store, driver=driver)
    cfg = store.get()

    assert len(engine.PRESETS) >= 190

    for preset in engine.PRESETS:
        pid = preset["id"]
        merged = cfg.animation.model_dump()
        merged.update(preset["animation"])
        merged["running"] = True
        cfg.animation = AnimationConfig.model_validate(merged)

        engine._anchor_mono = 1000.0
        engine._anchor_phase = 0.0
        engine._last_speed = cfg.animation.speed
        engine._paused_at_mono = None

        pts_t0, _ = engine.render_frame_at(cfg, now_mono=1000.0)
        pts_t1, _ = engine.render_frame_at(cfg, now_mono=1000.7)

        rgb_t0 = [(p.r, p.g, p.b) for p in pts_t0]
        rgb_t1 = [(p.r, p.g, p.b) for p in pts_t1]

        # 1. Must change over time between t=1000.0 and t=1000.7
        assert rgb_t0 != rgb_t1, f"Preset '{pid}' did not animate between t=1000.0 and t=1000.7"
        # 2. Must have spatial variation across the strip (not all segments identical color)
        assert len(set(rgb_t0)) > 1 or len(set(rgb_t1)) > 1, f"Preset '{pid}' has no spatial variation"


def test_dynamic_1_2_3_4_houses_and_toggle_add_delete_endpoints() -> None:
    from backend.app.main import app, store

    with TestClient(app) as client:
        store.reset_to_example()

        # Default 3 houses: 24 + 9 + 30 = 63 segments
        cfg3 = store.get()
        slots3 = build_virtual_strip_map(cfg3)
        assert len(slots3) == 63

        # Disable house-1 -> 2 active houses (house-2 with 9 segs, house-3 with 30 segs = 39 segs)
        r_tog1 = client.patch("/api/houses/house-1/toggle", json={"enabled": False})
        assert r_tog1.status_code == 200
        assert r_tog1.json()["enabled"] is False
        assert r_tog1.json()["enabled_houses"] == 2
        assert r_tog1.json()["active_segments"] == 39

        slots2 = build_virtual_strip_map(store.get())
        assert len(slots2) == 39
        h2_slots = [s for s in slots2 if s.house.id == "house-2"]
        h3_slots = [s for s in slots2 if s.house.id == "house-3"]
        assert abs(sum(s.normalized_width for s in h2_slots) - 0.5) < 1e-6
        assert abs(sum(s.normalized_width for s in h3_slots) - 0.5) < 1e-6

        # Disable house-3 -> 1 active house (My House #2 alone with 9 segments spanning [0, 1.0))
        r_tog3 = client.patch("/api/houses/house-3/toggle", json={"enabled": False})
        assert r_tog3.status_code == 200
        assert r_tog3.json()["enabled_houses"] == 1
        assert r_tog3.json()["active_segments"] == 9
        slots1 = build_virtual_strip_map(store.get())
        assert len(slots1) == 9
        assert abs(sum(s.normalized_width for s in slots1) - 1.0) < 1e-6

        # Re-enable house-1 and house-3
        client.patch("/api/houses/house-1/toggle", json={"enabled": True})
        client.patch("/api/houses/house-3/toggle", json={"enabled": True})

        # Add 4th neighbor house via POST /api/houses/add
        r_add = client.post(
            "/api/houses/add",
            json={
                "name": "Neighbor 3 (Far Right House)",
                "connection_type": "govee_cloud",
                "segment_count": 15,
                "controller_count": 1,
            },
        )
        assert r_add.status_code == 200
        added_house = r_add.json()["house"]
        assert added_house["id"] == "house-4"
        assert added_house["order"] == 4
        assert len(r_add.json()["houses"]) == 4

        # 4 active houses -> each gets 0.25 share of [0, 1)
        slots4 = build_virtual_strip_map(store.get())
        assert len(slots4) == 63 + 15
        h4_slots = [s for s in slots4 if s.house.id == "house-4"]
        assert len(h4_slots) == 15
        assert abs(sum(s.normalized_width for s in h4_slots) - 0.25) < 1e-6

        # Delete 4th house via DELETE /api/houses/house-4
        r_del = client.delete("/api/houses/house-4")
        assert r_del.status_code == 200
        assert len(r_del.json()["houses"]) == 3
        assert [h["order"] for h in r_del.json()["houses"]] == [1, 2, 3]

        store.reset_to_example()


def test_compute_schedule_status_timezone_and_dst_detection() -> None:
    import datetime as dt
    from zoneinfo import ZoneInfo
    from backend.app.animation_engine import compute_schedule_status
    from backend.app.models import ScheduleConfig

    sched = ScheduleConfig(
        enabled=True,
        start_time="17:30",
        stop_time="23:00",
        preset_id="cyber_chase",
        timezone="America/Los_Angeles",
        days_of_week=["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
        turn_off_lights_on_stop=True,
    )
    la_tz = ZoneInfo("America/Los_Angeles")

    # Summer / October PDT (DST active, UTC-07:00) inside [17:30, 23:00)
    dt_pdt = dt.datetime(2026, 7, 15, 19, 45, 0, tzinfo=la_tz)
    st_pdt = compute_schedule_status(sched, last_triggered_action="started", now_dt=dt_pdt)
    assert st_pdt["dst_active"] is True
    assert st_pdt["tz_abbrev"] == "PDT"
    assert st_pdt["utc_offset"] == "-07:00"
    assert st_pdt["is_within_active_window"] is True
    assert st_pdt["autonomous_container_daemon"] is True

    # Winter PST (DST inactive, UTC-08:00) outside [17:30, 23:00)
    dt_pst = dt.datetime(2026, 12, 15, 14, 0, 0, tzinfo=la_tz)
    st_pst = compute_schedule_status(sched, now_dt=dt_pst)
    assert st_pst["dst_active"] is False
    assert st_pst["tz_abbrev"] == "PST"
    assert st_pst["utc_offset"] == "-08:00"
    assert st_pst["is_within_active_window"] is False

    # Overnight window (17:30 -> 01:00) at 00:30 AM
    sched_overnight = ScheduleConfig(
        enabled=True,
        start_time="17:30",
        stop_time="01:00",
        preset_id="cyber_chase",
        timezone="America/Los_Angeles",
    )
    dt_after_midnight = dt.datetime(2026, 7, 16, 0, 30, 0, tzinfo=la_tz)
    st_overnight = compute_schedule_status(sched_overnight, now_dt=dt_after_midnight)
    assert st_overnight["is_within_active_window"] is True


def test_apk_versioning_releases_and_versioned_download() -> None:
    import json
    from backend.app.main import app, store

    with TestClient(app) as client:
        releases_dir = store.data_dir / "releases"
        releases_dir.mkdir(parents=True, exist_ok=True)
        v30_apk = releases_dir / "Govee-Sync-Studio-v3.0.0-b3.apk"
        v31_apk = releases_dir / "Govee-Sync-Studio-v3.1.0-b4.apk"
        v30_apk.write_bytes(b"PK\x03\x04apk-v3.0.0-payload")
        v31_apk.write_bytes(b"PK\x03\x04apk-v3.1.0-payload-newer")
        (store.data_dir / "govee-multi-house-sync.apk").write_bytes(b"PK\x03\x04apk-v3.1.0-payload-newer")

        manifest = {
            "releases": [
                {
                    "version_name": "3.1.0",
                    "version_code": 4,
                    "filename": "Govee-Sync-Studio-v3.1.0-b4.apk",
                    "size_bytes": len(b"PK\x03\x04apk-v3.1.0-payload-newer"),
                    "sha256": "abcd1234",
                    "released_at": "2026-10-26T18:30:00Z",
                    "changelog": ["Added APK versioning & release archive system"],
                },
                {
                    "version_name": "3.0.0",
                    "version_code": 3,
                    "filename": "Govee-Sync-Studio-v3.0.0-b3.apk",
                    "size_bytes": len(b"PK\x03\x04apk-v3.0.0-payload"),
                    "sha256": "dc4f0c90",
                    "released_at": "2026-10-26T09:24:26Z",
                    "changelog": ["Custom 3-House Neon Roofline launcher icon"],
                },
            ]
        }
        (store.data_dir / "apk_releases.json").write_text(json.dumps(manifest), encoding="utf-8")

        r_info = client.get("/api/apk/info")
        assert r_info.status_code == 200
        info_data = r_info.json()
        assert info_data["available"] is True
        assert info_data["version_name"] == "3.1.0"
        assert info_data["version_code"] == 4
        assert info_data["filename"] == "Govee-Sync-Studio-v3.1.0-b4.apk"
        assert info_data["download_url"] == "/api/apk/download?version=3.1.0"
        assert len(info_data["releases"]) == 2

        r_rel = client.get("/api/apk/releases")
        assert r_rel.status_code == 200
        rel_data = r_rel.json()
        assert rel_data["latest_version_name"] == "3.1.0"
        assert rel_data["latest_version_code"] == 4
        assert rel_data["count"] == 2

        # Download specific archived version v3.0.0
        r_dl_30 = client.get("/api/apk/download?version=3.0.0")
        assert r_dl_30.status_code == 200
        assert r_dl_30.content == b"PK\x03\x04apk-v3.0.0-payload"
        assert "Govee-Sync-Studio-v3.0.0-b3.apk" in r_dl_30.headers.get("content-disposition", "")

        # Download latest version v3.1.0
        r_dl_31 = client.get("/api/apk/download?version=3.1.0")
        assert r_dl_31.status_code == 200
        assert r_dl_31.content == b"PK\x03\x04apk-v3.1.0-payload-newer"
        assert "Govee-Sync-Studio-v3.1.0-b4.apk" in r_dl_31.headers.get("content-disposition", "")

        # Unknown version returns 404
        r_dl_404 = client.get("/api/apk/download?version=9.9.9")
        assert r_dl_404.status_code == 404


def test_representative_controller_color_animates_across_all_71_presets(tmp_path: Path) -> None:
    """
    Verify that compute_representative_controller_color (used for LAN colorwc and Cloud colorRgb)
    never collapses multi-color scenes into a static muddy grey average, and instead changes RGB
    vividly over time across a controller's segments for all 71 presets.
    """
    from backend.app.models import AnimationConfig

    store = ConfigStore(data_dir=str(tmp_path))
    driver = GoveeProtocolDriver()
    engine = MasterAnimationEngine(store=store, driver=driver)
    cfg = store.get()

    for preset in engine.PRESETS:
        pid = preset["id"]
        merged = cfg.animation.model_dump()
        merged.update(preset["animation"])
        merged["running"] = True
        cfg.animation = AnimationConfig.model_validate(merged)

        engine._anchor_mono = 1000.0
        engine._anchor_phase = 0.0
        engine._last_speed = cfg.animation.speed
        engine._paused_at_mono = None

        rep_samples = set()
        for dt_offset in (0.0, 0.45, 0.90, 1.45, 2.10, 2.85, 3.60):
            pts, _ = engine.render_frame_at(cfg, now_mono=1000.0 + dt_offset)
            h2_segs = [(p.r, p.g, p.b) for p in pts if p.house_id == "house-2"]
            rep_samples.add(compute_representative_controller_color(h2_segs))

        assert len(rep_samples) > 1, f"Preset '{pid}' produced static representative controller color: {rep_samples}"


def test_house_architecture_presets_api_and_3d_roofline_geometry(tmp_path: Path) -> None:
    """
    Verify:
    - Default architectures for House 1 (craftsman_multi_section — Neighbor 1 Left House),
      House 2 (a_frame_gable — My House Middle, Front-Only 2-story peak + garage eave + porch peak),
      and House 3 (two_story_estate — Neighbor 2 Right House).
    - GET /api/architecture/presets returns all 5 templates.
    - PATCH /api/houses/house-1/architecture updates sections (triangle gable + flat eave + dormer),
      camera angles, default_view_mode, and controller section_spans / custom_nodes.
    - PATCH /api/controllers/{controller_id}/zones syncs wall_zones from section_spans.
    - build_virtual_strip_map and render_frame_at populate section_id, arch_x, arch_y, arch_z with
      peak elevation at the middle of a triangle_gable and horizontal alignment in front_street_sync.
    """
    store = ConfigStore(data_dir=str(tmp_path))
    cfg = store.get()
    houses_by_id = {h.id: h for h in cfg.houses}

    h1 = houses_by_id["house-1"]
    h2 = houses_by_id["house-2"]
    h3 = houses_by_id["house-3"]

    assert h1.architecture is not None
    assert h1.architecture.preset_style == "craftsman_multi_section"
    h1_sec_ids = {s.id for s in h1.architecture.sections}
    assert {
        "sec-upper-dormer",
        "sec-upper-right-eave",
        "sec-entry-gable",
        "sec-garage-square",
        "sec-left-eave",
        "sec-right-eave",
        "sec-back-eave",
    }.issubset(h1_sec_ids)

    assert h2.architecture is not None
    assert h2.architecture.preset_style == "a_frame_gable"
    h2_sec_ids = {s.id for s in h2.architecture.sections}
    assert h2_sec_ids == {"sec-main-gable", "sec-lower-garage-eave", "sec-lower-porch-gable"}
    assert all(s.wall == "front" for s in h2.architecture.sections)

    assert h3.architecture is not None
    assert h3.architecture.preset_style == "two_story_estate"
    h3_sec_ids = {s.id for s in h3.architecture.sections}
    assert {
        "sec-left-tower-gable",
        "sec-center-flat-fascia",
        "sec-right-garage-gable",
        "sec-left-wing",
        "sec-right-wing",
        "sec-back-wing",
    }.issubset(h3_sec_ids)

    # Check build_virtual_strip_map populates section_id, arch_x, arch_y, arch_z with peak at middle of sec-main-gable on House 2
    slots = build_virtual_strip_map(cfg)
    h2_gable_slots = [s for s in slots if s.house.id == "house-2" and s.section_id == "sec-main-gable"]
    assert len(h2_gable_slots) == 5
    mid_idx = len(h2_gable_slots) // 2
    assert h2_gable_slots[mid_idx].arch_y > h2_gable_slots[0].arch_y + 0.25
    assert h2_gable_slots[mid_idx].arch_y > h2_gable_slots[-1].arch_y + 0.25
    assert abs(h2_gable_slots[mid_idx].arch_x - 0.50) < 0.08
    assert h2_gable_slots[0].arch_x < h2_gable_slots[mid_idx].arch_x < h2_gable_slots[-1].arch_x

    # Check front_street_sync horizontally aligns Upper (story=2) and Lower (story=1) front sections by arch_x
    cfg.animation.zone_mode = "front_street_sync"
    sync_slots = build_virtual_strip_map(cfg)
    for hid in ("house-1", "house-2", "house-3"):
        front_slots = [s for s in sync_slots if s.house.id == hid and s.wall == "front"]
        assert len(front_slots) > 0
        for s in front_slots:
            expected_local = max(0.02, min(0.98, (s.arch_x - 0.02) / 0.96))
            assert abs(s.house_local_pos - expected_local) < 1e-6
    cfg.animation.zone_mode = "all_segments"

    from backend.app.main import app

    with TestClient(app) as client:
        client.post("/api/config/reset")

        # 1. GET /api/architecture/presets returns all 5 templates
        r_presets = client.get("/api/architecture/presets")
        assert r_presets.status_code == 200
        presets = r_presets.json().get("presets", [])
        assert len(presets) == 5
        preset_ids = {p["preset_style"] for p in presets}
        assert preset_ids == {
            "a_frame_gable",
            "craftsman_multi_section",
            "two_story_estate",
            "modern_stepped",
            "colonial_dormer",
        }

        # 2. PATCH /api/houses/house-1/architecture updates sections, camera angles, default_view_mode, and controller mappings
        patch_payload = {
            "architecture": {
                "preset_style": "custom_hybrid",
                "default_view_mode": "2d",
                "camera_yaw": -35.0,
                "camera_pitch": 28.0,
                "camera_zoom": 1.25,
                "siding_color": "#1f2937",
                "trim_color": "#38bdf8",
                "roof_color": "#0f172a",
                "sections": [
                    {
                        "id": "sec-main-gable",
                        "label": "Custom Front Triangle Peak",
                        "shape": "triangle_gable",
                        "wall": "front",
                        "story": 1,
                        "x_start": 0.05,
                        "x_end": 0.55,
                        "eave_height": 0.50,
                        "peak_height": 0.92,
                        "peak_offset": 0.50,
                        "depth_offset": 0.10,
                        "has_garage": False,
                        "has_door": True,
                        "window_style": "picture",
                    },
                    {
                        "id": "sec-garage-flat",
                        "label": "Right Garage Flat Eave",
                        "shape": "flat_eave",
                        "wall": "front",
                        "story": 1,
                        "x_start": 0.55,
                        "x_end": 0.95,
                        "eave_height": 0.48,
                        "peak_height": 0.48,
                        "peak_offset": 0.50,
                        "depth_offset": 0.16,
                        "has_garage": True,
                        "has_door": False,
                        "window_style": "modern_grid",
                    },
                    {
                        "id": "sec-upper-dormer",
                        "label": "Upper Dormer Peak",
                        "shape": "dormer_peak",
                        "wall": "front",
                        "story": 2,
                        "x_start": 0.20,
                        "x_end": 0.50,
                        "eave_height": 0.68,
                        "peak_height": 0.96,
                        "peak_offset": 0.50,
                        "depth_offset": -0.05,
                        "has_garage": False,
                        "has_door": False,
                        "window_style": "arched",
                    },
                ],
            },
            "controller_mappings": [
                {
                    "controller_id": "h1-ctrl-1",
                    "section_spans": [
                        {"section_id": "sec-main-gable", "wall": "front", "segments": 9, "direction": "ltr"},
                        {"section_id": "sec-garage-flat", "wall": "front", "segments": 3, "direction": "ltr"},
                    ],
                    "custom_nodes": [
                        {"x": 0.05, "y": 0.50, "z": 0.10, "wall": "front", "label": "Left Corner"},
                        {"x": 0.30, "y": 0.92, "z": 0.10, "wall": "front", "label": "Gable Apex"},
                    ],
                },
                {
                    "controller_id": "h1-ctrl-2",
                    "section_spans": [
                        {"section_id": "sec-garage-flat", "wall": "front", "segments": 6, "direction": "ltr"},
                        {"section_id": "sec-upper-dormer", "wall": "front", "segments": 6, "direction": "rtl"},
                    ],
                },
            ],
        }
        r_patch = client.patch("/api/houses/house-1/architecture", json=patch_payload)
        assert r_patch.status_code == 200
        body = r_patch.json()
        assert body["ok"] is True
        updated_h1 = body["house"]
        assert updated_h1["architecture"]["default_view_mode"] == "2d"
        assert updated_h1["architecture"]["camera_yaw"] == -35.0
        assert updated_h1["architecture"]["camera_pitch"] == 28.0
        assert updated_h1["architecture"]["camera_zoom"] == 1.25
        assert len(updated_h1["architecture"]["sections"]) == 3
        ctrl1 = next(c for c in updated_h1["controllers"] if c["id"] == "h1-ctrl-1")
        assert len(ctrl1["section_spans"]) == 2
        assert len(ctrl1["custom_nodes"]) == 2
        assert ctrl1["wall_zones"] == [{"wall": "front", "segments": 12}]

        from backend.app.models import SystemConfig

        # Verify triangle_gable peak elevation at segment index 4 (middle of 9 segments on sec-main-gable)
        live_cfg = SystemConfig.model_validate(body["config"])
        patched_slots = build_virtual_strip_map(live_cfg)
        c1_gable_slots = [
            s for s in patched_slots if s.controller.id == "h1-ctrl-1" and s.section_id == "sec-main-gable"
        ]
        assert len(c1_gable_slots) == 9
        assert abs(c1_gable_slots[0].arch_y - 0.50) < 1e-3
        assert abs(c1_gable_slots[4].arch_y - 0.92) < 1e-3
        assert abs(c1_gable_slots[8].arch_y - 0.50) < 1e-3

        # 3. PATCH /api/controllers/h2-ctrl-1/zones with section_spans and custom_nodes
        r_zones = client.patch(
            "/api/controllers/h2-ctrl-1/zones",
            json={
                "section_spans": [
                    {"section_id": "sec-garage-square", "wall": "front", "segments": 4, "direction": "ltr"},
                    {"section_id": "sec-entry-gable", "wall": "front", "segments": 5, "direction": "ltr"},
                ],
                "custom_nodes": [
                    {"x": 0.04, "y": 0.48, "z": 0.16, "wall": "front", "label": "Garage Start"},
                ],
            },
        )
        assert r_zones.status_code == 200
        z_body = r_zones.json()
        assert z_body["ok"] is True
        assert len(z_body["controller"]["section_spans"]) == 2
        assert z_body["controller"]["wall_zones"] == [{"wall": "front", "segments": 9}]

        client.post("/api/config/reset")




