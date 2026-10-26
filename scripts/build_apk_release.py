#!/usr/bin/env python3
"""
Automated Android APK Release Builder & Version Archive Manager.

Usage examples:
  python3 scripts/build_apk_release.py --version 3.1.0 --build-number 4 --notes "Added OTA update checker;Added version archive"
  python3 scripts/build_apk_release.py --bump minor --notes "New holiday lighting effects"
  python3 scripts/build_apk_release.py --bump patch --notes "Bug fixes and performance improvements"
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]
PUBSPEC_PATH = REPO_ROOT / "mobile" / "pubspec.yaml"
GRADLE_PATH = REPO_ROOT / "mobile" / "android" / "app" / "build.gradle.kts"
MODELS_DART_PATH = REPO_ROOT / "mobile" / "lib" / "models" / "govee_models.dart"
DATA_DIR = REPO_ROOT / "data"
RELEASES_DIR = DATA_DIR / "releases"
MANIFEST_PATH = DATA_DIR / "apk_releases.json"
LATEST_APK_PATH = DATA_DIR / "govee-multi-house-sync.apk"
BUILT_APK_PATH = (
    REPO_ROOT
    / "mobile"
    / "build"
    / "app"
    / "outputs"
    / "flutter-apk"
    / "app-release.apk"
)


def _parse_dotenv(env_file: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not env_file.exists():
        return values
    for raw_line in env_file.read_text(encoding="utf-8", errors="ignore").splitlines():
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
        if k and v:
            values[k] = v
    return values


def _load_manifest() -> List[Dict[str, Any]]:
    if not MANIFEST_PATH.exists():
        return []
    try:
        raw = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        if isinstance(raw, dict) and isinstance(raw.get("releases"), list):
            return list(raw["releases"])
        if isinstance(raw, list):
            return list(raw)
    except Exception:
        pass
    return []


def _current_version() -> Tuple[str, int]:
    releases = _load_manifest()
    if releases:
        top = max(releases, key=lambda r: int(r.get("version_code") or 0))
        return str(top.get("version_name") or "3.0.0"), int(top.get("version_code") or 3)

    if GRADLE_PATH.exists():
        txt = GRADLE_PATH.read_text(encoding="utf-8")
        m_code = re.search(r"versionCode\s*=\s*(\d+)", txt)
        m_name = re.search(r'versionName\s*=\s*"([^"]+)"', txt)
        if m_code and m_name:
            return m_name.group(1), int(m_code.group(1))
    return "3.0.0", 3


def _bump_semver(ver: str, bump: str) -> str:
    parts = [int(p) if p.isdigit() else 0 for p in (ver.split(".") + ["0", "0"])[:3]]
    major, minor, patch = parts[0], parts[1], parts[2]
    if bump == "major":
        return f"{major + 1}.0.0"
    if bump == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def _parse_notes(raw_notes: List[str]) -> List[str]:
    notes: List[str] = []
    for item in raw_notes:
        for part in re.split(r"[;\n]+", item):
            clean = part.strip()
            if clean:
                notes.append(clean)
    return notes


def _update_version_files(version_name: str, version_code: int) -> None:
    if PUBSPEC_PATH.exists():
        txt = PUBSPEC_PATH.read_text(encoding="utf-8")
        txt = re.sub(
            r"(?m)^version:\s*[^\s]+\s*$",
            f"version: {version_name}+{version_code}",
            txt,
        )
        PUBSPEC_PATH.write_text(txt, encoding="utf-8")

    if GRADLE_PATH.exists():
        txt = GRADLE_PATH.read_text(encoding="utf-8")
        txt = re.sub(r"versionCode\s*=\s*\d+", f"versionCode = {version_code}", txt)
        txt = re.sub(
            r'versionName\s*=\s*"[^"]+"',
            f'versionName = "{version_name}"',
            txt,
        )
        GRADLE_PATH.write_text(txt, encoding="utf-8")

    if MODELS_DART_PATH.exists():
        txt = MODELS_DART_PATH.read_text(encoding="utf-8")
        if "kAppVersionName" in txt:
            txt = re.sub(
                r"const\s+String\s+kAppVersionName\s*=\s*'[^']*';",
                f"const String kAppVersionName = '{version_name}';",
                txt,
            )
            txt = re.sub(
                r"const\s+int\s+kAppVersionCode\s*=\s*\d+;",
                f"const int kAppVersionCode = {version_code};",
                txt,
            )
        else:
            anchor = "import 'package:flutter/material.dart';\n"
            ver_block = (
                f"\nconst String kAppVersionName = '{version_name}';\n"
                f"const int kAppVersionCode = {version_code};\n"
            )
            if anchor in txt:
                txt = txt.replace(anchor, anchor + ver_block, 1)
            else:
                txt = ver_block + txt
        MODELS_DART_PATH.write_text(txt, encoding="utf-8")


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description="Build & Archive a Versioned Govee Sync Studio APK")
    parser.add_argument("--version", help="Explicit version name (e.g. 3.1.0)")
    parser.add_argument("--build-number", type=int, help="Explicit Android versionCode integer (e.g. 4)")
    parser.add_argument(
        "--bump",
        choices=["patch", "minor", "major"],
        default="patch",
        help="Bump semantic version when --version is not specified (default: patch)",
    )
    parser.add_argument(
        "--notes",
        action="append",
        default=[],
        help="Release changelog notes (repeatable or semicolon-separated)",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Only update version metadata and register existing built APK",
    )
    args = parser.parse_args()

    cur_name, cur_code = _current_version()
    version_name = (args.version or _bump_semver(cur_name, args.bump)).strip().lstrip("v")
    version_code = int(args.build_number) if args.build_number is not None else (cur_code + 1)
    changelog = _parse_notes(args.notes) or [f"Govee Sync Studio v{version_name} (Build {version_code})"]

    print(f"[apk-release] Updating source metadata to v{version_name} (Build {version_code})...")
    _update_version_files(version_name, version_code)

    if not args.skip_build:
        env_vals = _parse_dotenv(REPO_ROOT / ".env")
        dart_defines: List[str] = [
            f"--build-name={version_name}",
            f"--build-number={version_code}",
        ]
        pub_url = env_vals.get("PUBLIC_BASE_URL", "").strip().rstrip("/")
        owner_email = env_vals.get("OWNER_EMAIL", "").strip()
        if pub_url:
            dart_defines.append(f"--dart-define=DEFAULT_BACKEND_URL={pub_url}")
        if owner_email:
            dart_defines.append(f"--dart-define=OWNER_EMAIL={owner_email}")

        flutter_cmd = (
            "/sdks/flutter/bin/flutter pub get && "
            "/sdks/flutter/bin/flutter test && "
            "/sdks/flutter/bin/flutter build apk --release "
            + " ".join(f'"{d}"' for d in dart_defines)
        )
        docker_cmd = [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{REPO_ROOT / 'mobile'}:/app",
            "-w",
            "/app",
            "samebadge-flutter:3.41.9",
            "bash",
            "-lc",
            flutter_cmd,
        ]
        print(f"[apk-release] Compiling signed release APK v{version_name} (b{version_code}) in samebadge-flutter:3.41.9...")
        res = subprocess.run(docker_cmd, cwd=REPO_ROOT, check=False)
        if res.returncode != 0:
            print("[apk-release] ERROR: Flutter APK build failed.", file=sys.stderr)
            return res.returncode

    src_apk = BUILT_APK_PATH if BUILT_APK_PATH.exists() else LATEST_APK_PATH
    if not src_apk.exists():
        print(f"[apk-release] ERROR: Built APK not found at {src_apk}", file=sys.stderr)
        return 1

    RELEASES_DIR.mkdir(parents=True, exist_ok=True)
    archive_filename = f"Govee-Sync-Studio-v{version_name}-b{version_code}.apk"
    archive_path = RELEASES_DIR / archive_filename

    shutil.copy2(src_apk, archive_path)
    shutil.copy2(src_apk, LATEST_APK_PATH)

    st = archive_path.stat()
    sha256_hex = _sha256_file(archive_path)
    released_at = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    entry: Dict[str, Any] = {
        "version_name": version_name,
        "version_code": version_code,
        "filename": archive_filename,
        "size_bytes": st.st_size,
        "sha256": sha256_hex,
        "released_at": released_at,
        "changelog": changelog,
    }

    releases = [
        r
        for r in _load_manifest()
        if str(r.get("version_name")) != version_name
        and int(r.get("version_code") or 0) != version_code
    ]
    releases.append(entry)
    releases.sort(key=lambda r: int(r.get("version_code") or 0), reverse=True)

    MANIFEST_PATH.write_text(
        json.dumps({"releases": releases}, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"[apk-release] Archived {archive_filename} "
        f"({st.st_size / (1024 * 1024):.1f} MB, sha256={sha256_hex[:16]}...)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
