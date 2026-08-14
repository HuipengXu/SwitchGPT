# Security policy

## Supported scope

The supported public alpha consists of:

- the read-only/mock SwiftUI application;
- the read-only quota decoder and isolated app-server reader;
- the temporary-fixture Safety Core and offline lifecycle validation.

Real ChatGPT Desktop identity switching is not enabled and is outside the supported public alpha.

## Reporting a vulnerability

Please do not open a public issue for a suspected credential, token, authentication-file, or account-isolation vulnerability. Use a private GitHub Security Advisory for the repository, or contact the maintainers privately before disclosing details.

Never include access tokens, refresh tokens, ID tokens, cookies, passwords, private keys, or copied `auth.json` files in a report. Redacted logs and metadata-only hashes are sufficient for initial triage.

## Security boundaries

- Credentials must remain outside the repository.
- Default UI actions use mock data. The app may persist only non-sensitive mock metadata in a private `700/600` Application Support location.
- The read-only adapter stages only a restricted copy outside the repository and requires a pinned identity hash.
- Safety Core tests operate only on temporary fixtures.
- System service mutation and real desktop switching require separate explicit authorization and are not part of normal development or CI.
