# 2026-10-16 — A script sources the libraries shipped beside it

**The blessed entry points and the two git hooks locate their libraries from
their own path.** `commit-memory.sh`, `push-memory.sh`, `merge-memory.sh`,
`emit-memory-gate.sh`, `git-hooks/pre-push` and `git-hooks/memory-pre-commit`
took `CLAUDE_PLUGIN_ROOT`, or else `$(git config gitlore.hooksDir)/../..`, as
the plugin root. `gitlore.hooksDir` is a per-repo pin that lags a plugin
upgrade, so a script run by path (the form `gitlore.commitCommand` and its kin
hand out) sourced an older cache's libraries. Observed: a 0.10.0
`commit-memory.sh`, called by path in a repo whose pin named a 0.6.0 cache, died
with `gitlore_approval_present: command not found`. `PLUGIN_ROOT` is now the
script's own tree, and neither the pin nor `CLAUDE_PLUGIN_ROOT` overrides it.
Nothing relied on the old lookup: the wrapper reaches the hooks through
`gitlore.hooksDir` and `exec`s them in place, so a hook's own path and the pin
agree whenever the wrapper ran it, and the wrappers keep resolving the hook
itself through the pin (D5).

`add-tier.sh`, `emit-wrappers.sh` and `install/*.sh` still prefer
`CLAUDE_PLUGIN_ROOT` and fall back to their own path. That variable reaches Bash
only where a caller exports it, so the same mismatch needs an explicit export
pointing at another tree; left as is.
