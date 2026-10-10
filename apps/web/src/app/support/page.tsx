import Link from "next/link";
import { ArrowRightIcon, MailIcon, LockKeyholeIcon } from "lucide-react";
import { PageIntro } from "@/components/page-intro";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { site } from "@/lib/site";
import { faq } from "@/content/faq";
import { plainText } from "@/lib/markdown";
import { pageMetadata, breadcrumbs } from "@/lib/seo";
import { JsonLd } from "@/components/json-ld";
import { Markdown } from "@/components/markdown";

export const metadata = pageMetadata({
  title: "Support",
  description: "Help with pairing, Mac permissions, the macOS firewall, Tailscale and more. Answers to common Tetherly questions, and how to contact support.",
  path: "/support",
});

const faqJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: faq.map((item) => ({ "@type": "Question", name: item.q, acceptedAnswer: { "@type": "Answer", text: plainText(item.a) } })),
};

export default function SupportPage() {
  return (
    <div className="site-shell secondary-page support-page">
      <JsonLd data={faqJsonLd} />
      <JsonLd data={breadcrumbs([{ name: "Support", path: "/support" }])} />
      <PageIntro eyebrow="Support" title="A little help," accent="when you need it." aside={
        <nav className="support-shortcuts" aria-label="Get started">
          <p className="eyebrow">Start with a connection</p>
          <Link href="/setup#local"><span>On your Wi-Fi<small>Pair nearby, in a few steps.</small></span><ArrowRightIcon className="size-5" aria-hidden /></Link>
          <Link href="/setup#tailscale"><span>Away with Tailscale<small>Find your route back to your Mac.</small></span><ArrowRightIcon className="size-5" aria-hidden /></Link>
          <a href="#contact"><span>Write to us<small>For the questions that need a hand.</small></span><ArrowRightIcon className="size-5" aria-hidden /></a>
        </nav>
      }>
        <p>Pairing, permissions, or a connection that won&apos;t work. Find the next step here, or get in touch.</p>
      </PageIntro>

      <section className="support-answers" aria-labelledby="answers-title">
        <div className="support-answers-intro"><p className="eyebrow">A good place to look</p><h2 id="answers-title">Common<br /><span className="editorial">questions.</span></h2><p>Start with the question closest to what you&apos;re seeing. For a complete walkthrough, follow the connection guide.</p><Link href="/setup" className="text-link">Open the guide <ArrowRightIcon className="size-4" aria-hidden /></Link></div>
        <Accordion className="support-faq" defaultValue={[faq[0].q]}>
          {faq.map((item, index) => (
            <AccordionItem key={item.q} value={item.q}>
              <AccordionTrigger className="support-question"><span className="step-number" aria-hidden>{String(index + 1).padStart(2, "0")}</span><span>{item.q}</span></AccordionTrigger>
              <AccordionContent className="support-answer"><Markdown source={item.a} /></AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </section>

      <section id="contact" className="support-contact" aria-labelledby="contact-title">
        <div className="support-contact-heading"><p className="eyebrow">Keep the conversation going</p><h2 id="contact-title">Write to us.</h2><p>Include your device models, OS versions, and what you were trying to do. A few clear steps help us understand the problem.</p></div>
        <div className="contact-options">
          <div><MailIcon className="size-5" strokeWidth={1.5} aria-hidden /><h3>Setup &amp; support</h3><p>Pairing, a bug, or a question about Tetherly.</p><a href={`mailto:${site.email.support}`} className="text-link">{site.email.support}<ArrowRightIcon className="size-4" aria-hidden /></a></div>
          <div><LockKeyholeIcon className="size-5" strokeWidth={1.5} aria-hidden /><h3>Security reports</h3><p>Please report security issues privately, rather than in a public issue.</p><a href={`mailto:${site.email.security}`} className="text-link">{site.email.security}<ArrowRightIcon className="size-4" aria-hidden /></a></div>
        </div>
      </section>
    </div>
  );
}
