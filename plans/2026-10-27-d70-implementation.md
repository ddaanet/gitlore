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
  paragraphs grouped under a `== <tier> ==` / `== memory ==` header per store
  when more than one store changed), then the protocol — show the summary, end
  the turn, and on the user's approving reply run
  `gitlore-commit-memory <<'EOF'` from the repo root with the approved text
  verbatim. The skill body becomes the clause's only copy. Tests: the skill
  ships, and its body carries the review directive and the section format.
- Invariant: the keys still work; nothing yet calls the names or the skill.

## 2. `commit-memory.sh` takes the summary in the call

- Pre: bare invocation commits on an approval file judged by freshness; the sync
  restamps the message file on failure.
- Post: the summary is read from stdin, the only input; `-m`, `-F` and bare mode
  are gone. A terminal on stdin, or an empty or all-whitespace summary, exits 2
  before any store access, the usage error pointing at `/gitlore:commit`; every
  other refusal that needs a summary does too. No message file exists at any
  point: each commit reads its store's section, extracted from the summary
  string by a function (bash 3.2 has no associative arrays), on
  `git commit -F -`; a prepared merge keeps git's own `MERGE_MSG`. This
  supersedes the draft's `-F -` call syntax and its temporary-file transport.
  Freshness arm, every `touch "$msgfile"`, the restamp block and
  `rm -f "$msgfile"` gone; `gitlore_commit_msg_file`,
  `gitlore_commit_msg_freshness` gone from `util.sh`, `gitlore_approval_present`
  reduced to a string check or inlined.
- Post (per-store messages): a summary with no `== <store> ==` line is one
  message, valid only when one store has changes. Otherwise the script splits it
  on header lines (`memory` for root, a tier's mount name for a tier) and
  commits each section verbatim in its own store, tiers before root. It refuses
  (exit 2, nothing committed, pointing at `/gitlore:commit`) when a store with
  changes has no section, a section names a store with nothing to commit or not
  mounted, or a store appears twice. Tier changes alone give root the canned
  index commit the merge path makes; with root changes too, the index update
  rides in root's own commit.
- Red first: an empty and an all-whitespace stdin each exit 2 with nothing
  committed; each refusal arm of the section check; a two-store run lands each
  section in its own store and no other store's text; no file left under
  `.claude/` after a successful run or a refusal. Suites seeding the message
  file are rewritten to pipe the summary on stdin (list in the removals file);
  `commit_memory_retry.bats` goes.
- Invariant: the trigger-file batch still works until commit 3 — it now passes
  its message file on stdin and keeps its own trigger bookkeeping.

## 3. Hook commit path and store gate retire

- Post: `memory-commit-batch.sh` and its `hooks.json` entry,
  `memory-pre-commit`, `emit-memory-gate.sh` and its `SessionStart` call, every
  `GITLORE_MEMORY_COMMIT=1` site, `gitlore_commit_trigger_file`, the
  `.gitignore` lines and the listed tests are gone; batch-naming comments fixed.
  Evals assert on the memory log and the absence of an in-turn commit, not on
  the message file or trigger, and on the `Skill` tool_use for `gitlore:commit`
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
Each writes its report to a named file. The main thread reviews diffs, runs the
gate in the background and commits.

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
