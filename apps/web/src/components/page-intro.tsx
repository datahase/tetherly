import Link from "next/link";
import { ArrowLeftIcon } from "lucide-react";
import { Entrance } from "@/components/reveal";

export function PageIntro({ eyebrow, title, accent, children, aside }: {
  eyebrow: string;
  title: string;
  accent: string;
  children: React.ReactNode;
  aside?: React.ReactNode;
}) {
  return (
    <header className={`page-intro${aside ? " page-intro-split" : ""}`}>
      <div>
        <Link href="/" className="page-back"><ArrowLeftIcon className="size-3.5" aria-hidden />Back to Tetherly</Link>
        <Entrance><p className="eyebrow">{eyebrow}</p><h1>{title}<br /><span className="editorial">{accent}</span></h1></Entrance>
        <div className="page-intro-copy">{children}</div>
      </div>
      {aside && <div className="page-intro-aside">{aside}</div>}
    </header>
  );
}
