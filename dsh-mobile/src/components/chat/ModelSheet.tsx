import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { PROVIDERS, EFFORT_LABELS } from "@contracts/models";
import { AlertTriangle, Check, Cpu } from "lucide-react";

export function modelLabel(provider: string, model: string, effort: string) {
  const p = PROVIDERS.find((x) => x.id === provider);
  const m = p?.models.find((x) => x.id === model);
  const base = m?.label ?? model;
  return effort !== "off" ? `${base} · ${EFFORT_LABELS[effort] ?? effort}` : base;
}

// 模型选择弹层：按 provider 分组，模型卡片 + 推理强度档
export function ModelSheet({
  open,
  onClose,
  current,
  onSelect,
  failedProviders = 0,
}: {
  open: boolean;
  onClose: () => void;
  current: { provider: string; model: string; effort: string };
  onSelect: (provider: string, model: string, effort: string) => void;
  failedProviders?: number;
}) {
  return (
    <Sheet open={open} onOpenChange={(v) => !v && onClose()}>
      <SheetContent
        side="bottom"
        className="mx-auto max-h-[80dvh] w-full max-w-[430px] overflow-y-auto rounded-t-[24px] border-border bg-popover px-4 pb-8"
      >
        <SheetHeader>
          <SheetTitle className="flex items-center gap-2">
            选择模型
            {failedProviders > 0 && (
              <span className="text-xs font-normal text-amber-700 dark:text-amber-300">
                {failedProviders} 个 provider 加载失败
              </span>
            )}
          </SheetTitle>
        </SheetHeader>
        <div className="mt-2 space-y-5">
          {PROVIDERS.map((p) => (
            <section key={p.id}>
              <p className="mb-2 flex items-center gap-1.5 text-xs font-semibold text-faint">
                {p.label}
                {!p.available && (
                  <span className="flex items-center gap-1 text-amber-700 dark:text-amber-300">
                    <AlertTriangle className="h-3 w-3" /> 路由不可用
                  </span>
                )}
              </p>
              <div className="space-y-2">
                {p.models.map((m) => {
                  const active = current.provider === p.id && current.model === m.id;
                  return (
                    <div
                      key={m.id}
                      className={`hairline rounded-[20px] p-3.5 ${active ? "bg-accent" : "bg-surface-1"} ${
                        p.available ? "" : "opacity-50"
                      }`}
                    >
                      <button
                        className="pressable flex w-full items-center gap-3 text-left"
                        disabled={!p.available}
                        onClick={() => {
                          const effort = m.efforts.includes(current.effort)
                            ? current.effort
                            : m.efforts[0];
                          onSelect(p.id, m.id, effort);
                        }}
                      >
                        <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-surface-3">
                          <Cpu className="h-4.5 w-4.5 h-5 w-5 text-primary" strokeWidth={1.6} />
                        </div>
                        <span className="flex-1 text-[15px] font-bold">{m.label}</span>
                        {active && <Check className="h-4 w-4 text-primary" />}
                      </button>
                      {/* 推理强度档 */}
                      {m.efforts.length > 1 && (
                        <div className="mt-2.5 flex gap-1.5">
                          {m.efforts.map((e) => {
                            const on = active && current.effort === e;
                            return (
                              <button
                                key={e}
                                disabled={!p.available}
                                className={`pressable rounded-full px-3 py-1 text-xs font-semibold ${
                                  on
                                    ? "bg-primary text-primary-foreground"
                                    : "bg-surface-3 text-muted-foreground"
                                }`}
                                onClick={() => onSelect(p.id, m.id, e)}
                              >
                                {EFFORT_LABELS[e] ?? e}
                              </button>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </section>
          ))}
        </div>
      </SheetContent>
    </Sheet>
  );
}
