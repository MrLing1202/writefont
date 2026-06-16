import { useState, useCallback } from "react";
import type { FontParams, CharacterImage, AppStep, DEFAULT_PARAMS } from "../types";

export function useAppState() {
  const [step, setStep] = useState<AppStep>("upload");
  const [params, setParams] = useState<FontParams>({
    strokeWidth: 5,
    smoothness: 70,
    spacing: 10,
    baseline: 0,
    inkDensity: 80,
    style: "regular",
  });
  const [characters, setCharacters] = useState<CharacterImage[]>([]);
  const [fontName, setFontName] = useState("我的手写字体");
  const [fontAuthor, setFontAuthor] = useState("");
  const [isProcessing, setIsProcessing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [generatedTtfPath, setGeneratedTtfPath] = useState<string | null>(null);
  const [previewImages, setPreviewImages] = useState<string[]>([]);

  const addCharacter = useCallback((char: CharacterImage) => {
    setCharacters((prev) => {
      const existing = prev.findIndex((c) => c.char === char.char);
      if (existing >= 0) {
        const updated = [...prev];
        updated[existing] = char;
        return updated;
      }
      return [...prev, char];
    });
  }, []);

  const removeCharacter = useCallback((char: string) => {
    setCharacters((prev) => prev.filter((c) => c.char !== char));
  }, []);

  const clearCharacters = useCallback(() => {
    setCharacters([]);
  }, []);

  return {
    step,
    setStep,
    params,
    setParams,
    characters,
    setCharacters,
    addCharacter,
    removeCharacter,
    clearCharacters,
    fontName,
    setFontName,
    fontAuthor,
    setFontAuthor,
    isProcessing,
    setIsProcessing,
    progress,
    setProgress,
    generatedTtfPath,
    setGeneratedTtfPath,
    previewImages,
    setPreviewImages,
  };
}
