import { pageMetadata, breadcrumbs } from "@/lib/seo";
import { JsonLd } from "@/components/json-ld";
import Link from "next/link";
import { LegalPage, type LegalSection } from "@/components/legal-page";
import { site } from "@/lib/site";

export const metadata = pageMetadata({
  title: "Privacy Policy",
  description: "How Tetherly handles your screen, input, clipboard and files between your own devices, what stays on each device, and the Android QR-scanner diagnostics Google may collect.",
  path: "/privacy",
});

const mail = (a: string) => <a href={`mailto:${a}`}>{a}</a>;

const sections: LegalSection[] = [
  {
    id: "who-we-are",
    title: "Who we are",
    body: (
      <>
        <p>
          Tetherly is made by {site.company}, a company registered in {site.country} (&quot;we&quot;, &quot;us&quot;).
          This policy covers the Tetherly app for Mac, the Tetherly apps for Android and for iPhone and iPad (together
          &quot;the apps&quot;), and this website, {site.url.replace("https://", "")}.
        </p>
        <p>
          For anything about privacy, write to {mail(site.email.privacy)}.
        </p>
      </>
    ),
  },
  {
    id: "summary",
    title: "The short version",
    body: (
      <ul>
        <li>Tetherly does not operate a server that receives your screen, input, clipboard or transferred files.</li>
        <li>No Tetherly account or advertising service is required.</li>
        <li>The apps contain no analytics. This website uses Google Analytics to measure visits, with your consent where the law requires it, as described below.</li>
        <li>The Android QR scanner uses Google Play services, which collects diagnostic and usage data as described below.</li>
        <li>
          We run no servers in the remote-session content path. Your Mac and your phone or tablet talk directly to each other over your
          local network or your own Tailscale network.
        </li>
        <li>You control local pairing records and files. Deleting them does not delete Google&apos;s scanner diagnostics.</li>
      </ul>
    ),
  },
  {
    id: "how-it-works",
    title: "How Tetherly handles your data",
    body: (
      <>
        <p>
          The Mac app captures your Mac&apos;s screen, and, only if you turn sound on, its system audio. It does this
          solely to stream them, encrypted, to the phone or tablet you have paired with it. The stream is not recorded,
          saved or sent anywhere else.
        </p>
        <p>
          Your phone or tablet sends pointer, touch, scroll and keyboard input to the Mac so you can control it. This
          input goes only to your paired Mac and is not logged.
        </p>
        <p>
          <strong>Clipboard.</strong> Clipboard text moves between devices only when you tap send or fetch. The apps
          do not read or sync your clipboard in the background. Only text is supported.
        </p>
        <p>
          <strong>Files.</strong> You can send files in either direction. Each transfer must be accepted on the
          receiving device, which also chooses where the file is saved. Received files are stored only where you choose.
        </p>
        <p>
          All of this travels device to device over mutual TLS 1.3, using keys created at pairing and pinned on both
          devices. None of it passes through us.
        </p>
      </>
    ),
  },
  {
    id: "on-device",
    title: "What is stored on your devices",
    body: (
      <>
        <p>The apps keep the following on your devices only. We never receive any of it.</p>
        <ul>
          <li>
            <strong>Pairing records:</strong> the names of the devices you paired and their public key pins.
          </li>
          <li>
            <strong>The device&apos;s own private key</strong>, kept in the Mac Keychain, the Android Keystore or the
            iOS Keychain.
          </li>
          <li>
            <strong>App preferences</strong>, such as input mode or whether sound is on.
          </li>
          <li>
            <strong>Files you choose to transfer</strong>, saved in the location you pick.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: "not-collected",
    title: "Remote content and scanner diagnostics",
    body: (
      <>
        <p>
          Tetherly does not send your screen, system audio, keystrokes, clipboard or selected files to DataHase.
          That content travels between the devices you approve. Scanner diagnostics are separate from this content.
        </p>
        <p>
          The Android app uses Google&apos;s code scanner. Google documents collection of device and app information,
          device or installation identifiers, performance metrics, scanner configuration, event information and error
          codes for diagnostics and usage analytics. This data is encrypted in transit using HTTPS. See{" "}
          <a href="https://developers.google.com/ml-kit/android-data-disclosure">Google&apos;s ML Kit data disclosure</a>.
        </p>
        <p>
          Google says scanner images are processed on your device and it does not store the images or scan results.
          This does not mean the scanner sends no diagnostic data. See the{" "}
          <a href="https://developers.google.com/ml-kit/vision/barcode-scanning/code-scanner">code scanner documentation</a>.
        </p>
      </>
    ),
  },
  {
    id: "permissions",
    title: "Permissions and why we ask",
    body: (
      <>
        <h3>Mac</h3>
        <ul>
          <li>
            <strong>Screen Recording</strong> (also covers system audio): to stream your screen, and sound if you turn
            it on, to your paired device.
          </li>
          <li>
            <strong>Accessibility</strong>: to move the pointer, click, scroll and type on your Mac on your behalf.
          </li>
          <li>
            <strong>Local Network</strong>: to be found by, and talk to, your paired phone or tablet.
          </li>
        </ul>
        <h3>iPhone and iPad</h3>
        <ul>
          <li>
            <strong>Local Network</strong>: to find and connect to your Mac.
          </li>
          <li>
            <strong>Camera</strong>: only to scan the pairing QR code shown by your Mac. Camera images are processed on
            the device, and are not stored or sent anywhere.
          </li>
        </ul>
        <h3>Android</h3>
        <ul>
          <li>
            <strong>Network and multicast access</strong>: to find and connect to your Mac.
          </li>
          <li>
            The Android app does not hold the camera permission. QR scanning uses the Google Play services code
            scanner, which runs on your device and returns only the scanned code to the app.
          </li>
        </ul>
        <p>You can withdraw any permission in your device settings at any time. Features that rely on it will stop working.</p>
      </>
    ),
  },
  {
    id: "third-parties",
    title: "Third-party services",
    body: (
      <ul>
        <li>
          <strong>Tailscale.</strong> If you choose to connect over Tailscale, that network is a third-party service
          you set up yourself, governed by Tailscale&apos;s own terms and privacy policy. Tetherly traffic over it is
          still end-to-end encrypted between your devices.
        </li>
        <li>
          <strong>App stores.</strong> When you download an app from the Apple App Store or Google Play, Apple or Google
          may collect data under their own policies. We do not receive personal data from them.
        </li>
        <li>
          <strong>Google Analytics</strong> (this website only). Measures website visits as described under{" "}
          <a href="#website">This website</a>.
        </li>
        <li>
          <strong>Google Play services code scanner</strong> (Android only). Image processing runs on-device;
          diagnostic and usage data is handled by Google as described above and under{" "}
          <a href="https://policies.google.com/privacy">Google&apos;s Privacy Policy</a>.
        </li>
      </ul>
    ),
  },
  {
    id: "website",
    title: "This website",
    body: (
      <>
      <p>
        This website uses Google Analytics to understand how visitors find and use it, for example which pages are
        read and which links are followed. Google Analytics sets cookies and collects information such as pages
        visited, referring sites, approximate location derived from your IP address, and device and browser type. We
        use it only in aggregate, not to identify you or for advertising. Google processes this data under{" "}
        <a href="https://policies.google.com/privacy">Google&apos;s Privacy Policy</a>; see also{" "}
        <a href="https://policies.google.com/technologies/partner-sites">how Google uses data from sites that use its
        services</a>.
      </p>
      <p>
        <strong>Your choice.</strong> If you visit from the European Union, the rest of the European Economic Area, the
        United Kingdom or Switzerland, or we can&apos;t tell where you are, Google Analytics stays off and sets no
        cookies unless you accept it in the cookie banner. Elsewhere it is on by default. Wherever you are, you can turn
        it on or off at any time with <strong>Cookie settings</strong> at the bottom of every page; turning it off
        removes its cookies. You can also block cookies in your browser or use{" "}
        <a href="https://tools.google.com/dlpage/gaoptout">Google&apos;s opt-out browser add-on</a>.
      </p>
      <p>
        To apply the right default, our hosting provider looks up your country from your IP address when you load a
        page. We keep only a short-lived <code>tl_region</code> cookie that says whether consent is needed, not your
        country or IP address. Your choice is saved in your browser&apos;s local storage. Both are needed for the
        consent choice to work and are never sent to Google.
      </p>
      <p>
        Like any web host, our hosting provider may keep standard server logs, such as IP address, user agent and the
        page requested, for security and operations. These logs are kept only as long as needed for those purposes and
        are not used to profile you. The Tetherly apps do not use Google Analytics or any other analytics.
      </p>
      </>
    ),
  },
  {
    id: "retention",
    title: "Retention and deletion",
    body: (
      <>
        <p>
          Tetherly&apos;s local pairing records, preferences and received files stay under your control:
        </p>
        <ul>
          <li>
            <strong>Unpair</strong> a device in the app to remove its pairing record and key pin.
          </li>
          <li>
            <strong>Uninstall</strong> an app to remove its pairing records and preferences from that device. On
            Android, its keys are removed too. Apple systems may keep Keychain items after an app is deleted; on a Mac
            you can remove them with the Keychain Access app, and they never leave your device.
          </li>
          <li>Files you received stay where you saved them until you delete them.</li>
        </ul>
        <p>
          Unpairing or uninstalling Tetherly does not request deletion of diagnostic data already collected by Google.
          Google&apos;s privacy policy explains its retention practices and available privacy controls. Tetherly does
          not set a retention period for Google&apos;s SDK data. Messages you send to DataHase and website logs are
          handled separately as described in this policy.
        </p>
      </>
    ),
  },
  {
    id: "security",
    title: "Security",
    body: (
      <p>
        Devices pair by scanning a QR code (or entering a code) and confirming a short code shown on both screens.
        After that, every connection uses mutual TLS 1.3 with pinned keys, and private keys never leave the device&apos;s
        secure key store. Please report vulnerabilities to{" "}
        {mail(site.email.security)}. You are responsible for the security of your own network and devices.
      </p>
    ),
  },
  {
    id: "children",
    title: "Children",
    body: (
      <p>
        Tetherly is not directed to children under 13. The Android scanner&apos;s data practices are described above.
      </p>
    ),
  },
  {
    id: "your-rights",
    title: "Your rights (GDPR, India DPDP Act and others)",
    body: (
      <>
        <p>
          Privacy laws such as the EU and UK General Data Protection Regulation and India&apos;s Digital Personal Data
          Protection Act, 2023 give you rights to access, correct, erase and port your personal data, to withdraw
          consent, to object to processing and to complain to a regulator or, in India, to seek grievance redressal.
        </p>
        <p>
          Because the apps do not send personal data to us, we normally hold nothing that these rights could apply to.
          You exercise control directly on your devices, as described above. If you believe we hold personal data about
          you, for example because you emailed us, write to {mail(site.email.privacy)} and we will respond within the
          time the law requires. Email you send us is used only to reply and is deleted when no longer needed.
        </p>
        <p>
          Third-party services may process data in other countries under their own policies. You may also complain
          to the data protection authority where you live.
        </p>
      </>
    ),
  },
  {
    id: "changes",
    title: "Changes to this policy",
    body: (
      <p>
        If we change this policy, we will post the new version on this page and update the date at the top. If a
        change would affect how the apps handle your data, we will also point it out in the app release notes.
      </p>
    ),
  },
  {
    id: "contact",
    title: "Contact",
    body: (
      <p>
        {site.company}, {site.country}
        <br />
        Privacy and grievance contact: {mail(site.email.privacy)}
        <br />
        Support: {mail(site.email.support)} · <Link href="/support">Support page</Link>
      </p>
    ),
  },
];

export default function PrivacyPage() {
  return (
    <>
      <JsonLd data={breadcrumbs([{ name: "Privacy Policy", path: "/privacy" }])} />
      <LegalPage
        title="Privacy Policy"
        intro={
          <p>
            Tetherly is built so that your screen, your input and your files go from one of your devices to another and
            nowhere else. This policy explains exactly what that means.
          </p>
        }
        sections={sections}
      />
    </>
  );
}
