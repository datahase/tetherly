import Link from "next/link";
import { ArrowRightIcon } from "lucide-react";
import { PageIntro } from "@/components/page-intro";

export default function NotFound() {
  return (
    <div className="site-shell secondary-page not-found-page">
      <PageIntro eyebrow="Page not found" title="This page" accent="isn't here." aside={<div className="not-found-number" aria-hidden>404<span>A different route is just below.</span></div>}>
        <p>The link may have changed, or the address may have a typo. You can head home or pick up the connection guide.</p>
        <div className="not-found-actions"><Link href="/" className="action-primary">Back to the homepage <ArrowRightIcon className="size-4" aria-hidden /></Link><Link href="/setup" className="text-link">How to connect <ArrowRightIcon className="size-4" aria-hidden /></Link></div>
        <p className="not-found-help">Looking for help? <Link href="/support">Visit Support.</Link></p>
      </PageIntro>
    </div>
  );
}
