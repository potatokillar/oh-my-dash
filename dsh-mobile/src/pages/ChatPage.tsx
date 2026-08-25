import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router";
import { trpc } from "@/providers/trpc";
import type { Message } from "@db/schema";
import { useSessionStream } from "@/hooks/useSessionStream";
import { PhoneShell } from "@/components/Chrome";
import { GlowOrb } from "@/components/EmptyState";
import { MessageBubble, ThinkingDots } from "@/components/chat/MessageBubble";
import { Composer, QUICK_ACTIONS } from "@/components/chat/Composer";
import { ModelSheet, modelLabel } from "@/components/chat/ModelSheet";
import { ApprovalDialog } from "@/components/chat/ApprovalDialog";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Input } from "@/components/ui/input";
import { findProvider } from "@contracts/models";
import { toast } from "sonner";
import {
  ChevronLeft,
  MoreVertical,
  AlertTriangle,
  Code2,
  Lightbulb,
  Brain,
  FileText,
  Archive,
  Pencil,
  Info,
  LoaderCircle,
} from "lucide-react";

const BENTO = [
  { icon: Code2, title: "写代码", desc: "生成、审查、重构", prefix: QUICK_ACTIONS[0].prefix },
  { icon: Lightbulb, title: "解释概念", desc: "深入浅出讲清楚", prefix: QUICK_ACTIONS[1].prefix },
  { icon: Brain, title: "头脑风暴", desc: "一起拓展思路", prefix: QUICK_ACTIONS[2].prefix },
  { icon: FileText, title: "总结文字", desc: "提炼长文要点", prefix: QUICK_ACTIONS[3].prefix },
];

const PAGE_SIZE = 30;

export default function ChatPage() {
  const { sessionId: idStr } = useParams();
  const sessionId = Number(idStr);
  const navigate = useNavigate();
  const utils = trpc.useUtils();

  const stream = useSessionStream(Number.isFinite(sessionId) ? sessionId : null);
  const session = stream.session;

  const { data: deviceList } = trpc.devices.list.useQuery(undefined, { staleTime: 30000 });
  const device = deviceList?.find((d) => d.id === session?.deviceId);

  // ---------- 历史分页 ----------
  const [older, setOlder] = useState<Message[]>([]);
  const [loadingOlder, setLoadingOlder] = useState(false);
  const [hasMore, setHasMore] = useState(false);

  useEffect(() => {
    setOlder([]);
    setHasMore(stream.messages.length >= PAGE_SIZE);
  }, [sessionId]); // eslint-disable-line react-hooks/exhaustive-deps

  const allMessages = useMemo(() => {
    const seen = new Set(older.map((m) => m.id));
    return [...older, ...stream.messages.filter((m) => !seen.has(m.id))].sort(
      (a, b) => a.seq - b.seq,
    );
  }, [older, stream.messages]);

  // ---------- 滚动管理 ----------
  const scrollRef = useRef<HTMLDivElement>(null);
  const nearBottom = useRef(true);

  const scrollToBottom = useCallback((smooth = false) => {
    const el = scrollRef.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: smooth ? "smooth" : "auto" });
  }, []);

  // 新内容到达时，若用户在底部附近则跟随滚动
  useEffect(() => {
    if (nearBottom.current) scrollToBottom();
  }, [allMessages, scrollToBottom]);

  // 进入会话滚到底部
  const firstLoad = useRef(true);
  useEffect(() => {
    if (firstLoad.current && stream.messages.length > 0) {
      firstLoad.current = false;
      scrollToBottom();
    }
  }, [stream.messages.length, scrollToBottom]);

  const loadOlder = async () => {
    const first = allMessages[0];
    const el = scrollRef.current;
    if (!first || !el || loadingOlder) return;
    setLoadingOlder(true);
    const prevHeight = el.scrollHeight;
    try {
      const rows = await utils.sessions.messages.fetch({
        sessionId,
        beforeSeq: first.seq,
        limit: PAGE_SIZE,
      });
      setHasMore(rows.length >= PAGE_SIZE);
      setOlder((prev) => {
        const seen = new Set(prev.map((m) => m.id));
        return [...rows.filter((r) => !seen.has(r.id)), ...prev];
      });
      // 位置不跳动
      requestAnimationFrame(() => {
        el.scrollTop += el.scrollHeight - prevHeight;
      });
    } finally {
      setLoadingOlder(false);
    }
  };

  const onScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    nearBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 120;
    if (el.scrollTop < 60 && hasMore) void loadOlder();
  };

  // ---------- 操作 ----------
  const sendMut = trpc.sessions.send.useMutation({
    onError: (e) => toast.error(e.message),
  });
  const stopMut = trpc.sessions.stop.useMutation();
  const respondMut = trpc.sessions.respond.useMutation();
  const renameMut = trpc.sessions.rename.useMutation({
    onSuccess: () => {
      setRenameOpen(false);
      utils.sessions.list.invalidate();
    },
  });
  const archiveMut = trpc.sessions.archive.useMutation({
    onSuccess: () => {
      utils.sessions.list.invalidate();
      utils.sessions.projects.invalidate();
      navigate(-1);
    },
  });
  const setModelMut = trpc.sessions.setModel.useMutation();

  const [modelsOpen, setModelsOpen] = useState(false);
  const [renameOpen, setRenameOpen] = useState(false);
  const [renameValue, setRenameValue] = useState("");
  const [infoOpen, setInfoOpen] = useState(false);

  const running = session?.running || allMessages.some((m) => m.status === "streaming");
  const providerUnavailable = session ? !findProvider(session.provider)?.available : false;
  const isEmpty = allMessages.length === 0;

  // 日期分隔条
  const withSeparators = useMemo(() => {
    const out: ({ type: "sep"; label: string; key: string } | { type: "msg"; msg: Message })[] = [];
    let lastDay = "";
    for (const m of allMessages) {
      const d = new Date(m.createdAt);
      const day = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
      if (day !== lastDay) {
        lastDay = day;
        out.push({
          type: "sep",
          key: `sep-${day}`,
          label: `${d.getMonth() + 1}月${d.getDate()}日`,
        });
      }
      out.push({ type: "msg", msg: m });
    }
    return out;
  }, [allMessages]);

  const [bentoPrefix, setBentoPrefix] = useState<string | null>(null);

  return (
    <PhoneShell>
      {/* 顶栏 */}
      <header className="flex shrink-0 items-center gap-1 px-2 pt-4 pb-2">
        <button
          className="pressable flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground"
          onClick={() => navigate(-1)}
          aria-label="返回"
        >
          <ChevronLeft className="h-6 w-6" />
        </button>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[15px] font-bold">{session?.title ?? "…"}</p>
          <p className="flex items-center gap-1 text-[11px] text-faint">
            {running && <LoaderCircle className="h-3 w-3 animate-spin text-primary" />}
            {running ? "正在生成" : stream.connected ? "已连接" : "连接中…"}
          </p>
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <button
              className="pressable flex h-9 w-9 items-center justify-center rounded-full text-muted-foreground"
              aria-label="会话菜单"
            >
              <MoreVertical className="h-5 w-5" />
            </button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="rounded-2xl bg-popover">
            <DropdownMenuItem
              onClick={() => {
                setRenameValue(session?.title ?? "");
                setRenameOpen(true);
              }}
            >
              <Pencil className="mr-2 h-4 w-4" /> 重命名
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => setInfoOpen(true)}>
              <Info className="mr-2 h-4 w-4" /> 会话信息
            </DropdownMenuItem>
            <DropdownMenuItem
              className="text-destructive"
              onClick={() => session && archiveMut.mutate({ id: session.id })}
            >
              <Archive className="mr-2 h-4 w-4" /> 归档会话
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </header>

      {/* 消息区 */}
      <div ref={scrollRef} onScroll={onScroll} className="min-h-0 flex-1 overflow-y-auto px-3">
        {isEmpty && stream.connected ? (
          /* 空会话引导页：光晕球 + 2×2 bento 卡片 */
          <div className="flex min-h-full flex-col items-center justify-center gap-8 px-4 pb-10">
            <GlowOrb size={110} />
            <div className="text-center">
              <p className="greeting-gradient font-display text-[22px] font-bold">开始新的对话</p>
              <p className="mt-1 text-xs text-faint">选择下方任一方式，或直接输入你的想法</p>
            </div>
            <div className="reveal-stagger grid w-full grid-cols-2 gap-2.5">
              {BENTO.map((b, i) => (
                <button
                  key={b.title}
                  style={{ ["--i" as string]: i }}
                  className="pressable hairline rounded-[20px] bg-surface-1 p-4 text-left"
                  onClick={() => setBentoPrefix(b.prefix)}
                >
                  <b.icon className="h-5 w-5 text-primary" strokeWidth={1.6} />
                  <p className="mt-2.5 text-[15px] font-bold">{b.title}</p>
                  <p className="mt-0.5 text-xs text-faint">{b.desc}</p>
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="space-y-3 py-3">
            {loadingOlder && (
              <div className="flex justify-center py-2">
                <LoaderCircle className="h-4 w-4 animate-spin text-faint" />
              </div>
            )}
            {hasMore && !loadingOlder && (
              <p className="pb-1 text-center text-[11px] text-faint">向上滑动加载更早的消息</p>
            )}
            {withSeparators.map((item) =>
              item.type === "sep" ? (
                <div key={item.key} className="flex items-center gap-3 py-1">
                  <div className="h-px flex-1 bg-border" />
                  <span className="text-[11px] text-faint">{item.label}</span>
                  <div className="h-px flex-1 bg-border" />
                </div>
              ) : (
                <MessageBubble key={item.msg.id} msg={item.msg} />
              ),
            )}
            {running && !allMessages.some((m) => m.status === "streaming") && (
              <div className="msg-in flex justify-start">
                <div className="hairline rounded-[20px] rounded-bl-md bg-surface-1 px-4 py-3">
                  <ThinkingDots />
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* 模型路由不可用警告条 */}
      {providerUnavailable && (
        <div className="mx-3 mb-2 flex shrink-0 items-center gap-2 rounded-2xl hairline bg-amber-400/10 px-4 py-2.5 text-xs text-amber-700 dark:text-amber-300">
          <AlertTriangle className="h-4 w-4 shrink-0" />
          当前模型路由不可用，请切换模型后再发送
        </div>
      )}

      <Composer
        disabled={device ? !device.status.online : false}
        running={!!running}
        modelLabel={session ? modelLabel(session.provider, session.model, session.effort) : "…"}
        onOpenModels={() => setModelsOpen(true)}
        onStop={() => stopMut.mutate({ sessionId })}
        onSend={(text, images) => {
          sendMut.mutate({ sessionId, text, images });
        }}
      />
      {/* 空会话 bento 点击后填入前缀（复用 composer 输入，不直接发送） */}
      {bentoPrefix && (
        <BentoPrefill prefix={bentoPrefix} onDone={() => setBentoPrefix(null)} />
      )}

      {/* 模型切换弹层（每会话独立） */}
      {session && (
        <ModelSheet
          open={modelsOpen}
          onClose={() => setModelsOpen(false)}
          current={{ provider: session.provider, model: session.model, effort: session.effort }}
          failedProviders={device?.status.online ? 1 : 0}
          onSelect={(provider, model, effort) => {
            setModelMut.mutate({ id: session.id, provider, model, effort });
            setModelsOpen(false);
            toast.success(`已切换到 ${modelLabel(provider, model, effort)}`);
          }}
        />
      )}

      {/* 远程审批 */}
      <ApprovalDialog
        approval={stream.pendingApprovals[0] ?? null}
        onRespond={(rpcId, allow) => respondMut.mutate({ rpcId, allow })}
      />

      {/* 重命名 */}
      <Dialog open={renameOpen} onOpenChange={setRenameOpen}>
        <DialogContent className="max-w-[360px] rounded-[20px] bg-popover">
          <DialogHeader>
            <DialogTitle>重命名会话</DialogTitle>
          </DialogHeader>
          <Input
            value={renameValue}
            onChange={(e) => setRenameValue(e.target.value)}
            className="bg-surface-2"
          />
          <DialogFooter>
            <Button
              className="rounded-full"
              disabled={!renameValue.trim() || renameMut.isPending}
              onClick={() => session && renameMut.mutate({ id: session.id, title: renameValue.trim() })}
            >
              保存
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 会话信息 */}
      <Sheet open={infoOpen} onOpenChange={setInfoOpen}>
        <SheetContent
          side="bottom"
          className="mx-auto w-full max-w-[430px] rounded-t-[24px] border-border bg-popover pb-10"
        >
          <SheetHeader>
            <SheetTitle>会话信息</SheetTitle>
          </SheetHeader>
          {session && (
            <dl className="mt-3 space-y-3 text-sm">
              <div className="hairline rounded-2xl bg-surface-1 px-4 py-3">
                <dt className="text-xs text-faint">sessionId</dt>
                <dd className="mt-0.5 font-mono text-[13px]">{session.id}</dd>
              </div>
              <div className="hairline rounded-2xl bg-surface-1 px-4 py-3">
                <dt className="text-xs text-faint">工作目录</dt>
                <dd className="mt-0.5 font-mono text-[13px]">{session.cwd ?? "未知"}</dd>
              </div>
              <div className="hairline rounded-2xl bg-surface-1 px-4 py-3">
                <dt className="text-xs text-faint">当前模型</dt>
                <dd className="mt-0.5 font-mono text-[13px]">
                  {session.provider}/{session.model}
                  {session.effort !== "off" ? ` · 推理强度 ${session.effort}` : ""}
                </dd>
              </div>
            </dl>
          )}
        </SheetContent>
      </Sheet>
    </PhoneShell>
  );
}

// bento 点击后把前缀预填进 composer：通过自定义事件桥接
function BentoPrefill({ prefix, onDone }: { prefix: string; onDone: () => void }) {
  useEffect(() => {
    window.dispatchEvent(new CustomEvent("dsh:prefill", { detail: prefix }));
    onDone();
  }, [prefix, onDone]);
  return null;
}
