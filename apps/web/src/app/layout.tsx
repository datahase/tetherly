import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { Providers } from "@/components/providers";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { site } from "@/lib/site";
import { organization } from "@/lib/seo";
import { AnalyticsConsent } from "@/components/analytics-consent";
import { JsonLd } from "@/components/json-ld";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: {
    default: `${site.name}: control your Mac from your phone`,
    template: `%s · ${site.name}`,
  },
  description: site.description,
  applicationName: site.name,
  authors: [{ name: site.company }],
  creator: site.company,
  publisher: site.company,
  keywords: [
    "control Mac from phone", "Mac remote desktop", "remote desktop for Mac", "control Mac from Android",
    "control Mac from iPhone", "control Mac from iPad", "Mac screen sharing app", "Tailscale remote desktop",
    "open source remote desktop", "VNC alternative for Mac", "phone as trackpad for Mac",
  ],
  category: "technology",
  alternates: { canonical: "/", types: { "application/rss+xml": [{ url: "/blog/feed.xml", title: `${site.name} blog` }] } },
  robots: { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1, "max-video-preview": -1 } },
  formatDetection: { email: false, address: false, telephone: false },
  openGraph: {
    type: "website",
    siteName: site.name,
    url: site.url,
    title: `${site.name}: control your Mac from your phone`,
    description: site.description,
    locale: "en_US",
  },
  twitter: {
    card: "summary_large_image",
    title: `${site.name}: control your Mac from your phone`,
    description: site.description,
  },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#faf8f3" },
    { media: "(prefers-color-scheme: dark)", color: "#1c1814" },
  ],
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" data-scroll-behavior="smooth" suppressHydrationWarning className={`${geistSans.variable} ${geistMono.variable} antialiased`}>
      <body className="flex min-h-dvh flex-col">
        <JsonLd data={{
          "@context": "https://schema.org",
          "@graph": [
            organization,
            { "@type": "WebSite", "@id": `${site.url}/#website`, url: site.url, name: site.name, description: site.description, publisher: { "@id": organization["@id"] }, inLanguage: "en" },
          ],
        }} />
        <Providers>
          <SiteHeader />
          <main id="main" className="flex-1">
            {children}
          </main>
          <SiteFooter />
          <AnalyticsConsent />
        </Providers>
      </body>
    </html>
  );
}
