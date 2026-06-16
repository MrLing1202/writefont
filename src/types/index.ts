export interface FontParams {
  strokeWidth: number; // 笔画粗细 1-10
  smoothness: number; // 平滑度 0-100
  spacing: number; // 字间距 0-100
  baseline: number; // 基线偏移 -20 to 20
  inkDensity: number; // 墨迹浓度 1-100
  style: "regular" | "bold" | "light";
}

export interface CharacterImage {
  char: string;
  imagePath: string;
  processed: boolean;
}

export interface ProjectConfig {
  name: string;
  author: string;
  description: string;
  characters: CharacterImage[];
  params: FontParams;
}

export type AppStep = "upload" | "adjust" | "preview" | "export";

export interface GenerateResult {
  success: boolean;
  ttfPath: string;
  previewImages: string[];
  message: string;
}

export const DEFAULT_PARAMS: FontParams = {
  strokeWidth: 5,
  smoothness: 70,
  spacing: 10,
  baseline: 0,
  inkDensity: 80,
  style: "regular",
};

export const SAMPLE_CHARS = [
  "永",
  "东",
  "国",
  "风",
  "华",
  "龙",
  "凤",
  "书",
  "法",
  "墨",
  "笔",
  "纸",
  "砚",
  "春",
  "夏",
  "秋",
  "冬",
  "山",
  "水",
  "云",
  "天",
  "地",
  "人",
  "和",
];
