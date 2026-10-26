from __future__ import annotations

import json
import logging
import os
import shutil
import threading
from pathlib import Path
from typing import Optional

from .models import SystemConfig

logger = logging.getLogger("govee_sync.config")


class ConfigStore:
    """Thread-safe persistent configuration manager stored in /mnt/media/govee_lights_sync/data."""

    def __init__(self, data_dir: Optional[str] = None, example_path: Optional[str] = None) -> None:
        base_dir = Path(__file__).resolve().parents[2]
        self.data_dir = Path(data_dir or os.environ.get("DATA_DIR", "/mnt/media/govee_lights_sync/data"))
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.config_path = self.data_dir / "config.json"
        self.backup_path = self.data_dir / "config.backup.json"
        self.example_path = Path(example_path) if example_path else (base_dir / "examples" / "default_3_houses.json")
        self._lock = threading.RLock()
        self._config: SystemConfig = self._load_or_init()

    def _load_or_init(self) -> SystemConfig:
        with self._lock:
            if not self.config_path.exists():
                if self.example_path.exists():
                    shutil.copyfile(self.example_path, self.config_path)
                    logger.info("Initialized persistent config at %s from %s", self.config_path, self.example_path)
                else:
                    default_cfg = SystemConfig()
                    self._write_atomic(default_cfg)
                    return default_cfg

            try:
                raw = json.loads(self.config_path.read_text(encoding="utf-8"))
                cfg = SystemConfig.model_validate(raw)
            except Exception as exc:
                logger.error("Failed to parse %s (%s); loading default 3-house topology", self.config_path, exc)
                if self.example_path.exists():
                    raw = json.loads(self.example_path.read_text(encoding="utf-8"))
                    cfg = SystemConfig.model_validate(raw)
                else:
                    cfg = SystemConfig()
                self._write_atomic(cfg)

            env_api_key = os.environ.get("GOVEE_API_KEY", "").strip()
            if env_api_key and not cfg.govee_api_key:
                cfg.govee_api_key = env_api_key
                self._write_atomic(cfg)

            return cfg

    def _write_atomic(self, config: SystemConfig) -> None:
        tmp_path = self.config_path.with_suffix(".json.tmp")
        payload = json.dumps(config.model_dump(mode="json"), indent=2)
        tmp_path.write_text(payload, encoding="utf-8")
        if self.config_path.exists():
            shutil.copyfile(self.config_path, self.backup_path)
        tmp_path.replace(self.config_path)

    def get(self) -> SystemConfig:
        with self._lock:
            return self._config.model_copy(deep=True)

    def save(self, new_config: SystemConfig) -> SystemConfig:
        with self._lock:
            # Ensure houses are ordered sequentially
            new_config.houses.sort(key=lambda h: (h.order, h.id))
            self._write_atomic(new_config)
            self._config = new_config.model_copy(deep=True)
            logger.info(
                "Saved configuration to %s (%d houses, %d total controllers)",
                self.config_path,
                len(self._config.houses),
                sum(len(h.controllers) for h in self._config.houses),
            )
            return self.get()

    def reset_to_example(self) -> SystemConfig:
        with self._lock:
            prev_cfg = self._config
            raw = json.loads(self.example_path.read_text(encoding="utf-8"))
            cfg = SystemConfig.model_validate(raw)
            env_api_key = os.environ.get("GOVEE_API_KEY", "").strip()
            if prev_cfg and prev_cfg.govee_api_key:
                cfg.govee_api_key = prev_cfg.govee_api_key
            elif env_api_key and not cfg.govee_api_key:
                cfg.govee_api_key = env_api_key
            if prev_cfg and prev_cfg.authorized_emails:
                cfg.authorized_emails = list(prev_cfg.authorized_emails)
            if prev_cfg:
                prev_house_keys = {h.id: h.govee_api_key for h in prev_cfg.houses if h.govee_api_key}
                for h in cfg.houses:
                    if h.id in prev_house_keys and not h.govee_api_key:
                        h.govee_api_key = prev_house_keys[h.id]
            return self.save(cfg)
