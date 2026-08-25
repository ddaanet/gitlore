# 2026-06-10 — Implemented D14 — user-facing SessionStart output on `systemMessage`

Every user-visible SessionStart notice now rides the single SessionStart
`systemMessage` (the only reliably user-visible hook channel — verified
2026-06-10; stderr surfaces only on exit 2 / `--verbose`). The two fatal notices
(parent branch named `live`; memory diverged from `live`) changed from
`echo >&2; exit 1` (effectively invisible) to `systemMessage` + `exit 0`
(non-blocking; exit code consumed by nothing). The dirty-skip notice moved off
stderr, and a clean start now emits a brief confirmation
(`memory ready (… synced with live)`), per the always-confirm choice.
`session-start.sh` gains a `sysmsg` accumulator + `emit_session_json` helper;
`gitlore_say_for_agent_or_user` is retained only for the git hooks (which run
outside a session). `additionalContext` still carries the D12 commit-protocol
orientation on every path. `cc_hook_session_start.bats`: 3 tests rewritten + 1
added (divergence); 183 green.
