import { pageMetadata, breadcrumbs } from "@/lib/seo";
import { JsonLd } from "@/components/json-ld";
import Link from "next/link";
import { LegalPage, type LegalSection } from "@/components/legal-page";
import { site } from "@/lib/site";

export const metadata = pageMetadata({
  title: "Terms of Use",
  description: "The terms for using the Tetherly apps for Mac, Android, iPhone and iPad, and the tetherly.link website.",
  path: "/terms",
});

const mail = (a: string) => <a href={`mailto:${a}`}>{a}</a>;

const sections: LegalSection[] = [
  {
    id: "agreement",
    title: "Agreement",
    body: (
      <>
        <p>
          These Terms of Use (&quot;Terms&quot;) are an agreement between you and {site.company}, {site.country}{" "}
          (&quot;we&quot;, &quot;us&quot;). They apply to the Tetherly app for Mac, the Tetherly apps for Android and
          for iPhone and iPad (together &quot;the apps&quot;), and this website. By installing or using the apps, you
          agree to these Terms. If you do not agree, do not install or use them.
        </p>
        <p>
          Our <Link href="/privacy">Privacy Policy</Link> explains how the apps handle data and forms part of these
          Terms.
        </p>
      </>
    ),
  },
  {
    id: "license",
    title: "License",
    body: (
      <>
        <p>
          <strong>App binaries.</strong> We grant you a personal, worldwide, non-exclusive, non-transferable, revocable
          license to install and use the compiled apps we distribute, on devices you own or control, subject to these
          Terms. Apps obtained from the Apple App Store are also subject to the Usage Rules in Apple&apos;s Media
          Services Terms and Conditions, and apps obtained from Google Play to Google Play&apos;s terms.
        </p>
        <p>
          <strong>Source code.</strong> The Tetherly source code is published under the{" "}
          <a href="https://www.apache.org/licenses/LICENSE-2.0">Apache License, Version 2.0</a> at{" "}
          <a href={site.repo}>{site.repo.replace("https://", "")}</a>. Your use of the source code is governed by that
          license, and nothing in these Terms limits the rights it grants you.
        </p>
        <p>
          <strong>Name and logo.</strong> The Tetherly name and logo are not licensed under Apache 2.0. Do not use them
          in a way that suggests your build or product comes from or is endorsed by us.
        </p>
      </>
    ),
  },
  {
    id: "acceptable-use",
    title: "Acceptable use",
    body: (
      <>
        <p>Tetherly gives one device full control of another. You agree to:</p>
        <ul>
          <li>
            Only pair with and control computers and devices that you own, or that you are explicitly authorized to
            access by their owner.
          </li>
          <li>
            Not use the apps to access, monitor or record anyone without their knowledge and consent, or in any way
            that breaks the law, including privacy, surveillance and computer misuse laws.
          </li>
          <li>Not use the apps to transfer content you have no right to transfer, or to distribute malware.</li>
          <li>
            Not attempt to interfere with or bypass the apps&apos; pairing, approval or encryption, except for good
            faith security research that you report to us responsibly.
          </li>
        </ul>
      </>
    ),
  },
  {
    id: "your-responsibility",
    title: "Your responsibilities",
    body: (
      <ul>
        <li>
          You are responsible for the security of your devices and the networks you use, including your Wi-Fi and any
          Tailscale network, and for who can use your paired phone or tablet.
        </li>
        <li>
          The Mac app needs permissions such as Screen Recording and Accessibility, which give it broad access to your
          Mac. You choose whether to grant them, and you can revoke them in System Settings at any time.
        </li>
        <li>
          Anyone holding an unlocked, paired device can see and control your Mac while it is reachable. Unpair devices
          you no longer use or have lost.
        </li>
        <li>Keep backups of important data. Actions you take through the apps are real actions on your Mac.</li>
      </ul>
    ),
  },
  {
    id: "third-party",
    title: "Third-party services",
    body: (
      <p>
        The apps may rely on services provided by others, including Apple (the App Store and macOS and iOS), Google
        (Google Play and Google Play services) and Tailscale. Your use of those services is governed by their own terms
        and privacy policies, and we are not responsible for them.
      </p>
    ),
  },
  {
    id: "no-warranty",
    title: "No warranty",
    body: (
      <p>
        To the maximum extent permitted by law, the apps and website are provided <strong>&quot;as is&quot;</strong> and{" "}
        <strong>&quot;as available&quot;</strong>, without warranties of any kind, express or implied, including
        warranties of merchantability, fitness for a particular purpose, non-infringement, and that the apps will be
        uninterrupted, error-free or secure. Some jurisdictions do not allow certain warranty exclusions, so some of
        these may not apply to you.
      </p>
    ),
  },
  {
    id: "liability",
    title: "Limitation of liability",
    body: (
      <>
        <p>
          To the maximum extent permitted by law, {site.company} and its directors, employees and contributors will not
          be liable for any indirect, incidental, special, consequential or punitive damages, or for any loss of data,
          profits, revenue or business, arising from your use of or inability to use the apps, even if advised of the
          possibility of such damages.
        </p>
        <p>
          Our total liability for any claim relating to the apps or these Terms is limited to the greater of the amount
          you paid us for the apps in the twelve months before the claim, or INR 1,000. Nothing in these Terms limits
          liability that cannot be limited by law.
        </p>
      </>
    ),
  },
  {
    id: "termination",
    title: "Termination",
    body: (
      <p>
        You may stop using the apps at any time by uninstalling them. Your license under these Terms ends
        automatically if you breach them, in which case you must stop using and uninstall the apps. Sections on
        warranty, liability, governing law and anything else that by its nature should survive will survive
        termination. Termination does not affect rights you have under the Apache 2.0 license for the source code.
      </p>
    ),
  },
  {
    id: "law",
    title: "Governing law and disputes",
    body: (
      <p>
        These Terms are governed by the laws of India, without regard to conflict of law rules. The courts of competent
        jurisdiction in India will have jurisdiction over any dispute arising from these Terms or the apps. This does
        not take away any mandatory consumer protection rights you have under the laws of the country where you live.
      </p>
    ),
  },
  {
    id: "changes",
    title: "Changes to these Terms",
    body: (
      <p>
        We may update these Terms from time to time. We will post the new version on this page and update the date at
        the top. If you keep using the apps after a change takes effect, you accept the updated Terms.
      </p>
    ),
  },
  {
    id: "general",
    title: "General",
    body: (
      <p>
        If any part of these Terms is found unenforceable, the rest remains in effect. Our failure to enforce a term is
        not a waiver. You may not assign these Terms without our consent; we may assign them in connection with a
        merger, acquisition or sale of assets. These Terms are the entire agreement between you and us about the apps.
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
        Support and legal questions: {mail(site.email.support)}
        <br />
        Privacy: {mail(site.email.privacy)} · Security: {mail(site.email.security)}
      </p>
    ),
  },
];

export default function TermsPage() {
  return (
    <>
      <JsonLd data={breadcrumbs([{ name: "Terms of Use", path: "/terms" }])} />
      <LegalPage
        title="Terms of Use"
        intro={
          <p>
            Please read these Terms before using Tetherly. They set out what you may do with the apps, what you are
            responsible for, and the limits of our responsibility.
          </p>
        }
        sections={sections}
      />
    </>
  );
}
