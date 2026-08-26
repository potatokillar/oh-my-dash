import {
  AlertDialog,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import { ShieldAlert } from "lucide-react";
import type { PendingApprovalInfo } from "@/hooks/useSessionStream";

// 远程审批：智能体请求工具权限时弹出，「允许一次」/「拒绝」，应答原样回显 rpcId
export function ApprovalDialog({
  approval,
  onRespond,
}: {
  approval: PendingApprovalInfo | null;
  onRespond: (rpcId: string, allow: boolean) => void;
}) {
  return (
    <AlertDialog open={approval !== null}>
      <AlertDialogContent className="max-w-[340px] rounded-[20px] bg-popover">
        <AlertDialogHeader>
          <div className="mb-2 flex h-12 w-12 items-center justify-center rounded-2xl bg-amber-400/10">
            <ShieldAlert className="h-6 w-6 text-amber-700 dark:text-amber-300" />
          </div>
          <AlertDialogTitle className="flex items-center gap-2">
            权限审批
            <code className="rounded bg-surface-3 px-1.5 py-0.5 text-xs font-normal text-primary">
              {approval?.tool}
            </code>
          </AlertDialogTitle>
          <AlertDialogDescription>{approval?.description}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter className="flex-row gap-2 sm:justify-end">
          <Button
            variant="secondary"
            className="flex-1 rounded-full"
            onClick={() => approval && onRespond(approval.rpcId, false)}
          >
            拒绝
          </Button>
          <Button
            className="flex-1 rounded-full"
            onClick={() => approval && onRespond(approval.rpcId, true)}
          >
            允许一次
          </Button>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
