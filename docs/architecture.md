# XQ OpenClaw Windows Kit architecture baseline

This repository is a controlled digital-delivery project, not an OpenClaw installer project. It distributes an unchanged official installer only after the approved supply-chain and release gates pass.

The authoritative M0 implementation is machine-readable:

- Product scope and the sole commercial/support boundary: [`manifest/product-config.json`](../manifest/product-config.json)
- Diagnostic command allowlist: [`policy/diagnostic-command-policy.json`](../policy/diagnostic-command-policy.json)
- Trust and signer conditions: [`policy/signer-policy.json`](../policy/signer-policy.json)
- Release stop conditions: [`policy/release-gates.json`](../policy/release-gates.json)
- Support intake enforcement: [`policy/support-policy.json`](../policy/support-policy.json)

Human-facing content, README material, FAQ pages, listing copy, and support templates must link to `manifest/product-config.json#/productBoundary`; they must not define a second product or after-sales boundary.

## Frozen v0.1 path

The only XQ-validated environment is **Windows 11 x64**. The only standard flow is `windows-hub-local-managed-wsl`: the user runs the unchanged official Windows Hub installer, selects the local setup in the official Hub, and the official Hub manages its default `OpenClawGateway` WSL Gateway. The user enters model credentials in the official onboarding and completes their own test conversation.

This is an XQ validation scope, not a claim that upstream OpenClaw supports only Windows 11 x64. Windows 10, ARM64, macOS, Linux, cloud servers, remote Gateway, SSH tunnels, channels, Skills, plugins, and a native PowerShell CLI installation are outside the self-service product path. A native CLI may be reported by diagnostics when present, but never changes the primary path.

## Capability matrix

| Area | v0.1 policy |
|---|---|
| Operating-system scope | Windows 11 x64 only |
| Standard installation | Official Hub with locally managed WSL Gateway only |
| Credentials | Supplied by the user to official onboarding; never collected by XQ |
| Diagnostics | Explicit allowlist, read-only, redacted, no network upload |
| Node Mode, startup, privileged capabilities | User decision in official UI; never enabled by XQ |
| Repair and configuration writes | Not supported; prohibited from diagnostic commands |
| Remote assistance | Not included in the self-service SKU; requires a separate SKU and SOP |

## Fail-closed controls

Every official prerequisite that cannot be verified is `unverified`, not successful. `unverified` blocks release. Formal G1–G9 gate actions live in `policy/release-gates.json`; a successful build alone cannot authorize a listing or delivery.

The approved upstream lock is the sole formal-build input. It fixes repository ID, release, assets, checksums, signer subject and thumbprint, and source-file hashes. `latest` aliases, unsigned artifacts, a different valid signer, missing timestamp/chain evidence, and GitHub API license metadata are not acceptable substitutes for the approved lock plus fixed-commit `LICENSE` and `THIRD_PARTY_NOTICES.md` verification.

## Diagnostic safety contract

The diagnostic implementation may execute only exact entries in the command policy, with bounded per-command timeouts. It must not expand the list on error. Before it invokes `OpenClawGateway`, it must call `wsl.exe --list --running --quiet` and proceed only if that exact distro appears in the running list; inspection must never start a stopped distro. It may inspect narrowly scoped host, Hub, WSL, and command output data, but not full environment variables, configuration, sessions, browser data, logs, clipboard, or SSH data. It never installs, repairs, restarts, configures, uploads, elevates, or overwrites reports.

## Architecture decisions

- [ADR-0001](adr/0001-primary-hub-managed-wsl-path.md): unique Hub + local managed WSL path.
- [ADR-0002](adr/0002-read-only-diagnostic-posture.md): allowlist-only diagnostic posture.
- [ADR-0003](adr/0003-approved-lock-and-signer-policy.md): approved lock and signer verification.
- [ADR-0004](adr/0004-version-lifecycle.md): immutable version lifecycle.
- [ADR-0005](adr/0005-support-and-remote-service-boundary.md): canonical product/support boundary.
