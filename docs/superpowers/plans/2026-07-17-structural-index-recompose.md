# Structural Index Recompose (D17 slice 3a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a structural recompose of the root `MEMORY.md` index that guarantees every memory file has exactly one pointer line (coverage), drops lines whose file is gone (prune), and heals duplicate-path residue (dedup) — owning each line's *presence/placement*, never its *text* — run once per session at SessionStart.

**Architecture:** A new sourced library `scripts/lib/index-recompose.sh` exposes `gitlore_recompose_index <mempath>`, a pure, idempotent, write-on-change rewrite of `<mempath>/MEMORY.md`. It reuses the existing bullet parser (`gitlore_index_pairs`) and description getter (`gitlore_get_frontmatter_description`) from `index-sync.sh`, adds a generic frontmatter-field getter, and does dedup + prune + coverage in a single awk pass that preserves all non-bullet content. `session-start.sh` calls it after the live ff-merge (so it also heals union-driver residue from the merge) and surfaces a one-line notice when it changed anything.

**Tech Stack:** Bash (portable, no bashisms beyond bash 3.2), awk (POSIX subset, `length()`-based, `getline` from files), `jq` (already a dependency), `bats` 1.5+ for tests.

## Global Constraints

- Target shells: bash 3.2 (macOS default) and Linux bash — no associative-array-free tricks needed inside awk, but bash-level code must avoid bash-4 features (no `declare -A`, no `${var,,}`).
- awk must stay in the portable subset already used by `index-sync.sh`: `index()`, `substr()`, `length()`, `getline < file`; a literal `"\t"` is a real tab.
- The index-line grammar is exactly `- [<title>](<path>) — <hook>` where the separator is `) — ` (space, em-dash U+2014, space). A bullet without a parseable `](path)` and `) — ` is *malformed* and must be preserved verbatim (never pruned, deduped, or rewritten).
- The recompose owns **presence and placement only**. It must never alter the text of a line it keeps. Coverage lines are the sole exception (a net-new line has no prior text).
- Writes are **atomic and change-gated**: rewrite to a temp on the same filesystem, `cmp -s`, `mv` only if different; never leave a `.tmp` inside the memory worktree (an untracked leftover there is swept up by the FR11 gate's `git add -A`).
- Flat store only (slice 3a): scan top-level `<mempath>/*.md`, excluding `MEMORY.md`. Nested-tier subdirectories are slice 3b and out of scope here.
- `gitlore_memory_dirty` treats any working-tree change as dirty; a recompose write intentionally dirties `memory/` and rides the next parent commit (D17 "float"). This is expected, not a bug.

---

## File Structure

- **Create** `scripts/lib/index-recompose.sh` — the recompose library. One responsibility: structural rewrite of the root index. Sourced, never exec'd.
- **Create** `tests/index_recompose.bats` — unit tests for the library, following the `index_sync.bats` pattern (`setup_tmp_repo`, source the lib, operate on files in cwd with `mempath="."`).
- **Modify** `scripts/cc-hooks/session-start.sh` — source the new lib and call `gitlore_recompose_index` after the live ff-merge; add a user notice on change.
- **Modify** `tests/cc_hook_session_start.bats` — a test that SessionStart heals an uncovered/orphaned index.
- **Modify** `docs/design.md` — D17 status + changelog: slice 3a landed, SessionStart-only (PostToolUse recompose deferred to 3b), with the anti-race rationale.

`Makefile` needs no change — `UNIT_TESTS` is glob-discovered, so `tests/index_recompose.bats` is picked up automatically.

---

### Task 1: Recompose core — dedup + prune, write-on-change

**Files:**
- Create: `scripts/lib/index-recompose.sh`
- Test: `tests/index_recompose.bats`

**Interfaces:**
- Consumes: `gitlore_index_pairs <index>` (from `scripts/lib/index-sync.sh`) — prints `path<TAB>hook` per valid bullet.
- Produces:
  - `gitlore_recompose_index <mempath>` — rewrites `<mempath>/MEMORY.md` in place if and only if its canonical form differs; prints `1` to stdout when it wrote, `0` when it did not; returns `0` on success, `2` on an awk/rewrite error (leaving the index untouched). In this task it performs dedup + prune only (no coverage — `SEEDS` is empty).

- [ ] **Step 1: Write the failing tests (dedup + prune + no-op)**

Create `tests/index_recompose.bats`:

```bash
#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

SYNC="$PLUGIN_ROOT/scripts/lib/index-sync.sh"
SRC="$PLUGIN_ROOT/scripts/lib/index-recompose.sh"

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SYNC"; . "$SRC"; }
teardown() { teardown_tmp_repo; }

# A memory file with frontmatter, so coverage (Task 2) and prune have real files.
mkmem() { # $1 = filename, $2 = name, $3 = description
  printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: reference\n---\n\nbody\n' \
    "$2" "$3" > "$1"
}

@test "recompose: dedup drops a duplicate-path line, keeps the first" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n- [a again](a.md) — stale dup\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -c '](a.md)' MEMORY.md
  [ "$output" = "1" ]
  run grep -c 'hook a' MEMORY.md   # the FIRST line survived
  [ "$output" = "1" ]
}

@test "recompose: prune drops a line whose file is gone" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n- [ghost](ghost.md) — no file\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -c 'ghost.md' MEMORY.md
  [ "$output" = "0" ]
  run grep -c '](a.md)' MEMORY.md
  [ "$output" = "1" ]
}

@test "recompose: no-op on an already-canonical index returns 0 and does not write" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  before=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$before" ]
}

@test "recompose: preserves header and non-bullet lines verbatim" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\nSome prose line.\n\n- [a](a.md) — hook a\n' > MEMORY.md
  before=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$before" ]
}

@test "recompose: keeps a malformed bullet (no separator) verbatim" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [x](a.md) no separator here\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  run grep -c 'no separator here' MEMORY.md
  [ "$output" = "1" ]
}

@test "recompose: empty store (no memory files) is a no-op, never wipes the index" {
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  before=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$before" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/index_recompose.bats`
Expected: FAIL — `gitlore_recompose_index: command not found` (the lib does not exist yet).

- [ ] **Step 3: Write the minimal implementation (dedup + prune, empty coverage)**

Create `scripts/lib/index-recompose.sh`:

```bash
#!/usr/bin/env bash
# Structural recompose of the root MEMORY.md index (D17 slice 3a). Owns each
# bullet line's PRESENCE and PLACEMENT, never its TEXT. Sourced by SessionStart
# and unit-tested directly. Operations on the flat store: dedup by path, prune
# orphaned lines, seed coverage for uncovered files (coverage added in a later
# task; here SEEDS is empty). Idempotent; writes only when the canonical form
# differs. Depends on gitlore_index_pairs from index-sync.sh being sourced.

# Print the raw value of the first `<field>:` line in a file's leading
# frontmatter block (nothing if absent). $1 = file, $2 = field name. Unlike the
# description getter this does not unquote — callers that need unquoting use
# gitlore_get_frontmatter_description instead.
gitlore_frontmatter_field() {
  awk -v field="$2" '
    BEGIN { dashes = 0 }
    /^---[[:space:]]*$/ { dashes++; if (dashes == 2) exit; next }
    (dashes == 1) {
      if ($0 ~ "^" field ":") { sub("^" field ":[[:space:]]*", ""); print; exit }
    }
  ' "$1"
}

# Rewrite $1/MEMORY.md into its canonical structural form (dedup + prune +
# coverage). Prints 1 if it wrote, 0 if it did not. Returns 0 on success, 2 on
# a rewrite error (index left untouched). Never alters the text of a kept line.
gitlore_recompose_index() {
  local mempath="$1" index="$mempath/MEMORY.md"
  [ -e "$index" ] || { printf '0\n'; return 0; }

  local present covered seeds tmp
  present=$(mktemp) || { printf '0\n'; return 2; }
  covered=$(mktemp) || { rm -f "$present"; printf '0\n'; return 2; }
  seeds=$(mktemp)   || { rm -f "$present" "$covered"; printf '0\n'; return 2; }
  # Rewrite temp lives beside the index (same filesystem → atomic mv) and is
  # removed on every exit path so it never survives inside the memory worktree.
  tmp="$index.gitlore-recompose.tmp"

  # Present memory files (flat store): top-level *.md except the index itself.
  local f base
  for f in "$mempath"/*.md; do
    [ -e "$f" ] || continue
    base=$(basename "$f")
    [ "$base" = "MEMORY.md" ] && continue
    printf '%s\n' "$base" >> "$present"
  done

  # An empty present set would make awk prune every bullet — refuse to run
  # (protects against a mis-resolved mempath wiping the index).
  if [ ! -s "$present" ]; then
    rm -f "$present" "$covered" "$seeds"
    printf '0\n'; return 0
  fi

  # Paths already carrying a bullet.
  gitlore_index_pairs "$index" | cut -f1 > "$covered"

  # Coverage seeds are built in a later task; SEEDS stays empty here.
  gitlore_build_coverage_seeds "$mempath" "$present" "$covered" "$seeds"

  if ! awk -v PRESENT="$present" -v SEEDS="$seeds" '
    BEGIN {
      while ((getline p < PRESENT) > 0) if (p != "") present[p] = 1
      ns = 0
      while ((getline s < SEEDS) > 0) seed[ns++] = s
      havebullet = 0
    }
    {
      line = $0
      isbullet = 0
      if (line ~ /^- \[/) {
        isbullet = 1
        sep = ") — "; d = index(line, sep); path = ""
        if (d > 0) {
          left = substr(line, 1, d); lp = index(left, "](")
          if (lp > 0) {
            rest = substr(left, lp + 2); rp = index(rest, ")")
            if (rp > 0) path = substr(rest, 1, rp - 1)
          }
        }
        if (path != "") {
          if (!(path in present)) next     # prune orphan
          if (path in emitted) next         # dedup by path (keep first)
          emitted[path] = 1
        }
        # malformed bullet (no parseable path) falls through, kept verbatim
      }
      buf[nb++] = line
      if (isbullet) { havebullet = 1; lastbullet = nb - 1 }
    }
    END {
      for (i = 0; i < nb; i++) {
        print buf[i]
        if (havebullet && i == lastbullet)
          for (j = 0; j < ns; j++) print seed[j]
      }
      if (!havebullet)
        for (j = 0; j < ns; j++) print seed[j]
    }
  ' "$index" > "$tmp"; then
    rm -f "$tmp" "$present" "$covered" "$seeds"
    printf '0\n'; return 2
  fi

  local changed=0
  if ! cmp -s "$tmp" "$index"; then
    mv "$tmp" "$index"
    changed=1
  else
    rm -f "$tmp"
  fi
  rm -f "$present" "$covered" "$seeds"
  printf '%s\n' "$changed"
  return 0
}
```

Also add the coverage-seed builder as a **stub** in this task so `gitlore_recompose_index` can call it (Task 2 fills it in). Add this above `gitlore_recompose_index`:

```bash
# Append a seed bullet line for every present file lacking a covered bullet.
# Stub in slice 3a Task 1 (writes nothing → SEEDS empty → no coverage yet);
# implemented in Task 2. Args: $1 mempath, $2 present-file, $3 covered-file,
# $4 seeds-file (output, appended).
gitlore_build_coverage_seeds() {
  :
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/index_recompose.bats`
Expected: PASS — all six tests green (coverage-specific behavior is not exercised yet).

- [ ] **Step 5: Lint**

Run: `scripts/lint-shell.sh`
Expected: no findings for `scripts/lib/index-recompose.sh` or `tests/index_recompose.bats`.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/index-recompose.sh tests/index_recompose.bats
git commit -m "feat: structural index recompose — dedup + prune (D17 slice 3a)"
```

---

### Task 2: Coverage — seed a pointer for every uncovered file

**Files:**
- Modify: `scripts/lib/index-recompose.sh` (replace the `gitlore_build_coverage_seeds` stub)
- Test: `tests/index_recompose.bats` (add coverage tests)

**Interfaces:**
- Consumes: `gitlore_get_frontmatter_description <file>` (from `index-sync.sh`, handles quoting) and `gitlore_frontmatter_field <file> <field>` (Task 1).
- Produces: `gitlore_build_coverage_seeds <mempath> <present-file> <covered-file> <seeds-file>` — for each path in `<present-file>` not present in `<covered-file>`, appends one line `- [<title>](<path>) — <hook>` to `<seeds-file>`. `title` = frontmatter `name`, falling back to the basename without `.md`; `hook` = frontmatter `description`, falling back to `title` when the description is empty. Seed order follows the present-file order (glob-sorted).

- [ ] **Step 1: Write the failing coverage tests**

Append to `tests/index_recompose.bats`:

```bash
@test "recompose: coverage seeds a line for an uncovered file, from frontmatter" {
  mkmem a.md a "hook a"
  mkmem newfact.md new-fact "a fresh durable fact"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -F -- '- [new-fact](newfact.md) — a fresh durable fact' MEMORY.md
  [ "$status" -eq 0 ]
}

@test "recompose: coverage title falls back to basename when name is missing" {
  printf -- '---\ndescription: only a description\nmetadata:\n  type: reference\n---\nbody\n' > nonm.md
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  run grep -F -- '- [nonm](nonm.md) — only a description' MEMORY.md
  [ "$status" -eq 0 ]
}

@test "recompose: coverage hook falls back to title when description is empty" {
  printf -- '---\nname: no-desc\nmetadata:\n  type: reference\n---\nbody\n' > nd.md
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  run grep -F -- '- [no-desc](nd.md) — no-desc' MEMORY.md
  [ "$status" -eq 0 ]
}

@test "recompose: coverage line is inserted after the last existing bullet, before trailing prose" {
  mkmem a.md a "hook a"
  mkmem newfact.md new-fact "fresh fact"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n\nTrailing note.\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  # new bullet sits between the last bullet and the trailing note
  run bash -c "grep -n . MEMORY.md"
  # last bullet line comes before the seed, seed before the trailing note
  line_a=$(grep -n '](a.md)' MEMORY.md | cut -d: -f1)
  line_new=$(grep -n '](newfact.md)' MEMORY.md | cut -d: -f1)
  line_note=$(grep -n 'Trailing note' MEMORY.md | cut -d: -f1)
  [ "$line_a" -lt "$line_new" ]
  [ "$line_new" -lt "$line_note" ]
}

@test "recompose is idempotent: a second run after coverage is a no-op" {
  mkmem a.md a "hook a"
  mkmem newfact.md new-fact "fresh fact"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$output" = "1" ]
  after=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$after" ]
}
```

- [ ] **Step 2: Run the coverage tests to verify they fail**

Run: `bats tests/index_recompose.bats -f coverage; bats tests/index_recompose.bats -f idempotent`
Expected: FAIL — no coverage line is added (the builder is still a stub), so the `grep -F` assertions fail and the idempotence test sees `output = 0` on the first run.

- [ ] **Step 3: Implement the coverage-seed builder**

Replace the `gitlore_build_coverage_seeds` stub in `scripts/lib/index-recompose.sh` with:

```bash
# Append a seed bullet line for every present file lacking a covered bullet.
# title = frontmatter `name` (fallback: basename sans .md); hook = frontmatter
# `description` (fallback: title, so a description-less file still carries real
# words for retrieval). Args: $1 mempath, $2 present-file, $3 covered-file,
# $4 seeds-file (appended). The agent owns the text thereafter (D17).
gitlore_build_coverage_seeds() {
  local mempath="$1" present="$2" covered="$3" seeds="$4"
  local p title desc hook
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    grep -qxF "$p" "$covered" && continue    # already has a bullet
    title=$(gitlore_frontmatter_field "$mempath/$p" name)
    [ -n "$title" ] || title="${p%.md}"
    desc=$(gitlore_get_frontmatter_description "$mempath/$p" 2>/dev/null) || desc=""
    if [ -n "$desc" ]; then hook="$desc"; else hook="$title"; fi
    printf -- '- [%s](%s) — %s\n' "$title" "$p" "$hook" >> "$seeds"
  done < "$present"
}
```

- [ ] **Step 4: Run the full lib suite to verify it passes**

Run: `bats tests/index_recompose.bats`
Expected: PASS — all eleven tests green.

- [ ] **Step 5: Lint**

Run: `scripts/lint-shell.sh`
Expected: no findings.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/index-recompose.sh tests/index_recompose.bats
git commit -m "feat: index recompose coverage — seed a pointer per uncovered file (D17 slice 3a)"
```

---

### Task 3: Wire recompose into SessionStart + document the slice

**Files:**
- Modify: `scripts/cc-hooks/session-start.sh:149-172`
- Test: `tests/cc_hook_session_start.bats`
- Modify: `docs/design.md` (D17 body + changelog)

**Interfaces:**
- Consumes: `gitlore_recompose_index <mempath>` (Task 1/2).
- Produces: no new callable interface — SessionStart now heals the index once per session after the live ff-merge and adds a `systemMessage` line when the index changed.

- [ ] **Step 1: Write the failing SessionStart test**

First inspect the existing harness to match conventions:

Run: `sed -n '1,40p' tests/cc_hook_session_start.bats`
Expected: shows `load helpers/...`, how the hook is invoked (piping a JSON payload to `session-start.sh`), and how a memory submodule fixture is built.

Add a test modeled on the existing ones (adapt the fixture/invocation helper names to whatever that file already uses). The intent, expressed against the real hook invocation:

```bash
@test "session-start: recompose seeds a pointer for an unindexed memory file" {
  # <use this suite's existing helper to build an enabled gitlore repo whose
  #  memory submodule is checked out with a MEMORY.md and at least one *.md>
  # Add an uncovered memory file:
  printf -- '---\nname: orphaned-fact\ndescription: was never indexed\nmetadata:\n  type: reference\n---\nbody\n' \
    > "$MEMPATH/orphaned-fact.md"
  # Run SessionStart the way the other tests in this file do (same payload +
  # env: GITLORE_LAUNCHED=1, CLAUDE_PLUGIN_ROOT, CLAUDE_PROJECT_DIR):
  run_session_start   # <-- replace with this suite's actual invocation
  [ "$status" -eq 0 ]
  run grep -F -- '](orphaned-fact.md) — was never indexed' "$MEMPATH/MEMORY.md"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/cc_hook_session_start.bats -f recompose`
Expected: FAIL — the uncovered file gets no pointer (recompose is not wired in yet).

- [ ] **Step 3: Wire the call into `session-start.sh`**

Add the source line next to the other lib sources (after line 11, `source .../log.sh`):

```bash
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-recompose.sh"
```

Then, immediately **after** the dirty/ff-merge block (after the current line 168 `fi`, before the `emit_session_json` comment block at line 170), insert:

```bash
# Structural index recompose (D17 slice 3a). Runs AFTER the ff-merge so it also
# heals union-driver residue the merge may have left, on top of coverage/prune.
# It runs at SessionStart only — a cold store, before the agent authors anything
# — so it never races the agent's own index edits (a mid-session recompose could
# dedup-away a line the agent had just curated). Writes only on real drift, which
# then rides the next parent commit like any memory change (the "float", D17).
# A recompose failure must never abort SessionStart, hence `|| changed=0`.
changed=$(gitlore_recompose_index "$mempath") || changed=0
if [ "$changed" = "1" ]; then
  add_sysmsg "gitlore: healed the memory index (added/pruned pointer lines); the change rides your next commit."
fi
```

- [ ] **Step 4: Run the SessionStart test to verify it passes**

Run: `bats tests/cc_hook_session_start.bats -f recompose`
Expected: PASS — the pointer line appears in the memory `MEMORY.md`.

- [ ] **Step 5: Run the whole suite + lint**

Run: `make test && scripts/lint-shell.sh`
Expected: all bats suites PASS (previous count + the new `index_recompose.bats` cases + the new SessionStart case), no lint findings. Record the new total.

- [ ] **Step 6: Update the design doc**

In `docs/design.md`, update the D17 block and add a changelog row. Edit the D17 `Status:` line (around line 657) to record slice 3a:

> Implementation sequence: (1) authoring-time one-way sync — **done**; (2) one-time reconcile — **dogfooded 2026-07-17**; (3a) **structural recompose (coverage + prune + dedup), SessionStart-only — done 2026-07-17**; (3b) nested-tier materialization + tier-block placement/carrier mirroring — next.

In the D17 body where the recompose is described (around line 641), append a sentence recording the 3a scoping decision:

> Slice 3a runs the recompose at **SessionStart only**, not `PostToolUse` — a cold-store pass cannot race the agent's own in-session index authoring (a mid-session dedup could drop a line the agent had just curated); the `PostToolUse` trigger, and the tier-block placement + carrier mirroring it feeds, are deferred to slice 3b where a nested tier makes placement non-trivial.

Add a changelog row at the top of the changelog table:

```markdown
| 2026-07-17 | **D17 slice 3a (structural recompose) shipped.** New `scripts/lib/index-recompose.sh` exposes `gitlore_recompose_index`: dedup by path, prune orphaned lines, and seed a coverage pointer for every uncovered memory file (title from frontmatter `name`, hook from `description`), owning each line's presence/placement but never a kept line's text. Idempotent, write-on-change. Wired into `session-start.sh` after the live ff-merge (so it also heals union-driver residue), SessionStart-only to avoid racing the agent's in-session index edits — `PostToolUse` recompose and tier placement deferred to 3b. Flat store only; nested-tier scan is 3b. |
```

- [ ] **Step 7: Commit**

```bash
git add scripts/cc-hooks/session-start.sh tests/cc_hook_session_start.bats docs/design.md
git commit -m "feat: run structural index recompose at SessionStart (D17 slice 3a)"
```

---

## Self-Review

**Spec coverage (against D17's recompose paragraph):**
- (a) coverage — Task 2. ✓
- (b) prune — Task 1. ✓
- (d) dedup by path — Task 1. ✓
- (c) placement (tier blocks) + carrier mirroring — **intentionally deferred to slice 3b** (no tiers exist yet; documented in Task 3 Step 6). ✓ (scoped out, not missed)
- "recompose owns presence/placement, never text" — enforced: awk keeps kept lines verbatim; only coverage adds new lines. ✓
- "PostToolUse(Write|Edit) and SessionStart" triggers — 3a is SessionStart-only by deliberate anti-race decision, recorded in the design doc. The PostToolUse trigger moves to 3b. ✓ (documented deviation)
- "leaves memory/ dirty — expected, rides next commit" — the SessionStart notice says exactly this; no auto-commit. ✓
- union-driver residue healing — dedup runs after the ff-merge. ✓

**Placeholder scan:** every code step contains complete code. The one soft spot is Task 3 Step 1, which adapts to the existing `cc_hook_session_start.bats` helper names (invocation + fixture) that the implementer reads in-place — the Step explicitly instructs reading the file first and states the exact assertion. No `TODO`/`TBD`/"add error handling" placeholders.

**Type/name consistency:**
- `gitlore_recompose_index <mempath>` → prints `0`/`1`, returns `0`/`2` — consistent across Tasks 1 and 3.
- `gitlore_build_coverage_seeds <mempath> <present> <covered> <seeds>` — stub in Task 1, filled in Task 2, same signature.
- `gitlore_frontmatter_field <file> <field>` — defined Task 1, used Task 2.
- Reused names `gitlore_index_pairs`, `gitlore_get_frontmatter_description` match `scripts/lib/index-sync.sh` verbatim.

---

## Out of Scope (slice 3b — next plan)

- Nested-tier submodule materialization (`memory/lore`, `memory/<org>`), reusing init / FR11 gate / push-lockstep.
- Tier-block placement in the recompose (global-first ordering, project bare-path last) + mirroring a tier's lines into `memory/<tier>/MEMORY.md` and splicing them into the root index at SessionStart.
- Routing guidance in the SessionStart `additionalContext` (portable → `memory/<tier>/`, project → `memory/`).
- The `PostToolUse(Write|Edit)` recompose trigger (with anti-race handling) if 3b needs sub-session healing.
- Recursive `*.md` scan (subdirectories) for present/coverage/prune.
