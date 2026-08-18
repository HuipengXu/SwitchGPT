# macOS distribution and notarization

SwitchGPT has separate local-validation and public-distribution paths. A valid
Apple Development signature proves the bundle and its embedded recovery helper
are assembled consistently on this Mac. It does not make the app acceptable to
Gatekeeper on another Mac.

Public distribution requires all of the following:

- a `Developer ID Application` identity for Team `A3JV7CHQDT`;
- hardened runtime on the app and embedded recovery helper;
- matching non-empty Team IDs and the expected signing identifiers;
- acceptance by Apple Notary Service;
- a stapled ticket and a successful Gatekeeper assessment;
- a checksum generated after stapling.

The Team ID matches the existing Apple Developer configuration used by the
sibling `babytracker` project. No certificate, private key, Apple ID, app-specific
password, or App Store Connect key belongs in this repository.

## Local Release bundle validation

Use the locally installed Apple Development identity only for local validation:

```sh
SWITCHGPT_SIGNING_IDENTITY="Apple Development: …" \
  SWITCHGPT_VERSION="0.1.0" \
  SWITCHGPT_BUILD_NUMBER="1" \
  ./Scripts/build-release-app.sh

./Scripts/verify-release-app.sh --app dist/release/SwitchGPT.app
```

`Scripts/package-release.sh` intentionally rejects this signature class. This
prevents a development-signed ZIP from being mistaken for a public release.

## Developer ID archive

After a Developer ID Application certificate and its private key are installed:

```sh
SWITCHGPT_SIGNING_IDENTITY="Developer ID Application: …" \
  SWITCHGPT_VERSION="0.1.0" \
  SWITCHGPT_BUILD_NUMBER="1" \
  ./Scripts/package-release.sh
```

The packaging script rebuilds the app, verifies the nested signature and
hardened runtime, creates an architecture-labelled ZIP, extracts that ZIP into a
temporary directory, verifies the extracted app again, and writes a SHA-256 file
whose entry uses only the archive basename.

## Notarized archive

First store notarization credentials in the login Keychain using
`xcrun notarytool store-credentials`. Give the profile a non-secret local name;
do not put the Apple ID password, app-specific password, private key, or profile
contents in an environment file or this repository.

Then run the explicit networked release step:

```sh
SWITCHGPT_SIGNING_IDENTITY="Developer ID Application: …" \
  SWITCHGPT_NOTARY_KEYCHAIN_PROFILE="SwitchGPT-notary" \
  SWITCHGPT_VERSION="0.1.0" \
  SWITCHGPT_BUILD_NUMBER="1" \
  ./Scripts/notarize-release.sh
```

This is the only script that submits an artifact to Apple. It waits for the
result, staples and validates the ticket, runs `spctl`, then recreates the ZIP and
checksum because stapling changes the app bundle. Do not upload the pre-stapling
archive.

Before GitHub Release publication, also run the Swift tests, the 26-scenario
cross-process matrix, the strict public-tree audit, and the exact-history review
defined in [PUBLIC_RELEASE.md](PUBLIC_RELEASE.md).

## Public alpha release

The public `0.1.0 (1)` arm64 archive is built from the isolated, audited
single-commit release candidate. Before publication, the final archive is
accepted by Apple Notary Service, stapled, re-verified from a fresh extraction,
and assessed by Gatekeeper as `Notarized Developer ID`. The post-stapling
archive and its SHA-256 sidecar are published together as GitHub Release assets;
`dist/` remains ignored by Git.

The public alpha keeps real account switching experimental and default-off. Each
switch requires explicit confirmation, and the recovery path must restore the
original state if any step fails.
