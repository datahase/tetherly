import { NextResponse, type NextRequest } from "next/server";
import { REGION_COOKIE, needsConsent } from "@/lib/consent";

/** Tells the static pages whether analytics needs opt-in consent here. Only the yes/no is stored, not the country or IP. */
export function proxy(request: NextRequest) {
  const response = NextResponse.next();
  const region = needsConsent(request.headers.get("x-vercel-ip-country")) ? "consent" : "open";
  if (request.cookies.get(REGION_COOKIE)?.value !== region) {
    response.cookies.set(REGION_COOKIE, region, { path: "/", sameSite: "lax", secure: true, maxAge: 60 * 60 * 24 });
  }
  return response;
}

// Pages only: skip Next assets and files with an extension (images, llms.txt, sitemap.xml and so on).
export const config = { matcher: ["/((?!_next/|.*\\..*).*)"] };
