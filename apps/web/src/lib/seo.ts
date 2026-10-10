import type { Metadata } from "next";
import { site } from "@/lib/site";

/** Per-page metadata. Pages must set their own openGraph/twitter, or they inherit the home page's title and URL. */
export function pageMetadata({ title, description, path, type = "website", publishedTime, keywords, image = "/opengraph-image" }: {
  title: string;
  description: string;
  path: string;
  type?: "website" | "article";
  publishedTime?: string;
  keywords?: string[];
  image?: string;
}): Metadata {
  const images = [{ url: image, width: 1200, height: 630, alt: title }];
  const fullTitle = `${title} · ${site.name}`;
  return {
    title,
    description,
    keywords,
    alternates: { canonical: path },
    openGraph: {
      type, url: path, title: fullTitle, description, siteName: site.name, locale: "en_US", images,
      ...(type === "article" && { publishedTime, authors: [site.company] }),
    },
    twitter: { card: "summary_large_image", title: fullTitle, description, images },
  };
}

export const organization = {
  "@type": "Organization",
  "@id": `${site.url}/#organization`,
  name: site.company,
  url: site.url,
  logo: `${site.url}/logo.png`,
  email: site.email.support,
  sameAs: [site.repo],
};

export function breadcrumbs(items: { name: string; path: string }[]) {
  return {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [{ name: site.name, path: "" }, ...items].map((item, i) => ({
      "@type": "ListItem", position: i + 1, name: item.name, item: `${site.url}${item.path}`,
    })),
  };
}
