# Tiered Memory — Slice 3-i-a (nested-tier propagation-in + routing) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a shared memory *tier* (a git submodule nested inside the `gitlore-memory` submodule) discovered and fast-forwarded at `SessionStart`, and advertise its self-described routing to the agent — so a portable fact authored in another repo *arrives* here, and the agent knows the tier exists and what it is for. No index composition and no commit/push lockstep yet.

**Architecture:** `SessionStart` (after the existing memory submodule is materialized and synced) enumerates the memory store's own `memory/.gitmodules` — *every* entry there is a tier, by enclosure, no name constant — initializes/checks-out each, fast-forwards it toward its remote (propagation-in), and reads the consumer-local activation manifest `memory/.gitlore-tiers` to report each *active* tier's frontmatter `description:` into the standing `additionalContext` (routing guidance). All new logic is small shell helpers in `scripts/lib/` plus a block appended to `scripts/cc-hooks/session-start.sh`; behavior is pinned by `bats`.

**Tech Stack:** POSIX-ish bash (targets bash 3.2 / macOS + Linux), `git` submodule/worktree plumbing, `jq`, `awk`, `bats` (>= 1.5.0, `run --separate-stderr`), ShellCheck.

## Global Constraints

- **No hardcoded tier name.** Tiers are discovered from `memory/.gitmodules`; there is no tier analogue of `GITLORE_SUBMODULE_NAME`. (D17: "discovery by enclosure".)
- **No new marker text in either `MEMORY.md`.** This slice writes no memory index content at all.
- **Never block parent git or the session.** All new SessionStart work degrades to a `systemMessage` notice and `exit 0` on failure; it must never abort `session-start.sh` under `set -euo pipefail` (guard every `git` that may fail).
- **Clear leaked git env before any nested `git -C`.** Git hooks/commands inherit repo-local `GIT_*` vars scoped to the parent; a nested `git -C <tier>` inherits `GIT_COMMON_DIR`/`GIT_OBJECT_DIRECTORY` and silently retargets the tier's store. `session-start.sh` is not a git hook (it runs from CC), so it does not currently `unset`; any code path that could run under leaked env must clear the full set (`unset $(git rev-parse --local-env-vars)`). See `reference_git_hook_env_leak`, `reference_submodule_escape_to_parent`.
- **Guard submodule escape.** Operate on a tier only when `[ -e "$tierpath/.git" ]`; a `git -C` into an unchecked-out submodule path walks up to the enclosing repo and corrupts it (`reference_submodule_escape_to_parent`).
- **ShellCheck-clean.** `make lint` (or `scripts/lint-shell.sh`) must pass; a comment starting `# shellcheck` that is not a real directive fails lint (`reference_shellcheck_comment_directive`).
- **Register every new suite in `make test`.** An unlisted `.bats` file silently never runs (`feedback_test_the_invocation_path`).

**Out of scope for this plan (deliberately deferred, plan-late):**
- **Branch-model unification, then tier commit + push lockstep.** The branch model is **decided**: memory and every tier check out **detached at `live`** — one commit path, no named working branch (D17 "Branch model — detached at `live`"). Unifying the *memory* submodule onto that model is a Plan-03-level refactor slice of its own (`session-start.sh` checkout, `sync_memory_to_live`, `resolve.sh`), landing *before* tier lockstep, which then rides the unified path nearly for free. Still open for those later slices (not this one): one approval summary per memory episode vs. per tier; whether the memory submodule needs its own recursing `pre-commit`/`pre-push` or the parent gate drives it.
- **3-ii** index composition (splice/mirror, manifest ordering, `PostToolUse` recompose + validation).
- **3-iii** `/gitlore:add-tier`.

---

### Task 1: Characterization spike — a nested tier under the memory submodule

Before writing propagation code, pin *how git actually behaves* when a submodule is added inside the (already-a-submodule) memory store, including the D11 linked-worktree case. The rest of this plan and all of 3-i-b depend on these facts; this task turns unknowns into a fixture + a pinned characterization test.

**Files:**
- Create: `tests/helpers/tier-fixtures.bash`
- Create: `tests/tier_discovery.bats` (characterization cases only in this task)
- Modify: `Makefile` (add `tier_discovery.bats` to the test list) — confirm the exact list variable first with `grep -n bats Makefile`.

**Interfaces:**
- Produces: `make_tier_in_memory [tier_subpath] [bare_seed]` — a bats helper that, given a repo already built by `make_parent_with_memory`, creates a bare tier remote, `git submodule add`s it at `memory/<tier_subpath>` (default `ddaanet`) with `--name <tier_subpath>`, seeds a `MEMORY.md` with frontmatter `description:`, and commits inside the memory submodule using the blessed sentinel `GITLORE_MEMORY_COMMIT=1`. Leaves the parent staged (mirrors `make_parent_with_memory`'s contract).
- Produces (findings): documented answers recorded as comments at the top of `tier-fixtures.bash` — the nested gitdir path (expected `<parent>/.git/modules/gitlore-memory/modules/<tier>`), whether `git -C memory submodule add` works when `memory` is a linked worktree (`git worktree add`), and whether the tier checks out cleanly from a session-less linked worktree.

- [x] **Step 1: Observe the mechanics in a scratch repo (spike, not committed)**

Run these by hand in a throwaway dir (use the absolute scratchpad path, not `/tmp` — `reference_tmpdir_unset_unsandboxed`) and record each output; they answer the four Global-Constraints/lockstep unknowns:

```bash
D=/tmp/claude-1000/-Users-david-code-gitlore/f19d5835-954b-4ce8-90fc-c2dec4f26c2a/scratchpad/tier-spike
rm -rf "$D"; mkdir -p "$D"; cd "$D"
git init -q parent && cd parent
git config protocol.file.allow always
# ... build a bare memory + `git submodule add` it at memory/ (mirror fixtures.bash) ...
# Then, INSIDE the memory submodule, add a nested tier:
git init -q --bare "$D/ddaanet.git"
( cd "$D/seed" && git init -q && echo '---' > /dev/null )   # seed a MEMORY.md w/ frontmatter, push to ddaanet.git
git -C memory -c protocol.file.allow=always submodule add --name ddaanet "$D/ddaanet.git" ddaanet
# RECORD: where did the nested gitdir land?
ls -la .git/modules/gitlore-memory/modules/            # expect: ddaanet/
cat memory/ddaanet/.git                                # expect: gitdir: ../../.git/modules/gitlore-memory/modules/ddaanet
# RECORD: does it work through a LINKED memory worktree? (D11)
git -C .git/modules/gitlore-memory worktree add --detach "$D/parent2/memory" live 2>&1 | tail -3
```

Record the actual paths/errors — they set the assertions below and confirm whether a tier can be checked out **detached at `live`** through a linked-worktree memory store (the decided branch model — D17), which is the one materialization risk the later slices inherit.

- [x] **Step 2: Write the fixture helper `make_tier_in_memory`**

Encode the *observed* layout. Skeleton (fill the recorded paths):

```bash
#!/usr/bin/env bash
# Nested-tier fixtures. Findings (Task 1 spike, 2026-07-18):
#   nested gitdir: <RECORD>/.git/modules/gitlore-memory/modules/<tier>
#   linked-worktree add: <RECORD ok/err>
make_tier_in_memory() {
  local tier="${1:-ddaanet}" mempath="memory"
  local bare="$TMP_REPO/.bare-$tier.git"
  local seed; seed="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-tier-seed.XXXXXX")"
  git init -q -b main "$seed"
  ( cd "$seed"
    git config user.email test@example.com; git config user.name Test
    printf -- '---\ndescription: "org-wide facts for %s projects"\n---\n\n# %s tier index\n' "$tier" "$tier" > MEMORY.md
    git add MEMORY.md; git commit -q -m "Initial $tier" )
  git clone -q --bare "$seed" "$bare"; rm -rf "$seed"
  git -C "$mempath" -c protocol.file.allow=always submodule add --name "$tier" "$bare" "$tier" >/dev/null 2>&1
  ( cd "$mempath/$tier" && git config user.email test@example.com && git config user.name Test && git branch live )
  # Blessed commit inside the memory submodule so the FR11 gate admits it.
  GITLORE_MEMORY_COMMIT=1 git -C "$mempath" commit -q -m "Add $tier tier"
}
```

- [x] **Step 3: Write the characterization test pinning the observed layout**

```bash
@test "make_tier_in_memory places the nested gitdir under the memory module store" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  [ -e memory/ddaanet/.git ]
  [ -d .git/modules/gitlore-memory/modules/ddaanet ]
  grep -q '^description:' memory/ddaanet/MEMORY.md
  # the tier is registered in the memory store's OWN .gitmodules, not the parent's
  git config --file memory/.gitmodules --get submodule.ddaanet.path
  ! git config --file .gitmodules --get submodule.ddaanet.path
}
```

- [x] **Step 4: Run it and register the suite**

Run: `bats tests/tier_discovery.bats` → PASS. Then add `tier_discovery.bats` to `make test` and run `make test` to confirm it is discovered (`feedback_test_the_invocation_path`).

- [x] **Step 5: Commit**

```bash
git add tests/helpers/tier-fixtures.bash tests/tier_discovery.bats Makefile
git commit -m "test: characterize nested-tier mount under memory submodule (D17 3-i-a)"
```

---

### Task 2: Discover + fast-forward nested tiers at SessionStart (propagation-in)

**Files:**
- Modify: `scripts/lib/util.sh` (add `gitlore_tier_paths`)
- Modify: `scripts/cc-hooks/session-start.sh` (tier materialize + ff block, after the memory ff/dirty block around line 168, before `emit_session_json`)
- Modify: `tests/tier_discovery.bats` (add propagation cases)

**Interfaces:**
- Consumes: `make_parent_with_memory`, `make_tier_in_memory` (Task 1); `gitlore_memory_path`, `gitlore_git` (util.sh).
- Produces: `gitlore_tier_paths <mempath>` → prints each tier's path relative to `<mempath>` (one per line), read from `<mempath>/.gitmodules`; prints nothing (exit 0) when there is no `.gitmodules`.

- [x] **Step 1: Write the failing test for `gitlore_tier_paths`**

```bash
@test "gitlore_tier_paths lists tiers from the memory store's own .gitmodules" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  source "$PLUGIN_ROOT/scripts/lib/util.sh"
  run gitlore_tier_paths memory
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

@test "gitlore_tier_paths is empty when the memory store has no tiers" {
  make_parent_with_memory
  source "$PLUGIN_ROOT/scripts/lib/util.sh"
  run gitlore_tier_paths memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [x] **Step 2: Run to verify failure**

Run: `bats tests/tier_discovery.bats -f tier_paths` → FAIL (`gitlore_tier_paths: command not found`).

- [x] **Step 3: Implement `gitlore_tier_paths` in util.sh**

```bash
# Print each tier submodule's path (relative to the memory worktree), one per
# line, read from the memory store's OWN .gitmodules. Discovery is by enclosure:
# every submodule registered inside the memory store is a tier — there is no
# tier-name constant (D17). No output (exit 0) when there is no nested .gitmodules.
# Args: $1 = memory worktree path.
gitlore_tier_paths() {
  local mempath="$1"
  [ -f "$mempath/.gitmodules" ] || return 0
  git config --file "$mempath/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | awk '{ print $2 }'
}
```

- [x] **Step 4: Run to verify pass**

Run: `bats tests/tier_discovery.bats -f tier_paths` → PASS.

- [x] **Step 5: Write the failing test for SessionStart propagation-in**

A tier remote gains a new commit after the tier is mounted here; a fresh SessionStart must fast-forward the local tier to include it and leave the working tree **detached at `live`** (the decided branch model — D17). After SessionStart, local `live` and the detached HEAD both equal the remote commit, and HEAD is *not* on a branch.

```bash
@test "SessionStart ff's a mounted tier and leaves it detached at live (propagation-in)" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  # Author a new tier commit directly in the bare remote's live branch.
  work="$(mktemp -d)"; git clone -q "$TMP_REPO/.bare-ddaanet.git" "$work"
  ( cd "$work" && git checkout -q -B live && echo "- [x](x.md) — y" >> MEMORY.md \
      && git commit -aqm "remote tier fact" && git push -q origin live )
  remote_sha="$(git -C "$work" rev-parse HEAD)"
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]   # local live ff'd
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]   # HEAD at live
  ! git -C memory/ddaanet symbolic-ref -q HEAD                    # detached, no branch
}
```

- [x] **Step 6: Run to verify failure**

Run: `bats tests/tier_discovery.bats -f propagation` → FAIL (local `live` still at the mount SHA).

- [x] **Step 7: Implement the SessionStart tier block**

Insert after the memory dirty/ff block (~line 168), before `emit_session_json`. Every `git` is guarded so a bad tier never aborts the session:

```bash
# Nested tiers (D17 3-i-a): materialize + fast-forward each tier submodule inside
# the memory store so a portable fact authored in another repo arrives here.
# Discovery is by enclosure — every entry in memory/.gitmodules is a tier. Tiers
# use the detached-at-live branch model (D17): no named working branch, HEAD is
# detached at live. Propagation-in only; commit/push lockstep is a later slice.
while IFS= read -r tier; do
  [ -n "$tier" ] || continue
  tierpath="$mempath/$tier"
  # Materialize if this worktree never checked the tier out. Guard submodule
  # escape: only operate once the tier working tree exists.
  if [ ! -e "$tierpath/.git" ]; then
    gitlore_git -C "$mempath" submodule update --init -- "$tier" >&2 \
      || { add_sysmsg "gitlore: tier '$tier' could not be initialized; skipped."; continue; }
  fi
  [ -e "$tierpath/.git" ] || continue
  # ff local `live` from the remote's `live` — ff-only by construction (a
  # refspec fetch into a branch ref refuses a non-fast-forward without '+'), and
  # allowed only because `live` is never checked out AS a branch (we detach).
  # Missing remote / divergence is not fatal to the session; writes are a later slice.
  git -C "$tierpath" fetch -q origin "live:live" 2>/dev/null || true
  # Detach the working tree at live (the tier branch model — no named branch).
  if git -C "$tierpath" show-ref --verify --quiet refs/heads/live; then
    gitlore_git -C "$tierpath" checkout -q --detach live 2>/dev/null || true
  fi
done < <(gitlore_tier_paths "$mempath")
```

Note: `fetch origin live:live` ff-updates the local `live` ref and refuses a non-ff — the ff-only guarantee for free. It works precisely because tiers never check `live` out as a branch (git refuses to update a checked-out branch via fetch); the immediately-following `checkout --detach live` keeps HEAD off the branch.

- [x] **Step 8: Run to verify pass**

Run: `bats tests/tier_discovery.bats -f propagation` → PASS. Then full-file: `bats tests/tier_discovery.bats` → all PASS, and `bats tests/cc_hook_session_start.bats` → still green (no regression to the memory-only path).

- [x] **Step 9: Lint + commit**

```bash
bash scripts/lint-shell.sh
git add scripts/lib/util.sh scripts/cc-hooks/session-start.sh tests/tier_discovery.bats
git commit -m "feat: fast-forward nested tiers at SessionStart (D17 3-i-a propagation-in)"
```

---

### Task 3: Advertise active-tier routing guidance in additionalContext

**Files:**
- Modify: `scripts/lib/util.sh` (add `gitlore_active_tiers`)
- Modify: `scripts/cc-hooks/session-start.sh` (append routing guidance to `protocol_ctx`)
- Modify: `scripts/lib/index-sync.sh` is *not* touched — reuse `gitlore_get_frontmatter_description` from it by sourcing (already sourced? confirm; if not, source it in session-start.sh).
- Modify: `tests/tier_discovery.bats` (routing cases)

**Interfaces:**
- Consumes: `gitlore_tier_paths` (Task 2); `gitlore_get_frontmatter_description` (index-sync.sh).
- Produces: `gitlore_active_tiers <mempath>` → prints the tier paths listed in `<mempath>/.gitlore-tiers`, in file order, trimmed of surrounding whitespace, skipping blank lines; nothing (exit 0) when the manifest is absent. (Presence/validation against the mounted set is a 3-ii concern; here it only gates *advertising*.)

- [x] **Step 1: Write the failing test for `gitlore_active_tiers`**

```bash
@test "gitlore_active_tiers reads the manifest in order, skipping blanks" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  printf 'ddaanet\n\n' > memory/.gitlore-tiers
  source "$PLUGIN_ROOT/scripts/lib/util.sh"
  run gitlore_active_tiers memory
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

@test "gitlore_active_tiers is empty when no manifest exists" {
  make_parent_with_memory
  source "$PLUGIN_ROOT/scripts/lib/util.sh"
  run gitlore_active_tiers memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [x] **Step 2: Run to verify failure**

Run: `bats tests/tier_discovery.bats -f active_tiers` → FAIL (command not found).

- [x] **Step 3: Implement `gitlore_active_tiers`**

```bash
# Print the tier paths listed in the activation manifest memory/.gitlore-tiers,
# in file order, one per line, whitespace-trimmed, skipping blank lines. The
# manifest is the deliberate activation+precedence surface (listed = active);
# no output (exit 0) when it is absent. (D17)
# Args: $1 = memory worktree path.
gitlore_active_tiers() {
  local manifest="$1/.gitlore-tiers" line
  [ -f "$manifest" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    # trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] && printf '%s\n' "$line"
  done < "$manifest"
}
```

- [x] **Step 4: Run to verify pass**

Run: `bats tests/tier_discovery.bats -f active_tiers` → PASS.

- [x] **Step 5: Write the failing test for routing guidance in additionalContext**

```bash
@test "SessionStart advertises an active tier's frontmatter description as routing guidance" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  printf 'ddaanet\n' > memory/.gitlore-tiers
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ddaanet")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("org-wide facts for ddaanet")'
}

@test "SessionStart does not advertise a mounted-but-unlisted (dormant) tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  # No manifest → tier is dormant, not advertised.
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  ! ( echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("ddaanet")' )
}
```

- [x] **Step 6: Run to verify failure**

Run: `bats tests/tier_discovery.bats -f "routing guidance"` → FAIL (no `ddaanet` in additionalContext).

- [x] **Step 7: Implement routing guidance in session-start.sh**

After the tier propagation block (Task 2), before `emit_session_json`, build the guidance and append to `protocol_ctx` (which `emit_session_json` already emits as `additionalContext`). Source `index-sync.sh` near the other sources at the top if `gitlore_get_frontmatter_description` is not already available.

```bash
# Routing guidance (D17): advertise each ACTIVE tier (listed in the manifest)
# and its self-described purpose so the agent routes portable facts correctly.
# A mounted-but-unlisted tier is dormant and intentionally not advertised.
tier_guidance=""
while IFS= read -r tier; do
  [ -n "$tier" ] || continue
  tierpath="$mempath/$tier"
  [ -e "$tierpath/.git" ] || continue
  desc=$(gitlore_get_frontmatter_description "$tierpath/MEMORY.md" 2>/dev/null || true)
  if [ -n "$desc" ]; then
    tier_guidance="$tier_guidance
  - memory/$tier/ — $desc"
  else
    tier_guidance="$tier_guidance
  - memory/$tier/"
  fi
done < <(gitlore_active_tiers "$mempath")

if [ -n "$tier_guidance" ]; then
  protocol_ctx="$protocol_ctx

gitlore memory tiers (write a portable fact into the matching tier directory; project-local facts stay in memory/):$tier_guidance"
fi
```

- [x] **Step 8: Run to verify pass**

Run: `bats tests/tier_discovery.bats -f "routing guidance"` and `-f dormant` → PASS. Full file green: `bats tests/tier_discovery.bats`. Regression: `bats tests/cc_hook_session_start.bats` green.

- [x] **Step 9: Lint + commit**

```bash
bash scripts/lint-shell.sh
git add scripts/lib/util.sh scripts/cc-hooks/session-start.sh tests/tier_discovery.bats
git commit -m "feat: advertise active-tier routing guidance at SessionStart (D17 3-i-a)"
```

---

### Task 4: Dogfood — mount `ddaanet` for real and confirm propagation-in + routing

Not a code task; the required real-world check before declaring 3-i-a done (`feedback_dogfood_early`). Uses this repo's actual memory submodule.

**Files:** none (operational).

- [x] **Step 1: Stand up a real `ddaanet` remote and mount it (create flow)**

Create an empty `ddaanet` submodule inside `memory/` with a seeded `MEMORY.md` carrying a real frontmatter `description:`, create+push its remote (org-scoped; mirror `create-remote.sh`'s visibility/naming choices — confirm with David whether the org tier is private), and **do not** commit the parent yet. The git mutations inside the memory submodule run via the `!`-shell (the agent cannot; strict-sandbox/classifier — `feedback_strict_sandbox_git`, `reference_memory_gate_commit_path`).

- [x] **Step 2: Activate it and restart the session**

Append `ddaanet` to `memory/.gitlore-tiers`; start a fresh Claude Code session in this repo.

- [x] **Step 3: Confirm propagation + routing**

Verify the SessionStart notice/`additionalContext` advertises `memory/ddaanet/` with its description, and that `git -C memory/ddaanet log` shows the remote's `live` (fast-forwarded). Record findings in the D17 changelog.

- [x] **Step 4: Capture the open lockstep questions the dogfood surfaces**

The moment you author a fact into `memory/ddaanet/` you will hit the deferred 3-i-b territory (it won't commit/push with the tier). Note concretely what the dogfood shows about the `live`-model-for-tiers and summary-granularity questions — this is the input to the 3-i-b plan. Do **not** build lockstep here.

---

## Self-Review

**Spec coverage (against D17 3-i-a scope):**
- Discovery by enclosure → Task 2 (`gitlore_tier_paths` reads `memory/.gitmodules`). ✓
- Propagation-in (ff) → Task 2 SessionStart block. ✓
- Routing guidance, self-describing, active-only → Task 3 (`gitlore_active_tiers` + frontmatter `description:` → `additionalContext`). ✓
- Mount vs create, manifest-last → exercised in Task 4 dogfood (create flow) and by the fixtures. ✓
- Nested-mount mechanics / linked-worktree risk → Task 1 spike. ✓
- Commit/push lockstep, composition, `/add-tier` → explicitly deferred (Out of scope), each with its open questions named. ✓

**Placeholder scan:** Task 1 is a genuine spike; its Step 1 records values that Step 2/3 pin — this is intentional characterization, not a code placeholder. Steps that emit code show the code. No "TBD"/"handle edge cases" left in code steps. The branch model is decided (detached-at-`live`, D17), not an assumption — Task 2's code detaches explicitly.

**Type/name consistency:** `gitlore_tier_paths` and `gitlore_active_tiers` are defined in util.sh (Task 2/3) and consumed by the SessionStart blocks and tests under those exact names; `make_tier_in_memory` / `make_parent_with_memory` are the fixture names used throughout; `.gitlore-tiers` and the `memory/<tier>/MEMORY.md` frontmatter `description:` match D17. `gitlore_get_frontmatter_description` matches `scripts/lib/index-sync.sh`.

**Known soft spot:** the only real risk is Task 1's territory — whether git places and resolves a submodule-under-a-submodule cleanly, especially through a linked-worktree memory store (D11). The branch model is settled (detached-at-`live`), so there is no branch-strategy ambiguity left in Tasks 2/3; if Task 1 finds nested checkout misbehaves in a linked worktree, that constrains *materialization* (Task 2's `submodule update --init`), not the ff/detach or routing logic. This is why the spike leads and lockstep is a separate plan.
