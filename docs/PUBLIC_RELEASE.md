# Public alpha release contract

This document defines what may be published from this repository.

`0.1.0-alpha` is a read-only/mock public alpha. It does not claim that complete ChatGPT Desktop identity switching is safe or supported.

## Public in `0.1.0-alpha`

- SwiftPM sources, mock UI, tests, and documentation.
- The read-only quota decoder and its isolated app-server reader.
- Safety Core and temporary-fixture lifecycle validation.
- Deliberately reviewed, metadata-only validation notes (not raw protocol exports or machine logs).
- The redacted real A↔B release-gate record, after the separately authorized test passes.

## Not public or not enabled

- Raw authentication files, tokens, cookies, passwords, private keys, and account exports.
- A real account switch adapter or automatic ChatGPT process restart.
- `launchd`/`SMAppService` mutation from the default app or CI.
- User-specific credential homes or unredacted machine logs.

## Release gates

Before a public tag or GitHub release:

1. A controlled real A→B→A account test passes, including Chat/Work/Codex identity consistency, history visibility, failure rollback, and current-session integrity. This test requires explicit user authorization because it exits/restarts ChatGPT and temporarily replaces real authentication state.
2. `./Scripts/audit-public-repo.sh` passes against the exact public tree.
3. `xcrun swift test` passes.
4. `xcrun swift run SwitchGPTSafetySimulator matrix` reports 26/26.
5. `./Scripts/build-release-app.sh` produces a verified app bundle with the intended signing identity.
6. The release notes repeat the Phase 0 boundary and state that real switching is not enabled in the public alpha.
7. The public Git history contains no private validation material, user-specific account baselines, exported protocol schemas, machine logs, or authentication metadata.

The real A↔B test is a release decision gate only. Passing it does not authorize wiring real switching into the default app or publishing any credential-handling adapter.

For a distributable artifact, run `Scripts/package-release.sh` with a Developer ID Application identity. Apple Development signatures are suitable for local bundle verification only; they are not a public Gatekeeper release.

## Current state

The repository is being prepared for the public alpha, but no public tag or GitHub release should be created until the real A↔B gate and the exact public-history audit are complete.

The alpha is a read-only/mock product and safety-core reference implementation, not a promise that complete ChatGPT Desktop identity switching is safe or supported.
