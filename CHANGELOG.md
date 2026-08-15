# Changelog

## Unreleased

- Prepare the macOS app and repository for public alpha distribution.
- Add an explicit pre-release gate for a separately authorized real A↔B validation.
- Keep the default app read-only/mock; real switching remains disabled.
- Retire `launchctl submit` as a transaction host after the release-gate restart-loop incident.
- Clarify throughout the app and website that accounts, selection, and quotas are previews in the public alpha.
- Permit publishing the audited source repository separately from creating a tag or binary release.

## 0.1.0-alpha.1

- Add a ChatGPT-style sidebar and monochrome usage detail window.
- Show weekly quota in the menu bar and optional five-hour quota only when returned by the data source.
- Support an arbitrary number of mock accounts with local metadata persistence.
- Add isolated AppCore quota models, a read-only app-server adapter, and simulation-only switching.
- Add the Safety Core, cross-process recovery matrix, and offline lifecycle validation.

Real ChatGPT Desktop switching is intentionally not included in this alpha.
