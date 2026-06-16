import { useState } from "react";
import { motion } from "framer-motion";
import {
  ArrowLeft,
  ArrowRight,
  PenTool,
  Droplets,
  Move,
  AlignVerticalSpaceAround,
  Palette,
} from "lucide-react";
import type { FontParams, AppState, CharacterImage } from "../types";

interface Props {
  state: AppState;
}

export default function AdjustPanel({ state }: Props) {
  const { params, setParams, characters, setStep, fontName, setFontName, fontAuthor, setFontAuthor } = state;

  const updateParam = <K extends keyof FontParams>(key: K, value: FontParams[K]) => {
    setParams((prev: FontParams) => ({ ...prev, [key]: value }));
  };

  return (
    <div className="h-full flex flex-col p-6 gap-6">
      <div className="text-center">
        <h2 className="text-2xl font-brush text-ink-800 mb-2">调整字体参数</h2>
        <p className="text-ink-400 text-sm">
          微调笔画、间距、浓度等参数，实时预览效果
        </p>
      </div>

      <div className="flex-1 flex gap-6 overflow-hidden">
        {/* Left: Controls */}
        <div className="w-96 flex flex-col gap-5 overflow-auto pr-2">
          {/* Font Info */}
          <div className="bg-white rounded-xl p-5 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-4 flex items-center gap-2">
              <PenTool size={14} />
              字体信息
            </h3>
            <div className="space-y-3">
              <div>
                <label className="text-xs text-ink-400 block mb-1">字体名称</label>
                <input
                  type="text"
                  value={fontName}
                  onChange={(e) => setFontName(e.target.value)}
                  className="w-full px-3 py-2 border border-ink-200 rounded-lg text-sm focus:outline-none focus:border-ink-500 bg-paper-50"
                  placeholder="我的手写字体"
                />
              </div>
              <div>
                <label className="text-xs text-ink-400 block mb-1">作者</label>
                <input
                  type="text"
                  value={fontAuthor}
                  onChange={(e) => setFontAuthor(e.target.value)}
                  className="w-full px-3 py-2 border border-ink-200 rounded-lg text-sm focus:outline-none focus:border-ink-500 bg-paper-50"
                  placeholder="您的名字"
                />
              </div>
            </div>
          </div>

          {/* Style Selection */}
          <div className="bg-white rounded-xl p-5 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-4 flex items-center gap-2">
              <Palette size={14} />
              风格
            </h3>
            <div className="flex gap-2">
              {(["light", "regular", "bold"] as const).map((style) => (
                <button
                  key={style}
                  onClick={() => updateParam("style", style)}
                  className={`flex-1 py-2 rounded-lg text-sm transition-all ${
                    params.style === style
                      ? "bg-ink-800 text-paper-100 shadow-ink"
                      : "bg-paper-100 text-ink-500 hover:bg-paper-200"
                  }`}
                >
                  {style === "light" ? "纤细" : style === "regular" ? "常规" : "粗体"}
                </button>
              ))}
            </div>
          </div>

          {/* Sliders */}
          <div className="bg-white rounded-xl p-5 border border-ink-100 shadow-sm space-y-5">
            <h3 className="text-sm font-medium text-ink-600 mb-2">笔画参数</h3>

            <ParamSlider
              icon={<PenTool size={14} />}
              label="笔画粗细"
              value={params.strokeWidth}
              min={1}
              max={10}
              step={1}
              onChange={(v) => updateParam("strokeWidth", v)}
              displayValue={`${params.strokeWidth}px`}
            />

            <ParamSlider
              icon={<Droplets size={14} />}
              label="墨迹浓度"
              value={params.inkDensity}
              min={10}
              max={100}
              step={5}
              onChange={(v) => updateParam("inkDensity", v)}
              displayValue={`${params.inkDensity}%`}
            />

            <ParamSlider
              icon={<AlignVerticalSpaceAround size={14} />}
              label="平滑度"
              value={params.smoothness}
              min={0}
              max={100}
              step={5}
              onChange={(v) => updateParam("smoothness", v)}
              displayValue={`${params.smoothness}%`}
            />

            <ParamSlider
              icon={<Move size={14} />}
              label="字间距"
              value={params.spacing}
              min={0}
              max={50}
              step={1}
              onChange={(v) => updateParam("spacing", v)}
              displayValue={`${params.spacing}px`}
            />

            <ParamSlider
              icon={<AlignVerticalSpaceAround size={14} />}
              label="基线偏移"
              value={params.baseline}
              min={-20}
              max={20}
              step={1}
              onChange={(v) => updateParam("baseline", v)}
              displayValue={`${params.baseline > 0 ? "+" : ""}${params.baseline}px`}
            />
          </div>

          {/* Presets */}
          <div className="bg-white rounded-xl p-5 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-3">快速预设</h3>
            <div className="grid grid-cols-2 gap-2">
              {[
                {
                  name: "毛笔楷书",
                  p: { strokeWidth: 7, smoothness: 80, inkDensity: 90, spacing: 10, baseline: 0, style: "regular" as const },
                },
                {
                  name: "钢笔行书",
                  p: { strokeWidth: 3, smoothness: 60, inkDensity: 85, spacing: 8, baseline: 2, style: "regular" as const },
                },
                {
                  name: "铅笔字",
                  p: { strokeWidth: 2, smoothness: 50, inkDensity: 50, spacing: 12, baseline: 0, style: "light" as const },
                },
                {
                  name: "马克笔",
                  p: { strokeWidth: 9, smoothness: 40, inkDensity: 95, spacing: 6, baseline: 0, style: "bold" as const },
                },
              ].map((preset) => (
                <button
                  key={preset.name}
                  onClick={() => setParams((prev: FontParams) => ({ ...prev, ...preset.p }))}
                  className="py-2 px-3 bg-paper-100 rounded-lg text-sm text-ink-600 hover:bg-ink-100 transition-colors border border-ink-50"
                >
                  {preset.name}
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Right: Live preview */}
        <div className="flex-1 flex flex-col gap-4">
          <div className="bg-white rounded-xl p-6 border border-ink-100 shadow-sm flex-1">
            <h3 className="text-sm font-medium text-ink-600 mb-4">实时预览</h3>
            <div className="xuan-paper rounded-lg p-8 min-h-[300px]">
              <div className="text-center">
                <p
                  className="text-4xl leading-relaxed tracking-wider"
                  style={{
                    fontFamily: "Ma Shan Zheng, cursive",
                    letterSpacing: `${params.spacing}px`,
                    opacity: params.inkDensity / 100,
                    filter: `blur(${(100 - params.smoothness) * 0.02}px)`,
                  }}
                >
                  {characters.length > 0
                    ? characters.map((c: { char: string }) => c.char).join("")
                    : "永东国风华龙凤书法墨笔纸砚春夏秋冬山水云天地人和"}
                </p>
              </div>

              {/* Sentence preview */}
              <div className="mt-8 pt-6 border-t border-ink-100/30">
                <p className="text-ink-400 text-xs mb-3">句子预览</p>
                <p
                  className="text-lg leading-loose"
                  style={{
                    fontFamily: "Ma Shan Zheng, cursive",
                    letterSpacing: `${params.spacing * 0.5}px`,
                    opacity: params.inkDensity / 100,
                  }}
                >
                  床前明月光，疑是地上霜。举头望明月，低头思故乡。
                </p>
              </div>
            </div>
          </div>

          {/* Character detail preview */}
          {characters.length > 0 && (
            <div className="bg-white rounded-xl p-5 border border-ink-100 shadow-sm">
              <h3 className="text-sm font-medium text-ink-600 mb-3">字符预览</h3>
              <div className="flex gap-3 overflow-x-auto pb-2">
                {characters.slice(0, 8).map((char: CharacterImage) => (
                  <div
                    key={char.char}
                    className="shrink-0 w-16 h-16 bg-paper-50 rounded-lg border border-ink-100 flex items-center justify-center"
                  >
                    {char.imagePath?.startsWith("data:") ? (
                      <img
                        src={char.imagePath}
                        alt={char.char}
                        className="w-12 h-12 object-contain"
                        style={{
                          filter: `contrast(${params.inkDensity}%) blur(${
                            (100 - params.smoothness) * 0.02
                          }px)`,
                        }}
                      />
                    ) : (
                      <span className="text-2xl font-brush">{char.char}</span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Bottom actions */}
      <div className="flex items-center justify-between pt-4 border-t border-ink-100">
        <button
          onClick={() => setStep("upload")}
          className="flex items-center gap-2 px-5 py-2.5 rounded-lg text-ink-600 hover:bg-paper-200 transition-colors"
        >
          <ArrowLeft size={16} />
          返回上传
        </button>
        <button
          onClick={() => setStep("preview")}
          className="btn-ink flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium bg-ink-800 text-paper-100 hover:bg-ink-700 shadow-ink transition-all"
        >
          下一步：预览字体
          <ArrowRight size={16} />
        </button>
      </div>
    </div>
  );
}

function ParamSlider({
  icon,
  label,
  value,
  min,
  max,
  step,
  onChange,
  displayValue,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
  displayValue: string;
}) {
  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <label className="text-xs text-ink-500 flex items-center gap-1.5">
          {icon}
          {label}
        </label>
        <span className="text-xs font-mono text-ink-600 bg-paper-100 px-2 py-0.5 rounded">
          {displayValue}
        </span>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full"
      />
    </div>
  );
}
