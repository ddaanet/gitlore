# add-tier as a direct call with a canned commit — plan

Status: awaiting approval by my human partner. Base: `dev`.

## Why

`/gitlore:add-tier` routes through an intent file (`.claude/gitlore-add-tier`)
that the `PostToolBatch` hook `scripts/cc-hooks/add-tier-batch.sh` consumes,
running `scripts/add-tier.sh` outside the sandbox. D32 justifies the route by
two reasons — the auto-mode classifier reads a submodule mutation as
self-modification, and the command sandbox has no network. D70 already answered
both for push and commit: an explicit command is what the user asked for, so the
classifier objection does not survive it, and a denied call has moved nothing,
so recovery is one turn. The intent file strands nothing a denial could lose; it
is one-shot anyway.

The mount then hands off to `gitlore:commit` for an approved summary that has
nothing to say: every staged change (`.gitmodules`, `.gitlore-tiers`, the tier
gitlink, composed index lines the tier's publishers already approved) follows
mechanically from the `/add-tier` request. D49's argument for canned merge
commits applies: no unapproved content, intention already expressed.

## Decisions to record (D71, in `docs/references/tiered-memory.md`)

- `/gitlore:add-tier` calls `gitlore-add-tier` directly, the intent in its
  existing `key=value` format on stdin through a quoted heredoc, as
  `gitlore-commit` takes its summary; the intent file and `add-tier-batch.sh`
  retire. Supersedes D32's routing; D32's mount/create convergence and
  activate-as-last-step stand.
- On a clean store, the mount commits itself in the memory root under a canned
  message, and stages the moved memory gitlink in the parent like the commit
  path does. Subject `mount <tier> tier from <url>` (create:
  `create <tier> tier at <url>`), body the tier's routing description.
- A clean store gets the canned commit, carrying exactly the mount. A store with
  unapproved work pending before the call gets no canned commit, and the mount
  is left staged for the next approved `gitlore:commit`: the recomposed
  `MEMORY.md` would fold the unapproved index edits in (D49's guard, D43's
  staged-pair discipline).
- Step 3 triage moves (local facts routed into the tier) are judgement and keep
  the `gitlore:commit` approval path.
- Rejected alternatives to name: keeping the intent file and hook with a canned
  commit added (a hook commit sits against D70's wording for no gain) · the
  agent running `gitlore-commit` with a canned summary (an approval round with
  no content) · a rubric-graded mount summary (grades behaviour the skill does
  not specify) · the intent as `--options` or JSON arguments (shell quoting of a
  free-text description, and a new parser for the one that exists).

## Probe before step 1

Settle how the call runs: whether a sandboxed `gitlore-commit` / `gitlore-push`
works today in a real session, and whether a sandboxed `git submodule add` of an
https and an ssh url reaches the network through the proxy. The answer picks the
`commands/add-tier.md` instruction — run sandboxed, or run with the sandbox
disabled as `commands/install.md` does — and is recorded in the D71 argument
with the CC version it was verified against.

## Steps

Each step is one commit, gated by `just precommit`, reviewed at medium.

1. **Decision.** D71 into `docs/decisions.md` (Tiered memory group: conclusion
   lines and rejected names) and its argument into `tiered-memory.md`; mark
   D32's routing paragraph superseded. `docs/design.md` Architecture lines that
   describe the intent file and the `PostToolBatch` add-tier hook are restated.
2. **Script.** `bin/gitlore-add-tier` entry point; `scripts/add-tier.sh` reads
   the intent from stdin instead of the IPC file, same parser, keeps the url
   scheme allowlist (input is still agent-supplied), composes and reports itself
   (the helper `add-tier-batch.sh` calls today), and on a clean store ends with
   the canned commit carrying exactly the mount, then stages the parent gitlink.
   Red tests first, per behaviour: the stdin intent drives the mount; a clean
   store gets the canned commit carrying exactly the mount; a store with pending
   work gets no canned commit and the mount left staged; the parent gitlink is
   staged; the url refusal still fires.
3. **Retire the hook.** Delete `add-tier-batch.sh`, its `hooks/hooks.json`
   entry, the intent filename in `.gitignore`, and every reference: the
   `git grep -E 'gitlore-add-tier|add-tier-batch'` list outside
   `docs/changelog/` is the sweep's input (`craft:removing-cleanly`). The grep
   misses the D57 report-once text in `docs/references/index-composition.md`,
   which is restated too: the mount size line measured "after the mount hook's
   own compose", "keyed by nothing: the intent file is consumed", and the
   rejected alternative's "the intent file being consumed when it fires". Its
   once-only basis becomes the script's compose-stamp refresh (D71).
4. **Command and eval.** Rewrite `commands/add-tier.md` steps 2 and 4: call the
   script, relay its report, no `gitlore:commit` hand-off for the mount; triage
   moves still go through it. Return scenario `03-add-tier` to a single turn and
   `tests/evals/asserts/add-tier.sh` to grading the canned commit (message
   subject, the mount's paths, nothing else in it, gitlink staged, no
   `gitlore:commit` Skill call needed), undoing the two-turn assertions of the
   add-tier eval commit. Run the eval at k=5.
5. **Changelog** entry under `docs/changelog/`.

## Out of scope

Leftover intent files in existing clones: the file is one-shot and gitignored,
so a stale one is inert once no hook reads it; no migration.
