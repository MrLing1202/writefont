import { getCurrentWindow } from "@tauri-apps/api/window";
import { Minus, Square, X } from "lucide-react";

export default function TitleBar() {
  const appWindow = getCurrentWindow();

  return (
    <div
      data-tauri-drag-region
      className="h-10 flex items-center justify-between px-4 bg-xuan text-paper-100 select-none shrink-0"
    >
      <div className="flex items-center gap-3">
        <div className="seal-stamp text-xs !border-paper-300 !text-paper-300 !p-1">
          手迹
        </div>
        <span className="text-sm font-brush tracking-wider">手迹造字 WriteFont</span>
      </div>

      <div className="flex items-center gap-1">
        <button
          onClick={() => appWindow.minimize()}
          className="w-8 h-8 flex items-center justify-center hover:bg-white/10 rounded transition-colors"
        >
          <Minus size={14} />
        </button>
        <button
          onClick={() => appWindow.toggleMaximize()}
          className="w-8 h-8 flex items-center justify-center hover:bg-white/10 rounded transition-colors"
        >
          <Square size={12} />
        </button>
        <button
          onClick={() => appWindow.close()}
          className="w-8 h-8 flex items-center justify-center hover:bg-red-500/80 rounded transition-colors"
        >
          <X size={14} />
        </button>
      </div>
    </div>
  );
}
