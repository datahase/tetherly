import Link from "next/link";
import { ArrowRightIcon, FileTextIcon, HistoryIcon, LifeBuoyIcon, NewspaperIcon, ShieldCheckIcon } from "lucide-react";
import type { ComponentType } from "react";
import type { LucideProps } from "lucide-react";
import { site } from "@/lib/site";
import { CookieSettingsButton } from "@/components/analytics-consent";

type FooterLink = { href: string; label: string; desktopHidden?: boolean; icon?: ComponentType<LucideProps> };

const groups: { label: string; links: FooterLink[] }[] = [
  { label: "Explore", links: [{ href: "/#features", label: "Explore Tetherly", desktopHidden: true }, { href: "/setup", label: "How to connect", desktopHidden: true }, { href: "/blog", label: "Blog", icon: NewspaperIcon }, { href: "/changelog", label: "Changelog", icon: HistoryIcon }, { href: "/support", label: "Get support", icon: LifeBuoyIcon }] },
  { label: "Information", links: [{ href: "/privacy", label: "Privacy", icon: ShieldCheckIcon }, { href: "/terms", label: "Terms", icon: FileTextIcon }, { href: site.repo, label: "GitHub", icon: GithubMark }] },
];

function GithubMark({ className }: LucideProps) {
  return <svg className={className} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .9a11.1 11.1 0 0 0-3.51 21.63c.55.1.75-.24.75-.53v-2.1c-3.06.66-3.7-1.3-3.7-1.3-.5-1.28-1.23-1.62-1.23-1.62-.99-.68.08-.67.08-.67 1.09.08 1.67 1.12 1.67 1.12.97 1.66 2.54 1.18 3.16.9.1-.7.38-1.18.69-1.45-2.44-.28-5.01-1.22-5.01-5.44 0-1.2.43-2.19 1.13-2.96-.11-.28-.49-1.4.11-2.92 0 0 .92-.29 3.03 1.13a10.45 10.45 0 0 1 5.52 0c2.1-1.42 3.02-1.13 3.02-1.13.6 1.52.22 2.64.11 2.92.7.77 1.13 1.76 1.13 2.96 0 4.23-2.57 5.15-5.02 5.42.39.34.73 1 .73 2.02v3.01c0 .29.2.64.76.53A11.1 11.1 0 0 0 12 .9Z" /></svg>;
}

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="site-shell">
        <div className="footer-invitation">
          <div><p className="eyebrow">Start where you are</p><h2><span className="footer-desktop-copy">A little closer.<br /><span className="editorial">Even from a little further.</span></span><span className="footer-mobile-copy">Your Mac,<br /><span className="editorial">within reach.</span></span></h2></div>
          <div><p>Your Wi-Fi at home. Tailscale when you&apos;re away.<br />We&apos;ll walk you through both.</p><Link href="/setup" className="text-link">Find your connection <ArrowRightIcon className="size-4" aria-hidden /></Link></div>
        </div>
        <div className="footer-main">
          {groups.map((group) => <nav aria-label={group.label} key={group.label}><h3>{group.label}</h3><ul>{group.links.map((link) => <li className={link.desktopHidden ? "footer-desktop-hidden" : undefined} key={link.href}><Link href={link.href}>{link.icon && <link.icon className="footer-link-icon" strokeWidth={1.7} aria-hidden />}{link.label}</Link></li>)}</ul></nav>)}
        </div>
        <div className="footer-bottom"><p>© 2026 Tetherly. <CookieSettingsButton className="ml-3 underline underline-offset-2 hover:text-foreground" /></p></div>
      </div>
    </footer>
  );
}
