import { ogImage } from "@/lib/og";

export const alt = "Tetherly: Your Mac, a little closer. Connect on Wi-Fi or with Tailscale.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return ogImage({ title: "Your Mac,", accent: "a little closer.", subline: "Wi-Fi at home. Tailscale when you're away." });
}
