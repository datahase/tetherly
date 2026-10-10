import { ImageResponse } from "next/og";
import { join } from "node:path";
import { readFile } from "node:fs/promises";

export const ogSize = { width: 1200, height: 630 };

const logo = readFile(join(process.cwd(), "public/logo.png"), "base64").then((b) => `data:image/png;base64,${b}`);

/** The standard Tetherly share card: logo, a two-part headline, a subline and the domain. */
export async function ogImage({ title, accent, subline, eyebrow = "Mac · iPhone · iPad · Android" }: {
  title: string;
  accent: string;
  subline: string;
  eyebrow?: string;
}) {
  const long = title.length + accent.length > 40;
  return new ImageResponse(
    <div style={{ width: "100%", height: "100%", display: "flex", flexDirection: "column", padding: "58px 76px", background: "#faf8f3", color: "#29231e" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", width: 62, height: 62, background: "#6c4a32", borderRadius: 18 }}>{/* eslint-disable-next-line @next/next/no-img-element -- next/og renders plain img only */}
        <img src={await logo} width={96} height={96} alt="" /></div>
        <div style={{ fontSize: 32, fontWeight: 600, letterSpacing: -1 }}>Tetherly</div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", marginTop: long ? 40 : 50, fontSize: long ? 64 : 86, lineHeight: 1.08, letterSpacing: long ? -2.5 : -4 }}>
        <div>{title}</div>
        <div style={{ color: "#b64d14", fontStyle: "italic" }}>{accent}</div>
      </div>
      <div style={{ marginTop: 28, fontSize: 27, color: "#74695e" }}>{subline}</div>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", borderTop: "1px solid #dfd5c6", paddingTop: 24, marginTop: "auto", fontSize: 21 }}>
        <div style={{ color: "#74695e" }}>{eyebrow}</div>
        <div style={{ color: "#b64d14" }}>tetherly.link</div>
      </div>
    </div>,
    ogSize,
  );
}
