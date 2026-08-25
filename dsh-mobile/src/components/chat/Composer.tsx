import { useEffect, useRef, useState } from "react";
import { Button } from "@/components/ui/button";
import { ArrowUp, ImagePlus, Square, X, Sparkles } from "lucide-react";
import { toast } from "sonner";

export const QUICK_ACTIONS = [
  { label: "写代码", prefix: "写代码：" },
  { label: "解释概念", prefix: "解释一下这个概念：" },
  { label: "头脑风暴", prefix: "头脑风暴：" },
  { label: "总结文字", prefix: "总结一下：" },
];

async function compressImage(file: File): Promise<string> {
  const bmp = await createImageBitmap(file);
  const MAX = 1024;
  const scale = Math.min(1, MAX / Math.max(bmp.width, bmp.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bmp.width * scale);
  canvas.height = Math.round(bmp.height * scale);
  canvas.getContext("2d")!.drawImage(bmp, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL("image/jpeg", 0.72);
}

export function Composer({
  disabled,
  running,
  modelLabel,
  onOpenModels,
  onSend,
  onStop,
}: {
  disabled: boolean;
  running: boolean;
  modelLabel: string;
  onOpenModels: () => void;
  onSend: (text: string, images: string[]) => void;
  onStop: () => void;
}) {
  const [text, setText] = useState("");
  const [images, setImages] = useState<string[]>([]);
  const fileRef = useRef<HTMLInputElement>(null);
  const areaRef = useRef<HTMLTextAreaElement>(null);

  const canSend = (text.trim().length > 0 || images.length > 0) && !running && !disabled;

  // 空会话 bento 卡片点击后预填提示词前缀（不直接发送）
  useEffect(() => {
    const handler = (e: Event) => {
      const prefix = (e as CustomEvent<string>).detail;
      setText((t) => (t.startsWith(prefix) ? t : prefix + t));
      areaRef.current?.focus();
    };
    window.addEventListener("dsh:prefill", handler);
    return () => window.removeEventListener("dsh:prefill", handler);
  }, []);

  const submit = () => {
    if (!canSend) return;
    onSend(text.trim(), images);
    setText("");
    setImages([]);
    if (areaRef.current) areaRef.current.style.height = "auto";
  };

  const pickImages = async (files: FileList | null) => {
    if (!files) return;
    const rest = 9 - images.length;
    if (rest <= 0) return toast.info("最多添加 9 张图片");
    for (const f of [...files].slice(0, rest)) {
      try {
        const dataUrl = await compressImage(f);
        setImages((prev) => [...prev, dataUrl]);
      } catch {
        toast.error("图片处理失败");
      }
    }
  };

  return (
    <div className="shrink-0 px-3 pb-4 pt-1">
      {/* 快捷操作：横滑 chip，点击填入提示词前缀，不直接发送 */}
      <div className="mb-2 flex gap-2 overflow-x-auto px-1 pb-1">
        {QUICK_ACTIONS.map((a) => (
          <button
            key={a.label}
            className="pressable flex shrink-0 items-center gap-1 rounded-full hairline bg-surface-1 px-3 py-1.5 text-xs font-semibold text-muted-foreground"
            onClick={() => {
              setText((t) => (t.startsWith(a.prefix) ? t : a.prefix + t));
              areaRef.current?.focus();
            }}
          >
            <Sparkles className="h-3 w-3 text-primary" />
            {a.label}
          </button>
        ))}
      </div>

      <div className="composer-glow rounded-[24px] bg-surface-1 p-2">
        {images.length > 0 && (
          <div className="flex gap-2 overflow-x-auto px-1 pb-2">
            {images.map((src, i) => (
              <div key={i} className="relative shrink-0">
                <img src={src} alt="" className="h-16 w-16 rounded-xl object-cover" />
                <button
                  className="absolute -right-1.5 -top-1.5 rounded-full bg-zinc-700 p-0.5 text-white"
                  onClick={() => setImages((prev) => prev.filter((_, j) => j !== i))}
                  aria-label="移除图片"
                >
                  <X className="h-3 w-3" />
                </button>
              </div>
            ))}
          </div>
        )}
        <textarea
          ref={areaRef}
          rows={1}
          value={text}
          disabled={disabled}
          placeholder={disabled ? "设备离线，无法发送" : "发消息…"}
          className="max-h-36 w-full resize-none bg-transparent px-2 py-1.5 text-[15px] outline-none placeholder:text-faint"
          onChange={(e) => {
            setText(e.target.value);
            const el = e.target;
            el.style.height = "auto";
            el.style.height = Math.min(el.scrollHeight, 144) + "px";
          }}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
              e.preventDefault();
              submit();
            }
          }}
        />
        <div className="flex items-center gap-1 px-1">
          {/* composer 内模型 chip */}
          <button
            className="pressable max-w-[45%] truncate rounded-full bg-surface-3 px-3 py-1.5 text-xs font-semibold text-accent-foreground"
            onClick={onOpenModels}
          >
            {modelLabel}
          </button>
          <div className="flex-1" />
          <button
            className="pressable rounded-full p-2 text-muted-foreground"
            onClick={() => fileRef.current?.click()}
            aria-label="添加图片"
          >
            <ImagePlus className="h-5 w-5" />
          </button>
          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            multiple
            hidden
            onChange={(e) => {
              void pickImages(e.target.files);
              e.target.value = "";
            }}
          />
          {running ? (
            <Button
              size="icon"
              variant="secondary"
              className="h-9 w-9 rounded-full"
              onClick={onStop}
              aria-label="停止生成"
            >
              <Square className="h-4 w-4 fill-current" />
            </Button>
          ) : (
            <Button
              size="icon"
              className="h-9 w-9 rounded-full"
              disabled={!canSend}
              onClick={submit}
              aria-label="发送"
            >
              <ArrowUp className="h-5 w-5" />
            </Button>
          )}
        </div>
      </div>
    </div>
  );
}
