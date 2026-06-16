import type { AppStep } from "../types";
import { Upload, Sliders, Eye, Download } from "lucide-react";

const steps: { key: AppStep; label: string; icon: typeof Upload }[] = [
  { key: "upload", label: "上传字图", icon: Upload },
  { key: "adjust", label: "调整参数", icon: Sliders },
  { key: "preview", label: "预览字体", icon: Eye },
  { key: "export", label: "导出字体", icon: Download },
];

interface Props {
  currentStep: AppStep;
  onStepClick: (step: AppStep) => void;
  charactersCount: number;
}

export default function StepIndicator({
  currentStep,
  onStepClick,
  charactersCount,
}: Props) {
  const currentIndex = steps.findIndex((s) => s.key === currentStep);

  return (
    <div className="px-6 py-4 shrink-0">
      <div className="flex items-center justify-center gap-2">
        {steps.map((step, index) => {
          const Icon = step.icon;
          const isActive = step.key === currentStep;
          const isCompleted = index < currentIndex;
          const isClickable =
            index <= currentIndex || (step.key === "upload" && true);

          return (
            <div key={step.key} className="flex items-center">
              <button
                onClick={() => isClickable && onStepClick(step.key)}
                disabled={!isClickable}
                className={`flex items-center gap-2 px-4 py-2 rounded-lg transition-all duration-300 ${
                  isActive
                    ? "bg-ink-900 text-paper-100 shadow-ink"
                    : isCompleted
                    ? "bg-ink-200 text-ink-800 hover:bg-ink-300"
                    : "bg-paper-200 text-ink-300"
                } ${isClickable ? "cursor-pointer" : "cursor-default"}`}
              >
                <Icon size={16} />
                <span className="text-sm font-medium">{step.label}</span>
                {step.key === "upload" && charactersCount > 0 && (
                  <span
                    className={`text-xs px-1.5 py-0.5 rounded-full ${
                      isActive
                        ? "bg-paper-200 text-ink-800"
                        : "bg-ink-300 text-ink-800"
                    }`}
                  >
                    {charactersCount}
                  </span>
                )}
              </button>
              {index < steps.length - 1 && (
                <div
                  className={`w-8 h-0.5 mx-1 transition-colors duration-300 ${
                    index < currentIndex ? "bg-ink-400" : "bg-paper-300"
                  }`}
                />
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
