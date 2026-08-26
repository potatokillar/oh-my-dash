// 模型目录：按 provider 分组，模型卡片 + 推理强度档
export interface ModelInfo {
  id: string;
  label: string;
  efforts: string[]; // 推理强度档
}

export interface ProviderInfo {
  id: string;
  label: string;
  available: boolean; // 路由不可用时输入区上方显示警告条
  models: ModelInfo[];
}

export const EFFORT_LABELS: Record<string, string> = {
  off: "Off",
  low: "Low",
  high: "High",
  max: "Max",
};

export const PROVIDERS: ProviderInfo[] = [
  {
    id: "kimi",
    label: "Kimi",
    available: true,
    models: [
      { id: "kimi-k2", label: "Kimi K2", efforts: ["off"] },
      { id: "kimi-k2-thinking", label: "Kimi K2 Thinking", efforts: ["low", "high", "max"] },
    ],
  },
  {
    id: "deepseek",
    label: "DeepSeek",
    available: true,
    models: [
      { id: "deepseek-chat", label: "DeepSeek V3.2", efforts: ["off"] },
      { id: "deepseek-reasoner", label: "DeepSeek R1", efforts: ["low", "high", "max"] },
    ],
  },
  {
    id: "glm",
    label: "GLM",
    available: false, // 演示「模型路由不可用」警告条
    models: [{ id: "glm-4.6", label: "GLM 4.6", efforts: ["off", "high"] }],
  },
];

export const DEFAULT_MODEL = {
  provider: "kimi",
  model: "kimi-k2-thinking",
  effort: "high",
};

export function findProvider(id: string) {
  return PROVIDERS.find((p) => p.id === id);
}
