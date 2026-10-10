import { llmsFullTxt } from "@/content/llms";

export function GET() {
  return new Response(llmsFullTxt, { headers: { "Content-Type": "text/plain; charset=utf-8" } });
}
