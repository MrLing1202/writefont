#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

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
    for name in &["python3", "python"] {
        if let Ok(output) = Command::new(name).arg("--version").output() {
            if output.status.success() {
                return name.to_string();
            }
        }
    }
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
    let dev_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf();
    if dev_root.join("src").join("writefont").exists() {
        return dev_root;
    }

    if let Ok(exe_path) = std::env::current_exe() {
        let exe_dir = exe_path.parent().unwrap();
        let resource_dir = exe_dir.join("../Resources");
        if resource_dir.join("writefont").exists() {
            return resource_dir;
        }
        if exe_dir.join("writefont").exists() {
            return exe_dir.to_path_buf();
        }
    }

    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

/// Run a Python script with JSON data passed via stdin (C-1: prevents injection)
fn run_python_with_stdin(
    script: &str,
    stdin_data: &serde_json::Value,
) -> Result<String, String> {
    let python = find_python();
    let output = Command::new(&python)
        .args(["-c", script])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to spawn Python: {}", e))
        .and_then(|mut child| {
            if let Some(ref mut stdin) = child.stdin {
                let data = serde_json::to_string(stdin_data)
                    .map_err(|e| format!("JSON serialize error: {}", e))?;
                stdin
                    .write_all(data.as_bytes())
                    .map_err(|e| format!("Failed to write stdin: {}", e))?;
            }
            child
                .wait_with_output()
                .map_err(|e| format!("Failed to run Python: {}", e))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Python error: {}", stderr));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
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
    let project_root = get_project_root();
    let project_root_str = project_root.to_string_lossy().to_string();

    // C-1: Pass all user input via JSON stdin, not format!()
    let script = r#"
import sys
import os
import json
import base64
import tempfile
import io

data = json.load(sys.stdin)
sys.path.insert(0, data["project_root"])

image_path = data["image_path"]
char = data["char"]
stroke_width = data["stroke_width"]
smoothness = data["smoothness"]
ink_density = data["ink_density"]

try:
    from src.writefont.core import process_character
    result = process_character(image_path, char, stroke_width, smoothness, ink_density)
    print(json.dumps(result))
except ImportError:
    try:
        from PIL import Image, ImageFilter, ImageEnhance
        
        if image_path.startswith("data:"):
            header, img_data = image_path.split(",", 1)
            img_bytes = base64.b64decode(img_data)
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
        output_path = os.path.join(output_dir, "char_{}.png".format(safe_char))
        img.save(output_path)
        
        result = {"char": char, "processed_path": output_path}
        print(json.dumps(result))
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
"#;

    let stdin_data = serde_json::json!({
        "project_root": project_root_str,
        "image_path": image_path,
        "char": char,
        "stroke_width": stroke_width,
        "smoothness": smoothness,
        "ink_density": ink_density
    });

    let stdout = run_python_with_stdin(script, &stdin_data)?;
    let result: serde_json::Value =
        serde_json::from_str(&stdout).map_err(|e| format!("Parse error: {}", e))?;

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
    let project_root = get_project_root();
    let project_root_str = project_root.to_string_lossy().to_string();
    let output_dir = std::env::temp_dir().join("writefont_output");
    fs::create_dir_all(&output_dir).map_err(|e| e.to_string())?;
    let output_dir_str = output_dir.to_string_lossy().to_string();

    // C-1: All data passed via JSON stdin — no format!() with user input
    let script = r#"
import sys
import os
import json

data = json.load(sys.stdin)
sys.path.insert(0, data["project_root"])

chars_data = data["characters"]
params_data = data["params"]
font_name = data["font_name"]
author = data["author"]
output_dir = data["output_dir"]

try:
    from src.writefont.font_generator import generate_ttf
    ttf_path = generate_ttf(chars_data, params_data, font_name, author, output_dir)
    result = {"success": True, "ttfPath": ttf_path, "previewImages": [], "message": "字体生成成功"}
    print(json.dumps(result))
except ImportError:
    try:
        from fontTools.fontBuilder import FontBuilder
        
        char_list = [c["char"] for c in chars_data]
        fb = FontBuilder(1000, isTTF=True)
        glyph_order = [".notdef"] + char_list
        fb.setupGlyphOrder(glyph_order)
        
        cmap = {0: ".notdef"}
        for c in char_list:
            cmap[ord(c)] = c
        fb.setupCharacterMap(cmap)
        
        glyf = {".notdef": {}}
        for c in char_list:
            glyf[c] = {}
        fb.setupGlyf(glyf)
        
        spacing = params_data.get("spacing", 10)
        advance_width = max(400, 1000 - int(spacing * 5))
        metrics = {".notdef": (500, 0)}
        for c in char_list:
            metrics[c] = (advance_width, 0)
        fb.setupHorizontalMetrics(metrics)
        
        fb.setupHorizontalHeader(ascent=800, descent=-200)
        
        style = params_data.get("style", "Regular").capitalize()
        if style not in ["Regular", "Bold", "Light"]:
            style = "Regular"
        fb.setupNameTable({"familyName": font_name, "styleName": style})
        
        fb.setupOs2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=1000, usWinDescent=200)
        fb.setupPost()
        
        os.makedirs(output_dir, exist_ok=True)
        ttf_path = os.path.join(output_dir, font_name + ".ttf")
        fb.font.save(ttf_path)
        
        result = {"success": True, "ttfPath": ttf_path, "previewImages": [], "message": "字体生成成功（基础模式）"}
        print(json.dumps(result))
    except Exception as e:
        result = {"success": False, "ttfPath": "", "previewImages": [], "message": "字体生成失败: " + str(e)}
        print(json.dumps(result))
except Exception as e:
    result = {"success": False, "ttfPath": "", "previewImages": [], "message": "字体生成失败: " + str(e)}
    print(json.dumps(result))
"#;

    let stdin_data = serde_json::json!({
        "project_root": project_root_str,
        "characters": characters,
        "params": params,
        "font_name": font_name,
        "author": author,
        "output_dir": output_dir_str
    });

    let stdout = run_python_with_stdin(script, &stdin_data)?;
    let result: GenerateResult =
        serde_json::from_str(&stdout).map_err(|e| format!("Parse error: {}", e))?;

    Ok(result)
}

/// C-4: Validate that a path is inside the allowed output directory
fn validate_output_path(path: &str) -> Result<PathBuf, String> {
    let output_dir = std::env::temp_dir().join("writefont_output");
    let canonical_output = fs::canonicalize(&output_dir)
        .map_err(|_| "Output directory does not exist".to_string())?;

    let target = PathBuf::from(path);
    let canonical_target = fs::canonicalize(&target)
        .map_err(|e| format!("Invalid path: {}", e))?;

    if !canonical_target.starts_with(&canonical_output) {
        return Err("Access denied: path is outside allowed output directory".to_string());
    }

    // Also verify it's a .ttf file
    if canonical_target.extension().map_or(true, |ext| ext != "ttf") {
        return Err("Only .ttf files can be read".to_string());
    }

    Ok(canonical_target)
}

/// Read TTF file as bytes for export (C-4: path whitelist)
#[tauri::command]
async fn read_ttf_file(path: String) -> Result<Vec<u8>, String> {
    let validated = validate_output_path(&path)?;
    fs::read(&validated).map_err(|e| format!("Failed to read TTF: {}", e))
}

/// Preview a processed glyph
#[tauri::command]
async fn preview_glyph(
    image_path: String,
    stroke_width: f64,
    smoothness: f64,
    ink_density: f64,
) -> Result<String, String> {
    let project_root = get_project_root();
    let project_root_str = project_root.to_string_lossy().to_string();

    // C-1: Pass all data via JSON stdin
    let script = r#"
import sys
import json

data = json.load(sys.stdin)
sys.path.insert(0, data["project_root"])

image_path = data["image_path"]

try:
    from src.writefont.preview import generate_preview
    result = generate_preview(image_path, data["stroke_width"], data["smoothness"], data["ink_density"])
    print(result)
except Exception:
    print(image_path)
"#;

    let stdin_data = serde_json::json!({
        "project_root": project_root_str,
        "image_path": image_path,
        "stroke_width": stroke_width,
        "smoothness": smoothness,
        "ink_density": ink_density
    });

    let stdout = run_python_with_stdin(script, &stdin_data)?;
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

/// M-7: Clean up old temp files (older than 24 hours)
fn cleanup_temp_output() {
    let output_dir = std::env::temp_dir().join("writefont_output");
    if !output_dir.exists() {
        return;
    }
    if let Ok(entries) = fs::read_dir(&output_dir) {
        let cutoff = std::time::SystemTime::now() - std::time::Duration::from_secs(24 * 3600);
        for entry in entries.flatten() {
            if let Ok(metadata) = entry.metadata() {
                if let Ok(modified) = metadata.modified() {
                    if modified < cutoff {
                        let _ = fs::remove_file(entry.path());
                    }
                }
            }
        }
    }
}

fn main() {
    // M-7: Clean up old temp files on startup
    cleanup_temp_output();

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
