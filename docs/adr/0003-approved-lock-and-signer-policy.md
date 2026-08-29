# ADR-0003: Require an approved lock and identity-bound verification

## Status

Accepted.

## Decision

Formal builds accept only an approved `upstream-lock.json` for `openclaw/openclaw-windows-node` repository ID `1144728715`. The lock fixes the release ID/tag, asset ID/name/size, GitHub REST `asset.digest` SHA-256, approved signer subject and thumbprint, timestamp requirement, and fixed-commit license file hashes. Builds verify all of those properties, plus the official asset digest, a valid Authenticode chain, and a valid timestamp.

## Consequences

`latest` is discovery-only. A newly observed signer, any other valid signer, a missing or malformed GitHub REST asset digest, or a missing/changed `LICENSE` or `src/OpenClaw.Tray.WinUI/THIRD_PARTY_NOTICES.md` rejects the build. GitHub API `license.spdx_id` metadata is insufficient: both files must be obtained from the locked commit and verified by hash.
