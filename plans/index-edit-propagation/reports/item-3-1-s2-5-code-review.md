# Item 3.1 slice 2.5 — code review (GREEN phase)

The merge is correct: it preserves write order, keeps both channels separate,
reads before the redirect opens, and is associative over three or more writes.
Every mutation the dispatch named reds at least one case, including the two the
GREEN report's central claims rest on (the truncate-before-read race, and the
fresh-marker byte identity).

Three fixes applied, all inside `scripts/lib/index-sync.sh`:

1. The duplicated `awk` split is extracted to `_gitlore_relay_sysblock` /
   `_gitlore_relay_ctxblock`, used by both `gitlore_relay_write` and
   `gitlore_relay_drain`.
2. The merge joins a channel only when the old body is non-empty. An empty
   existing ctx channel — reachable, see §2 — merged to a leading blank line.
3. An unreadable-but-present marker no longer kills the calling hook. This is a
   failure mode the slice introduced; the `[ -f ]` guard does not cover it.

One thing is flagged and not fixed (§7): `gitlore_relay_drain` has the same
unreadable-marker hole, in committed code outside this slice.

## 1. The duplicated split — extracted

Extracted. Two call sites is normally below the threshold, but three things
put this one over it.

- The coupling is silent both ways. The format carries no version marker, so a
  delimiter edited on one side alone does not fail — it mis-splits and
  attributes a body to the wrong channel, which is the exact failure the
  function's own header comment already calls out as "silently, so the
  guarantee is the whole protection".
- The file has the precedent. `_gitlore_agent_suffix` is extracted for the same
  reason — three sibling `*_file` helpers that must agree on one string — and
  is defined after its users, which is where these two go (immediately after
  `gitlore_relay_drain`, the second of their two users).
- The extraction is where the non-obvious property of the parser can be
  written down, and it turns out to be load-bearing. See below.

Two printing functions, one per channel, rather than one function setting two
variables: bash 3.2 has no namerefs, so a two-variable helper has to publish
fixed names, and `gitlore_relay_drain`'s `local sysblock ctxblock` would have
had to change with it. Printers keep both call sites' local names and let the
exit status propagate through the command substitution, which is what §3's fix
needs.

**Not one parameterised program**, and this is the finding the extraction
surfaced. The two `awk` programs are asymmetric: the sysmsg reader resets on a
second ctx delimiter, the ctx reader does not reset on a second sysmsg one.
Folding them into

```awk
/^--- gitlore-relay-sysmsg ---$/ { f = (ch == "sysmsg"); next }
/^--- gitlore-relay-ctx ---$/    { f = (ch == "ctx");    next }
f
```

is behaviour-identical on well-formed markers and looks like the obvious
cleanup. Measured (mutation NG below): it passes both suites entire on its own,
**and it makes the naive-append shape undetectable** — with the symmetric
parser plus a `>>` write, both suites pass 101/0, where the asymmetric parser
reds `tests/index_sync.bats:1031`. The asymmetry is what keeps a marker
carrying a second delimiter pair visible instead of folding it away. That is
now stated in the helpers' comment, so the next reader does not "simplify" it.

## 2. The empty existing channel — reachable, fixed

Traced rather than assumed, and confirmed by hand-run.

Both hooks guard on a non-empty sysmsg before calling `gitlore_relay_write`
(`scripts/cc-hooks/index-sync-post.sh:258`, `scripts/cc-hooks/index-compose.sh:83`),
so the **sysmsg** channel can never be empty on disk and never grows a leading
newline. The **ctx** channel has no such guard, and one branch sets a sysmsg
with no ctx: `index-sync-post.sh`'s `failed` block (`:234`) appends only to
`$sysmsg`, deliberately — the comment above the relay call says "every block
above that sets a ctx sets a sysmsg with it", which is true in one direction
only.

So the reachable case is: a batch in a subagent where the frontmatter sync
*fails* (permissions) and nothing else reports, followed by `index-compose.sh`
in the same `PostToolBatch`. Measured before the fix:

```
--- gitlore-relay-ctx ---
                          <- blank line from the empty first body
COMPOSE-CTX
```

and the parent's `additionalContext` block became `--- gitlore-relay agent a1
---`, a blank line, then the body.

It matters little — a stray blank line in the model's channel — but the fix
removes nothing and matches how `index-sync-post.sh` already joins its own
blocks (`if [ -n "$sysmsg" ]; then sysmsg="$sysmsg\n"; fi`). Applied:

```bash
if [ -n "$old_sys" ]; then sysmsg="$old_sys
$sysmsg"; fi
if [ -n "$old_ctx" ]; then ctx="$old_ctx
$ctx"; fi
```

Verified after the fix: the merged ctx is `COMPOSE-CTX` with no leading blank
line, and the sysmsg channel is unchanged (`SYNC-FAILED\nCOMPOSE`).

The mirror case — a non-empty old ctx merged with an empty new one — leaves a
*trailing* blank line, which `$( )` strips at drain time. Left as is; guarding
it too would add a branch for something unobservable.

**This fix is not covered by the frozen suite.** No case writes an empty ctx.
Both frozen cases pass unchanged because their old bodies are non-empty.

## 3. Three or more writes — associative, no accumulation

Checked by hand-run, since no test covers it. Three writes of `S1/C1`, `S2/C2`,
`S3/C3` under one agent id give exactly:

```
--- gitlore-relay-sysmsg ---
S1
S2
S3
--- gitlore-relay-ctx ---
C1
C2
C3
```

and drain to `S1\nS2\nS3` / `C1\nC2\nC3` under one framing line. No blank-line
accumulation, no re-split. The merge is associative.

The degenerate case is bounded too: three successive writes with an empty ctx
each leave the ctx section at one blank line, not three, because `$( )` strips
trailing newlines on each read. (Before §2's fix it stabilised at two; either
way it does not grow without bound.)

## 4. Mutation round

Every row is a full run of both suites against an **in-place** mutated
`scripts/lib/index-sync.sh`, restored after. The M-rows are against the SUT as
the GREEN phase submitted it; the N-rows re-measure the same shapes against the
refactored SUT, so the extraction is not taking the coverage on trust.
"case 1" is `relay_write merges a second report into an existing marker`;
"case 2" is `both PostToolBatch hooks in one keyed batch reach the parent`.

| id | shape | result |
|---|---|---|
| — | GREEN as submitted (baseline) | 101 passed, 0 failed |
| MA | append order swapped (new body before old) | 100/1 — case 1 reds at `:1027` |
| MB | merges the sysmsg channel only, ctx overwritten | 100/1 — case 1 reds at `:1031` |
| MC | `>>` naive append, second delimiter pair mid-file | 100/1 — case 1 reds at `:1031` |
| MD | `[ -f "$marker" ]` guard dropped | 90/11 — awk exits 2 on a missing file and takes the caller down; reds cases 45, 46, 56, 89–94 |
| ME | read moved inside the `> "$marker"` block | 99/2 — case 1 reds at `:988`, case 2 at `:410` |
| MF | fresh-marker write joins unconditionally (one leading newline per body) | 100/1 — case 1 reds at `:988` only |
| NA | MA against the refactored SUT | 100/1 — case 1 reds at `:1027` |
| NC | MC against the refactored SUT | 100/1 — case 1 reds at `:1031` |
| NE | ME against the refactored SUT | 99/2 — case 1 reds at `:1027`, case 2 at `:410` |
| NG | ctx reader made symmetric with the sysmsg reader | **101 passed, 0 failed — not caught** |
| NG+NC | symmetric ctx reader *and* the naive `>>` append | **101 passed, 0 failed — not caught** |

Notes on the rows that carry a claim:

- **MC / NC** confirm the drain mis-parses a naive append exactly as the
  runbook predicted. The sysmsg channel still reads `S1\nS2` (the sysmsg reader
  resets at each ctx delimiter), so `:1027` passes; the ctx channel comes back
  as `C1\n--- gitlore-relay-sysmsg ---\nS2\nC2` and `:1031` reds. The mis-parse
  is caught by one assertion only.
- **ME / NE** confirm the truncate-before-read claim the GREEN report rests on.
  Against the submitted SUT it reds at `:988`, because the redirect creates the
  file and the merge then reads the *empty* file, drifting the fresh write by a
  newline; against the refactored SUT §2's non-empty guard absorbs that, and it
  reds at `:1027` and `:410` instead — the merge still loses both old channels.
  Either way the case reds, so the claim is pinned.
- **MF** confirms `:988` is the byte-pin the test review added it for, and that
  it is the only assertion that sees the drift.
- **MD** shows the `[ -f ]` guard is load-bearing far beyond this slice: `awk`
  on a nonexistent file exits 2, which under the hooks' `set -e` aborts the
  hook, so eleven cases red.
- **NG / NG+NC** are the refactor hazard described in §1 — the only mutation
  run here that no assertion catches, and the reason the asymmetry is now
  documented rather than left to be discovered.

Write order (MA/NA) is pinned by case 1 alone; case 2's substring assertions
pass against a reversed merge. That is a property of the frozen tests, reported
not changed.

## 5. Failure path — preserved (report only, per the dispatch)

Confirmed by hand-run against the fixed SUT, both halves:

- **Directory squatting the marker path.** `[ -f "$marker" ]` is false for a
  directory, so the merge is skipped entirely and the function reaches the same
  single redirect it always did. `bash: …/gitlore-relay-a1: Is a directory`,
  return 1, the shell survives, and the directory is still empty — nothing
  partial. Slice 1's contract ("returns non-zero without writing", "exactly one
  create/open of the target", "leaves nothing partial") is intact, and slice
  4's RED for `relay_write refuses an empty agent id and a squatted marker
  path` still depends on unchanged behaviour. Not touched.
- **`awk` failing the function early under `set -e`.** It could, and this is
  the one real regression the slice introduced. With the marker present but
  unreadable (mode 0200), `[ -f ]` is true, `awk` exits 2, and under the
  callers' `set -euo pipefail` the assignment aborts **the whole hook** —
  measured: the shell died at rc 2 with the statement after the write never
  reached. The hook emits no JSON at all on that path, so the run loses its own
  report as well as the staged one, and before this slice the same marker was
  simply overwritten.

  Fixed with `|| old_sys=""` / `|| old_ctx=""` at the two reads, which degrades
  the merge to the pre-slice overwrite: the staged report is lost, this run's
  is not. That is the same trade `gitlore_relay_drain`'s `-type f` comment
  already states for the non-file shape ("trading a lost relay for a lost
  report"), so the helper now has one consistent policy. `awk`'s own diagnostic
  still reaches stderr — nothing is suppressed. Re-measured after the fix: rc
  0, the hook continues, the new report lands.

  This is not the failure path slice 4 owns — that one is the *unwritable*
  marker, and it takes `[ -f ]` false. Slice 4's RED is unaffected either way.

## 6. `set -euo pipefail`, bash 3.2, BSD

- **`set -u`.** `old_sys` / `old_ctx` are `local`-declared unset, and every
  read of them is inside the `if [ -f "$marker" ]` branch that assigns them
  first. `x=$(cmd) || x=""` assigns unconditionally — the substitution assigns
  the (empty) output whatever the exit status — so neither can be read unset.
- **`set -e`.** Both reads are `x=$(…) || x=""`, so neither can trip errexit.
  The extraction changes nothing here: a function called as a simple command
  propagates errexit exactly as an inline assignment did, and both call sites
  keep their position (write: inside an `if` body; drain: inside a `while`
  body). The function's return value is still the redirect block's status.
- **`pipefail`.** No new pipelines.
- **bash 3.2.** Nothing 4.x: no nameref, no `mapfile`, no `${var^^}`, no
  associative array, no `[[ =~ ]]`. `local` with several names, `$( )`, a
  multi-line double-quoted string and `[ -n ]` are all 3.2-and-POSIX.
- **BSD.** No new external tool. The two `awk` programs are byte-identical to
  the ones `gitlore_relay_drain` has been shipping — same POSIX awk subset, no
  GNU extension, no `-v` needed. `tests/bsd_portability.bats` passes (3/3).

## 7. Stdout discipline

Confirmed, including on the awk-failure path. Measured directly: a sequence of
write, merge-write, merge-write-against-an-unreadable-marker and drain, with
stdout redirected to a file, produced **0 bytes** on stdout; `awk`'s two
"Permission denied" lines went to stderr. Every `printf` in the function is
inside the `{ … } > "$marker"` block, and both channel readers are consumed by
command substitutions. Nothing new can reach the hooks' single JSON object.

## 8. Style

- Comment density and idiom match the neighbours: mechanism plus the reason a
  cheaper shape was rejected, which is how `gitlore_relay_drain`,
  `_gitlore_agent_suffix` and `gitlore_set_frontmatter_description` are all
  written.
- "Entry points first, definitions after their users" holds:
  `_gitlore_relay_sysblock` / `_gitlore_relay_ctxblock` sit after
  `gitlore_relay_drain`, the second of their two users, next to the file's
  other private helper.
- No comment cites anything under `plans/` or `memory/`. References are to
  shipped files only (`index-sync-post.sh`, the drain's `-type f`).
- The GREEN comment's phrase "read with the same split the drain uses" is now
  stale prose — the split *is* the drain's — so it was rewritten rather than
  left describing a duplication that no longer exists.

## 9. Flagged, not fixed

- **`gitlore_relay_drain` has the same unreadable-marker hole.** `find -type f`
  screens non-files, not permissions, so a mode-mangled marker still aborts the
  hook there. Committed code from slice 1, outside this slice; the drain's
  behaviour on that path is unchanged by this review. Tolerating it there is a
  one-line change (`|| sysblock=""`), but it changes what the drain does with a
  marker it cannot read — it would fold an empty block and `rm -f` the file —
  and that deserves its own case rather than riding in on a refactor.
- **Case 2 does not discriminate write order** (MA/NA red case 1 only). The
  test files are frozen; reported, not edited.
- **§2's non-empty join guard is untested.** No frozen case writes an empty
  ctx. If a later slice wants it pinned, the fixture is one
  `gitlore_relay_write mem a1 "S" ""` followed by
  `gitlore_relay_write mem a1 "S2" "C2"`, asserting the drained ctx block has
  no leading blank line.

## Checks that passed, by name

- `scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats`
  — 101 passed, 0 failed (baseline before mutation, and again on the restored
  fixed SUT).
- `scripts/run-bats.sh tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats
  tests/index_compose.bats tests/cc_hook_post_tool_use.bats tests/lib_util.bats`
  — 130 passed, 0 failed.
- `scripts/run-bats.sh tests/bsd_portability.bats` — 3 passed, 0 failed.
- `shellcheck -s bash scripts/lib/index-sync.sh` — clean.
- `scripts/lint-shell.sh` — 137 files clean.
- Mutations MA, MB, MC, MD, ME, MF against the submitted SUT and NA, NC, NE,
  NG, NG+NC against the refactored SUT — each a full run of both suites, each
  restored; results in §4.
- Hand-run probes, all against the SUT in place: three successive writes
  (associativity), the empty-ctx merge before and after the fix, the
  directory-squat failure path, the unreadable-marker path before and after the
  fix, and the stdout-byte count across all four.
- Mutation restore verified: `diff` of the SUT against the saved pre-mutation
  copy came back identical immediately after the last mutation run. One comment
  was reworded afterwards (§8's third bullet), and every check listed above was
  run on the file as it now stands. `git diff -- scripts/lib/index-sync.sh`
  shows only the reviewed change plus this review's three fixes.
- `git status --short` — `scripts/lib/index-sync.sh` and the two frozen test
  files modified, this slice's reports untracked. Nothing committed, nothing
  staged, no mutation artifact or scratch file left in the tree.
