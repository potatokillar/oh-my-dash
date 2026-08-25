import { useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router";
import { trpc } from "@/providers/trpc";
import { PhoneShell, PageHeader } from "@/components/Chrome";
import { EmptyState } from "@/components/EmptyState";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { toast } from "sonner";
import { Folder, Eye, FolderPlus, ChevronRight, FolderOpen } from "lucide-react";

// 目录浏览器：面包屑 chip 链 + 子目录导航 + 隐藏目录开关 + 新建文件夹
export default function BrowsePage() {
  const { deviceId: idStr } = useParams();
  const deviceId = Number(idStr);
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const mode = params.get("mode") === "add" ? "add" : "create";
  const path = params.get("path") || "/";
  const showHidden = params.get("hidden") === "1";

  const { data, isLoading, error } = trpc.browse.list.useQuery(
    { deviceId, path, showHidden },
    { retry: false },
  );
  const utils = trpc.useUtils();

  const [mkdirOpen, setMkdirOpen] = useState(false);
  const [dirNameInput, setDirNameInput] = useState("");

  const createDirMut = trpc.browse.createDir.useMutation({
    onSuccess: () => {
      setMkdirOpen(false);
      setDirNameInput("");
      utils.browse.list.invalidate();
      toast.success("文件夹已创建");
    },
    onError: (e) => toast.error(e.message),
  });
  const addProjectMut = trpc.sessions.addProject.useMutation({
    onSuccess: (r) => {
      if (r.duplicated) toast.info("该目录已经是项目了");
      else toast.success("已添加为项目");
      navigate(`/d/${deviceId}`);
    },
    onError: (e) => toast.error(e.message),
  });
  const createSessionMut = trpc.sessions.create.useMutation({
    onSuccess: (s) => navigate(`/chat/${s.id}`),
  });

  // 面包屑 chip 链
  const crumbs = useMemo(() => {
    const parts = path.split("/").filter(Boolean);
    const list: { label: string; path: string }[] = [{ label: "根目录", path: "/" }];
    let acc = "";
    for (const p of parts) {
      acc += "/" + p;
      list.push({ label: p, path: acc });
    }
    return list;
  }, [path]);

  const goto = (p: string) => {
    const next = new URLSearchParams(params);
    next.set("path", p);
    setParams(next, { replace: false });
  };

  return (
    <PhoneShell>
      <PageHeader
        title={mode === "add" ? "添加项目" : "选择工作目录"}
        subtitle="浏览主机文件系统"
        onBack={() => navigate(-1)}
        right={
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Eye className="h-4 w-4" />
            <Switch
              checked={showHidden}
              onCheckedChange={(v) => {
                const next = new URLSearchParams(params);
                next.set("hidden", v ? "1" : "0");
                setParams(next, { replace: true });
              }}
              aria-label="显示隐藏目录"
            />
          </div>
        }
      />

      {/* 面包屑 */}
      <div className="flex shrink-0 items-center gap-1 overflow-x-auto px-4 pb-3">
        {crumbs.map((c, i) => (
          <div key={c.path} className="flex shrink-0 items-center gap-1">
            {i > 0 && <ChevronRight className="h-3 w-3 text-faint" />}
            <button
              className={`rounded-full px-2.5 py-1 text-xs font-semibold ${
                i === crumbs.length - 1
                  ? "bg-primary/15 text-primary"
                  : "text-muted-foreground"
              }`}
              onClick={() => goto(c.path)}
            >
              {c.label}
            </button>
          </div>
        ))}
      </div>

      <div className="flex-1 overflow-y-auto px-4 pb-28">
        {isLoading ? (
          <div className="space-y-2">
            {[0, 1, 2, 3].map((i) => (
              <div key={i} className="skeleton-line h-12 !rounded-2xl" />
            ))}
          </div>
        ) : error ? (
          <EmptyState icon={FolderOpen} title="无法浏览目录" hint={error.message} />
        ) : !data?.entries.length ? (
          <EmptyState icon={FolderOpen} title="空目录" hint="这里还没有子目录" />
        ) : (
          <>
            <ul className="reveal-stagger space-y-2">
              {data.entries.map((e, i) => (
                <li key={e.path} style={{ ["--i" as string]: i }}>
                  <button
                    className="pressable hairline flex w-full items-center gap-3 rounded-2xl bg-surface-1 px-4 py-3 text-left"
                    onClick={() => goto(e.path)}
                  >
                    <Folder
                      className={`h-5 w-5 shrink-0 ${e.hidden ? "text-faint" : "text-primary"}`}
                      strokeWidth={1.6}
                    />
                    <span className={`min-w-0 flex-1 truncate text-[15px] ${e.hidden ? "text-muted-foreground" : ""}`}>
                      {e.name}
                    </span>
                    <ChevronRight className="h-4 w-4 shrink-0 text-faint" />
                  </button>
                </li>
              ))}
            </ul>
            {data.truncated && (
              <p className="px-2 pt-3 text-center text-xs text-faint">
                条目过多，仅显示前 200 项
              </p>
            )}
          </>
        )}
      </div>

      {/* 底部主操作：按进入场景切换 */}
      <div className="pointer-events-none absolute bottom-5 left-0 right-0 z-20 flex justify-center gap-3 px-5">
        <Button
          variant="secondary"
          className="pointer-events-auto rounded-full"
          onClick={() => setMkdirOpen(true)}
        >
          <FolderPlus className="mr-1.5 h-4 w-4" />
          新建文件夹
        </Button>
        {mode === "add" ? (
          <Button
            className="pointer-events-auto rounded-full px-5 shadow-[0_0_24px_hsl(var(--glow-warm)/0.35)]"
            disabled={addProjectMut.isPending}
            onClick={() => addProjectMut.mutate({ deviceId, path })}
          >
            添加此目录为项目
          </Button>
        ) : (
          <Button
            className="pointer-events-auto rounded-full px-5 shadow-[0_0_24px_hsl(var(--glow-warm)/0.35)]"
            disabled={createSessionMut.isPending}
            onClick={() => createSessionMut.mutate({ deviceId, cwd: path === "/" ? null : path })}
          >
            在此目录创建会话
          </Button>
        )}
      </div>

      <Dialog open={mkdirOpen} onOpenChange={setMkdirOpen}>
        <DialogContent className="max-w-[360px] rounded-[20px] bg-popover">
          <DialogHeader>
            <DialogTitle>新建文件夹</DialogTitle>
          </DialogHeader>
          <Input
            placeholder="文件夹名称"
            value={dirNameInput}
            onChange={(e) => setDirNameInput(e.target.value)}
            className="bg-surface-2"
          />
          <DialogFooter>
            <Button
              className="rounded-full"
              disabled={!dirNameInput.trim() || createDirMut.isPending}
              onClick={() =>
                createDirMut.mutate({
                  deviceId,
                  path: (path === "/" ? "" : path) + "/" + dirNameInput.trim(),
                })
              }
            >
              创建
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </PhoneShell>
  );
}
