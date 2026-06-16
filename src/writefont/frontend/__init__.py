"""Frontend module: Gradio-based web UI for WriteFont."""

try:
    from .app import create_app
except ImportError:
    create_app = None  # type: ignore[assignment,misc]

__all__ = ["create_app"]
