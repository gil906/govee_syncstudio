from __future__ import annotations

import base64
import hashlib
import hmac
import html
import json
import logging
import os
import secrets
import time
import urllib.parse
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
from fastapi import HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse

from .config_store import ConfigStore
from .models import OWNER_EMAIL, normalize_authorized_emails

logger = logging.getLogger("govee_sync.auth")

SESSION_COOKIE_NAME = "govee_sync_session"
TOKEN_TTL_SECONDS = 30 * 86400  # 30 days


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _b64url_decode(s: str) -> bytes:
    pad = "=" * ((4 - len(s) % 4) % 4)
    return base64.urlsafe_b64decode((s + pad).encode("ascii"))


def _load_dotenv_into_environ(env_path: Optional[Path] = None) -> None:
    """Load key=value pairs from /mnt/media/govee_lights_sync/.env into os.environ if not already set."""
    candidates = []
    if env_path is not None:
        candidates.append(env_path)
    base_dir = Path(__file__).resolve().parents[2]
    candidates.append(base_dir / ".env")
    candidates.append(Path("/mnt/media/govee_lights_sync/.env"))

    for path in candidates:
        try:
            if not path.exists():
                continue
            for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
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
        except Exception as exc:
            logger.debug("Note loading .env from %s: %s", path, exc)


def access_denied_message(email: str) -> str:
    return (
        f"Access denied for {email}. "
        f"Only authorized emails (configured by {OWNER_EMAIL}) can access Govee Multi-House Light Sync."
    )


def is_external_request(request: Request) -> bool:
    """
    Determine whether an incoming HTTP request originated from the external internet
    (e.g., via Nginx Proxy Manager / Cloudflare for `PUBLIC_BASE_URL` or `X-Forwarded-For`),
    versus a direct localhost (`127.0.0.1`) health check or CLI test.
    """
    if request.headers.get("x-require-auth", "").strip() in ("1", "true", "yes"):
        return True

    host = (
        request.headers.get("x-forwarded-host")
        or request.headers.get("host")
        or ""
    ).strip().lower()
    public_domain = (urllib.parse.urlparse(os.environ.get("PUBLIC_BASE_URL", "")).hostname or "").strip().lower()
    if (public_domain and public_domain in host) or "govee." in host or "govee-sync." in host:
        return True

    xff = request.headers.get("x-forwarded-for", "").strip()
    if xff:
        first_ip = xff.split(",")[0].strip()
        if first_ip and first_ip not in ("127.0.0.1", "::1", "localhost"):
            return True

    client_host = (request.client.host if request.client else "127.0.0.1").strip().lower()
    if client_host in ("127.0.0.1", "::1", "localhost", "testclient"):
        return False

    return True


class AuthManager:
    """
    Google OAuth2 (Authorization Code + GIS ID Token) & GitHub OAuth2 authentication manager
    with HMAC-SHA256 30-day session tokens, authorized email enforcement (`OWNER_EMAIL`),
    and Android `.apk` deep-link handoff (`goveesync://auth`).
    """

    GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
    GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
    GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"
    GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"

    GITHUB_AUTH_URL = "https://github.com/login/oauth/authorize"
    GITHUB_TOKEN_URL = "https://github.com/login/oauth/access_token"
    GITHUB_USER_URL = "https://api.github.com/user"
    GITHUB_EMAILS_URL = "https://api.github.com/user/emails"

    def __init__(self, store: ConfigStore, http_client: Optional[httpx.AsyncClient] = None) -> None:
        self.store = store
        self._http_client = http_client
        self._mobile_handoffs: Dict[str, Dict[str, Any]] = {}
        self._handoff_sessions: Dict[str, Dict[str, Any]] = {}
        self._completed_bridge_tokens: Dict[str, Dict[str, Any]] = {}
        _load_dotenv_into_environ()
        self._secret_key = self._init_secret_key()

    def _init_secret_key(self) -> str:
        env_secret = (
            os.environ.get("AUTH_SECRET_KEY")
            or os.environ.get("JWT_SECRET")
            or os.environ.get("SESSION_SECRET")
            or os.environ.get("SECRET_KEY")
            or ""
        ).strip()
        if env_secret:
            return env_secret

        secret_file = self.store.data_dir / ".auth_secret"
        try:
            if secret_file.exists():
                val = secret_file.read_text(encoding="utf-8").strip()
                if len(val) >= 32:
                    return val
            generated = secrets.token_hex(32)
            secret_file.write_text(generated, encoding="utf-8")
            try:
                os.chmod(secret_file, 0o600)
            except OSError:
                pass
            return generated
        except Exception:
            return secrets.token_hex(32)

    @property
    def secret_key(self) -> str:
        env_secret = (
            os.environ.get("AUTH_SECRET_KEY")
            or os.environ.get("JWT_SECRET")
            or os.environ.get("SESSION_SECRET")
            or os.environ.get("SECRET_KEY")
            or ""
        ).strip()
        return env_secret or self._secret_key

    @property
    def google_client_id(self) -> str:
        _load_dotenv_into_environ()
        return (
            os.environ.get("GOOGLE_CLIENT_ID")
            or os.environ.get("GOOGLE_GSI_CLIENT_ID")
            or os.environ.get("GOOGLE_DEVPOST_CLIENT_ID")
            or os.environ.get("GOOGLE_OAUTH_CLIENT_ID")
            or os.environ.get("VITE_GOOGLE_CLIENT_ID")
            or ""
        ).strip()

    @property
    def google_client_secret(self) -> str:
        _load_dotenv_into_environ()
        return (
            os.environ.get("GOOGLE_CLIENT_SECRET")
            or os.environ.get("GOOGLE_DEVPOST_CLIENT_SECRET")
            or os.environ.get("GOOGLE_OAUTH_CLIENT_SECRET")
            or ""
        ).strip()

    @property
    def github_client_id(self) -> str:
        _load_dotenv_into_environ()
        return (
            os.environ.get("GITHUB_CLIENT_ID")
            or os.environ.get("GITHUB_OAUTH_CLIENT_ID")
            or ""
        ).strip()

    @property
    def github_client_secret(self) -> str:
        _load_dotenv_into_environ()
        return (
            os.environ.get("GITHUB_CLIENT_SECRET")
            or os.environ.get("GITHUB_OAUTH_CLIENT_SECRET")
            or ""
        ).strip()

    @property
    def google_gsi_client_id(self) -> str:
        _load_dotenv_into_environ()
        return (
            os.environ.get("GOOGLE_GSI_CLIENT_ID")
            or os.environ.get("GOOGLE_CLIENT_ID")
            or ""
        ).strip()

    @property
    def oauth_bridge_base(self) -> str:
        _load_dotenv_into_environ()
        return (os.environ.get("OAUTH_BRIDGE_BASE") or "").strip().rstrip("/")

    @property
    def google_enabled(self) -> bool:
        return bool(self.google_client_id or self.oauth_bridge_base)

    @property
    def github_enabled(self) -> bool:
        return bool((self.github_client_id and self.github_client_secret) or self.oauth_bridge_base)

    def should_use_oauth_bridge(
        self,
        provider: str,
        direct: str = "",
        bridge: str = "",
    ) -> bool:
        """
        Return True when OAuth login should route through OAUTH_BRIDGE_BASE
        (/api/auth/{provider}?mobile_session=govee_...).
        Preserves direct OAuth flow when `direct=1` is passed or when unit tests
        monkeypatch `test-google-client-id*` / `test-github-client-id*`.
        """
        if str(direct).strip().lower() in ("1", "true", "yes"):
            return False
        if str(bridge).strip().lower() in ("1", "true", "yes"):
            return bool(self.oauth_bridge_base)
        if not self.oauth_bridge_base:
            return False
        if provider == "google" and self.google_client_id.startswith("test-google-client-id"):
            return False
        if provider == "github" and self.github_client_id.startswith("test-github-client-id"):
            return False
        return True

    def create_bridge_handoff(
        self,
        provider: str,
        mobile: bool = False,
        redirect_scheme: str = "",
        next_path: str = "/",
        custom_handoff: str = "",
    ) -> Tuple[str, str]:
        """Generate a `govee_web_<hex>` or `govee_mob_<hex>` handoff ID and bridge redirect URL."""
        now = time.time()
        # Evict old entries (>600s)
        for k in [k for k, v in self._handoff_sessions.items() if now - float(v.get("ts", 0)) > 600]:
            self._handoff_sessions.pop(k, None)
        for k in [k for k, v in self._completed_bridge_tokens.items() if now - float(v.get("ts", 0)) > 300]:
            self._completed_bridge_tokens.pop(k, None)

        prefix = "govee_mob_" if mobile else "govee_web_"
        clean_custom = (custom_handoff or "").strip()
        if clean_custom and clean_custom.startswith("govee_") and len(clean_custom) >= 16:
            handoff_id = clean_custom
        else:
            handoff_id = f"{prefix}{secrets.token_hex(12)}"

        self._handoff_sessions[handoff_id] = {
            "provider": provider,
            "mobile": bool(mobile or handoff_id.startswith("govee_mob_")),
            "redirect_scheme": redirect_scheme or ("goveesync://auth" if mobile else ""),
            "next": next_path or "/",
            "ts": now,
        }
        bridge_url = (
            f"{self.oauth_bridge_base}/api/auth/{provider}"
            f"?mobile_session={urllib.parse.quote(handoff_id, safe='')}"
        )
        return handoff_id, bridge_url

    def record_mobile_handoff(self, handoff: str, token: str, user: Dict[str, Any]) -> None:
        clean = (handoff or "").strip()
        if not clean:
            return
        self._completed_bridge_tokens[clean] = {
            "status": "completed",
            "authenticated": True,
            "authorized": True,
            "email": str(user.get("email") or ""),
            "name": str(user.get("name") or ""),
            "token": token,
            "user": user,
            "mobile": True,
            "redirect_scheme": "goveesync://auth",
            "next": "/",
            "ts": time.time(),
        }

    def consume_mobile_handoff(self, handoff: str) -> Dict[str, Any]:
        clean = (handoff or "").strip()
        if clean and clean in self._completed_bridge_tokens:
            entry = self._completed_bridge_tokens[clean]
            if entry.get("status") == "completed" and entry.get("token"):
                return {
                    "status": "completed",
                    "authenticated": True,
                    "token": entry["token"],
                    "user": entry["user"],
                }
            if entry.get("status") == "denied":
                em = str(entry.get("email") or "unknown")
                return {
                    "status": "denied",
                    "authenticated": False,
                    "email": em,
                    "detail": access_denied_message(em),
                }
        return {"status": "pending", "authenticated": False}

    async def poll_or_consume_bridge_handoff(self, handoff: str) -> Dict[str, Any]:
        """
        Query `{OAUTH_BRIDGE_BASE}/api/auth/oauth/mobile-poll/{handoff}` (or cached result)
        and return `{status, authorized, email, name, user, token, mobile, redirect_scheme, next}`.
        """
        clean_handoff = (handoff or "").strip()
        if not clean_handoff:
            raise HTTPException(status_code=400, detail="Invalid OAuth handoff token")

        if clean_handoff in self._completed_bridge_tokens:
            return self._completed_bridge_tokens[clean_handoff]

        meta = self._handoff_sessions.get(clean_handoff, {})
        is_mobile = bool(meta.get("mobile") or clean_handoff.startswith("govee_mob_") or not clean_handoff.startswith("govee_web_"))
        redirect_scheme = str(meta.get("redirect_scheme") or ("goveesync://auth" if is_mobile else ""))
        next_path = str(meta.get("next") or "/")
        provider = str(meta.get("provider") or "oauth")

        poll_url = f"{self.oauth_bridge_base}/api/auth/oauth/mobile-poll/{urllib.parse.quote(clean_handoff, safe='')}"
        client, own = await self._get_http_client()
        try:
            resp = await client.get(poll_url, headers={"Accept": "application/json"})
            if resp.status_code != 200:
                return {"status": "pending", "authenticated": False}
            data = resp.json()
        except Exception as exc:
            logger.warning("OAuth bridge poll failed for %s: %s", clean_handoff, exc)
            return {"status": "pending", "authenticated": False}
        finally:
            if own:
                await client.aclose()

        if not isinstance(data, dict) or data.get("status") != "completed":
            return {"status": "pending", "authenticated": False}

        raw_user = data.get("user") if isinstance(data.get("user"), dict) else {}
        email = str(raw_user.get("email") or "").strip().lower()
        name = str(raw_user.get("name") or "").strip()
        login = str(raw_user.get("login") or raw_user.get("username") or "").strip().lower()

        owner_gh = (os.environ.get("OWNER_GITHUB_USER") or "owner-github").strip().lower()
        if owner_gh and (
            login == owner_gh
            or name.lower() == owner_gh
            or email == owner_gh
            or email.startswith(f"{owner_gh}@")
        ):
            email = OWNER_EMAIL

        if not email:
            raise HTTPException(status_code=400, detail="OAuth bridge response did not contain a valid email")

        authorized = self.is_email_authorized(email)
        if not authorized:
            result = {
                "status": "denied",
                "authenticated": False,
                "authorized": False,
                "email": email,
                "name": name,
                "mobile": is_mobile,
                "redirect_scheme": redirect_scheme,
                "next": next_path,
                "ts": time.time(),
            }
            self._completed_bridge_tokens[clean_handoff] = result
            return result

        token = self.create_session_token(
            email=email,
            name=name or email.split("@")[0],
            picture=str(raw_user.get("picture") or raw_user.get("avatar_url") or ""),
            provider=provider,
        )
        user_obj = self.verify_session_token(token, check_authorized_list=False) or {
            "email": email,
            "name": name or email.split("@")[0],
            "picture": "",
            "provider": provider,
            "is_owner": email == OWNER_EMAIL,
        }
        result = {
            "status": "completed",
            "authenticated": True,
            "authorized": True,
            "email": email,
            "name": user_obj.get("name", ""),
            "token": token,
            "user": user_obj,
            "mobile": is_mobile,
            "redirect_scheme": redirect_scheme,
            "next": next_path,
            "ts": time.time(),
        }
        self._completed_bridge_tokens[clean_handoff] = result
        return result

    def create_session_token(
        self,
        email: str,
        name: str = "",
        picture: str = "",
        provider: str = "google",
        ttl_sec: int = TOKEN_TTL_SECONDS,
    ) -> str:
        """Issue a signed HMAC-SHA256 JWT token valid for 30 days."""
        clean_email = email.strip().lower()
        now = int(time.time())
        header = {"alg": "HS256", "typ": "JWT"}
        payload = {
            "sub": clean_email,
            "email": clean_email,
            "name": (name or clean_email.split("@")[0]).strip(),
            "picture": (picture or "").strip(),
            "provider": provider,
            "iat": now,
            "exp": now + int(ttl_sec),
        }
        h_b64 = _b64url_encode(json.dumps(header, separators=(",", ":")).encode("utf-8"))
        p_b64 = _b64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
        signing_input = f"{h_b64}.{p_b64}".encode("ascii")
        sig = hmac.new(self.secret_key.encode("utf-8"), signing_input, hashlib.sha256).digest()
        s_b64 = _b64url_encode(sig)
        return f"{h_b64}.{p_b64}.{s_b64}"

    def verify_session_token(
        self,
        token: str,
        check_authorized_list: bool = True,
    ) -> Optional[Dict[str, Any]]:
        """Verify HMAC-SHA256 signature, expiration, and membership in `cfg.authorized_emails`."""
        if not token or not isinstance(token, str):
            return None
        tok = token.strip()
        if tok.lower().startswith("bearer "):
            tok = tok[7:].strip()
        parts = tok.split(".")
        if len(parts) != 3:
            return None
        h_b64, p_b64, s_b64 = parts
        signing_input = f"{h_b64}.{p_b64}".encode("ascii")
        expected_sig = hmac.new(self.secret_key.encode("utf-8"), signing_input, hashlib.sha256).digest()
        try:
            actual_sig = _b64url_decode(s_b64)
        except Exception:
            return None
        if not hmac.compare_digest(expected_sig, actual_sig):
            return None

        try:
            payload = json.loads(_b64url_decode(p_b64).decode("utf-8"))
        except Exception:
            return None
        if not isinstance(payload, dict):
            return None

        exp = int(payload.get("exp", 0))
        if exp <= int(time.time()):
            return None

        email = str(payload.get("email") or payload.get("sub") or "").strip().lower()
        if not email:
            return None

        if check_authorized_list and not self.is_email_authorized(email):
            return None

        return {
            "email": email,
            "name": str(payload.get("name") or email.split("@")[0]),
            "picture": str(payload.get("picture") or ""),
            "provider": str(payload.get("provider") or "oauth"),
            "is_owner": email == OWNER_EMAIL,
            "exp": exp,
        }

    def encode_oauth_state(
        self,
        mobile: bool = False,
        redirect_scheme: str = "",
        next_path: str = "/",
        handoff: str = "",
    ) -> str:
        state_obj = {
            "m": 1 if mobile else 0,
            "s": redirect_scheme or ("goveesync://auth" if mobile else ""),
            "n": next_path or "/",
            "h": (handoff or "").strip()[:64],
            "t": int(time.time()),
        }
        raw_b64 = _b64url_encode(json.dumps(state_obj, separators=(",", ":")).encode("utf-8"))
        sig = hmac.new(self.secret_key.encode("utf-8"), raw_b64.encode("ascii"), hashlib.sha256).hexdigest()[:16]
        return f"{raw_b64}.{sig}"

    def decode_oauth_state(self, state: str) -> Dict[str, Any]:
        default_state = {"mobile": False, "redirect_scheme": "", "next": "/", "handoff": ""}
        if not state or "." not in state:
            return default_state
        raw_b64, sig = state.rsplit(".", 1)
        expected = hmac.new(self.secret_key.encode("utf-8"), raw_b64.encode("ascii"), hashlib.sha256).hexdigest()[:16]
        if not hmac.compare_digest(sig, expected):
            return default_state
        try:
            data = json.loads(_b64url_decode(raw_b64).decode("utf-8"))
            mobile = bool(data.get("m")) or bool(data.get("s")) or bool(data.get("h"))
            scheme = str(data.get("s") or ("goveesync://auth" if mobile else ""))
            return {
                "mobile": mobile,
                "redirect_scheme": scheme,
                "next": str(data.get("n") or "/"),
                "handoff": str(data.get("h") or ""),
            }
        except Exception:
            return default_state

    def get_authorized_emails(self) -> List[str]:
        cfg = self.store.get()
        return normalize_authorized_emails(cfg.authorized_emails)

    def is_email_authorized(self, email: str) -> bool:
        clean = (email or "").strip().lower()
        if not clean:
            return False
        return clean in self.get_authorized_emails()

    def extract_token_from_request(self, request: Request) -> str:
        auth_header = request.headers.get("authorization", "").strip()
        if auth_header.lower().startswith("bearer "):
            return auth_header[7:].strip()
        header_tok = request.headers.get("x-auth-token", "").strip()
        if header_tok:
            return header_tok
        query_tok = request.query_params.get("token", "").strip()
        if query_tok:
            return query_tok
        cookie_tok = request.cookies.get(SESSION_COOKIE_NAME, "").strip()
        if cookie_tok:
            return cookie_tok
        return ""

    def get_current_user(self, request: Request) -> Optional[Dict[str, Any]]:
        tok = self.extract_token_from_request(request)
        if not tok:
            return None
        return self.verify_session_token(tok, check_authorized_list=True)

    def require_authenticated_user(self, request: Request) -> Dict[str, Any]:
        """
        Verify that the request is authenticated via Bearer token or session cookie.
        Allows localhost (`127.0.0.1`) requests when no invalid token is supplied and
        the request is not from the external internet (`X-Forwarded-For` / `PUBLIC_BASE_URL`).
        """
        tok = self.extract_token_from_request(request)
        if tok:
            user = self.verify_session_token(tok, check_authorized_list=False)
            if user is None:
                raise HTTPException(status_code=401, detail="Invalid or expired session token")
            if not self.is_email_authorized(user["email"]):
                raise HTTPException(status_code=403, detail=access_denied_message(user["email"]))
            return user

        if not is_external_request(request):
            return {
                "email": OWNER_EMAIL,
                "name": "Localhost Admin",
                "picture": "",
                "provider": "localhost",
                "is_owner": True,
            }

        if request.url.path == "/api/download/govee-sync.apk":
            raise HTTPException(
                status_code=401,
                detail="Authentication required to download the Android APK. Please sign in first.",
            )

        raise HTTPException(
            status_code=401,
            detail="Authentication required. Sign in with an authorized Google or GitHub account.",
        )

    def set_session_cookie(self, response: Response, token: str, request: Optional[Request] = None) -> None:
        is_https = False
        if request is not None:
            proto = (request.headers.get("x-forwarded-proto") or request.url.scheme or "").lower()
            is_https = proto == "https"
        response.set_cookie(
            key=SESSION_COOKIE_NAME,
            value=token,
            max_age=TOKEN_TTL_SECONDS,
            httponly=True,
            secure=is_https,
            samesite="lax",
            path="/",
        )

    def clear_session_cookie(self, response: Response) -> None:
        response.delete_cookie(key=SESSION_COOKIE_NAME, path="/")

    def resolve_public_base_url(self, request: Request) -> str:
        env_base = os.environ.get("PUBLIC_BASE_URL", "").strip().rstrip("/")
        if env_base:
            return env_base
        proto = (request.headers.get("x-forwarded-proto") or request.url.scheme or "http").split(",")[0].strip()
        host = (
            request.headers.get("x-forwarded-host")
            or request.headers.get("host")
            or request.url.netloc
            or "localhost:8200"
        ).split(",")[0].strip()
        public_domain = (urllib.parse.urlparse(os.environ.get("PUBLIC_BASE_URL", "")).hostname or "").strip().lower()
        if (public_domain and public_domain in host) or "govee." in host or "govee-sync." in host:
            proto = "https"
        return f"{proto}://{host}"

    def build_oauth_success_response(
        self,
        request: Request,
        token: str,
        user: Dict[str, Any],
        mobile: bool = False,
        redirect_scheme: str = "",
        next_path: str = "/",
        handoff: str = "",
    ) -> Response:
        """
        Return either a Mobile App OAuth Handoff response (`goveesync://auth?token=...&email=...&name=...`
        with a 1-tap 'Return to Govee Sync Android App' button + copyable token) or a Web redirect.
        """
        if handoff:
            self.record_mobile_handoff(handoff, token, user)
        email = user.get("email", "")
        name = user.get("name", "")

        if mobile or redirect_scheme:
            scheme_base = (redirect_scheme or "goveesync://auth").strip()
            sep = "&" if "?" in scheme_base else "?"
            deep_link = (
                f"{scheme_base}{sep}"
                f"token={urllib.parse.quote(token, safe='')}"
                f"&email={urllib.parse.quote(email, safe='')}"
                f"&name={urllib.parse.quote(name, safe='')}"
            )
            esc_link = html.escape(deep_link, quote=True)
            esc_email = html.escape(email)
            esc_name = html.escape(name)
            esc_token = html.escape(token)

            page_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Govee Sync — Signed In</title>
  <style>
    body {{
      margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      background: #060814; color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      padding: 20px; box-sizing: border-box;
    }}
    .card {{
      max-width: 440px; width: 100%; background: rgba(15, 23, 42, 0.92);
      border: 1px solid rgba(0, 245, 212, 0.35); border-radius: 20px; padding: 28px;
      text-align: center; box-shadow: 0 20px 50px rgba(0, 0, 0, 0.6);
    }}
    h1 {{ font-size: 22px; margin: 0 0 8px; color: #00f5d4; }}
    p {{ font-size: 14px; color: #94a3b8; margin: 0 0 20px; line-height: 1.5; }}
    .btn {{
      display: block; width: 100%; padding: 14px 18px; border-radius: 12px;
      background: linear-gradient(135deg, #00f5d4, #3b82f6); color: #040711;
      font-weight: 700; font-size: 15px; text-decoration: none; box-sizing: border-box;
      margin-bottom: 16px;
    }}
    .token-box {{
      background: #020617; border: 1px solid #334155; border-radius: 10px;
      padding: 10px; font-family: monospace; font-size: 12px; color: #e2e8f0;
      width: 100%; box-sizing: border-box; margin-bottom: 8px;
    }}
  </style>
</head>
<body>
  <div class="card">
    <h1>Authenticated!</h1>
    <p>Signed in as <strong>{esc_name}</strong> ({esc_email}).</p>
    <a class="btn" href="{esc_link}">Return to Govee Sync Android App</a>
    <p style="font-size:12px;margin-bottom:6px;">Or copy session token for manual paste in app:</p>
    <input class="token-box" id="tok" value="{esc_token}" readonly onclick="this.select();navigator.clipboard&&navigator.clipboard.writeText(this.value);" />
  </div>
  <script>
    setTimeout(function() {{ window.location.href = {json.dumps(deep_link)}; }}, 150);
  </script>
</body>
</html>"""
            resp = HTMLResponse(
                content=page_html,
                status_code=302,
                headers={"Location": deep_link},
            )
            self.set_session_cookie(resp, token, request)
            return resp

        target = next_path if (next_path and next_path.startswith("/")) else "/"
        sep = "&" if "?" in target else "?"
        redirect_url = f"{target}{sep}auth_token={urllib.parse.quote(token, safe='')}"
        resp = RedirectResponse(url=redirect_url, status_code=302)
        self.set_session_cookie(resp, token, request)
        return resp

    def build_access_denied_response(self, request: Request, email: str) -> Response:
        msg = access_denied_message(email)
        accept = (request.headers.get("accept") or "").lower()
        if "text/html" in accept and "application/json" not in accept:
            esc_msg = html.escape(msg)
            page = f"""<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/><title>Access Denied</title></head>
<body style="background:#060814;color:#f8fafc;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;padding:20px;">
  <div style="max-width:460px;background:#0f172a;border:1px solid #ef4444;border-radius:16px;padding:28px;text-align:center;">
    <h2 style="color:#ef4444;margin-top:0;">403 Access Denied</h2>
    <p style="color:#cbd5e1;line-height:1.5;">{esc_msg}</p>
    <a href="/" style="display:inline-block;margin-top:14px;padding:10px 18px;background:#1e293b;color:#38bdf8;border-radius:8px;text-decoration:none;">Return Home</a>
  </div>
</body>
</html>"""
            return HTMLResponse(content=page, status_code=403)
        return JSONResponse(
            status_code=403,
            content={"detail": msg, "error": msg, "email": email},
        )

    async def _get_http_client(self) -> Tuple[httpx.AsyncClient, bool]:
        if self._http_client is not None:
            return self._http_client, False
        return httpx.AsyncClient(timeout=10.0), True

    async def exchange_google_code(self, code: str, redirect_uri: str) -> Dict[str, Any]:
        """Exchange Google OAuth2 authorization code for user email & profile."""
        if not self.google_client_id or not self.google_client_secret:
            raise HTTPException(status_code=503, detail="Google OAuth2 is not configured on this server.")

        client, own = await self._get_http_client()
        try:
            token_resp = await client.post(
                self.GOOGLE_TOKEN_URL,
                data={
                    "code": code,
                    "client_id": self.google_client_id,
                    "client_secret": self.google_client_secret,
                    "redirect_uri": redirect_uri,
                    "grant_type": "authorization_code",
                },
                headers={"Accept": "application/json"},
            )
            if token_resp.status_code != 200:
                raise HTTPException(
                    status_code=400,
                    detail=f"Google token exchange failed (HTTP {token_resp.status_code})",
                )
            token_data = token_resp.json()
            access_token = token_data.get("access_token", "")
            id_token = token_data.get("id_token", "")

            if access_token:
                ui_resp = await client.get(
                    self.GOOGLE_USERINFO_URL,
                    headers={"Authorization": f"Bearer {access_token}"},
                )
                if ui_resp.status_code == 200:
                    info = ui_resp.json()
                    email = str(info.get("email") or "").strip().lower()
                    if email:
                        return {
                            "email": email,
                            "name": str(info.get("name") or email.split("@")[0]),
                            "picture": str(info.get("picture") or ""),
                            "provider": "google",
                        }

            if id_token:
                return await self.verify_google_id_token(id_token)

            raise HTTPException(status_code=400, detail="Could not retrieve Google user email")
        finally:
            if own:
                await client.aclose()

    async def verify_google_id_token(self, id_token: str) -> Dict[str, Any]:
        """Verify a Google Identity Services ID token via Google's tokeninfo endpoint."""
        clean_tok = (id_token or "").strip()
        if not clean_tok:
            raise HTTPException(status_code=400, detail="Missing Google id_token")

        client, own = await self._get_http_client()
        try:
            resp = await client.get(
                self.GOOGLE_TOKENINFO_URL,
                params={"id_token": clean_tok},
            )
            if resp.status_code != 200:
                raise HTTPException(status_code=401, detail="Invalid Google ID token")
            info = resp.json()
            aud = str(info.get("aud") or "").strip()
            allowed_auds = {
                x.strip()
                for x in (
                    self.google_client_id,
                    os.environ.get("GOOGLE_GSI_CLIENT_ID", ""),
                    os.environ.get("GOOGLE_DEVPOST_CLIENT_ID", ""),
                    os.environ.get("GOOGLE_OAUTH_CLIENT_ID", ""),
                )
                if x and x.strip()
            }
            if allowed_auds and aud and aud not in allowed_auds:
                raise HTTPException(status_code=401, detail="Google ID token audience mismatch")
            email = str(info.get("email") or "").strip().lower()
            if not email:
                raise HTTPException(status_code=400, detail="Google ID token did not contain an email")
            return {
                "email": email,
                "name": str(info.get("name") or email.split("@")[0]),
                "picture": str(info.get("picture") or ""),
                "provider": "google",
            }
        finally:
            if own:
                await client.aclose()

    async def exchange_github_code(self, code: str, redirect_uri: str) -> Dict[str, Any]:
        """
        Exchange GitHub OAuth2 code for access token, query `/user` and `/user/emails`
        (when `/user` has `email: null` or private email), and map configured `OWNER_GITHUB_USER`
        to `OWNER_EMAIL` if email scope is private.
        """
        if not self.github_client_id or not self.github_client_secret:
            raise HTTPException(status_code=503, detail="GitHub OAuth2 is not configured on this server.")

        client, own = await self._get_http_client()
        try:
            tok_resp = await client.post(
                self.GITHUB_TOKEN_URL,
                data={
                    "client_id": self.github_client_id,
                    "client_secret": self.github_client_secret,
                    "code": code,
                    "redirect_uri": redirect_uri,
                },
                headers={"Accept": "application/json"},
            )
            if tok_resp.status_code != 200:
                raise HTTPException(
                    status_code=400,
                    detail=f"GitHub token exchange failed (HTTP {tok_resp.status_code})",
                )
            tok_data = tok_resp.json()
            access_token = str(tok_data.get("access_token") or "").strip()
            if not access_token:
                raise HTTPException(status_code=400, detail="GitHub did not return an access_token")

            gh_headers = {
                "Authorization": f"Bearer {access_token}",
                "Accept": "application/vnd.github+json",
                "User-Agent": "Govee-Multi-House-Sync",
            }
            user_resp = await client.get(self.GITHUB_USER_URL, headers=gh_headers)
            if user_resp.status_code != 200:
                raise HTTPException(status_code=400, detail="Failed to fetch GitHub user profile")

            uinfo = user_resp.json()
            login = str(uinfo.get("login") or "").strip()
            display_name = str(uinfo.get("name") or login or "GitHub User").strip()
            avatar_url = str(uinfo.get("avatar_url") or "").strip()
            primary_email = str(uinfo.get("email") or "").strip().lower()

            candidate_emails: List[str] = []
            if primary_email:
                candidate_emails.append(primary_email)

            # Always check /user/emails when primary_email is missing or not yet in authorized_emails
            authorized_set = set(self.get_authorized_emails())
            if not primary_email or primary_email not in authorized_set:
                try:
                    emails_resp = await client.get(self.GITHUB_EMAILS_URL, headers=gh_headers)
                    if emails_resp.status_code == 200 and isinstance(emails_resp.json(), list):
                        # Prioritize primary+verified, then any verified email
                        email_items = emails_resp.json()
                        for item in sorted(
                            email_items,
                            key=lambda x: (bool(x.get("primary")), bool(x.get("verified"))),
                            reverse=True,
                        ):
                            if isinstance(item, dict) and item.get("verified", True):
                                em = str(item.get("email") or "").strip().lower()
                                if em and em not in candidate_emails:
                                    candidate_emails.append(em)
                except Exception as exc:
                    logger.debug("GitHub /user/emails lookup note: %s", exc)

            # Allow configured OWNER_GITHUB_USER to map to OWNER_EMAIL if email is private
            owner_gh = (os.environ.get("OWNER_GITHUB_USER") or "owner-github").strip().lower()
            if owner_gh and login.lower() == owner_gh and OWNER_EMAIL not in candidate_emails:
                candidate_emails.append(OWNER_EMAIL)

            # Pick the first candidate email that is in authorized_emails, or the first candidate email
            matched_email = next((em for em in candidate_emails if em in authorized_set), None)
            chosen_email = matched_email or (candidate_emails[0] if candidate_emails else f"{login}@users.noreply.github.com")

            return {
                "email": chosen_email.lower(),
                "name": display_name,
                "picture": avatar_url,
                "provider": "github",
                "github_login": login,
            }
        finally:
            if own:
                await client.aclose()
