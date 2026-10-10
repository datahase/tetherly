import Link from "next/link";
import { Fragment } from "react";
import { parseBlocks } from "@/lib/markdown";

function Inline({ text }: { text: string }) {
  return text.split(/(\[[^\]]+\]\([^)]+\)|\*\*[^*]+\*\*)/g).map((part, i) => {
    const link = part.match(/^\[([^\]]+)\]\(([^)]+)\)$/);
    if (link) return link[2].startsWith("/") ? <Link key={i} href={link[2]}>{link[1]}</Link> : <a key={i} href={link[2]}>{link[1]}</a>;
    if (part.startsWith("**") && part.endsWith("**")) return <strong key={i}>{part.slice(2, -2)}</strong>;
    return <Fragment key={i}>{part}</Fragment>;
  });
}

export function Markdown({ source }: { source: string }) {
  return parseBlocks(source).map((b, i) => {
    if ("items" in b) {
      const List = b.type;
      return <List key={i} className={b.type === "ul" ? "list-disc space-y-2 pl-5" : "list-decimal space-y-2 pl-5"}>{b.items.map((item, j) => <li key={j}><Inline text={item} /></li>)}</List>;
    }
    const Tag = b.type;
    return <Tag key={i}><Inline text={b.text} /></Tag>;
  });
}
