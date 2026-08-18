# Contributing to SwitchGPT

Thank you for helping improve SwitchGPT. The project is currently an alpha macOS app and a safety-focused technical spike.

## Scope

Contributions are welcome for:

- the read-only quota model and protocol decoder;
- the SwiftUI menu bar and account-management experience;
- the isolated Safety Core and its temporary-fixture tests;
- documentation, accessibility, packaging, and CI.

Do not add code that silently reads, writes, replaces, or prints real authentication material. Real ChatGPT account switching remains a suspended, disabled experiment and is not a default product capability. Runtime code and scripts must not use `launchctl submit` as a transaction host.

## Development setup

Requirements:

- macOS 14 or later;
- an Xcode toolchain that supports Swift 6.2;
- Swift Package Manager.

Run the checks from the repository root:

```sh
xcrun swift test
xcrun swift run SwitchGPTSafetySimulator matrix
./script/build_and_run.sh --verify
./Scripts/audit-public-repo.sh
```

The GUI path uses mock data by default. It must not require a login, a token, a copied `auth.json`, ChatGPT termination, `launchd`, or `SMAppService` mutation.

## Pull requests

Keep changes focused, explain user-visible behavior, and include tests for model or safety changes. Do not commit build products, local credentials, account baselines, or machine-specific logs. Use the pull request template and keep the public repository audit green.
