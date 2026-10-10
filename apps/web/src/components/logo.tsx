import Image from "next/image";
import Link from "next/link";
import { site } from "@/lib/site";

export function Logo() {
  return (
    <Link href="/" className="flex items-center gap-2.5 rounded-md font-semibold tracking-tight">
      <span className="brand-mark" aria-hidden="true">
        <Image src="/logo.png" alt="" width={64} height={64} loading="eager" />
      </span>
      <span className="text-xl">{site.name}</span>
    </Link>
  );
}
