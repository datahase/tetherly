import { site } from "@/lib/site";
import releaseInfo from "@/content/changelog.json";
import Image from "next/image";
import Link from "next/link";
import { ArrowDownIcon, ArrowRightIcon, CheckIcon, MonitorIcon, SmartphoneIcon, TabletIcon } from "lucide-react";
import { FeatureStories } from "@/components/feature-stories";
import { Entrance, Reveal } from "@/components/reveal";
import { JsonLd } from "@/components/json-ld";
import { organization } from "@/lib/seo";

const app = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "@id": `${site.url}/#app`,
  name: site.name,
  description: site.description,
  url: site.url,
  image: `${site.url}/opengraph-image`,
  applicationCategory: "UtilitiesApplication",
  applicationSubCategory: "Remote desktop",
  operatingSystem: "macOS 14 or later, Android 12 or later, iOS 17 or later, iPadOS 17 or later",
  softwareVersion: releaseInfo.version,
  downloadUrl: [site.downloads.mac, site.downloads.android],
  license: "https://www.apache.org/licenses/LICENSE-2.0",
  isAccessibleForFree: true,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
  publisher: { "@id": organization["@id"] },
  featureList: [
    "View and control your Mac's desktop from a phone or tablet",
    "Touch and trackpad pointer modes, scrolling and zoom",
    "Phone keyboard and dictation, Mac shortcuts and function keys",
    "Clipboard sharing and two-way file transfer on request",
    "Mac audio on the phone",
    "Direct connection over Wi-Fi or Tailscale, no Tetherly account",
    "QR pairing with code comparison and mutual TLS 1.3",
  ],
};

const steps = [
  { title: "Start with your Mac.", body: "Install the menu bar app and allow screen and control access. Connect your phone to the same Wi-Fi, or use Tailscale." },
  { title: "Make the introduction.", body: "Scan the Mac's QR code with your phone. Check that the short codes on both screens match, then approve on your Mac." },
  { title: "Settle in.", body: "Your desktop is ready to view and control. Your devices remember the pairing for the next time you connect." },
];

const platforms = [
  { icon: MonitorIcon, name: "Mac", detail: "macOS 14 or later", role: "The menu bar app" },
  { icon: SmartphoneIcon, name: "Android", detail: "Android 12 or later", role: "Phones & tablets" },
  { icon: TabletIcon, name: "iPhone & iPad", detail: "iOS / iPadOS 17 or later", role: "Phones & tablets" },
];

export default function Home() {
  return (
    <>
      <JsonLd data={app} />
      <section className="site-shell home-hero" aria-labelledby="hero-title">
        <div className="hero-copy">
          <Entrance><p className="eyebrow">A small app to bring your devices together</p></Entrance>
          <Entrance delay={0.06}>
            <h1 id="hero-title" className="hero-title">Your Mac,<br /><span className="editorial">a little closer.</span></h1>
          </Entrance>
          <Entrance delay={0.12}>
            <p className="hero-description">Your desktop, right there on your phone. Click, type, and pick up where you left off, from wherever you feel comfortable.</p>
          </Entrance>
          <Entrance delay={0.18} className="hero-actions">
            <Link href="#download" className="action-primary">Download for Mac <ArrowDownIcon className="size-4" aria-hidden /></Link>
            <Link href="/setup" className="text-link">How to connect <ArrowRightIcon className="size-4" aria-hidden /></Link>
          </Entrance>
          <Entrance delay={0.22}><p className="hero-note">For Mac + Android, iPhone, or iPad.<br /><span>Mac and Android downloads available. Mobile store releases coming soon.</span></p></Entrance>
        </div>
        <Entrance delay={0.08} className="hero-art">
          <figure>
            <Image src="/illustrations/hero.webp" alt="A phone in a hand showing the same desktop as the Mac on the desk" width={1200} height={900} loading="eager" fetchPriority="high" sizes="(min-width: 1024px) 620px, (min-width: 768px) 52vw, 100vw" className="hero-image" />
            <figcaption><span className="connection-line" aria-hidden /><span>Two devices. One familiar desktop.</span></figcaption>
          </figure>
        </Entrance>
      </section>

      <div className="site-shell">
        <ul className="principles" aria-label="The essentials">
          {["Connect over Wi-Fi or Tailscale", "No Tetherly account needed", "Apache 2.0 licensed"].map((text) => <li key={text}><CheckIcon className="size-4" aria-hidden />{text}</li>)}
        </ul>
      </div>

      <section id="features" className="site-shell home-section" aria-labelledby="features-title">
        <Reveal className="section-heading">
          <p className="eyebrow">The familiar things</p>
          <h2 id="features-title">A few things,<br /><span className="editorial">made easier.</span></h2>
          <p>Pause a video from the sofa. Write a quick reply. Bring a file over to your phone. Your Mac is still part of the moment.</p>
        </Reveal>
        <FeatureStories />
      </section>

      <section id="how-it-works" className="setup-section home-section" aria-labelledby="setup-title">
        <div className="site-shell setup-layout">
          <Reveal className="setup-art">
            <Image src="/illustrations/step-scan.webp" alt="A phone scanning the pairing QR code on a Mac" width={720} height={720} sizes="(min-width: 768px) 420px, 80vw" />
            <p>A quick introduction.<br /><span>A connection you control.</span></p>
          </Reveal>
          <div>
            <Reveal className="section-heading">
              <p className="eyebrow">Getting acquainted</p>
              <h2 id="setup-title">Pair once.<br /><span className="editorial">Feel right at home.</span></h2>
            </Reveal>
            <ol className="setup-steps">
              {steps.map((step, index) => (
                <Reveal as="li" key={step.title} delay={index * 0.04}>
                  <span className="step-number" aria-hidden>0{index + 1}</span>
                  <div><h3>{step.title}</h3><p>{step.body}</p></div>
                </Reveal>
              ))}
            </ol>
            <p className="connection-summary">At home, your Wi-Fi brings the devices together. Away from home, Tailscale gives them a private connection over the internet, so your Mac can stay on your desk.</p>
            <Link href="/setup" className="text-link">Set up Wi-Fi or Tailscale <ArrowRightIcon className="size-4" aria-hidden /></Link>
          </div>
        </div>
      </section>

      <section id="privacy" className="site-shell home-section privacy-layout" aria-labelledby="privacy-title">
        <Reveal className="section-heading">
          <p className="eyebrow">Between your devices</p>
          <h2 id="privacy-title">Your screen.<br /><span className="editorial">Your business.</span></h2>
          <p>Connect your Mac and phone directly. Choose when to share your screen, clipboard, and files.</p>
          <Link href="/privacy" className="text-link">Read our privacy policy <ArrowRightIcon className="size-4" aria-hidden /></Link>
        </Reveal>
        <Reveal className="privacy-details" delay={0.06}>
          <div><h3>You choose who connects.</h3><p>Approve your phone on your Mac once, then reconnect when you need it.</p></div>
          <div><h3>Your clipboard stays yours.</h3><p>Send or fetch text when you need it. Clipboard sharing happens only when you ask.</p></div>
          <div><h3>No Tetherly account.</h3><p>Open the apps, pair your devices, and get started.</p></div>
        </Reveal>
      </section>

      <section id="download" className="site-shell availability-section" aria-labelledby="download-title">
        <Reveal className="availability-layout">
          <div className="section-heading">
            <p className="eyebrow">Get Tetherly</p>
            <h2 id="download-title">A new way to<br /><span className="editorial">stay within reach.</span></h2>
            <p>Download Tetherly {releaseInfo.version} for Mac and Android. The Mac app supports Apple silicon and Intel Macs running macOS 14 or later. Android requires Android 12 or later. Mobile store releases are coming soon.</p>
            <div className="download-actions">
              <a href={site.downloads.mac} download data-download="mac" className="action-primary">Download for Mac <ArrowDownIcon className="size-4" aria-hidden /></a>
              <a href={site.downloads.android} data-download="android" className="action-primary">Download for Android <ArrowDownIcon className="size-4" aria-hidden /></a>
            </div>
            <div className="store-actions" aria-label="Upcoming store releases">
              <button type="button" className="store-button" disabled aria-label="App Store for iPhone and iPad, coming soon">
                <span className="store-badge-frame"><Image src="/store-badges/app-store.svg" width={120} height={40} alt="Download on the App Store" className="app-store-badge" unoptimized /></span>
                <span className="store-coming-soon">Coming soon</span>
              </button>
              <button type="button" className="store-button" disabled aria-label="Google Play for Android, coming soon">
                <span className="store-badge-frame"><Image src="/store-badges/google-play.png" width={646} height={250} alt="Get it on Google Play" className="google-play-badge" unoptimized /></span>
                <span className="store-coming-soon">Coming soon</span>
              </button>
            </div>
            <Link href="/setup" className="text-link">Installation and pairing <ArrowRightIcon className="size-4" aria-hidden /></Link>
            <p><a href="/downloads/SHA256SUMS.txt" className="text-link">Download checksums</a> · <Link href="/changelog" className="text-link">Changelog</Link></p>
          </div>
          <ul className="platform-list">
            {platforms.map((platform) => (
              <li key={platform.name}>
                <platform.icon className="size-6" strokeWidth={1.5} aria-hidden />
                <div><h3>{platform.name}</h3><p>{platform.detail}</p><span className="platform-role">{platform.role}</span></div>
                <span className="platform-status">{platform.name === "Mac" || platform.name === "Android" ? "Available" : "Coming soon"}</span>
              </li>
            ))}
          </ul>
        </Reveal>
      </section>
    </>
  );
}
