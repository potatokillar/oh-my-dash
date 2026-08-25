import { useState } from "react";
import type { Message } from "@db/schema";
import { Markdown } from "@/components/Markdown";
import { Brain, ChevronDown, ImageIcon } from "lucide-react";

function parseImages(images: string | null): string[] {
  if (!images) return [];
  try {
    return JSON.parse(images) as string[];
  } catch {
    return [];
  }
}

export function MessageBubble({ msg }: { msg: Message }) {
  const images = parseImages(msg.images);

  if (msg.role === "user") {
    return (
      <div className="msg-in flex justify-end">
        <div className="max-w-[85%] rounded-[20px] rounded-br-md bg-primary/90 px-4 py-2.5 text-primary-foreground shadow-[0_0_20px_hsl(var(--glow-warm)/0.18)]">
          {images.length > 0 && (
            <div className="mb-2 grid grid-cols-2 gap-1.5">
              {images.map((src, i) => (
                <img key={i} src={src} alt="" className="max-h-40 rounded-xl object-cover" />
              ))}
            </div>
          )}
          <p className="whitespace-pre-wrap text-[15px] leading-relaxed">{msg.content}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="msg-in flex justify-start">
      <div className="hairline max-w-[92%] rounded-[20px] rounded-bl-md bg-surface-1 px-4 py-3">
        {msg.reasoning && <ReasoningBlock text={msg.reasoning} streaming={msg.status === "streaming"} />}
        {images.length > 0 && (
          <div className="mb-2 grid grid-cols-2 gap-1.5">
            {images.map((src, i) => (
              <div key={i} className="flex items-center gap-2 rounded-xl bg-surface-2 p-2">
                <ImageIcon className="h-4 w-4 text-faint" />
                <img src={src} alt="" className="max-h-32 rounded-lg object-cover" />
              </div>
            ))}
          </div>
        )}
        {msg.content ? (
          <Markdown text={msg.content} />
        ) : msg.status === "streaming" && !msg.reasoning ? (
          <ThinkingDots />
        ) : null}
        {msg.status === "interrupted" && (
          <p className="mt-2 text-xs text-faint">已停止生成</p>
        )}
      </div>
    </div>
  );
}

// 「正在思考」三点打字动画
export function ThinkingDots() {
  return (
    <div className="flex items-center gap-1.5 py-1" aria-label="正在思考">
      <span className="typing-dot" />
      <span className="typing-dot" />
      <span className="typing-dot" />
    </div>
  );
}

// 思考过程折叠块
function ReasoningBlock({ text, streaming }: { text: string; streaming: boolean }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="mb-2">
      <button
        className="pressable flex items-center gap-1.5 text-xs font-semibold text-primary"
        onClick={() => setOpen((v) => !v)}
      >
        <Brain className="h-3.5 w-3.5" />
        思考过程
        <ChevronDown className={`h-3.5 w-3.5 transition-transform ${open ? "rotate-180" : ""}`} />
      </button>
      {open && (
        <div className="mt-1.5 rounded-xl bg-surface-2 px-3 py-2 text-[13px] leading-relaxed text-muted-foreground">
          <p className="whitespace-pre-wrap">{text}</p>
          {streaming && <ThinkingDots />}
        </div>
      )}
    </div>
  );
}
