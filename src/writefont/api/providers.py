"""
WriteFont API Providers

Provides a unified interface for multiple LLM API providers using
OpenAI-compatible chat/completions endpoints.
"""

from __future__ import annotations

import base64
import mimetypes
import time
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Optional

import httpx


_DEFAULT_TIMEOUT = 30.0
_MAX_RETRIES = 3


class BaseProvider(ABC):
    """Abstract base class for all API providers."""

    base_url: str
    default_model: str
    api_key: str

    def __init__(self, api_key: str, base_url: str = "", default_model: str = "") -> None:
        self.api_key = api_key
        if base_url:
            self.base_url = base_url
        if default_model:
            self.default_model = default_model

    # ------------------------------------------------------------------
    # Public interface
    # ------------------------------------------------------------------

    @abstractmethod
    def chat_completion(self, messages: list[dict[str, Any]], model: str = "") -> str:
        """Send a chat completion request and return the assistant's reply."""
        ...

    @abstractmethod
    def vision_completion(
        self,
        image_path_or_b64: str,
        prompt: str,
        model: str = "",
    ) -> str:
        """Send a vision completion request with an image and return the reply."""
        ...

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _encode_image(path: str | Path) -> str:
        """Read an image file and return its base64-encoded content."""
        p = Path(path).expanduser().resolve()
        if not p.exists():
            raise FileNotFoundError(f"Image file not found: {p}")
        return base64.b64encode(p.read_bytes()).decode("utf-8")

    @staticmethod
    def _guess_mime(path: str | Path) -> str:
        """Guess the MIME type of a file."""
        mime, _ = mimetypes.guess_type(str(path))
        return mime or "image/png"

    def _post_chat(self, payload: dict[str, Any]) -> str:
        """POST to /chat/completions with retry logic and return content."""
        url = f"{self.base_url.rstrip('/')}/chat/completions"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        last_exc: Exception | None = None
        for attempt in range(1, _MAX_RETRIES + 1):
            try:
                resp = httpx.post(
                    url,
                    json=payload,
                    headers=headers,
                    timeout=_DEFAULT_TIMEOUT,
                )
                resp.raise_for_status()
                data = resp.json()
                return data["choices"][0]["message"]["content"]
            except (httpx.HTTPStatusError, httpx.RequestError, KeyError) as exc:
                last_exc = exc
                if attempt < _MAX_RETRIES:
                    time.sleep(1 * attempt)
        raise RuntimeError(
            f"API request failed after {_MAX_RETRIES} retries: {last_exc}"
        )

    def _build_image_content(
        self,
        image_path_or_b64: str,
        prompt: str,
    ) -> list[dict[str, Any]]:
        """Build a vision message payload from either a file path or base64."""
        # Detect whether input is a file path or raw base64
        if len(image_path_or_b64) < 512 and (
            "/" in image_path_or_b64 or "\\" in image_path_or_b64
        ):
            b64 = self._encode_image(image_path_or_b64)
            mime = self._guess_mime(image_path_or_b64)
        else:
            b64 = image_path_or_b64
            mime = "image/png"

        image_url = f"data:{mime};base64,{b64}"
        return [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": image_url}},
                ],
            }
        ]


# ======================================================================
# Concrete providers
# ======================================================================


class MiMoProvider(BaseProvider):
    """Xiaomi MiMo API provider."""

    base_url = "https://token-plan-cn.xiaomimimo.com/v1"
    default_model = "mimo-v2.5-pro"

    def __init__(self, api_key: str, model: str = "") -> None:
        super().__init__(api_key=api_key, default_model=model or self.default_model)

    def chat_completion(self, messages: list[dict[str, Any]], model: str = "") -> str:
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)

    def vision_completion(
        self, image_path_or_b64: str, prompt: str, model: str = ""
    ) -> str:
        messages = self._build_image_content(image_path_or_b64, prompt)
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)


class OpenAIProvider(BaseProvider):
    """OpenAI API provider."""

    base_url = "https://api.openai.com/v1"
    default_model = "gpt-4o"

    def __init__(self, api_key: str, model: str = "") -> None:
        super().__init__(api_key=api_key, default_model=model or self.default_model)

    def chat_completion(self, messages: list[dict[str, Any]], model: str = "") -> str:
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)

    def vision_completion(
        self, image_path_or_b64: str, prompt: str, model: str = ""
    ) -> str:
        messages = self._build_image_content(image_path_or_b64, prompt)
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)


class QwenProvider(BaseProvider):
    """Alibaba Qwen (通义千问) API provider via DashScope."""

    base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    default_model = "qwen-vl-max"

    def __init__(self, api_key: str, model: str = "") -> None:
        super().__init__(api_key=api_key, default_model=model or self.default_model)

    def chat_completion(self, messages: list[dict[str, Any]], model: str = "") -> str:
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)

    def vision_completion(
        self, image_path_or_b64: str, prompt: str, model: str = ""
    ) -> str:
        messages = self._build_image_content(image_path_or_b64, prompt)
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)


class DeepSeekProvider(BaseProvider):
    """DeepSeek API provider."""

    base_url = "https://api.deepseek.com/v1"
    default_model = "deepseek-chat"

    def __init__(self, api_key: str, model: str = "") -> None:
        super().__init__(api_key=api_key, default_model=model or self.default_model)

    def chat_completion(self, messages: list[dict[str, Any]], model: str = "") -> str:
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)

    def vision_completion(
        self, image_path_or_b64: str, prompt: str, model: str = ""
    ) -> str:
        messages = self._build_image_content(image_path_or_b64, prompt)
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)


class CustomProvider(BaseProvider):
    """User-defined provider with custom base_url and model."""

    def __init__(
        self,
        api_key: str,
        base_url: str,
        model: str = "default",
    ) -> None:
        if not base_url:
            raise ValueError("CustomProvider requires a base_url")
        super().__init__(api_key=api_key, base_url=base_url, default_model=model)

    def chat_completion(self, messages: list[dict[str, Any]], model: str = "") -> str:
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)

    def vision_completion(
        self, image_path_or_b64: str, prompt: str, model: str = ""
    ) -> str:
        messages = self._build_image_content(image_path_or_b64, prompt)
        payload = {
            "model": model or self.default_model,
            "messages": messages,
        }
        return self._post_chat(payload)
