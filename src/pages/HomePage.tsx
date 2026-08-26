import { useMemo } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router";
import { trpc } from "@/providers/trpc";
import { PhoneShell } from "@/components/Chrome";
import { EmptyState } from "@/components/EmptyState";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/ThemeToggle";
import { dayBucket, formatTime, dirName } from "@/lib/format";
import {
  FolderGit2,
  MessagesSquare,
  SwitchCamera,
  Plus,
  FolderPlus,
  ChevronRight,
  LoaderCircle,
} from "lucide-react";

function greeting() {
  const h = new Date().getHours();
  if (h < 6) return "夜深了";
  if (h < 12) return "早上好";
  if (h < 18) return "下午好";
  return "晚上好";
}

export default function HomePage() {
  const { deviceId: idStr } = useParams();
  const deviceId = Number(idStr);
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const tab = params.get("tab") === "sessions" ? "sessions" : "projects";

  const { data: deviceList } = trpc.devices.list.useQuery(undefined, { refetchInterval: 30000 });
  const device = deviceList?.find((d) => d.id === deviceId);

  const {
    data: projectList,
    isLoading: loadingProjects,
    isError: projectsError,
  } = trpc.sessions.projects.useQuery({ deviceId }, { refetchInterval: 8000 });
  const {
    data: sessionList,
    isLoading: loadingSessions,
    isError: sessionsError,
  } = trpc.sessions.list.useQuery({ deviceId }, { refetchInterval: 8000 });

  const buckets = useMemo(() => {
    const map = new Map<string, NonNullable<typeof sessionList>>();
    for (const s of sessionList ?? []) {
      const b = dayBucket(new Date(s.updatedAt));
      if (!map.has(b)) map.set(b, []);
      map.get(b)!.push(s);
    }
    return map;
  }, [sessionList]);

  return (
    <PhoneShell>
      <header className="shrink-0 px-5 pt-6 pb-2">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-xs text-muted-foreground">{device?.name ?? "…"}</p>
            <h1 className="greeting-gradient font-display mt-1 text-[32px] font-bold leading-tight tracking-tight">
              {greeting()}
            </h1>
          </div>
          <div className="mt-2 flex items-center gap-2">
            <ThemeToggle />
            <Button
              variant="secondary"
              size="sm"
              className="rounded-full"
              onClick={() => navigate("/devices")}
            >
              <SwitchCamera className="mr-1.5 h-4 w-4" />
              切换设备
            </Button>
          </div>
        </div>
        {device && !device.status.online && (
          <div className="mt-3 rounded-2xl hairline bg-surface-1 px-4 py-2.5 text-xs text-amber-700 dark:text-amber-300">
            当前设备离线：{device.status.reason ?? "无法连接"}。你仍可查看历史会话。
          </div>
        )}
      </header>

      <Tabs
        value={tab}
        onValueChange={(v) => setParams({ tab: v }, { replace: true })}
        className="flex min-h-0 flex-1 flex-col"
      >
        <div className="shrink-0 px-5 pt-2">
          <TabsList className="grid w-full grid-cols-2 rounded-full bg-surface-2 p-1">
            <TabsTrigger value="projects" className="rounded-full">项目</TabsTrigger>
            <TabsTrigger value="sessions" className="rounded-full">会话</TabsTrigger>
          </TabsList>
        </div>

        {/* ---------- 项目视图 ---------- */}
        <TabsContent value="projects" className="mt-0 flex min-h-0 flex-1 flex-col data-[state=inactive]:hidden">
          <div className="flex-1 overflow-y-auto px-4 pb-24 pt-3">
            {loadingProjects ? (
              <div className="space-y-3" aria-label="加载中">
                {[0, 1, 2].map((i) => (
                  <div key={i} className="skeleton-line h-[84px] !rounded-[20px]" />
                ))}
                <p className="flex items-center justify-center gap-2 pt-1 text-xs text-faint">
                  <LoaderCircle className="h-3.5 w-3.5 animate-spin" />
                  正在连接主机…
                </p>
              </div>
            ) : projectsError ? (
              <EmptyState
                icon={FolderGit2}
                title="加载失败"
                hint="无法从主机获取项目列表，请检查设备连接后下拉重试"
              />
            ) : !projectList?.length ? (
              <EmptyState
                icon={FolderGit2}
                title="还没有项目"
                hint="项目即目录：会话会按工作目录自动聚合，也可以直接注册一个空目录"
              />
            ) : (
              <ul className="reveal-stagger space-y-3">
                {projectList.map((p, i) => (
                  <li key={p.path ?? "unknown"} style={{ ["--i" as string]: i }}>
                    <button
                      className="pressable hairline w-full rounded-[20px] bg-surface-1 p-4 text-left"
                      onClick={() =>
                        p.path &&
                        navigate(`/d/${deviceId}/project/${encodeURIComponent(p.path)}`)
                      }
                    >
                      <div className="flex items-center gap-3">
                        <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-surface-3">
                          <FolderGit2 className="h-5 w-5 text-primary" strokeWidth={1.6} />
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <span className="truncate text-[15px] font-bold">
                              {p.title ?? dirName(p.path)}
                            </span>
                            <span className="shrink-0 rounded-full bg-surface-3 px-2 py-0.5 text-[11px] font-semibold text-muted-foreground">
                              {p.count} 个会话
                            </span>
                          </div>
                          <p className="mt-0.5 truncate text-xs text-faint">
                            {p.path ?? "工作目录未知"}
                          </p>
                        </div>
                        {p.path && <ChevronRight className="h-4 w-4 shrink-0 text-faint" />}
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </TabsContent>

        {/* ---------- 会话视图 ---------- */}
        <TabsContent value="sessions" className="mt-0 flex min-h-0 flex-1 flex-col data-[state=inactive]:hidden">
          <div className="flex-1 overflow-y-auto px-4 pb-24 pt-3">
            {loadingSessions ? (
              <div className="space-y-3" aria-label="加载中">
                {[0, 1, 2, 3].map((i) => (
                  <div key={i} className="skeleton-line h-[72px] !rounded-[20px]" />
                ))}
                <p className="flex items-center justify-center gap-2 pt-1 text-xs text-faint">
                  <LoaderCircle className="h-3.5 w-3.5 animate-spin" />
                  正在连接主机…
                </p>
              </div>
            ) : sessionsError ? (
              <EmptyState
                icon={MessagesSquare}
                title="加载失败"
                hint="无法从主机获取会话列表，请检查设备连接后重试"
              />
            ) : !sessionList?.length ? (
              <EmptyState
                icon={MessagesSquare}
                title="还没有会话"
                hint="点右下角新建会话，选择一个工作目录后即可开始与智能体对话"
              />
            ) : (
              <div>
                {(["今天", "昨天", "更早"] as const).map((bucket) => {
                  const items = buckets.get(bucket);
                  if (!items?.length) return null;
                  return (
                    <div key={bucket} className="mb-4 first:-mt-1">
                      <p className="px-1 pb-2 text-xs font-semibold text-faint">{bucket}</p>
                      <ul className="space-y-2.5">
                      {items.map((s) => (
                        <li key={s.id}>
                          <button
                            className="pressable hairline w-full rounded-[20px] bg-surface-1 px-4 py-3.5 text-left"
                            onClick={() => navigate(`/chat/${s.id}`)}
                          >
                            <div className="flex items-center gap-2">
                              {s.running && (
                                <LoaderCircle className="h-3.5 w-3.5 shrink-0 animate-spin text-primary" />
                              )}
                              <span className="min-w-0 flex-1 truncate text-[15px] font-semibold">
                                {s.title}
                              </span>
                              <span className="shrink-0 text-[11px] text-faint">
                                {formatTime(new Date(s.updatedAt))}
                              </span>
                            </div>
                            <p className="mt-1 truncate text-xs text-muted-foreground">
                              {dirName(s.cwd)} · {s.provider}/{s.model}
                              {s.effort !== "off" ? ` · ${s.effort}` : ""}
                            </p>
                          </button>
                        </li>
                      ))}
                      </ul>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </TabsContent>
      </Tabs>

      {/* 底部操作 */}
      <div className="pointer-events-none absolute bottom-5 left-0 right-0 z-20 flex justify-center gap-3 px-5">
        {tab === "projects" && (
          <Button
            variant="secondary"
            className="pointer-events-auto rounded-full"
            onClick={() => navigate(`/d/${deviceId}/browse?mode=add`)}
          >
            <FolderPlus className="mr-1.5 h-4 w-4" />
            添加项目
          </Button>
        )}
        <Button
          className="pointer-events-auto rounded-full px-6 shadow-[0_0_24px_hsl(var(--glow-warm)/0.35)]"
          onClick={() => navigate(`/d/${deviceId}/browse?mode=create`)}
        >
          <Plus className="mr-1.5 h-4 w-4" />
          新建会话
        </Button>
      </div>
    </PhoneShell>
  );
}
