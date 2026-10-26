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
    Compute the optimal whole-controller RGB color when sending a LAN `colorwc` packet.
    Instead of a naive flat average (which dims narrow chase pulses on 12-15 segment controllers),
    weights segments by perceptual energy (max channel^2 + 0.15) so active chase heads remain vivid.
    """
    if not segment_colors:
        return (0, 0, 0)
    if len(segment_colors) == 1:
        return segment_colors[0]

    peak_energy = max(max(r, g, b) for r, g, b in segment_colors)
    if peak_energy == 0:
        return (0, 0, 0)

    total_w = 0.0
    acc_r = 0.0
    acc_g = 0.0
    acc_b = 0.0
    for r, g, b in segment_colors:
        m = max(r, g, b) / 255.0
        # Emphasize active/lit segments so chase heads stay sharp on whole-strip LAN controllers
        w = (m ** 2.4) + 0.04
        acc_r += r * w
        acc_g += g * w
        acc_b += b * w
        total_w += w

    if total_w <= 0:
        return segment_colors[0]
    return (
        max(0, min(255, round(acc_r / total_w))),
        max(0, min(255, round(acc_g / total_w))),
        max(0, min(255, round(acc_b / total_w))),
    )


def group_segments_by_color(
    segment_colors: List[RGBTuple], quantize_step: int = 8, max_groups: int = 4
) -> List[Tuple[RGBTuple, List[int]]]:
    """
    Group segment indices that share identical (or quantized) RGB values so we can minimize
    `ptReal` or Cloud `segmentedColorRgb` packets per controller frame.
    """
    buckets: Dict[RGBTuple, List[int]] = {}
    actual_sums: Dict[RGBTuple, List[int]] = {}

    for idx, (r, g, b) in enumerate(segment_colors):
        key = (
            (r // quantize_step) * quantize_step,
            (g // quantize_step) * quantize_step,
            (b // quantize_step) * quantize_step,
        )
        buckets.setdefault(key, []).append(idx)
        if key not in actual_sums:
            actual_sums[key] = [r, g, b, 1]
        else:
            actual_sums[key][0] += r
            actual_sums[key][1] += g
            actual_sums[key][2] += b
            actual_sums[key][3] += 1

    grouped: List[Tuple[RGBTuple, List[int]]] = []
    for key, indices in buckets.items():
        sr, sg, sb, cnt = actual_sums[key]
        avg_rgb = (round(sr / cnt), round(sg / cnt), round(sb / cnt))
        grouped.append((avg_rgb, indices))

    # Prioritize brightest / largest segment groups
    grouped.sort(key=lambda item: (max(item[0]), len(item[1])), reverse=True)
    return grouped[:max_groups]


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
        self._last_sent_time: Dict[str, float] = {}
        self._last_sent_brightness: Dict[str, int] = {}
        self._cloud_last_call: Dict[str, float] = {}

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
                    mac = str(item.get("device", "")).upper()
                    sku = str(item.get("sku", "Govee-Cloud"))
                    name = str(item.get("deviceName", sku))
                    caps = item.get("capabilities", [])
                    has_seg = any(
                        "segment_color_setting" in str(c.get("type", ""))
                        or c.get("instance") == "segmentedColorRgb"
                        for c in caps
                    )
                    existing = self.discovered_devices.get(mac)
                    dev = DiscoveredDevice(
                        ip=existing.ip if existing else "",
                        mac=mac,
                        sku=sku,
                        name=name,
                        source="cloud" if not (existing and existing.ip) else existing.source,
                        last_seen=time.time(),
                        online=True,
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
        groups = group_segments_by_color(segment_colors, quantize_step=16, max_groups=2)
        top_rgb, top_indices = groups[0] if groups else (rep_rgb, list(range(len(segment_colors))))
        seg_rgb_int = (top_rgb[0] << 16) | (top_rgb[1] << 8) | top_rgb[2]
        rep_rgb_int = (rep_rgb[0] << 16) | (rep_rgb[1] << 8) | rep_rgb[2]

        headers = {"Govee-API-Key": effective_api_key, "Content-Type": "application/json"}

        try:
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
                resp_ok = resp.status_code == 200
                if resp_ok:
                    try:
                        rjson = resp.json()
                        if isinstance(rjson, dict) and rjson.get("code", 200) not in (200, "200"):
                            resp_ok = False
                    except Exception:
                        pass

                if resp_ok:
                    self._record_log(
                        house,
                        ctrl,
                        "CLOUD",
                        "segmentedColorRgb",
                        f"segs {top_indices[:6]}.. rgb=#{seg_rgb_int:06x} HTTP {resp.status_code}",
                        top_rgb,
                        (time.perf_counter() - t_start) * 1000.0,
                        True,
                        verbose_logging,
                        target_override=f"cloud:{ctrl.mac[-8:]}" if not ctrl.ip else ctrl.ip,
                    )
                    return True

                # Mark device as needing colorRgb fallback and immediately send colorRgb
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
            ok2 = resp2.status_code == 200
            self._record_log(
                house,
                ctrl,
                "CLOUD",
                "colorRgb",
                f"rgb=#{rep_rgb_int:06x} HTTP {resp2.status_code}",
                rep_rgb,
                (time.perf_counter() - t_start) * 1000.0,
                ok2,
                verbose_logging,
                target_override=f"cloud:{ctrl.mac[-8:]}" if not ctrl.ip else ctrl.ip,
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

        # Check delta cache so unchanged colors aren't spammed needlessly, while sending periodic keepalives
        prev_rgb = self._last_sent_rgb.get(ctrl.id)
        last_time = self._last_sent_time.get(ctrl.id, 0.0)
        color_delta = (
            999
            if prev_rgb is None
            else max(abs(rep_rgb[0] - prev_rgb[0]), abs(rep_rgb[1] - prev_rgb[1]), abs(rep_rgb[2] - prev_rgb[2]))
        )

        if not force_send and color_delta < 2 and (now - last_time) < 0.75:
            self.stats["dedup_skipped"] += 1
            return

        self._last_sent_rgb[ctrl.id] = rep_rgb
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

        # 3. Method A: Explicit Govee Cloud OpenAPI (for neighbors on separate Wi-Fi without an active bridge)
        if conn_type == "govee_cloud" or mode == ProtocolMode.CLOUD_API or (not ctrl.ip and effective_api_key):
            if effective_api_key and ctrl.mac:
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
        self._last_sent_time.clear()

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
                ok = ok or (resp.status_code == 200)
            except Exception:
                pass
        return ok

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

