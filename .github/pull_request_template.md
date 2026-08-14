## What changed

## Why

## Safety and privacy

- [ ] No raw credentials, tokens, cookies, private keys, or copied `auth.json` files are included.
- [ ] The default app still avoids real ChatGPT switching and system service mutation.
- [ ] Any new external side effect is documented and separately authorized.

## Validation

- [ ] `xcrun swift test`
- [ ] `xcrun swift run SwitchGPTSafetySimulator matrix`
- [ ] `./Scripts/audit-public-repo.sh`
