import { pageMetadata, breadcrumbs } from "@/lib/seo";
import { JsonLd } from "@/components/json-ld";
import { PageIntro } from "@/components/page-intro";
import changelog from "@/content/changelog.json";

export const metadata = pageMetadata({
  title: "Changelog",
  description: "Tetherly release notes and version history for the Mac, Android and iOS apps.",
  path: "/changelog",
});

export default function ChangelogPage() {
  return <div>
      <JsonLd data={breadcrumbs([{ name: "Changelog", path: "/changelog" }])} />
    <PageIntro eyebrow="Release notes" title="What changed," accent="version by version.">
      <p>Tetherly is currently version {changelog.version}. Find what changed in each release below.</p>
    </PageIntro>
    <section className="section-shell" style={{ maxWidth: 760, margin: "0 auto", padding: "0 24px 80px" }}>
      <div className="space-y-4" style={{ lineHeight: 1.8 }}>
        {changelog.markdown.split("\n").filter(line => line && line !== "# Changelog").map((line, index) =>
          line.startsWith("## ") ? <h2 className="text-2xl" key={index}>Version {line.slice(3)}</h2> :
          line.startsWith("- ") ? <p key={index}>{line.slice(2)}</p> : <p className="text-sm" key={index}>{line}</p>
        )}
      </div>
    </section>
  </div>;
}
