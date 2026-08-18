# Security policy

## Supported scope

The supported public alpha consists of:

- the read-only/mock SwiftUI application;
- the read-only quota decoder and isolated app-server reader;
- app-managed private account sign-in and storage;
- the temporary-fixture Safety Core and offline lifecycle validation.

Real ChatGPT Desktop identity switching is default-off and remains outside the supported public alpha until the real gate passes.

## Reporting a vulnerability

Please do not open a public issue for a suspected credential, token, authentication-file, or account-isolation vulnerability. Use a private GitHub Security Advisory for the repository, or contact the maintainers privately before disclosing details.

Never include access tokens, refresh tokens, ID tokens, cookies, passwords, private keys, or copied `auth.json` files in a report. Redacted logs and metadata-only hashes are sufficient for initial triage.

## Security boundaries

- Credentials must remain outside the repository.
- The app may persist account email addresses, membership labels, local profile paths, quota snapshots, and identity hashes only in its private `700/600` Application Support location. Email values must never be written to repository files, public diagnostics, switch receipts, or logs.
- The read-only adapter stages only a restricted copy outside the repository and requires a pinned identity hash.
- Safety Core tests operate only on temporary fixtures.
- System service mutation and real desktop switching require separate explicit authorization and are not part of normal development or CI.
- Runtime sources and scripts must not use `launchctl submit`; the retired mechanism caused repeated relaunches during private validation.
