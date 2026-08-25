import type { LucideIcon } from "lucide-react";

// 空状态：大图标 + 引导文案
export function EmptyState({
  icon: Icon,
  title,
  hint,
}: {
  icon: LucideIcon;
  title: string;
  hint?: string;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-3 px-10 pb-20 text-center">
      <div className="flex h-16 w-16 items-center justify-center rounded-[20px] hairline bg-surface-1">
        <Icon className="h-7 w-7 text-muted-foreground" strokeWidth={1.5} />
      </div>
      <p className="text-[15px] font-semibold text-secondary-foreground">{title}</p>
      {hint && <p className="text-xs leading-relaxed text-faint">{hint}</p>}
    </div>
  );
}

export function GlowOrb({ size = 96 }: { size?: number }) {
  return (
    <div
      className="glow-orb shrink-0"
      style={{ width: size, height: size }}
      aria-hidden
    />
  );
}
