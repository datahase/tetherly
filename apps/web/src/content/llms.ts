import { headline, posts } from "@/content/blog/posts";
import { faq } from "@/content/faq";
import { absoluteLinks } from "@/lib/markdown";
import { site } from "@/lib/site";
import releaseInfo from "@/content/changelog.json";

// llms.txt (https://llmstxt.org): a plain summary and link map for language models and answer engines.
const summary = `# ${site.name}

> ${site.name} lets you view and control your Mac's own desktop from an Android phone or tablet, an iPhone or an iPad. The phone connects directly to the Mac over the same Wi-Fi or over the user's own Tailscale network. No ${site.name} account, no ${site.name} servers in the data path. Open source under the Apache 2.0 license.

Key facts:

- Platforms: a Mac menu bar host app (macOS 14 or later, Apple silicon and Intel); clients for Android 12 or later and iOS/iPadOS 17 or later.
- Current version: ${releaseInfo.version}. The Mac and Android apps are available as direct downloads, and Android is on Google Play (${site.stores.googlePlay}); the App Store release is coming soon.
- Price: free.
- Features: live screen view (H.264), touch and trackpad pointer modes, scrolling and zoom, phone keyboard and dictation with Mac modifier keys, fn and F1–F12, a Mission Control button and multi-finger swipes, clipboard send and fetch on request, two-way file transfer with explicit acceptance, Mac audio on the phone.
- Security: QR pairing with a short code compared on both screens and approved on the Mac, then mutual TLS 1.3 with pinned keys. Keys stay in the Mac Keychain, iOS Keychain or Android Keystore.
- Connection: local network discovery on Wi-Fi; Tailscale for access away from home, with no port forwarding. The Mac host listens on TCP port 47800.
- Requirements: the Mac must be awake with ${site.name} running; it cannot be woken remotely. Mac permissions needed: Screen Recording, Accessibility and Local Network.
- Not for: helping someone else with their computer, or controlling Windows or Linux computers.
- Made by ${site.company}, ${site.country}. Contact: ${site.email.support}. Security reports: ${site.email.security}.`;

const links = (pairs: [string, string, string][]) => pairs.map(([title, path, note]) => `- [${title}](${path.startsWith("http") ? path : site.url + path}): ${note}`).join("\n");

export const llmsTxt = `${summary}

## Docs

${links([
  ["How to connect", "/setup", "Install, grant Mac permissions, pair with a QR code on Wi-Fi, and connect away from home with Tailscale."],
  ["Support and FAQ", "/support", "Pairing, permissions, the macOS firewall prompt, discovery problems, unpairing and contacting support."],
  ["Changelog", "/changelog", "Release notes."],
])}

## Blog

${links(posts.map((p) => [headline(p), `/blog/${p.slug}`, p.description]))}

## Policies

${links([
  ["Privacy Policy", "/privacy", "What stays on each device, the permissions used, and third parties."],
  ["Terms of Use", "/terms", "Terms for the apps and website."],
])}

## Optional

${links([
  ["Full text for LLMs", "/llms-full.txt", "This summary plus the FAQ and every blog post in full."],
  ["Source code", site.repo, "Mac, Android and iOS apps, and the wire protocol specification."],
  ["Wire protocol", `${site.repo}/blob/main/protocol/SPEC.md`, "The protocol between the Mac host and phone clients."],
])}
`;

export const llmsFullTxt = `${summary}

Website: ${site.url} · Source: ${site.repo}

# Frequently asked questions

${faq.map((item) => `## ${item.q}\n\n${absoluteLinks(item.a, site.url)}`).join("\n\n")}

${posts.map((p) => `# ${headline(p)}\n\nURL: ${site.url}/blog/${p.slug} · Published ${p.date}\n\n${p.description}\n\n${absoluteLinks(p.body, site.url)}`).join("\n\n")}
`;
