# Deliverable review — code partition (fresh, after the fix pass)

## Scope

Plan `index-edit-propagation`, range `b6dbe92..HEAD` at `7d20aab`. Files in
scope:

- `scripts/lib/resolve.sh`, `scripts/lib/index-sync.sh`,
  `scripts/lib/index-compose.sh` and `scripts/lib/util.sh`;
- `scripts/resolve.sh`;
- `scripts/cc-hooks/` — `index-compose.sh`, `index-sync-post.sh`,
  `index-sync-pre.sh`, `add-tier-batch.sh`, `session-start.sh` and
  `relay-drain.sh`;
- `hooks/hooks.json`.

Out of scope: `justfile` and the two `check-*.py` scripts.

The baseline is `outline.md` §B–D, as amended by `runbook.md` (FR-F), with
`relay-redesign.md` superseding D51. The new code from the fix pass got the most
attention: `7485483`, `081e364`, `e36e7fc`, `38de36b` and `7d20aab`.

No suite or `just` recipe ran. What did run:

- one single bats case: `commit_memory.bats` "a commit that landed a tier and
  then failed on memory's index retries to completion" (ok);
- two throwaway bats probes under `/tmp/claude-1000/drc-root/tests/`, which
  symlinks the real `scripts/` and `tests/helpers/`;
- two shell probes under `/tmp/claude-1000/drc probe/` (the path has a space).

**Probe debris to remove.** The first relay probe ran against a plain `git init`
store. As m1 explains, that sent 122 files named `gitlore-relay-S1-a{0,1,2}-*`
into this repository's own `.git/`. The sandbox classifier refused my cleanup.
They are inert: no real session id is `S1`, and nothing drains the parent
gitdir. To remove them:

```sh
G=/Users/david/code/gitlore/.git
find "$G" -maxdepth 1 -type f -name 'gitlore-relay-S1-a[012]-*' -delete
ls "$G" | grep -c '^gitlore-relay-' # prints 0 when they are gone
```

**Counts: Critical 0 · Major 2 · Minor 5**

## Prior findings status

Sources: the 2026-09-12 aggregate (C/M numbering) and its code partition
(code-M, code-m).

- **C1 / code-M4** (the pin guard refuses the retry of a half-landed commit):
  resolved. `gitlore_stage_landed_tiers` works from a landing record. Verified
  by the single bats case above, and by a probe of the untested variant (the
  tier `live` advance fails on a ref lock): the retry exits 0 and stages the
  gitlink.
- **C2 / code-M1** (read-merge-write race between parallel hooks): resolved.
  Reports are write-once files with unique names. A probe of 40 concurrent
  writer processes against 30 interleaved drains, over a spaced gitdir, ran
  three times: every body was delivered exactly once and nothing was left over.
- **M1 / code-M2** (the drain unlinks a report written between its read and its
  `rm`): resolved by construction. The drain removes only names it listed, and
  `.tmp` files are excluded.
- **M2 / code-M3** (the drain was gated on an index change): resolved.
  `relay-drain.sh` runs on every main-thread batch and takes no baseline.
- **M3 / code-m4** (markers keyed by agent only): resolved. Names carry the
  sanitized session, and both drains enumerate their own session only.
- **M4 / code-M5** ("stage the gitlink by hand" was the overwrite itself):
  resolved. The remedy now adopts the carrier into root first. Its wording still
  has a gap (m5).
- **M5** (the take and the continuation staged after a failed up projection):
  resolved. Both now record nothing. The walk-back introduces Major 1.
- **M6** (no concurrent test): resolved at the code level. Two concurrency cases
  exist (`index_sync.bats:972`, `cc_hook_index_compose.bats:321`). Their quality
  belongs to the test partition.
- **M7** (`CLAUDE.md` gate paragraph): prose partition, not assessed here.
- **code-m1 / Minor** (approval left stale on failure paths): resolved, since
  non-merge failures now restamp. Two residuals remain (m2, m3).
- **code-m2 / Minor** (adoption composes up when the pin already records HEAD):
  resolved by the short-circuit in `gitlore_adopt_recovered_merge`.
- **code-m3 / Minor** (unquoted printed staging command): resolved. Both
  adoption remedies quote `"%s"`.
- **Minor** (stale "the redirect below is the single write" comment): resolved;
  the comment is gone.
- **Minor** (`index-compose.sh` "only gitlore_compose calls it"): resolved; the
  comment now names the pin guard.
- **Minor** (non-fatal `agent_id` read untested, fatal reads not argued):
  resolved. There is a fallback case in each hook suite, and `index-sync-pre.sh`
  argues its fatal read. The session read in `index-sync-post.sh` is now
  non-fatal too.
- **Minor** ("sixth untracked file" in the `index-sync.sh` comment): resolved;
  the comment is gone.

## Critical

None.

## Major

### 1. A defect in the arriving carrier makes a failed take unrepairable where the remedy points, and blocks every push

- **Where:** `scripts/lib/resolve.sh:1778-1787` (`gitlore_adopt_tier_into_root`,
  the walk-back arm) and `scripts/resolve.sh:179-200` (`rest_unadopted_tier`).
  Reached through `gitlore_push_stores` (`resolve.sh:1309`, `:1334`) and hence
  `scripts/git-hooks/pre-push:59`.
- **Axes:** functional correctness, error signaling.
- **Requirement:** D50 (compose up and stage the pair, or stage nothing), and
  printed remedies that can actually be carried out.
- **Mechanism.** `gitlore_compose_up` refuses through `gitlore_compose_check`.
  That check validates every index, the checked-out carrier included (rule 1:
  duplicate pointer; rule 4: a stray non-bullet line; rule 6: a welded line).
  When the refusal lies in the carrier that just arrived, the walk-back does
  three things:
  1. It checks the tier out at the pre-take commit, which does not hold the
     defect.
  2. It prints problem lines naming `memory/<tier>/MEMORY.md`.
  3. It says "Fix the store, then run /gitlore:merge again".

  The file it names is clean in the worktree, because the defect exists only in
  `live`. So every later take goes through `gitlore_adopt_advanced_live`, checks
  out `live`, refuses again and walks back again. `gitlore_push_stores` runs
  that take whenever a tier's `live` is ahead of HEAD, so the gate refuses every
  `/gitlore:push` and every parent `git push`. The only way out by hand is to
  check out `live`, fix the carrier and commit. But the commit path's pin guard
  refuses a tier ahead of its pin, and no printed remedy describes that route.
  The same applies to a merge synthesis carrying such a defect, via
  `rest_unadopted_tier` ("Fix the store, then run /gitlore:merge to adopt").

  Before the fix pass the take staged anyway, and the defect surfaced as a
  non-fatal compose refusal on a store the user could edit. The overwrite hazard
  M5 described was real, but it needed a later compose-down over a re-texted
  line. This failure blocks publishing outright.
- **Reproduced.** Probe `probe2.bats` used the real `merge-memory.sh` and
  `push-memory.sh` on the `merge_memory.bats` fixture, with a tier remote given
  two commits that each append `- [dup](dup.md)`.

  | Step | Output |
  |---|---|
  | Take | exit 1: `memory/ddaanet/MEMORY.md: duplicate pointer path dup.md` … "Fix the store, then run /gitlore:merge again" |
  | Tier state | `HEAD = pin = a11bbf7`, `live = 5c37068` |
  | `grep -c dup.md memory/ddaanet/MEMORY.md` | 0 |
  | `push-memory.sh` | exit 1, same three lines |
- **Impact.** One malformed commit that another consumer publishes to a shared
  tier stops this repository's memory publishing and parent pushes. The remedy
  names a file that has nothing wrong with it. Rule 6 (two bullets welded onto
  one line) is what appending to a carrier with no trailing newline produces, an
  ordinary hand edit on the tier remote.
- **Fix direction.** Split the problem lines by file. When a refusal names the
  tier's own carrier, the walk-back remedy must say the defect is in the tier's
  `live`. It must also give the commands to fix it there, or the push gate must
  not make a take whose arrival cannot be adopted fatal to publishing what this
  repository already has.

### 2. `|| tier_unadopted=1` turns off errexit for all of `compose_merged_indexes`, and a failed root staging reads as "the root index could not take the tier"

- **Where:** `scripts/resolve.sh:247`; the function's last command at `:152`;
  the consequences at `:278`, `:308` and `:318`.
- **Axes:** error signaling, robustness, functional correctness.
- **Requirement:** D50 on the continuation. Every failure path must be
  observable as what it is.
- **Mechanism.**
  - Called in an `||` list, the function runs with errexit suspended throughout,
    and its status is its last command's status.
  - When the up projection succeeds, that last command is
    `gitlore_git -C "$memroot" add -- MEMORY.md`.
  - So an `index.lock` on memory that outlasts `gitlore_git`'s ~10 s of retries
    sets `tier_unadopted=1` for a tier that was adopted.
  - The continuation then commits the merge and skips the gitlink staging and
    the bookkeeping commit. It clears the merge state and advances `live`.
  - Last, `rest_unadopted_tier` checks the tier out at its old pin, while root
    `MEMORY.md` still holds the up-projected block, unstaged.
  - The printed line says "Fix the store, then run /gitlore:merge". Nothing
    about the store needs fixing, and the lock is never named as the cause.

  At `b6dbe92` the bare call aborted under `set -e` before the commit, and the
  merge state survived for the retry. The failing tail
  `gitlore_git -C "$store" add -A` is now swallowed too.

  For memory's own merge (`merged_tier` empty), the same failure calls
  `rest_unadopted_tier "$memroot" ""`, which prints "tier '' stays on the merge
  commit". If the lock clears before `git commit`, that commit also lands
  without the composed index staged.
- **Reproduced (mechanism).** Probe `p2.sh` extracted the real
  `compose_merged_indexes` with `sed` and ran it under `set -euo pipefail`.
  Stubs: `gitlore_compose_up` returns 0; `gitlore_git` fails only on
  `add -- MEMORY.md`. The call then printed `merged_tier=tier tier_unadopted=1`,
  and the script continued past the failed add.
- **Impact.**
  - Root describes merged facts while the tier sits on its pre-merge pin.
  - The next compose-down (PostToolBatch or SessionStart) passes the pin guard
    and projects root's merged lines onto the old carrier, dangling at that pin.
  - That dirties the tier, which then makes `gitlore_adopt_advanced_live` refuse
    the retake the remedy asks for.
  - The trigger is narrow: a lock held past the retry schedule.
- **Fix direction.**
  - Return an explicit, distinct status (for example 3) from the unadopted arm,
    and check each staging command inside the function explicitly.
  - Or call the function bare, and signal "unadopted" through a variable, as
    `merged_tier` already is.

## Minor

### m1. The relay write and its drain resolve the gitdir two different ways

- **Where:** `scripts/lib/index-sync.sh:171` (`rev-parse --git-path`) against
  `:206` and `:264` (`--absolute-git-dir`).
- **Axes:** robustness, conformance (D51: "in the memory gitdir").
- **Mechanism.** For a store whose `.git` is a directory, `--git-path` prints
  `.git/gitlore-relay-…`, relative to `-C`'s directory. The write then opens
  that path relative to the caller's cwd, which is the project root in every
  hook. The file lands in the parent's gitdir and returns 0. The drain and sweep
  look in the store's absolute gitdir and never see it. The loss is silent, and
  the subagent is told nothing.

  Not reachable from gitlore's own install: `init-submodule.sh` absorbs the
  gitdir and `add-tier.sh` clones through `submodule add`, so `--git-path` is
  absolute in production. The preimage and stamp helpers share the pattern but
  pair with themselves; the relay is the first consumer that mixes the two
  forms.
- **Reproduced** by accident (see Scope): writes against a plain `git init`
  store landed in `/Users/david/code/gitlore/.git/`, and the drain found
  nothing.
- **Fix direction:** build the name from `--absolute-git-dir` in the write, as
  the drain does.

### m2. The pin-guard abort promises "the approved summary is still in place", but every remedy it prints invalidates it

- **Where:** `scripts/lib/resolve.sh:1065` and `:1068`.
- **Axes:** error signaling, clarity.
- **Mechanism.** `gitlore_commit_msg_freshness` compares the message file's
  mtime against every file under the store, tier worktrees included. Each remedy
  writes into that tree:
  - the ahead-of-pin remedy edits root `MEMORY.md`;
  - the sideways and diverged remedy checks the tier out;
  - `/gitlore:resolve` lands a merge.

  So the `touch "$msgfile"` on this arm never keeps the approval usable. After
  following the remedy, the retry is refused with "no approved commit summary",
  contrary to what the agent was just told. Requiring re-approval is correct,
  since a hand-edited root index is new content; the promise is what is wrong.
- **From the code.**

### m3. The restamp's coverage and its justification

- **Where:** `scripts/lib/resolve.sh` — the comment at `~1014-1030`, and the
  `touch "$msgfile"` arms at `:910-941` and `:1040-1151`.
- **Axes:** robustness, conformance (FR11).
- **Two gaps.**
  - **Guard failures that prepare no merge.** The comment says the stale-merge
    guard in the per-tier loop returns 1 only after preparing a merge. Several
    of its arms prepare nothing:
    - "manual intervention required";
    - the failed checkout arms of `gitlore_recover_landed_merge`;
    - the interrupted-preparation and dead-merge arms.

    If an earlier tier's recovery composed up, and a later tier fails in one of
    these arms, the approval is left stale. That is the old code-m1 residual.
  - **Concurrent writes.** A restamp at failure time also covers any write
    another agent made to memory between the freshness check and the `touch`.
    The window includes `gitlore_git`'s lock retries. The success path has the
    same window up to `add -A`, but the restamp extends the blessing to a retry
    arbitrarily later. Background subagents writing memory are the premise of
    FR-C.
- **From the code.**

### m4. The continuation's non-divergence push failures skip the rest

- **Where:** `scripts/resolve.sh:296` and `:312`, via `push_or_report`, which
  runs `exit 1` itself.
- **Axes:** functional completeness.
- **Mechanism.** With `tier_unadopted=1`, a local `HEAD:live` or origin push
  refused for a non-divergence reason exits inside `push_or_report`, before
  either `rest_unadopted_tier` call. The merge state is already cleared, so the
  tier is left on the merge commit, ahead of an unstaged pin. `live` is either
  not advanced (the local push failed) or equal to HEAD (the origin push
  failed), so `/gitlore:merge` finds nothing to adopt: `live` is not ahead of
  HEAD. The pin guard refuses every memory commit with the by-hand adoption
  remedy.

  The changelog names only two paths that leave the tier in place: a yield, and
  a pin the merge does not contain. This is a third.
- **From the code.**

### m5. The ahead-of-pin remedy under-specifies the adoption it asks for

- **Where:** `scripts/lib/index-compose.sh:358`.
- **Axes:** error signaling, clarity.
- **Mechanism.** "Bring every line of … into `MEMORY.md`, each link prefixed"
  does not say to **replace** root's existing `<tier>/` lines.
  - Appending a re-texted line leaves a duplicate pointer, and the next pass
    refuses it (rule 1).
  - It also leaves root's lines for paths the carrier dropped. The next
    compose-down projects those back into the carrier as dangling pointers.

  What `gitlore_compose_up` does is replace root's block for the tier; the
  remedy should say so.
- **From the code.**

## Checks that passed

- **Relay write** (`index-sync.sh:157-183`):
  - The name `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>` matches D51.
  - `pid` is read outside the command substitution, so it is the hook's process
    id.
  - The tag comes from a closed set, which keeps `${rest%-*-*-*}` unambiguous.
  - The occupied-name refusal comes before `mv`, so `mv`-into-directory is
    covered.
  - Every failure returns non-zero into both callers' `if !`.
  - An empty agent id is refused.
- **Relay drain:**
  - Own-session prefix only, and `-type f` excludes directories.
  - `.tmp` is excluded, and the sanitized class cannot contain `.`.
  - Enumeration is `-print0` into `read -d ''`; sorting is basename
    `LC_ALL=C sort` with no `-z` (BSD-safe).
  - It removes exactly the files it read, and `rm` failures are absorbed.
  - Session ids are fixed-length UUIDs, so one session's prefix cannot match
    another's.
- **Writer vs drainer vs sweep:**
  - The concurrent probe was clean (see Prior findings, C2).
  - The sweep's `-mtime +7` cannot touch a live write or temp.
  - SessionStart drains before it sweeps, so a session resumed after more than
    seven days still receives its own reports first.
- **`relay-drain.sh`:**
  - It is executable and registered on `PostToolBatch` in `hooks.json`.
  - Unparseable payloads and keyed runs exit 0 before any drain; the parse fails
    toward not draining.
  - It emits one `jq -n` object on both channels.
  - The residual (reports lost if the hook is killed between drain and emit) is
    stated.
- **Reporting hooks:**
  - Their drain branches are gone. They write when keyed (guarded on a non-empty
    report) and otherwise emit only.
  - The `session_id` and `agent_id` reads in the PostToolBatch hooks are
    non-fatal.
  - A failed relay write appends the "could not be staged" line to
    `additionalContext`. `index-sync-post.sh` falls back to `sysmsg` when `ctx`
    is empty.
  - `agent_id`, never `agent_type`, is used everywhere, and `add-tier-batch.sh`
    drops the keyed stamp.
- **`session-start.sh`:**
  - It reads stdin once, before the first guard exit.
  - It sources `index-sync.sh`.
  - The drain and sweep sit after the tier and compose passes and before the
    final emit, and both always return 0 under `set -e`.
- **Landing record** (`resolve.sh:913-925`, `:1143-1148`, `:1216-1246`):
  - The record is written before the tier commit and removed when that commit
    fails.
  - All records are cleared once memory's `add -A` succeeds.
  - A record is honoured only when `HEAD^` equals the record and the pin; a
    foreign commit on a failed-commit pin is refused (bats case at
    `commit_memory.bats:325`).
  - It stages the gitlink only. That is safe because the carrier in that commit
    was composed from root in the same run, or committed as-is after an rc-1
    refusal, which is what `add -A` would have staged anyway.
  - Unmaterialized tiers are skipped.
- **Retry of a tier `live` advance failure** (probe `probe.bats`, one-shot
  `live.lock`): the first run exits 1 and leaves the record; the retry exits 0
  and records the tier HEAD. The tier's `live` stays behind HEAD after the
  retry. That predates this range (a clean tier skips the advance), and
  `gitlore_repair_stranded_live` in the push gate repairs it.
- **Commit-path order:**
  1. freshness;
  2. the per-tier stale-merge loop;
  3. `gitlore_stage_landed_tiers`;
  4. the pin guard;
  5. `gitlore_compose` (rc 0 proceeds, rc 1 reports and proceeds, rc 2 and `*`
     abort);
  6. `gitlore_sync_tiers_to_live`;
  7. `add -A`, clearing records;
  8. commit.

  All messages go to stderr through `gitlore_say_for_agent_or_user`. The
  `local pin_problems` declaration is split from its assignment, so the status
  is not lost.
- **Take failure arm** (`resolve.sh:1776-1788`):
  - Nothing is staged or committed, and the tier is checked out at the pre-take
    commit.
  - Both callers propagate `|| return 1`.
  - A failed checkout prints a quoted, absolute, runnable command.
  - The walk-back loses no work: both take paths refuse a dirty tier first, and
    `gitlore_compose_up` writes only root through temp+mv.
- **Continuation:**
  - An unadopted tier skips the gitlink staging and bookkeeping.
  - The rest runs only on the two exit-0 paths.
  - The pin-ancestry check uses `rev-parse -q --verify "${pin}^{commit}"` before
    `merge-base`.
  - The checkout-failure remedy is quoted and absolute.
- **`gitlore_adopt_recovered_merge`:**
  - It short-circuits when `:<rel>` equals the tier's HEAD.
  - A failed up projection stages nothing.
  - It stages the named pair only, never `add -A`.
- **`gitlore_compose_check_pins` ahead-of-pin arm:**
  - It guards `merge-base` with `rev-parse -q --verify`.
  - The absolute path is computed in the capture subshell.
  - The staging command is quoted.
- **Portability and whitespace.** Nothing new needs bash 4 or GNU tools:
  `find -maxdepth/-delete/'!'/-print0`, `date +%s`, `${BASHPID:-$$}` and
  `tr -c 'A-Za-z0-9-' '_'` all work on BSD and bash 3.2. Every path expansion in
  the new code is quoted, and tier lists are read line by line with `read -r`.
- **Citations.** No code comment added in the fix pass cites `plans/`, a runbook
  item or a finding id.
