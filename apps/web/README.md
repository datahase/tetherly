# Tetherly website

The public site for [tetherly.link](https://tetherly.link): landing page, Privacy Policy, Terms of Use, Support, and a connection guide.
Next.js (App Router, TypeScript), Tailwind CSS v4, shadcn/ui (Base UI), `motion` for animation. Every route is
prerendered as static content; there is no server data, no cookies and no analytics.

[Community documentation](../../docs/README.md) · [Contributor guide](../../CONTRIBUTING.md)

## Develop

Use Node.js 24 LTS and the pnpm version pinned in `package.json`. Run these commands from `apps/web`.

```sh
pnpm install --frozen-lockfile
pnpm dev        # http://localhost:3000
```

## Check and build

```sh
pnpm lint
pnpm build      # all routes must show as ○ (Static)
pnpm start      # serve the production build locally
```

## Where things live

- `src/lib/site.ts`: the one place for the site name, URL, GitHub repo, company and contact emails.
- `src/app/`: pages (`/`, `/setup`, `/privacy`, `/terms`, `/support`), `not-found`, `sitemap.ts`, `robots.ts`,
  `opengraph-image.tsx` (generated at build), `icon.png` and `apple-icon.png`.
- `src/components/`: header, footer, legal page layout, theme toggle, and `reveal.tsx` (the only animation
  primitives; they honour `prefers-reduced-motion`).
- `public/illustrations/`: WebP illustrations. `public/logo.png`: the transparent mark, displayed on a brown tile.

Legal pages show their date from `site.legalEffectiveDate`. Update it whenever the policy or terms change.

## Deploy

Any host that runs Next.js works, for example Vercel (set the project root to `apps/web`) or a Node server running
`pnpm build && pnpm start`. Point the `tetherly.link` domain at it. `next/image` resizes images at request time, so a
fully static export (`output: "export"`) would need `images.unoptimized: true`.

### Vercel monorepo uploads

The linked Vercel project has Root Directory `apps/web`. Run the CLI from the repository root, so uploaded paths retain the `apps/web` prefix:

```sh
# From the repository root (the directory containing apps/)
vercel          # preview
vercel --prod   # production, when ready to publish
```

Do not deploy this linked project from inside `apps/web`. The root `.vercelignore` retains the website source, public assets, manifests, lockfile, and configuration. It excludes native projects, protocol files, evidence, local environment files, dependencies, and build output. Its directory patterns have no trailing slashes because Vercel's file collector tests directory paths without them. The website's own ignore file supports projects configured with the website directory as their upload root.

## SEO and answer engines
- Per-page metadata comes from `pageMetadata()` in `src/lib/seo.ts`: canonical URL, Open Graph and Twitter cards. Every page must use it, or it inherits the home page's share title and URL.
- Structured data (JSON-LD): Organization and WebSite on every page, SoftwareApplication on `/`, HowTo on `/setup`, FAQPage on `/support`, Blog and BlogPosting on the blog, and breadcrumbs on subpages.
- `/llms.txt` and `/llms-full.txt` are generated from `src/content/` (FAQ and blog posts), so they stay in sync with the pages.
- Blog posts live in `src/content/blog/posts.ts` (markdown subset in `src/lib/markdown.ts`). Each gets a share image, an RSS entry at `/blog/feed.xml` and a sitemap entry.
- Also generated: `/sitemap.xml`, `/robots.txt`, `/manifest.webmanifest`. Static: `/.well-known/security.txt` (renew its `Expires` date yearly).
- `pnpm test` runs the markdown parser tests.
