# Phase 1 boundary decisions — implemented

The six items in `phase-1-corrector.md` §"Decisions for my human partner", each
implemented as its accepted **Recommended:** line and nothing more.

---

## D-1 — a memory commit adopts an off-pin tier gitlink

Recorded, not implemented. `scripts/lib/resolve.sh` carries no behaviour change.

**`plans/index-edit-propagation/runbook.md`**, four edits:

- **`:17`** — new §Requirements row,
  `FR-F — a memory commit never adopts a tier gitlink moved off the pin the memory store records`,
  tracing FR15, FR8, FR11, NFR5 (the four Item 1.1 traces) plus NFR2, which is
  what the self-describing refusal answers to. Phase 1, Item 1.2. No existing
  phase or item renumbered.
- **`:92-102`** — Item 1.1's rc-1 rule amended, in the item's prose rather than
  in a slice: "a `gitlore_compose_check` refusal proceeds; a pin refusal
  aborts", with the `add -A` mechanism that makes the two halves different and a
  cross-reference to Item 1.2. The already-executed slices are not rewritten;
  the paragraph says so explicitly.
- **`:357-521`** — **Item 1.2**, appended to Phase 1 after Item 1.1, typed as a
  tdd item. Content: call `gitlore_compose_check_pins "$mempath"` at the
  `gitlore_sync_memory_to_live` call site, after the up-front per-tier
  stale-merge loop and immediately before `gitlore_compose`, and `return 1` on
  its refusal. It states that its execution slot is deliberately open and that
  it must land before Phase 4 so Item 4.1's decision node describes the final
  behaviour. Three behaviour slices in Item 1.1's shape — named test files,
  named test cases, and the three message texts (header, agent remedy, user
  remedy) pinned in the item text rather than left to green time. It also names
  the two Item 1.1 cases the change invalidates
  (`an off-pin compose refusal is reported and does not abort the commit`,
  `the rc-1 user arm does not tell a user to retry a commit that succeeded`),
  the `gitlore_compose_check` induction that re-homes the surviving rc-1 arm
  (`set_tier_manifest ddaanet phantom`, rule 2 at
  `scripts/lib/index-compose.sh:177-180`), and where to look for fallout
  (`tests/tier_divergence.bats`, `tests/tier_lockstep.bats`).
- **`:834-867`** — Item 4.1's third argued reason rewritten. It no longer says
  an off-pin refusal is correct to commit through; it states the rule Item 1.2
  implements and the `add -A` → next-compose → `pre-push` chain that destroys
  and then ships the approved upstream fact. The `Rejected:` line now takes two
  entries: the original **a refusal that instructs the agent to run compose**,
  plus **reporting an off-pin tier and committing through it**.

Two consequential edits made because the runbook would otherwise contradict
itself, both reported rather than silent:

- **`:809`** — Item 4.1's header now reads `Depends on: Item 1.1, Item 1.2` (and
  "alternatives", plural). This is where an orchestrator reads the ordering
  constraint Item 1.2 states in prose.
- **`:879-880`** — Item 4.2's bullet said "the rejected alternative appended to
  the group's existing `*Rejected:*` line"; it now says "Item 4.1's two rejected
  alternatives".

**Evidence:** none run — this decision is recorded prose, and its underlying
measurement is the checkpoint's own D-1 probe. No `scripts/lib/resolve.sh`
behaviour was touched, which `git diff` confirms: the only hunk in that file is
D-6's comment.

## D-2 — remedy sentences pinned by nothing

Two assertions added, on the two reachable arms; the two `*)` arms recorded as a
residual.

- **`tests/commit_memory.bats:188-192`** — in
  `an off-pin compose refusal is reported and does not abort the commit`, which
  already runs `CLAUDECODE=1 run --separate-stderr`:
  `[[ "$stderr" == *"This commit also stages each tier at the commit its worktree is on now"* ]]`.
- **`tests/commit_memory.bats:220-223`** — in
  `a compose write failure aborts the commit`, same preconditions:
  `[[ "$stderr" == *"Investigate that path (permissions, disk space, a read-only worktree)"* ]]`.
- **`plans/index-edit-propagation/runbook.md:226-232`** and **`:251-259`** — the
  two slice-3 assertion lists amended so plan-as-written matches
  plan-as-executed. The rc-2 bullet also gained the header and forwarded
  problem-line assertions it was already executing but never listed.
- **`plans/index-edit-propagation/runbook.md:348-356`** — the residual, at the
  end of Item 1.1: the `*)` arm's two remedy sentences stay unasserted, because
  `gitlore_compose` returns only 0, 1 or 2, so the arm is reachable only through
  a stub and a second stub case bought to pin wording on an unreachable path
  costs more than the wording is worth.

**Evidence:** `CDPATH=. bash scripts/run-bats.sh tests/commit_memory.bats` —
**16 passed, 0 failed** (the run also serves as D-5's positive), plus the full
gate below.

Not applied: the two `*)` assertions, per the recommendation.

## D-3 — ambient `CLAUDECODE`

- **`tests/push_memory.bats:110-117`** —
  `says memory stays local when it has no remote, and offers /gitlore:resolve`
  now runs `CLAUDECODE=1 run --separate-stderr bash "$CMD"`, with a comment
  saying why.
- **`tests/tier_lockstep.bats:214-216`** —
  `a naked commit inside a tier is blocked by the FR11 gate` now runs
  `CLAUDECODE=1 run git -C memory/ddaanet commit -aqm "naked"`, matching the
  idiom already at `:103`.

**Evidence**, both files together:

| run | verdict |
|---|---|
| `env -u CLAUDECODE bash scripts/run-bats.sh tests/push_memory.bats tests/tier_lockstep.bats` | `bats: 26 passed, 0 failed` |
| `CLAUDECODE=1 bash scripts/run-bats.sh tests/push_memory.bats tests/tier_lockstep.bats` | `bats: 26 passed, 0 failed` |

The first is the run that fails against the unfixed tree — the checkpoint
measured it at 782 passed, 2 failed, those two being exactly these cases.

## D-4 — a successful compose on the commit path is silent

No code change, as recommended. The reasoning is now an argued point in Item
4.1's text (**`plans/index-edit-propagation/runbook.md:850-859`**): a non-empty
`$compose_result` on the commit path means the in-session compose was missed,
which is the hole this job exists to close, and one `[ -n "$compose_result" ]`
branch would say so — left silent because the `PostToolBatch` report is the
intended surface and duplicating it puts a line on every commit that repairs
anything. Phase 4's decision node now carries it rather than omitting it.

## D-5 — `CDPATH` in the test suite

- **`tests/helpers/setup.bash:5-8`** — `unset CDPATH`, with the reason. One line
  plus its comment; the six raw `$(cd … && pwd)` sites are untouched, per the
  recommendation.

**Evidence**, both against `tests/commit_memory.bats`, whose
`exits 0 when memory is clean and synced` is the case that fails through
`tests/helpers/fixtures.bash:25`:

| run | verdict |
|---|---|
| `git stash push tests/helpers/setup.bash` then `CDPATH=. bash scripts/run-bats.sh tests/commit_memory.bats` | `15 passed, 1 failed` — `cd: $'…/parent-with-memory/memory\n…/parent-with-memory': No such file or directory` at `fixtures.bash` line 25 |
| `git stash pop` then `CDPATH=. bash scripts/run-bats.sh tests/commit_memory.bats` | `16 passed, 0 failed` |

## D-6 — the up-front tier guard's comment

- **`scripts/lib/resolve.sh:901-909`** — the comment's second sentence replaced.
  It no longer justifies the loop by "the compose below writes carrier files
  inside the tier worktrees" (false for a dormant tier); it now states that the
  loop runs over every mounted tier rather than the active subset because what
  it orders against is `gitlore_sync_tiers_to_live`, which commits inside a
  mounted-but-unlisted tier too. Comment only — the loop, the guard call and the
  submodule-escape check are byte-identical.

---

## Gate

`just precommit`, run once over the finished tree with `run_in_background: true`
— **exit 0**. Every check by name:

| check | verdict |
|---|---|
| `format-docs` | ran; the only lines left over 80 columns are pinned message
texts inside inline code, the shape Item 1.1's own rc-1/rc-2 texts already
have |
| `check-distribution` | `bats: 14 passed, 0 failed` |
| `check-memory-hygiene` | 90 facts, 160 files; 0 errors across frontmatter,
name-drift, first-person, direct-naming, pre-rename, broken-reference and
volatile-state; 32 pre-existing `deictic` warnings |
| `check-docs-links` | 49 decisions, 111 files; 0 across all nine checks |
| `check-version` | `in sync (0.7.1)` |
| `lint` (`lint-shell`) | `137 files clean` |
| `test-unit` | `bats: 784 passed, 0 failed` |
| `test-integration` | `bats: 72 passed, 0 failed` |

Sentinels, all four carrying this tree's input hash `3456471586 1074094`
(recomputed by hand from `gate-inputs-hash`'s own pipeline and compared):
`check-distribution` 12:33:21, `lint` 12:34:25, `test-unit` 12:43:03,
`test-integration` 12:43:50 — each postdating the last edit to any gated input
(~12:32).

**One anomaly, resolved rather than assumed away.** At 12:39:49, while this
run's `test-unit` was still in flight, `test-unit` and `test-integration` both
carried `89124467 1074092` — a hash two bytes off this tree's and matching no
state this session produced, written in the same second by something outside
this run. Not trusted: the verdict above is read from the run's own stdout, and
the sentinels were re-read afterwards, by which time this run had overwritten
both with the correct hash. It is consistent with a concurrent session's gate
run sharing the gitdir, and is worth knowing about before the next session reads
a sentinel as authoritative.

## Commits

Four, not the three the dispatch named. The extra one is forced by a real
dependency: this report has to carry commit 3's hash, which does not exist until
commit 3 is made, so the report is its own commit. Nothing was resplit — commits
1-3 carry exactly the contents specified.

| # | hash | subject | contents |
|---|---|---|---|
| 1 | `f98dff1` | `✅ Item 1.1 — assert the agent remedy sentences` | D-2's two assertions, D-6's comment |
| 2 | `25ced81` | `✅ neutralise ambient CLAUDECODE and CDPATH in the suite` | D-3, D-5 |
| 3 | `f95b95f` | `📝 record the Phase 1 boundary decisions` | the runbook: D-1, D-2's assertion lists and residual, D-4 |
| 4 | — | `📝 the Phase 1 boundary decisions report` | this file |

Commit 4's own hash is absent for the obvious reason — a file cannot name the
commit that introduces it; it is in the message returned to the dispatcher.

The subjects were written as `test:` and `docs:`; the repo's gitmoji commit-msg
hook rewrote each prefix to its emoji.

## Tree

`git status --porcelain`, after commit 4:

```
?? .bash_profile
?? .bashrc
?? .claude/agents
?? .claude/commands
?? .claude/hooks
?? .claude/launch.json
?? .claude/loop.md
?? .claude/output-styles
?? .claude/routines
?? .claude/skills
?? .claude/workflows
?? .gitconfig
?? .idea
?? .mcp.json
?? .profile
?? .ripgreprc
?? .vscode
?? .zprofile
?? .zshrc
```

No tracked file is modified or staged. Every line is an untracked sandbox
phantom dotfile, all nineteen present in this session's opening `git status` and
none touched by this work. `memory/` and the `.claude/handoff-*.md` files were
neither read nor edited.
