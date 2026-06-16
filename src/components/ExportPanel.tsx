import { useState } from "react";
import { motion } from "framer-motion";
import {
  ArrowLeft,
  Download,
  Check,
  FileText,
  Copy,
  Share2,
  Printer,
} from "lucide-react";
import { exportTtf } from "../hooks/useWriteFont";
import toast from "react-hot-toast";

interface Props {
  state: any;
}

export default function ExportPanel({ state }: Props) {
  const { generatedTtfPath, fontName, characters, params, setStep } = state;
  const [exported, setExported] = useState(false);
  const [isExporting, setIsExporting] = useState(false);

  const handleExport = async () => {
    if (!generatedTtfPath) {
      toast.error("请先生成字体");
      return;
    }
    setIsExporting(true);
    try {
      const success = await exportTtf(generatedTtfPath);
      if (success) {
        setExported(true);
        toast.success("字体已导出！");
      }
    } catch (e: any) {
      toast.error("导出失败: " + (e.message || e));
    }
    setIsExporting(false);
  };

  const handleCopyPath = () => {
    if (generatedTtfPath) {
      navigator.clipboard.writeText(generatedTtfPath);
      toast.success("路径已复制");
    }
  };

  return (
    <div className="h-full flex flex-col p-6 gap-6">
      <div className="text-center">
        <h2 className="text-2xl font-brush text-ink-800 mb-2">导出字体文件</h2>
        <p className="text-ink-400 text-sm">
          将生成的字体保存为 TTF 文件，可在任何应用中使用
        </p>
      </div>

      <div className="flex-1 flex items-center justify-center">
        <div className="max-w-lg w-full space-y-6">
          {/* Success animation */}
          {exported && (
            <motion.div
              initial={{ scale: 0 }}
              animate={{ scale: 1 }}
              transition={{ type: "spring", stiffness: 200, damping: 15 }}
              className="flex justify-center mb-6"
            >
              <div className="w-20 h-20 bg-green-100 rounded-full flex items-center justify-center">
                <Check size={40} className="text-green-600" />
              </div>
            </motion.div>
          )}

          {/* Font info card */}
          <div className="bg-white rounded-xl p-6 border border-ink-100 shadow-sm">
            <div className="flex items-start gap-4">
              <div className="w-16 h-16 ink-wash rounded-xl flex items-center justify-center">
                <FileText size={28} className="text-paper-100" />
              </div>
              <div className="flex-1">
                <h3 className="text-lg font-medium text-ink-800">{fontName}</h3>
                <p className="text-sm text-ink-400 mt-1">
                  {characters.length} 个字符 ·{" "}
                  {params.style === "light"
                    ? "纤细"
                    : params.style === "regular"
                    ? "常规"
                    : "粗体"}{" "}
                  · TTF 格式
                </p>
                {generatedTtfPath && (
                  <p className="text-xs text-ink-300 mt-2 font-mono truncate">
                    {generatedTtfPath}
                  </p>
                )}
              </div>
            </div>
          </div>

          {/* Character preview */}
          <div className="bg-white rounded-xl p-5 border border-ink-100 shadow-sm">
            <h3 className="text-sm font-medium text-ink-600 mb-3">字符集预览</h3>
            <div className="flex flex-wrap gap-2">
              {characters.map((char: any) => (
                <div
                  key={char.char}
                  className="w-10 h-10 bg-paper-50 rounded-lg border border-ink-100 flex items-center justify-center text-lg font-brush"
                >
                  {char.char}
                </div>
              ))}
            </div>
          </div>

          {/* Export button */}
          <button
            onClick={handleExport}
            disabled={isExporting || !generatedTtfPath}
            className={`w-full py-4 rounded-xl font-medium text-lg transition-all flex items-center justify-center gap-3 ${
              exported
                ? "bg-green-600 text-white hover:bg-green-500"
                : isExporting
                ? "bg-ink-300 text-ink-500 cursor-wait"
                : "btn-ink bg-ink-800 text-paper-100 hover:bg-ink-700 shadow-ink"
            }`}
          >
            {exported ? (
              <>
                <Check size={20} />
                导出成功！再次导出
              </>
            ) : isExporting ? (
              <>
                <motion.div
                  animate={{ rotate: 360 }}
                  transition={{ repeat: Infinity, duration: 1, ease: "linear" }}
                >
                  <Download size={20} />
                </motion.div>
                导出中...
              </>
            ) : (
              <>
                <Download size={20} />
                导出 TTF 文件
              </>
            )}
          </button>

          {/* Actions */}
          {generatedTtfPath && (
            <div className="flex gap-3">
              <button
                onClick={handleCopyPath}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg bg-paper-100 text-ink-600 hover:bg-paper-200 transition-colors text-sm border border-ink-100"
              >
                <Copy size={14} />
                复制路径
              </button>
              <button
                onClick={() => setStep("preview")}
                className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-lg bg-paper-100 text-ink-600 hover:bg-paper-200 transition-colors text-sm border border-ink-100"
              >
                <Share2 size={14} />
                返回预览
              </button>
            </div>
          )}

          {/* Tips */}
          <div className="bg-paper-100 rounded-xl p-4 border border-ink-50">
            <h4 className="text-sm font-medium text-ink-600 mb-2">💡 使用提示</h4>
            <ul className="text-xs text-ink-400 space-y-1.5">
              <li>• 双击 TTF 文件即可安装到系统字体库</li>
              <li>• macOS: 字体册 → 添加字体 → 选择 TTF 文件</li>
              <li>• Windows: 右键 TTF → 为所有用户安装</li>
              <li>• 安装后可在 Word、Photoshop 等软件中使用</li>
              <li>• 如需商用，请确保手写字体内容的原创性</li>
            </ul>
          </div>

          {/* Back button */}
          <div className="text-center">
            <button
              onClick={() => setStep("upload")}
              className="text-sm text-ink-400 hover:text-ink-600 transition-colors flex items-center gap-1 mx-auto"
            >
              <ArrowLeft size={14} />
              返回上传新字体
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
