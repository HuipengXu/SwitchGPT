# Public alpha release contract

This document defines what may be published from this repository.

`0.1.0-alpha.1` is the first public alpha. The source, tag, GitHub Release, and binary are published only from the isolated audited tree described below.

## Public in `0.1.0-alpha.1`

- SwiftPM sources, mock UI, tests, and documentation.
- The read-only quota decoder and its isolated app-server reader.
- Safety Core and temporary-fixture lifecycle validation.
- Deliberately reviewed, metadata-only validation notes (not raw protocol exports or machine logs).
- A high-level, metadata-only statement that a private gate failed, without account identifiers or machine logs.

## Not public or not enabled

- Raw authentication files, tokens, cookies, passwords, private keys, and account exports.
- An enabled-by-default account switch or any adapter that has not passed the real release gate.
- `launchd`/`SMAppService` mutation from the default app or CI.
- Any `launchctl submit` transaction host in runtime code or scripts.
- User-specific credential homes or unredacted machine logs.

## Tag and binary release gates

Before a public tag, GitHub Release, or distributable binary:

1. A controlled real A→B→A account test passes, including Chat/Work/Codex identity consistency, history visibility, failure rollback, and current-session integrity. This test requires explicit user authorization because it exits/restarts ChatGPT and temporarily replaces real authentication state.
2. `./Scripts/audit-public-repo.sh` passes against the exact public tree.
3. `xcrun swift test` passes.
4. `xcrun swift run SwitchGPTSafetySimulator matrix` reports 26/26.
5. `./Scripts/build-release-app.sh` produces a verified local app bundle with the intended signing identity.
6. The release notes state whether the experimental switch remains disabled or has separately passed the real gate; it is never enabled silently.
7. The public Git history contains no private validation material, user-specific account baselines, exported protocol schemas, machine logs, or authentication metadata.
8. A public binary is signed with Developer ID Application, accepted and stapled by Apple Notary Service, passes Gatekeeper assessment, and is archived with a post-stapling SHA-256 checksum.

The real A↔B test is a release decision gate only. Passing it does not by
itself enable default switching or authorize publishing an unreviewed
credential-handling adapter; this alpha publishes only the reviewed adapter and
keeps it default-off.

For a distributable artifact, follow [MACOS_DISTRIBUTION.md](MACOS_DISTRIBUTION.md). `Scripts/package-release.sh` rejects Apple Development signatures, and `Scripts/notarize-release.sh` is the only explicit Apple submission step. Apple Development signatures are suitable for local bundle verification only; they are not a public Gatekeeper release.

## Source publication gate

The repository must remain private until the real-switch gate and all other release checks pass. After completion, generate and audit the exact source tree intended for GitHub before changing repository visibility. Source publication does not waive any tag or binary release gate.

The private `main` history contains deliberately excluded validation paths and
must never be made public in place. `Scripts/prepare-public-release-repo.sh`
creates an isolated, no-remote, single-commit repository from the explicit
public export allowlist. It then runs both the strict tree audit and a complete
history audit. The preparation script cannot push, create a tag, or change
GitHub visibility.

## Current state

The local development repository remains private because its history contains excluded validation material. The public GitHub repository is populated only from the isolated, no-remote, single-commit candidate after the exact public-history audit and final release configuration complete.

The 2026-08-15 private gate failed because the submitted-job controller caused repeated ChatGPT relaunches. The active account was restored, temporary jobs were removed, and runtime/public audit surfaces now reject that controller mechanism.

On 2026-08-16 the replacement independent app/helper path completed a real A→B→A round trip with one stable ChatGPT process and zero lifecycle residue. A separately authorized B→A failure injection then produced an append-only receipt recording `rolledBack`, final B, one target launch, one rollback launch, and `targetIdentityMismatch`; the UI reported safe restoration and this Codex task resumed after restart. The real-switch safety gate is complete. An isolated, no-remote, single-commit public-history candidate passes the current tests, the 26/26 matrix, website build, strict tree audit, and complete history audit. The product owner has also confirmed private OpenAI permission covering the current product name and icon; the exact private correspondence is intentionally not included.

The public alpha provides real quota, managed sign-in, and a default-off experimental adapter. The real-switch gate has passed, but switching remains explicitly experimental and requires explicit confirmation for every operation.

The experimental adapter fails closed before quitting ChatGPT unless the fixed
application path has the expected bundle identifier, strict valid signature,
OpenAI Team ID, signing identifier, and the remaining credential, helper, and
transaction preflights. An exact version/build pair in the compatibility list is
shown as validated. A different but still officially signed client may be tried
only after the same explicit switch confirmation; target-identity failure uses
the existing one-shot rollback path and never retries the target. Quota viewing
and managed sign-in do not use this version classification.

On 2026-08-17, the user explicitly authorized creating a Developer ID Application identity for Team `A3JV7CHQDT` in Xcode and separately authorized the Apple notarization workflow. The current public arm64 candidate was rebuilt from the exact isolated source tree on 2026-08-19 and accepted by Apple Notary Service. The app and embedded recovery helper pass strict Developer ID verification and hardened-runtime checks; the ticket is stapled and validates; both the local app and the app extracted from the final arm64 ZIP pass Gatekeeper as `Notarized Developer ID`; and the post-stapling ZIP passes SHA-256 validation.

The current official OpenAI brand guidelines are retained as the baseline for
interoperability language and logo use. The product owner has confirmed private
permission covering the current name and icon, so no rename is required for this
alpha. See [BRAND_RELEASE_REVIEW.md](BRAND_RELEASE_REVIEW.md); the repository does
not include private authorization correspondence.
