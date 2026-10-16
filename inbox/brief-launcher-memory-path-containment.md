## Brief: launcher shim passes an unvalidated repo path as `autoMemoryDirectory`

2026-10-13

Source: a background commit security review of ghmem's gitlore install
(gitlore 0.9.0), which flagged the generated `.gitlore/bin/claude` as
"path-traversal / trust-boundary bypass (repo-controlled value promoted to
trusted CLI setting)". The summary line was all the review delivered; the
analysis below is from reading the shim.

### The finding

`scripts/install/launcher-shim` builds the setting it injects from two files
the repository controls:

- `mempath` comes from `git config --file "$root/.gitmodules"
  submodule.gitlore-memory.path`.
- The gate is `.gitlore.enabled` in `$root/.claude/settings.json`.

It then runs `exec "$real" --settings '{"autoMemoryDirectory":"$root/$mempath"}'`.
Nothing checks that `$root/$mempath` stays under `$root`.

Claude Code does not honor `autoMemoryDirectory` from project settings (the
design doc's "Memory Redirect Launcher" section, D10, says so). The shim
exists to lift the value into an honored tier, and in doing so it gives a
value read from the checkout the standing of one the user typed.

### Attack shape

A hostile repository ships a `.gitmodules` whose `gitlore-memory` entry has
`path = ../../<somewhere>` and a `.claude/settings.json` with
`gitlore.enabled: true`. A user who has a gitlore shim on PATH and launches
`claude` inside that clone gets auto-memory read from, and written to, a
directory outside the repo. `git config --file` returns the path verbatim; the
`..` rejection git applies when adding a submodule does not apply to a read.

Not verified here: whether an absolute `path` or a symlinked memory directory
reaches the same outcome, and how Claude Code treats an `autoMemoryDirectory`
pointing outside the project. Check both before choosing the containment test.

### Exposure

- The per-repo copy only runs where the user already entered the repo's
  direnv, so the wider exposure is the global shim
  (`scripts/install/global-shim.sh`), which wraps every `claude` launch.
- ghmem itself is unaffected: its `.gitmodules` has `path = memory`.

### Suggested fix

Resolve `$root/$mempath` to its physical form (the shim already does
`cd … && pwd -P` for PATH entries) and inject only when the result sits under
the physical `$root`; otherwise pass through to the real `claude` without
`--settings`. Decide whether that passthrough is silent or says why — the
shim deliberately stays quiet on the common non-gitlore paths, but this one is
a refusal, not a miss.

### Constraints

- The shim header says it is "identical in both placements": change
  `scripts/install/launcher-shim` and let `emit-launcher.sh` and the global
  shim carry it. Do not patch a consumer's generated `.gitlore/bin/claude`.
- It is POSIX `sh` and runs on every `claude` invocation, including outside
  any repo; keep the cheap-checks-first ordering.
- Consumers hold a committed copy of the shim, so a fix reaches them only on
  re-install or whatever refresh path the plugin has — say which in the
  release note.

### Rejected approaches

- Patching the copy in ghmem: it would drift from the plugin's source and
  leave every other consumer exposed.
