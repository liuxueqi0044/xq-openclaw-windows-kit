# Synthetic test fixtures

Every file below this directory is synthetic test data. No value is a working
credential, personal identifier, customer record, diagnostic export, or
official OpenClaw binary.

Some fixtures deliberately resemble API keys, tokens, email addresses,
Windows user paths, logs, or executable filenames so the redaction and package
security tests can prove that unsafe content is rejected.

- Reserved domains such as `example.test` are used for network-shaped data.
- Secret-shaped strings include `fixture` or `DO-NOT-USE` markers.
- Files named `OpenClawCompanion-Setup-x64.exe` are 15-byte text fixtures, not
  PE executables and not upstream installers.
- Upstream `LICENSE` and `THIRD_PARTY_NOTICES.md` fixtures are test placeholders,
  not copies of the official legal documents.

Do not replace these files with real logs, credentials, user paths, installers,
or customer data.
