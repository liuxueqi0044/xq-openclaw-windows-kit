# ADR-0002: Use an exact read-only diagnostic allowlist

## Status

Accepted.

## Decision

Diagnostics use only entries in `policy/diagnostic-command-policy.json`. The only OpenClaw inspections are `--version`, `doctor --json`, and `gateway status --json`, either in the managed WSL context or for a discovered native CLI. Before a managed-WSL inspection, the tool uses the exact `wsl.exe --list --running --quiet` command and runs no distro command unless `OpenClawGateway` is already listed as running. Each external process receives the policy timeout.

## Consequences

Commands and arguments containing `fix`, `repair`, `install`, `restart`, `set`, `remove`, `start`, `stop`, or `reload` are disallowed. The running-list guard prevents a read probe from implicitly starting a stopped WSL distro. The tool neither modifies the host nor uploads data. Probe failure creates an `unverified` finding rather than a guessed healthy state; only inability to safely create a new report may fail the entire diagnostic run.
