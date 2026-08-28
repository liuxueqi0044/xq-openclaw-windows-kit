# ADR-0005: Keep product and after-sales boundaries canonical

## Status

Accepted.

## Decision

`manifest/product-config.json#/productBoundary` is the single source for product claims, included/excluded service, and support-data rules. All human-facing content must reference it instead of restating or widening it. Self-service support is written-only and can accept only user-reviewed, redacted diagnostics and non-sensitive order/version details. Remote support is a separate SKU with its own SOP.

## Consequences

XQ must never request API keys, passwords, cookies, tokens, remote-control credentials, full configuration files, or chat/session content. The self-service product does not promise official authorization, permanent updates, unlimited tokens, or unconditional compatibility, and it does not include unattended access or remote control.
