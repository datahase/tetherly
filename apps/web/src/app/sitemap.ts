import type { MetadataRoute } from "next";
import { posts } from "@/content/blog/posts";
import { site } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  const pages: [string, number][] = [["", 1], ["/setup", 0.8], ["/blog", 0.7], ["/support", 0.7], ["/changelog", 0.5], ["/privacy", 0.3], ["/terms", 0.3]];
  return [
    ...pages.map(([path, priority]) => ({ url: `${site.url}${path}`, changeFrequency: "monthly" as const, priority })),
    ...posts.map((p) => ({ url: `${site.url}/blog/${p.slug}`, lastModified: p.date, changeFrequency: "yearly" as const, priority: 0.6 })),
  ];
}
