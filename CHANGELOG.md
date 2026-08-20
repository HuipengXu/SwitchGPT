# Changelog

## 0.1.0-alpha.2 - 2026-08-20

- Improve the status-bar popover layout and keep it open while refreshing usage.
- Make automatic quota refresh silent so account switching stays immediately available.
- Add clear account-row hover feedback and make the full Remove account button clickable.
- Refresh the product website with the current app screenshots, status-bar guidance, and alpha download links.

## 0.1.0-alpha.1 - 2026-08-19

- Add strict Release-bundle verification for identifiers, version fields, nested signatures, Team ID consistency, hardened runtime, and matching architectures.
- Require Developer ID Application for public ZIP packaging, re-verify the extracted archive, and add an explicit notarization, stapling, Gatekeeper, and post-stapling checksum workflow.
- Rebuild the app shell, account list, usage detail, settings, sign-in, and switch confirmation around a measured ChatGPT desktop-inspired monochrome design system; remove repeated quota cards and unused accent styling.
- Publish the audited macOS alpha from an isolated single-commit source tree.
- Add an explicit pre-release gate for a separately authorized real A↔B validation.
- Add an ordinary “Sign in another account” flow backed by official OpenAI login and app-managed private storage; no folder selection is exposed.
- Complete one real A→B→A round trip through the signed independent app/helper path with a single stable ChatGPT process and zero lifecycle residue.
- Add private append-only terminal switch receipts so launch budgets, rollback outcomes, and final identity hashes remain independently verifiable after later user actions.
- Show “Switch ChatGPT to this account” on real account cards when experimental switching is enabled instead of the read-only menu-bar wording.
- Auto-import the active local account when the untouched Personal/Work demo catalog is detected.
- Fix app-server pipe reads that waited for 4096 bytes, timed out, and could terminate the host before quota appeared.
- Add a default-off experimental switch flow with fresh task acknowledgement for every operation.
- Add a signed independent host collector, same-team embedded recovery helper, secure auth installer, pinned identity reader, and bounded ChatGPT process adapter.
- Preserve the active account automatically in app-managed 700/600 storage before enabling a real switch, and refresh that profile atomically before switching away.
- Add a one-shot SIGTERM fallback after the normal AppKit termination request, use `open -n` with the verified app path, and require a stable single launch before success.
- Retain manual-recovery transaction evidence and block a new transaction while any prior transaction directory remains.
- Embed and sign the recovery helper in debug and release app bundles; derive the trusted Team ID from the actual signing certificate.
- Retire `launchctl submit` as a transaction host after the release-gate restart-loop incident.
- Add an independent supervisor host contract and require recovery readiness before the first desktop side effect.
- Persist only local profile paths, display metadata, and pinned identity hashes; never persist credential contents.
- Record the product owner's private permission for the current product name and icon without publishing private correspondence.

Real ChatGPT Desktop switching remains default-off, experimental, and requires
explicit confirmation for every operation in this alpha.
