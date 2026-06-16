import { useState } from "react";
import { motion } from "framer-motion";
import { ArrowLeft, ArrowRight, RefreshCw, ZoomIn, ZoomOut } from "lucide-react";
import { generateFont } from "../hooks/useWriteFont";
import toast from "react-hot-toast";

interface Props {
  state: any;
}

const PREVIEW_TEXTS = [
  "永东国风华龙凤书法",
  "床前明月光疑是地上霜",
  "春眠不觉晓处处闻啼鸟",
  "白日依山尽黄河入海流",
  "千山鸟飞绝万径人踪灭",
  "锄禾日当午汗滴禾下土",
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
  "abcdefghijklmnopqrstuvwxyz",
  "0123456789",
  "你好世界Hello World",
];

export default function PreviewPanel({ state }: Props) {
  const {
    params,
    characters,
    setStep,
    fontName,
    fontAuthor,
    isProcessing,
    setIsProcessing,
    setGeneratedTtfPath,
    setPreviewImages,
  } = state;
  const [previewSize, setPreviewSize] = useState(32);
  const [selectedText, setSelectedText] = useState(0);
  const [customText, setCustomText] = useState("");
  const [generated, setGenerated] = useState(false);

  const handleGenerate = async () => {
    setIsProcessing(true);
    try {
      const result = await generateFont(characters, params, fontName, fontAuthor);
      if (result.success) {
        setGeneratedTtfPath(result.ttfPath);
        setPreviewImages(result.previewImages);
        setGenerated(true);
        toast.success("字体生成成功！");
      } else {
        toast.error(result.message || "生成失败");
      }
    } catch (e: any) {
      toast.error("字体生成失败: " + (e.message || e));
    }
    setIsProcessing(false);
  };

  return (
    <div className="h-full flex flex-col p-6 gap-6">
      <div className="text-center">
        <h2 className="text-2xl font-brush text-ink-800 mb-2">预览字体效果</h2>
        <p className="text-ink-400 text-sm">
          生成字体并预览效果，满意后可导出 TTF 文件
        </p>
      </div>

      <div className="flex-1 flex gap-6 overflow-hidden">
        {/* Left: Controls */}
        <div className="w-72 flex flex-col gap-4 overflow-auto">
          {/* Generate button */}
          <button
            onClick={handleGenerate}
            disabled={isProcessing}
            className={`w-full py-3 rounded-xl font-medium text-lg transition-all ${
              isProcessing
                ? "bg-ink-300 text-ink-500 cursor-wait"
                : generated
                ? "bg-green-700 text-white hover:bg-green-600"
                : "btn-ink bg-ink-800 text-paper-100 hover:bg-ink-700 shadow-ink"
            }`}
          >
            {isProcessing ? (
              <span className="flex items-center justify-center gap-2">
                <RefreshCw size={18} className="animate-spin" />
                生成中...
              </span>
            ) : generated ? (
              "✓ 重新生成"
            ) : (
              "开始生成字体"
            )}
          </button>

          {/* Size control */}
          <div className="bg-white rounded-xl p-4 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-3">预览大小</h3>
            <div className="flex items-center gap-3">
              <button
                onClick={() => setPreviewSize((s) => Math.max(12, s - 4))}
                className="p-1.5 rounded-lg hover:bg-paper-200 transition-colors"
              >
                <ZoomOut size={16} className="text-ink-500" />
              </button>
              <input
                type="range"
                min={12}
                max={120}
                value={previewSize}
                onChange={(e) => setPreviewSize(Number(e.target.value))}
                className="flex-1"
              />
              <button
                onClick={() => setPreviewSize((s) => Math.min(120, s + 4))}
                className="p-1.5 rounded-lg hover:bg-paper-200 transition-colors"
              >
                <ZoomIn size={16} className="text-ink-500" />
              </button>
              <span className="text-xs font-mono text-ink-500 w-10 text-right">
                {previewSize}px
              </span>
            </div>
          </div>

          {/* Sample texts */}
          <div className="bg-white rounded-xl p-4 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-3">预览文本</h3>
            <div className="space-y-1.5 max-h-[300px] overflow-auto">
              {PREVIEW_TEXTS.map((text, idx) => (
                <button
                  key={idx}
                  onClick={() => setSelectedText(idx)}
                  className={`w-full text-left px-3 py-2 rounded-lg text-sm transition-colors ${
                    selectedText === idx
                      ? "bg-ink-800 text-paper-100"
                      : "hover:bg-paper-200 text-ink-600"
                  }`}
                >
                  {text}
                </button>
              ))}
            </div>
          </div>

          {/* Custom text */}
          <div className="bg-white rounded-xl p-4 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-3">自定义文本</h3>
            <textarea
              value={customText}
              onChange={(e) => setCustomText(e.target.value)}
              placeholder="输入要预览的文字..."
              className="w-full px-3 py-2 border border-ink-200 rounded-lg text-sm focus:outline-none focus:border-ink-500 bg-paper-50 resize-none h-20"
            />
          </div>

          {/* Stats */}
          <div className="bg-white rounded-xl p-4 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-2">字体信息</h3>
            <div className="space-y-1.5 text-xs text-ink-500">
              <div className="flex justify-between">
                <span>字符数</span>
                <span className="text-ink-700">{characters.length}</span>
              </div>
              <div className="flex justify-between">
                <span>字体名称</span>
                <span className="text-ink-700">{fontName}</span>
              </div>
              <div className="flex justify-between">
                <span>风格</span>
                <span className="text-ink-700">
                  {params.style === "light"
                    ? "纤细"
                    : params.style === "regular"
                    ? "常规"
                    : "粗体"}
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Right: Preview area */}
        <div className="flex-1 flex flex-col gap-4 overflow-auto">
          <div className="bg-white rounded-xl p-6 border border-ink-100 shadow-sm flex-1">
            <div className="xuan-paper rounded-lg p-8 min-h-[400px]">
              {!generated ? (
                <div className="h-full flex flex-col items-center justify-center text-ink-300">
                  <motion.div
                    animate={{ rotate: [0, 5, -5, 0] }}
                    transition={{ repeat: Infinity, duration: 3 }}
                  >
                    <span className="text-6xl font-brush">墨</span>
                  </motion.div>
                  <p className="mt-4 text-sm">点击「开始生成字体」查看效果</p>
                </div>
              ) : (
                <div className="space-y-8">
                  {/* Main preview text */}
                  <div>
                    <p className="text-ink-400 text-xs mb-3">字体预览</p>
                    <p
                      className="leading-relaxed"
                      style={{
                        fontFamily: fontName,
                        fontSize: `${previewSize}px`,
                        letterSpacing: `${params.spacing}px`,
                        lineHeight: 1.8,
                      }}
                    >
                      {customText || PREVIEW_TEXTS[selectedText]}
                    </p>
                  </div>

                  {/* Multi-size preview */}
                  <div className="pt-6 border-t border-ink-100/30">
                    <p className="text-ink-400 text-xs mb-3">多尺寸预览</p>
                    {[16, 24, 32, 48, 64].map((size) => (
                      <div key={size} className="mb-3">
                        <span className="text-xs text-ink-300 mr-2">{size}px</span>
                        <span
                          style={{
                            fontFamily: fontName,
                            fontSize: `${size}px`,
                            letterSpacing: `${params.spacing * 0.5}px`,
                          }}
                        >
                          永东国风华龙凤
                        </span>
                      </div>
                    ))}
                  </div>

                  {/* Pangram */}
                  <div className="pt-6 border-t border-ink-100/30">
                    <p className="text-ink-400 text-xs mb-3">完整字符集</p>
                    <p
                      className="text-xl leading-loose break-all"
                      style={{
                        fontFamily: fontName,
                        letterSpacing: `${params.spacing * 0.3}px`,
                      }}
                    >
                      {characters.map((c: any) => c.char).join(" ")}
                    </p>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Bottom actions */}
      <div className="flex items-center justify-between pt-4 border-t border-ink-100">
        <button
          onClick={() => setStep("adjust")}
          className="flex items-center gap-2 px-5 py-2.5 rounded-lg text-ink-600 hover:bg-paper-200 transition-colors"
        >
          <ArrowLeft size={16} />
          返回调整
        </button>
        <button
          onClick={() => setStep("export")}
          disabled={!generated}
          className={`btn-ink flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium transition-all ${
            generated
              ? "bg-ink-800 text-paper-100 hover:bg-ink-700 shadow-ink"
              : "bg-ink-200 text-ink-400 cursor-not-allowed"
          }`}
        >
          下一步：导出字体
          <ArrowRight size={16} />
        </button>
      </div>
    </div>
  );
}
