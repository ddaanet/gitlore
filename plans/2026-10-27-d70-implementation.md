# D70 implementation — the agent commits memory itself

Executes [the D70 draft](2026-10-26-memory-commit-simplification-decision.md)
and [its removals list](2026-10-26-memory-commit-simplification-removals.md).
The removals list is the file-and-line inventory; this plan only orders it into
commits and states each commit's contract. Section 8 of the draft holds the
answers to its open questions: 1–4, 6 and 7 take their defaults. Question 5 is
settled on 2026-10-27, superseding the draft: the summary guidance reaches the
agent through a `gitlore:commit` skill, read when memory is to be committed; no
tool output displays it, and the commit script's usage and error messages point
at `/gitlore:commit`.

**Branch.** `d70-memory-commit`, cut from `dev` on approval of this plan. Each
commit passes `just precommit` and lands with memory in lockstep. One code
review of the branch against `dev` before it merges back (at most one re-review,
per the shared triage rule).

**Order.** Additive first, then the contract change, then removals, then docs.
Each commit leaves the suite green and the plugin usable, so the branch can stop
at any boundary.

## 1. Plugin `bin/` names and the `gitlore:commit` skill (additive)

- Pre: no `bin/`; callers resolve the `gitlore.*Command` keys.
- Post: `bin/gitlore-commit-memory`, `bin/gitlore-push-memory`,
  `bin/gitlore-merge-memory`, mode 755, each `exec`s its `scripts/` script
  resolved from its own physical location (no `CLAUDE_PLUGIN_ROOT`); `bin`
  listed in `dist.include`; `tests/plugin_distribution.bats` asserts each name
  ships, is `-x`, and reaches its script (run by path in a non-gitlore dir,
  assert the script's guard exit).
- Post: `skills/commit/SKILL.md`, its description self-triggering on pending
  memory changes and a request to commit memory. Body: the review directive and
  the summary format (the text of `reference/memory-approval-clause.txt`, its
  paragraphs grouped under a `== <tier> ==` / `== memory ==` header per store,
  always — one store or several), then the protocol — show the summary, end the
  turn, and on the user's approving reply run `gitlore-commit-memory <<'EOF'`
  from the repo root with the approved text verbatim. The skill body becomes the
  clause's only copy. Tests: the skill ships, and its body carries the review
  directive and the section format.
- Invariant: the keys still work; nothing yet calls the names or the skill.

## 2. `commit-memory.sh` takes the summary in the call

- Rename (settled 2026-10-29): the `bin/` names become `gitlore-commit`,
  `gitlore-push`, `gitlore-merge`, matching the skills; every later mention of
  `gitlore-*-memory` in this plan reads as the short name.

- Pre: bare invocation commits on an approval file judged by freshness; the sync
  restamps the message file on failure.
- Post: the summary is read from stdin, the only input; `-m`, `-F` and bare mode
  are gone. A terminal on stdin, or an empty or all-whitespace summary, exits 2
  before any store access, the usage error pointing at `/gitlore:commit`; every
  other refusal that needs a summary does too. No message file exists at any
  point: each store's section, extracted from the summary string by a function
  (bash 3.2 has no associative arrays), is piped to that store's `git commit` on
  stdin; a prepared merge keeps git's own `MERGE_MSG`. Freshness arm, every
  `touch "$msgfile"`, the restamp block and `rm -f "$msgfile"` gone;
  `gitlore_commit_msg_file`, `gitlore_commit_msg_freshness` gone from `util.sh`,
  `gitlore_approval_present` reduced to a string check or inlined.
- Post (per-store messages): every summary carries one `== <store> ==` section
  per store with changes, a single store included; text before the first header,
  or no header at all, is refused. The script splits it on header lines
  (`memory` for root, a tier's mount name for a tier) and commits each section
  verbatim in its own store, tiers before root. It refuses (exit 2, nothing
  committed, pointing at `/gitlore:commit`) when a store with changes has no
  section, a section names a store with nothing to commit or not mounted, or a
  store appears twice. Tier-only root changes — a tier gitlink moving, and
  `MEMORY.md` lines under a tier prefix — are left out of the summary: a commit
  created at the same time carries them silently, so beside a `memory` section
  they ride in root's own commit, and alone they get a plain commit whose canned
  message names the tiers (`Index lines from <tier>, …`), distinct from the
  merge path's bookkeeping message. A root `MEMORY.md` line with a bare path is
  root content and needs the `memory` section.
- Post (no sync, settled 2026-10-28): the script commits each store on its
  checked-out branch, then attempts to fast-forward that store's local `live` to
  the new commit. It never prepares or takes a merge: when `live` cannot
  fast-forward, the run reports divergence and points at `/gitlore:merge` or
  `/gitlore:push`, exit 0: a fork is an expected condition, and the report is a
  directive (`craft:directive-writing`) naming the next act, not an error. The
  merge and push scripts gain the branch-vs-`live` step ahead of their remote
  step, so `live` carries the new commit before a push publishes it:
  fast-forward, else merge, conflicts routed to `/gitlore:resolve` as now.
  Memory with nothing to commit exits 0. Dirty memory stops being a resting
  state the commit path produces. The suites that ran the commit on a clean
  store to reach the sync drive the merge or push entry point instead.
- Red first: an empty and an all-whitespace stdin each exit 2 with nothing
  committed; a headerless summary is refused when only the tier changed, so
  nothing lands in the shared store; each refusal arm of the section check; a
  two-store run lands each section in its own store and no other store's text;
  no file left under `.claude/` after a successful run or a refusal; `live`
  fast-forwarded after a commit, and left in place with a divergence report
  naming `/gitlore:merge` or `/gitlore:push` when it cannot be, no merge
  prepared. Suites seeding the message file are rewritten to pipe the summary on
  stdin (list in the removals file); `commit_memory_retry.bats` goes.
- Post (settled 2026-10-29): the trigger-file batch path goes here, not in
  commit 3, since it cannot feed the sectioned contract —
  `memory-commit-batch.sh` and its `hooks.json` entry, its suites,
  `gitlore_commit_msg_file`, `gitlore_commit_trigger_file` and the `.gitignore`
  lines.

## 3. Hook commit path and store gate retire

- Post: `memory-pre-commit`, `emit-memory-gate.sh` and its `SessionStart` call,
  every `GITLORE_MEMORY_COMMIT=1` site and the listed tests are gone;
  batch-naming comments fixed (the batch path itself went in commit 2). Evals
  assert on the memory log and the absence of an in-turn commit, not on the
  message file or trigger, and on the `Skill` tool_use for `gitlore:commit`
  ahead of the commit. A new scenario edits a fact file for a stated reason, and
  its rubric fails a summary that retells the body or omits the reason.
- New (Q4): `SessionStart` removes a store or tier `pre-commit` byte-identical
  to `gitlore_emit_hook_wrapper … memory-pre-commit` output and unsets the
  mirrored `gitlore.hooksDir` there; any other `pre-commit` is left. Red test
  for both arms.
- Invariant: `pre-push`'s take still lands D49 bookkeeping and D52 repair (Q1).

## 4. Discovery keys retire

- Post: the three seeds in `write-settings.sh` and re-pins in `session-start.sh`
  gone; the orientation names the `gitlore:commit` skill and keeps the rule that
  a request to commit is not approval of an unseen summary; skills (`push`,
  `merge`, `memory-writing`, `resolve`) and script header comments name the
  `bin/` commands; `resolve` skill's bare retry becomes "pass the summary again,
  re-approved if the merge brought content it did not cover". Tests per the
  removals list; bats calls `"$PLUGIN_ROOT/bin/gitlore-commit-memory"` by path.
- Post: the clause file retires — `reference/memory-approval-clause.txt`,
  `gitlore_memory_approval_clause`, the `gitlore.memoryApprovalClauseFile` seed
  and re-pin, and their tests; `plugin_distribution.bats` asserts the
  review-directive literal in the skill instead.
- Invariant: `gitlore.hooksDir` still re-pinned; a grep for
  `commitCommand|pushCommand|mergeCommand` outside `docs/changelog/` and the
  `precommitCommand` hits returns nothing.

## 5. Docs

- Post: D70 line and node text from the draft's sections 3–4; D4, D12, D53, D54,
  D56 leave `decisions.md` for a changelog entry; every node edit in the
  removals list's "Decision lines and node paragraphs edited" and "Docs"
  sections; `commit-gate.md` retitled per Q6; `check-docs-links` clean, no file
  over 400 lines. The repo `CLAUDE.md` "Memory and commits" names
  `gitlore-commit-memory`.
- The draft and removals files then move nowhere: the D-entry and changelog are
  the record.

## Dispatch

Commits 1–4: one red author (Sonnet), one red reviewer (Sonnet, a different
agent), one green implementer (Sonnet for 2 and 3, whose threading and hook
edits leave choices open; Haiku for 1 and 4), reused across commits by
`SendMessage`. Commit 5: one Sonnet agent with the two plan files as its brief.
Each writes its report to a named file. A Sonnet reviewer reviews each green
diff; the main thread orchestrates, runs the gate in the background and commits.

## Dogfood (same day)

`just dogfood`, then in a fresh session in this repo: write a fact, approve a
summary, and confirm `gitlore-commit-memory` resolves on PATH and commits;
confirm a stale `pre-commit` wrapper in `memory/` is removed at session start.
Then `just evals`, in the background, before the branch review.

## After merge

A note in `/Users/david/code/handoff/inbox/` superseding the earlier brief:
handoff and precompact commit memory through `/gitlore:commit` in both modes,
the clause-file key is gone, and with commit=true the memory approval takes a
turn before the parent commit stages the pointer. Nothing else in that repo.

## Out of scope

The `handoff` implementation; a `Stop` hook nudging uncommitted memory (decided
on the eval's trigger rate); the postponed tier-line-loss design.
