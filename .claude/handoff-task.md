# Task — 2026-07-22 15:42 +0200

## Current task

**Next slice: happy-path evals** covering the finished tier flow, the recall
round trip, and the add-tier round trip ([[feedback_evals_happy_path]]). Evals
live in `tests/evals/`, sentinels in `scripts/run-gate.sh`; `just precommit` is
fast, `just prerelease` adds evals and is slow.

Nothing is in flight. Working tree clean at `f716a76`, `make test` 450 green,
shellcheck clean across 106 files.

### Done this session

**PreCompact ledger reset (FR16/D18) verified**, closing the last open item from
the previous session. Both halves: the ledger file was gone from
`.git/modules/gitlore-memory/` after the compaction, and a body fetched *before*
it came back as a fresh fetch rather than an "already in this context" skip.
Native recall feeding the ledger is still unexercised — no "Recalled N memories"
has fired since the hook was built.

**D17 slice 3-iii `/gitlore:add-tier` built and committed** (`de36ba9`):

- `scripts/add-tier.sh` — parse intent → validate → (create: seed + push) →
  mount → detach at `live` → report
- `scripts/cc-hooks/add-tier-batch.sh` — PostToolBatch, one-shot, reports on
  systemMessage + additionalContext
- `commands/add-tier.md` — flat under `commands/`
- `tests/add_tier.bats` (31) + `tests/cc_hook_add_tier.bats` (9)

The agent writes `.claude/gitlore-add-tier` as `key=value` lines (`mode`, `name`,
`url`, `description`) and never runs git. The trigger-file route was already the
FR11 pattern, but a **second independent reason** forced it here that the design
had not named: mounting a tier *clones*, and the command sandbox has no network —
satisfying the classifier alone would not have been enough.

Both modes end **mounted but INACTIVE** and make no commit inside memory;
activation stays the deliberate `memory/.gitlore-tiers` edit. `mode=create`
pushes `main` **then** `live` so the remote default settles on `main` — a `live`
default gets checked out as a branch and the ff-only `fetch origin live:live`
refuses forever. A tier name with whitespace is refused up front: it would mount
fine but the line-oriented manifest could never list it.

**Url scheme allowlist added** (`f716a76`) after a background security review
reported "command injection via git-remote-ext". **The finding was not
reproducible** — two claims were conflated:

- *shell injection* — no; the url is a quoted argument after `--`, never
  interpolated, no `eval`
- *transport selection* — git already answers it. `protocol.ext.allow` defaults
  to `never`; probed git 2.47.3, `git submodule add -- "ext::sh -c 'touch X'" p`
  dies with `fatal: transport 'ext' not allowed` and nothing runs. Forcing
  `protocol.ext.allow=always` still produced no execution in the probe.

`check_url` was added anyway, for a reason specific to this design rather than to
fix the report: **the hook runs outside the agent's command sandbox and has
network**, so a url the agent supplies reaches further than one the agent could
use itself. Resting that bound on a git default the user can change is the wrong
place for it. Allows `http`/`https`/`ssh`/`git`/`file`, scp-like
`[user@]host:path`, local paths; refuses a leading `-` and any `helper::address`
form. Called at three sites (create pushes to a supplied url before mounting and
may derive a different one from `gh`).

**Live evidence gained:** writing the new tier memory's index line made the 3-ii
composition hook mirror it down into `memory/ddaanet/MEMORY.md` on the spot, and
the FR11 gate committed memory *and* the tier from one approved summary —
3-ii and the tier lockstep working against the real store, not a fixture.

### Not dogfooded

`add-tier-batch.sh` is a **new** PostToolBatch registration, and CC freezes hook
event registration at session start — it could not fire this session. Same
constraint that held active recall back last time. It needs a fresh session and a
real second tier remote, not a fixture.

## Unpushed

`main` is **30 commits ahead of `origin/main`** (at `4d54f52`), carrying 19
memory and 3 tier commits. A parent push publishes all three in lockstep via
`pre-push`. Backlog goes back to the start of 3-ii. Raised twice; the user has
not asked for the push, so it stays pending — it is outward-facing.

## Open decisions

- **Presence-authority — file set or index authoritative over a pointer line's
  presence?** Still gates coverage/prune/dedup. The recall ledger now produces
  the usage evidence that question was waiting on.
- **Index→frontmatter sync has no keyword-density validation.** The index line is
  canonical and overwrites each file's `description:`; both feed CC's recall
  classifier, so a teaser-style line silently degrades passive recall. Candidate
  fifth compose validation.
- **Root `MEMORY.md` is 19.4KB against a 24.4KB limit** — it *grew* today. Line
  56 (the gitlore project-state line) is 3812 bytes on its own, ~20% of the whole
  index. What is left is semantic curation, not trimming; probably its own
  focused session.
- **Tier divergence is detected but not resolvable** — the resolve continuation
  derives its store from `gitlore_memory_path` and cannot target a tier; the
  state file would need to carry the store path.
- **`/gitlore:resolve` does not compose** — an index merged by the resolve
  continuation composes only on the next batch or session.
- **`release` depends on a plugin-defined `prerelease`** — the fix belongs in
  `ddaanet/claude-plugin-dev`, not this repo's vendored copy; today releases go
  `just prerelease release`.

## Deferred nit

The live recall refusal text reads "REFUSED — nothing was read. the request names
entries that do not resolve. Nothing was read." — the phrase twice, plus a
lowercase sentence start. The exact string is likely asserted in the bats suite;
fix message and tests together when next touching `recall-batch.sh`.

## Environment gotcha hit twice

`git add -A` under the sandbox fails with `error: .bash_profile: can only add
regular files…` — a phantom home dotfile the sandbox surfaces. Retry with
`dangerouslyDisableSandbox: true`, and `rm -f .git/index.lock` first, since the
failed add strands it.
