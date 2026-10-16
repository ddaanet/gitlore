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

**The scripts that preferred `CLAUDE_PLUGIN_ROOT` locate themselves too.**
`add-tier.sh`, `emit-wrappers.sh`, `resolve.sh` and the install scripts
`run.sh`, `emit-launcher.sh`, `write-settings.sh` and `create-remote.sh` took
`CLAUDE_PLUGIN_ROOT` ahead of their own path, so a session frozen at an older
root could run a newer script against older libraries, pin `gitlore.hooksDir`
and the command keys into the wrong tree, or run the continuation of a prepared
merge from a different tree than the script that prepared it. They resolve from
their own path now. `install/run.sh` and `resolve.sh` still export the result,
because `install/global-shim.sh` is the one script that requires
`CLAUDE_PLUGIN_ROOT` and is handed it by `run.sh`; the `cc-hooks` scripts take
the variable the harness injects for them and are unchanged.
