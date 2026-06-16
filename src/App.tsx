import { useState, useEffect } from "react";
import { Toaster } from "react-hot-toast";
import { motion, AnimatePresence } from "framer-motion";
import TitleBar from "./components/TitleBar";
import StepIndicator from "./components/StepIndicator";
import UploadPanel from "./components/UploadPanel";
import AdjustPanel from "./components/AdjustPanel";
import PreviewPanel from "./components/PreviewPanel";
import ExportPanel from "./components/ExportPanel";
import { useAppState } from "./hooks/useAppState";
import { checkPythonEnv } from "./hooks/useWriteFont";
import toast from "react-hot-toast";

function App() {
  const state = useAppState();
  const [pythonReady, setPythonReady] = useState(false);
  const [pythonMessage, setPythonMessage] = useState("检测 Python 环境中...");

  useEffect(() => {
    checkPythonEnv().then((env) => {
      setPythonReady(env.available);
      setPythonMessage(env.message);
      if (!env.available) {
        toast.error("Python 环境未就绪: " + env.message, { duration: 5000 });
      }
    });
  }, []);

  const renderStep = () => {
    switch (state.step) {
      case "upload":
        return <UploadPanel state={state} />;
      case "adjust":
        return <AdjustPanel state={state} />;
      case "preview":
        return <PreviewPanel state={state} />;
      case "export":
        return <ExportPanel state={state} />;
    }
  };

  return (
    <div className="h-full flex flex-col bg-paper-50 overflow-hidden">
      <Toaster
        position="top-center"
        toastOptions={{
          style: {
            background: "#fdf9f3",
            color: "#2e211c",
            border: "1px solid #e0d6c8",
            fontFamily: "Noto Serif SC, serif",
          },
        }}
      />

      <TitleBar />

      <div className="flex-1 flex flex-col overflow-hidden">
        <StepIndicator
          currentStep={state.step}
          onStepClick={state.setStep}
          charactersCount={state.characters.length}
        />

        {/* Python status indicator */}
        <div className="px-6 py-1">
          <div className="flex items-center gap-2 text-xs">
            <div
              className={`w-2 h-2 rounded-full ${
                pythonReady ? "bg-green-500" : "bg-red-400"
              }`}
            />
            <span className="text-ink-400">{pythonMessage}</span>
          </div>
        </div>

        <div className="flex-1 overflow-auto">
          <AnimatePresence mode="wait">
            <motion.div
              key={state.step}
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.3 }}
              className="h-full"
            >
              {renderStep()}
            </motion.div>
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}

export default App;
