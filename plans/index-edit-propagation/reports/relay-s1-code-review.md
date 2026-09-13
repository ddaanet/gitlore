# GREEN code review: relay redesign, slice 1 (library)

Review of `git diff scripts/lib/index-sync.sh` — `gitlore_relay_write`,
`gitlore_relay_drain`, `gitlore_relay_sweep`, `_gitlore_sanitize_id`, the two
block readers and their comments — against
`plans/index-edit-propagation/relay-redesign.md` §Decisions, the RED /
test-review / GREEN reports, `plans/index-edit-propagation/recall-artifact.md`
and `.claude/rules/shell.md`. Ten fixes applied, all in scope. Nothing
committed, no branch touched, no formatter run, no test file edited.

Final state: `scripts/run-bats.sh tests/index_sync.bats` —
**81 passed, 3 failed**, the three expected `scripts/cc-hooks/*`-owned cases.
`just lint` — `lint-shell: 137 files clean`.

## Fixes applied

### 1. The tag was spliced into the filename unvalidated (major)

`gitlore_relay_write` put `$4` verbatim into
`gitlore-relay-$s-$a-$epoch-$pid-$tag`, where it is both a filename component
and the anchor the drain's `${rest%-*-*-*}` recovery counts back from. A tag
holding `-`, `/` or whitespace corrupts one or the other.

Fixed by validating the closed set rather than sanitizing:

```sh
case "$tag" in sync|compose) ;; *) return 1 ;; esac
```

Validation over a `[A-Za-z0-9]` sanitizer, stated in the comment:

- The tag is a caller-chosen literal, not a hook-payload field. A sanitizer
  defends against nothing reachable and silently accepts anything else.
- D51 fixes the domain at exactly two values, so the set is not an invention.
- It costs no `tr` subprocess, and it bounds the component's **length**, which a
  sanitizer does not. That bound is not hypothetical: the GREEN report measured
  the old-shape caller passing a whole `additionalContext` body as the tag and
  getting `File name too long` on stderr.
- The refusal routes through the callers' existing `if ! gitlore_relay_write …`
  "could not be staged" branch, so a caller mistake is reported rather than
  written.

Observable: case 44 in `tests/index_sync.bats` now fails at line 740 on the
retired `gitlore_relay_marker_file`, the line the RED report predicted, instead
of at 738 on a `jq` parse that the `File name too long` message was breaking.
Cases 45/46 now fail at the guard itself (`index-sync.sh:161`) on their old
4-arg call. Three failures either way; the noise is gone.

### 2. `gitlore_relay_sweep` could abort its caller (major)

`find … -delete` exits non-zero when the gitdir refuses the unlink, and the
function's own comment claimed "Always returns 0". Its caller is SessionStart,
which runs `set -euo pipefail`, so best-effort garbage collection could take a
session's whole startup hook down. Added `|| true` with the reason inline,
matching the trade `gitlore_relay_drain`'s `rm -f` already makes on the same
directory, and corrected the doc line to name both tolerated cases.

### 3. `|| true` with no stated reason (major)

The drain's `rm -f "$marker" || true` lost its justification in the rewrite.
`.claude/rules/shell.md` and the house rule both require one. Restored: it is
the gitdir's own writability, not the marker's mode, and nothing a caller
reports may die behind this call.

### 4. The whitespace-safety argument was deleted (major)

The drain enumerates correctly with `-print0` into `read -r -d ''`, then joins
basenames with newlines and re-splits them with `read -r name`. That join is
only sound because a name this library writes draws from `[A-Za-z0-9_-]` — the
sanitizer's class, a decimal epoch and pid, and now a tag from a closed set. The
old comment carried that argument; the rewrite dropped it, leaving a
newline-split with nothing stating why it is safe. Restored, with the residual
as a bound: a file some other writer put on a matching name holding a newline
splits into two names here, framing two empty blocks and removing neither.

### 5. `-type f` lost its reason (minor)

Restored one clause: anything else on a relay name is not a report, framing it
attributes a block to an agent that staged nothing, and `rm -f` cannot remove a
directory, so every later run would frame it again.

### 6. The file format went undocumented (major)

The rewritten header documents the *name* in detail and dropped the *content*
format together with the no-delimiter-in-a-body contract. That contract is still
the whole protection against a mis-split — a body holding a delimiter line makes
the drain attribute its tail to the wrong channel, silently. Restored compactly
above the writer.

### 7. Comments cited `plans/` and a slice id (minor)

`gitlore_relay_write`'s header cited
`plans/index-edit-propagation/relay-redesign.md`; both `${N:-}` notes argued
from "slice 2 still calls this with the OLD 4-arg shape". Replaced with durable
statements of what is genuinely optional: an absent session is the same case as
an empty one, either body is legitimately empty on its own (the sync hook's
`failed` branch reports a sysmsg and no ctx), and an absent agent or tag is
refused by the guards — which report through the caller's channel, where
`set -u` would instead abort the whole hook. Nothing now names a plan, a slice
or a line number, and nothing frames itself against a previous version.

### 8. The `pid` comment sat above the wrong line (minor)

It explained the bare assignment while sitting above `epoch=$(date +%s)`. Moved
above `pid=${BASHPID:-$$}`.

### 9. The agent-recovery comment understated its own guarantee (minor)

It asserted the strip is unambiguous "even when A contains a dash" without
saying why a dashed *session* id is also safe. Now states that S is removed by
length as a literal prefix rather than by pattern, and grounds the dash-free
tail in two decimals plus the tag guard from fix 1.

### 10. `_gitlore_relay_sysblock`'s header said "both call sites" without saying whose (minor)

Now names the drain's two `|| …=""` sites, and states the degrade-don't-abort
trade: under a caller's errexit the alternative is aborting the hook before it
emits any JSON, losing that run's own report to save nothing.

## Verified against the brief, no change needed

- **errexit / condition context.** Both call sites are
  `if ! gitlore_relay_write …`. Every failure path in the writer returns
  non-zero itself: the agent guard, the tag guard, `date`, `rev-parse`, the
  redirection, the occupied-destination refusal. `mv` is the tail command, so
  its status is the return.
- **Directory-squat trap.** `[ -e "$dest" ]` before `mv` is present and removes
  the temp. `-e` rather than `-d` also refuses overwriting an existing report,
  which D51 requires. POSIX `mv` into an existing directory succeeds with exit
  0, so the check, not `mv`, is what stops it.
- **Agent-id recovery.** `<epoch>` is decimal from `date +%s`, `<pid>` decimal,
  `<H>` dash-free by construction after fix 1 — so exactly three trailing
  dash-free fields. A session id containing `-` (a UUID does) survives because
  `${name#"$prefix"}` strips S as a known literal. Mutation-probed in place:
  replacing `${rest%-*-*-*}` with `${rest%%-*}` reds case 1 at
  `tests/index_sync.bats:976` (its agent id is `a-1`). Suite restored from a
  saved copy afterwards and re-run clean; tests were never moved.
- **Drain contract.** Always returns 0. Removes exactly `$gitdir/$name` for each
  name it enumerated, and nothing else — the old blanket `.tmp` removal is gone.
  Both out-variables are set empty before either early return. Framing is
  `--- gitlore-relay agent <A> ---` on both channels, unchanged.
- **Sweep contract.** `-type f -name 'gitlore-relay-*' -mtime +7 -delete`
  includes temps, filters on nothing but the name and the age, returns 0 on a
  missing gitdir via the `rev-parse` and `[ -d ]` guards. Same shape as
  `_gitlore_nudge_reset`, as its comment claims.
- **Shell rules.** No `2>/dev/null` added. No `ls`. No bare `read` on a
  human-written file — the two `read` loops consume `find -print0` and a
  generated stream that is always newline-terminated. NUL delimiters on the one
  enumeration that crosses the unsanitized gitdir prefix.
- **Portability.** No arrays, no `${var,,}`; `${BASHPID:-$$}`; `case` rather
  than `[[ =~ ]]`. Every `find` predicate used is BSD/bfs-safe, and
  `-mtime +7 -delete`, `date +%s` and `mv` behave identically on all three.
- **Residuals stated as bounds.** Same-second same-process collision, the
  stranded temp collected only at 7 days, the drain's `.tmp` exclusion, and now
  the newline-in-a-foreign-name bound from fix 4.
- **Dead code.** `_gitlore_relay_stub_file` gone. `gitlore_relay_marker_file`
  gone with no caller left outside `tests/index_sync.bats:740,758,803` and
  `tests/cc_hook_*.bats`, all of which slice 2 owns. `_gitlore_relay_sysblock` /
  `_gitlore_relay_ctxblock` are still the drain's two channel readers and stay.
- **Stale premises.** Grepped the file for `sequential`, `merge`, `merged into`
  — nothing left arguing sequential hooks or per-agent merging.

## Flagged, not fixed

- **The tag guard ships untested.** No case passes a tag outside the set, so
  nothing binds the closed set or the refusal. Tests are out of scope for this
  pass; one case asserting that `gitlore_relay_write mem s1 a1 bogus S C`
  returns non-zero and leaves no file belongs in slice 2 or a follow-up.
- **`_gitlore_nudge_reset` has the exposure fix 2 removed.** Its
  `find … -mtime +7 -delete` is unguarded and it is called from the same errexit
  hook. Out of scope, untouched.
- **`scripts/lib/index-sync.sh` is 470 lines** against the 400 soft cap. This
  change brought it down from 513; the review adds ~40 comment lines back for
  fixes 3, 4, 5 and 6. A split is ruled out for this pass.
- **D51's own sweep sentence still reads both ways.** It names the sweep as
  `gitlore-relay-*` "temps included" while the same decision says `.tmp` is
  excluded from every enumeration. The code implements the two-rule reading
  (drain excludes, sweep includes), the comment states it, and the tests lock it
  in. The RED test review raised the same point; the design text is slice 3.

## Checks run

| check | result |
| --- | --- |
| `scripts/run-bats.sh tests/index_sync.bats` | 81 passed, 3 failed (expected) |
| `just lint` | `lint-shell: 137 files clean` |
| `shellcheck scripts/lib/index-sync.sh` | clean |
| `bash -n scripts/lib/index-sync.sh` | OK |
| `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats` | 39 passed, 10 failed — identical to the pre-review baseline |

The three expected failures are cases 44, 45 and 46: case 44 on the retired
`gitlore_relay_marker_file`, cases 45 and 46 on their old 4-arg
`gitlore_relay_write` call meeting the new tag guard. All three drive
`scripts/cc-hooks/index-sync-post.sh`.

The hook-suite run is not part of the slice's gate; it was taken before and
after to prove the tag guard regressed nothing in the suites slice 2 owns.
`git diff --stat` still names only `scripts/lib/index-sync.sh` and
`tests/index_sync.bats`, the latter untouched by this review.
