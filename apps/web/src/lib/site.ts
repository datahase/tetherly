// Single source for names, links and contacts used across the site.
export const site = {
  name: "Tetherly",
  url: "https://tetherly.link",
  description:
    "View and control your Mac from Android, iPhone, or iPad over Wi-Fi or Tailscale. No Tetherly account needed. Open source.",
  repo: "https://github.com/datahase/tetherly",
  downloads: {
    mac: "https://assets.tetherly.link/releases/0.1.0/20261010.6/Tetherly-0.1.0.dmg",
    android: "https://assets.tetherly.link/releases/0.1.0/20261010.6/Tetherly-0.1.0.apk",
  },
  stores: {
    googlePlay: "https://play.google.com/store/apps/details?id=link.tetherly",
  },
  company: "DataHase Dev Private Limited",
  country: "India",
  email: {
    privacy: "privacy@tetherly.link",
    support: "support@tetherly.link",
    security: "security@tetherly.link",
  },
  /** Set NEXT_PUBLIC_GA_MEASUREMENT_ID at build time; analytics and the consent banner are off without it. */
  googleAnalyticsId: process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID ?? "",
  legalEffectiveDate: "10 October 2026",
} as const;
