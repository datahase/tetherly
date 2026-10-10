import { ChevronDownIcon, ArrowRightIcon } from "lucide-react";
import Link from "next/link";
import { PageIntro } from "@/components/page-intro";
import { site } from "@/lib/site";

export type LegalSection = { id: string; title: string; body: React.ReactNode };

function Contents({ sections }: { sections: LegalSection[] }) {
  return <ol>{sections.map((section, index) => <li key={section.id}><a href={`#${section.id}`}><span aria-hidden>{String(index + 1).padStart(2, "0")}</span>{section.title}</a></li>)}</ol>;
}

/** Legal section bodies and anchor IDs stay intact; only the reading layout changes. */
export function LegalPage({ title, intro, sections, updated = true }: {
  title: string;
  intro: React.ReactNode;
  sections: LegalSection[];
  updated?: boolean;
}) {
  const split = title.lastIndexOf(" ");
  const contact = title === "Privacy Policy" ? site.email.privacy : site.email.support;
  return (
    <div className="site-shell secondary-page legal-page">
      <PageIntro eyebrow="The details" title={title.slice(0, split)} accent={`${title.slice(split + 1)}.`} aside={
        <div className="legal-contact-note"><p className="eyebrow">A question about this document?</p><p>Get in touch with DataHase.</p><a href={`mailto:${contact}`} className="text-link">{contact}<ArrowRightIcon className="size-4" aria-hidden /></a><Link href="/support" className="legal-support-link">For help with the apps, visit Support.</Link></div>
      }>
        {intro}
        {updated && <p className="document-date">Effective date and last updated: <time dateTime="2026-10-10">{site.legalEffectiveDate}</time></p>}
      </PageIntro>
      <div className="legal-reading-layout">
        <aside className="legal-sidebar">
          <nav aria-label="Contents" className="legal-desktop-contents"><h2>In this document</h2><Contents sections={sections} /></nav>
          <details className="legal-mobile-contents"><summary>In this document <ChevronDownIcon className="size-4" aria-hidden /></summary><nav aria-label="Mobile contents"><Contents sections={sections} /></nav></details>
        </aside>
        <article className="legal-article prose-legal">
          {sections.map((section, index) => <section className="legal-section" id={section.id} key={section.id} aria-labelledby={`heading-${section.id}`}><div className="legal-section-title"><span aria-hidden>{String(index + 1).padStart(2, "0")}</span><h2 id={`heading-${section.id}`}>{section.title}</h2></div>{section.body}</section>)}
        </article>
      </div>
    </div>
  );
}
