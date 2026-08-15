# Real account-switch release gate

This runbook is for the one controlled real ChatGPT A↔B validation required before a public tag or release. It is not an application feature and must not be automated by the default app.

> **Suspended after the 2026-08-15 failed gate.** Do not execute this sequence until a new supervisor design has passed offline review. The retired `launchctl submit` mechanism is forbidden, and a controller running inside ChatGPT/Codex must never attempt to terminate its own host process. Public source visibility does not authorize another real test.

## Authorization boundary

The test is disruptive: it can quit and relaunch ChatGPT and temporarily replace the active authentication state. Before starting, the user must explicitly confirm both that no Work/Codex task is running and that this exact test is authorized. A suitable confirmation is:

> Confirm that no Work/Codex task is running, and authorize one real A↔B account-switch test.

Do not inspect Safari or any browser session for this test. Do not ask for, print, commit, or copy token values, cookies, passwords, or raw authentication files into the repository. Do not reuse the retired Phase C controller, retry its consumed reservation, or register a system service as part of this gate.

Authorization alone is not sufficient while this runbook is suspended. A future revision must first document a reviewed execution host that remains one-shot without submitted jobs, does not depend on the ChatGPT process it terminates, and cannot relaunch after reaching a terminal state.

## Preconditions

1. Confirm the active ChatGPT account is A and that the user has a recoverable private A state outside the repository.
2. Confirm the isolated B account home is outside the repository, has directory mode `700`, and has authentication file mode `600`.
3. Record only metadata: identity short hashes, account type/plan, file size, modification time, and SHA-256 values. Never record credential contents.
4. Confirm ChatGPT is running as the expected single process, no SwitchGPT lifecycle job or helper is present, and the Phase C service status remains `notRegistered`.
5. Build and test the current source before touching the desktop session.

## Acceptance sequence

The sequence below is retained as design history, not as an executable procedure.

1. Read A and B with the read-only app-server path and verify both identities and weekly quota. This step must not modify the active desktop account.
2. With the user’s confirmation still in force, perform one A→B transaction using the reviewed one-shot procedure: preflight, private backup, complete ChatGPT termination, atomic state replacement, relaunch, and identity verification.
3. Verify the returned account identity is B. Manually verify the visible Chat and Work identity where automation cannot provide an authoritative signal. Confirm a known historical Codex task is still discoverable.
4. Perform one B→A restoration using the same one-shot limits and verify A, the known task, and the original session state.
5. If a separate rollback check is authorized, inject only a bounded verification failure and allow at most one restoration launch. Any ambiguous identity, timeout, or second launch is a failed gate and must stop for manual recovery.
6. After the sequence, verify the active account is A, ChatGPT is running normally, there is one expected process, no lifecycle residue exists, and no repository file changed.

Any repeated launch, second controller delivery, or need to reboot the Mac is an immediate failed gate. Remove the exact temporary controller label, restore A, and stop. Do not retry in the same authorization window.

## Evidence to publish

The release record may contain only redacted metadata and outcome fields:

- test timestamp and ChatGPT build;
- A/B identity short hashes and plan names;
- A→B, B→A, and rollback outcomes;
- Chat/Work/Codex identity consistency result;
- historical task visibility result;
- process/residue checks and final A identity;
- hashes and permissions of private state files, without their contents.

Raw `auth.json`, token claims, cookies, email addresses, private logs, or account-specific baselines do not belong in a public report. If the test fails or leaves an ambiguous state, do not publish a release; restore the known account manually and document the failure privately.

The test passing is a release decision only. It does not enable real switching in the public alpha, which remains read-only/mock and simulation-only.
