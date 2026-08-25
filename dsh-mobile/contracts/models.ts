// 模型目录：真实来源是 dsh 的 session.models RPC（按 provider 分组 + 推理强度档）。
// UI 组件同步 import 本模块的 PROVIDERS，因此目录在运行时就地更新（引用不变），
// 由 useSessionStream 在拉取 session.models 后调用 updateModelCatalog 填充。
import type { SessionModels } from "@/lib/dsh/protocol";

export interface ModelInfo {
  id: string;
  label: string;
  efforts: string[]; // 推理强度档（dsh effort id；无推理能力的模型为 ["off"]）
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

// 运行时就地更新的目录；首次拉取前为空（ModelSheet 仅在会话打开后渲染，此时已填充）
export const PROVIDERS: ProviderInfo[] = [];

export const DEFAULT_MODEL = {
  provider: "",
  model: "",
  effort: "off",
};

export function findProvider(id: string) {
  return PROVIDERS.find((p) => p.id === id);
}

/**
 * 用 session.models 响应更新目录（就地替换 PROVIDERS 内容）。
 * current.provider 不在目录里时补一个兜底分组：目录成员资格只是建议性的
 * （routable 才是能否开工的依据），避免误报「路由不可用」。
 */
export function updateModelCatalog(models: SessionModels): void {
  const groups: ProviderInfo[] = (models.groups ?? []).map((g) => ({
    id: g.id,
    label: g.name || g.id,
    available: true,
    models: (g.models ?? []).map((m) => {
      const efforts = m.reasoning?.efforts ?? [];
      for (const e of efforts) {
        if (!(e.id in EFFORT_LABELS)) EFFORT_LABELS[e.id] = e.name || e.id;
      }
      return {
        id: m.id,
        label: m.name || m.id,
        efforts: efforts.length ? efforts.map((e) => e.id) : ["off"],
      };
    }),
  }));
  const cur = models.current;
  if (cur?.provider && !groups.some((g) => g.id === cur.provider)) {
    groups.unshift({
      id: cur.provider,
      label: cur.provider,
      available: models.routable !== false,
      models: [
        {
          id: cur.model,
          label: cur.model,
          efforts: cur.reasoningEffort ? [cur.reasoningEffort] : ["off"],
        },
      ],
    });
  }
  PROVIDERS.splice(0, PROVIDERS.length, ...groups);
}
