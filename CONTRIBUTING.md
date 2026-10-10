# Contributing to Tetherly

Tetherly is a native Mac host with Android and iPhone/iPad clients. They share a wire contract, so a network change can affect all three apps. The website and documentation also welcome focused improvements.

[Documentation](docs/README.md) · [Development setup](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md)

## Find a useful starting point

You do not need every toolchain to help. Pick the area that matches your experience:

| Contribution | A useful first step |
| --- | --- |
| Documentation | Follow a setup guide from a clean starting point and clarify the first confusing step. |
| Device testing | Reproduce an issue with disposable content and report the device, OS, route, and result. |
| Accessibility | Check keyboard navigation, screen-reader labels, contrast, and reduced motion. |
| Native apps | Choose one reproducible bug and read its source map in the architecture guide. |
| Protocol/security | Read the specification and threat model; report vulnerabilities privately. |
| Website | Check an affected page at desktop and mobile sizes, including both themes. |

Read [current milestones](docs/PLAN.md) and [acceptance evidence](docs/ACCEPTANCE.md) before picking release work. Open an issue to discuss a large change, a new dependency, or a protocol change before implementation. Small corrections can go directly to a pull request.

## Community expectations

Follow the [Code of Conduct](CODE_OF_CONDUCT.md). Describe the behavior and evidence, and keep discussions respectful. Report security problems through the [private disclosure policy](SECURITY.md), rather than a public issue or pull request.

## Report a bug or request a feature

Use the repository's issue templates. A useful bug report includes:

- App version or commit, device models, and OS versions.
- Whether the connection uses local Wi-Fi or Tailscale.
- Short reproduction steps, expected behavior, and actual behavior.
- Relevant error text and checks already attempted.

Remove pairing codes, QR links, keys, desktop content, and clipboard text from shared logs or screenshots. For a feature request, describe the task it would help someone complete and any limits you already know.

## Make a focused change

1. Fork the repository and create a branch from `main`.
2. Follow [Development](docs/DEVELOPMENT.md) for the component you plan to change.
3. Keep the diff focused and match the surrounding code. Preserve unrelated local work.
4. Add or update meaningful checks for changed behavior. Update documentation when setup or user-visible behavior changes.
5. Run the relevant checks and review the final diff.
6. Sign off your commits, then open a pull request using the repository template.

For native work, preserve permission checks, bounded payloads, pinned identities, and session teardown. Changes to cancellation or reconnect behavior must not replay old input, leave capture running, or retain held keys/buttons. The [security design](docs/SECURITY.md) explains these requirements.

For protocol work, update [the specification](protocol/SPEC.md), the fixture generator and fixtures, and all affected implementations together. Explain compatibility with existing peers. Run the Swift and Kotlin fixture checks; byte-level agreement does not replace device testing.

For docs, use relative repository links, exact UI labels, and commands with a clear working directory. For visuals, use selected brand masters, retain provenance, and provide useful image descriptions.

## Prepare the pull request

Explain the problem, the resulting behavior, and why the change addresses it. Include a short reproduction or before/after example when useful. List the commands you actually ran and the results. For UI changes, attach desktop/mobile or device screenshots with private content removed.

The [development guide](docs/DEVELOPMENT.md) has the canonical check commands. Run checks for every affected component. Protocol changes need the host and both clients. Use a real device for capture, input, audio, transfers, and network recovery when those paths change; state clearly when you only tested in a Simulator or could not test a path.

Fill in the [pull request template](.github/PULL_REQUEST_TEMPLATE.md). Resolve local check failures and reviewer feedback before merge. A successful build alone does not establish a release-ready feature.

## Sign off your commits

Contributions use the [Developer Certificate of Origin](https://developercertificate.org/) (DCO). A sign-off certifies that you wrote the change or have the right to submit it under the project's license.

```sh
git commit -s -m "Describe the change"
```

This adds `Signed-off-by: Your Name <you@example.com>` to the commit message. Use your real name and sign off every contribution commit. A sign-off does not require cryptographic commit signing.

By contributing, you agree that your contribution is licensed under the [Apache License 2.0](LICENSE).

[Back to documentation](docs/README.md)
