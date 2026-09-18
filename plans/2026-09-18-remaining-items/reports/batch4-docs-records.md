# batch4 — docs records and dead code

Five items, all landed, uncommitted in the working tree. Nine files changed.

## Item 1 — `set -e` does not abort a Bash tool command

**Changed:** `.claude/rules/shell.md` (new bullet, next to the `$TMPDIR` one).

**Measured before writing**, four probes:

- `set -e; false; echo …` — the echo ran. `$?` was 1 at that point, so the
  failure registered and did not abort.
- `set -e; … ; cd /nonexistent-dir-xyz; echo pwd=$(pwd)` — `cd` failed with
  `/bin/bash: line 4: cd: … No such file or directory`, and `pwd` was still
  `/Users/david/code/gitlore`. This is the half the file already records from
  the `$TMPDIR` side, confirmed from the other direction.
- `set -e; echo "$-"` printed `ehmtBc`, and `shopt -q -o errexit` returned 0.
  **errexit is on.** The first draft of this rule would have said `set -e` is
  stripped or ignored; it is not, which is why the bullet says suppressed.
- Contrast: the same four lines written to a file and run as `bash script.sh`
  exited 1 after `echo start`, without reaching `echo continued`.

**Mechanism, grounded rather than guessed.** `bash -c 'set -e; { echo "$-";
false; echo inner; } || true; echo outer'` printed `ehBc`, `inner` and `outer` —
errexit set, and suppressed anyway. Same for the group as an `if` condition.
POSIX suppresses errexit throughout any context whose exit status is tested, and
the Bash tool runs the command in one; `FUNCNAME` is empty, so it is not a
wrapper function. The bullet states the suppression and the consequence without
asserting the wrapper's exact shape, since only the suppression is measured.

## Item 2 — D53 and D54

**Changed:** `docs/decisions.md` (Git hooks group), `docs/references/git-hooks.md`
(title, conclusion bullets, Mechanism, Decisions section, Rejected alternatives).

Ids D53/D54 — D52 was the highest in use, and `grep -rn "D5[3-9]" docs/ plans/`
returned nothing.

**Both statements verified against the code first, and both hold.**

(a) `gitlore_guard_stale_merge_state` (`scripts/lib/resolve.sh:82`) returns 1
from every failing arm — `:103` (state file uncompletable), `:107` (prepared
merge re-emitted), `:110` (recovery), `:124` (orphaned `MERGE_HEAD`) — with no
per-arm code. Its four call sites inside the commit path (`:901`, `:982`,
`:1010`, `:1055`) are all bare `|| return 1`, with no `touch "$msgfile"`,
against sibling failures on the same paths that do restamp (`:910`, `:915`,
`:917`, `:923`, `:941`, `:963`, `:1060`, `:1088`). The comment at `:1041-1046`
states the same reason the decision now records.

(b) `gitlore_commit_msg_freshness` (`scripts/lib/util.sh:284`) reads the
approval as fresh when the msgfile's mtime is `>=` the newest non-`.git` file in
the store, and the restamp is a bare `touch`, stamping it at now — so a write
landed mid-run by another session reads as covered. The rejected `touch -r`
snapshot buys nothing because the success path holds the same window, wider:
freshness is read once at `:998` and the memory `add -A` is at `:1197`, after
the pin check, compose and every tier commit. Verified by reading the call
order, not inferred from the node.

Neither statement needed downgrading; nothing was recorded that the code does
not do.

## Item 3 — bats assertions assume bash >= 4.1

**Changed:** `tests/bsd_portability.bats` (header comment, one paragraph),
`docs/references/testing.md` (one paragraph in the NFR9 section — the natural
place, since that section owns what the bats tier is).

Stated once in each, framed as what the suite's assertions assume and what a
macOS run does about it. No `|| return 1` sweep and no per-test rule, as
directed. Nothing in the repo documented this before — `grep` for `bash 3.2` hit
only the BSD header, a changelog entry about `BASHPID`, and
`tests/index_sync.bats:960`.

Not verified by execution: no bash 3.2 is available here, so the version
boundary is taken as given rather than measured. Worth flagging, since every
other claim in this report was run.

## Item 4 — `gitlore_index_largest` removed

**Changed:** `scripts/lib/index-sync.sh` (function plus its 8-line comment
block, 23 lines), `tests/index_sync.bats` (both unit tests, 36 lines),
`scripts/lib/index-compose.sh:607` (the comment naming it).

**Re-verified dead before deleting:** `grep -rn "index_largest" scripts/ skills/
commands/ hooks/ agents/` returned only the definition and the one comment. No
production caller.

Swept per `craft:removing-cleanly`, including the skill's warning about derived
figures that a name-grep misses:

- `docs/` — `grep -rn "index_largest\|largest" docs/` returned six hits, all
  unrelated prose about largest *index lines*. No doc named the function.
- No helper or fixture was exclusive to the two tests; both built their
  `MEMORY.md` inline with `printf`/`awk`.
- The `index-compose.sh` comment's parenthetical was dropped rather than the
  sentence — the SIGPIPE rule it states stands on its own now that the sibling
  it pointed at is gone.
- Derived figures: no count of functions or of `index_sync.bats` cases appears
  in `docs/`. `check-docs-links.py`'s `enumeration-drift` check is 0.

**Not changed, deliberately:** four hits under `plans/`, three of them in
`plans/*/reports/`. Reports record a run that finished and are excluded from
`format-docs` for that reason; rewriting them would falsify what those runs
observed. One of them, `batch2-small-pins.md`, is a peer agent's in-flight report
in this same batch, which is not mine to edit in any case.

## Item 5 — the recall artifact's dangling memory files

**Changed:** `plans/index-edit-propagation/recall-artifact.md`.

All four moved into **skills**, none into a successor memory file, so all four
retire rather than repoint. Traced through `git log --diff-filter=DR` in the
memory tree and read from the removing commits' own messages:

| named file | commit | where the content went |
| --- | --- | --- |
| `hook-input-schema` | `a7c1e85` "Retire what plugin-craft now ships…" | `plugin-craft:hook-authoring` reference material — moved so recall's 4096-byte cap stops truncating it |
| `genuine-red-not-missing-sut` | `f4e077f` "Retire twenty craft-seed source facts…" | `craft:test-discipline`, genuine-red node |
| `green-is-not-evidence` | `f4e077f` | `craft:test-discipline`, vacuous-green and non-vacuous-negatives nodes |
| `design-doc-writing` | `f4e077f` | `craft:design-doc-writing`, hub plus five reference nodes; the cited §"Splitting an oversized subsystem" is now the splitting-an-oversized-doc node |

The three surviving bullets (`hook-output-channels`, `git-hook-env-leak`) were
confirmed still present under `memory/ddaanet/`.

**A judgement call worth surfacing.** Deleting the four bullets outright would
have dropped the rationale that explains why Phases 1-3 are shaped as they are —
the artifact's whole purpose. So the four are gone from the list of memory
entries (which is what the header says it holds, and nothing there now names a
file that does not exist), and the reasoning survives in a short paragraph below
it that names the skill and node carrying each fact. If the intent was a bare
deletion, that paragraph is the thing to cut.

**One dangling reference beyond the four named.** The closing paragraph cited
`test-the-invocation-path`, also retired in `f4e077f` into
`craft:test-discipline`'s coverage-shape node, and confirmed absent under
`memory/ddaanet/`. Repointed, since "nothing left dangling" would not have held
otherwise.

## Verification

`just format-docs` — fixed 2 issues in 2 files (re-wrapped `testing.md` and
`git-hooks.md` after the edits).

`python3 scripts/check-docs-links.py` — rc 0, **54 decisions, 121 files
scanned** (52 before; D53 and D54 are the two new ones), and every counter 0:
broken-link, unstubbed-decision, stub-without-body, duplicate-decision,
duplicate-conclusion, undefined-decision, enumeration-drift, delegation-drift,
oversized-file. `git-hooks.md` is still under the 400-line cap after +77 lines.

Suites, each foreground through `scripts/run-bats.sh`, one at a time:

| suite | result |
| --- | --- |
| `tests/index_sync.bats` | 87 passed, 0 failed |
| `tests/bsd_portability.bats` | 3 passed, 0 failed |
| `tests/check_docs_links.bats` | 43 passed, 0 failed |
| `tests/lint_shell.bats` | 3 passed, 0 failed |
| `tests/check_memory_hygiene.bats` | 39 passed, 0 failed |

The last was added because `grep -rln` showed it as the only other suite
referencing `decisions.md`; `grep` found no suite besides `index_sync.bats`
referencing the removed function.

`scripts/lint-shell.sh` — 138 files clean, rc 0. Run directly rather than
through `just lint` so no gate sentinel was written.

Not run, as directed: `just precommit`, `just test-unit`, `just test-integration`.
Nothing committed, no branch created, `memory/` untouched.
