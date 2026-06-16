import { useCallback, useState, useMemo, useEffect } from "react";
import { useDropzone } from "react-dropzone";
import { motion, AnimatePresence } from "framer-motion";
import { Upload, X, ImagePlus, ArrowRight, Sparkles, Trash2 } from "lucide-react";
import toast from "react-hot-toast";
import { processImage } from "../hooks/useWriteFont";
import { SAMPLE_CHARS } from "../types";
import type { CharacterImage, AppState } from "../types";

interface Props {
  state: AppState;
}

export default function UploadPanel({ state }: Props) {
  const { characters, addCharacter, removeCharacter, clearCharacters, setStep, params } =
    state;
  const [assignChar, setAssignChar] = useState("");
  const [pendingFiles, setPendingFiles] = useState<File[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);

  const onDrop = useCallback(
    async (acceptedFiles: File[]) => {
      if (acceptedFiles.length === 0) return;

      // If we have a single character assigned, process immediately
      if (assignChar && acceptedFiles.length === 1) {
        setIsProcessing(true);
        try {
          const file = acceptedFiles[0];
          const arrayBuffer = await file.arrayBuffer();
          const uint8 = new Uint8Array(arrayBuffer);
          // Convert to base64 for passing to backend
          const base64 = btoa(
            uint8.reduce((data, byte) => data + String.fromCharCode(byte), "")
          );
          const result = await processImage(
            `data:image/png;base64,${base64}`,
            assignChar,
            params
          );
          addCharacter(result);
          toast.success(`已添加字符「${assignChar}」`);
          setAssignChar("");
        } catch (e) {
          toast.error("处理图片失败");
        }
        setIsProcessing(false);
        return;
      }

      // Otherwise, queue files for assignment
      setPendingFiles((prev) => [...prev, ...acceptedFiles]);
      if (!assignChar) {
        toast("请为每张图片指定对应汉字", { icon: "✍️" });
      }
    },
    [assignChar, params, addCharacter]
  );

  const processPendingFile = async (file: File, char: string) => {
    setIsProcessing(true);
    try {
      const arrayBuffer = await file.arrayBuffer();
      const uint8 = new Uint8Array(arrayBuffer);
      const base64 = btoa(
        uint8.reduce((data, byte) => data + String.fromCharCode(byte), "")
      );
      const result = await processImage(
        `data:image/png;base64,${base64}`,
        char,
        params
      );
      addCharacter(result);
      setPendingFiles((prev) => prev.filter((f) => f !== file));
      toast.success(`已添加字符「${char}」`);
    } catch (e) {
      toast.error("处理图片失败");
    }
    setIsProcessing(false);
  };

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      "image/*": [".png", ".jpg", ".jpeg", ".bmp", ".webp"],
    },
    multiple: true,
  });

  const canProceed = characters.length >= 10;

  // M-3: Memoize and revoke object URLs to prevent memory leaks
  const pendingFileUrls = useMemo(
    () => pendingFiles.map((f) => URL.createObjectURL(f)),
    [pendingFiles]
  );
  useEffect(() => {
    return () => {
      pendingFileUrls.forEach((url) => URL.revokeObjectURL(url));
    };
  }, [pendingFileUrls]);

  return (
    <div className="h-full flex flex-col p-6 gap-6">
      {/* Header */}
      <div className="text-center">
        <h2 className="text-2xl font-brush text-ink-800 mb-2">上传手写字图片</h2>
        <p className="text-ink-400 text-sm">
          上传您手写汉字的照片，每个汉字对应一张图片。建议至少上传 10 个字符以获得更好效果。
        </p>
      </div>

      <div className="flex-1 flex gap-6 overflow-hidden">
        {/* Left: Drop zone */}
        <div className="flex-1 flex flex-col gap-4">
          <div
            {...getRootProps()}
            className={`xuan-paper border-2 border-dashed rounded-xl p-8 flex flex-col items-center justify-center gap-4 cursor-pointer transition-all duration-300 min-h-[200px] ${
              isDragActive
                ? "border-ink-600 bg-ink-50/50 scale-[1.02]"
                : "border-ink-200 hover:border-ink-400 hover:bg-paper-100"
            }`}
          >
            <input {...getInputProps()} />
            <motion.div
              animate={isDragActive ? { scale: 1.1, rotate: 5 } : { scale: 1, rotate: 0 }}
              transition={{ type: "spring", stiffness: 300 }}
            >
              {isDragActive ? (
                <Sparkles size={48} className="text-ink-500" />
              ) : (
                <ImagePlus size={48} className="text-ink-300" />
              )}
            </motion.div>
            <div className="text-center">
              <p className="text-ink-600 font-medium">
                {isDragActive ? "松手上传图片" : "拖拽图片到此处"}
              </p>
              <p className="text-ink-300 text-sm mt-1">
                支持 PNG、JPG、BMP、WebP 格式
              </p>
            </div>
          </div>

          {/* Pending files */}
          {pendingFiles.length > 0 && (
            <div className="bg-paper-100 rounded-lg p-4 border border-ink-100">
              <h4 className="text-sm font-medium text-ink-600 mb-3">
                待分配图片 ({pendingFiles.length})
              </h4>
              <div className="space-y-2 max-h-[200px] overflow-auto">
                {pendingFiles.map((file, idx) => (
                  <div
                    key={idx}
                    className="flex items-center gap-3 bg-white rounded-lg p-2 border border-ink-50"
                  >
                    <img
                      src={pendingFileUrls[idx]}
                      alt={file.name}
                      className="w-10 h-10 object-cover rounded"
                    />
                    <span className="text-sm text-ink-600 flex-1 truncate">
                      {file.name}
                    </span>
                    <input
                      type="text"
                      placeholder="输入对应汉字"
                      maxLength={1}
                      className="w-20 px-2 py-1 text-center border border-ink-200 rounded text-sm focus:outline-none focus:border-ink-500"
                      onKeyDown={(e) => {
                        if (e.key === "Enter" && e.currentTarget.value) {
                          processPendingFile(file, e.currentTarget.value);
                        }
                      }}
                    />
                    <button
                      onClick={(e) => {
                        const input = (e.currentTarget as HTMLElement).closest("div")
                          ?.querySelector("input") as HTMLInputElement;
                        if (input?.value) {
                          processPendingFile(file, input.value);
                        }
                      }}
                      className="px-3 py-1 bg-ink-800 text-paper-100 rounded text-xs hover:bg-ink-700 transition-colors"
                    >
                      确认
                    </button>
                    <button
                      onClick={() =>
                        setPendingFiles((prev) => prev.filter((_, i) => i !== idx))
                      }
                      className="text-ink-300 hover:text-red-500 transition-colors"
                    >
                      <X size={16} />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Right: Character grid */}
        <div className="w-80 flex flex-col gap-4">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-brush text-ink-700">
              已收集 ({characters.length})
            </h3>
            {characters.length > 0 && (
              <button
                onClick={clearCharacters}
                className="text-xs text-ink-400 hover:text-red-500 flex items-center gap-1 transition-colors"
              >
                <Trash2 size={12} />
                清空
              </button>
            )}
          </div>

          <div className="flex-1 overflow-auto bg-paper-100 rounded-xl p-4 border border-ink-100">
            {characters.length === 0 ? (
              <div className="h-full flex flex-col items-center justify-center text-ink-300">
                <Upload size={32} className="mb-2 opacity-50" />
                <p className="text-sm">暂无字符</p>
                <p className="text-xs mt-1">上传图片并分配汉字</p>
              </div>
            ) : (
              <div className="grid grid-cols-4 gap-3">
                <AnimatePresence>
                  {characters.map((char: CharacterImage) => (
                    <motion.div
                      key={char.char}
                      initial={{ scale: 0, opacity: 0 }}
                      animate={{ scale: 1, opacity: 1 }}
                      exit={{ scale: 0, opacity: 0 }}
                      className="relative group"
                    >
                      <div className="aspect-square bg-white rounded-lg border border-ink-100 overflow-hidden shadow-sm hover:shadow-ink transition-shadow">
                        {char.imagePath.startsWith("data:") ? (
                          <img
                            src={char.imagePath}
                            alt={char.char}
                            className="w-full h-full object-cover"
                          />
                        ) : (
                          <div className="w-full h-full flex items-center justify-center text-2xl font-brush text-ink-600">
                            {char.char}
                          </div>
                        )}
                      </div>
                      <span className="absolute bottom-0 left-0 right-0 text-center text-xs bg-black/60 text-white py-0.5">
                        {char.char}
                      </span>
                      <button
                        onClick={() => removeCharacter(char.char)}
                        className="absolute -top-1 -right-1 w-5 h-5 bg-red-500 text-white rounded-full flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                      >
                        <X size={10} />
                      </button>
                    </motion.div>
                  ))}
                </AnimatePresence>
              </div>
            )}
          </div>

          {/* Quick add reference */}
          <div className="bg-paper-100 rounded-lg p-3 border border-ink-100">
            <p className="text-xs text-ink-400 mb-2">参考字符（点击复制）</p>
            <div className="flex flex-wrap gap-1">
              {SAMPLE_CHARS.slice(0, 12).map((char) => (
                <button
                  key={char}
                  onClick={() => {
                    navigator.clipboard.writeText(char);
                    toast.success(`已复制「${char}」`);
                  }}
                  className="w-7 h-7 flex items-center justify-center text-sm hover:bg-ink-100 rounded transition-colors text-ink-600"
                >
                  {char}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      {/* Bottom action */}
      <div className="flex items-center justify-between pt-4 border-t border-ink-100">
        <p className="text-sm text-ink-400">
          {characters.length < 10
            ? `还需上传至少 ${10 - characters.length} 个字符`
            : "已达到最低要求，可以继续添加更多字符"}
        </p>
        <button
          onClick={() => setStep("adjust")}
          disabled={!canProceed}
          className={`btn-ink flex items-center gap-2 px-6 py-2.5 rounded-lg font-medium transition-all ${
            canProceed
              ? "bg-ink-800 text-paper-100 hover:bg-ink-700 shadow-ink"
              : "bg-ink-200 text-ink-400 cursor-not-allowed"
          }`}
        >
          下一步：调整参数
          <ArrowRight size={16} />
        </button>
      </div>
    </div>
  );
}
