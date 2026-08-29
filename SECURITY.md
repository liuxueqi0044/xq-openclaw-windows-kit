# Security Policy

## Supported scope

Security reports are accepted for the current `main` branch and for build,
diagnostic, privacy, packaging, and release-governance code maintained in this
repository.

Upstream OpenClaw vulnerabilities should be reported to the upstream project.
This repository does not modify or redistribute the upstream executable.

## Reporting a vulnerability

Use GitHub private vulnerability reporting for this repository when it is
available. Do not disclose an unpatched vulnerability in a public Issue.

Never include any real API key, token, cookie, password, private key, customer
file, session transcript, raw diagnostic log, or other sensitive data in a
report. Reproduce with synthetic data and provide the smallest safe example.

## Test-fixture notice

Files below `tests/Fixtures` intentionally contain strings shaped like API
keys, tokens, credentials, email addresses, and Windows user paths. Every such
value is synthetic and non-functional. Reserved domains such as
`example.test`, names beginning with `fixture`, and 15-byte text files carrying
an `.exe` extension are used to test redaction and packaging controls.

A secret-scanning match inside a fixture must still be reviewed. The word
`fixture` is evidence of test intent, not an automatic exemption from review.

## Security posture

- Diagnostic tools are designed to be read-only, non-elevating, and offline.
- Supply-chain verification fails closed on identity, digest, hash, signature,
  or license mismatch.
- Package assembly uses an explicit allowlist and re-verifies the expanded ZIP.
- No security control is claimed to be perfect; a clean Windows VM and manual
  acceptance remain required before a product release.

