import { pageMetadata, breadcrumbs } from "@/lib/seo";
import { JsonLd } from "@/components/json-ld";
import { site } from "@/lib/site";
import Link from "next/link";
import { ArrowDownIcon, ArrowRightIcon, CheckIcon, Globe2Icon, MonitorIcon, SmartphoneIcon, WifiIcon } from "lucide-react";
import { Reveal } from "@/components/reveal";
import { PageIntro } from "@/components/page-intro";

export const metadata = pageMetadata({
  title: "How to connect",
  description: "Set up Tetherly on Wi-Fi, or use Tailscale to reach your Mac from your phone away from home. Permissions, QR pairing, code comparison and reconnecting, step by step.",
  path: "/setup",
});

const localSteps = [
  { title: "Join the same network.", body: "Connect your Mac and phone or tablet to the same home Wi-Fi. A Mac connected by Ethernet works too, as long as both devices are on the same local network." },
  { title: "Show the pairing code.", body: "Open Tetherly from your Mac's menu bar. Turn on Allow connections, then choose Pair New Device to show the QR code." },
  { title: "Make the introduction.", body: "Open Tetherly on your phone or tablet and scan the QR code. Compare the short codes on both screens. Confirm that they match on your phone, then approve the device on your Mac. Cancel if they differ." },
  { title: "You're connected.", body: "Your Mac's desktop is ready to view and control. Next time, choose your Mac from the paired devices and tap Connect. Keep the Mac awake with Tetherly running." },
];

const remoteSteps = [
  { title: "Install Tailscale on both devices.", body: <>Get Tailscale for your Mac and phone or tablet from the <a href="https://tailscale.com/download">official downloads page</a>. Follow its setup prompts, including the VPN permission on your phone.</> },
  { title: "Sign in to the same private network.", body: "Use the same Tailscale account on both devices. Check that both appear in Tailscale and are connected. This private network is called a tailnet. Tetherly itself does not need an account." },
  { title: "Pair before you head out.", body: <>With Tailscale connected on both devices, follow the <Link href="#local">Wi-Fi pairing steps above</Link>. If you already paired, connect to your Mac once while Tailscale is on so Tetherly can remember its Tailscale address.</> },
  { title: "Try it on another connection.", body: "Leave your Mac awake, online, and allowing connections. Switch your phone to mobile data or another Wi-Fi network, keep Tailscale connected, and tap Connect for your paired Mac in Tetherly." },
];

const howTo = {
  "@context": "https://schema.org",
  "@type": "HowTo",
  name: "How to connect your phone to your Mac with Tetherly",
  description: "Pair an Android phone, iPhone or iPad with your Mac on the same Wi-Fi, then view and control the Mac's desktop.",
  tool: [{ "@type": "HowToTool", name: "Tetherly for Mac (macOS 14 or later)" }, { "@type": "HowToTool", name: "Tetherly for Android, iPhone or iPad" }],
  step: localSteps.map((step, i) => ({ "@type": "HowToStep", position: i + 1, name: step.title, text: step.body, url: `${site.url}/setup#local` })),
};

function GuideSteps({ steps }: { steps: { title: string; body: React.ReactNode }[] }) {
  return <ol className="guide-steps">{steps.map((step, index) => <li key={step.title}><span className="step-number" aria-hidden>0{index + 1}</span><div><h3>{step.title}</h3><p>{step.body}</p></div></li>)}</ol>;
}

export default function SetupPage() {
  return (
    <div className="site-shell secondary-page guide-page">
      <JsonLd data={howTo} />
      <JsonLd data={breadcrumbs([{ name: "How to connect", path: "/setup" }])} />
      <PageIntro eyebrow="How to connect" title="Two ways to connect." accent="One familiar Mac." aside={
        <div className="connection-map" role="img" aria-label="Connect your phone to your Mac on local Wi-Fi, or across networks with Tailscale.">
          <div className="map-device"><MonitorIcon strokeWidth={1.2} aria-hidden /><span>Your Mac</span></div>
          <div className="map-routes"><div><WifiIcon className="size-4" aria-hidden /><span>Local Wi-Fi</span></div><div><Globe2Icon className="size-4" aria-hidden /><span>Tailscale</span></div></div>
          <div className="map-device"><SmartphoneIcon strokeWidth={1.2} aria-hidden /><span>Your phone</span></div>
          <p>Start nearby. Go further when you need to.</p>
        </div>
      }>
        <p>Start on your Wi-Fi. Add Tailscale when you want to reach your Mac from somewhere else.</p>
        <p className="guide-preview">Mac and Android downloads are available, and Android is on Google Play. iPhone and iPad releases are coming soon.</p>
      </PageIntro>
      <nav className="guide-paths" aria-label="Choose your connection">
        <Link href="#local"><WifiIcon className="size-6" strokeWidth={1.5} aria-hidden /><div><h2>Nearby, on Wi-Fi</h2><p>Your own network. No extra service.</p></div><ArrowDownIcon className="size-4" aria-hidden /></Link>
        <Link href="#tailscale"><Globe2Icon className="size-6" strokeWidth={1.5} aria-hidden /><div><h2>Away, with Tailscale</h2><p>A private route back to your Mac.</p></div><ArrowDownIcon className="size-4" aria-hidden /></Link>
      </nav>
      <Reveal className="guide-preparation">
        <p className="eyebrow">Before either route</p>
        <h2>Give your Mac a moment to get ready.</h2>
        <ul className="preparation-checklist">
          <li><CheckIcon className="size-4" aria-hidden /><div><h3>Install on both devices.</h3><p><a href={site.downloads.mac} download data-download="mac">Download Tetherly for Mac</a>, open it, and drag Tetherly to Applications. Then open Tetherly from the menu bar. Install Tetherly for Android from <a href={site.stores.googlePlay} data-download="google-play">Google Play</a>, or <a href={site.downloads.android} data-download="android">download the APK</a> and follow the installation prompts. iPhone and iPad releases are coming soon.</p></div></li>
          <li><CheckIcon className="size-4" aria-hidden /><div><h3>Give your Mac permission.</h3><p>Follow the Screen Recording and Accessibility prompts. Allow Local Network access and incoming connections through the macOS firewall. Reopen Tetherly if macOS asks you to.</p></div></li>
          <li><CheckIcon className="size-4" aria-hidden /><div><h3>Let your phone find your Mac.</h3><p>On iPhone or iPad, allow Local Network access. Scanning the QR code also needs camera access.</p></div></li>
        </ul>
        <Link href="/support" className="text-link">Help with permissions <ArrowRightIcon className="size-4" aria-hidden /></Link>
      </Reveal>
      <section id="local" className="guide-section" aria-labelledby="local-title">
        <div className="guide-section-heading"><WifiIcon className="size-6" aria-hidden /><p className="eyebrow">Stay nearby</p><h2 id="local-title">On your Wi-Fi.</h2><p>The simplest place to start. No Tailscale account or internet connection is needed for the local session.</p></div>
        <div><GuideSteps steps={localSteps} /><aside className="guide-note"><h3>No QR scanner?</h3><p>Choose the Mac under Nearby and tap Pair, or enter the local address shown in the Mac app. You still compare the codes and approve on the Mac.</p></aside></div>
      </section>
      <section id="tailscale" className="guide-section" aria-labelledby="tailscale-title">
        <div className="guide-section-heading"><Globe2Icon className="size-6" aria-hidden /><p className="eyebrow">Reach a little further</p><h2 id="tailscale-title">Away, with Tailscale.</h2><p>Tailscale lets your devices reach each other across different networks. Your Mac stays at home while your phone connects over the internet.</p><p>Both devices need Tailscale. No router port forwarding or exit node is needed.</p></div>
        <div>
          <GuideSteps steps={remoteSteps} />
          <aside className="guide-note"><h3>If your Mac isn&apos;t found</h3><p>Copy the Mac&apos;s Tailscale IPv4 address (starting with <code>100.</code>) from Tailscale. Enter it in Tetherly&apos;s address field. For a new pairing, first enable Pair New Device on the Mac, then compare and approve the codes as usual.</p></aside>

        </div>
      </section>
      <section className="guide-help" aria-labelledby="guide-help-title">
        <h2 id="guide-help-title">A few things to check.</h2>
        <div className="guide-help-grid">
          <div><h3>Mac not showing up?</h3><p>Check that it is awake and Allow connections is on. Guest Wi-Fi can block devices from reaching each other. Try a home network, or the Tailscale route.</p></div>
          <div><h3>Tailscale connected, but no desktop?</h3><p>Check that both devices are online in the same tailnet. On a managed tailnet, its access rules must allow the phone to reach the Mac on TCP port 47800. Tetherly pairing is still required.</p></div>
          <div><h3>A slower remote session?</h3><p>Try a stronger internet connection on both devices. Relayed Tailscale connections can have more delay. Keep your Mac awake; Tetherly does not wake a sleeping Mac remotely.</p></div>
        </div>
        <div className="guide-help-links"><Link href="/support" className="text-link">Ask for a hand <ArrowRightIcon className="size-4" aria-hidden /></Link><a href="https://tailscale.com/docs/how-to/quickstart" className="text-link">Tailscale&apos;s official getting started guide <ArrowRightIcon className="size-4" aria-hidden /></a></div>
      </section>
    </div>
  );
}
