#!/usr/bin/env python3
"""
WriteFont Desktop Engine Bridge
This script provides the Python backend for the Tauri desktop application.
It handles image processing and font generation.

Usage:
    python writefont-engine.py <command> <args...>
    
Commands:
    process <image_path> <char> <stroke_width> <smoothness> <ink_density>
    generate <chars_json> <params_json> <font_name> <author> <output_dir>
    preview <image_path> <stroke_width> <smoothness> <ink_density>
    check
"""

import sys
import os
import json
import tempfile
import base64
import io

# Add parent directory to path for importing writefont modules
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
sys.path.insert(0, PROJECT_ROOT)


def check_environment():
    """Check Python environment and available packages."""
    result = {
        "available": True,
        "version": sys.version,
        "packages": {}
    }
    
    try:
        import PIL
        result["packages"]["Pillow"] = PIL.__version__
    except ImportError:
        result["packages"]["Pillow"] = "not installed"
    
    try:
        import fontTools
        result["packages"]["fontTools"] = fontTools.__version__
    except ImportError:
        result["packages"]["fontTools"] = "not installed"
    
    try:
        import numpy
        result["packages"]["numpy"] = numpy.__version__
    except ImportError:
        result["packages"]["numpy"] = "not installed"
    
    print(json.dumps(result))


def process_character(image_path, char, stroke_width, smoothness, ink_density):
    """Process a single character image."""
    try:
        # Try importing the core module
        from src.writefont.core import process_character as core_process
        result = core_process(image_path, char, stroke_width, smoothness, ink_density)
        print(json.dumps(result))
        return
    except ImportError:
        pass
    
    # Fallback: basic image processing with Pillow
    try:
        from PIL import Image, ImageFilter
        
        # Load image
        if image_path.startswith("data:"):
            header, data = image_path.split(",", 1)
            img_bytes = base64.b64decode(data)
            img = Image.open(io.BytesIO(img_bytes))
        else:
            img = Image.open(image_path)
        
        # Process: convert to grayscale, apply threshold
        img = img.convert("L")
        
        # Apply ink density as contrast adjustment
        from PIL import ImageEnhance
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(ink_density / 50.0)
        
        # Apply smoothness as blur
        if smoothness > 50:
            blur_radius = (smoothness - 50) / 25.0
            img = img.filter(ImageFilter.GaussianBlur(radius=blur_radius))
        
        # Apply threshold for binary effect
        threshold = int(128 * (1 - stroke_width / 10))
        img = img.point(lambda x: 0 if x < threshold else 255)
        
        # Save processed image
        output_dir = tempfile.mkdtemp()
        safe_char = char.replace("/", "_").replace("\\", "_")
        output_path = os.path.join(output_dir, f"char_{safe_char}.png")
        img.save(output_path)
        
        result = {
            "char": char,
            "processed_path": output_path
        }
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)


def generate_font(characters, params, font_name, author, output_dir):
    """Generate a TTF font file."""
    try:
        # Try importing the font generator
        from src.writefont.font_generator import generate_ttf as core_generate
        ttf_path = core_generate(characters, params, font_name, author, output_dir)
        result = {
            "success": True,
            "ttfPath": ttf_path,
            "previewImages": [],
            "message": "字体生成成功"
        }
        print(json.dumps(result))
        return
    except ImportError:
        pass
    
    # Fallback: generate basic font with fonttools
    try:
        from fontTools.ttLib import TTFont
        from fontTools.fontBuilder import FontBuilder
        
        char_list = [c["char"] for c in characters]
        
        # Create font
        fb = FontBuilder(1000, isTTF=True)
        glyph_order = [".notdef"] + char_list
        fb.setupGlyphOrder(glyph_order)
        
        # Setup cmap
        cmap = {0: ".notdef"}
        for c in char_list:
            cmap[ord(c)] = c
        fb.setupCharacterMap(cmap)
        
        # Setup glyf (empty outlines as placeholder)
        glyf = {".notdef": {}}
        for c in char_list:
            glyf[c] = {}
        fb.setupGlyf(glyf)
        
        # Setup metrics
        spacing = params.get("spacing", 10)
        advance_width = max(400, 1000 - int(spacing * 5))
        metrics = {".notdef": (500, 0)}
        for c in char_list:
            metrics[c] = (advance_width, 0)
        fb.setupHorizontalMetrics(metrics)
        
        # Setup header
        fb.setupHorizontalHeader(ascent=800, descent=-200)
        
        # Setup name table
        style = params.get("style", "Regular").capitalize()
        fb.setupNameTable({
            "familyName": font_name,
            "styleName": style if style in ["Regular", "Bold", "Light"] else "Regular"
        })
        
        # Setup OS/2
        fb.setupOs2(
            sTypoAscender=800,
            sTypoDescender=-200,
            usWinAscent=1000,
            usWinDescent=200
        )
        
        fb.setupPost()
        
        # Save
        os.makedirs(output_dir, exist_ok=True)
        ttf_path = os.path.join(output_dir, f"{font_name}.ttf")
        fb.font.save(ttf_path)
        
        result = {
            "success": True,
            "ttfPath": ttf_path,
            "previewImages": [],
            "message": "字体生成成功（基础模式）"
        }
        print(json.dumps(result))
    except Exception as e:
        result = {
            "success": False,
            "ttfPath": "",
            "previewImages": [],
            "message": f"字体生成失败: {str(e)}"
        }
        print(json.dumps(result))
        sys.exit(1)


def preview_glyph(image_path, stroke_width, smoothness, ink_density):
    """Generate a preview of a processed glyph."""
    try:
        from src.writefont.preview import generate_preview
        result = generate_preview(image_path, stroke_width, smoothness, ink_density)
        print(result)
        return
    except ImportError:
        pass
    
    # Fallback: return image path
    print(image_path)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "check":
        check_environment()
    
    elif command == "process":
        if len(sys.argv) < 7:
            print("Usage: process <image_path> <char> <stroke_width> <smoothness> <ink_density>")
            sys.exit(1)
        process_character(
            sys.argv[2], sys.argv[3],
            float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
        )
    
    elif command == "generate":
        if len(sys.argv) < 7:
            print("Usage: generate <chars_json> <params_json> <font_name> <author> <output_dir>")
            sys.exit(1)
        generate_font(
            json.loads(sys.argv[2]), json.loads(sys.argv[3]),
            sys.argv[4], sys.argv[5], sys.argv[6]
        )
    
    elif command == "preview":
        if len(sys.argv) < 6:
            print("Usage: preview <image_path> <stroke_width> <smoothness> <ink_density>")
            sys.exit(1)
        preview_glyph(
            sys.argv[2],
            float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
        )
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)


if __name__ == "__main__":
    main()
