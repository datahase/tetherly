import { getPost, posts } from "@/content/blog/posts";
import { ogImage } from "@/lib/og";

export const alt = "A post from the Tetherly blog";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const generateStaticParams = () => posts.map((p) => ({ slug: p.slug }));

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const post = getPost((await params).slug)!;
  return ogImage({ title: post.title, accent: post.accent, subline: "From the Tetherly blog"});
}
