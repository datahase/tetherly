# Security policy

Tetherly gives a paired phone or tablet control of a Mac, so security reports get priority.

## Reporting a vulnerability
Email **security@tetherly.link** with a description, the affected versions and steps to reproduce. You can also use
GitHub's private vulnerability reporting on this repository when that option is enabled. Please do not open a public issue or discuss the problem
publicly until a fix is released.

We aim to acknowledge reports within 3 working days and to share an assessment and expected timeline within 10 working
days. We will credit you in the release notes unless you prefer otherwise.

## Scope
In scope: the Mac host, the Android and iOS apps, the wire protocol (`protocol/SPEC.md`), pairing, and key storage.
Especially relevant: anything that lets an unpaired device connect, view the screen or inject input; bypasses of the
pairing code comparison; key extraction; and path traversal or overwrite through file transfer.

Out of scope: attacks that need an already unlocked and compromised Mac or phone, social engineering, and denial of
service on a network the attacker already controls.

## Supported versions
Only the latest release receives security fixes.

The design and threat model are documented in [docs/SECURITY.md](docs/SECURITY.md).
