export type Post = {
  slug: string;
  title: string;
  /** Second line of the page and share-card headline. */
  accent: string;
  description: string;
  date: string;
  keywords: string[];
  body: string;
};

/** Newest first. Bodies use the subset in lib/markdown.ts. */
export const posts: Post[] = [
  {
    slug: "why-tetherly-is-different",
    title: "Why Tetherly is different",
    accent: "from other Mac remote desktop apps.",
    description:
      "Most remote desktop tools were built for one computer controlling another. Tetherly is built for one thing: using your own Mac from your phone or tablet, directly and privately.",
    date: "2026-10-10",
    keywords: ["Mac remote desktop", "remote desktop for Mac", "VNC alternative", "Screen Sharing alternative", "control Mac from phone"],
    body: `There are plenty of ways to see a Mac's screen from somewhere else. macOS has Screen Sharing built in, VNC has been around for decades, and many commercial apps offer remote access and remote support. So why build another one?

Because almost all of them start from the same idea: **one computer controlling another computer**. Tetherly starts from a different one: **your phone or tablet, reaching your own Mac**. That changes nearly every design decision.

## The short answer

- **Made for the device in your hand.** Touch and trackpad modes, your phone's keyboard and dictation, Mac shortcuts and Mission Control, all designed for a small touch screen.
- **Direct, not relayed.** Your phone connects straight to your Mac over your Wi-Fi or your own Tailscale network. There is no Tetherly server in the path.
- **No Tetherly account.** Install the apps, pair once, and connect.
- **Paired, not just password-protected.** You scan a QR code, compare a short code on both screens, and approve on the Mac. After that, both sides check each other's keys on every connection.
- **Open source.** The Mac, Android and iOS apps and the protocol between them are public under the Apache 2.0 license.

## Built for a phone, not adapted to one

Desktop-to-desktop tools assume a mouse, a full keyboard and a big screen on the viewing side. On a phone, those assumptions make for a cramped, fiddly experience: a tiny pointer, missing keys, and gestures that fight with the desktop.

Tetherly is designed the other way around. You can tap the desktop directly, or switch to trackpad mode and use your phone like a laptop trackpad. Scroll and zoom work the way they do on a phone. The keyboard bar adds the keys a phone lacks, such as Command, Option, Control, fn and F1 to F12, and your phone's own dictation keyboard types straight into your Mac. A Mission Control button and multi-finger swipes bring the overview you're used to on a trackpad.

## Your Mac's real desktop

Tetherly shows and controls the desktop you already have: the same apps, windows and logged-in session you left on your desk. There is no virtual machine and no separate remote session to set up. If a video is playing, your Mac's audio can come along to your phone as well.

## A direct connection you own

Many remote access services route your connection through the vendor's servers so they can find your computer from anywhere. That's convenient, but it means an account, and a third party in the middle of every session.

Tetherly connects device to device. At home, both devices are on the same Wi-Fi and find each other on the local network. Away from home, you can use [Tailscale](/blog/reach-your-mac-with-tailscale), which gives your own devices a private network across the internet. No port forwarding is needed, and Tetherly never sees your screen.

## Security you can check

Pairing uses a QR code shown by your Mac and a short code you compare on both screens. That comparison is what stops someone else on the network from slipping in. After pairing, every connection uses mutual TLS 1.3 with pinned keys, and the keys stay in the Mac Keychain, the iOS Keychain or the Android Keystore.

Because the apps and the [wire protocol](https://github.com/datahase/tetherly/blob/main/protocol/SPEC.md) are open source, you don't have to take our word for any of this.

## Sharing only when you ask

Clipboard text moves only when you tap send or fetch. Files can go in either direction, and the receiving device chooses whether to accept each one and where to save it. Nothing is shared in the background.

## When another tool is a better fit

Tetherly is focused, and it's not for every situation. Choose something else if you need to:

- Help someone else with their computer, as remote support tools do.
- Control a Windows or Linux computer. Tetherly's host app is for macOS only.
- Reach a Mac over the internet without installing Tailscale or a similar private network.
- Wake a sleeping Mac remotely. Tetherly needs the Mac awake with the app running.

If what you want is your own Mac, within reach of your phone or tablet, that is exactly what Tetherly is for. [See how to connect](/setup), or [download it](/#download).`,
  },
  {
    slug: "control-your-mac-from-android",
    title: "How to control your Mac",
    accent: "from an Android phone.",
    description:
      "A step-by-step guide to viewing and controlling your Mac's desktop from an Android phone or tablet with Tetherly: install, pair with a QR code, and connect.",
    date: "2026-10-10",
    keywords: ["control Mac from Android", "Android remote desktop for Mac", "Mac remote control app for Android", "use Android as Mac trackpad"],
    body: `Apple doesn't make an Android app for controlling a Mac, and most remote desktop apps treat the phone as an afterthought. Tetherly gives you your Mac's real desktop on your Android phone or tablet, with touch controls designed for it.

## What you need

- A Mac running macOS 14 or later, with Apple silicon or an Intel processor.
- An Android phone or tablet running Android 12 or later.
- Both devices on the same Wi-Fi network. To connect from elsewhere, add [Tailscale](/blog/reach-your-mac-with-tailscale).

## Step by step

1. **Install Tetherly on your Mac.** [Download the Mac app](/#download), open the DMG and drag Tetherly to Applications. Open it and find its icon in the menu bar.
2. **Give your Mac permission.** Allow Screen Recording so Tetherly can show your screen, and Accessibility so it can move the pointer and type. Allow Local Network access and incoming connections through the macOS firewall when asked.
3. **Install Tetherly on Android.** [Download the Android app](/#download) and allow your browser to install it when Android asks.
4. **Show the pairing code.** In the Mac menu bar app, turn on Allow connections and choose Pair New Device. A QR code appears.
5. **Scan and compare.** Open Tetherly on your phone and scan the QR code. Both screens now show the same short code. Confirm on your phone that they match, then approve on your Mac.
6. **Connect.** Your Mac's desktop appears on your phone. Next time, just pick your Mac from your paired devices and tap Connect.

## Getting around

- **Touch mode:** tap where you want to click, and drag to move things.
- **Trackpad mode:** use the screen like a laptop trackpad, with the pointer staying where you leave it.
- **Keyboard:** use your phone's keyboard or dictation. The key bar adds Command, Option, Control, fn and F1 to F12.
- **Mission Control:** tap the Mission Control button to see all your windows and desktops.
- **Clipboard and files:** send or fetch clipboard text, and send files either way. The receiving device accepts each file.

## If your phone can't find your Mac

Check that both devices are on the same network and the Mac is awake with Tetherly running. Guest Wi-Fi and some office networks stop devices from seeing each other. If the QR scanner isn't available, you can choose the Mac under Nearby or enter the address shown in the Mac app. The [support page](/support) covers more.`,
  },
  {
    slug: "reach-your-mac-with-tailscale",
    title: "Reach your Mac from anywhere",
    accent: "with Tailscale.",
    description:
      "Use Tetherly with Tailscale to control your Mac from your phone while you're away, without port forwarding or exposing your Mac to the internet.",
    date: "2026-10-10",
    keywords: ["Tailscale remote desktop", "access Mac remotely from phone", "remote desktop without port forwarding", "Mac remote access Tailscale"],
    body: `At home, Tetherly connects your phone and Mac over your Wi-Fi. When you leave, the Wi-Fi no longer connects them. Tailscale fixes that by putting your own devices on a private network that works across the internet, so your phone can reach your Mac from a café, the office or mobile data.

## Why Tailscale

- **No port forwarding.** You don't open ports on your router or expose your Mac to the internet.
- **Your own private network.** Only devices signed in to your Tailscale network, called a tailnet, can reach each other.
- **Tetherly's protection still applies.** Your phone must still be paired with your Mac, and every connection is still checked with mutual TLS.

Tailscale is a separate service with its own account and terms. Tetherly itself still needs no account.

## Set it up

1. **Install Tailscale** on your Mac and on your phone or tablet from [Tailscale's downloads page](https://tailscale.com/download), and follow its setup prompts.
2. **Sign in to the same tailnet** on both devices. Check that both show as connected in Tailscale.
3. **Pair before you leave.** With Tailscale on, pair your phone with your Mac as usual. If you paired earlier, connect once while Tailscale is on so Tetherly can remember the Mac's Tailscale address.
4. **Try it away from home.** Leave the Mac awake with Tetherly allowing connections. Switch your phone to mobile data, keep Tailscale connected, and tap Connect.

## Tips

- **Mac not found?** Copy the Mac's Tailscale address, which starts with 100., and enter it in Tetherly's address field.
- **Managed tailnet?** Its access rules must let your phone reach the Mac on TCP port 47800.
- **Feels slow?** Relayed Tailscale connections add delay. A stronger connection on both ends helps.
- **Keep the Mac awake.** Tetherly can't wake a sleeping Mac remotely.

The full walkthrough is in the [connection guide](/setup#tailscale).`,
  },
];

/** One-line headline for titles, feeds and structured data. */
export const headline = (p: Post) => `${p.title} ${p.accent.replace(/\.$/, "")}`;

export const getPost = (slug: string) => posts.find((p) => p.slug === slug);
