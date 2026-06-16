"""Gradio web interface for WriteFont.

Provides an interactive UI for:
1. Uploading reference handwriting images to extract a style vector.
2. Configuring generation parameters (image size, diffusion steps, etc.).
3. Previewing individual generated glyphs.
4. Generating a full font and downloading the packaged file.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path
from typing import List, Optional, Tuple

import gradio as gr
import numpy as np
import torch

# Internal imports — wrapped in try/except so the module can be inspected
# even when dependencies are not fully installed.
try:
    from ..generator.diffusion import ConditionalDiffusionModel
    from ..generator.renderer import GlyphRenderer
    from ..font.vectorizer import GlyphVectorizer
    from ..font.packager import FontPackager
    from ..utils.charset import get_gb2312_chars, get_ascii_chars
    from ..utils.image import (
        to_grayscale,
        pad_to_square,
        ndarray_to_tensor,
    )
except ImportError:
    ConditionalDiffusionModel = None  # type: ignore[assignment]
    GlyphRenderer = None  # type: ignore[assignment]
    GlyphVectorizer = None  # type: ignore[assignment]
    FontPackager = None  # type: ignore[assignment]
    get_gb2312_chars = None  # type: ignore[assignment,misc]
    get_ascii_chars = None  # type: ignore[assignment,misc]


# ---------------------------------------------------------------------------
# Style extractor (simple CNN encoder)
# ---------------------------------------------------------------------------

class StyleExtractor(torch.nn.Module):
    """Lightweight CNN that maps a handwriting image to a style vector."""

    def __init__(self, style_dim: int = 128) -> None:
        super().__init__()
        self.encoder = torch.nn.Sequential(
            torch.nn.Conv2d(1, 32, 3, stride=2, padding=1),
            torch.nn.GroupNorm(8, 32),
            torch.nn.SiLU(),
            torch.nn.Conv2d(32, 64, 3, stride=2, padding=1),
            torch.nn.GroupNorm(8, 64),
            torch.nn.SiLU(),
            torch.nn.Conv2d(64, 128, 3, stride=2, padding=1),
            torch.nn.GroupNorm(8, 128),
            torch.nn.SiLU(),
            torch.nn.AdaptiveAvgPool2d(1),
            torch.nn.Flatten(),
            torch.nn.Linear(128, style_dim),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.encoder(x)


# ---------------------------------------------------------------------------
# Application state
# ---------------------------------------------------------------------------

class WriteFontApp:
    """Holds model state and implements the generation pipeline."""

    def __init__(self, device: Optional[str] = None) -> None:
        self.device = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
        self.model: Optional[ConditionalDiffusionModel] = None
        self.style_extractor: Optional[StyleExtractor] = None
        self.renderer: Optional[GlyphRenderer] = None
        self.vectorizer: Optional[GlyphVectorizer] = None
        self.current_style: Optional[torch.Tensor] = None

        # Character sets
        self.gb2312_chars: List[str] = get_gb2312_chars() if get_gb2312_chars else []
        self.ascii_chars: List[str] = get_ascii_chars() if get_ascii_chars else []

    def load_model(self, checkpoint_path: Optional[str] = None) -> str:
        """Load or initialise the diffusion model."""
        if ConditionalDiffusionModel is None:
            return "❌ Dependencies not installed. Run: pip install writefont"

        self.model = ConditionalDiffusionModel().to(self.device)
        self.style_extractor = StyleExtractor().to(self.device)
        self.renderer = GlyphRenderer(target_size=(128, 128))
        self.vectorizer = GlyphVectorizer()

        if checkpoint_path and os.path.isfile(checkpoint_path):
            state = torch.load(checkpoint_path, map_location=self.device)
            if "model" in state:
                self.model.load_state_dict(state["model"])
            if "style_extractor" in state:
                self.style_extractor.load_state_dict(state["style_extractor"])
            return f"✅ Model loaded from {checkpoint_path}"
        return "✅ Model initialised (no checkpoint — using random weights)"

    def extract_style(self, image: np.ndarray) -> str:
        """Extract style vector from a reference handwriting image."""
        if self.style_extractor is None:
            return "❌ Please load the model first."

        gray = to_grayscale(image)
        squared = pad_to_square(gray, target_size=128)
        tensor = ndarray_to_tensor(squared).unsqueeze(0).to(self.device)

        with torch.no_grad():
            self.current_style = self.style_extractor(tensor)

        return "✅ Style extracted successfully!"

    def generate_single_glyph(
        self,
        char: str,
        num_steps: int = 50,
    ) -> Optional[np.ndarray]:
        """Generate a single glyph image for preview."""
        if self.model is None or self.current_style is None:
            return None

        # Map character to index
        char_id = self._char_to_id(char)
        if char_id is None:
            return None

        with torch.no_grad():
            generated = self.model.generate_glyph(
                style=self.current_style,
                char_id=char_id,
                device=self.device,
                num_steps=num_steps,
            )

        rendered = self.renderer.render(generated[0])
        return rendered

    def generate_font(
        self,
        charset: str,
        font_name: str,
        num_steps: int = 50,
        format: str = "ttf",
        progress: Optional[gr.Progress] = None,
    ) -> Optional[str]:
        """Generate a full font file and return its path."""
        if self.model is None or self.current_style is None:
            return None

        # Select character set
        if charset == "ASCII":
            chars = self.ascii_chars
        elif charset == "GB2312 Level 1":
            chars = get_gb2312_chars(level=1) if get_gb2312_chars else []
        elif charset == "GB2312 Level 2":
            chars = get_gb2312_chars(level=2) if get_gb2312_chars else []
        else:
            chars = self.gb2312_chars

        if not chars:
            return None

        packager = FontPackager(font_name=font_name, family_name=font_name)

        total = len(chars)
        for i, ch in enumerate(chars):
            if progress is not None:
                progress((i, total), desc=f"Generating '{ch}' ({i+1}/{total})")

            char_id = self._char_to_id(ch)
            if char_id is None:
                continue

            with torch.no_grad():
                generated = self.model.generate_glyph(
                    style=self.current_style,
                    char_id=char_id,
                    device=self.device,
                    num_steps=num_steps,
                )

            rendered = self.renderer.render(generated[0])
            contours = self.vectorizer.vectorize(rendered)
            packager.add_glyph(ord(ch), contours, advance_width=600)

        # Export
        output_dir = Path(tempfile.mkdtemp(prefix="writefont_"))
        output_path = output_dir / f"{font_name}.{format}"
        packager.export(output_path, format=format)
        return str(output_path)

    def _char_to_id(self, char: str) -> Optional[int]:
        """Map a character to its model embedding index."""
        if char in self.gb2312_chars:
            return self.gb2312_chars.index(char)
        if char in self.ascii_chars:
            return len(self.gb2312_chars) + self.ascii_chars.index(char)
        # Fallback: use Unicode code point as index (may be OOB, but works for demo)
        return ord(char) % 8000


# ---------------------------------------------------------------------------
# Gradio UI builder
# ---------------------------------------------------------------------------

def create_app(device: Optional[str] = None) -> gr.Blocks:
    """Build and return the Gradio Blocks application.

    Parameters
    ----------
    device : str, optional
        Torch device (``"cpu"``, ``"cuda"``, ``"mps"``).

    Returns
    -------
    gr.Blocks
        Ready-to-launch Gradio app.
    """
    app_state = WriteFontApp(device=device)

    with gr.Blocks(
        title="WriteFont — AI Handwriting Font Generator",
        theme=gr.themes.Soft(),
    ) as demo:
        gr.Markdown(
            "# ✍️ WriteFont\n"
            "Generate a personalised handwriting font from a single reference image.\n\n"
            "Upload a handwriting sample → extract style → generate any Chinese character in your style → download as TTF."
        )

        # ---- Step 1: Model loading ----
        with gr.Row():
            checkpoint_input = gr.Textbox(
                label="Checkpoint Path (optional)",
                placeholder="path/to/checkpoint.pt",
                scale=3,
            )
            load_btn = gr.Button("🔄 Load Model", variant="secondary")
        load_status = gr.Textbox(label="Status", interactive=False)

        # ---- Step 2: Style upload ----
        with gr.Row():
            with gr.Column(scale=1):
                style_image = gr.Image(label="Upload Handwriting Sample", type="numpy")
                extract_btn = gr.Button("🎨 Extract Style", variant="primary")
            style_status = gr.Textbox(label="Style Status", interactive=False)

        # ---- Step 3: Single glyph preview ----
        gr.Markdown("### 🔍 Glyph Preview")
        with gr.Row():
            preview_char = gr.Textbox(label="Character", value="好", max_lines=1, scale=1)
            preview_steps = gr.Slider(10, 200, value=50, step=10, label="Diffusion Steps", scale=2)
            preview_btn = gr.Button("👁️ Generate Preview", scale=1)
        glyph_preview = gr.Image(label="Generated Glyph", type="numpy")

        # ---- Step 4: Full font generation ----
        gr.Markdown("### 📦 Generate Full Font")
        with gr.Row():
            charset_select = gr.Radio(
                choices=["ASCII", "GB2312 Level 1", "GB2312 Level 2", "GB2312 Full"],
                value="ASCII",
                label="Character Set",
            )
            font_name_input = gr.Textbox(label="Font Name", value="MyHandwriting")
            font_format = gr.Dropdown(
                choices=["ttf", "otf", "woff", "woff2"],
                value="ttf",
                label="Output Format",
            )
        gen_steps = gr.Slider(10, 200, value=50, step=10, label="Diffusion Steps (more = better quality)")
        generate_btn = gr.Button("🚀 Generate Font", variant="primary", size="lg")
        font_output = gr.File(label="Download Font File")
        gen_status = gr.Textbox(label="Generation Status", interactive=False)

        # ---- Wire events ----
        load_btn.click(
            fn=app_state.load_model,
            inputs=[checkpoint_input],
            outputs=[load_status],
        )
        extract_btn.click(
            fn=app_state.extract_style,
            inputs=[style_image],
            outputs=[style_status],
        )
        preview_btn.click(
            fn=app_state.generate_single_glyph,
            inputs=[preview_char, preview_steps],
            outputs=[glyph_preview],
        )
        generate_btn.click(
            fn=app_state.generate_font,
            inputs=[charset_select, font_name_input, gen_steps, font_format],
            outputs=[font_output, gen_status],
        )

    return demo


# ---------------------------------------------------------------------------
# Standalone entry point
# ---------------------------------------------------------------------------

def main() -> None:
    """Launch the Gradio app."""
    demo = create_app()
    demo.launch(server_name="0.0.0.0", server_port=7860, share=False)


if __name__ == "__main__":
    main()
