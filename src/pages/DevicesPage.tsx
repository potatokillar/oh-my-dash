import { useState } from "react";
import { useNavigate } from "react-router";
import { trpc } from "@/providers/trpc";
import { PhoneShell, PageHeader } from "@/components/Chrome";
import { EmptyState, GlowOrb } from "@/components/EmptyState";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/ThemeToggle";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Server, Plus, Pencil, Trash2, Wifi, WifiOff, LoaderCircle } from "lucide-react";

export const LAST_DEVICE_KEY = "dsh.lastDeviceId";

export default function DevicesPage() {
  const navigate = useNavigate();
  const utils = trpc.useUtils();
  const { data: deviceList, isLoading } = trpc.devices.list.useQuery(undefined, {
    refetchOnMount: "always",
    staleTime: 0,
  });

  const [editorOpen, setEditorOpen] = useState(false);
  const [editing, setEditing] = useState<{ id: number; name: string; address: string } | null>(null);
  const [name, setName] = useState("");
  const [address, setAddress] = useState("");
  const [formError, setFormError] = useState("");
  const [deleting, setDeleting] = useState<number | null>(null);

  const invalidate = () => utils.devices.list.invalidate();
  const addMut = trpc.devices.add.useMutation({
    onSuccess: (d) => {
      invalidate();
      setEditorOpen(false);
      connect(d.id);
    },
    onError: (e) => setFormError(e.message),
  });
  const updateMut = trpc.devices.update.useMutation({
    onSuccess: () => {
      invalidate();
      setEditorOpen(false);
    },
    onError: (e) => setFormError(e.message),
  });
  const removeMut = trpc.devices.remove.useMutation({ onSuccess: invalidate });

  const connect = (id: number) => {
    localStorage.setItem(LAST_DEVICE_KEY, String(id));
    navigate(`/d/${id}`);
  };

  const openAdd = () => {
    setEditing(null);
    setName("");
    setAddress("");
    setFormError("");
    setEditorOpen(true);
  };
  const openEdit = (d: { id: number; name: string; address: string }) => {
    setEditing(d);
    setName(d.name);
    setAddress(d.address);
    setFormError("");
    setEditorOpen(true);
  };

  return (
    <PhoneShell>
      <PageHeader
        title="设备"
        subtitle="每台设备对应一个运行中的 dsh web 主机"
        right={
          <div className="flex items-center gap-2">
            <ThemeToggle />
            <Button size="icon" variant="secondary" className="rounded-full h-9 w-9" onClick={openAdd}>
              <Plus className="h-5 w-5" />
            </Button>
          </div>
        }
      />

      <div className="flex-1 overflow-y-auto px-4 pb-8">
        {isLoading ? (
          <div className="space-y-3 pt-2" aria-label="加载中">
            {[0, 1, 2].map((i) => (
              <div key={i} className="skeleton-line h-[92px] !rounded-[20px]" />
            ))}
            <p className="flex items-center justify-center gap-2 pt-1 text-xs text-faint">
              <LoaderCircle className="h-3.5 w-3.5 animate-spin" />
              正在探测设备状态…
            </p>
          </div>
        ) : !deviceList?.length ? (
          <div className="flex h-full flex-col">
            <div className="flex justify-center pt-16 pb-8">
              <GlowOrb size={88} />
            </div>
            <EmptyState
              icon={Server}
              title="还没有设备"
              hint="添加一台运行 dsh web 的主机，随时随地在手机上继续你的智能体会话"
            />
            <div className="flex justify-center">
              <Button onClick={openAdd} className="rounded-full px-6">
                <Plus className="mr-1 h-4 w-4" /> 添加设备
              </Button>
            </div>
          </div>
        ) : (
          <ul className="reveal-stagger space-y-3 pt-2">
            {deviceList.map((d, i) => (
              <li key={d.id} style={{ ["--i" as string]: i }}>
                <div
                  className="pressable hairline cursor-pointer rounded-[20px] bg-surface-1 p-4"
                  onClick={() => d.status.online && connect(d.id)}
                >
                  <div className="flex items-center gap-3">
                    <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-surface-3">
                      <Server className="h-5 w-5 text-primary" strokeWidth={1.6} />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="truncate text-[15px] font-bold">{d.name}</span>
                        {d.status.online ? (
                          <span className="pulse-dot flex items-center gap-1 rounded-full bg-emerald-400/10 px-2 py-0.5 text-[11px] font-semibold text-emerald-600 dark:text-emerald-300">
                            <Wifi className="h-3 w-3" /> 在线
                          </span>
                        ) : (
                          <span className="flex items-center gap-1 rounded-full bg-zinc-500/10 px-2 py-0.5 text-[11px] font-semibold text-zinc-400">
                            <WifiOff className="h-3 w-3" /> 离线
                          </span>
                        )}
                      </div>
                      <p className="mt-0.5 truncate text-xs text-muted-foreground">{d.address}</p>
                      <p className="mt-0.5 truncate text-xs text-faint">
                        {d.status.online
                          ? `${d.status.model ?? "未知模型"} · ${d.status.cwd ?? ""}`
                          : d.status.reason ?? "无法连接"}
                      </p>
                    </div>
                    <div className="flex shrink-0 flex-col gap-1">
                      <button
                        className="pressable rounded-full p-2 text-muted-foreground"
                        aria-label="编辑"
                        onClick={(e) => {
                          e.stopPropagation();
                          openEdit(d);
                        }}
                      >
                        <Pencil className="h-4 w-4" />
                      </button>
                      <button
                        className="pressable rounded-full p-2 text-muted-foreground"
                        aria-label="删除"
                        onClick={(e) => {
                          e.stopPropagation();
                          setDeleting(d.id);
                        }}
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>

      {/* 添加 / 编辑设备 */}
      <Dialog open={editorOpen} onOpenChange={setEditorOpen}>
        <DialogContent className="max-w-[360px] rounded-[20px] bg-popover">
          <DialogHeader>
            <DialogTitle>{editing ? "编辑设备" : "添加设备"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5">
              <Label htmlFor="dev-name">名称</Label>
              <Input
                id="dev-name"
                placeholder="例如：家里的工作站"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="bg-surface-2"
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="dev-addr">地址</Label>
              <Input
                id="dev-addr"
                placeholder="例如：100.103.29.13:3080"
                value={address}
                onChange={(e) => setAddress(e.target.value)}
                className="bg-surface-2"
              />
            </div>
            {formError && <p className="text-xs text-destructive">{formError}</p>}
          </div>
          <DialogFooter>
            <Button
              className="rounded-full"
              disabled={addMut.isPending || updateMut.isPending}
              onClick={() => {
                setFormError("");
                if (editing) updateMut.mutate({ id: editing.id, name, address });
                else addMut.mutate({ name, address });
              }}
            >
              {editing ? "保存" : "添加"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* 删除二次确认 */}
      <AlertDialog open={deleting !== null} onOpenChange={() => setDeleting(null)}>
        <AlertDialogContent className="max-w-[340px] rounded-[20px] bg-popover">
          <AlertDialogHeader>
            <AlertDialogTitle>删除这台设备？</AlertDialogTitle>
            <AlertDialogDescription>
              将从列表中移除该设备及其连接配置，此操作不可撤销。
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel className="rounded-full">取消</AlertDialogCancel>
            <AlertDialogAction
              className="rounded-full bg-destructive text-destructive-foreground"
              onClick={() => {
                if (deleting !== null) removeMut.mutate({ id: deleting });
                setDeleting(null);
              }}
            >
              删除
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </PhoneShell>
  );
}
