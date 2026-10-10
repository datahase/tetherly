# Tetherly documentation

**Your Mac, a little closer.**

This is the community guide to using, understanding, and contributing to Tetherly. Start with the path that fits what you want to do.

> Tetherly 0.1.0 is available for Mac and Android from [tetherly.link](https://tetherly.link); App Store and Google Play releases are in review. These guides describe the current source, while the [acceptance record](ACCEPTANCE.md) tracks what has actually been checked.

## Try it

| Guide | What you will learn |
| --- | --- |
| [Getting started](GETTING_STARTED.md) | Build or prepare your devices, grant permissions, and make a first connection. |
| [Wi-Fi and Tailscale](CONNECTIONS.md) | Choose a route, pair safely, reconnect, and use a manual address. |
| [Troubleshooting](TROUBLESHOOTING.md) | Resolve discovery, permission, identity, and connection problems. |

**Suggested reading:** Getting started → Connections → Troubleshooting when you need it.

## Build and contribute

| Guide | What you will learn |
| --- | --- |
| [Development](DEVELOPMENT.md) | Toolchains, builds, signing, device installation, and component checks. |
| [Architecture](ARCHITECTURE.md) | How the host, clients, shared core, and separate channels fit together. |
| [Contributing](../CONTRIBUTING.md) | Pick a change, report a bug, sign off commits, and prepare a pull request. |
| [Wire protocol](../protocol/SPEC.md) | Framing, pairing, messages, channel tickets, and teardown requirements. |

**Suggested reading:** Development → Architecture → the wire protocol when changing network behavior.

## Trust, status, and releases

- [Security design](SECURITY.md): threat model, identities, pairing, storage, and review gates.
- [Report a vulnerability](../SECURITY.md): private disclosure instructions.
- [Plan and status](PLAN.md): scope and milestone progress.
- [Acceptance evidence](ACCEPTANCE.md): automated checks and real-device observations.
- [Publishing checklist](PUBLISHING.md): signing, notarization, store preparation, and release dependencies.
- [Code of Conduct](../CODE_OF_CONDUCT.md): expectations for community participation.

## Website and brand

The website has its own [development README](../apps/web/README.md). The [website design notes](WEB_REDESIGN.md) and [2D illustration notes](FEATURE_ILLUSTRATIONS_2D.md) record asset choices and provenance. Brand masters live in `design/brand/`; generated app assets should stay consistent with those sources.

## Reading the project status

“Implemented” means a code path exists. “Automated checks” means its behavior has been exercised by the listed checks. A Simulator run is useful evidence for layout and logic, but it does not establish physical-device capture, input, audio, or network performance. “Release ready” requires the remaining gates in the publishing and acceptance documents.

## Improve these docs

If a step is unclear, tell us where you started, which step failed, and what you expected. Documentation fixes use the same [contribution workflow](../CONTRIBUTING.md) as code. Keep commands runnable from the directory shown, use exact app labels, and link status claims to evidence.

[Back to the project](../README.md)
