# Release maintenance, 10 October 2026

The owner requested a fresh production build from consolidated main, version 0.1.0, followed by removal of automatic CI, Dependabot and extra branches.

The last main CI run (38061598953) passed Mac/iOS, website and protocol jobs. Android failed the premature-pair-done test. That test supplied every server frame immediately but expected queued client frames to have been flushed. The test transport now waits for hello, commit and reveal before supplying premature pair_done. It still verifies rejection, an empty trust store, and cancellation. Production pairing logic is unchanged. All 82 Android tests pass locally with the corrected fixture.

Dependabot's five Actions updates and test-only JSON update were integrated with their history preserved. The workflow was then removed at the owner's request. Compose BOM and coroutines-test upgrades are deferred to a focused Android dependency refresh. TypeScript 6 is deferred to a compiler migration. The Node 26 type proposal is superseded by matching Node 24 LTS and @types/node 24. Routine Dependabot configuration is removed. Source checks remain available locally.

Node 24 is declared in .nvmrc and package engines, and is used for the web build and deployment. The release helper's transitive basic-ftp dependency is pinned to 6.2.3 to resolve the FTP parser advisory reported by npm audit. FTP publishing is not enabled. Validate the release helper's dry run before using it.

The refreshed binaries use a separate distribution revision while app version remains 0.1.0. Keep the exact build source commit, signatures, notarization results, public file hashes and checks in the local release evidence. The website download links share one definition so installation guides cannot drift from the home page.

The owner requested removal of security, notarization and store/legal commentary from product copy. Detailed privacy disclosures remain on the privacy page; the source security review remains in the repository. Physical iOS camera testing is deferred by the owner. No independent security review or store publication is claimed.

The shadcn scaffolding CLI is a development dependency, not a website runtime dependency. The full development audit currently reports the braces 3.0.3 nested-pattern advisory through glob tooling; the registry has no patched 3.0.4 release yet. Production audit and lint/build are checked separately. Do not describe the full development audit as clean.
