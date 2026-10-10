// Tiny markdown subset shared by the site, JSON-LD and llms-full.txt: ## / ### headings, paragraphs,
// "- " and "1. " lists, [links](href) and **bold**. shortcut: no nesting or code blocks; use MDX if posts need them.
export type Block =
  | { type: "h2" | "h3" | "p"; text: string }
  | { type: "ul" | "ol"; items: string[] };

export function parseBlocks(md: string): Block[] {
  return md.trim().split(/\n\s*\n/).map((chunk): Block => {
    const lines = chunk.trim().split("\n").map((l) => l.trim());
    if (lines[0].startsWith("### ")) return { type: "h3", text: lines[0].slice(4) };
    if (lines[0].startsWith("## ")) return { type: "h2", text: lines[0].slice(3) };
    if (lines.every((l) => l.startsWith("- "))) return { type: "ul", items: lines.map((l) => l.slice(2)) };
    if (lines.every((l) => /^\d+\. /.test(l))) return { type: "ol", items: lines.map((l) => l.replace(/^\d+\. /, "")) };
    return { type: "p", text: lines.join(" ") };
  });
}

/** Plain text for JSON-LD: links keep their label, bold markers go. */
export function plainText(md: string): string {
  return md.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1").replace(/\*\*/g, "").replace(/\n\s*\n/g, "\n").replace(/^- /gm, "• ").trim();
}

/** Absolute links for llms-full.txt, which is read outside the site. */
export function absoluteLinks(md: string, origin: string): string {
  return md.replace(/\]\((\/[^)]*)\)/g, `](${origin}$1)`);
}
