from __future__ import annotations

import asyncio
import base64
import collections
import datetime as dt
import ipaddress
import json
import logging
import os
import socket
import struct
import subprocess
import time
import uuid
from typing import Any, Callable, Deque, Dict, List, Optional, Set, Tuple

import httpx

from .models import ControllerConfig, DiscoveredDevice, HouseConfig, PacketLogEntry, ProtocolMode, SystemConfig

logger = logging.getLogger("govee_sync.protocol")

RGBTuple = Tuple[int, int, int]


def get_arp_neighbor_ips() -> List[str]:
    """
    Collect active IPv4 neighbors from `/proc/net/arp` and `ip -4 neigh show`
    so unicast UDP discovery reaches Govee controllers even when mesh APs drop multicast.
    """
    ips: Set[str] = set()
    try:
        arp_path = "/proc/net/arp"
        if os.path.exists(arp_path):
            with open(arp_path, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.read().splitlines()[1:]
            for line in lines:
                parts = line.split()
                if len(parts) >= 4:
                    ip_str, flags = parts[0], parts[2]
                    if flags != "0x0":
                        try:
                            ip_obj = ipaddress.IPv4Address(ip_str)
                            if not ip_obj.is_loopback and not ip_obj.is_multicast:
                                ips.add(ip_str)
                        except ValueError:
                            pass
    except Exception as exc:
        logger.debug("ARP table read note: %s", exc)

    try:
        proc = subprocess.run(
            ["ip", "-4", "neigh", "show"],
            capture_output=True,
            text=True,
            timeout=1.5,
            check=False,
        )
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                parts = line.split()
                if parts and ("lladdr" in parts or "REACHABLE" in parts or "STALE" in parts or "DELAY" in parts):
                    try:
                        ip_obj = ipaddress.IPv4Address(parts[0])
                        if not ip_obj.is_loopback and not ip_obj.is_multicast:
                            ips.add(parts[0])
                    except ValueError:
                        pass
    except Exception:
        pass

    return sorted(ips)


def get_local_subnet_targets(max_hosts: int = 1024) -> Tuple[List[str], List[str]]:
    """
    Discover local private IPv4 subnet unicast and broadcast addresses (/24 or /22)
    for sweeping UDP :4001 discovery across mesh networks.
    """
    unicast_ips: List[str] = []
    broadcast_ips: Set[str] = set()
    seen_ips: Set[str] = set()
    interfaces: List[ipaddress.IPv4Interface] = []

    try:
        proc = subprocess.run(
            ["ip", "-4", "-o", "addr", "show"],
            capture_output=True,
            text=True,
            timeout=1.5,
            check=False,
        )
        if proc.returncode == 0:
            for line in proc.stdout.splitlines():
                parts = line.split()
                for idx, tok in enumerate(parts):
                    if tok == "inet" and idx + 1 < len(parts):
                        try:
                            iface = ipaddress.IPv4Interface(parts[idx + 1])
                            if iface.ip.is_private and not iface.ip.is_loopback:
                                # Ignore Docker internal bridge subnets (172.16.0.0/12) when a LAN subnet exists
                                interfaces.append(iface)
                        except ValueError:
                            pass
    except Exception:
        pass

    if not interfaces:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("10.255.255.255", 80))
            local_ip = s.getsockname()[0]
            s.close()
            interfaces.append(ipaddress.IPv4Interface(f"{local_ip}/24"))
        except Exception:
            pass

    # Prefer 192.168.x.x or 10.x.x.x LAN interfaces over container bridge networks
    lan_ifaces = [i for i in interfaces if str(i.ip).startswith(("192.168.", "10."))] or interfaces

    for iface in lan_ifaces:
        net = iface.network
        broadcast_ips.add(str(net.broadcast_address))
        # Also include the local /24 broadcast and /24 hosts first so closest neighbors are scanned first
        local_24 = ipaddress.IPv4Network(f"{iface.ip}/24", strict=False)
        broadcast_ips.add(str(local_24.broadcast_address))
        for host_ip in local_24.hosts():
            ip_s = str(host_ip)
            if ip_s not in seen_ips and ip_s != str(iface.ip):
                seen_ips.add(ip_s)
                unicast_ips.append(ip_s)

        # If network is /22 or /23, also include remaining hosts up to max_hosts
        if 22 <= net.prefixlen < 24 and len(unicast_ips) < max_hosts:
            for host_ip in net.hosts():
                ip_s = str(host_ip)
                if ip_s not in seen_ips and ip_s != str(iface.ip):
                    seen_ips.add(ip_s)
                    unicast_ips.append(ip_s)
                    if len(unicast_ips) >= max_hosts:
                        break

    return unicast_ips[:max_hosts], sorted(broadcast_ips)


def build_ptreal_segment_packet(r: int, g: int, b: int, segment_indices: List[int]) -> str:
    """
    Build a 20-byte Govee BLE-over-LAN `ptReal` RGBIC segment color command (0x33 0x05 0x15 0x01 ...).
    Encodes a 16-bit segment mask for segments 0..14 and appends the 19-byte XOR checksum.
    """
    mask = 0
    for idx in segment_indices:
        if 0 <= idx < 16:
            mask |= 1 << idx
    mask_lo = mask & 0xFF
    mask_hi = (mask >> 8) & 0xFF

    pkt = bytearray(20)
    pkt[0] = 0x33
    pkt[1] = 0x05
    pkt[2] = 0x15
    pkt[3] = 0x01
    pkt[4] = max(0, min(255, int(r)))
    pkt[5] = max(0, min(255, int(g)))
    pkt[6] = max(0, min(255, int(b)))
    pkt[12] = mask_lo
    pkt[13] = mask_hi

    xor_sum = 0
    for i in range(19):
        xor_sum ^= pkt[i]
    pkt[19] = xor_sum
    return base64.b64encode(bytes(pkt)).decode("ascii")


def compute_representative_controller_color(segment_colors: List[RGBTuple]) -> RGBTuple:
    """
    Compute the vivid focal RGB color for a controller when sending LAN `colorwc` or Cloud `colorRgb`.
    Never flat-averages dissimilar colors across all segments (which turns rainbows and multi-color
    scenes into a static muddy grey):
    - If the strip has a localized bright chase pulse over a dark background (`min_brightness < 45`
      and `max_brightness > min_brightness + 50`), tracks the active pulse (returning the focal center
      segment when the pulse reaches the center, or the brightest active segment scaled by proximity
      as it approaches/exits) so every controller transitions vividly through Lead -> Mid -> Tail -> Base.
    - Otherwise (for continuous multi-color scenes like `govee_rainbow1`, `govee_rainbow2`,
      `rainbow_wave`, `christmas_magic`, `diwali_festival`, `fire_sparkle`, `split_complimentary`, etc.),
      returns the center focal segment `segment_colors[len(segment_colors) // 2]` so as the wave moves
      across the house, the controller cycles through 100% pure, saturated scene colors continuously.
    """
    if not segment_colors:
        return (0, 0, 0)
    n = len(segment_colors)
    if n == 1:
        return segment_colors[0]

    energies = [max(r, g, b) for r, g, b in segment_colors]
    max_brightness = max(energies)
    if max_brightness == 0:
        return (0, 0, 0)
    min_brightness = min(energies)

    mid = n // 2
    mid_rgb = segment_colors[mid]
    mid_energy = energies[mid]

    # 2-color uniform block wipe transition across the controller (e.g. color_wipe where both colors are lit)
    first_c, last_c = segment_colors[0], segment_colors[-1]
    unique_colors = set(segment_colors)
    if (
        min_brightness > 20
        and len(unique_colors) == 2
        and first_c != last_c
        and (segment_colors[1] == first_c or segment_colors[-2] == last_c)
    ):
        avg_r = round(sum(c[0] for c in segment_colors) / n)
        avg_g = round(sum(c[1] for c in segment_colors) / n)
        avg_b = round(sum(c[2] for c in segment_colors) / n)
        return (avg_r, avg_g, avg_b)

    # If the center focal segment is lit, return its pure color directly so the controller
    # cycles through every color of the wave/chase/marquee as it passes across the house.
    if mid_energy >= 22:
        return mid_rgb

    # Sparse pulse over a dark background where the center segment is currently dark
    best_idx, best_rgb = max(
        enumerate(segment_colors),
        key=lambda item: (max(item[1]), item[1][0] + item[1][1] + item[1][2], -abs(item[0] - mid)),
    )
    max_dist = max(1, mid, n - 1 - mid)
    dist = abs(best_idx - mid)
    scale = 1.0 - 0.25 * (dist / max_dist)
    return (
        max(0, min(255, round(best_rgb[0] * scale))),
        max(0, min(255, round(best_rgb[1] * scale))),
        max(0, min(255, round(best_rgb[2] * scale))),
    )


def group_segments_by_color(
    segment_colors: List[RGBTuple], quantize_step: int = 8, max_groups: int = 4
) -> List[Tuple[RGBTuple, List[int]]]:
    """
    Partition all segment indices `0..N-1` into at most `max_groups` vivid color groups so
    100% of segments on the controller are covered by `<= max_groups` `segmentedColorRgb` or
    `ptReal` commands (never leaving orphaned segments behind when smooth gradients produce
    >max_groups distinct RGB values).
    """
    if not segment_colors:
        return []

    buckets: Dict[RGBTuple, List[int]] = {}
    peak_rgb: Dict[RGBTuple, RGBTuple] = {}

    for idx, (r, g, b) in enumerate(segment_colors):
        key = (
            (r // quantize_step) * quantize_step,
            (g // quantize_step) * quantize_step,
            (b // quantize_step) * quantize_step,
        )
        buckets.setdefault(key, []).append(idx)
        prev_peak = peak_rgb.get(key)
        if prev_peak is None or (max(r, g, b), r + g + b) > (max(prev_peak), sum(prev_peak)):
            peak_rgb[key] = (r, g, b)

    grouped: List[Tuple[RGBTuple, List[int]]] = [
        (peak_rgb[key], indices) for key, indices in buckets.items()
    ]
    grouped.sort(key=lambda item: (max(item[0]), len(item[1])), reverse=True)

    if len(grouped) <= max_groups:
        return grouped

    # Select `max_groups` maximally color-distinct seed colors so all palette colors are preserved
    seeds: List[RGBTuple] = [grouped[0][0]]
    remaining_candidates = [g[0] for g in grouped[1:]]
    while len(seeds) < max_groups and remaining_candidates:
        best_cand = max(
            remaining_candidates,
            key=lambda c: min(
                (c[0] - s[0]) ** 2 + (c[1] - s[1]) ** 2 + (c[2] - s[2]) ** 2
                for s in seeds
            ),
        )
        seeds.append(best_cand)
        remaining_candidates.remove(best_cand)

    # Assign EVERY segment 0..N-1 to its nearest seed color so 100% of the strip updates
    clusters: List[List[int]] = [[] for _ in seeds]
    cluster_peaks: List[RGBTuple] = list(seeds)
    for idx, (r, g, b) in enumerate(segment_colors):
        best_si = min(
            range(len(seeds)),
            key=lambda si: (
                (r - seeds[si][0]) ** 2
                + (g - seeds[si][1]) ** 2
                + (b - seeds[si][2]) ** 2
            ),
        )
        clusters[best_si].append(idx)
        cp = cluster_peaks[best_si]
        if (max(r, g, b), r + g + b) > (max(cp), sum(cp)):
            cluster_peaks[best_si] = (r, g, b)

    merged_groups: List[Tuple[RGBTuple, List[int]]] = [
        (cluster_peaks[si], clusters[si])
        for si in range(len(seeds))
        if clusters[si]
    ]
    merged_groups.sort(key=lambda item: (max(item[0]), len(item[1])), reverse=True)
    return merged_groups


class GoveeUDPListenerProtocol(asyncio.DatagramProtocol):
    """Async UDP listener on port 4002 for Govee LAN `scan` and `devStatus` responses."""

    def __init__(self, on_message: Callable[[dict, Tuple[str, int]], None]) -> None:
        self.on_message = on_message

    def datagram_received(self, data: bytes, addr: Tuple[str, int]) -> None:
        try:
            payload = json.loads(data.decode("utf-8", errors="ignore"))
            self.on_message(payload, addr)
        except Exception as exc:
            logger.debug("Ignored malformed UDP packet from %s: %s", addr, exc)


class GoveeProtocolDriver:
    """
    Manages Govee LAN UDP (multicast discovery on 4001, response listener on 4002,
    unicast control on 4003) and Govee Cloud OpenAPI v1 fallback.
    """

    CLOUD_BASE_URL = "https://openapi.api.govee.com/router/api/v1"

    def __init__(self) -> None:
        self.multicast_group = os.environ.get("GOVEE_LAN_MULTICAST", "239.255.255.250")
        self.scan_port = int(os.environ.get("GOVEE_LAN_SCAN_PORT", "4001"))
        self.listen_port = int(os.environ.get("GOVEE_LAN_LISTEN_PORT", "4002"))
        self.control_port = int(os.environ.get("GOVEE_LAN_CONTROL_PORT", "4003"))

        self._send_sock: Optional[socket.socket] = None
        self._listen_transport: Optional[asyncio.DatagramTransport] = None
        self._http_client: Optional[httpx.AsyncClient] = None

        self.discovered_devices: Dict[str, DiscoveredDevice] = {}
        self.packet_logs: Deque[PacketLogEntry] = collections.deque(maxlen=300)

        # Connected Neighbor Bridge WebSocket relays keyed by house_id
        self.connected_bridges: Dict[str, Any] = {}
        self.bridge_info: Dict[str, Dict[str, Any]] = {}

        # Delta cache & rate limiters per controller
        self._last_sent_rgb: Dict[str, RGBTuple] = {}
        self._last_sent_sig: Dict[str, Tuple[RGBTuple, ...]] = {}
        self._last_sent_time: Dict[str, float] = {}
        self._last_sent_brightness: Dict[str, int] = {}
        self._cloud_last_call: Dict[str, float] = {}
        self._cloud_group_cursor: Dict[str, int] = {}
        self._cloud_powered_on: Set[str] = set()
        self._cloud_offline_until: Dict[str, float] = {}
        self._cloud_last_error: Dict[str, str] = {}
        self._active_cloud_scene: Dict[str, Dict[str, Any]] = {}
        self.device_scenes_cache: Dict[str, Dict[str, Dict[str, Any]]] = {}

        self.stats = {
            "lan_packets_sent": 0,
            "lan_ptreal_packets_sent": 0,
            "bridge_packets_sent": 0,
            "cloud_requests_sent": 0,
            "simulated_frames": 0,
            "send_errors": 0,
            "dedup_skipped": 0,
            "connected_bridges": 0,
            "listener_active": False,
        }

    async def start(self) -> None:
        """Open non-blocking UDP control socket, bind UDP 4002 listener, and init Cloud HTTP client."""
        if self._send_sock is None:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, struct.pack("b", 2))
            sock.setblocking(False)
            self._send_sock = sock

        if self._http_client is None:
            self._http_client = httpx.AsyncClient(timeout=3.5)

        loop = asyncio.get_running_loop()
        try:
            listen_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
            listen_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if hasattr(socket, "SO_REUSEPORT"):
                try:
                    listen_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
                except OSError:
                    pass
            listen_sock.bind(("0.0.0.0", self.listen_port))

            # Join multicast group 239.255.255.250 on all interfaces
            mreq = struct.pack("4s4s", socket.inet_aton(self.multicast_group), socket.inet_aton("0.0.0.0"))
            try:
                listen_sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            except OSError as exc:
                logger.debug("Multicast membership note on UDP %d: %s", self.listen_port, exc)

            listen_sock.setblocking(False)
            transport, _ = await loop.create_datagram_endpoint(
                lambda: GoveeUDPListenerProtocol(self._handle_udp_response),
                sock=listen_sock,
            )
            self._listen_transport = transport
            self.stats["listener_active"] = True
            logger.info("Govee LAN UDP listener bound on 0.0.0.0:%d (multicast %s)", self.listen_port, self.multicast_group)
        except Exception as exc:
            self.stats["listener_active"] = False
            logger.warning("Could not bind UDP listener port %d (%s); unicast sending still active", self.listen_port, exc)

    async def stop(self) -> None:
        if self._listen_transport is not None:
            self._listen_transport.close()
            self._listen_transport = None
        if self._send_sock is not None:
            self._send_sock.close()
            self._send_sock = None
        if self._http_client is not None:
            await self._http_client.aclose()
            self._http_client = None

    def _handle_udp_response(self, payload: dict, addr: Tuple[str, int]) -> None:
        msg = payload.get("msg", {})
        cmd = msg.get("cmd")
        data = msg.get("data", {})
        ip = data.get("ip") or addr[0]

        if cmd == "scan":
            mac = (data.get("device") or ip).upper()
            sku = data.get("sku") or "Govee-LAN"
            dev = DiscoveredDevice(
                ip=ip,
                mac=mac,
                sku=sku,
                name=f"{sku} ({ip})",
                source="lan",
                ble_version_hard=str(data.get("bleVersionHard", "")),
                ble_version_soft=str(data.get("bleVersionSoft", "")),
                wifi_version_hard=str(data.get("wifiVersionHard", "")),
                wifi_version_soft=str(data.get("wifiVersionSoft", "")),
                last_seen=time.time(),
                online=True,
            )
            self.discovered_devices[mac] = dev
            logger.info("Discovered Govee LAN device: %s (%s) at %s", sku, mac, ip)
        elif cmd == "devStatus":
            for dev in self.discovered_devices.values():
                if dev.ip == ip:
                    dev.last_seen = time.time()
                    dev.online = True
                    dev.on_off = data.get("onOff")
                    dev.brightness = data.get("brightness")

    def _send_udp_json(self, ip: str, port: int, message: dict) -> bool:
        if not self._send_sock or not ip:
            return False
        raw = json.dumps(message, separators=(",", ":")).encode("utf-8")
        try:
            self._send_sock.sendto(raw, (ip, port))
            return True
        except OSError as exc:
            self.stats["send_errors"] += 1
            logger.debug("UDP send to %s:%d failed: %s", ip, port, exc)
            return False

    def register_bridge(self, house_id: str, ws: Any, remote_addr: str = "") -> None:
        self.connected_bridges[house_id] = ws
        self.bridge_info[house_id] = {
            "house_id": house_id,
            "connected_at": time.time(),
            "last_seen": time.time(),
            "remote_addr": remote_addr,
            "devices": [],
            "packets_relayed": 0,
        }
        self.stats["connected_bridges"] = len(self.connected_bridges)
        logger.info("Neighbor Bridge connected for house %s from %s", house_id, remote_addr)

    def unregister_bridge(self, house_id: str, ws: Any = None) -> None:
        current = self.connected_bridges.get(house_id)
        if ws is None or current is ws:
            self.connected_bridges.pop(house_id, None)
            self.bridge_info.pop(house_id, None)
            self.stats["connected_bridges"] = len(self.connected_bridges)
            logger.info("Neighbor Bridge disconnected for house %s", house_id)

    async def _send_bridge_udp(
        self,
        house_id: str,
        ctrl: ControllerConfig,
        messages: List[dict],
    ) -> bool:
        ws = self.connected_bridges.get(house_id)
        if ws is None:
            return False
        payload = {
            "type": "udp_relay",
            "house_id": house_id,
            "controller_id": ctrl.id,
            "ip": ctrl.ip,
            "mac": ctrl.mac,
            "port": self.control_port,
            "messages": messages,
        }
        try:
            await ws.send_json(payload)
            self.stats["bridge_packets_sent"] += 1
            if house_id in self.bridge_info:
                self.bridge_info[house_id]["packets_relayed"] = (
                    self.bridge_info[house_id].get("packets_relayed", 0) + len(messages)
                )
                self.bridge_info[house_id]["last_seen"] = time.time()
            return True
        except Exception as exc:
            self.stats["send_errors"] += 1
            logger.debug("Neighbor bridge send failed for house %s: %s", house_id, exc)
            self.unregister_bridge(house_id, ws)
            return False

    async def discover_cloud_devices(self, api_key: str) -> List[DiscoveredDevice]:
        """
        Query Govee Cloud OpenAPI v1 `/user/devices` with a specific (global or per-house) API key.
        Returns the list of discovered devices for that account and updates `self.discovered_devices`.
        """
        clean_key = (api_key or "").strip()
        if not clean_key:
            return []

        own_client = False
        client = self._http_client
        if client is None:
            client = httpx.AsyncClient(timeout=5.0)
            own_client = True

        found: List[DiscoveredDevice] = []
        try:
            resp = await client.get(
                f"{self.CLOUD_BASE_URL}/user/devices",
                headers={"Govee-API-Key": clean_key, "Content-Type": "application/json"},
            )
            if resp.status_code == 200:
                body = resp.json()
                for item in body.get("data", []):
                    dev_type = str(item.get("type", ""))
                    caps = item.get("capabilities", [])
                    is_light = "light" in dev_type.lower() or any(
                        "color_setting" in str(c.get("type", ""))
                        or "segment_color_setting" in str(c.get("type", ""))
                        for c in caps
                    )
                    if not is_light:
                        continue
                    mac = str(item.get("device", "")).upper()
                    sku = str(item.get("sku", "Govee-Cloud"))
                    name = str(item.get("deviceName", sku))
                    has_seg = any(
                        "segment_color_setting" in str(c.get("type", ""))
                        or c.get("instance") == "segmentedColorRgb"
                        for c in caps
                    )
                    is_online = True
                    on_off_val: Optional[int] = None
                    bri_val: Optional[int] = None
                    try:
                        st_resp = await client.post(
                            f"{self.CLOUD_BASE_URL}/device/state",
                            headers={"Govee-API-Key": clean_key, "Content-Type": "application/json"},
                            json={"requestId": str(uuid.uuid4()), "payload": {"sku": sku, "device": mac}},
                        )
                        if st_resp.status_code == 200:
                            st_caps = st_resp.json().get("payload", {}).get("capabilities", [])
                            for sc in st_caps:
                                inst = sc.get("instance")
                                val = sc.get("state", {}).get("value")
                                if inst == "online" and isinstance(val, bool):
                                    is_online = val
                                elif inst == "powerSwitch" and isinstance(val, int):
                                    on_off_val = val
                                elif inst == "brightness" and isinstance(val, int):
                                    bri_val = val
                    except Exception:
                        pass

                    existing = self.discovered_devices.get(mac)
                    dev = DiscoveredDevice(
                        ip=existing.ip if existing else "",
                        mac=mac,
                        sku=sku,
                        name=name,
                        source="cloud" if not (existing and existing.ip) else existing.source,
                        last_seen=time.time(),
                        online=is_online if not (existing and existing.ip) else True,
                        on_off=on_off_val,
                        brightness=bri_val,
                        supports_segment_rgb=has_seg,
                    )
                    self.discovered_devices[mac] = dev
                    found.append(dev)
            else:
                logger.warning("Govee Cloud /user/devices returned HTTP %d: %s", resp.status_code, resp.text[:200])
        except Exception as exc:
            logger.warning("Govee Cloud device discovery failed: %s", exc)
        finally:
            if own_client:
                await client.aclose()

        return found

    async def scan_lan_and_cloud(
        self,
        known_ips: Optional[List[str]] = None,
        api_key: str = "",
        extra_api_keys: Optional[List[str]] = None,
        sweep_subnet: bool = True,
    ) -> List[DiscoveredDevice]:
        """
        Broadcast Govee LAN `scan` request to 239.255.255.250:4001 and 255.255.255.255:4001,
        sweep unicast UDP :4001 across ARP neighbors and local /24 or /22 subnet hosts so
        mesh APs that filter multicast still deliver discovery probes, trigger connected
        Neighbor Bridges to scan, and query Govee Cloud OpenAPI `/user/devices` for all configured keys.
        """
        scan_msg = {"msg": {"cmd": "scan", "data": {"account_topic": "reserve"}}}
        status_msg = {"msg": {"cmd": "devStatus", "data": {}}}
        self._send_udp_json(self.multicast_group, self.scan_port, scan_msg)
        self._send_udp_json("255.255.255.255", self.scan_port, scan_msg)

        priority_ips: Set[str] = set()
        for ip in known_ips or []:
            if ip and ip.strip():
                priority_ips.add(ip.strip())

        for arp_ip in get_arp_neighbor_ips():
            priority_ips.add(arp_ip)

        for ip in sorted(priority_ips):
            self._send_udp_json(ip, self.scan_port, scan_msg)
            self._send_udp_json(ip, self.control_port, status_msg)

        if sweep_subnet and self._send_sock is not None:
            subnet_ips, broadcast_ips = get_local_subnet_targets(max_hosts=1024)
            for bcast in broadcast_ips:
                self._send_udp_json(bcast, self.scan_port, scan_msg)
            for idx, sub_ip in enumerate(subnet_ips):
                if sub_ip in priority_ips:
                    continue
                self._send_udp_json(sub_ip, self.scan_port, scan_msg)
                if (idx + 1) % 96 == 0:
                    await asyncio.sleep(0.002)

        # Trigger remote LAN scan on any connected Neighbor Bridges
        for house_id, ws in list(self.connected_bridges.items()):
            try:
                await ws.send_json({"type": "scan", "house_id": house_id})
            except Exception:
                self.unregister_bridge(house_id, ws)

        # Query Govee Cloud OpenAPI for global key and any per-house keys
        all_keys: List[str] = []
        for k in [api_key] + list(extra_api_keys or []):
            ck = (k or "").strip()
            if ck and ck not in all_keys:
                all_keys.append(ck)

        for ck in all_keys:
            await self.discover_cloud_devices(ck)

        await asyncio.sleep(0.35)
        return sorted(self.discovered_devices.values(), key=lambda d: (d.ip or "zzz", d.mac))

    def _record_log(
        self,
        house: HouseConfig,
        ctrl: ControllerConfig,
        protocol: str,
        cmd: str,
        summary: str,
        rgb: RGBTuple,
        latency_ms: float,
        success: bool,
        enabled: bool = True,
        target_override: str = "",
    ) -> None:
        if not enabled:
            return
        r, g, b = rgb
        now = time.time()
        entry = PacketLogEntry(
            timestamp=now,
            iso_time=dt.datetime.fromtimestamp(now, tz=dt.timezone.utc).strftime("%H:%M:%S.%f")[:-3],
            house_id=house.id,
            house_name=house.name,
            controller_id=ctrl.id,
            controller_name=ctrl.name,
            target_ip=target_override or ctrl.ip or "cloud/sim",
            protocol=protocol,
            cmd=cmd,
            summary=summary,
            rgb_preview=f"#{r:02x}{g:02x}{b:02x}",
            latency_ms=round(latency_ms, 2),
            success=success,
        )
        self.packet_logs.appendleft(entry)

    # Explicit 1-to-1 mapping of all 71 Studio Presets to 71 UNIQUE Govee Hardware Dynamic Scenes
    # (verified from POST /router/api/v1/device/scenes across both H705E and H805D)
    PRESET_TO_GOVEE_SCENE: Dict[str, Dict[str, Any]] = {
        # --- 28 Halloween Presets (mapped to real Govee Official & DIY scenes) ---
        "halloween_haunted_chase": {"name": "Halloween", "id": 10764, "paramId": 17969},
        "halloween_witch_cauldron": {"name": "Halloween B", "id": 10765, "paramId": 17970},
        "halloween_blood_meteor": {"name": "Halloween D", "id": 10767, "paramId": 17972},
        "halloween_pumpkin_marquee": {"name": "Halloween C", "id": 10766, "paramId": 17971},
        "halloween_poltergeist_portal": {"name": "Spooky Halloween AI (DIY)", "diy_name": "spooky halloween ai", "diy_id": 25004667, "id": 14158, "paramId": 22806},
        "halloween_zombie_outbreak": {"name": "Halloween II", "id": 14491, "paramId": 23302},
        "halloween_frankenstein_lab": {"name": "Flash", "id": 23504, "paramId": 34012},
        "halloween_headless_horseman": {"name": "Meteor", "id": 14161, "paramId": 22809},
        "halloween_beetlejuice_sandworm": {"name": "Karst Cave", "id": 10747, "paramId": 17952},
        "halloween_hellfire_brimstone": {"name": "Fire", "id": 10753, "paramId": 17958},
        "halloween_phantom_ghost_train": {"name": "Halloween Chasing (DIY)", "diy_name": "halloween chasing", "diy_id": 24908117, "id": 10764, "paramId": 17969},
        "halloween_shadow_possession": {"name": "Orange & Purple (DIY)", "diy_name": "orange and purple", "diy_id": 24907990, "id": 10765, "paramId": 17970},
        "halloween_black_widow_lair": {"name": "Night", "id": 10795, "paramId": 18000},
        "halloween_haunted_heartbeat": {"name": "Profound", "id": 10811, "paramId": 18016},
        "halloween_candy_corn_parade": {"name": "Fall", "id": 10757, "paramId": 17962},
        "halloween_pharaoh_curse": {"name": "Sunset Glow", "id": 10739, "paramId": 17944},
        "halloween_rainbow1_spooky_prism": {"name": "Rainbow", "id": 10744, "paramId": 17949},
        "halloween_rainbow2_monster_blocks": {"name": "Stacking", "id": 10806, "paramId": 18011},
        "halloween_rainbow1_hocus_pocus": {"name": "Dreamlike", "id": 10815, "paramId": 18020},
        "halloween_rainbow2_candy_corn_blocks": {"name": "Cornfield", "id": 10749, "paramId": 17954},
        "halloween_rainbow1_ectoplasm_wave": {"name": "Forest", "id": 10745, "paramId": 17950},
        "halloween_rainbow2_dracula_castle": {"name": "Sunset", "id": 10738, "paramId": 17943},
        "halloween_rainbow1_pumpkin_spice": {"name": "Rustling leaves", "id": 10750, "paramId": 17955},
        "halloween_rainbow2_goblin_parade": {"name": "Spin", "id": 10799, "paramId": 18004},
        "halloween_rainbow1_witches_brew": {"name": "Twilight", "id": 10794, "paramId": 17999},
        "halloween_rainbow2_skeleton_rave": {"name": "Dancing", "id": 10800, "paramId": 18005},
        "halloween_rainbow1_full_spectrum": {"name": "Gradient", "id": 10807, "paramId": 18012},
        "halloween_rainbow2_warlock_crystal": {"name": "Milky Way", "id": 14159, "paramId": 22807},
        # --- 28 Christmas Presets (mapped to real Govee Official & DIY scenes) ---
        "xmas_sleigh_ride": {"name": "Sled", "id": 10763, "paramId": 17968},
        "xmas_candy_cane": {"name": "Candy Cane", "id": 14165, "paramId": 22813},
        "xmas_frozen_aurora": {"name": "Winter Wonderland", "id": 10787, "paramId": 17992},
        "xmas_nutcracker_marquee": {"name": "Christmas", "id": 10760, "paramId": 17965},
        "xmas_rudolph_dash": {"name": "Delivering Gifts", "id": 14492, "paramId": 23303},
        "xmas_north_pole_beacon": {"name": "Christmas Tree", "id": 10761, "paramId": 17966},
        "xmas_grinch_heist": {"name": "Leprechaun", "id": 10788, "paramId": 17993},
        "xmas_polar_express": {"name": "Winter", "id": 10758, "paramId": 17963},
        "xmas_gingerbread_village": {"name": "Christmas Gift", "id": 10762, "paramId": 17967},
        "xmas_arctic_blizzard": {"name": "Downpour", "id": 10759, "paramId": 17964},
        "xmas_yule_log_hearth": {"name": "Warm", "id": 10816, "paramId": 18021},
        "xmas_elf_workshop_ribbon": {"name": "Children's Day", "id": 14169, "paramId": 22817},
        "xmas_star_of_bethlehem": {"name": "Christmas Eve", "id": 14166, "paramId": 22814},
        "xmas_sugar_plum_fairy": {"name": "Dreamland", "id": 10818, "paramId": 18023},
        "xmas_mistletoe_harmony": {"name": "Christmas Wreath", "id": 14167, "paramId": 22815},
        "xmas_rainbow1_classic_C9": {"name": "Christmas Bell", "id": 14164, "paramId": 22812},
        "xmas_rainbow2_c9_blocks": {"name": "Colorful", "id": 10803, "paramId": 18008},
        "xmas_rainbow1_peppermint_silk": {"name": "Red White Running (DIY)", "diy_name": "red white running", "diy_id": 25240693, "id": 14165, "paramId": 22813},
        "xmas_rainbow2_candy_shoppe": {"name": "Amusement", "id": 14172, "paramId": 22820},
        "xmas_rainbow1_arctic_aurora": {"name": "Aurora", "id": 10746, "paramId": 17951},
        "xmas_rainbow2_glacier_blocks": {"name": "Lake", "id": 14162, "paramId": 22810},
        "xmas_rainbow1_royal_nativity": {"name": "Star", "id": 10742, "paramId": 17947},
        "xmas_rainbow2_toy_soldier": {"name": "Swing", "id": 10802, "paramId": 18007},
        "xmas_rainbow1_pastel_macaron": {"name": "Cherry blossoms", "id": 10754, "paramId": 17959},
        "xmas_rainbow2_jingle_bell_rock": {"name": "Music Show", "id": 14171, "paramId": 22819},
        "xmas_rainbow1_full_spectrum": {"name": "Flower Parade", "id": 14174, "paramId": 22822},
        "xmas_rainbow2_wreath_and_holly": {"name": "Saint Patrick's Day", "id": 10783, "paramId": 17988},
        "xmas_frost_vs_flame": {"name": "ZDP Duo", "id": 23508, "paramId": 34016},
        # --- 4 Diwali Presets ---
        "diwali_golden_diya": {"name": "Candlelight", "id": 10782, "paramId": 17987},
        "diwali_rangoli_wave": {"name": "Flower Field", "id": 10751, "paramId": 17956},
        "diwali_firecracker_sparkle": {"name": "Hooray", "id": 14175, "paramId": 22823},
        "diwali_aarti_flame": {"name": "Sunrise", "id": 10737, "paramId": 17942},
        # --- 3 Center-Out Presets ---
        "center_supernova": {"name": "Universe", "id": 10743, "paramId": 17948},
        "center_golden_ripple": {"name": "Morning", "id": 10792, "paramId": 17997},
        "center_serpent_clash": {"name": "ZDP Trio", "id": 23509, "paramId": 34017},
        # --- 4 Cyber & Party Presets ---
        "cyber_chase": {"name": "Flow", "id": 10804, "paramId": 18009},
        "dual_comet_pingpong": {"name": "Active", "id": 10819, "paramId": 18024},
        "seamless_rainbow": {"name": "Enthusiastic", "id": 10812, "paramId": 18017},
        "harmonic_pulse": {"name": "Fluctuate", "id": 10805, "paramId": 18010},
        # --- 4 Celebrations Presets ---
        "seahawks_gameday": {"name": "Game Day", "id": 10785, "paramId": 17990},
        "july4_fireworks": {"name": "Fireworks", "id": 10781, "paramId": 17986},
        "holiday_marquee": {"name": "Carnival", "id": 10776, "paramId": 17981},
        "hearth_fire": {"name": "Firefly", "id": 10752, "paramId": 17957},
    }

    DEFAULT_GOVEE_SCENES: Dict[str, Dict[str, Any]] = {
        v["name"].lower(): v for v in PRESET_TO_GOVEE_SCENE.values()
    }

    def resolve_govee_light_scene(
        self,
        preset_id: str,
        effect: str = "",
        category: str = "",
        mac: str = "",
    ) -> Dict[str, Any]:
        """
        Map any Studio preset ID or effect to its unique official Govee hardware `lightScene`
        (`devices.capabilities.dynamic_scene`, `instance: "lightScene"`, `value: {"id", "paramId"}`).
        """
        pid = (preset_id or "").strip().lower()
        if pid in self.PRESET_TO_GOVEE_SCENE:
            return dict(self.PRESET_TO_GOVEE_SCENE[pid])

        eff = (effect or "").lower()
        if eff == "govee_rainbow1" or eff == "rainbow_wave":
            return {"name": "Rainbow", "id": 10744, "paramId": 17949}
        if eff == "govee_rainbow2":
            return {"name": "Flow", "id": 10804, "paramId": 18009}
        if eff == "halloween_spooky":
            return {"name": "Halloween", "id": 10764, "paramId": 17969}
        if eff == "christmas_magic":
            return {"name": "Christmas", "id": 10760, "paramId": 17965}
        if eff == "diwali_festival":
            return {"name": "Candlelight", "id": 10782, "paramId": 17987}
        if eff == "lightning_storm":
            return {"name": "Thunderstorm", "id": 14158, "paramId": 22806}
        if eff == "comet_meteor":
            return {"name": "Meteor", "id": 14161, "paramId": 22809}
        if eff == "fire_sparkle":
            return {"name": "Fire", "id": 10753, "paramId": 17958}
        return {"name": "Rainbow", "id": 10744, "paramId": 17949}

    async def fetch_device_scenes(self, api_key: str, sku: str, mac: str) -> Dict[str, Dict[str, Any]]:
        """
        Query `POST /router/api/v1/device/scenes` for a specific controller and cache its dynamic scenes.
        """
        clean_key = (api_key or "").strip()
        clean_mac = (mac or "").strip().upper()
        if not clean_key or not clean_mac:
            return {}
        if clean_mac in self.device_scenes_cache and self.device_scenes_cache[clean_mac]:
            return self.device_scenes_cache[clean_mac]

        own_client = False
        client = self._http_client
        if client is None:
            client = httpx.AsyncClient(timeout=5.0)
            own_client = True

        scenes_map: Dict[str, Dict[str, Any]] = {}
        try:
            resp = await client.post(
                f"{self.CLOUD_BASE_URL}/device/scenes",
                headers={"Govee-API-Key": clean_key, "Content-Type": "application/json"},
                json={"requestId": str(uuid.uuid4()), "payload": {"sku": sku or "H705E", "device": clean_mac}},
            )
            if resp.status_code == 200:
                caps = resp.json().get("payload", {}).get("capabilities", [])
                for cap in caps:
                    if cap.get("instance") == "lightScene":
                        for opt in cap.get("parameters", {}).get("options", []):
                            nm = " ".join(str(opt.get("name", "")).split()).strip()
                            val = opt.get("value", {})
                            if nm and isinstance(val, dict) and "id" in val and "paramId" in val:
                                key_l = nm.lower()
                                if key_l not in scenes_map:
                                    scenes_map[key_l] = {
                                        "name": nm,
                                        "id": val["id"],
                                        "paramId": val["paramId"],
                                    }
                if scenes_map:
                    self.device_scenes_cache[clean_mac] = scenes_map
        except Exception as exc:
            logger.debug("fetch_device_scenes failed for %s: %s", clean_mac, exc)
        finally:
            if own_client:
                await client.aclose()
        return scenes_map

    async def send_cloud_light_scene(
        self,
        house: HouseConfig,
        ctrl: ControllerConfig,
        effective_api_key: str,
        preset_id: str,
        effect: str = "",
        category: str = "",
        brightness: int = 100,
        verbose_logging: bool = True,
        primary_hex: str = "#00f5d4",
        secondary_hex: str = "#7b2cbf",
        accent_hex: str = "#ff007f",
    ) -> Dict[str, Any]:
        """
        Send a single atomic Govee OpenAPI v2 `lightScene` or `diyScene` command (`POST /device/control`),
        locking `_active_cloud_scene[ctrl.id]` before awaiting HTTP so the 25 FPS loop never triggers
        HTTP 429 rate limits or overwrites the scene with `colorwc`. Automatically retries once on HTTP 429.
        """
        clean_key = (effective_api_key or "").strip()
        if not clean_key or not ctrl.mac or ctrl.mac.upper().startswith("AA:BB:CC:DD:EE:"):
            return {"ok": False, "reason": "missing_api_key_or_mac"}

        t0 = time.perf_counter()
        scene_info = self.resolve_govee_light_scene(preset_id, effect=effect, category=category, mac=ctrl.mac)
        now_mono = time.monotonic()

        # Pre-register active cloud scene IMMEDIATELY before any await so 25 FPS loop never sends colorwc / 429s
        self._active_cloud_scene[ctrl.id] = {
            "preset_id": preset_id,
            "effect": effect,
            "category": category,
            "scene_name": scene_info["name"],
            "id": scene_info["id"],
            "paramId": scene_info["paramId"],
            "applied": True,
            "last_attempt": now_mono,
        }
        self._cloud_last_call[ctrl.id] = now_mono

        headers = {"Govee-API-Key": clean_key, "Content-Type": "application/json"}
        target_label = f"cloud:{ctrl.mac[-8:]}" if not ctrl.ip else ctrl.ip

        own_client = False
        client = self._http_client
        if client is None:
            client = httpx.AsyncClient(timeout=4.5)
            own_client = True

        dev_meta = self.discovered_devices.get(ctrl.mac.upper())
        try:
            # Determine if this preset uses a Govee DIY scene (`diyScene`) or Official `lightScene`
            diy_val = None
            if scene_info.get("diy_name"):
                # Lookup controller's own DIY scene ID by name if cached, else use diy_id on My House H705E
                diy_map = getattr(self, "device_diy_cache", {}).get(ctrl.mac.upper(), {})
                if not diy_map:
                    try:
                        d_resp = await client.post(
                            f"{self.CLOUD_BASE_URL}/device/diy-scenes",
                            headers=headers,
                            json={"requestId": str(uuid.uuid4()), "payload": {"sku": ctrl.sku or "H705E", "device": ctrl.mac}},
                        )
                        if d_resp.status_code == 200:
                            d_caps = d_resp.json().get("payload", {}).get("capabilities", [])
                            for dc in d_caps:
                                if dc.get("instance") == "diyScene":
                                    for opt in dc.get("parameters", {}).get("options", []):
                                        d_nm = " ".join(str(opt.get("name", "")).split()).strip().lower()
                                        if d_nm and opt.get("value") is not None:
                                            diy_map[d_nm] = opt["value"]
                            if not hasattr(self, "device_diy_cache"):
                                self.device_diy_cache = {}
                            self.device_diy_cache[ctrl.mac.upper()] = diy_map
                    except Exception:
                        pass
                diy_val = diy_map.get(scene_info["diy_name"].lower())

            if diy_val is not None:
                cap_payload = {
                    "type": "devices.capabilities.dynamic_scene",
                    "instance": "diyScene",
                    "value": diy_val,
                }
            else:
                cap_payload = {
                    "type": "devices.capabilities.dynamic_scene",
                    "instance": "lightScene",
                    "value": {
                        "paramId": scene_info["paramId"],
                        "id": scene_info["id"],
                    },
                }

            req_json = {
                "requestId": str(uuid.uuid4()),
                "payload": {
                    "sku": ctrl.sku or "H705E",
                    "device": ctrl.mac,
                    "capability": cap_payload,
                },
            }
            scene_resp = await client.post(
                f"{self.CLOUD_BASE_URL}/device/control",
                headers=headers,
                json=req_json,
            )
            self.stats["cloud_requests_sent"] += 1

            # If Govee returns HTTP 429 due to a recent burst, wait 1.2s and retry once
            if scene_resp.status_code == 429:
                await asyncio.sleep(1.2)
                req_json["requestId"] = str(uuid.uuid4())
                scene_resp = await client.post(
                    f"{self.CLOUD_BASE_URL}/device/control",
                    headers=headers,
                    json=req_json,
                )
                self.stats["cloud_requests_sent"] += 1

            ok = scene_resp.status_code == 200
            err_msg = ""
            is_offline = False
            if ok:
                try:
                    rj = scene_resp.json()
                    cap_state = rj.get("capability", {}).get("state", {}) if isinstance(rj.get("capability"), dict) else {}
                    err_msg = str(cap_state.get("errorMsg") or rj.get("msg") or "")
                    if rj.get("code", 200) not in (200, "200") or cap_state.get("status") == "failure":
                        ok = False
                        is_offline = "offline" in err_msg.lower()
                except Exception:
                    pass
            else:
                err_msg = f"HTTP {scene_resp.status_code}"

            now_done = time.monotonic()
            self._cloud_last_call[ctrl.id] = now_done
            self._active_cloud_scene[ctrl.id]["applied"] = ok
            self._active_cloud_scene[ctrl.id]["last_attempt"] = now_done

            if ok:
                self._cloud_powered_on.add(ctrl.id)
                self._cloud_offline_until.pop(ctrl.id, None)
                self._cloud_last_error.pop(ctrl.id, None)
                if dev_meta is not None:
                    dev_meta.online = True
                    dev_meta.on_off = 1
                self._record_log(
                    house,
                    ctrl,
                    "CLOUD-SCENE",
                    "diyScene" if diy_val is not None else "lightScene",
                    f"scene='{scene_info['name']}' -> OK",
                    (0, 245, 212),
                    (time.perf_counter() - t0) * 1000.0,
                    True,
                    True,
                    target_override=target_label,
                )
            else:
                self.stats["send_errors"] += 1
                self._cloud_last_error[ctrl.id] = err_msg or "Failed to apply scene"
                if is_offline:
                    self._cloud_offline_until[ctrl.id] = now_done + 15.0
                    self._cloud_powered_on.discard(ctrl.id)
                    if dev_meta is not None:
                        dev_meta.online = False
                self._record_log(
                    house,
                    ctrl,
                    "CLOUD-SCENE",
                    "offline" if is_offline else "lightSceneError",
                    f"scene='{scene_info['name']}' -> {err_msg}",
                    (255, 80, 80),
                    (time.perf_counter() - t0) * 1000.0,
                    False,
                    True,
                    target_override=target_label,
                )
            return {
                "ok": ok,
                "offline": is_offline,
                "error": err_msg if not ok else "",
                "scene": scene_info,
            }
        except Exception as exc:
            self.stats["send_errors"] += 1
            self._cloud_last_error[ctrl.id] = str(exc)
            if ctrl.id in self._active_cloud_scene:
                self._active_cloud_scene[ctrl.id]["applied"] = False
            return {"ok": False, "offline": False, "error": str(exc), "scene": scene_info}
        finally:
            if own_client:
                await client.aclose()

    async def apply_cloud_scene_to_all(
        self,
        config: SystemConfig,
        preset_id: str,
        effect: str = "",
        category: str = "",
    ) -> List[Dict[str, Any]]:
        """
        Trigger Govee hardware `lightScene` or `diyScene` across all enabled houses & controllers.
        """
        tasks = []
        meta = []
        p_hex = getattr(config.animation, "primary_color", "#00f5d4")
        s_hex = getattr(config.animation, "secondary_color", "#7b2cbf")
        a_hex = getattr(config.animation, "accent_color", "#ff007f")
        for house in config.houses:
            if not house.enabled:
                continue
            effective_key = (house.govee_api_key or config.govee_api_key or "").strip()
            for ctrl in house.controllers:
                if not ctrl.enabled:
                    continue
                if effective_key and ctrl.mac:
                    eff_bri = (
                        ctrl.brightness_override
                        if ctrl.brightness_override is not None
                        else getattr(config.animation, "intensity", 100)
                    )
                    tasks.append(
                        self.send_cloud_light_scene(
                            house=house,
                            ctrl=ctrl,
                            effective_api_key=effective_key,
                            preset_id=preset_id,
                            effect=effect,
                            category=category,
                            brightness=eff_bri,
                            verbose_logging=config.verbose_packet_logging,
                            primary_hex=p_hex,
                            secondary_hex=s_hex,
                            accent_hex=a_hex,
                        )
                    )
                    meta.append((house.id, ctrl.id, ctrl.name))
        if not tasks:
            return []
        raw_results = await asyncio.gather(*tasks, return_exceptions=True)
        out = []
        for (hid, cid, cname), res in zip(meta, raw_results):
            if isinstance(res, dict):
                out.append({"house_id": hid, "controller_id": cid, "controller_name": cname, **res})
            else:
                out.append({"house_id": hid, "controller_id": cid, "controller_name": cname, "ok": False, "error": str(res)})
        return out

    def clear_active_cloud_scenes(self) -> None:
        """Exit hardware `lightScene` mode so static/custom RGB colors can be sent directly."""
        self._active_cloud_scene.clear()

    async def _send_cloud_control(
        self,
        house: HouseConfig,
        ctrl: ControllerConfig,
        segment_colors: List[RGBTuple],
        rep_rgb: RGBTuple,
        effective_api_key: str,
        now: float,
        t_start: float,
        verbose_logging: bool,
        force_send: bool = False,
    ) -> bool:
        """
        Send Govee Cloud OpenAPI v1 `/device/control` using `segmentedColorRgb` with automatic
        fallback to whole-device `colorRgb` when segment capability is unsupported or rejected.
        """
        if not effective_api_key or not ctrl.mac:
            return False

        offline_until = self._cloud_offline_until.get(ctrl.id, 0.0)
        if now < offline_until and not force_send:
            return False

        last_cloud = self._cloud_last_call.get(ctrl.id, 0.0)
        # Respect Govee Cloud OpenAPI rate limit (~2 req/sec/device) unless force_send (e.g. stop/blackout)
        if (now - last_cloud) < 0.50 and not force_send:
            return False
        self._cloud_last_call[ctrl.id] = now

        own_client = False
        client = self._http_client
        if client is None:
            client = httpx.AsyncClient(timeout=4.0)
            own_client = True

        dev_meta = self.discovered_devices.get(ctrl.mac.upper())
        prefer_segment = True if dev_meta is None else dev_meta.supports_segment_rgb
        groups = group_segments_by_color(segment_colors, quantize_step=24, max_groups=3)
        cursor = self._cloud_group_cursor.get(ctrl.id, 0)
        self._cloud_group_cursor[ctrl.id] = cursor + 1
        if groups:
            top_rgb, top_indices = groups[cursor % len(groups)]
        else:
            top_rgb, top_indices = rep_rgb, list(range(len(segment_colors)))
        seg_rgb_int = (top_rgb[0] << 16) | (top_rgb[1] << 8) | top_rgb[2]
        rep_rgb_int = (rep_rgb[0] << 16) | (rep_rgb[1] << 8) | rep_rgb[2]

        headers = {"Govee-API-Key": effective_api_key, "Content-Type": "application/json"}
        target_label = f"cloud:{ctrl.mac[-8:]}" if not ctrl.ip else ctrl.ip

        def _parse_govee_response(resp_obj: httpx.Response) -> Tuple[bool, bool, str]:
            if resp_obj.status_code != 200:
                return False, False, f"HTTP {resp_obj.status_code}"
            try:
                rj = resp_obj.json()
                if isinstance(rj, dict):
                    code = rj.get("code", 200)
                    msg = str(rj.get("msg") or "")
                    cap_state = rj.get("capability", {}).get("state", {}) if isinstance(rj.get("capability"), dict) else {}
                    err_msg = str(cap_state.get("errorMsg") or msg or "")
                    if code not in (200, "200") or cap_state.get("status") == "failure":
                        is_off = "offline" in err_msg.lower()
                        return False, is_off, err_msg or f"code {code}"
            except Exception:
                pass
            return True, False, "OK"

        try:
            if ctrl.id not in self._cloud_powered_on and any(c > 0 for c in rep_rgb):
                pwr_resp = await client.post(
                    f"{self.CLOUD_BASE_URL}/device/control",
                    headers=headers,
                    json={
                        "requestId": str(uuid.uuid4()),
                        "payload": {
                            "sku": ctrl.sku or "H705A",
                            "device": ctrl.mac,
                            "capability": {
                                "type": "devices.capabilities.on_off",
                                "instance": "powerSwitch",
                                "value": 1,
                            },
                        },
                    },
                )
                self.stats["cloud_requests_sent"] += 1
                pwr_ok, pwr_offline, pwr_err = _parse_govee_response(pwr_resp)
                if pwr_offline:
                    self._cloud_offline_until[ctrl.id] = now + 15.0
                    self._cloud_last_error[ctrl.id] = pwr_err
                    if dev_meta is not None:
                        dev_meta.online = False
                    self.stats["send_errors"] += 1
                    self._record_log(
                        house,
                        ctrl,
                        "CLOUD",
                        "offline",
                        f"{pwr_err} (check 2.4 GHz Wi-Fi & power)",
                        rep_rgb,
                        (time.perf_counter() - t_start) * 1000.0,
                        False,
                        True,
                        target_override=target_label,
                    )
                    return False
                if pwr_ok:
                    self._cloud_powered_on.add(ctrl.id)
                    self._cloud_last_error.pop(ctrl.id, None)
                    if dev_meta is not None:
                        dev_meta.online = True

            if prefer_segment:
                seg_body = {
                    "requestId": str(uuid.uuid4()),
                    "payload": {
                        "sku": ctrl.sku or "H705A",
                        "device": ctrl.mac,
                        "capability": {
                            "type": "devices.capabilities.segment_color_setting",
                            "instance": "segmentedColorRgb",
                            "value": {
                                "segment": top_indices,
                                "rgb": seg_rgb_int,
                            },
                        },
                    },
                }
                resp = await client.post(
                    f"{self.CLOUD_BASE_URL}/device/control",
                    headers=headers,
                    json=seg_body,
                )
                self.stats["cloud_requests_sent"] += 1
                resp_ok, is_offline, err_msg = _parse_govee_response(resp)

                if resp_ok:
                    self._cloud_offline_until.pop(ctrl.id, None)
                    self._cloud_last_error.pop(ctrl.id, None)
                    self._cloud_powered_on.add(ctrl.id)
                    if dev_meta is not None:
                        dev_meta.online = True
                    self._record_log(
                        house,
                        ctrl,
                        "CLOUD",
                        "segmentedColorRgb",
                        f"segs {top_indices[:6]}.. rgb=#{seg_rgb_int:06x} OK",
                        top_rgb,
                        (time.perf_counter() - t_start) * 1000.0,
                        True,
                        verbose_logging,
                        target_override=target_label,
                    )
                    return True

                if is_offline:
                    self._cloud_offline_until[ctrl.id] = now + 15.0
                    self._cloud_last_error[ctrl.id] = err_msg
                    self._cloud_powered_on.discard(ctrl.id)
                    if dev_meta is not None:
                        dev_meta.online = False
                    self.stats["send_errors"] += 1
                    self._record_log(
                        house,
                        ctrl,
                        "CLOUD",
                        "offline",
                        f"{err_msg} (check 2.4 GHz Wi-Fi & power)",
                        top_rgb,
                        (time.perf_counter() - t_start) * 1000.0,
                        False,
                        True,
                        target_override=target_label,
                    )
                    return False

                if dev_meta is not None:
                    dev_meta.supports_segment_rgb = False

            color_body = {
                "requestId": str(uuid.uuid4()),
                "payload": {
                    "sku": ctrl.sku or "H705A",
                    "device": ctrl.mac,
                    "capability": {
                        "type": "devices.capabilities.color_setting",
                        "instance": "colorRgb",
                        "value": rep_rgb_int,
                    },
                },
            }
            resp2 = await client.post(
                f"{self.CLOUD_BASE_URL}/device/control",
                headers=headers,
                json=color_body,
            )
            self.stats["cloud_requests_sent"] += 1
            ok2, is_offline2, err_msg2 = _parse_govee_response(resp2)
            if is_offline2:
                self._cloud_offline_until[ctrl.id] = now + 15.0
                self._cloud_last_error[ctrl.id] = err_msg2
                self._cloud_powered_on.discard(ctrl.id)
                if dev_meta is not None:
                    dev_meta.online = False
                self.stats["send_errors"] += 1
            elif ok2:
                self._cloud_offline_until.pop(ctrl.id, None)
                self._cloud_last_error.pop(ctrl.id, None)
                self._cloud_powered_on.add(ctrl.id)
                if dev_meta is not None:
                    dev_meta.online = True

            self._record_log(
                house,
                ctrl,
                "CLOUD",
                "colorRgb" if ok2 else "offline",
                f"rgb=#{rep_rgb_int:06x} OK" if ok2 else f"{err_msg2}",
                rep_rgb,
                (time.perf_counter() - t_start) * 1000.0,
                ok2,
                verbose_logging or not ok2,
                target_override=target_label,
            )
            return ok2
        except Exception as exc:
            self.stats["send_errors"] += 1
            self._record_log(
                house,
                ctrl,
                "CLOUD",
                "device/control",
                f"error: {exc}",
                rep_rgb,
                (time.perf_counter() - t_start) * 1000.0,
                False,
                verbose_logging,
                target_override=f"cloud:{ctrl.mac[-8:]}" if not ctrl.ip else ctrl.ip,
            )
            return False
        finally:
            if own_client:
                await client.aclose()

    async def dispatch_controller_frame(
        self,
        house: HouseConfig,
        ctrl: ControllerConfig,
        segment_colors: List[RGBTuple],
        master_intensity: int,
        lan_enabled: bool,
        cloud_fallback_enabled: bool,
        api_key: str,
        verbose_logging: bool,
        force_send: bool = False,
    ) -> None:
        """
        Send the calculated segment colors for a single controller using the configured house & controller transport:
        - Neighbor Bridge WebSocket Relay (`house.id in connected_bridges` or `connection_type == "neighbor_bridge"`):
          Streams 25 FPS UDP `:4003` (`colorwc` / `ptReal`) over WebSocket to the neighbor's local bridge script.
        - Per-House or Global Govee Cloud OpenAPI (`connection_type == "govee_cloud"` or `protocol_mode == CLOUD_API`):
          Sends `segmentedColorRgb` with automatic `colorRgb` fallback using `house.govee_api_key or api_key`.
        - Local LAN / Tailscale VPN UDP `:4003` (`colorwc` or `ptReal`):
          Sends direct UDP packets to `ctrl.ip:4003`.
        - Simulation (virtual preview only).
        """
        if not segment_colors:
            return

        rep_rgb = compute_representative_controller_color(segment_colors)
        now = time.monotonic()

        # Check delta cache across representative focal color AND first/last segments so multi-segment motion is never skipped
        frame_sig = (rep_rgb, segment_colors[0], segment_colors[-1])
        prev_sig = self._last_sent_sig.get(ctrl.id)
        last_time = self._last_sent_time.get(ctrl.id, 0.0)
        color_delta = (
            999
            if prev_sig is None
            else max(
                max(abs(a[0] - b[0]), abs(a[1] - b[1]), abs(a[2] - b[2]))
                for a, b in zip(frame_sig, prev_sig)
            )
        )

        if not force_send and color_delta < 2 and (now - last_time) < 0.75:
            self.stats["dedup_skipped"] += 1
            return

        self._last_sent_rgb[ctrl.id] = rep_rgb
        self._last_sent_sig[ctrl.id] = frame_sig
        self._last_sent_time[ctrl.id] = now

        effective_brightness = ctrl.brightness_override if ctrl.brightness_override is not None else master_intensity
        prev_bri = self._last_sent_brightness.get(ctrl.id)
        effective_api_key = (getattr(house, "govee_api_key", "") or api_key or "").strip()
        conn_type = getattr(house, "connection_type", "local_lan") or "local_lan"

        mode = ctrl.protocol_mode
        t_start = time.perf_counter()

        # 1. Pure Simulation Mode
        if mode == ProtocolMode.SIMULATION or (not lan_enabled and not cloud_fallback_enabled):
            self.stats["simulated_frames"] += 1
            self._record_log(
                house,
                ctrl,
                "SIM",
                "virtualFrame",
                f"{len(segment_colors)} segs -> rep rgb({rep_rgb[0]},{rep_rgb[1]},{rep_rgb[2]})",
                rep_rgb,
                (time.perf_counter() - t_start) * 1000.0,
                True,
                verbose_logging,
            )
            return

        # 1b. If controller has an active Govee Cloud hardware `lightScene` (`devices.capabilities.dynamic_scene`),
        # do NOT overwrite it with static `colorwc` / `colorRgb` frames. Retry every 15s if offline.
        active_scene = self._active_cloud_scene.get(ctrl.id)
        if active_scene is not None and effective_api_key and ctrl.mac:
            if prev_bri != effective_brightness and ctrl.ip and lan_enabled:
                self._send_udp_json(
                    ctrl.ip,
                    self.control_port,
                    {"msg": {"cmd": "brightness", "data": {"value": int(effective_brightness)}}},
                )
                self._last_sent_brightness[ctrl.id] = effective_brightness
            if not active_scene.get("applied") and now >= self._cloud_offline_until.get(ctrl.id, 0.0):
                await self.send_cloud_light_scene(
                    house=house,
                    ctrl=ctrl,
                    effective_api_key=effective_api_key,
                    preset_id=active_scene.get("preset_id", ""),
                    effect=active_scene.get("effect", ""),
                    category=active_scene.get("category", ""),
                    brightness=effective_brightness,
                    verbose_logging=verbose_logging,
                )
            return

        # Build the UDP :4003 command messages for LAN or Neighbor Bridge relay
        udp_messages: List[dict] = []
        if prev_bri != effective_brightness:
            udp_messages.append({"msg": {"cmd": "brightness", "data": {"value": int(effective_brightness)}}})
            self._last_sent_brightness[ctrl.id] = effective_brightness

        if mode == ProtocolMode.LAN_PTREAL:
            groups = group_segments_by_color(segment_colors, quantize_step=12, max_groups=3)
            b64_cmds = [build_ptreal_segment_packet(rgb[0], rgb[1], rgb[2], idxs) for rgb, idxs in groups]
            udp_messages.append({"msg": {"cmd": "ptReal", "data": {"command": b64_cmds}}})
            udp_cmd_name = "ptReal"
            udp_summary = f"{len(b64_cmds)} seg-groups ({len(segment_colors)} segs)"
        else:
            udp_messages.append(
                {
                    "msg": {
                        "cmd": "colorwc",
                        "data": {
                            "color": {"r": rep_rgb[0], "g": rep_rgb[1], "b": rep_rgb[2]},
                            "colorTemInKelvin": 0,
                        },
                    }
                }
            )
            udp_cmd_name = "colorwc"
            udp_summary = f"rgb({rep_rgb[0]},{rep_rgb[1]},{rep_rgb[2]})"

        # 2. Method B: Connected Neighbor Bridge WebSocket Relay (25 FPS over Internet -> Neighbor LAN UDP :4003)
        if house.id in self.connected_bridges and (
            conn_type in ("neighbor_bridge", "govee_cloud") or not ctrl.ip
        ):
            ok = await self._send_bridge_udp(house.id, ctrl, udp_messages)
            self._record_log(
                house,
                ctrl,
                "BRIDGE-WS",
                udp_cmd_name,
                f"{udp_summary} -> bridge:{house.id} ({ctrl.ip or ctrl.mac})",
                rep_rgb,
                (time.perf_counter() - t_start) * 1000.0,
                ok,
                verbose_logging,
                target_override=f"bridge://{house.id}/{ctrl.ip or ctrl.mac}",
            )
            if ok:
                return

        # 3. Method A: Explicit Govee Cloud OpenAPI or multi-segment RGBIC controller with Cloud API key
        # NOTE: For RGBIC controllers with a Cloud API key (e.g. H705E / H805D) in AUTO mode, use multi-segment
        # `segmentedColorRgb` rather than 1-color `LAN-UDP colorwc` (which flattens all segments to a single color).
        dev_meta_chk = self.discovered_devices.get((ctrl.mac or "").upper())
        has_cloud_seg = bool(
            effective_api_key
            and ctrl.mac
            and not ctrl.mac.upper().startswith("AA:BB:CC:DD:EE:")
            and (dev_meta_chk is None or dev_meta_chk.supports_segment_rgb)
            and mode in (ProtocolMode.AUTO, ProtocolMode.CLOUD_API)
        )
        if conn_type == "govee_cloud" or mode == ProtocolMode.CLOUD_API or (not ctrl.ip and effective_api_key) or has_cloud_seg:
            if effective_api_key and ctrl.mac:
                if prev_bri != effective_brightness and ctrl.ip and lan_enabled:
                    self._send_udp_json(
                        ctrl.ip,
                        self.control_port,
                        {"msg": {"cmd": "brightness", "data": {"value": int(effective_brightness)}}},
                    )
                    self._last_sent_brightness[ctrl.id] = effective_brightness
                await self._send_cloud_control(
                    house=house,
                    ctrl=ctrl,
                    segment_colors=segment_colors,
                    rep_rgb=rep_rgb,
                    effective_api_key=effective_api_key,
                    now=now,
                    t_start=t_start,
                    verbose_logging=verbose_logging,
                    force_send=force_send,
                )
                return
            # No API key yet configured for this cloud neighbor house -> record simulated preview frame
            self.stats["simulated_frames"] += 1
            self._record_log(
                house,
                ctrl,
                "SIM-CLOUD",
                "awaitingApiKey",
                f"{udp_summary} (set house Govee API key or connect Neighbor Bridge)",
                rep_rgb,
                (time.perf_counter() - t_start) * 1000.0,
                True,
                verbose_logging,
                target_override="cloud:unconfigured",
            )
            return

        # 4. Local LAN or Tailscale/VPN UDP :4003 Path
        if lan_enabled and ctrl.ip and mode in (ProtocolMode.AUTO, ProtocolMode.LAN_COLORWC, ProtocolMode.LAN_PTREAL):
            ok = True
            for msg in udp_messages:
                ok = self._send_udp_json(ctrl.ip, self.control_port, msg) and ok
            if mode == ProtocolMode.LAN_PTREAL:
                self.stats["lan_ptreal_packets_sent"] += 1
            else:
                self.stats["lan_packets_sent"] += 1
            self._record_log(
                house,
                ctrl,
                "LAN-VPN" if conn_type == "tailscale_vpn" else "LAN-UDP",
                udp_cmd_name,
                f"{udp_summary} -> {ctrl.ip}:{self.control_port}",
                rep_rgb,
                (time.perf_counter() - t_start) * 1000.0,
                ok,
                verbose_logging,
            )

            if mode == ProtocolMode.AUTO and not (cloud_fallback_enabled and effective_api_key):
                return

        # 5. Cloud Fallback Path (if LAN unavailable or opportunistic segment sync)
        if cloud_fallback_enabled and effective_api_key and ctrl.mac:
            await self._send_cloud_control(
                house=house,
                ctrl=ctrl,
                segment_colors=segment_colors,
                rep_rgb=rep_rgb,
                effective_api_key=effective_api_key,
                now=now,
                t_start=t_start,
                verbose_logging=verbose_logging,
                force_send=force_send,
            )

    async def blackout_all_controllers(self, config: SystemConfig, turn_off: bool = True) -> None:
        """
        Immediately blackout (`colorwc` 0,0,0) and optionally power off (`turn` 0) all enabled controllers
        across LAN, Neighbor Bridges, and Govee Cloud when Stop Sync is triggered.
        """
        self._last_sent_rgb.clear()
        self._last_sent_sig.clear()
        self._last_sent_time.clear()
        self._cloud_powered_on.clear()
        self._cloud_offline_until.clear()
        self._active_cloud_scene.clear()

        blackout_msg = {
            "msg": {
                "cmd": "colorwc",
                "data": {"color": {"r": 0, "g": 0, "b": 0}, "colorTemInKelvin": 0},
            }
        }
        turn_off_msg = {"msg": {"cmd": "turn", "data": {"value": 0}}}
        msgs = [blackout_msg, turn_off_msg] if turn_off else [blackout_msg]

        tasks = []
        for house in config.houses:
            if not house.enabled:
                continue
            effective_key = (house.govee_api_key or config.govee_api_key or "").strip()
            for ctrl in house.controllers:
                if not ctrl.enabled:
                    continue
                t0 = time.perf_counter()
                sent_any = False

                if house.id in self.connected_bridges:
                    ok_b = await self._send_bridge_udp(house.id, ctrl, msgs)
                    sent_any = sent_any or ok_b
                    self._record_log(
                        house,
                        ctrl,
                        "BRIDGE-WS",
                        "stopBlackout",
                        f"rgb(0,0,0) + turn(0) -> bridge:{house.id}",
                        (0, 0, 0),
                        (time.perf_counter() - t0) * 1000.0,
                        ok_b,
                        config.verbose_packet_logging,
                        target_override=f"bridge://{house.id}/{ctrl.ip or ctrl.mac}",
                    )

                if config.lan_enabled and ctrl.ip:
                    ok_l = True
                    for m in msgs:
                        ok_l = self._send_udp_json(ctrl.ip, self.control_port, m) and ok_l
                    self.stats["lan_packets_sent"] += len(msgs)
                    sent_any = sent_any or ok_l
                    self._record_log(
                        house,
                        ctrl,
                        "LAN-UDP",
                        "stopBlackout",
                        f"rgb(0,0,0) + turn(0) -> {ctrl.ip}:{self.control_port}",
                        (0, 0, 0),
                        (time.perf_counter() - t0) * 1000.0,
                        ok_l,
                        config.verbose_packet_logging,
                    )

                if effective_key and ctrl.mac and self._http_client:
                    tasks.append(self.send_power_command(ctrl, turn_on=False, api_key=effective_key, house_id=house.id))
                elif not sent_any:
                    self._record_log(
                        house,
                        ctrl,
                        "SIM",
                        "stopBlackout",
                        "stopped -> rgb(0,0,0)",
                        (0, 0, 0),
                        (time.perf_counter() - t0) * 1000.0,
                        True,
                        config.verbose_packet_logging,
                    )

        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def send_power_command(
        self, ctrl: ControllerConfig, turn_on: bool, api_key: str = "", house_id: str = ""
    ) -> bool:
        val = 1 if turn_on else 0
        ok = False
        turn_msg = {"msg": {"cmd": "turn", "data": {"value": val}}}
        if house_id and house_id in self.connected_bridges:
            ok = await self._send_bridge_udp(house_id, ctrl, [turn_msg]) or ok
        if ctrl.ip:
            ok = self._send_udp_json(ctrl.ip, self.control_port, turn_msg) or ok
            self.stats["lan_packets_sent"] += 1
        if api_key and ctrl.mac and self._http_client:
            try:
                resp = await self._http_client.post(
                    f"{self.CLOUD_BASE_URL}/device/control",
                    headers={"Govee-API-Key": api_key, "Content-Type": "application/json"},
                    json={
                        "requestId": str(uuid.uuid4()),
                        "payload": {
                            "sku": ctrl.sku or "H705A",
                            "device": ctrl.mac,
                            "capability": {
                                "type": "devices.capabilities.on_off",
                                "instance": "powerSwitch",
                                "value": val,
                            },
                        },
                    },
                )
                self.stats["cloud_requests_sent"] += 1
                if resp.status_code == 200:
                    try:
                        rj = resp.json()
                        c_state = rj.get("capability", {}).get("state", {}) if isinstance(rj.get("capability"), dict) else {}
                        if rj.get("code", 200) in (200, "200") and c_state.get("status") != "failure":
                            ok = True
                            if turn_on:
                                self._cloud_powered_on.add(ctrl.id)
                            else:
                                self._cloud_powered_on.discard(ctrl.id)
                    except Exception:
                        ok = True
            except Exception:
                pass
        return ok

    async def power_on_all_controllers(self, config: SystemConfig) -> None:
        """
        Send hardware power ON (`turn: 1` on LAN/Bridge and `powerSwitch: 1` on Cloud) to all
        enabled controllers across all enabled houses when starting an animation or selecting a scene.
        """
        self._cloud_offline_until.clear()
        tasks = []
        for house in config.houses:
            if not house.enabled:
                continue
            effective_key = (house.govee_api_key or config.govee_api_key or "").strip()
            for ctrl in house.controllers:
                if not ctrl.enabled:
                    continue
                if ctrl.ip and config.lan_enabled:
                    self._send_udp_json(ctrl.ip, self.control_port, {"msg": {"cmd": "turn", "data": {"value": 1}}})
                    self.stats["lan_packets_sent"] += 1
                if house.id in self.connected_bridges or (effective_key and ctrl.mac and not ctrl.ip):
                    tasks.append(self.send_power_command(ctrl, turn_on=True, api_key=effective_key, house_id=house.id))
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def test_controller_pulse(
        self,
        house: HouseConfig,
        ctrl: ControllerConfig,
        rgb: RGBTuple = (0, 245, 212),
        api_key: str = "",
        verbose_logging: bool = True,
    ) -> Dict[str, Any]:
        """
        Send an immediate 1-click test pulse (`turn(1)` + `brightness(100)` + `colorwc(rgb)` + `devStatus`)
        to a specific controller over LAN UDP :4003, Neighbor Bridge WebSocket, or Govee Cloud OpenAPI.
        """
        t0 = time.perf_counter()
        r, g, b = max(0, min(255, int(rgb[0]))), max(0, min(255, int(rgb[1]))), max(0, min(255, int(rgb[2])))
        hex_color = f"#{r:02x}{g:02x}{b:02x}"
        effective_key = (getattr(house, "govee_api_key", "") or api_key or "").strip()

        turn_msg = {"msg": {"cmd": "turn", "data": {"value": 1}}}
        bri_msg = {"msg": {"cmd": "brightness", "data": {"value": 100}}}
        color_msg = {
            "msg": {
                "cmd": "colorwc",
                "data": {"color": {"r": r, "g": g, "b": b}, "colorTemInKelvin": 0},
            }
        }
        status_msg = {"msg": {"cmd": "devStatus", "data": {}}}
        scan_msg = {"msg": {"cmd": "scan", "data": {"account_topic": "reserve"}}}
        udp_msgs = [turn_msg, bri_msg, color_msg, status_msg]

        sent = False
        transports: List[str] = []

        if house.id in self.connected_bridges:
            ok_b = await self._send_bridge_udp(house.id, ctrl, udp_msgs)
            if ok_b:
                sent = True
                transports.append("bridge_ws")

        if ctrl.ip:
            ok_l = True
            for m in udp_msgs:
                ok_l = self._send_udp_json(ctrl.ip, self.control_port, m) and ok_l
            self._send_udp_json(ctrl.ip, self.scan_port, scan_msg)
            self.stats["lan_packets_sent"] += len(udp_msgs)
            if ok_l:
                sent = True
                transports.append(f"lan_udp:{ctrl.ip}:{self.control_port}")

        if effective_key and ctrl.mac:
            ok_pwr = await self.send_power_command(ctrl, turn_on=True, api_key=effective_key, house_id=house.id)
            ok_cld = await self._send_cloud_control(
                house=house,
                ctrl=ctrl,
                segment_colors=[(r, g, b)] * max(1, ctrl.segment_count),
                rep_rgb=(r, g, b),
                effective_api_key=effective_key,
                now=time.monotonic(),
                t_start=t0,
                verbose_logging=verbose_logging,
                force_send=True,
            )
            if ok_pwr or ok_cld:
                sent = True
                transports.append("govee_cloud")

        self._last_sent_rgb[ctrl.id] = (r, g, b)
        self._last_sent_time[ctrl.id] = time.monotonic()

        transport_label = "+".join(transports) if transports else "simulation"
        self._record_log(
            house,
            ctrl,
            "TEST-PULSE",
            "testPulse",
            f"turn(1) + colorwc({r},{g},{b}) [{hex_color}] via {transport_label}",
            (r, g, b),
            (time.perf_counter() - t0) * 1000.0,
            True,
            verbose_logging,
        )

        return {
            "status": "ok",
            "house_id": house.id,
            "house_name": house.name,
            "controller_id": ctrl.id,
            "controller_name": ctrl.name,
            "ip": ctrl.ip,
            "mac": ctrl.mac,
            "sku": ctrl.sku,
            "color": hex_color,
            "rgb": [r, g, b],
            "sent": sent,
            "transport": transport_label,
        }

