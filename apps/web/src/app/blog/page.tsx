import Link from "next/link";
import { ArrowRightIcon } from "lucide-react";
import { PageIntro } from "@/components/page-intro";
import { JsonLd } from "@/components/json-ld";
import { headline, posts } from "@/content/blog/posts";
import { breadcrumbs, organization, pageMetadata } from "@/lib/seo";
import { site } from "@/lib/site";

export const metadata = pageMetadata({
  title: "Blog",
  description: "Guides and notes on using your Mac from your phone or tablet: how Tetherly differs from other remote desktop apps, setup on Android, and remote access with Tailscale.",
  path: "/blog",
});

const date = (d: string) => new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" });

export default function BlogPage() {
  return (
    <div className="site-shell secondary-page">
      <JsonLd data={{
        "@context": "https://schema.org",
        "@type": "Blog",
        "@id": `${site.url}/blog`,
        name: `${site.name} blog`,
        url: `${site.url}/blog`,
        publisher: { "@id": organization["@id"] },
        blogPost: posts.map((p) => ({ "@type": "BlogPosting", headline: headline(p), url: `${site.url}/blog/${p.slug}`, datePublished: p.date })),
      }} />
      <JsonLd data={breadcrumbs([{ name: "Blog", path: "/blog" }])} />
      <PageIntro eyebrow="Blog" title="Notes from" accent="a little closer.">
        <p>Guides for getting the most from your Mac on your phone or tablet, and the thinking behind Tetherly.</p>
      </PageIntro>
      <ul className="mx-auto grid max-w-3xl gap-10 pt-12 pb-24">
        {posts.map((p) => (
          <li key={p.slug}>
            <article>
              <p className="eyebrow"><time dateTime={p.date}>{date(p.date)}</time></p>
              <h2 className="mt-2 text-2xl font-semibold tracking-tight"><Link href={`/blog/${p.slug}`}>{p.title} <span className="editorial">{p.accent}</span></Link></h2>
              <p className="mt-3 text-muted-foreground">{p.description}</p>
              <Link href={`/blog/${p.slug}`} className="text-link mt-3" aria-label={`Read: ${p.title} ${p.accent}`}>Read the post <ArrowRightIcon className="size-4" aria-hidden /></Link>
            </article>
          </li>
        ))}
      </ul>
    </div>
  );
}
