# ADR-0001: Freeze the Hub-managed local WSL path

## Status

Accepted.

## Decision

`windows-hub-local-managed-wsl` is the sole v0.1 primary installation mode. It means Windows 11 x64, the unchanged official Windows Hub installer, the Hub's local setup, and its default `OpenClawGateway` WSL Gateway.

## Consequences

The package must not treat a Windows-host `openclaw.exe` as a prerequisite. Diagnostics may observe a native CLI if it exists, but it remains non-primary. Windows 10, ARM64, macOS, Linux, remote Gateway, SSH tunnels, channels, Skills, plugins, and cloud-server paths are out of scope. This is an XQ validation boundary, not a claim about upstream support.
