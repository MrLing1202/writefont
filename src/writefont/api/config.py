"""
WriteFont API Configuration Manager

Manages persistent storage and retrieval of API provider configurations.
Configs are stored in ~/.writefont/api_config.json with API keys masked on save.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .providers import (
    BaseProvider,
    CustomProvider,
    DeepSeekProvider,
    MiMoProvider,
    OllamaProvider,
    OpenAIProvider,
    QwenProvider,
    SiliconFlowProvider,
    ZhipuAIProvider,
)

_CONFIG_DIR = Path.home() / ".writefont"
_CONFIG_FILE = _CONFIG_DIR / "api_config.json"

_PROVIDER_CLASSES: dict[str, type[BaseProvider]] = {
    "mimo": MiMoProvider,
    "openai": OpenAIProvider,
    "qwen": QwenProvider,
    "deepseek": DeepSeekProvider,
    "custom": CustomProvider,
    "zhipuai": ZhipuAIProvider,
    "siliconflow": SiliconFlowProvider,
    "ollama": OllamaProvider,
}


def _mask_key(api_key: str) -> str:
    """Mask an API key, keeping only the first 8 characters."""
    if len(api_key) <= 8:
        return api_key + "***"
    return api_key[:8] + "***"


class APIConfigManager:
    """
    Manages API provider configurations.

    Configuration is persisted to ``~/.writefont/api_config.json``.
    API keys are stored in masked form (first 8 chars + ``***``).
    """

    def __init__(self, config_path: Path | str = _CONFIG_FILE) -> None:
        self._path = Path(config_path).expanduser()
        self._ensure_dir()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _ensure_dir(self) -> None:
        """Create the config directory if it doesn't exist."""
        self._path.parent.mkdir(parents=True, exist_ok=True)

    def _read(self) -> dict[str, Any]:
        """Read the raw config file."""
        if not self._path.exists():
            return {"providers": {}}
        try:
            return json.loads(self._path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return {"providers": {}}

    def _write(self, data: dict[str, Any]) -> None:
        """Write the raw config file."""
        self._path.write_text(
            json.dumps(data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def save_provider(
        self,
        name: str,
        base_url: str,
        api_key: str,
        model: str = "",
        *,
        enabled: bool = True,
    ) -> None:
        """
        Save (or update) a provider configuration.

        Args:
            name: Provider identifier (e.g. ``"mimo"``, ``"openai"``, ``"custom"``).
            base_url: API endpoint base URL.
            api_key: **Plain-text** API key; will be masked before storage.
            model: Default model name (optional).
            enabled: Whether the provider is active.
        """
        cfg = self._read()
        cfg["providers"][name] = {
            "base_url": base_url,
            "api_key": _mask_key(api_key),
            "model": model,
            "enabled": enabled,
        }
        self._write(cfg)

    def load_providers(self) -> dict[str, dict[str, Any]]:
        """
        Load all stored provider configurations.

        Returns:
            Mapping of provider name → config dict.
        """
        return self._read().get("providers", {})

    def get_provider(self, name: str) -> BaseProvider:
        """
        Instantiate a configured provider by name.

        The stored masked API key is **not** usable for real requests;
        callers must supply the real key externally.

        Args:
            name: Provider identifier.

        Returns:
            A :class:`BaseProvider` instance.

        Raises:
            KeyError: If the provider name is not found.
            ValueError: If the provider class is unknown.
        """
        providers = self.load_providers()
        if name not in providers:
            raise KeyError(f"Provider '{name}' is not configured")

        entry = providers[name]
        cls = _PROVIDER_CLASSES.get(name)
        if cls is None:
            # Treat unknown names as custom providers
            cls = CustomProvider

        kwargs: dict[str, Any] = {
            "api_key": entry.get("api_key", ""),
            "base_url": entry.get("base_url", ""),
            "model": entry.get("model", ""),
        }
        if cls is not CustomProvider:
            kwargs.pop("base_url", None)

        return cls(**kwargs)  # type: ignore[call-arg]

    def list_providers(self) -> list[dict[str, Any]]:
        """
        List all configured providers with summary info.

        Returns:
            List of dicts with keys ``name``, ``configured`` (bool),
            ``enabled`` (bool), ``free`` (bool), ``description`` (str).
        """
        providers = self.load_providers()
        result: list[dict[str, Any]] = []
        for name, entry in providers.items():
            result.append(
                {
                    "name": name,
                    "configured": bool(entry.get("api_key")),
                    "enabled": entry.get("enabled", True),
                }
            )

        # 免费Provider — 即使用户没配置也要显示
        free_providers = {
            "zhipuai": {
                "name": "智谱AI (免费)",
                "configured": False,
                "free": True,
                "description": "永久免费，注册即用",
            },
            "siliconflow": {
                "name": "硅基流动 (免费)",
                "configured": False,
                "free": True,
                "description": "国内直连，免费tier",
            },
            "ollama": {
                "name": "Ollama (本地)",
                "configured": False,
                "free": True,
                "description": "完全本地，无需联网",
            },
        }

        existing_names = {r["name"] for r in result}
        for name, info in free_providers.items():
            if name not in existing_names:
                result.append(info)
            else:
                # 已配置的免费provider也标记free
                for r in result:
                    if r["name"] == name:
                        r.setdefault("free", True)
                        r.setdefault("description", info["description"])

        return result

    def delete_provider(self, name: str) -> None:
        """
        Remove a provider configuration.

        Args:
            name: Provider identifier to delete.

        Raises:
            KeyError: If the provider name is not found.
        """
        cfg = self._read()
        if name not in cfg.get("providers", {}):
            raise KeyError(f"Provider '{name}' is not configured")
        del cfg["providers"][name]
        self._write(cfg)
