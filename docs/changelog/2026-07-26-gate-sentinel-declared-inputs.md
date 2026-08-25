# 2026-07-26 — The gate sentinel hashes declared inputs instead of a throwaway index; `run-gate.sh` and the Makefile are both gone

The 2026-07-21 hash was built by copying the real index and running `git add -A`
into it, which takes a silent dependency on *every* path that happens to sit in
the working directory — including ones git will not index. The Claude Code
sandbox surfaces phantom home dotfiles in the working directory, and that is
enough:
`error: .bash_profile: can only add regular files, symbolic links or git-directories`,
`fatal: adding files failed`, empty hash. (This repo also had real untracked
dotfiles of the same names for a while, since cleaned with `git clean -f` — a
local coincidence, not the mechanism.) The damage is the second-order effect. An
empty hash suppresses the *record* step as well as the skip, so the gate never
skipped and never recorded: not degraded, inert, with the live sentinel stuck at
Jul 25 11:48 through three full green runs on Jul 26 and the only diagnostic on
stderr where nothing captures it. The lesson is about inferring an input set
from whatever is lying around. The gate now hashes what the caller **declares**:
`git ls-files -z --cached --others --exclude-standard` over named pathspecs,
each name followed by its contents, through `cksum`, with the versions of the
tools this repo does not pin (`bats`, `shellcheck`, `jq`) in the same stream. No
index is built, so nothing can refuse a path, and naming paths also puts a
phantom root dotfile permanently out of reach where an inferred `.` would let
the sandbox's set thrash the sentinel between sandboxed and unsandboxed runs.
This **reverses** the 2026-07-21 whole-tree call, whose fear — a forgotten input
yielding a stale green — is right, so the declaration is guarded by two
assertions rather than by hashing everything: every declared path must exist
(`git ls-files` is silent about a pathspec matching nothing, so a stale entry
silently narrows coverage), and every top-level entry must be either declared or
on a written-down exclusion list. **Two input sets, not one.**
`precommit_inputs` covers what the checks read; `evals_inputs` adds `agents`,
`commands` and `skills`, which the evals reach through the installed plugin. The
bats suites read those three as well, so the narrow set is a deliberate trade —
an agents/commands/skills-only edit keeps a green precommit green and
`plugin_distribution`'s guard does not re-run until the evals do. `memory/` and
`docs/` are out of both: no check reads either, and the parent stages memory as
a gitlink, so under the old rule every memory commit re-ran the whole ~10-minute
suite. **The gate lives in the justfile now, not a script.**
`scripts/run-gate.sh` is deleted; `check-sentinel` / `record-sentinel` /
`gate-inputs-hash` are bash functions in a `bash_prolog` variable that every
shebang recipe expands, ported from `micro/tools/ghmem`. The sentinel stays
under the gitdir (`$(git rev-parse --git-path gitlore/gates)/NAME`) rather than
ghmem's gitignored `tmp/` — a gate whose bookkeeping showed up in `git status`
would land in its own input hash. `record-sentinel` runs only after the checks
pass, and on a hash it cannot compute it removes the sentinel and says so: a
partial hash is a hash of a partial input set, and a deterministic failure would
match itself next run and skip a tree nothing checked. Each component of the
stream fails explicitly (`|| exit 1`) rather than leaning on errexit, which bash
suspends outright inside the command substitution these run in. The `Makefile`'s
five one-line targets moved into the justfile as recipes (`check-version`,
`lint`, `test`, `test-unit`, `test-integration`) — nothing there needed make's
dependency graph. Suite discovery stays a glob, never a list, pinned by driving
the real recipes with `bats` stubbed to echo its arguments and asserting the
union is exactly every `*.bats` under `tests/` — the invocation path, not a
re-implementation of the globs. 15 cases in `tests/justfile_gates.bats`, which
sources the prolog `just --evaluate` hands back and exercises it in a throwaway
repo; ten deliberate faults each turned exactly the intended assertion red.
