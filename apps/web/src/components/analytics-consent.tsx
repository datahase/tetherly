"use client";

import { GoogleAnalytics, sendGAEvent } from "@next/third-parties/google";
import Link from "next/link";
import { useEffect, useState, useSyncExternalStore } from "react";
import { REGION_COOKIE } from "@/lib/consent";
import { site } from "@/lib/site";

const CHOICE_KEY = "tl_analytics_consent"; // "granted" | "denied", kept in localStorage
const CHANGED = "tl:consent-changed";
const OPEN_SETTINGS = "tl:cookie-settings";

function subscribe(onChange: () => void) {
  window.addEventListener(CHANGED, onChange);
  window.addEventListener("storage", onChange);
  return () => {
    window.removeEventListener(CHANGED, onChange);
    window.removeEventListener("storage", onChange);
  };
}

const readRegion = () => (new RegExp(`(?:^|; )${REGION_COOKIE}=open`).test(document.cookie) ? "open" : "consent");
const snapshot = () => `${readRegion()}|${localStorage.getItem(CHOICE_KEY) ?? ""}`;

/** Expires Google Analytics cookies (_ga, _ga_<id>) on every domain level they may have been set on. */
function clearAnalyticsCookies() {
  const host = location.hostname;
  const domains = ["", host, `.${host}`, `.${host.split(".").slice(-2).join(".")}`];
  for (const name of document.cookie.split("; ").map((c) => c.split("=")[0]).filter((n) => n.startsWith("_ga"))) {
    for (const domain of domains) document.cookie = `${name}=; Max-Age=0; path=/${domain ? `; domain=${domain}` : ""}`;
  }
}

/**
 * Loads Google Analytics only with consent where the law requires opt-in (EU, EEA, UK, Switzerland, or unknown),
 * and by default elsewhere. Everyone can change the choice from "Cookie settings" in the footer.
 */
export function AnalyticsConsent() {
  const state = useSyncExternalStore(subscribe, snapshot, () => null);
  const [settingsOpen, setSettingsOpen] = useState(false);

  useEffect(() => {
    const open = () => setSettingsOpen(true);
    window.addEventListener(OPEN_SETTINGS, open);
    return () => window.removeEventListener(OPEN_SETTINGS, open);
  }, []);

  const [region, choice] = (state ?? "|").split("|");
  const optIn = region !== "open";
  const granted = !!state && (choice === "granted" || (!optIn && choice !== "denied"));

  // Counts clicks on links marked data-download="<platform>" as GA4 file_download events.
  useEffect(() => {
    if (!granted) return;
    const onClick = (e: MouseEvent) => {
      const link = (e.target as Element | null)?.closest<HTMLAnchorElement>("a[data-download]");
      if (!link) return;
      sendGAEvent("event", "file_download", {
        platform: link.dataset.download,
        file_name: link.pathname.split("/").pop(),
        link_url: link.href,
      });
    };
    document.addEventListener("click", onClick);
    return () => document.removeEventListener("click", onClick);
  }, [granted]);

  if (!state || !site.googleAnalyticsId) return null; // server render and hydration: decide on the client only
  const showBanner = settingsOpen || (optIn && !choice);

  const choose = (next: "granted" | "denied") => {
    localStorage.setItem(CHOICE_KEY, next);
    setSettingsOpen(false);
    if (next === "denied" && granted) {
      // The analytics script is already running; stop it, remove its cookies and start clean.
      (window as unknown as Record<string, boolean>)[`ga-disable-${site.googleAnalyticsId}`] = true;
      clearAnalyticsCookies();
      location.reload();
      return;
    }
    window.dispatchEvent(new Event(CHANGED));
  };

  const button = "inline-flex min-h-11 flex-1 items-center justify-center rounded-full border border-foreground/25 px-5 text-sm font-medium transition-colors hover:bg-foreground/5 focus-visible:outline-2 focus-visible:outline-offset-2 sm:flex-none";

  return (
    <>
      {granted && <GoogleAnalytics gaId={site.googleAnalyticsId} />}
      {showBanner && (
        <div
          role="dialog"
          aria-modal="false"
          aria-labelledby="consent-title"
          aria-describedby="consent-description"
          className="fixed inset-x-3 bottom-3 z-50 mx-auto max-w-xl rounded-2xl border border-border bg-popover p-5 text-popover-foreground shadow-lg sm:bottom-5"
        >
          <h2 id="consent-title" className="text-base font-semibold">Analytics cookies</h2>
          <p id="consent-description" className="mt-2 text-sm leading-relaxed text-muted-foreground">
            May we use Google Analytics cookies to understand how people find and use this website? They are only set
            if you agree. This doesn&apos;t affect the Tetherly apps, which contain no analytics.{" "}
            <Link href="/privacy#website" className="underline underline-offset-2">Privacy Policy</Link>
            {settingsOpen && <><br />Currently: analytics {granted ? "on" : "off"}.</>}
          </p>
          <div className="mt-4 flex gap-3">
            <button type="button" className={button} onClick={() => choose("denied")}>Reject</button>
            <button type="button" className={button} onClick={() => choose("granted")}>Accept</button>
          </div>
        </div>
      )}
    </>
  );
}

export function CookieSettingsButton({ className }: { className?: string }) {
  if (!site.googleAnalyticsId) return null;
  return (
    <button type="button" className={className} onClick={() => window.dispatchEvent(new Event(OPEN_SETTINGS))}>
      Cookie settings
    </button>
  );
}
