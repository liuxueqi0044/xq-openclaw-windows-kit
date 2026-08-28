# ADR-0003: Require an approved lock and identity-bound verification

## Status

Accepted.

## Decision

Formal builds accept only an approved `upstream-lock.json` for `openclaw/openclaw` repository ID `1103012935`. The lock fixes the release ID/tag, asset ID/name/size, SHA-256, approved signer subject and thumbprint, timestamp requirement, and fixed-commit license file hashes. Builds verify all of those properties, plus an official checksum, a valid Authenticode chain, and a valid timestamp.

## Consequences

`latest` is discovery-only. A newly observed signer, any other valid signer, a missing checksum, or a missing/changed `LICENSE` or `THIRD_PARTY_NOTICES.md` rejects the build. GitHub API `license.spdx_id` metadata is insufficient: both files must be obtained from the locked commit and verified by hash.
