import { notFound } from "next/navigation";
import Link from "next/link";
import { ArrowRightIcon } from "lucide-react";
import { PageIntro } from "@/components/page-intro";
import { JsonLd } from "@/components/json-ld";
import { Markdown } from "@/components/markdown";
import { getPost, headline, posts } from "@/content/blog/posts";
import { breadcrumbs, organization, pageMetadata } from "@/lib/seo";
import { site } from "@/lib/site";

export const generateStaticParams = () => posts.map((p) => ({ slug: p.slug }));

export async function generateMetadata({ params }: PageProps<"/blog/[slug]">) {
  const post = getPost((await params).slug);
  if (!post) return {};
  return pageMetadata({ title: headline(post), description: post.description, path: `/blog/${post.slug}`, image: `/blog/${post.slug}/opengraph-image`, type: "article", publishedTime: post.date, keywords: post.keywords });
}

export default async function PostPage({ params }: PageProps<"/blog/[slug]">) {
  const post = getPost((await params).slug);
  if (!post) notFound();
  const url = `${site.url}/blog/${post.slug}`;
  const others = posts.filter((p) => p.slug !== post.slug);
  return (
    <div className="site-shell secondary-page">
      <JsonLd data={{
        "@context": "https://schema.org",
        "@type": "BlogPosting",
        "@id": url,
        mainEntityOfPage: url,
        url,
        headline: headline(post),
        description: post.description,
        keywords: post.keywords.join(", "),
        image: `${url}/opengraph-image`,
        datePublished: post.date,
        dateModified: post.date,
        inLanguage: "en",
        author: { "@id": organization["@id"] },
        publisher: { "@id": organization["@id"] },
        about: { "@id": `${site.url}/#app` },
      }} />
      <JsonLd data={breadcrumbs([{ name: "Blog", path: "/blog" }, { name: post.title, path: `/blog/${post.slug}` }])} />
      <PageIntro eyebrow="Blog" title={post.title} accent={post.accent}>
        <p>{post.description}</p>
        <p className="document-date">Published <time dateTime={post.date}>{new Date(post.date).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" })}</time></p>
      </PageIntro>
      <article className="prose-legal mx-auto max-w-3xl pb-16">
        <Markdown source={post.body} />
      </article>
      <nav aria-label="More posts" className="mx-auto max-w-3xl border-t pt-10 pb-24">
        <p className="eyebrow">Keep reading</p>
        <ul className="mt-4 grid gap-4">
          {others.map((p) => <li key={p.slug}><Link href={`/blog/${p.slug}`} className="text-link">{p.title} {p.accent} <ArrowRightIcon className="size-4" aria-hidden /></Link></li>)}
        </ul>
      </nav>
    </div>
  );
}
