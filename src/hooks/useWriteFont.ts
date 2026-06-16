import { invoke } from "@tauri-apps/api/core";
import { save } from "@tauri-apps/plugin-dialog";
import { writeFile } from "@tauri-apps/plugin-fs";
import type { FontParams, GenerateResult, CharacterImage } from "../types";

export async function processImage(
  imagePath: string,
  char: string,
  params: FontParams
): Promise<CharacterImage> {
  try {
    const result = await invoke<{
      char: string;
      processed_path: string;
    }>("process_character_image", {
      imagePath,
      char,
      strokeWidth: params.strokeWidth,
      smoothness: params.smoothness,
      inkDensity: params.inkDensity,
    });
    return {
      char: result.char,
      imagePath: result.processed_path,
      processed: true,
    };
  } catch (error) {
    console.error("Failed to process image:", error);
    throw error;
  }
}

export async function generateFont(
  characters: CharacterImage[],
  params: FontParams,
  fontName: string,
  author: string
): Promise<GenerateResult> {
  try {
    const result = await invoke<GenerateResult>("generate_font", {
      characters: characters.map((c) => ({
        char: c.char,
        imagePath: c.imagePath,
      })),
      params: {
        strokeWidth: params.strokeWidth,
        smoothness: params.smoothness,
        spacing: params.spacing,
        baseline: params.baseline,
        inkDensity: params.inkDensity,
        style: params.style,
      },
      fontName,
      author,
    });
    return result;
  } catch (error) {
    console.error("Failed to generate font:", error);
    throw error;
  }
}

export async function exportTtf(ttfPath: string): Promise<boolean> {
  try {
    const savePath = await save({
      defaultPath: "writefont.ttf",
      filters: [
        {
          name: "TrueType Font",
          extensions: ["ttf"],
        },
      ],
    });
    if (savePath) {
      const ttfData = await invoke<number[]>("read_ttf_file", { path: ttfPath });
      await writeFile(savePath, new Uint8Array(ttfData));
      return true;
    }
    return false;
  } catch (error) {
    console.error("Failed to export TTF:", error);
    throw error;
  }
}

export async function previewGlyph(
  imagePath: string,
  params: FontParams
): Promise<string> {
  try {
    const result = await invoke<string>("preview_glyph", {
      imagePath,
      strokeWidth: params.strokeWidth,
      smoothness: params.smoothness,
      inkDensity: params.inkDensity,
    });
    return result;
  } catch (error) {
    console.error("Failed to preview glyph:", error);
    throw error;
  }
}

export async function checkPythonEnv(): Promise<{
  available: boolean;
  version: string;
  message: string;
}> {
  try {
    return await invoke("check_python_env");
  } catch {
    return { available: false, version: "", message: "无法检测 Python 环境" };
  }
}

export async function getPythonPath(): Promise<string> {
  try {
    return await invoke<string>("get_python_path");
  } catch {
    return "python3";
  }
}
