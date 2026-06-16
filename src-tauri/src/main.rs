#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FontParams {
    #[serde(rename = "strokeWidth")]
    pub stroke_width: f64,
    pub smoothness: f64,
    pub spacing: f64,
    pub baseline: f64,
    #[serde(rename = "inkDensity")]
    pub ink_density: f64,
    pub style: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CharacterInput {
    pub char: String,
    #[serde(rename = "imagePath")]
    pub image_path: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GenerateResult {
    pub success: bool,
    #[serde(rename = "ttfPath")]
    pub ttf_path: String,
    #[serde(rename = "previewImages")]
    pub preview_images: Vec<String>,
    pub message: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct PythonEnv {
    pub available: bool,
    pub version: String,
    pub message: String,
}

/// Find Python interpreter path
fn find_python() -> String {
    // Try python3 first, then python
    for name in &["python3", "python"] {
        if let Ok(output) = Command::new(name).arg("--version").output() {
            if output.status.success() {
                return name.to_string();
            }
        }
    }
    // Check common paths
    let common_paths = [
        "/usr/bin/python3",
        "/usr/local/bin/python3",
        "/opt/homebrew/bin/python3",
        "C:\\Python311\\python.exe",
        "C:\\Python310\\python.exe",
    ];
    for path in &common_paths {
        if std::path::Path::new(path).exists() {
            return path.to_string();
        }
    }
    "python3".to_string()
}

/// Get the project root directory (where src/writefont/ lives)
fn get_project_root() -> PathBuf {
    // First check if we're in development mode
    let dev_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf();
    if dev_root.join("src").join("writefont").exists() {
        return dev_root;
    }

    // Check bundled resources
    if let Ok(exe_path) = std::env::current_exe() {
        let exe_dir = exe_path.parent().unwrap();
        // macOS .app bundle: Contents/Resources/
        let resource_dir = exe_dir.join("../Resources");
        if resource_dir.join("writefont").exists() {
            return resource_dir;
        }
        // Windows/Linux: same directory as exe
        if exe_dir.join("writefont").exists() {
            return exe_dir.to_path_buf();
        }
    }

    // Fallback to current dir
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

/// Process a character image through the Python engine
#[tauri::command]
async fn process_character_image(
    image_path: String,
    char: String,
    stroke_width: f64,
    smoothness: f64,
    ink_density: f64,
) -> Result<serde_json::Value, String> {
    let python = find_python();
    let project_root = get_project_root();

    // Create a Python script to process the image
    let script = format!(
        r#"
import sys
import os
import json
import base64
import tempfile
import io

sys.path.insert(0, r"{}")

image_path = r"{}"
char = "{}"
stroke_width = {}
smoothness = {}
ink_density = {}

try:
    from src.writefont.core import process_character
    result = process_character(image_path, char, stroke_width, smoothness, ink_density)
    print(json.dumps(result))
except ImportError:
    try:
        from PIL import Image, ImageFilter, ImageEnhance
        
        if image_path.startswith("data:"):
            header, data = image_path.split(",", 1)
            img_bytes = base64.b64decode(data)
            img = Image.open(io.BytesIO(img_bytes))
        else:
            img = Image.open(image_path)
        
        img = img.convert("L")
        enhancer = ImageEnhance.Contrast(img)
        img = enhancer.enhance(ink_density / 50.0)
        
        if smoothness > 50:
            blur_radius = (smoothness - 50) / 25.0
            img = img.filter(ImageFilter.GaussianBlur(radius=blur_radius))
        
        output_dir = tempfile.mkdtemp()
        safe_char = char.replace("/", "_").replace("\\", "_")
        output_path = os.path.join(output_dir, f"char_{{}}.png".format(safe_char))
        img.save(output_path)
        
        result = {{"char": char, "processed_path": output_path}}
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({{"error": str(e)}}))
        sys.exit(1)
except Exception as e:
    print(json.dumps({{"error": str(e)}}))
    sys.exit(1)
"#,
        project_root.display(),
        image_path,
        char,
        stroke_width,
        smoothness,
        ink_density
    );

    let output = Command::new(&python)
        .args(["-c", &script])
        .output()
        .map_err(|e| format!("Failed to run Python: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Python error: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let result: serde_json::Value =
        serde_json::from_str(stdout.trim()).map_err(|e| format!("Parse error: {}", e))?;

    Ok(result)
}

/// Generate the font file using Python engine
#[tauri::command]
async fn generate_font(
    characters: Vec<CharacterInput>,
    params: FontParams,
    font_name: String,
    author: String,
) -> Result<GenerateResult, String> {
    let python = find_python();
    let project_root = get_project_root();
    let output_dir = std::env::temp_dir().join("writefont_output");
    fs::create_dir_all(&output_dir).map_err(|e| e.to_string())?;

    let chars_json = serde_json::to_string(&characters).map_err(|e| e.to_string())?;
    let params_json = serde_json::to_string(&params).map_err(|e| e.to_string())?;

    let script = format!(
        r#"
import sys
import os
import json

sys.path.insert(0, r"{}")

chars_data = json.loads(r'''{}''')
params_data = json.loads(r'''{}''')
font_name = "{}"
author = "{}"
output_dir = r"{}"

try:
    from src.writefont.font_generator import generate_ttf
    ttf_path = generate_ttf(chars_data, params_data, font_name, author, output_dir)
    result = {{"success": True, "ttfPath": ttf_path, "previewImages": [], "message": "字体生成成功"}}
    print(json.dumps(result))
except ImportError:
    try:
        from fontTools.fontBuilder import FontBuilder
        
        char_list = [c["char"] for c in chars_data]
        fb = FontBuilder(1000, isTTF=True)
        glyph_order = [".notdef"] + char_list
        fb.setupGlyphOrder(glyph_order)
        
        cmap = {{0: ".notdef"}}
        for c in char_list:
            cmap[ord(c)] = c
        fb.setupCharacterMap(cmap)
        
        glyf = {{".notdef": {{}}}}
        for c in char_list:
            glyf[c] = {{}}
        fb.setupGlyf(glyf)
        
        spacing = params_data.get("spacing", 10)
        advance_width = max(400, 1000 - int(spacing * 5))
        metrics = {{".notdef": (500, 0)}}
        for c in char_list:
            metrics[c] = (advance_width, 0)
        fb.setupHorizontalMetrics(metrics)
        
        fb.setupHorizontalHeader(ascent=800, descent=-200)
        
        style = params_data.get("style", "Regular").capitalize()
        if style not in ["Regular", "Bold", "Light"]:
            style = "Regular"
        fb.setupNameTable({{"familyName": font_name, "styleName": style}})
        
        fb.setupOs2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=1000, usWinDescent=200)
        fb.setupPost()
        
        os.makedirs(output_dir, exist_ok=True)
        ttf_path = os.path.join(output_dir, font_name + ".ttf")
        fb.font.save(ttf_path)
        
        result = {{"success": True, "ttfPath": ttf_path, "previewImages": [], "message": "字体生成成功（基础模式）"}}
        print(json.dumps(result))
    except Exception as e:
        result = {{"success": False, "ttfPath": "", "previewImages": [], "message": "字体生成失败: " + str(e)}}
        print(json.dumps(result))
except Exception as e:
    result = {{"success": False, "ttfPath": "", "previewImages": [], "message": "字体生成失败: " + str(e)}}
    print(json.dumps(result))
"#,
        project_root.display(),
        chars_json.replace('\'', "\\'").replace('"', "\\\""),
        params_json.replace('\'', "\\'").replace('"', "\\\""),
        font_name,
        author,
        output_dir.display()
    );

    let output = Command::new(&python)
        .args(["-c", &script])
        .output()
        .map_err(|e| format!("Failed to run Python: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Python error: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let result: GenerateResult =
        serde_json::from_str(stdout.trim()).map_err(|e| format!("Parse error: {}", e))?;

    Ok(result)
}

/// Read TTF file as bytes for export
#[tauri::command]
async fn read_ttf_file(path: String) -> Result<Vec<u8>, String> {
    fs::read(&path).map_err(|e| format!("Failed to read TTF: {}", e))
}

/// Preview a processed glyph
#[tauri::command]
async fn preview_glyph(
    image_path: String,
    stroke_width: f64,
    smoothness: f64,
    ink_density: f64,
) -> Result<String, String> {
    let python = find_python();
    let project_root = get_project_root();

    let script = format!(
        r#"
import sys
sys.path.insert(0, r"{}")

try:
    from src.writefont.preview import generate_preview
    result = generate_preview(r"{}"), {}, {}, {})
    print(result)
except Exception:
    print(r"{}")
"#,
        project_root.display(),
        image_path,
        stroke_width,
        smoothness,
        ink_density,
        image_path
    );

    let output = Command::new(&python)
        .args(["-c", &script])
        .output()
        .map_err(|e| format!("Failed to run Python: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Python error: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(stdout)
}

/// Check Python environment
#[tauri::command]
async fn check_python_env() -> Result<PythonEnv, String> {
    let python = find_python();

    let output = Command::new(&python)
        .args(["--version"])
        .output()
        .map_err(|e| format!("Python not found: {}", e))?;

    let version = String::from_utf8_lossy(&output.stdout).trim().to_string();

    // Check for required packages
    let check_output = Command::new(&python)
        .args([
            "-c",
            "import PIL; from fontTools.ttLib import TTFont; print('ok')",
        ])
        .output();

    let packages_ok = check_output
        .map(|o| o.status.success())
        .unwrap_or(false);

    if packages_ok {
        Ok(PythonEnv {
            available: true,
            version: version.clone(),
            message: format!("{} (Pillow ✓, fontTools ✓)", version),
        })
    } else {
        Ok(PythonEnv {
            available: true,
            version: version.clone(),
            message: format!("{} (建议安装: pip install Pillow fonttools)", version),
        })
    }
}

/// Get the Python path being used
#[tauri::command]
async fn get_python_path() -> Result<String, String> {
    Ok(find_python())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            process_character_image,
            generate_font,
            read_ttf_file,
            preview_glyph,
            check_python_env,
            get_python_path,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
