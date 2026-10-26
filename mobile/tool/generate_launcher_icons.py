#!/usr/bin/env python3
"""
Generates high-resolution Android launcher icons for Govee Multi-House Sync Studio:
- Deep midnight obsidian rounded background (#060B18)
- 3 glowing architectural house rooflines side-by-side:
  * Left House: Neon Cyan (#00F5D4)
  * Middle House (My House): Royal Violet (#A855F7) & Gold (#FBBF24)
  * Right House: Neon Magenta (#FF007F)
- A bright synchronized neon light wave arcing across all 3 roofs.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path


def write_png_rgba(path: Path, width: int, height: int, pixels: bytearray) -> None:
    """Write an RGBA8888 buffer (`width * height * 4` bytes) to a standard PNG file using stdlib zlib."""
    raw_rows = bytearray()
    stride = width * 4
    for y in range(height):
        raw_rows.append(0)  # filter type 0 (None)
        row_start = y * stride
        raw_rows.extend(pixels[row_start : row_start + stride])

    def make_chunk(chunk_type: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + chunk_type + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    compressed = zlib.compress(bytes(raw_rows), level=9)
    png_bytes = (
        b"\x89PNG\r\n\x1a\n"
        + make_chunk(b"IHDR", ihdr)
        + make_chunk(b"IDAT", compressed)
        + make_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png_bytes)


def dist_to_segment(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> tuple[float, float]:
    """Return (distance from (px, py) to segment AB, normalized projection parameter t in [0, 1])."""
    dx = bx - ax
    dy = by - ay
    len_sq = dx * dx + dy * dy
    if len_sq <= 1e-9:
        return math.hypot(px - ax, py - ay), 0.0
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / len_sq))
    proj_x = ax + t * dx
    proj_y = ay + t * dy
    return math.hypot(px - proj_x, py - proj_y), t


def sd_rounded_box(px: float, py: float, cx: float, cy: float, half_w: float, half_h: float, r: float) -> float:
    qx = abs(px - cx) - (half_w - r)
    qy = abs(py - cy) - (half_h - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def lerp_rgb(c1: tuple[float, float, float], c2: tuple[float, float, float], t: float) -> tuple[float, float, float]:
    t = max(0.0, min(1.0, t))
    return (
        c1[0] + (c2[0] - c1[0]) * t,
        c1[1] + (c2[1] - c1[1]) * t,
        c1[2] + (c2[2] - c1[2]) * t,
    )


def render_icon_rgba(size: int, include_background: bool = True) -> bytearray:
    """
    Analytically render the 3-House Neon Roofline Sync icon at `size x size`
    with anti-aliased signed distance fields and multi-house neon bloom.
    """
    buf = bytearray(size * size * 4)

    cyan = (0.0, 245.0, 212.0)       # #00F5D4 (Left House #1)
    violet = (168.0, 85.0, 247.0)    # #A855F7 (Middle House #2)
    gold = (251.0, 191.0, 36.0)      # #FBBF24 (Middle House #2 crown/accent)
    magenta = (255.0, 0.0, 127.0)    # #FF007F (Right House #3)
    white = (255.0, 255.0, 255.0)

    # 3 House definitions in normalized [0, 1] coordinates:
    # Left House (#1), Middle House (#2 - taller), Right House (#3)
    houses = [
        {
            "x0": 0.09,
            "x1": 0.36,
            "eave_y": 0.59,
            "peak_y": 0.39,
            "c1": cyan,
            "c2": (56.0, 189.0, 248.0),
            "win": cyan,
            "is_mid": False,
        },
        {
            "x0": 0.34,
            "x1": 0.66,
            "eave_y": 0.55,
            "peak_y": 0.29,
            "c1": violet,
            "c2": gold,
            "win": gold,
            "is_mid": True,
        },
        {
            "x0": 0.64,
            "x1": 0.91,
            "eave_y": 0.59,
            "peak_y": 0.39,
            "c1": magenta,
            "c2": (244.0, 63.0, 94.0),
            "win": magenta,
            "is_mid": False,
        },
    ]

    # Precompute LED puck coordinates along all 3 roofs
    leds: list[tuple[float, float, tuple[float, float, float], float]] = []
    for h in houses:
        x0 = float(h["x0"])
        x1 = float(h["x1"])
        cx = 0.5 * (x0 + x1)
        ey = float(h["eave_y"])
        py = float(h["peak_y"])
        c1 = h["c1"]  # type: ignore[assignment]
        c2 = h["c2"]  # type: ignore[assignment]
        is_mid = bool(h["is_mid"])
        n_leds = 7 if is_mid else 5
        for i in range(n_leds):
            u = i / (n_leds - 1)
            lx = x0 + u * (x1 - x0)
            roof_t = 1.0 - abs(u - 0.5) * 2.0
            ly = ey - roof_t * (ey - py)
            lcol = lerp_rgb(c1, c2, roof_t)
            leds.append((lx, ly, lcol, 0.015 if is_mid else 0.0125))

    ground_y = 0.80
    aa = 1.25 / size

    for py_i in range(size):
        ny = (py_i + 0.5) / size
        for px_i in range(size):
            nx = (px_i + 0.5) / size

            # 1. Rounded obsidian background (#060B18)
            bg_alpha = 1.0
            if include_background:
                d_box = sd_rounded_box(nx, ny, 0.5, 0.5, 0.465, 0.465, 0.21)
                if d_box > aa:
                    continue
                bg_alpha = max(0.0, min(1.0, 0.5 - d_box / (2.0 * aa)))

                # Deep midnight obsidian gradient (#060B18 -> #0B152C -> #050914)
                if ny < 0.62:
                    t_bg = ny / 0.62
                    r, g, b = lerp_rgb((6.0, 11.0, 24.0), (11.0, 21.0, 44.0), t_bg)
                else:
                    t_bg = (ny - 0.62) / 0.38
                    r, g, b = lerp_rgb((11.0, 21.0, 44.0), (5.0, 9.0, 20.0), t_bg)

                # Subtle outer neon border glow
                rim_dist = abs(d_box + 0.012)
                if rim_dist < 0.025:
                    rim_t = max(0.0, 1.0 - rim_dist / 0.025)
                    rim_col = lerp_rgb(cyan, magenta, nx)
                    r += rim_col[0] * rim_t * 0.28
                    g += rim_col[1] * rim_t * 0.28
                    b += rim_col[2] * rim_t * 0.28
            else:
                r, g, b = 0.0, 0.0, 0.0
                bg_alpha = 0.0

            fg_alpha = 0.0

            # 2. Synchronized neon light wave arcing over all 3 roofs
            if 0.08 <= nx <= 0.92:
                u_wave = (nx - 0.08) / 0.84
                arch = math.sin(u_wave * math.pi)
                ripple = math.sin(u_wave * math.pi * 3.0 - 0.45) * 0.024
                wy = 0.41 - 0.21 * arch + ripple
                d_wave = abs(ny - wy)

                if u_wave < 0.45:
                    wcol = lerp_rgb(cyan, violet, u_wave / 0.45)
                elif u_wave < 0.58:
                    wcol = lerp_rgb(violet, gold, (u_wave - 0.45) / 0.13)
                else:
                    wcol = lerp_rgb(gold, magenta, (u_wave - 0.58) / 0.42)

                # Soft wave bloom + bright core
                if d_wave < 0.075:
                    bloom = math.exp(-((d_wave / 0.026) ** 2)) * 0.72
                    core = max(0.0, 1.0 - d_wave / (0.0085 + aa))
                    core_col = lerp_rgb(wcol, white, 0.45 * core)
                    contrib = min(1.0, bloom + core * 0.9)
                    r += core_col[0] * contrib
                    g += core_col[1] * contrib
                    b += core_col[2] * contrib
                    fg_alpha = max(fg_alpha, contrib)

            # 3. Street baseline
            if 0.08 <= nx <= 0.92:
                d_street = abs(ny - ground_y)
                if d_street < 0.022:
                    st_glow = math.exp(-((d_street / 0.008) ** 2)) * 0.45
                    st_col = lerp_rgb(cyan, magenta, (nx - 0.08) / 0.84)
                    r += st_col[0] * st_glow
                    g += st_col[1] * st_glow
                    b += st_col[2] * st_glow
                    fg_alpha = max(fg_alpha, st_glow)

            # 4. House bodies, glowing windows, and pitched rooflines
            for h in houses:
                x0 = float(h["x0"])
                x1 = float(h["x1"])
                cx = 0.5 * (x0 + x1)
                w = x1 - x0
                ey = float(h["eave_y"])
                py_peak = float(h["peak_y"])
                c1 = h["c1"]  # type: ignore[assignment]
                c2 = h["c2"]  # type: ignore[assignment]
                win_c = h["win"]  # type: ignore[assignment]
                is_mid = bool(h["is_mid"])

                # House body interior
                body_l = x0 + w * 0.12
                body_r = x1 - w * 0.12
                if body_l <= nx <= body_r and ny <= ground_y:
                    roof_t_at_x = 1.0 - abs(nx - cx) / (0.5 * w)
                    roof_y_at_x = ey - max(0.0, roof_t_at_x) * (ey - py_peak)
                    if ny >= roof_y_at_x:
                        # Dark architectural silhouette with subtle under-eave neon wash
                        eave_wash = max(0.0, 1.0 - (ny - roof_y_at_x) / 0.22) * 0.25
                        base_body = (16.0, 26.0, 52.0) if is_mid else (11.0, 18.0, 38.0)
                        body_rgb = lerp_rgb(base_body, c1, eave_wash)
                        r = body_rgb[0]
                        g = body_rgb[1]
                        b = body_rgb[2]
                        fg_alpha = max(fg_alpha, 0.95)

                        # Side wall borders
                        wall_d = min(abs(nx - body_l), abs(nx - body_r))
                        if wall_d < 0.008:
                            wt = max(0.0, 1.0 - wall_d / 0.008) * 0.55
                            r, g, b = lerp_rgb((r, g, b), c1, wt)

                        # Warm glowing windows
                        win_y0 = ey + (ground_y - ey) * 0.24
                        win_y1 = ey + (ground_y - ey) * 0.62
                        bw = body_r - body_l
                        in_win_x = (
                            (body_l + bw * 0.16 <= nx <= body_l + bw * 0.39)
                            or (body_r - bw * 0.39 <= nx <= body_r - bw * 0.16)
                        )
                        if in_win_x and (win_y0 <= ny <= win_y1):
                            wcol = lerp_rgb(win_c, white, 0.35)
                            r, g, b = lerp_rgb((r, g, b), wcol, 0.88)

                # Pitched roof left slope & right slope
                d_left, t_left = dist_to_segment(nx, ny, x0, ey, cx, py_peak)
                d_right, t_right = dist_to_segment(nx, ny, cx, py_peak, x1, ey)
                if d_left <= d_right:
                    d_roof = d_left
                    roof_prog = t_left
                else:
                    d_roof = d_right
                    roof_prog = 1.0 - t_right

                if d_roof < 0.085:
                    rcol = lerp_rgb(c1, c2, roof_prog)
                    bloom_w = 0.030 if is_mid else 0.025
                    core_w = 0.0115 if is_mid else 0.0095
                    bloom = math.exp(-((d_roof / bloom_w) ** 2)) * (0.95 if is_mid else 0.82)
                    core = max(0.0, 1.0 - max(0.0, d_roof - core_w * 0.45) / (core_w * 0.65 + aa))
                    core_rgb = lerp_rgb(rcol, white, 0.55 * core)
                    strength = min(1.0, bloom + core)
                    r += core_rgb[0] * strength
                    g += core_rgb[1] * strength
                    b += core_rgb[2] * strength
                    fg_alpha = max(fg_alpha, strength)

            # 5. Individual Govee LED nodes along the 3 roofs
            for lx, ly, lcol, lrad in leds:
                d_led = math.hypot(nx - lx, ny - ly)
                if d_led < lrad * 2.4:
                    puck = max(0.0, 1.0 - d_led / (lrad + aa))
                    halo = math.exp(-((d_led / (lrad * 1.4)) ** 2)) * 0.65
                    pcol = lerp_rgb(lcol, white, 0.72 * puck)
                    amt = min(1.0, halo + puck)
                    r += pcol[0] * amt * 0.75
                    g += pcol[1] * amt * 0.75
                    b += pcol[2] * amt * 0.75
                    fg_alpha = max(fg_alpha, amt)

            out_a = bg_alpha if include_background else fg_alpha
            if out_a <= 0.0:
                continue

            idx = (py_i * size + px_i) * 4
            buf[idx] = max(0, min(255, int(round(r))))
            buf[idx + 1] = max(0, min(255, int(round(g))))
            buf[idx + 2] = max(0, min(255, int(round(b))))
            buf[idx + 3] = max(0, min(255, int(round(out_a * 255.0))))

    return buf


def downsample_2x(buf: bytearray, src_size: int) -> bytearray:
    """2x2 box-filter supersampling downsample for ultra-crisp edges."""
    dst_size = src_size // 2
    out = bytearray(dst_size * dst_size * 4)
    for y in range(dst_size):
        for x in range(dst_size):
            r_sum = g_sum = b_sum = a_sum = 0
            for dy in (0, 1):
                for dx in (0, 1):
                    s_idx = ((y * 2 + dy) * src_size + (x * 2 + dx)) * 4
                    r_sum += buf[s_idx]
                    g_sum += buf[s_idx + 1]
                    b_sum += buf[s_idx + 2]
                    a_sum += buf[s_idx + 3]
            d_idx = (y * dst_size + x) * 4
            out[d_idx] = r_sum >> 2
            out[d_idx + 1] = g_sum >> 2
            out[d_idx + 2] = b_sum >> 2
            out[d_idx + 3] = a_sum >> 2
    return out


def main() -> None:
    res_dir = Path("/mnt/media/govee_lights_sync/mobile/android/app/src/main/res")

    targets = {
        "mipmap-mdpi/ic_launcher.png": 48,
        "mipmap-hdpi/ic_launcher.png": 72,
        "mipmap-xhdpi/ic_launcher.png": 96,
        "mipmap-xxhdpi/ic_launcher.png": 144,
        "mipmap-xxxhdpi/ic_launcher.png": 192,
    }

    for rel_path, px in targets.items():
        dest = res_dir / rel_path
        # Render at 2x resolution and downsample 2x for 4x SSAA anti-aliasing
        hi_buf = render_icon_rgba(px * 2, include_background=True)
        aa_buf = downsample_2x(hi_buf, px * 2)
        write_png_rgba(dest, px, px, aa_buf)
        print(f"Generated {dest} ({px}x{px}, {dest.stat().st_size} bytes)")

    fg_dest = res_dir / "drawable/ic_launcher_foreground.png"
    fg_px = 432
    fg_buf = render_icon_rgba(fg_px, include_background=False)
    write_png_rgba(fg_dest, fg_px, fg_px, fg_buf)
    print(f"Generated {fg_dest} ({fg_px}x{fg_px}, {fg_dest.stat().st_size} bytes)")


if __name__ == "__main__":
    main()

