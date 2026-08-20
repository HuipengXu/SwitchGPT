# Real account-switch release gate

This runbook is for the one controlled real ChatGPT A↔B validation required before a public tag or release. It is not an application feature and must not be automated by the default app.

> **Completed on 2026-08-16.** The replacement signed independent app host completed one real A↔B→A round trip and one separately authorized B→A→B bounded rollback without lifecycle residue. The rollback receipt recorded final B, target and rollback launch counts of one, and `targetIdentityMismatch`. This completed gate must not be repeated merely to gather duplicate evidence. The retired `launchctl submit` mechanism remains permanently forbidden.

## Authorization boundary

The test is disruptive: it can quit and relaunch ChatGPT and temporarily replace the active authentication state. Before starting, the user must explicitly confirm both that no Work/Codex task is running and that this exact test is authorized. A suitable confirmation is:

> Confirm that no Work/Codex task is running, and authorize one real A↔B account-switch test.

Do not inspect Safari or any browser session for this test. Do not ask for, print, commit, or copy token values, cookies, passwords, or raw authentication files into the repository. Do not reuse the retired Phase C controller, retry its consumed reservation, or register a system service as part of this gate.

The authorization applies to one gate only and expires when the sequence ends or any ambiguity occurs. It never permits retrying a launch, using an old external controller, or running the switch from inside ChatGPT/Codex.

## Preconditions

1. Confirm the active ChatGPT account is A and that the user has a recoverable private A state outside the repository.
2. Confirm the isolated B account home is outside the repository, has directory mode `700`, and has authentication file mode `600`.
3. Record only metadata: identity short hashes, account type/plan, file size, modification time, and SHA-256 values. Never record credential contents.
4. Confirm ChatGPT is running as the expected single process, no SwitchGPT lifecycle job or helper is present, and the Phase C service status remains `notRegistered`.
5. Build and test the current source before touching the desktop session.
6. Confirm the active account is backed by an app-managed private profile rather than the mutable active `~/.codex` path.
7. Confirm the Transactions root is empty. Any retained transaction is a hard stop requiring manual review, not a candidate for automatic cleanup or retry.
8. Confirm `SwitchReceipts` is a private `700` directory. A terminal test is accepted only when its append-only metadata receipt is `600`, matches the transaction UUID, and records the expected final identity and launch budgets.

## Acceptance sequence

The sequence below is the current release gate. The app remains in default-off experimental mode until it passes.

1. Read A and B with the read-only app-server path and verify both identities and weekly quota. This step must not modify the active desktop account.
2. With the user’s confirmation still in force, perform one A→B transaction using the reviewed one-shot procedure: preflight, private backup, complete ChatGPT termination, atomic state replacement, relaunch, and identity verification.
3. Verify the returned account identity is B. Manually verify the visible Chat and Work identity where automation cannot provide an authoritative signal. Confirm a known historical Codex task is still discoverable.
4. Perform one B→A restoration using the same one-shot limits and verify A, the known task, and the original session state.
5. If a separate rollback check is authorized, inject only a bounded verification failure and allow at most one restoration launch. Any ambiguous identity, timeout, or second launch is a failed gate and must stop for manual recovery.
6. After the sequence, verify the active account is A, ChatGPT is running normally, there is one expected process, no lifecycle residue exists, and no repository file changed.

Any repeated launch, second controller delivery, or need to reboot the Mac is an immediate failed gate. Remove the exact temporary controller label, restore A, and stop. Do not retry in the same authorization window.

The desktop process controller may request normal AppKit termination and then send `SIGTERM` once to the exact original PID set after a bounded grace period. `SIGKILL`, repeated signals, PID broad matches, and launch retries are forbidden. A launch succeeds only when `/usr/bin/open -n` returns successfully and exactly one new ChatGPT process remains stable for the configured observation interval.

## Evidence to publish

The release record may contain only redacted metadata and outcome fields:

- test timestamp and ChatGPT build;
- A/B identity short hashes and plan names;
- A→B, B→A, and rollback outcomes;
- Chat/Work/Codex identity consistency result;
- historical task visibility result;
- process/residue checks and final A identity;
- the redacted terminal receipt fields and confirmation that the private receipt file is `600`;
- hashes and permissions of private state files, without their contents.

Raw `auth.json`, token claims, cookies, email addresses, private logs, or account-specific baselines do not belong in a public report. If the test fails or leaves an ambiguous state, do not publish a release; restore the known account manually and document the failure privately.

The test passing is a release decision only. It permits a separate decision about enabling the current default-off experimental adapter; it does not silently turn the feature on for users.
