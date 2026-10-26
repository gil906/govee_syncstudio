#!/usr/bin/env python3
"""
Automatic Git Redaction Filter & Pre-Commit / Pre-Push Secret Guard.

Loads local secrets and personal identifiers dynamically from unversioned runtime files
(`.env`, `data/config.json`, `mobile/android/key.properties`) and applies generic secret/LAN
patterns so tracked files in git never contain API keys, OAuth secrets, emails, domains,
controller MACs, or local subnet IPs.

Modes:
  --clean          Filter stdin -> stdout (used by git clean filter `govee-redact`)
  --redact-staged  Redact any staged text files in place and re-stage them
  --verify         Scan all git-tracked & staged files and fail (exit 1) on any leak
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.parse
from pathlib import Path
from typing import Dict, List, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]

SECRET_ENV_KEYS = {
    "AUTH_SECRET_KEY",
    "JWT_SECRET",
    "SESSION_SECRET",
    "SECRET_KEY",
    "GOOGLE_CLIENT_ID",
    "GOOGLE_CLIENT_SECRET",
    "GOOGLE_GSI_CLIENT_ID",
    "GOOGLE_DEVPOST_CLIENT_ID",
    "GOOGLE_DEVPOST_CLIENT_SECRET",
    "GITHUB_CLIENT_ID",
    "GITHUB_CLIENT_SECRET",
    "GOVEE_API_KEY",
    "DASH_PASS",
    "DASH_USER",
}

FORBIDDEN_PATH_PATTERNS = [
    re.compile(r"(^|/)\.env(\..+)?$"),
    re.compile(r"^data/(?!\.gitkeep$).+"),
    re.compile(r"\.apk$", re.IGNORECASE),
    re.compile(r"\.jks$", re.IGNORECASE),
    re.compile(r"\.keystore$", re.IGNORECASE),
    re.compile(r"(^|/)key\.properties$"),
    re.compile(r"(^|/)local\.properties$"),
]

GENERIC_REGEX_RULES: List[Tuple[str, re.Pattern[str], str]] = [
    (
        "google_oauth_client_secret",
        re.compile(r"GOCSPX-[A-Za-z0-9_-]{10,}"),
        "<REDACTED_GOOGLE_CLIENT_SECRET>",
    ),
    (
        "google_oauth_client_id",
        re.compile(r"\b[0-9]{10,}-[A-Za-z0-9_]{15,}\.apps\.googleusercontent\.com\b"),
        "<REDACTED_GOOGLE_CLIENT_ID>",
    ),
    (
        "github_pat_token",
        re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b|\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
        "<REDACTED_GITHUB_TOKEN>",
    ),
    (
        "google_api_key",
        re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
        "<REDACTED_GOOGLE_API_KEY>",
    ),
    (
        "private_lan_subnet",
        re.compile(r"\b192\.168\.6[89]\.(\d{1,3})\b"),
        r"192.168.1.\1",
    ),
]


def _parse_dotenv(env_file: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not env_file.exists():
        return values
    try:
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
    except Exception:
        pass
    return values


def _root_domain(hostname: str) -> str:
    parts = [p for p in hostname.strip().lower().split(".") if p]
    if len(parts) >= 2:
        return ".".join(parts[-2:])
    return hostname.strip().lower()


def build_dynamic_replacements() -> List[Tuple[str, str, str]]:
    """
    Return ordered list of (label, raw_sensitive_value, safe_replacement) tuples
    derived dynamically from local `.env`, `data/config.json`, and `key.properties`.
    """
    rules: List[Tuple[str, str, str]] = []
    env_vals = _parse_dotenv(REPO_ROOT / ".env")

    # 1. Secret keys in .env
    for key in sorted(SECRET_ENV_KEYS):
        val = env_vals.get(key, "").strip()
        if len(val) >= 6:
            rules.append((f"env:{key}", val, "<REDACTED_SECRET>"))

    # 2. Owner email & GitHub username in .env
    owner_email = env_vals.get("OWNER_EMAIL", "").strip()
    if owner_email and owner_email.lower() != "owner@example.com":
        rules.append(("env:OWNER_EMAIL", owner_email, "owner@example.com"))
        rules.append(("env:OWNER_EMAIL_LOWER", owner_email.lower(), "owner@example.com"))
        local_part = owner_email.split("@", 1)[0].strip()
        if len(local_part) >= 5:
            rules.append(("env:OWNER_EMAIL_USER", local_part, "owner"))

    owner_gh = env_vals.get("OWNER_GITHUB_USER", "").strip()
    if owner_gh and owner_gh.lower() not in ("owner-github", "owner_github"):
        rules.append(("env:OWNER_GITHUB_USER", owner_gh, "owner-github"))
        rules.append(("env:OWNER_GITHUB_USER_LOWER", owner_gh.lower(), "owner-github"))

    # 3. Public base URL & OAuth bridge domain in .env
    pub_url = env_vals.get("PUBLIC_BASE_URL", "").strip().rstrip("/")
    if pub_url and "example.com" not in pub_url and "localhost" not in pub_url:
        rules.append(("env:PUBLIC_BASE_URL", pub_url, "https://govee-sync.example.com"))
        parsed_pub = urllib.parse.urlparse(pub_url)
        if parsed_pub.hostname:
            rules.append(("env:PUBLIC_HOST", parsed_pub.hostname, "govee-sync.example.com"))
            rdom = _root_domain(parsed_pub.hostname)
            if rdom and rdom != "example.com":
                rules.append(("env:PUBLIC_ROOT_DOMAIN", rdom, "example.com"))

    bridge_url = env_vals.get("OAUTH_BRIDGE_BASE", "").strip().rstrip("/")
    if bridge_url and "example.com" not in bridge_url and "localhost" not in bridge_url:
        rules.append(("env:OAUTH_BRIDGE_BASE", bridge_url, "https://auth-bridge.example.com"))
        parsed_br = urllib.parse.urlparse(bridge_url)
        if parsed_br.hostname:
            rules.append(("env:OAUTH_BRIDGE_HOST", parsed_br.hostname, "auth-bridge.example.com"))
            rdom = _root_domain(parsed_br.hostname)
            if rdom and rdom != "example.com":
                rules.append(("env:OAUTH_BRIDGE_ROOT_DOMAIN", rdom, "example.com"))

    # 4. Runtime data/config.json secrets, controller MACs, IPs, and emails
    cfg_path = REPO_ROOT / "data" / "config.json"
    if cfg_path.exists():
        try:
            cfg = json.loads(cfg_path.read_text(encoding="utf-8", errors="ignore"))
            if isinstance(cfg, dict):
                top_key = str(cfg.get("govee_api_key") or "").strip()
                if len(top_key) >= 6:
                    rules.append(("config:govee_api_key", top_key, ""))

                for em in cfg.get("authorized_emails") or []:
                    if isinstance(em, str) and "@" in em and not em.lower().endswith("@example.com"):
                        replacement = (
                            "owner@example.com"
                            if owner_email and em.strip().lower() == owner_email.lower()
                            else "neighbor@example.com"
                        )
                        rules.append(("config:authorized_email", em.strip(), replacement))

                for house in cfg.get("houses") or []:
                    if not isinstance(house, dict):
                        continue
                    h_key = str(house.get("govee_api_key") or "").strip()
                    if len(h_key) >= 6:
                        rules.append(("config:house_govee_api_key", h_key, ""))
                    b_tok = str(house.get("bridge_token") or "").strip()
                    if len(b_tok) >= 6:
                        rules.append(("config:house_bridge_token", b_tok, ""))
                    for ctrl in house.get("controllers") or []:
                        if not isinstance(ctrl, dict):
                            continue
                        mac = str(ctrl.get("mac") or "").strip()
                        if mac and not mac.upper().startswith("AA:BB:CC:DD:EE"):
                            rules.append(("config:controller_mac", mac, "AA:BB:CC:DD:EE:FF:00:02"))
                            rules.append(("config:controller_mac_upper", mac.upper(), "AA:BB:CC:DD:EE:FF:00:02"))
                        ip = str(ctrl.get("ip") or "").strip()
                        if ip and not ip.startswith("192.168.1.") and ip not in ("127.0.0.1", "localhost"):
                            rules.append(("config:controller_ip", ip, "192.168.1.83"))
        except Exception:
            pass

    # 5. Android key.properties signing passwords
    key_props = _parse_dotenv(REPO_ROOT / "mobile" / "android" / "key.properties")
    for k in ("storePassword", "keyPassword"):
        v = key_props.get(k, "").strip()
        if len(v) >= 6:
            rules.append((f"key.properties:{k}", v, "<REDACTED_KEYSTORE_SECRET>"))

    # Sort longest-first so full URLs/emails are replaced before substrings
    deduped: Dict[str, Tuple[str, str, str]] = {}
    for label, needle, repl in rules:
        if needle and needle not in deduped:
            deduped[needle] = (label, needle, repl)
    return sorted(deduped.values(), key=lambda item: len(item[1]), reverse=True)


def redact_text(content: str) -> str:
    out = content
    for _label, needle, repl in build_dynamic_replacements():
        if needle in out:
            out = out.replace(needle, repl)
    for _label, pattern, repl in GENERIC_REGEX_RULES:
        out = pattern.sub(repl, out)
    return out


def is_forbidden_path(rel_path: str) -> bool:
    norm = rel_path.replace("\\", "/").lstrip("./")
    if norm == ".env.example":
        return False
    return any(p.search(norm) for p in FORBIDDEN_PATH_PATTERNS)


def get_git_files(staged_only: bool = False) -> List[str]:
    try:
        if staged_only:
            cmd = ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"]
        else:
            cmd = ["git", "ls-files"]
        res = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True, check=False)
        if res.returncode != 0:
            return []
        return [line.strip() for line in res.stdout.splitlines() if line.strip()]
    except Exception:
        return []


def run_redact_staged() -> int:
    staged = get_git_files(staged_only=True)
    redacted_count = 0
    for rel in staged:
        if rel == "scripts/git_redact_filter.py":
            continue
        fpath = REPO_ROOT / rel
        if not fpath.is_file():
            continue
        try:
            raw = fpath.read_bytes()
            if b"\x00" in raw[:4096]:
                continue  # skip binary files
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue

        cleaned = redact_text(text)
        if cleaned != text:
            fpath.write_text(cleaned, encoding="utf-8")
            subprocess.run(["git", "add", "--", rel], cwd=REPO_ROOT, check=False)
            redacted_count += 1
            print(f"[govee-redact] Auto-redacted sensitive data in staged file: {rel}", file=sys.stderr)
    return 0


def run_verify() -> int:
    tracked = set(get_git_files(staged_only=False)) | set(get_git_files(staged_only=True))
    violations: List[str] = []

    for rel in sorted(tracked):
        if is_forbidden_path(rel):
            violations.append(f"Forbidden sensitive/artifact file tracked or staged: {rel}")
            continue
        if rel == "scripts/git_redact_filter.py":
            continue
        fpath = REPO_ROOT / rel
        if not fpath.is_file():
            continue
        try:
            raw = fpath.read_bytes()
            if b"\x00" in raw[:4096]:
                continue
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue

        for label, needle, _repl in build_dynamic_replacements():
            if needle in text:
                violations.append(f"{rel}: matched dynamic redaction rule [{label}]")
        for label, pattern, _repl in GENERIC_REGEX_RULES:
            if pattern.search(text):
                violations.append(f"{rel}: matched pattern rule [{label}]")

    if violations:
        print("[govee-redact] VERIFICATION FAILED — sensitive data or forbidden files detected:", file=sys.stderr)
        for v in violations:
            print(f"  - {v}", file=sys.stderr)
        return 1

    print(f"[govee-redact] Verification passed ({len(tracked)} tracked/staged files scanned, 0 leaks).")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Govee Sync Git Redaction Filter & Secret Verifier")
    parser.add_argument("--clean", action="store_true", help="Read stdin and write redacted output to stdout")
    parser.add_argument("--redact-staged", action="store_true", help="Auto-redact staged files in place")
    parser.add_argument("--verify", action="store_true", help="Verify tracked/staged files have zero leaks")
    args = parser.parse_args()

    if args.clean:
        raw = sys.stdin.buffer.read()
        if b"\x00" in raw[:4096]:
            sys.stdout.buffer.write(raw)
            return 0
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            sys.stdout.buffer.write(raw)
            return 0
        sys.stdout.write(redact_text(text))
        return 0

    if args.redact_staged:
        return run_redact_staged()

    if args.verify:
        return run_verify()

    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
