import { useMemo, type ReactNode } from "react";

// 轻量 Markdown 渲染：代码块、行内代码、加粗、标题、有序/无序列表、引用
export function Markdown({ text }: { text: string }) {
  const blocks = useMemo(() => parseBlocks(text), [text]);
  return (
    <div className="space-y-2 text-[15px] leading-relaxed">
      {blocks.map((b, i) => {
        if (b.type === "code") {
          return (
            <pre
              key={i}
              className="overflow-x-auto rounded-xl bg-[hsl(var(--code-bg))] p-3 text-[13px] leading-relaxed text-zinc-200"
            >
              <code>{b.content}</code>
            </pre>
          );
        }
        if (b.type === "heading") {
          return (
            <p key={i} className="pt-1 text-[16px] font-bold">
              {renderInline((b as { content: string }).content)}
            </p>
          );
        }
        if (b.type === "ol") {
          return (
            <ol key={i} className="list-decimal space-y-1 pl-5 marker:text-faint">
              {b.items.map((it, j) => (
                <li key={j}>{renderInline(it)}</li>
              ))}
            </ol>
          );
        }
        if (b.type === "ul") {
          return (
            <ul key={i} className="list-disc space-y-1 pl-5 marker:text-faint">
              {b.items.map((it, j) => (
                <li key={j}>{renderInline(it)}</li>
              ))}
            </ul>
          );
        }
        if (b.type === "quote") {
          return (
            <blockquote key={i} className="border-l-2 border-primary/50 pl-3 text-muted-foreground">
              {renderInline((b as { content: string }).content)}
            </blockquote>
          );
        }
        return <p key={i}>{renderInline((b as { content: string }).content)}</p>;
      })}
    </div>
  );
}

type Block =
  | { type: "p" | "code" | "heading" | "quote"; content: string }
  | { type: "ol" | "ul"; items: string[] };

function parseBlocks(text: string): Block[] {
  const blocks: Block[] = [];
  const pushText = (seg: string) => {
    for (const para of seg.split(/\n{2,}/)) {
      const t = para.trim();
      if (!t) continue;
      const lines = t.split("\n");
      if (lines.every((l) => /^\s*[-*]\s+/.test(l))) {
        blocks.push({ type: "ul", items: lines.map((l) => l.replace(/^\s*[-*]\s+/, "")) });
      } else if (lines.every((l) => /^\s*\d+\.\s+/.test(l))) {
        blocks.push({ type: "ol", items: lines.map((l) => l.replace(/^\s*\d+\.\s+/, "")) });
      } else if (t.startsWith("> ")) {
        blocks.push({ type: "quote", content: t.replace(/^>\s?/gm, "") });
      } else if (t.startsWith("#")) {
        blocks.push({ type: "heading", content: t.replace(/^#+\s*/, "") });
      } else {
        blocks.push({ type: "p", content: t });
      }
    }
  };

  const re = /```(\w*)\n?([\s\S]*?)```/g;
  let last = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    pushText(text.slice(last, m.index));
    blocks.push({ type: "code", content: m[2].trim() });
    last = re.lastIndex;
  }
  const rest = text.slice(last);
  // 流式输出中未闭合的代码块：``` 之后的内容按代码渲染
  const openIdx = rest.indexOf("```");
  if (openIdx >= 0) {
    pushText(rest.slice(0, openIdx));
    const code = rest.slice(openIdx).replace(/^```\w*\n?/, "");
    if (code.trim()) blocks.push({ type: "code", content: code.trim() });
  } else {
    pushText(rest);
  }
  return blocks;
}

function renderInline(text: string): ReactNode[] {
  // 行内代码、加粗
  const parts = text.split(/(`[^`]+`|\*\*[^*]+\*\*)/g);
  return parts.map((p, i) => {
    if (p.startsWith("`") && p.endsWith("`")) {
      return (
        <code key={i} className="rounded bg-surface-3 px-1.5 py-0.5 text-[13px] font-semibold text-accent-foreground">
          {p.slice(1, -1)}
        </code>
      );
    }
    if (p.startsWith("**") && p.endsWith("**")) {
      return (
        <strong key={i} className="font-bold text-foreground">
          {p.slice(2, -2)}
        </strong>
      );
    }
    return <span key={i}>{p}</span>;
  });
}
