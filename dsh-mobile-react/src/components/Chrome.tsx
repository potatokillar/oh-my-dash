import type { ReactNode } from "react";
import { ChevronLeft } from "lucide-react";
import { useNavigate } from "react-router";

// 手机壳：移动端最大宽度 + 全局环境光斑
export function PhoneShell({ children }: { children: ReactNode }) {
  return (
    <div className="mx-auto flex h-dvh w-full max-w-[430px] flex-col bg-background relative overflow-hidden">
      <div className="ambient-glow" />
      <div className="relative z-10 flex h-full flex-col">{children}</div>
    </div>
  );
}

export function PageHeader({
  title,
  subtitle,
  onBack,
  right,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  onBack?: () => void;
  right?: ReactNode;
}) {
  const navigate = useNavigate();
  return (
    <header className="flex items-center gap-2 px-4 pt-5 pb-3 shrink-0">
      {onBack !== undefined && (
        <button
          className="pressable -ml-2 flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground"
          onClick={() => (onBack ? onBack() : navigate(-1))}
          aria-label="返回"
        >
          <ChevronLeft className="h-6 w-6" />
        </button>
      )}
      <div className="min-w-0 flex-1">
        <h1 className="font-display truncate text-[28px] font-bold leading-tight tracking-tight">{title}</h1>
        {subtitle && <div className="truncate text-xs text-muted-foreground mt-0.5">{subtitle}</div>}
      </div>
      {right}
    </header>
  );
}
