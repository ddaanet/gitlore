# 2026-05-23

Memory redirect reworked. Discovered CC honors `autoMemoryDirectory` only from
`policySettings`/`flagSettings`/`userSettings` — the prior
`.claude/settings.local.json` write was silently ignored and memory stranded in
the default dir. Added the Memory Redirect Launcher: a transparent `claude` shim
injecting `--settings` (one shim, two placements — repo-local committed
`.gitlore/bin/claude` + `.envrc` `PATH_add` via direnv as default; global
`~/.gitlore/bin/claude` via `global-shim.sh` / Placement B as no-direnv
fallback). Added `GITLORE_LAUNCHED` sentinel (anti-double-inject + SessionStart
launcher guard). Install no longer writes `autoMemoryDirectory`; SessionStart
warns loudly when launched without the shim. Added D10 and four Rejected
Alternatives (project-tier setting, global userSettings, cowork env override,
explicit launch command).
