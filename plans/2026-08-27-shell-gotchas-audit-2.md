# shell-gotchas audit 2 — gitlore, files unchanged since v0.5.0

Scope: every shell file (`.sh`/`.bash`/`.bats`, plus shebang-discovered hooks
and the launcher shim) that `git diff --name-only v0.5.0..HEAD` does not list —
84 files, 6925 lines — each read whole. The first pass
(`2026-08-27-shell-gotchas-audit.md`) covered the changed files; this one adds
macOS as a hard requirement: bash 3.2, BSD `sed`/`find`/`stat`/`paste`/`wc`/
`mktemp`, no `timeout(1)`. `plugin-dev/**` is vendored and out of scope.

`shellcheck 0.10.0 -x` is clean on all 83 files it was run on (`.gitlore/bin/
claude` and `scripts/install/launcher-shim` also clean under `-s sh`), and
`--enable=all -S warning` adds nothing on the runtime scripts. No finding below
is one shellcheck reports.

Counts: **1 BLOCK, 3 WARN, 4 NIT** in the files I read directly, plus
**0 BLOCK, 8 WARN, 12 NIT** from a delegated pass over the `.bats` suites and
eval scripts (last section), each verified against its source before being
applied.

Bash for every probe: GNU bash 5.2.37 on Linux, GNU sed 4.9. BSD behaviour is
cited from source or man page where named; the lock-in tests reproduce it with
PATH-shadowing stubs (`tests/helpers/bsd-stubs.bash`), per the skill's
"Locking In a Portability Fix".

---

## BLOCK

### B1 — `tests/helpers/fixtures.bash:53`: `sed -i` with no extension breaks every fixture-backed test on macOS

```sh
  sed -i "s/${old_esc}/${new_esc}/g" "$file"
```

Gotcha: **BSD `sed -i` requires an extension argument** (portability catalog,
`sed`). BSD sed reads `s/…/g` as the backup extension and `$file` as the
script; GNU sed only accepts the extension attached. There is no `-i` spelling
both run.

Why it bites: `_gitlore_sed_replace_path` is how `make_parent_with_memory`
repoints the cached template's absolute paths at the test's own `$TMP_REPO` —
`.gitmodules`, `.git/config`, the module store's `config`, the submodule
gitfile. It runs in every test that builds the parent+memory fixture, which is
most of the suite. On a Mac the whole suite is red before any assertion runs.

Verified: with a stub that enforces the BSD contract on `PATH`,
`make_parent_with_memory` fails at line 53; after the fix it succeeds and no
copied file still names the template directory.

Fix: `sed "s/…/g" "$file" > "$file.tmp" && mv -f "$file.tmp" "$file"`. Lock-in:
`tests/bsd_portability.bats` "fixture path rewrite survives BSD sed".

---

## WARN

### W1 — `scripts/run-bats.sh:12`: `mktemp` template with the `X`s not trailing — `just test` fails on its second run on macOS

```sh
log="$(mktemp "${TMPDIR:-/tmp}/gitlore-bats-XXXXXX.log")"
```

Gotcha: **BSD `mktemp` randomises only a trailing run of `X`s** (portability
catalog, `mktemp`). Apple Libc's `find_temp_path` walks back from the end of
the template replacing `X`s, has no minimum-`X` check, and then opens whatever
is left with `O_EXCL`. With `.log` last, nothing is replaced: the first run
creates `/tmp/gitlore-bats-XXXXXX.log` literally, the second gets `EEXIST`,
`mktemp` exits 1, and `set -e` ends the wrapper before `bats` runs. GNU
`mktemp` accepts a suffix after the `X`s, so Linux never sees it.

Verified: Apple Libc source (`stdio/FreeBSD/mktemp.c`, `find_temp_path`); a
stub reproducing that behaviour makes the second `run-bats.sh` invocation exit
non-zero, and the fixed template passes twice.

Fix: `gitlore-bats.XXXXXX` (drop the suffix). Lock-in:
`tests/bsd_portability.bats` "run-bats.sh log file survives BSD mktemp on a
second run".

### W2 — `scripts/commit-memory.sh:30-34`: `-m` or `-F` with no operand exits 1 with no message

```sh
    -m)
      summary="${2-}"; have_summary=1; shift 2 ;;
```

Gotcha: **silent failure path under `set -e`** (SKILL rule 3). `shift 2` with
one argument left returns 1 and prints nothing; errexit ends the script there.
`commit-memory.sh -m` — the shape an agent produces when it drops the summary —
therefore fails with an empty stderr and exit 1, the same exit the "memory is
dirty, needs a summary" path uses with a message. The `-F` arm is worse:
`cat ""` first prints its own error, then the same silent shift.

Verified: `bash -c 'set -euo pipefail; … -m) summary="${2-}"; shift 2 …' _ -m`
→ rc=1, no output.

Fix: check `$# -ge 2` in both arms and route to the existing usage message
(exit 2). Lock-in: `tests/commit_memory.bats` "-m with no summary operand is a
usage error".

### W3 — `scripts/lint-shell.sh:14`: `\b` in `grep -E` — shebang discovery finds nothing on macOS

```sh
  head -1 "$1" | grep -qE '^#!.*\b(ba)?sh\b'
```

Gotcha: **GNU-only regex escape** (portability catalog, `grep`). `\b` is a
GNU extension; BSD grep's ERE has no word boundary and spells the nearest
thing `[[:<:]]`/`[[:>:]]` — the repo already records this at
`docs/references/index-authoring-sync.md:116`, which is why the index-sync
token check is word-at-a-time awk rather than one ERE.

Why it bites: an ERE that does not match is not an error, so on a Mac
`is_shell_shebang` is quietly false for every extensionless file — the three
git hooks, `launcher-shim` and `.gitlore/bin/claude` drop out of `just lint`,
while the `.sh`/`.bats` files keep it green. Silent coverage loss, in the gate
that guards the hook scripts.

Verified: with a BSD-strict `grep` stub that refuses `\b` (as the platform
would fail to honour it), `lint-shell.sh` reports "no shell files discovered"
on a repo whose only shell file is an extensionless hook; the rewritten
pattern finds and lints it. Not run on a Mac.

Fix: `'^#!.*(/|[[:blank:]])(ba)?sh([[:blank:]]|$)'` — POSIX classes only.
Lock-in: `tests/bsd_portability.bats` "lint-shell.sh shebang discovery
survives BSD grep".

---

## NIT

- **`tests/cc_hook_index_compose.bats:104`** —
  `sed -i'' -e '$a\…' memory/MEMORY.md`. The shell strips `''`, so BSD sed sees
  a bare `-i` and takes `-e` as the backup extension: the edit still lands, but
  `memory/MEMORY.md-e` appears inside the memory store the test then composes.
  The test only wanted to append a line; `printf '%s\n' '…' >> memory/MEMORY.md`
  does that on both platforms. Applied.
- **`scripts/install/write-settings.sh:11-15` and
  `scripts/install/emit-launcher.sh:20-22`** — `tmp=$(mktemp)` … `mv "$tmp"
  target`. `mktemp` creates 0600 and `mv` carries the mode, so an existing
  `.claude/settings.json` or `.envrc` at 0644 comes out 0600 (verified:
  `mktemp` → 600, `mv` onto a 644 file → 600). Cosmetic for single-user files,
  and the fix is one line: capture the rewritten content in a variable and
  `printf` it over the original, which keeps the inode and its mode. Applied,
  pinned in `tests/write_settings.bats` and `tests/emit_launcher.bats`.
- **`scripts/install/write-settings.sh:28`** —
  `grep -qx '.claude/settings.local.json' .gitignore`: the leading `.` is a
  regex any-char, so a line `Xclaude/settings.local.json` counts as present and
  the real entry is never added. `-F`. Applied, pinned in
  `tests/write_settings.bats`.
- **`.gitlore/bin/claude` vs `scripts/install/launcher-shim`** — both headers
  say "identical in both placements", and `emit-launcher.sh` `cp`s one to the
  other, but the committed dogfood copy lagged the source by one edit
  (`65ce790` dropped a `2>/dev/null` and added the redirect rationale in the
  source only; `cmp` differs at byte 1341). The lagging copy still worked —
  `git config --file <missing>` is silent on absence (verified rc=1, no
  stderr), so the removed redirect hid nothing and its absence prints
  nothing. Re-copied, and `tests/plugin_distribution.bats` now `cmp`s the
  shipped copy against the source; `emit_launcher.bats:12` only ever diffed a
  fresh emission.

---

## Clean

The runtime scripts read whole and found portable-correct as written:
`scripts/cc-hooks/{add-tier-batch,index-compose,index-sync-pre,memory-commit-batch,nudge-reset,plugin-upgrade-batch,post-tool-use,worktree-drift,worktree-remove}.sh`,
`scripts/git-hooks/{pre-commit,pre-push,memory-pre-commit}`,
`scripts/hook-manager/{detect,wire-husky,wire-lefthook,wire-manual,wire-overcommit}.sh`,
`scripts/install/{create-remote,global-shim,preflight}.sh`,
`scripts/{emit-memory-gate,emit-wrappers,merge-memory}.sh`,
`scripts/lib/log.sh`, and the test helpers `setup.bash`, `triggers.bash`,
`gh-mock.bash`, `divergence-fixtures.bash`, `stub-synth.bash`, plus
`tests/evals/lib/{setup,claude-runner,judge}.sh` and `tests/evals/run-evals.sh`.

Shapes I suspected and cleared, so they do not get re-raised:

- `paste -sd: -` in both shims already carries the explicit stdin operand
  (and `tests/launcher_shim.bats` pins it with a BSD-strict stub — the model
  for the new stubs).
- `mktemp "${TMPDIR:-/tmp}/name.XXXXXX"` at `plugin-upgrade-batch.sh:68` and
  every helper: `X`s trailing, portable. Bare `mktemp`/`mktemp -d` also fine.
- `[ a -ef b ]` (`index-sync-pre.sh:35`), `cp -a` (`fixtures.bash:28`),
  `sleep 0.05`, `seq`, `find … -print -quit`, `grep -m1`, `awk -F'\t'`,
  `tail -c1`, `head -1`, `dirname --`/`basename --`: all present on macOS.
- `wc -l | tr -d ' '` at `tests/evals/asserts/memory-commit.sh:43` has the
  BSD-padding guard.
- `scripts/emit-memory-gate.sh:51-63` reads from `< <(gitlore_tier_paths …)`,
  where a producer failure would be lost — but `gitlore_tier_paths` ends in
  `return 0` unconditionally, so there is no status to lose.
- `scripts/commit-memory.sh:64` `exit $?` after a top-level call under `set -e`
  is inert (errexit already took the failure), not wrong.
- `scripts/git-hooks/pre-push:45-46`: `$(git rev-parse "HEAD:$mempath")` failing
  inside the `if !` condition is exempt from errexit and lands in the "warn"
  branch — the documented intent for an unanswerable check.
- `scripts/lib/log.sh`, `scripts/hook-manager/wire-manual.sh`,
  `scripts/install/preflight.sh`: fixed-string `echo`/heredocs only.
- Every
  `PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(git config gitlore.hooksDir)/../..}"`
  would exit 1 silently when `gitlore.hooksDir` is unset — but every caller (the
  emitted wrappers, `gitlore.commitCommand`/`mergeCommand` discovery) only
  reaches these scripts when that key is set. Not a live path.


---

## Delegated pass: `.bats` suites and eval scripts

An Opus subagent read the 42 `.bats` and `tests/evals/{asserts,setups}` files
whole against the same skill and reference set, with the three findings above
that touch tests excluded. It found no GNU-only flag, no bash-4 construct and
no `mktemp` template with the `X`s misplaced in any of them, and confirmed the
`launcher_shim.bats` BSD-`paste` stub and the `wc -l | tr -d ' '` guard as the
portable shapes they are. Its WARNs are all the `set -e`/`pipefail` honesty
class, verified on this box; the trigger for the two `pipefail` ones is a
producer over the 64 KiB pipe buffer, which no current fixture reaches — they
are applied because the first audit's W3 already treats that shape as a defect
in `scripts/`, and the tests should not carry what the code refuses.

Applied (WARN):

- **`tests/evals/asserts/recall.sh:32,39,44`** — `… | grep -m1 … | cut -f1) ||
  var=` under `set -o pipefail`: once `$tools` exceeds the pipe buffer the
  producer dies of SIGPIPE on a *successful* match, and the fallback erases the
  answer `cut` already printed (reproduced: `probe_at=[]`, a false "the agent
  never ran the probe"). Now one `awk` per lookup — no early-exit consumer, no
  fallback needed.
- **12 sites — `… | grep -q` as a bare assertion under `pipefail`**
  (`cc_hook_worktree_remove.bats:36,63`,
  `plugin_distribution.bats:40,42,82,85,99,116`, `tier_discovery.bats:51`,
  `tier_lockstep.bats:55,143,161`): the same SIGPIPE shape, where a match large
  enough to trip it fails the test *because* the assertion held (probed:
  rc=141). Replaced with `[[ "$(…)" == *pat* ]]` on the captured output, or
  `grep -q … <<<"$fm"` where the text was already in a variable.
- **`tests/evals/setups/mounted-tier.sh:14`** — `$(cd "$(dirname
  "${BASH_SOURCE[0]}")" && pwd)` with `CDPATH` unhandled: a relative invocation
  (`bash setups/mounted-tier.sh`, or `SETUPS_DIR` overridden via
  `run-evals.sh:22`) makes `cd` echo, and `SETUPS_DIR` becomes a two-line path
  into the wrong tree (reproduced). `unset CDPATH`, as every other
  self-locating script here does.
- **14 sites — a temp tree outside `$TMP_REPO` removed only on the success
  path** (`"$TMP_REPO-wt"`, `"$TMP_REPO-clone"`, `"$TMP_REPO-other"` and
  independent `mktemp -d`s across `cc_hook_memory_commit_batch`,
  `cc_hook_worktree_drift`, `commit_memory`, `emit_memory_gate`,
  `emit_wrappers`, `integration_clone_restore`, `pre_push_hook`, `push_memory`,
  `push_rejection_discriminator`, `tier_discovery`): the trailing `rm -rf` is
  skipped by errexit the moment an assertion fails, so every red run leaks a
  worktree into `$TMPDIR`. Each now sets `WT`/`CLONE`/`OTHER` and `teardown()`
  removes it — the shape `cc_hook_worktree_drift.bats` already had.
- **`tests/resolve_both_flavors.bats:24`** — `[[ … == *healthy* ]] || [[ -z
  "$stderr" ]]`: the second arm is dead today (`resolve.sh:348` prints the line
  to stderr) and is a standing escape hatch — the day resolve goes silent on a
  healthy store the test keeps passing on `status` alone. Now the one
  assertion.
- **16 sites — `>/dev/null 2>&1` on `git worktree add -q` / `submodule update`
  / `submodule deinit` fixture commands**: `-q` already quiets the normal
  chatter, so the `2>&1` only hid the failure (a stale `.git/worktrees/` entry
  from a leaked run — which the previous item arms — or a branch collision),
  and the test then died one line later on a bare `[ -e … ]`. Dropped the
  `2>&1`; `push_memory.bats:55` already ran it that way.
- **`pre_push_hook.bats:50`, `push_memory.bats:158`,
  `resolve_merge_remote.bats:66`** — `cd "$(mktemp -d …)"`: a failing `mktemp`
  yields `cd ""`, which succeeds without moving (verified rc=0), and the
  subshell then clones into whatever directory it was in. Split into
  `dir=$(mktemp -d …) || exit 1; cd "$dir" || exit 1`, the form
  `divergence-fixtures.bash:53` already uses.
- **`tests/evals/asserts/tier-write.sh:26-33`** — `done < <(find …)`: a failing
  `find` is invisible and reads as "no new file", i.e. the agent is blamed for
  a broken fixture. The list is captured first, with `|| fail`.

Applied (NIT): `run !` → `run -1` on the two `grep -qF` negatives in
`cc_hook_index_compose.bats` (grep's exit 2 on a missing file satisfied the old
form); `[ "$status" -eq 0 ]` added to the six `hook_manager_detect.bats` tests
and the fish case in `global_shim.bats`; `emit_memory_gate.bats:25`'s
`( cd … && run …; [ "$status" … ] || exit 1 )` rewritten as a plain `run bash
-c 'cd "$1" && bash "$2"' _ …`, and `push_memory.bats:56`'s `bash -c "cd '$WT'
…"` given positional arguments instead of quote interpolation;
`install_remote.bats:76-77` now fails loudly when a tool on its allowlist is
absent instead of silently omitting it; the two `2>/dev/null` on `git config
--get`/`--unset` (`emit_memory_gate.bats:41`, `install_remote.bats:25`)
dropped, since both are silent on a missing key; `tier-remote.sh` cleans its
seed dir from an `EXIT` trap.

Not applied, on the record:

- `echo "$output"` on hook JSON (30 sites) — implementation-defined by POSIX,
  inert under bash on both platforms (`xpg_echo` off); not worth a 30-line
  churn.
- `unset NAME` without `-v` (4 sites) — no function shares any of the names.
- `pre_push_hook.bats:18` `git -C memory remote remove origin 2>/dev/null ||
  true` — grouped by the subagent with the silent `git config` misses, but
  `remote remove` *does* print `error: No such remote` on its expected miss, so
  that redirect is scoped to a real message and stays.
- `integration_replay_guard.bats:82` — `GIT_SEQUENCE_EDITOR` is
  shell-evaluated by git, so a `$TMPDIR` with a space or quote would break it;
  neither platform's default `TMPDIR` has one.
- `plugin_distribution.bats:181-182` — `grep -n … | cut` would hand `[ -lt ]`
  two lines if `hooks.json` ever registered a hook twice; the failure is loud
  (`integer expression expected`), just mislabelled.
