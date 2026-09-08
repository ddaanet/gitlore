# Item 3.1 slice 1 — code review (GREEN)

Verdict: the implementation satisfies the three interfaces and the four frozen
cases discriminate against every mutation the interface names. Three defects
found, all fixed in `scripts/lib/index-sync.sh`; two of the three are invisible
to slice 1's tests and were caught by hand-run probes, not by the suite. Three
coverage gaps are reported and not fixed, because `tests/index_sync.bats` is
frozen.

The SUT under review after fixes:
`/Users/david/code/gitlore/scripts/lib/index-sync.sh` —
`gitlore_relay_marker_file` at `:120`, `gitlore_relay_write` at `:137`,
`gitlore_relay_drain` at `:161`.

## 1. Defects found and fixed

### C1 (critical) — a non-regular file on a marker name kills the hook

`find … -name 'gitlore-relay-*'` matched any directory entry, including a
directory. `awk` on a directory exits 2 on mawk (Debian) and on BSD/macOS awk;
`rm -f` on a directory exits 1. Both sit in the drain's loop body, and every
hook that sources this file runs `set -euo pipefail`, so a bare
`gitlore_relay_drain "$mempath"` aborts the hook — no JSON on stdout, so the
hook's *entire* report is lost, not just the relay.

That shape is not hypothetical: slice 4 creates it deliberately
(`mkdir "$(gitlore_relay_marker_file memory a1)"`, runbook `:842-847`) and never
removes it. Slice 4 asserts the *write* survives; the next unkeyed run in that
store hits the drain.

Measured, original vs fixed, drain called bare under `set -euo pipefail` with a
directory at `gitlore-relay-a2` beside a good `gitlore-relay-a1`:

```
##### original
about to call the drain bare, under set -e
awk: cannot open ".../gd/gitlore-relay-a2" (Is a directory)
script exit=2                      # the line after the drain never ran

##### fixed
about to call the drain bare, under set -e
REACHED THE LINE AFTER THE DRAIN
script exit=0
```

Fix: `-type f` in the `find`. The squatter is skipped rather than folded; the
good marker is still folded and unlinked.

### C2 (major) — a newline in the gitdir path corrupts the fold

The fold sorted **whole paths** joined on newline. The agent-id suffix is
sanitized, but nothing sanitizes the gitdir prefix, and the GREEN report's
argument ("the only whitespace this path class can carry is inside the gitdir
prefix") holds for a space and not for a newline. With the store at
`.../has\nnewline/memory`, the original produced four blocks from two markers,
attributed two of them to an agent named `has`, and removed nothing — so every
later drain re-emits them, unbounded:

```
##### original                                    ##### fixed
SYS=[--- gitlore-relay agent has ---              SYS=[--- gitlore-relay agent a1 ---
                                                  S-one
--- gitlore-relay agent has ---                   --- gitlore-relay agent a2 ---
                                                  S-two
--- gitlore-relay agent a1 ---                    ]
                                                  markers left: 0
--- gitlore-relay agent a2 ---
]
markers left: 4
```

Fix: sort **basenames**, not paths. A basename is `gitlore-relay-` plus what
`_gitlore_agent_suffix` emits (`[A-Za-z0-9-]`), so the newline-joined list is
unambiguous by construction, and the prefix — identical across markers — was
sorting nothing anyway. This is also the honest form the dispatch asked about:
the previous code sorted a constant prefix plus the key. The enumeration stays
`find -print0` / `read -r -d ''`.

The rewrite drops the `markers` array for a newline-joined string, which removes
a second, latent bash-3.2 exposure: `[ "${#markers[@]}" -gt 0 ]` on an empty
array under `set -u`. Bash before 4.4 treats an empty array as unset for
`${a[@]}` expansions (`bash -c 'set -u; unset a; echo "${#a[@]}"'` →
*unbound variable*), and the empty store is the common parent-side case, so a
macOS abort there would have hit every session with no marker pending. I could
not get a bash 3.2 to confirm the `${#a[@]}` form specifically, and the guard as
written never expanded the array — so this is a removed exposure, not a proven
break. `[ -n "$names" ]` has no version question.

### C3 (major) — `sort` collation was locale-dependent

Plain `sort` uses the ambient locale. Under a UTF-8 collation `-` is ignored at
the first level, so `gitlore-relay-a-1` and `gitlore-relay-a1` can order
differently than in byte order — a fold order that changes with the machine's
`LC_ALL`. The codebase already uses `LC_ALL=C` for exactly this, three functions
down (`_gitlore_agent_suffix`'s `LC_ALL=C tr`). Fix: `LC_ALL=C sort`.

Honest caveat: `en_US.UTF-8` is not installed on this box, so both my `sort`
runs collated in C and I have no local demonstration of the flip. The fix costs
nothing and the C-order result is now pinned: `A1 | a-1 | a1 | a2 | b1`.

### Minor fixes

- **The neighbour list did not add up.** The comment said "the sixth untracked
  `gitlore-…` file … beside" and then named four. The runbook's own count
  (`:682-686`) includes the `gitlore-merge-<artifact>` briefing files. Added.
- **Shipped source cited a plan file.**
  `(subagent-hook-output-probe.md, CC 2.1.261)` points into `plans/`, which is
  prospective and gets deleted (`git log --diff-filter=D -- plans/` shows prior
  sweeps). No other file under `scripts/` references `plans/`; the house style
  in this file is a decision id (`D17`, `D23`) or a shipped path
  (`commands/index-audit.md`). Reduced to "(measured under CC 2.1.261)".
  **For the orchestrator:** Items 4.1-4.3 should carry the probe's evidence into
  `docs/references/` and back-fill a decision id here.
- **The delimiter contract stated no failure mode.** Added one clause naming
  what a body containing an exact delimiter line would do (re-split, tail
  attributed to the wrong channel, silently), per the project's "state a
  residual bound rather than implying full coverage" rule.
- **The unsuffixed-marker comment argued from the runbook's wording.** Rewritten
  to argue from the mechanism (a run with an agent id is exactly a run whose
  report needs relaying) and to name the residual: a caller passing an empty id
  strands a file nothing folds and nothing removes. See §4.

## 2. Mutation round

In-place on `scripts/lib/index-sync.sh` (saved, mutated, run, restored);
`tests/index_sync.bats` untouched throughout. Run as
`bats -f 'relay' tests/index_sync.bats` — four cases, 3.2s, full stream shown,
no `tail`. Case numbers: 1 `relay_marker_file suffixes the agent id`, 2
`relay_write then relay_drain splits…`, 3
`relay_drain folds two markers in filename order, over a gitdir path holding a space`,
4 `relay_drain on an empty store…`.

| # | Mutation | Result | Which case caught it |
|---|---|---|---|
| M1 | drain glob `gitlore-*` instead of `gitlore-relay-*` | **red** | 4 (the compose-stamp decoy) |
| M2 | fold in reverse filename order (`sort -r`) | **red** | 3 |
| M3a | `ls "$gitdir" \| grep '^gitlore-relay-'` instead of `find -print0` | **GREEN — gap** | none |
| M3b | unquoted glob `for m in $gitdir/gitlore-relay-*` | **red** | 3 |
| M4 | never split on the ctx delimiter (both bodies into both vars) | **red** | 2 (the two cross-check negatives) |
| M5 | fold without unlinking the marker | **red** | 2 and 3 |
| M6 | framing line on `SYSMSG` only | **red** | 2 |
| M7a | `gitlore_relay_write` returns 0 on a failed open | **GREEN — gap** | none |
| M7b | `gitlore_relay_write` writes incrementally, leaves a partial file | **GREEN — gap** | none |
| M8 | `gitlore_relay_marker_file` suffixes unconditionally (`-${2:-}`) | **red** | 1 (the `""` half) |
| M9 | drop the two `=""` initializations | **red** | 2, 3 and 4 |
| M10 | framing line without the agent id | **red** | 2 |
| M11 | drop the sort entirely | **red** | 3 |

Re-run after the fixes, to confirm the cases still discriminate against the
rewritten drain: baseline 0 red; M1 1 red; M2 1 red; M11 1 red; M5 2 red. One
new mutation on the new code:

| # | Mutation | Result | Which case caught it |
|---|---|---|---|
| M12 | drop `-type f` from the `find` | **GREEN — gap** | none |

### The three ship-green gaps

**M3a — an `ls` pipeline passes the spaced-gitdir case.** Slice 1's own gap. The
runbook's "never an `ls` pipeline" clause is *unenforceable by this test*:
`ls "$gitdir"` prints basenames, and a marker basename is
`gitlore-relay-[A-Za-z0-9-]*` — no whitespace, by construction of
`_gitlore_agent_suffix`. The space lives in the prefix, which `ls` never prints.
The case does catch the unquoted glob (M3b), which is the other half of that
clause and the one that actually breaks. Recommendation: the clause is a style
rule with no reachable failure here — either accept that or drop it; do not add
a test that cannot fail.

**M7a and M7b — the write's failure contract is pinned by nothing.** Slice 1 has
no failed-write case, so "returns non-zero" and "without writing" are both
unasserted. Slice 4's case
(`a failed relay write leaves the subagent's own report intact`) asserts the
*hook* exits 0 with its own report intact, which a write wrongly returning 0
also satisfies — so the gap survives slice 4 as the runbook specifies it. I
verified both halves by hand instead (§3, item 4). **For the orchestrator:**
slice 4 could close it for one line by asserting
`run ! gitlore_relay_write memory a1 S C` and that the squatting directory is
still empty.

**M12 — nothing pins `-type f`.** Created by this review; no slice-1 case makes
a directory marker. The behaviour it protects is C1, which is a hook-level
observable, so the natural home is slice 4's file: after the failed write, fire
the hook again *unkeyed* and assert it still exits 0 and still reports. Flagged,
not written — `tests/` is out of scope for this dispatch.

## 3. The specific checks the dispatch named

1. **`sort` portability and correctness.** The GREEN report's newline argument
   is right about `_gitlore_agent_suffix` (`tr -c 'A-Za-z0-9-' '_'` folds an
   embedded newline too) and wrong about the gitdir prefix, which nothing
   sanitizes — C2. Sorting the basename is the more honest form and is what
   shipped. Locale sensitivity was real and is fixed — C3. BSD `sort` has no
   `-z`; that part of the GREEN report holds.
2. **bash 3.2 and BSD.** `find "$gitdir" -maxdepth 1 -type f -name … -print0`
   puts the path first, before the primaries, which is what BSD `find` wants;
   `-maxdepth`, `-type` and `-print0` are all on macOS `find`.
   `tests/helpers/bsd-stubs.bash` shadows only `sed`, `grep` and `mktemp`, so
   nothing here is stubbed. The `read -r -d ''` loop is fine on 3.2; the array
   is gone (C2). `$'\n'` is bash 2+. The `awk` program is two POSIX pattern
   blocks and a bare `f` — no gawk extension.
3. **`awk` and the delimiter split.** Probed on the fixed code:
   - empty sysmsg, non-empty ctx → `SYS` is the framing line and one empty line;
     `CTX` carries the body. Correct.
   - both empty → both channels framing-only. Correct.
   - a body line that merely *starts with* `--- gitlore-relay-ctx ---` (with a
     trailing word) stays in the sysmsg body — the `$` anchor holds.
   - trailing blank lines in a body are stripped, by `$(…)`, not by the awk.
     Cosmetic and accepted: no report body ends in meaningful blank lines.
   - a body containing an *exact* delimiter line is excluded by contract; it
     degrades to a silent re-split, mis-attributing the tail. Documented in the
     comment rather than escaped, since escaping would change the file format
     the runbook fixes.
4. **The failed-write path.** Verified by hand, marker path occupied by a
   directory: `rc=1`, **stdout empty**, the message on stderr only
   (`bash: …/gitlore-relay-a1: Is a directory`), and `find <dir> -mindepth 1`
   reports 0 entries — nothing written anywhere. A hook splicing this function's
   stdout into its JSON is safe. The single `>` on the compound is what buys it,
   and it is the right shape.
5. **The unsuffixed-marker no-op.** The call is right, the *reason* was not.
   "The runbook says keyed" is not an argument; the argument is that a hook only
   relays when it has an agent id, so an unsuffixed marker is unreachable from
   the wiring slices 2-4 install. I rewrote the comment to say that and to name
   the residual: it is a silent leak — a file nothing folds and nothing removes
   — if a call site ever passes an empty id. `gitlore_relay_write` does not
   refuse an empty `$2`, and I did **not** make it refuse: that adds a
   precondition the runbook's interface does not state, and no frozen test
   covers it. **Open question for the orchestrator:** either slices 2-3 assert
   the hooks call the write only when keyed, or `gitlore_relay_write` grows
   `[ -n "$agent_id" ] || return 1`. I recommend the guard in the write — it is
   one line and it makes the drain's scope airtight — but it is a contract
   change and therefore your call, not mine.
6. **Style and placement.** The three helpers sit with their siblings, above
   `_gitlore_agent_suffix`, so definitions still follow their users. No compat
   shim, no alias. Comment density matches the `gitlore_index_preimage_file` /
   `gitlore_compose_stamp_file` blocks. No comment cites anything under
   `memory/`; the one citation into `plans/` is fixed (§1, minor).

## 4. Observations, not defects

- **`gitlore_relay_marker_file` can return a relative path**, because
  `rev-parse --git-path` is relative for a plain repo — while
  `gitlore_relay_drain` resolves `--absolute-git-dir`. They agree only because
  gitlore's store is always a submodule (`memory/.git` is a file). This is the
  documented behaviour of both siblings ("Abs/relative path of…") and their call
  sites annotate it (`index-sync-pre.sh:41`, `index-sync-post.sh:38`), so the
  new helper is consistent and I changed nothing. It does mean the runbook's
  phrase "prints the **absolute** path" is true of the deployment, not of the
  function. It bit my own probe harness before I gave the fixture a
  `--separate-git-dir`.
- **No refactoring is being deferred.** Nothing here wants a module split or a
  new abstraction.

## 5. Checks that passed, by name

- `bats -f 'relay' tests/index_sync.bats` — 4 ok, 0 not ok (mutation-round
  baseline, and again after every restore)
- 13 mutations applied in place and reverted; SUT sha256 confirmed identical to
  the pre-mutation copy before any fix was written
  (`b0832cd2cd5607dd5b54ebc5bed78ea45fb39b9041a5ec9363370578a898ed6e`), and
  identical to the post-fix copy after the second mutation round
  (`1b17d151da470dded61b9ab746c385b0614f498b3abab87975cfde4aa5b1bc03`)
- 8-case edge probe on the fixed code (empty sysmsg / empty ctx / both empty /
  near-delimiter line / trailing blank lines / directory squatter / failed write
  rc+stdout+on-disk / newline gitdir / C-collation ordering) — all as specified
- 3-case differential probe, original vs fixed, proving C1 and C2 are real and
  closed
- `./scripts/run-bats.sh tests/index_sync.bats` — 75 passed, 0 failed
- `./scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats`
  — 49 passed, 0 failed
- `shellcheck -s bash scripts/lib/index-sync.sh` — clean, exit 0
- `./scripts/lint-shell.sh` — 137 files clean
- `git diff --stat -- scripts/lib/index-sync.sh` — `92 ++…`, 91 insertions, 1
  deletion, one hunk: the GREEN implementation plus this review's fixes, nothing
  from the mutation round
- `git status --short` — `scripts/lib/index-sync.sh`, `tests/index_sync.bats`
  and this report; nothing staged, nothing committed. No `just` recipe was run
  and no background task was started. (`plans/index-edit-propagation/runbook.md`
  also shows modified; not mine — I did not open it for writing.)
