# ADR-0004: Treat each release as immutable and separately approved

## Status

Accepted.

## Decision

Each XQ package version binds to one approved upstream lock and a precise ZIP SHA-256. New upstream versions run the full M1–M9 process and create a new record; no `latest.zip` alias or in-place replacement is permitted.

## Consequences

Any missing prerequisite blocks release. A passed CI build remains a candidate until the Windows 11 x64 VM gate passes. A mismatch between delivery ZIP and M9-approved ZIP immediately pauses delivery while preserving historical approval evidence.
