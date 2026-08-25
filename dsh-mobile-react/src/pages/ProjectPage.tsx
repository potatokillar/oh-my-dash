import { useNavigate, useParams } from "react-router";
import { trpc } from "@/providers/trpc";
import { PhoneShell, PageHeader } from "@/components/Chrome";
import { EmptyState } from "@/components/EmptyState";
import { Button } from "@/components/ui/button";
import { dirName, formatTime } from "@/lib/format";
import { MessagesSquare, Plus, LoaderCircle, ChevronRight } from "lucide-react";

// 项目内会话：只看该目录下的会话；新建会话自动落在本目录
export default function ProjectPage() {
  const { deviceId: idStr, path: encoded } = useParams();
  const deviceId = Number(idStr);
  const path = decodeURIComponent(encoded ?? "");
  const navigate = useNavigate();

  const { data: sessionList, isLoading } = trpc.sessions.list.useQuery(
    { deviceId },
    { refetchInterval: 8000 },
  );
  const inProject = (sessionList ?? []).filter((s) => s.cwd === path);

  const createMut = trpc.sessions.create.useMutation({
    onSuccess: (s) => navigate(`/chat/${s.id}`),
  });

  return (
    <PhoneShell>
      <PageHeader
        title={dirName(path)}
        subtitle={path}
        onBack={() => navigate(`/d/${deviceId}`)}
      />
      <div className="flex-1 overflow-y-auto px-4 pb-24">
        {isLoading ? (
          <div className="space-y-3">
            {[0, 1].map((i) => (
              <div key={i} className="skeleton-line h-[72px] !rounded-[20px]" />
            ))}
          </div>
        ) : !inProject.length ? (
          <EmptyState
            icon={MessagesSquare}
            title="这个项目还没有会话"
            hint="点击下方按钮在本目录创建第一个会话"
          />
        ) : (
          <ul className="reveal-stagger space-y-2.5">
            {inProject.map((s, i) => (
              <li key={s.id} style={{ ["--i" as string]: i }}>
                <button
                  className="pressable hairline w-full rounded-[20px] bg-surface-1 px-4 py-3.5 text-left"
                  onClick={() => navigate(`/chat/${s.id}`)}
                >
                  <div className="flex items-center gap-2">
                    {s.running && (
                      <LoaderCircle className="h-3.5 w-3.5 shrink-0 animate-spin text-primary" />
                    )}
                    <span className="min-w-0 flex-1 truncate text-[15px] font-semibold">{s.title}</span>
                    <span className="shrink-0 text-[11px] text-faint">
                      {formatTime(new Date(s.updatedAt))}
                    </span>
                    <ChevronRight className="h-4 w-4 shrink-0 text-faint" />
                  </div>
                  <p className="mt-1 truncate text-xs text-muted-foreground">
                    {s.provider}/{s.model}
                    {s.effort !== "off" ? ` · ${s.effort}` : ""}
                  </p>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
      <div className="pointer-events-none absolute bottom-5 left-0 right-0 z-20 flex justify-center px-5">
        <Button
          className="pointer-events-auto rounded-full px-6 shadow-[0_0_24px_hsl(var(--glow-warm)/0.35)]"
          disabled={createMut.isPending}
          onClick={() => createMut.mutate({ deviceId, cwd: path })}
        >
          <Plus className="mr-1.5 h-4 w-4" />
          在此目录新建会话
        </Button>
      </div>
    </PhoneShell>
  );
}
