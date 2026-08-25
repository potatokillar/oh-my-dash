import { useSyncExternalStore } from "react";

type Theme = "light" | "dark";
const KEY = "dsh.theme";

let current: Theme =
  (typeof localStorage !== "undefined" && (localStorage.getItem(KEY) as Theme | null)) ||
  (typeof window !== "undefined" &&
  window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light");

const listeners = new Set<() => void>();

function apply(theme: Theme) {
  document.documentElement.classList.toggle("dark", theme === "dark");
}

// 模块级共享主题：所有组件（App / ThemeToggle）读到同一个值
export function useTheme() {
  const theme = useSyncExternalStore(
    (cb) => {
      listeners.add(cb);
      return () => listeners.delete(cb);
    },
    () => current,
  );

  const toggle = () => {
    current = current === "dark" ? "light" : "dark";
    localStorage.setItem(KEY, current);
    apply(current);
    listeners.forEach((l) => l());
  };

  return { theme, toggle };
}

// 首屏立即应用，避免闪烁
apply(current);
