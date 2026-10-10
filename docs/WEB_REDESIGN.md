# Website redesign notes

Updated 10 October 2026.

## Current direction

- Warm cream page, restrained orange accents, and the existing transparent logo on a brown tile.
- Clean Explore, How to connect, and Support navigation.
- Three static illustrated feature stories, replacing the tabs and automatic rotation at the user's latest request. There is no timer or carousel.
- Subtle page and scroll entrances, hover feedback, and reduced-motion handling. The feature illustrations do not animate or change.
- Footer with a connection guide invitation, grouped product and legal links, and a quiet copyright row.
- Separate /setup guide for local Wi-Fi, Tailscale, permissions, pairing, reconnection, and common problems.

## Guide evidence

App labels and routes checked in MenuView.swift, HomeView.swift, Android MainActivity.kt, SessionEngine.swift, and Session.kt. Both clients save host-reported Tailscale routes. Port 47800 is the Mac listener.

Tailscale instructions checked against its official [quickstart](https://tailscale.com/docs/how-to/quickstart), [download page](https://tailscale.com/download), and [connection types](https://tailscale.com/docs/reference/connection-types) documentation. Relays remain encrypted, but can increase delay. The guide describes the supported flow; physical Tailscale-over-cellular acceptance remains pending in ACCEPTANCE.md.

Public Tetherly downloads remain in preparation. Website copy does not imply a published release.

## Illustration provenance

Tool: built-in image_gen, edit mode using the existing control illustration. Output converted to 720px WebP with cwebp. Originals retained in the generation workspace.

Website files:
- apps/web/public/illustrations/feature-keyboard.webp
- apps/web/public/illustrations/feature-sharing.webp

Exact prompt set:

1. Create a keyboard-and-shortcuts illustration variant of the supplied Tetherly website illustration. Preserve the same square composition, warm cream background, soft matte ceramic 3D style, restrained orange accents, laptop in back right and hand-held phone in front left. Change the action to typing on the phone: a finger pressing the phone's clearly visible on-screen keyboard, with a simple note window on the Mac showing a few short lines of text. Remove all pointer arrows and trails. A subtle curved orange link connects phone and Mac. Clean friendly composition with ample breathing space, consistent lighting and device proportions. No marketing copy, no labels, no watermarks, no extra logos. One complete square image.

2. Create a file-and-clipboard-sharing illustration variant of the supplied Tetherly website illustration. Preserve the same square composition, warm cream background, soft matte ceramic 3D style, restrained orange accents, laptop in back right and hand-held phone in front left. Change the action to sending a document between phone and laptop. Show a simple document card on the phone and a matching document with an orange acceptance check on the Mac, with one small paper document moving along a curved orange connection between them. Remove all pointer arrows and trails. Clean friendly composition with ample breathing space, consistent lighting and device proportions. No marketing copy, no labels, no watermarks, no extra logos. One complete square image.



## Current feature artwork

The feature cards now use distinct flat 2D illustrations. See [asset paths and exact generation prompts](FEATURE_ILLUSTRATIONS_2D.md). Earlier 3D feature artwork above is superseded; the hero and pairing illustrations retain their existing style.

## Secondary pages and mobile footer, 10 October 2026

Setup, Support, Privacy, Terms, and the 404 page now use a shared editorial introduction with consistent type, spacing, and back navigation. Setup has a flat connection diagram, a preparation checklist, and sticky section introductions on desktop. Support has connection shortcuts, numbered FAQ rows, and separate support/security contacts. Legal pages use numbered sections with a desktop contents list and a collapsed mobile contents list. Original legal source text, section IDs, and dates are unchanged. The share image uses the warm site palette and current Wi-Fi/Tailscale copy.

The mobile footer now has a shorter headline, one full-width guide link, two direct link groups, and a centered copyright line reading "© 2026 Tetherly.". The repeated logo and Made by DataHase row was removed at the user's request, on both desktop and mobile.

Browser evidence: `docs/evidence/web-redesign-2026-10-10/secondary-pages-check.json` covers all six page routes at five widths in both themes. `footer-check.json` covers the final footer at those widths, with legal and guide navigation. Screenshots include setup, support, legal reading layouts, 404, share image, and final footer in both themes.

## Vercel upload correction

The linked project's Root Directory is `apps/web`, verified with `vercel project inspect tetherly`. The failed deployment logs showed only three uploaded files and a missing root directory. The installed Vercel CLI checks directory paths without trailing slashes; `!/apps/` did not unignore the parent directory during traversal. The root ignore file now uses `!/apps` and `!/apps/web`, excludes other app directories and local output, and preserves the complete website input set.

Validated with Vercel CLI 62.7.0's actual `buildFileTree` collector, without creating a deployment: 51 files, 731266 bytes, including source, public assets, package manifests, lockfile, and configuration. Native projects, evidence, environment files, dependencies, and caches are excluded. Manifest saved in `vercel-upload-check.json` alongside the screenshots. Deploy this linked project from the repository root, retaining the `apps/web` setting. See `apps/web/README.md` for commands.

## Footer navigation update, 10 October 2026

The desktop and mobile footer navigation now share one line of four links: Get support, Privacy, Terms, and GitHub. The Explore Tetherly and How to connect links were removed from the footer, the repository link is named GitHub, and the remaining links have matching icons. The centered copyright line remains the only text in its row. Current screenshots: `footer-desktop-links.png` and `footer-mobile-links.png`.
