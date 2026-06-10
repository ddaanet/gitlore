## Current task

Write up two design-doc changes and implement both with bats tests (TDD): D13 — a git-lock retry wrapper, and D14 — consolidating gitlore's user-facing hook output onto `systemMessage`. Analysis is done and approved; nothing implemented yet (working tree was clean).

## D13 — git-lock retry with backoff

- Add `gitlore_git` wrapper to `scripts/lib/util.sh`: runs `git "$@"`, on lock-contention stderr retries on schedule `0.1 0.2 0.4 0.8 1.6 3.2 3.7` (cumulative exactly 10.0s — last term is the budget remainder, NOT a doubled value), surfaces the final stderr+exit code unchanged.
- Lock signature matcher: `index.lock` / `File exists` / `Unable to create *.lock` / `cannot lock ref` / `another git process`. Non-lock failures fail fast (no retry).
- MUST NOT match resolve's `checkout live` one-checkout-per-branch error (`'live' is already used by worktree at …`) — that fast-fail is D3 and must stay.
- Apply to mutating git calls (read-only ops never lock): `session-start.sh:100-124`, `git-hooks/pre-commit:65-73`, `git-hooks/pre-push:57`, `resolve.sh` + `lib/resolve.sh` (except the lock checkout), `install/init-submodule.sh`, `install/create-remote.sh`.
- Origin: real `index.lock: File exists` collision hit dogfooding on edify (concurrent SessionStart ff-merge vs pre-commit chain on the shared submodule index).

## D14 — user-visible message channel consolidation

- Route user-facing output through `systemMessage` — the working user-visible channel for SessionStart/PostToolUse (gitlore's launcher-guard warning already uses it). See memory `reference-plugin-hook-user-channel`.
- SessionStart success path (`session-start.sh:135-143`): add a concise one-line `systemMessage` alongside the always-on commit-protocol `additionalContext`.
- SessionStart error paths (`:68-74`, `:123-130`): emit via `systemMessage` AND keep stderr+exit for the plain-terminal case.
- PostToolUse (`post-tool-use.sh:31-38`): add `systemMessage` next to the existing `additionalContext`.
- Do NOT surface via the agent (additionalContext "tell the user…") — against NFR1/D7.

## Open decisions

- SessionStart `systemMessage` every launch is one extra line per session — user asked for it; confirm they don't want it gated to abnormal states only before finalizing.
- Whether WorktreeRemove's advisory stderr warnings (exit 0, currently silent to user) are in scope for D14 — it injects no context, so likely out of scope; confirm.
