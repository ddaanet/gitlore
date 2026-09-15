# Item 2.2 — code review

Commit reviewed: `7b8407f`. Scope: `scripts/lib/resolve.sh`,
`gitlore_adopt_tier_into_root` and its helpers. All fixes applied in the working
tree, uncommitted.

## Verdict

K1/K2/K6 conformance holds: R is built with `commit-tree -p HEAD` from a
temporary index in the tier's gitdir, `live` advances with an ff-checked
`push .`, the tier moves only by `checkout --detach live`, and the compose is
retried once. The trigger is `rc 1` plus a carrier-prefixed problem (K2). No
failure path silently continues. The fixes below cover a wrong header comment,
plan labels in source, bytes the blob write could change, a `2>/dev/null` the
shell rules forbid, and six copies of the cleanup-plus-walk-back tail.

## errexit and ignored statuses

`gitlore_adopt_tier_into_root` is always called as `... || return 1`, so errexit
is off throughout its body and every helper it calls. Unguarded failures
therefore continue rather than abort, so each one was checked:

- Every `|| :` sits on `gitlore_adopt_walk_back_tier` or
  `gitlore_adopt_report_refusal_and_walk_back`. Both always return 1 after
  emitting, and every caller returns 1 on the next line. No status is lost.
- `[ -n "$composed" ] && printf | sed` is never the last statement, so its
  status is never returned.
- The R build used an `rc` chain (`if [ "$rc" -eq 0 ] && ! ...`). It was correct
  but hard to read. It is now a helper with `|| return 1` on each step (below).
- The mode read (`ls-tree | awk`, falling back to `100644`) hid a failed read
  behind a default. It now fails the build when the entry is empty.

## Findings and fixes

1. **Major — header comment stated the opposite of the code.** The new paragraph
   in `gitlore_adopt_tier_into_root` said a refusal naming root, the manifest or
   another tier leaves "the first refusal's problem list … unprinted and the
   walk-back below never runs for it". With no carrier problem, the code prints
   the list and walks back as before. Rewritten to describe the repair arm and
   the retry's refusal.
2. **Major — plan labels in source.** The comments cited `K1`, `K2` and `K3`,
   which are outline-only IDs, against the dispatch constraint that source cites
   no plan. Removed and replaced with the substance. `D6`, `D49` and `D50` stay:
   they are `docs/decisions.md` records.
3. **Major — the blob write could change bytes.** `hash-object -w "$copy"` ran
   clean filters and attributes on a path inside the gitdir. `core.autocrlf` or
   a `* text=auto` attribute would rewrite a CRLF arrival, breaking "every other
   line keeps its bytes". The copy is taken from a blob, so it is now
   `hash-object -w --no-filters --`.
4. **Minor — `2>/dev/null` on the pin read.** `.claude/rules/shell.md` prefers a
   guard that removes the expected case. Now
   `rev-parse -q --verify "$old_gitlink:MEMORY.md"` (probed: silent, rc 1 on a
   missing path) guards a plain `git show`. As a side effect, a pin carrier that
   exists but cannot be read now fails the repair with a message. Before, the
   pin was silently treated as empty, which changes which duplicate survives.
5. **Minor — duplicated cleanup and walk-back tails; fragile scratch files.**
   There were three `mktemp` files, each failure arm repeated
   `rm -f …; walk_back || :; return 1`, and the temporary index was a 0-byte
   `mktemp` file. That works only because `read-tree` without `-m` never reads
   the index it replaces. Changes:
   - One `mktemp -d "$gitdir/gitlore-repair.XXXXXX"` holds `arrival`, `pin` and
     `index`, and a single `rm -rf` runs before any ref moves.
   - The read, rewrite, recheck and build steps form one `if/elif` chain that
     prints the failing step's message. A single walk-back follows, gated on
     `repair` being set.
   - Building R moved into `gitlore_adopt_commit_repair`, which prints the
     commit.
   - The index path no longer exists before `read-tree`.
6. **Minor — naming.** `local R` became `repair` to match the lowercase locals
   in the file, and `abs_gitdir`/`copy`/`pincopy`/`idxfile` became
   `gitdir`/`$scratch/*`. Every `$mempath/$tier` in the repair became
   `tierpath`, and the unused `carrier` local in `gitlore_adopt_tier_into_root`
   was dropped.
7. **Minor — definition order.** Functions are now ordered entry point first,
   with each definition after its users: `tier_into_root`, `repair_arrival`,
   `commit_repair`, `report_refusal_and_walk_back`, `walk_back_tier`,
   `stage_pair_and_commit`, then the existing `commit_tier_bookkeeping`.
8. **Minor — "Today's refusal" comment.** It framed the text against a previous
   version, so it is rewritten in the present tense. Each helper now states its
   return contract (`Returns 1 after emitting …`).
9. **Minor — unrepairable report lines are indented like the other list.** The
   problem lines were printed bare (`live:MEMORY.md: …`). The sibling refusal
   list in the same take prints `gitlore:   <problem>`, so they are now
   `gitlore:   live:MEMORY.md: …`. The runbook fixes the sentence exactly and
   the `live:MEMORY.md: ` substitution. It does not prescribe the line prefix,
   and slice 4's contains-assertion still holds. **Flag for Phases 5-7:** any
   prose quoting this output should use the indented form.

## Failure paths — who learns

| Path | Tier after | `live` after | Reported |
| --- | --- | --- | --- |
| gitdir or `mktemp -d` fails | pin | arrival | git or mktemp stderr, walk-back line |
| arrival or pin carrier unreadable | pin | arrival | git stderr, step message, walk-back |
| `gitlore_repair_index` rc 1 | pin | arrival | step message, walk-back |
| recheck still refuses | pin | arrival | unrepairable sentence and `live:MEMORY.md:` lines, walk-back |
| R build fails | pin | arrival (R unreachable) | git stderr, step message, walk-back |
| `push .` refused | pin | arrival | git's message, walk-back |
| checkout of `live` fails | pin | R | git's message, walk-back |
| retry rc 1/2 | pin | R | retry output under the refusal header, walk-back |
| walk-back checkout fails | arrival or R | as above | git's message and a runnable absolute command |

Scratch is removed before any ref moves, on every path. A kill between
`mktemp -d` and `rm -rf` leaves one `gitlore-repair.*` directory in the tier
gitdir. It is inert, since nothing reads it, and is not swept. Clearing it would
need a trap in a library function or a sweep elsewhere, which is beyond this
item.

## Notes (not changed)

- **Walk-back closing line after an unrepairable arrival.** The contract has the
  walk-back print "Fix the store, then run /gitlore:merge again." directly after
  "must be fixed where it was published". Read as "the tier store, fixed
  upstream", it holds. It is contract-prescribed, so it is left for the prose
  phases to weigh.
- **Unrepairable arm with root problems too.** Only the carrier's problems are
  printed. The root problems surface on the next take once upstream is fixed,
  which is per contract.
- **K6 wording inside a push.** `/gitlore:push publishes it` is printed even
  when the take runs inside a push. That arm is Item 2.3's.

## Coverage

- Mutation: skipping `rm -rf -- "$scratch"` turns slices 4 and 6 red on
  `tier_gitdir_files` (2 failed). Restored.
- **Gap (tests out of scope):** passing a nonexistent pin path to
  `gitlore_repair_index` in place of `$scratch/pin` leaves all 7 repair tests
  green. No take-level test has differing duplicates sharing a path, so nothing
  proves the pin carrier reaches the repair from the take. Item 2.1's unit tests
  cover the pick itself. A test where the arrival carries two differing lines
  for one path, one of them in the pin, would close it.
- No test covers `--no-filters` (a CRLF arrival under `core.autocrlf`).

## Verification (after fixes)

- `scripts/run-bats.sh tests/merge_memory.bats`: 30 passed, 0 failed
- `scripts/run-bats.sh tests/tier_divergence.bats`: 19 passed, 0 failed
- `scripts/run-bats.sh tests/push_behind_vs_diverged.bats`: 12 passed, 0 failed
- `scripts/run-bats.sh tests/resolve_compose.bats`: 9 passed, 0 failed
- `scripts/run-bats.sh tests/commit_memory.bats`: 35 passed, 0 failed
- `shellcheck scripts/lib/resolve.sh`: clean

REFACTOR-NEEDED: none. UNFIXABLE: none.
