# Item 3.1 slice 4 — RED

Six cases, three test files. Scope held to `tests/index_sync.bats`,
`tests/cc_hook_index_compose.bats`, `tests/cc_hook_session_start.bats` and this
report. No SUT file is left modified — every mutation used for a Group B proof
was applied in place and restored; `git status --porcelain` on `scripts/` is
empty throughout, and each restoration was re-confirmed with `git diff --stat`
after `git checkout --`.

## Group A — expected red against the committed tree

### 1. `a failed relay write leaves the subagent's own report intact`

`tests/cc_hook_index_compose.bats`. Induced with
`mkdir "$(gitlore_relay_marker_file memory a1)"` before a keyed compose run over
a real index edit (F5 in `item-3-1-s2-code-review.md`).

```
not ok 1 a failed relay write leaves the subagent's own report intact
# (in test file tests/cc_hook_index_compose.bats, line 428)
#   `[ "$status" -eq 0 ]' failed
```

Died on `[ "$status" -eq 0 ]` for the keyed `feed a1` call: today the hook exits
1 with empty stdout (matching F5's own hand-run transcript), so the compose
report never reaches the assertion that would check it.

### 2. `relay_write refuses an empty agent id and a squatted marker path`

`tests/index_sync.bats`. Two sub-cases in one body, in the order the runbook
names them.

```
not ok 1 relay_write refuses an empty agent id and a squatted marker path
# (in test file tests/index_sync.bats, line 1096)
#   `[ "$status" -ne 0 ]' failed
```

Died on the empty-agent-id half's first assertion (line 1096,
`[ "$status" -ne 0 ]` right after `run gitlore_relay_write memory "" "S" "C"`):
the guard does not exist yet, so the write currently succeeds and lands on the
bare, unsuffixed `gitlore-relay` marker — a file `gitlore_relay_drain`'s own
`-name 'gitlore-relay-*'` glob never matches, so nothing ever folds or removes
it. The squatted-path half (a `mkdir` on the keyed name, then a write) is not
reached by this run — confirmed separately by isolating just that half (see
non-vacuity below): it already passes today, per F5's own mechanism.

### 3. `an unreadable marker costs the relay, not the hook` (library half)

`tests/index_sync.bats`. A marker written normally, then `chmod 0200`, then a
synthetic caller —
`bash -c 'set -euo pipefail; . "$SRC"; gitlore_relay_drain "$mempath"; printf "OWN REPORT\n"'`
— reproducing the shape a real hook uses (bare call under `set -euo pipefail`),
run through bats' `run` at the *outer* `bash -c` level only, so the inner
script's own errexit is what is under test, not bats'.

```
not ok 1 an unreadable marker costs the relay, not the hook
# (in test file tests/index_sync.bats, line 1175)
#   `[ "$status" -eq 0 ]' failed
```

Died on `[ "$status" -eq 0 ]`: `find -type f` matches the mode-0200 regular
file, `_gitlore_relay_sysblock`'s `awk` then exits on the open failure
(permission denied), and under the synthetic caller's `set -euo pipefail` that
takes the whole script down before `printf "OWN REPORT\n"` runs.
`[[ "$output" == *"OWN REPORT"* ]]` was never reached — confirmed by moving the
"$status" check to a fresh isolated run and observing `$output` is empty (no
"OWN REPORT" anywhere), so the death is genuinely upstream of both assertions,
not a coincidence of ordering.

## Group B — born green, redded by mutation

Each mutation was applied to the working-tree SUT with `Edit`/`sed`, the target
case run with `bats -f "<name>" <file>` to isolate it, then restored with
`git checkout -- <file>` and reconfirmed both by `git diff --stat` (empty) and
by rerunning the same case green.

### 4. `an unkeyed run survives a non-file squatting on a marker name`

`tests/cc_hook_index_compose.bats`. Cannot red by absence:
`gitlore_relay_drain`'s `-type f` (slice 1, committed) already skips the
`mkdir`-squatted marker name before the compose hook's own `awk`/`rm` would
reach it (F6).

**Mutation** — `scripts/lib/index-sync.sh`, the drain's enumeration:

```diff
-  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' -print0)
+  done < <(find "$gitdir" -maxdepth 1 -name 'gitlore-relay-*' -print0)
```

```
not ok 1 an unkeyed run survives a non-file squatting on a marker name
# (in test file tests/cc_hook_index_compose.bats, line 447)
#   `[ "$status" -eq 0 ]' failed
```

Restored; `git diff --stat scripts/lib/index-sync.sh` empty; case rerun green.

### 5. `relay_write joins a channel only when the old body is non-empty`

`tests/index_sync.bats`. The slice 2.5 review fixed this and could not pin it —
no frozen case writes an empty ctx before this slice.

**Mutation** — `scripts/lib/index-sync.sh`, the ctx join guard specifically (the
sysmsg guard is left untouched, since only the ctx guard is what this case
exercises):

```diff
-    if [ -n "$old_ctx" ]; then ctx="$old_ctx
-$ctx"; fi
+    ctx="$old_ctx
+$ctx"
   fi
```

```
not ok 1 relay_write joins a channel only when the old body is non-empty
# (in test file tests/index_sync.bats, line 1140)
#   `[ "$GITLORE_RELAY_CTX" = '--- gitlore-relay agent a1 ---' failed
```

The unguarded join opens the ctx channel with a leading blank line
(`"" + "\n" + "C2"`), which the exact-block assertion catches and a substring
check on `"C2"` alone would not. Restored; `git diff --stat` empty; case rerun
green.

### 6. `an unreadable marker costs the relay, not the hook` (SessionStart half)

`tests/cc_hook_session_start.bats`. Same mode-0200 fixture as case 3, driven
through the real hook. The fix already in the tree —
`gitlore_relay_drain "$mempath" || true` — suspends errexit for the whole drain
call (per the codebase's own comment on that line), so today the hook already
survives and reports; this case pins that survival plus the residual the fix
does not restore: the standing FR11 commit-protocol text (checked via
`additionalContext | test("never commit"; "i")`, the idiom the file's own "emits
standing commit-protocol additionalContext" case already uses).

**Mutation** — `scripts/cc-hooks/session-start.sh`:

```diff
-gitlore_relay_drain "$mempath" || true
+gitlore_relay_drain "$mempath"
```

```
not ok 1 an unreadable marker costs the relay, not the hook
# (in test file tests/cc_hook_session_start.bats, line 431)
#   `[ "$status" -eq 0 ]' failed
```

Restored; `git diff --stat scripts/cc-hooks/session-start.sh` empty; case rerun
green.

## Non-vacuity notes

- Case 2's squatted-marker half was run alone (`bats -f` plus a body edited to
  drop the empty-id lines during the check, discarded afterward) and confirmed
  green today, so the combined case's red is attributable specifically to the
  empty-agent-id sub-case and not a fixture problem shared by both halves.
- Case 3's death point was confirmed upstream of both its assertions (see above)
  rather than assumed from the mutation table in `item-3-1-s2-code-review.md`
  alone.
- Cases 4–6 each redded on a mutation that changes exactly one documented fix
  and nothing else nearby (the sysmsg join guard in case 5, the SessionStart
  `|| true` in case 6, the compose-side `-type f` in case 4 — none of the three
  touched more than the single line the runbook names), and each restoration was
  verified structurally (`git diff --stat`), not merely by the case going green
  again.
- No test in this slice asserts against a trailing glob or a value computed by
  the function under test: case 5's expected block is a literal written out by
  hand; cases 1/4's `recomposed tier pointers` literal is the same fixed string
  every other case in the file already pins; case 6's `additionalContext` is
  checked non-null implicitly by the positive `test(...)` match itself
  succeeding (a `null` channel fails `jq -e` outright, matching the existing
  suite's own `[ "$ctx" != "null" ]` idiom used elsewhere in this file for the
  same reason).

## Checks that passed, by name

- `./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats`
  — 127 passed, 3 failed (the three Group A cases), against the unmodified tree.
- `shellcheck -s bash tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats`
  — clean.
- `./scripts/lint-shell.sh` — 137 files clean.
- `git status --porcelain` — only the three test files modified; no stray files
  or directories in the repo working tree.
- `git diff --stat scripts/` — empty after every Group B mutation-restore cycle.
