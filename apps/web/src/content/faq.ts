import { site } from "@/lib/site";

/** Support FAQ. Rendered on /support, published as FAQPage JSON-LD and included in llms-full.txt. */
export const faq: { q: string; a: string }[] = [
  {
    q: "How do I pair my phone or tablet with my Mac?",
    a: `Open the Tetherly menu bar app on your Mac and start pairing to show a QR code. In the Tetherly app on your phone or tablet, scan that code, or pair using the Mac's address.

Both screens then show the same short code. Check that they match, then approve on the Mac. If the codes do not match, cancel and try pairing again.`,
  },
  {
    q: "Which permissions does the Mac app need, and how do I grant them?",
    a: `Open System Settings, then Privacy & Security. Turn Tetherly on under **Screen Recording** (called Screen & System Audio Recording on newer macOS) so it can show your screen and play sound, and under **Accessibility** so it can move the pointer and type. Allow **Local Network** access when asked. macOS may ask you to quit and reopen Tetherly after you change these.`,
  },
  {
    q: "My Mac asks whether to accept incoming network connections. Should I allow it?",
    a: `Yes. Your phone connects directly to your Mac, so the macOS firewall needs to let Tetherly accept connections. If you clicked Deny by mistake, change it in System Settings, Network, Firewall, Options.`,
  },
  {
    q: "My phone cannot find my Mac.",
    a: `- Make sure both devices are on the same Wi-Fi network, and that the Mac is awake with Tetherly running.
- Guest networks and some office networks block devices from seeing each other. Try a home network or Tailscale.
- Turn off any VPN on either device, other than Tailscale, and try again.
- On iPhone and iPad, check that Local Network access is on for Tetherly in Settings, Privacy & Security.`,
  },
  {
    q: "Can I use Tetherly away from home with Tailscale?",
    a: `Yes. Install Tailscale on your Mac and on your phone or tablet, and sign in to the same Tailscale network on both. Follow our [Tailscale setup guide](/setup#tailscale) to get connected.`,
  },
  {
    q: "How do I unpair a device or delete my data?",
    a: `Unpair the device in the Tetherly app to remove its pairing record and key pin. Uninstalling an app removes its pairing records and preferences from that device. This does not delete Google's Android scanner diagnostics or messages you sent us. See the [Privacy Policy](/privacy#retention) for details.`,
  },
  {
    q: "Where do I report a bug or request a feature?",
    a: `Open an issue on [GitHub](${site.repo}/issues), or email us. Please include your Mac and phone models, their OS versions and the steps that cause the problem.`,
  },
];
