// 日期分桶：今天 / 昨天 / 更早
export function dayBucket(d: Date): "今天" | "昨天" | "更早" {
  const now = new Date();
  const startOf = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = startOf(now) - startOf(d);
  if (diff <= 0) return "今天";
  if (diff <= 86_400_000) return "昨天";
  return "更早";
}

export function formatTime(d: Date): string {
  const bucket = dayBucket(d);
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  if (bucket === "今天") return `${hh}:${mm}`;
  if (bucket === "昨天") return `昨天 ${hh}:${mm}`;
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

export function dirName(path: string | null): string {
  if (!path) return "未知目录";
  return path.split("/").filter(Boolean).pop() ?? path;
}
