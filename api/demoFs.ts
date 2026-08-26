import { getDb } from "./queries/connection";
import { demoDirs } from "@db/schema";

// 内置演示主机的静态文件系统（host.listDirectory 的数据来源）
const STATIC_DIRS: Record<string, string[]> = {
  "/": ["home", "etc", "var", ".ssh"],
  "/home": ["dev", "guest"],
  "/home/dev": ["projects", "Pictures", "Documents", ".config", ".cache"],
  "/home/dev/projects": ["dsh-client", "notes", "sandbox", "web-lab"],
  "/home/dev/projects/dsh-client": ["lib", "assets", "test"],
  "/home/dev/projects/notes": [],
  "/home/dev/projects/sandbox": [],
  "/home/dev/projects/web-lab": [],
  "/home/dev/Pictures": [],
  "/home/dev/Documents": [],
  "/home/guest": [],
  "/etc": [],
  "/var": ["log"],
  "/var/log": [],
};

export interface DirEntry {
  name: string;
  path: string;
  hidden: boolean;
}

export function normalizePath(p: string): string {
  let parts = p.split("/").filter(Boolean);
  let out = "/" + parts.join("/");
  return out === "" ? "/" : out;
}

export function parentPath(p: string): string {
  const n = normalizePath(p);
  if (n === "/") return "/";
  const idx = n.lastIndexOf("/");
  return idx === 0 ? "/" : n.slice(0, idx);
}

const MAX_ENTRIES = 200;

// 浏览主机文件系统：静态树 ∪ 用户新建目录
export async function listDirectory(
  path: string,
  showHidden: boolean,
): Promise<{ entries: DirEntry[]; truncated: boolean }> {
  const dir = normalizePath(path);
  const names = new Set(STATIC_DIRS[dir] ?? []);
  const created = await getDb().select().from(demoDirs);
  for (const row of created) {
    const p = normalizePath(row.path);
    if (parentPath(p) === dir) names.add(p.split("/").pop()!);
    // 新建的目录本身也可进入（即使是空的）
    if (!(p in STATIC_DIRS)) STATIC_DIRS[p] = STATIC_DIRS[p] ?? [];
  }
  let entries = [...names]
    .map((name) => ({ name, path: normalizePath(dir + "/" + name), hidden: name.startsWith(".") }))
    .filter((e) => showHidden || !e.hidden)
    .sort((a, b) => a.name.localeCompare(b.name));
  const truncated = entries.length > MAX_ENTRIES;
  if (truncated) entries = entries.slice(0, MAX_ENTRIES);
  return { entries, truncated };
}

export async function createDirectory(path: string): Promise<void> {
  await getDb().insert(demoDirs).values({ path: normalizePath(path) });
}

export async function pathExists(path: string): Promise<boolean> {
  const p = normalizePath(path);
  if (p in STATIC_DIRS) return true;
  const created = await getDb().select().from(demoDirs);
  return created.some((r) => normalizePath(r.path) === p);
}
