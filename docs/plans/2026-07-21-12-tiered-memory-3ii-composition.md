# Tiered memory 3-ii — index composition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Splice each active tier's pointer bullets into the always-loaded root `MEMORY.md`, and mirror root-authored tier bullets back down into their carrier, so a tier's facts become recall-reachable and travel to every consumer.

**Architecture:** One pure-bash library (`scripts/lib/index-compose.sh`) does all the work: it splits an index into preamble / bullets / trailer, attributes each bullet to a mounted tier by path prefix, merges root and carrier bullets per tier, and rewrites both surfaces. Two thin callers invoke it — a new `PostToolBatch` hook and the existing `session-start.sh`. The pass is a whole-index rewrite, byte-idempotent, and fail-safe: four validations run first and any failure aborts the whole pass with every file untouched.

**Tech Stack:** bash (3.2-compatible), `jq` for hook JSON, `bats` 1.5+ for tests. No awk needed for the new path arithmetic — bash parameter expansion is whitespace-safe here and avoids the `awk '{print $2}'` class of bug.

**Spec:** `docs/superpowers/specs/2026-07-21-tier-index-composition-design.md`. **Design decision:** D17 in `docs/design.md`.

## Global Constraints

- A bullet is a line matching `^- \[` **and** containing `](` followed by a `)`. A `^- \[` line without an extractable path is *not* a bullet — it is content, and triggers validation 4 if it sits inside the bullet region.
- Composition never edits bullet *text*, never touches project bullets, never creates or deletes a memory file.
- No hook may `exit 2`. Stdout JSON parses only on `exit 0`, so every failure reports on `systemMessage` and exits 0 (D14).
- Every loop that touches a tier must guard `[ -e "$tierpath/.git" ]` before any `git -C "$tierpath"` — into an unchecked-out submodule `git -C` escapes to the enclosing repo.
- No `2>/dev/null`. Where a non-zero status is the ordinary case, guard with a test (`[ -f ]`) rather than a redirect.
- No `|| true` on a fallible command whose failure matters.
- Shell must pass `scripts/lint-shell.sh` (shellcheck). A comment may never begin with `# shellcheck` unless it is a real directive.

## Refinement of the spec, decided here

The spec says an inactive tier's block is dropped from the root because "the lines persist in the carrier". That only holds if they were mirrored while the tier was active — a root bullet added for a mounted-but-never-active tier would be silently dropped. So: **mirror down runs for every *mounted* tier; splice up runs for *active* tiers only.** This is the same data-loss argument, and the same resolution, that the commit/push lockstep already applied when it chose to commit every mounted tier rather than only the active ones.

**Text conflict rule:** when a path appears in both the root index and its carrier with different hook text, the **root** wins and is written down. The root index is canonical for a line's text (D17, settled empirically by the SPOT eval).

---

## File Structure

- **Create `scripts/lib/index-compose.sh`** — the whole mechanism, sourced by both callers and unit-tested directly. Mirrors `index-sync.sh` in shape: small pure functions, one writer.
- **Create `scripts/cc-hooks/index-compose.sh`** — `PostToolBatch` hook. Decides from `.tool_calls[]` whether the batch touched the root index or the manifest, calls the library, emits one message on both channels.
- **Modify `hooks/hooks.json`** — register the new hook on `PostToolBatch`.
- **Modify `scripts/cc-hooks/session-start.sh`** — call the library after the tier fast-forward block; rewrite the routing-guidance sentence.
- **Create `tests/index_compose.bats`** — library unit tests.
- **Create `tests/cc_hook_index_compose.bats`** — hook tests.
- **Modify `tests/helpers/tier-fixtures.bash`** — add `set_tier_manifest` and `seed_tier_bullet` factories.
- **Modify `docs/design.md`** — D17 status line + changelog row.

`make test` globs `tests/*.bats`, so both new suites are collected automatically. Verify that in Task 4 rather than assuming it.

---

### Task 1: The read-only half — parsing, attribution, validation

*Both halves of this task edit `scripts/lib/index-compose.sh` and
`tests/index_compose.bats`, and neither writes a file. They are one reviewer's
gate: "does this correctly read a store and refuse a broken one?" Keep the two
red-green cycles and the two commits — just don't split the dispatch.*

#### Part A — index splitting and bullet path arithmetic

**Files:**
- Create: `scripts/lib/index-compose.sh`
- Test: `tests/index_compose.bats`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `gitlore_bullet_path LINE` → prints the path; returns 1 if the line is not a pointer bullet.
  - `gitlore_bullet_reprefix LINE PREFIX` → prints the line with `PREFIX/` inserted before the path.
  - `gitlore_bullet_deprefix LINE PREFIX` → prints the line with a leading `PREFIX/` removed from the path; returns 1 if the path does not carry that prefix.
  - `gitlore_index_region FILE` → prints `FIRST LAST` (1-indexed bullet line numbers, space-separated), or `0 0` when the file has no bullets.
  - `gitlore_index_part FILE PART` → prints the `preamble`, `bullets`, or `trailer` part.

- [x] **Step 1: Write the failing test**

Create `tests/index_compose.bats`:

```bash
#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup

source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "bullet_path extracts the path from a well-formed bullet" {
  run gitlore_bullet_path '- [Some Title](foo_bar.md) — the hook text'
  [ "$status" -eq 0 ]
  [ "$output" = "foo_bar.md" ]
}

@test "bullet_path handles a prefixed path and a hook containing parens" {
  run gitlore_bullet_path '- [T](ddaanet/x.md) — hook (with parens) — and a dash'
  [ "$output" = "ddaanet/x.md" ]
}

@test "bullet_path rejects a non-bullet and a bullet with no link" {
  run gitlore_bullet_path '# Memory Index'
  [ "$status" -eq 1 ]
  run gitlore_bullet_path '- [just a bracketed phrase] and prose'
  [ "$status" -eq 1 ]
}

@test "bullet_path accepts a bullet with no hook separator" {
  run gitlore_bullet_path '- [T](foo.md)'
  [ "$status" -eq 0 ]
  [ "$output" = "foo.md" ]
}

@test "reprefix and deprefix round-trip, preserving title and hook" {
  line='- [Some Title](foo.md) — hook — with an em dash'
  run gitlore_bullet_reprefix "$line" ddaanet
  [ "$output" = '- [Some Title](ddaanet/foo.md) — hook — with an em dash' ]
  run gitlore_bullet_deprefix "$output" ddaanet
  [ "$output" = "$line" ]
}

@test "deprefix refuses a line that does not carry the prefix" {
  run gitlore_bullet_deprefix '- [T](foo.md) — h' ddaanet
  [ "$status" -eq 1 ]
}

@test "index_region reports the first and last bullet lines" {
  printf '# Head\n\n- [A](a.md) — x\n- [B](b.md) — y\n\nTrailing prose\n' > idx.md
  run gitlore_index_region idx.md
  [ "$output" = "3 4" ]
}

@test "index_region reports 0 0 for a bulletless index" {
  printf -- '---\ndescription: "d"\n---\n\n# Tier\n' > idx.md
  run gitlore_index_region idx.md
  [ "$output" = "0 0" ]
}

@test "index_part splits preamble, bullets and trailer" {
  printf '# Head\n\n- [A](a.md) — x\n- [B](b.md) — y\n\nTrailing prose\n' > idx.md
  run gitlore_index_part idx.md preamble
  [ "$output" = "$(printf '# Head\n')" ]
  run gitlore_index_part idx.md bullets
  [ "$output" = "$(printf -- '- [A](a.md) — x\n- [B](b.md) — y')" ]
  run gitlore_index_part idx.md trailer
  [ "$output" = "$(printf '\nTrailing prose')" ]
}

@test "index_part of a bulletless index is all preamble" {
  printf -- '---\ndescription: "d"\n---\n\n# Tier\n' > idx.md
  run gitlore_index_part idx.md bullets
  [ -z "$output" ]
  run gitlore_index_part idx.md trailer
  [ -z "$output" ]
  run gitlore_index_part idx.md preamble
  [[ "$output" == *"# Tier"* ]]
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `bats tests/index_compose.bats`
Expected: FAIL — `scripts/lib/index-compose.sh: No such file or directory`.

- [x] **Step 3: Write minimal implementation**

Create `scripts/lib/index-compose.sh`:

```bash
#!/usr/bin/env bash
# Tier index composition (D17 slice 3-ii). Splices each ACTIVE tier's carrier
# bullets into the root MEMORY.md (prefix-added) and mirrors root-authored tier
# bullets back down into every MOUNTED tier's carrier (prefix-stripped).
#
# Composition is PLACEMENT ONLY: it never edits a bullet's text, never touches
# project bullets, never creates or deletes a memory file. Line identity is the
# path prefix — no sentinel text is injected into any index.

# Print the path of a pointer bullet; return 1 if $1 is not one. A bullet is
# `- [` ... `](` PATH `)` ... — the hook (if any) is irrelevant here. Pure
# parameter expansion: no field splitting, so a path or title containing
# whitespace is safe.
gitlore_bullet_path() {
  local line="$1" rest path
  case "$line" in
    '- ['*) ;;
    *) return 1 ;;
  esac
  case "$line" in
    *']('*) ;;
    *) return 1 ;;
  esac
  rest=${line#*](}                 # "foo.md) — hook"
  case "$rest" in
    *')'*) ;;
    *) return 1 ;;
  esac
  path=${rest%%)*}
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Print $1 with "$2/" inserted before its path. Return 1 if $1 is not a bullet.
gitlore_bullet_reprefix() {
  local line="$1" prefix="$2" left rest path tail
  gitlore_bullet_path "$line" >/dev/null || return 1
  left=${line%%](*}                # "- [Title"
  rest=${line#*](}                 # "foo.md) — hook"
  path=${rest%%)*}
  tail=${rest#*)}                  # " — hook"
  printf '%s](%s/%s)%s\n' "$left" "$prefix" "$path" "$tail"
}

# Print $1 with a leading "$2/" removed from its path. Return 1 if $1 is not a
# bullet or its path does not carry that prefix.
gitlore_bullet_deprefix() {
  local line="$1" prefix="$2" left rest path tail
  path=$(gitlore_bullet_path "$line") || return 1
  case "$path" in
    "$prefix"/*) ;;
    *) return 1 ;;
  esac
  left=${line%%](*}
  rest=${line#*](}
  tail=${rest#*)}
  printf '%s](%s)%s\n' "$left" "${path#"$prefix"/}" "$tail"
}

# Print "FIRST LAST", the 1-indexed line numbers of the first and last pointer
# bullet in $1, or "0 0" when there are none. Space-separated so callers can
# `read` the pair instead of doing tab arithmetic in a parameter expansion.
gitlore_index_region() {
  local line first=0 last=0 n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if gitlore_bullet_path "$line" >/dev/null; then
      [ "$first" -eq 0 ] && first=$n
      last=$n
    fi
  done < "$1"
  printf '%s %s\n' "$first" "$last"
}

# Print one part of an index: "preamble" (before the first bullet), "bullets"
# (the region between the first and last bullet, inclusive), or "trailer"
# (after the last bullet). A bulletless index is ALL preamble — which is the
# day-one state of a freshly seeded tier carrier.
gitlore_index_part() {
  local file="$1" part="$2" first last
  read -r first last < <(gitlore_index_region "$file")
  if [ "$first" -eq 0 ]; then
    case "$part" in
      preamble) cat "$file" ;;
      *) : ;;
    esac
    return 0
  fi
  case "$part" in
    preamble) [ "$first" -gt 1 ] && sed -n "1,$((first - 1))p" "$file" ;;
    bullets)  sed -n "$first,${last}p" "$file" ;;
    trailer)  sed -n "$((last + 1)),\$p" "$file" ;;
  esac
  return 0
}
```

- [x] **Step 4: Run test to verify it passes**

Run: `bats tests/index_compose.bats`
Expected: PASS, 10 tests.

- [x] **Step 5: Lint and commit**

```bash
scripts/lint-shell.sh
git add scripts/lib/index-compose.sh tests/index_compose.bats
git commit -m "feat: index splitting and bullet path arithmetic (D17 3-ii)"
```

---

#### Part B — attribution and the four validations

**Files:**
- Modify: `scripts/lib/index-compose.sh`
- Modify: `tests/index_compose.bats`
- Modify: `tests/helpers/tier-fixtures.bash`

**Interfaces:**
- Consumes: `gitlore_bullet_path`, `gitlore_index_region`, `gitlore_index_part` (Part A); `gitlore_tier_paths MEMPATH` and `gitlore_active_tiers MEMPATH` (existing, `scripts/lib/util.sh`).
- Produces:
  - `gitlore_tier_of PATH TIERS` → prints the first path component when it names a tier in the newline-separated list `TIERS`; prints nothing and returns 1 otherwise.
  - `gitlore_compose_check MEMPATH` → prints one human-readable problem per line and returns 1 if the store cannot be safely composed; prints nothing and returns 0 otherwise.

- [x] **Step 6: Write the failing test**

First add the fixture factories. Append to `tests/helpers/tier-fixtures.bash`:

```bash
# Write the tier activation manifest. Args: the active tier names, in
# precedence order. With no args the manifest is created empty.
set_tier_manifest() {
  : > memory/.gitlore-tiers
  local t
  for t in "$@"; do printf '%s\n' "$t" >> memory/.gitlore-tiers; done
}

# Append a bullet to a tier carrier's MEMORY.md (and create the file it names,
# so the store looks realistic). Args: $1 = tier, $2 = file name, $3 = hook.
seed_tier_bullet() {
  local tier="$1" file="$2" hook="$3"
  printf -- '- [%s](%s) — %s\n' "${file%.md}" "$file" "$hook" >> "memory/$tier/MEMORY.md"
  printf -- '---\nname: %s\ndescription: ""\n---\n\nbody\n' "${file%.md}" > "memory/$tier/$file"
}

# Append a bullet to the ROOT index. Args: $1 = path (may be tier-prefixed),
# $2 = hook.
seed_root_bullet() {
  printf -- '- [%s](%s) — %s\n' "$(basename "${1%.md}")" "$1" "$2" >> memory/MEMORY.md
}
```

Then append to `tests/index_compose.bats` (it must now also `load helpers/fixtures` and `load helpers/tier-fixtures`, and `source .../util.sh` for the tier helpers — update the file header accordingly):

```bash
@test "tier_of attributes a prefixed path to a mounted tier" {
  tiers=$(printf 'ddaanet\nlore\n')
  run gitlore_tier_of "ddaanet/x.md" "$tiers"
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

@test "tier_of rejects a bare path and an unknown prefix" {
  tiers=$(printf 'ddaanet\n')
  run gitlore_tier_of "x.md" "$tiers"
  [ "$status" -eq 1 ]
  run gitlore_tier_of "gone/x.md" "$tiers"
  [ "$status" -eq 1 ]
}

@test "check passes on a well-formed store" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "project_overview.md" "the project"
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check fails on a duplicate path in the root index" {
  make_parent_with_memory
  seed_root_bullet "dup.md" "first"
  seed_root_bullet "dup.md" "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
  [[ "$output" == *"dup.md"* ]]
}

@test "check fails when the manifest lists a tier that is not mounted" {
  make_parent_with_memory
  set_tier_manifest ghost
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *"not mounted"* ]]
}

@test "check fails on a root bullet whose prefix names no mounted tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "removed_tier/orphan.md" "leftover"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"removed_tier/orphan.md"* ]]
}

@test "check fails on a non-bullet line inside the bullet region" {
  make_parent_with_memory
  seed_root_bullet "a.md" "x"
  printf '\nSome interleaved prose\n\n' >> memory/MEMORY.md
  seed_root_bullet "b.md" "y"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"interleaved"* ]]
}

@test "check inspects tier carriers too, not just the root" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet dup.md "first"
  seed_tier_bullet ddaanet dup.md "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "a mounted but unlisted tier is dormant, not an error" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
}
```

- [x] **Step 7: Run test to verify it fails**

Run: `bats tests/index_compose.bats`
Expected: FAIL — `gitlore_tier_of: command not found`.

- [x] **Step 8: Write minimal implementation**

Append to `scripts/lib/index-compose.sh`:

```bash
# Print the first path component of $1 when it names a tier listed in the
# newline-separated $2; return 1 otherwise (a bare path, or a prefix that
# matches no mounted tier).
gitlore_tier_of() {
  local path="$1" tiers="$2" head t
  case "$path" in
    */*) head=${path%%/*} ;;
    *) return 1 ;;
  esac
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    [ "$t" = "$head" ] && { printf '%s\n' "$head"; return 0; }
  done <<EOF
$tiers
EOF
  return 1
}

# Print one problem per line and return 1 when $1's store cannot be composed
# safely; print nothing and return 0 otherwise. Every problem is reported, not
# just the first: a user fixing a broken store wants the whole list.
#
# The four rules (D17 3-ii):
#   1. no duplicate pointer path within any single index;
#   2. every manifest entry names a MOUNTED tier;
#   3. every root bullet with a "/" names a mounted tier — an unattributable
#      prefix has no carrier to survive in, so dropping it would be data loss;
#   4. no non-blank non-bullet line inside an index's bullet region — the
#      layout rule would relocate it and lose its position.
gitlore_compose_check() {
  local mempath="$1" mounted active problems="" tier file
  mounted=$(gitlore_tier_paths "$mempath")
  active=$(gitlore_active_tiers "$mempath")

  # Rule 2 — a listed tier must be mounted.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    if ! printf '%s\n' "$mounted" | grep -qxF -- "$tier"; then
      problems="${problems}the tier manifest lists '$tier', which is not mounted in $mempath/.gitmodules
"
    fi
  done <<EOF
$active
EOF

  # Rules 1 and 4 — for the root index and every mounted tier carrier.
  file="$mempath/MEMORY.md"
  [ -f "$file" ] && problems="${problems}$(gitlore_compose_check_index "$file")"
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    problems="${problems}$(gitlore_compose_check_index "$mempath/$tier/MEMORY.md")"
  done <<EOF
$mounted
EOF

  # Rule 3 — root bullets only; a carrier's own bullets are bare by construction.
  if [ -f "$mempath/MEMORY.md" ]; then
    local line path
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in */*) ;; *) continue ;; esac
      if ! gitlore_tier_of "$path" "$mounted" >/dev/null; then
        problems="${problems}root index line '$path' has a prefix naming no mounted tier — it is a leftover from a removed tier and must be fixed by hand
"
      fi
    done < "$mempath/MEMORY.md"
  fi

  [ -z "$problems" ] && return 0
  printf '%s' "$problems" | grep -v '^$'
  return 1
}

# Rules 1 and 4 for a single index file. Prints problems; always returns 0 (the
# caller aggregates).
gitlore_compose_check_index() {
  local file="$1" first last n=0 line path seen=""
  read -r first last < <(gitlore_index_region "$file")
  [ "$first" -eq 0 ] && return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if path=$(gitlore_bullet_path "$line"); then
      if printf '%s\n' "$seen" | grep -qxF -- "$path"; then
        printf '%s: duplicate pointer path %s\n' "$file" "$path"
      fi
      seen="$seen
$path"
    elif [ "$n" -gt "$first" ] && [ "$n" -lt "$last" ] && [ -n "${line//[[:space:]]/}" ]; then
      printf '%s: interleaved non-bullet line %s inside the pointer block\n' "$file" "$n"
    fi
  done < "$file"
  return 0
}
```

Note `${line//[[:space:]]/}` is bash-only (not POSIX sh) — the file is `#!/usr/bin/env bash` and every caller sources it from bash, so this is fine.

- [x] **Step 9: Run test to verify it passes**

Run: `bats tests/index_compose.bats`
Expected: PASS, 19 tests.

- [x] **Step 10: Lint and commit**

```bash
scripts/lint-shell.sh
git add scripts/lib/index-compose.sh tests/index_compose.bats tests/helpers/tier-fixtures.bash
git commit -m "feat: tier attribution and compose validations (D17 3-ii)"
```

---

### Task 2: The compose pass — mirror down, splice up, idempotent

**Files:**
- Modify: `scripts/lib/index-compose.sh`
- Modify: `tests/index_compose.bats`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces:
  - `gitlore_compose MEMPATH` → runs the check, then rewrites the root index and every mounted tier carrier. On check failure: prints the problems, writes nothing, returns 1. On success: prints one summary line per file it actually changed (`composed <path>`), returns 0.

- [x] **Step 1: Write the failing test**

Append to `tests/index_compose.bats`:

```bash
@test "splice up: an active tier's carrier bullets appear prefixed in the root" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "project_overview.md" "the project"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [shared](ddaanet/shared.md) — a portable fact' memory/MEMORY.md
  # Tier block precedes project lines.
  tierline=$(grep -n 'ddaanet/shared.md' memory/MEMORY.md | cut -d: -f1)
  projline=$(grep -n 'project_overview.md' memory/MEMORY.md | cut -d: -f1)
  [ "$tierline" -lt "$projline" ]
}

@test "mirror down: a root-authored tier line lands in the carrier, unprefixed" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/new_fact.md" "authored in the root"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [new_fact](new_fact.md) — authored in the root' memory/ddaanet/MEMORY.md
  ! grep -qF 'ddaanet/new_fact.md' memory/ddaanet/MEMORY.md
}

@test "compose is byte-idempotent" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "ddaanet/other.md" "root authored"
  seed_root_bullet "project_overview.md" "the project"
  gitlore_compose memory
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.1"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.1"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]                       # nothing changed → nothing reported
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.1"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.1"
}

@test "the root's hook text wins over a divergent carrier hook" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale carrier text"
  seed_root_bullet "ddaanet/shared.md" "fresh curated text"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '— fresh curated text' memory/ddaanet/MEMORY.md
  ! grep -qF 'stale carrier text' memory/ddaanet/MEMORY.md
  [ "$(grep -c 'shared.md' memory/MEMORY.md)" -eq 1 ]
}

@test "manifest order is tier block order" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory lore
  set_tier_manifest lore ddaanet
  seed_tier_bullet ddaanet d.md "dd fact"
  seed_tier_bullet lore l.md "lore fact"
  gitlore_compose memory
  l=$(grep -n 'lore/l.md' memory/MEMORY.md | cut -d: -f1)
  d=$(grep -n 'ddaanet/d.md' memory/MEMORY.md | cut -d: -f1)
  [ "$l" -lt "$d" ]
}

@test "a dormant mounted tier is dropped from the root but keeps its carrier lines" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  set_tier_manifest                       # deactivate
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  grep -qF -- '- [shared](shared.md) — a portable fact' memory/ddaanet/MEMORY.md
}

@test "a dormant tier still receives mirror-down, so no root line is lost" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest                       # mounted, never active
  seed_root_bullet "ddaanet/rescued.md" "would be dropped"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [rescued](rescued.md) — would be dropped' memory/ddaanet/MEMORY.md
  ! grep -qF 'ddaanet/rescued.md' memory/MEMORY.md
}

@test "preamble and trailer are preserved verbatim" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [A](a.md) — x\n\n<!-- footer -->\n' > memory/MEMORY.md
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  head -1 memory/MEMORY.md | grep -qF '# Memory Index'
  tail -1 memory/MEMORY.md | grep -qF '<!-- footer -->'
}

@test "project bullets keep their order and are never rewritten" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two\n' > memory/MEMORY.md
  gitlore_compose memory
  run gitlore_index_part memory/MEMORY.md bullets
  [ "$output" = "$(printf -- '- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two')" ]
}

@test "a failing check writes nothing at all" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ghost
  seed_tier_bullet ddaanet shared.md "a portable fact"
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `bats tests/index_compose.bats`
Expected: FAIL — `gitlore_compose: command not found`.

- [x] **Step 3: Write minimal implementation**

Append to `scripts/lib/index-compose.sh`:

```bash
# Print the merged bullet list for tier $2 under store $1, unprefixed and in
# carrier order with root-only lines appended. The ROOT's text wins on a path
# present in both: the root index is canonical for a line's text (D17).
gitlore_compose_tier_bullets() {
  local mempath="$1" tier="$2" carrier="$mempath/$tier/MEMORY.md"
  local root="$mempath/MEMORY.md" line path stripped rootline seen=""

  # Root bullets belonging to this tier, prefix stripped, keyed by path.
  local rootbullets=""
  if [ -f "$root" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) ;; *) continue ;; esac
      stripped=$(gitlore_bullet_deprefix "$line" "$tier") || continue
      rootbullets="$rootbullets$stripped
"
    done < "$root"
  fi

  # Carrier order first; each line replaced by the root's version when present.
  if [ -f "$carrier" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      rootline=$(printf '%s' "$rootbullets" | gitlore_compose_pick "$path")
      if [ -n "$rootline" ]; then printf '%s\n' "$rootline"; else printf '%s\n' "$line"; fi
      seen="$seen
$path"
    done < <(gitlore_index_part "$carrier" bullets)
  fi

  # Then root-only lines, in root order.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=$(gitlore_bullet_path "$line") || continue
    printf '%s\n' "$seen" | grep -qxF -- "$path" && continue
    printf '%s\n' "$line"
  done <<EOF
$rootbullets
EOF
}

# Filter stdin (bullets) to the first one whose path is $1. Helper for the
# merge above; keeps the path comparison out of a subshell-heavy inline loop.
gitlore_compose_pick() {
  local want="$1" line path
  while IFS= read -r line; do
    path=$(gitlore_bullet_path "$line") || continue
    if [ "$path" = "$want" ]; then printf '%s\n' "$line"; return 0; fi
  done
  return 0
}

# Replace $1's bullet region with the bullets on stdin, preserving preamble and
# trailer. Writes only when the result differs, so an already-canonical index
# produces no churn; prints "composed <file>" when it did write.
gitlore_compose_write() {
  local file="$1" tmp="$1.gitlore-compose.tmp" bullets
  bullets=$(cat)
  {
    gitlore_index_part "$file" preamble
    [ -n "$bullets" ] && printf '%s\n' "$bullets"
    gitlore_index_part "$file" trailer
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  printf 'composed %s\n' "$file"
}

# The whole pass. Validates first; on any problem prints the problems, writes
# nothing, and returns 1 — fail-safe, so a broken store is never half-rewritten.
# Otherwise mirrors down into every MOUNTED tier (a dormant tier still receives
# its root lines: dropping them would be data loss, not dormancy — the same rule
# the commit/push lockstep applies) and splices up every ACTIVE tier.
gitlore_compose() {
  local mempath="$1" mounted active tier changed="" root="$mempath/MEMORY.md"
  [ -f "$root" ] || return 0

  if ! gitlore_compose_check "$mempath"; then
    return 1
  fi

  mounted=$(gitlore_tier_paths "$mempath")
  active=$(gitlore_active_tiers "$mempath")

  # Mirror down — every mounted tier with a checked-out carrier.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    changed="$changed$(gitlore_compose_tier_bullets "$mempath" "$tier" \
      | gitlore_compose_write "$mempath/$tier/MEMORY.md")
"
  done <<EOF
$mounted
EOF

  # Splice up — active tiers in manifest order, then the project's own bullets.
  changed="$changed$( {
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      [ -f "$mempath/$tier/MEMORY.md" ] || continue
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        gitlore_bullet_reprefix "$line" "$tier"
      done < <(gitlore_index_part "$mempath/$tier/MEMORY.md" bullets)
    done <<INNER
$active
INNER
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in */*) continue ;; esac
      printf '%s\n' "$line"
    done < <(gitlore_index_part "$root" bullets)
  } | gitlore_compose_write "$root" )"

  [ -n "$changed" ] && printf '%s\n' "$changed"
  return 0
}
```

Declare `line` and `path` `local` in `gitlore_compose` alongside the others.

- [x] **Step 4: Run test to verify it passes**

Run: `bats tests/index_compose.bats`
Expected: PASS, 29 tests.

- [x] **Step 5: Lint and commit**

```bash
scripts/lint-shell.sh
git add scripts/lib/index-compose.sh tests/index_compose.bats
git commit -m "feat: the compose pass — splice up, mirror down (D17 3-ii)"
```

---

### Task 3: Both callers — the PostToolBatch hook and SessionStart

*Two thin callers of the same `gitlore_compose`. Separately they are a hook
registration and a two-line call plus a guidance string; together they are one
deliverable: "composition actually runs, on both triggers."*

#### Part A — the PostToolBatch hook

**Files:**
- Create: `scripts/cc-hooks/index-compose.sh`
- Modify: `hooks/hooks.json`
- Test: `tests/cc_hook_index_compose.bats`

**Interfaces:**
- Consumes: `gitlore_compose MEMPATH` (Task 2); `gitlore_has_submodule`, `gitlore_memory_path` (existing `util.sh`).
- Produces: nothing other scripts call.

- [x] **Step 1: Write the failing test**

Create `tests/cc_hook_index_compose.bats`:

```bash
#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

HOOK="$PLUGIN_ROOT/scripts/cc-hooks/index-compose.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
}
teardown() { teardown_tmp_repo; }

# Build a PostToolBatch payload naming the files an Edit/Write touched.
batch() {
  printf '{"tool_calls":['
  local first=1
  for f in "$@"; do
    [ "$first" -eq 1 ] || printf ','
    first=0
    printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$f"
  done
  printf ']}'
}

stdin() { printf '%s' "$1" | bash "$HOOK"; }

@test "the hook is executable and registered on PostToolBatch" {
  [ -x "$HOOK" ]
  run jq -r '.hooks.PostToolBatch[].hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *"index-compose.sh"* ]]
}

@test "no-op for a batch that touched neither the index nor the manifest" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  run stdin "$(batch "$PWD/some/other/file.txt")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "no-op for a read-only batch" {
  run stdin '{"tool_calls":[{"tool_name":"Read","tool_input":{"file_path":"x"}}]}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an index-touching batch composes and reports on both channels" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  run stdin "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
  run jq -e . <<<"$output"
  [ "$status" -eq 0 ]
}

@test "a manifest-touching batch recomposes" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  run stdin "$(batch "$PWD/memory/.gitlore-tiers")"
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

@test "an already-composed store reports nothing" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  stdin "$(batch "$PWD/memory/MEMORY.md")" >/dev/null
  run stdin "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a validation failure reports on both channels and exits 0" {
  set_tier_manifest ghost
  run stdin "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *systemMessage* ]]
  [[ "$output" == *additionalContext* ]]
}

@test "no-op outside a gitlore repo" {
  rm -rf memory .gitmodules
  git rm -q --cached memory 2>&1 || true
  run stdin "$(batch "$PWD/memory/MEMORY.md")"
  [ "$status" -eq 0 ]
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `bats tests/cc_hook_index_compose.bats`
Expected: FAIL — the hook file does not exist.

- [x] **Step 3: Write minimal implementation**

Create `scripts/cc-hooks/index-compose.sh` (and `chmod +x` it — a non-executable hook silently no-ops in production while `bash script.sh` in tests still passes):

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

# PostToolBatch, like the index→frontmatter sync: it fires once per turn with
# every call in .tool_calls[], so a turn holding several index edits composes —
# and reports — once instead of per edit.
payload=$(cat)
files=$(jq -r '
  .tool_calls[]? | select(.tool_name == "Write" or .tool_name == "Edit")
  | .tool_input.file_path // empty' <<<"$payload")
[ -n "$files" ] || exit 0

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
manifest="$mempath/.gitlore-tiers"
[ -e "$index" ] || exit 0

# Did this batch write the root index or the activation manifest? Identity via
# -ef, as in the sync hooks: the payload carries absolute paths and $mempath is
# relative to the repo root.
touched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -e "$f" ] || continue
  if [ "$f" -ef "$index" ]; then touched=1; break; fi
  if [ -e "$manifest" ] && [ "$f" -ef "$manifest" ]; then touched=1; break; fi
done <<<"$files"
[ -n "$touched" ] || exit 0

sysmsg=""
ctx=""
if result=$(gitlore_compose "$mempath"); then
  if [ -n "$result" ]; then
    n=$(printf '%s\n' "$result" | grep -c '^composed ')
    if [ "$n" -eq 1 ]; then unit="index"; else unit="indexes"; fi
    sysmsg="gitlore: recomposed tier pointers ($n $unit)"
    ctx="The gitlore tier composition rewrote these indexes to place each active tier's pointer block ahead of the project's own lines, and mirrored root-authored tier lines down into their carrier. This is expected and complete — do not re-read or re-edit them to verify. Composition moves lines only; it never changes a line's text.
$result"
  fi
else
  # Fail-safe: nothing was written. Never exit non-zero — stdout JSON parses on
  # exit 0 only, so a non-zero exit would DISCARD this message and make the
  # failure less visible, not more (D14).
  sysmsg="gitlore: tier composition refused — the memory indexes were left untouched:
$result"
  ctx="gitlore tier composition refused and wrote nothing. Fix the store by hand, then edit MEMORY.md or memory/.gitlore-tiers again to retrigger it. Problems:
$result"
fi

if [ -n "$sysmsg" ]; then
  jq -n --arg s "$sysmsg" --arg c "$ctx" \
    '{systemMessage: $s, suppressOutput: true,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
fi
exit 0
```

Register it in `hooks/hooks.json` by appending a third entry to the `PostToolBatch` array:

```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/index-compose.sh"
          }
        ]
      }
```

- [x] **Step 4: Run test to verify it passes**

Run: `chmod +x scripts/cc-hooks/index-compose.sh && bats tests/cc_hook_index_compose.bats`
Expected: PASS, 8 tests.

- [x] **Step 5: Lint and commit**

```bash
scripts/lint-shell.sh
git add scripts/cc-hooks/index-compose.sh hooks/hooks.json tests/cc_hook_index_compose.bats
git commit -m "feat: PostToolBatch tier composition hook (D17 3-ii)"
```

---

#### Part B — SessionStart wiring and the routing-guidance change

**Files:**
- Modify: `scripts/cc-hooks/session-start.sh` (tier block ends ~line 211; guidance text ~line 241)
- Modify: `tests/tier_discovery.bats`

**Interfaces:**
- Consumes: `gitlore_compose MEMPATH` (Task 2).
- Produces: nothing.

- [x] **Step 6: Write the failing test**

Append to `tests/tier_discovery.bats`:

```bash
@test "SessionStart composes propagated tier lines into the root index" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  push_tier_fact ddaanet '- [remote_fact](remote_fact.md) — arrived by propagation' >/dev/null
  export GITLORE_LAUNCHED=1
  run bash "$SESSION_START" <<<'{}'
  [ "$status" -eq 0 ]
  grep -qF -- '- [remote_fact](ddaanet/remote_fact.md) — arrived by propagation' memory/MEMORY.md
}

@test "SessionStart survives a store that fails composition" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ghost
  export GITLORE_LAUNCHED=1
  run bash "$SESSION_START" <<<'{}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost"* ]]
}

@test "routing guidance points the agent at the ROOT index, prefixed" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  export GITLORE_LAUNCHED=1
  run bash "$SESSION_START" <<<'{}'
  [[ "$output" == *"ddaanet/<file>.md"* ]]
  [[ "$output" != *"that tier's MEMORY.md"* ]]
}
```

- [x] **Step 7: Run test to verify it fails**

Run: `bats tests/tier_discovery.bats`
Expected: FAIL — the root index has no `ddaanet/remote_fact.md` line, and the guidance still says "that tier's MEMORY.md".

- [x] **Step 8: Write minimal implementation**

In `scripts/cc-hooks/session-start.sh`, source the new library beside the existing ones:

```bash
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
```

Immediately after the tier fast-forward `while … done < <(gitlore_tier_paths "$mempath")` loop (~line 211), before the routing-guidance block, add:

```bash
# Compose after the fast-forward, so lines that just propagated in surface in
# the always-loaded root index this session rather than next (D17 3-ii). Never
# fatal: a store that fails validation is reported and left alone — SessionStart
# must always finish.
if ! compose_problems=$(gitlore_compose "$mempath"); then
  add_sysmsg "gitlore: tier composition refused; the memory indexes were left untouched:
$compose_problems"
fi
```

Then replace the routing-guidance sentence (~line 241). Current text:

```
Write a portable fact into the matching tier's directory (same one-file-per-fact format, and add its index line to that tier's MEMORY.md); facts specific to this project stay in $mempath/.
```

New text:

```
Write a portable fact into the matching tier's directory (same one-file-per-fact format), and add its index line to the ROOT $mempath/MEMORY.md with the tier prefix — '- [Title](<tier>/<file>.md) — hook'. gitlore mirrors that line down into the tier's own index for you. Facts specific to this project stay in $mempath/ with a bare path.
```

- [x] **Step 9: Run test to verify it passes**

Run: `bats tests/tier_discovery.bats`
Expected: PASS, 16 tests.

- [x] **Step 10: Lint and commit**

```bash
scripts/lint-shell.sh
git add scripts/cc-hooks/session-start.sh tests/tier_discovery.bats
git commit -m "feat: compose at SessionStart and route tier lines via the root index (D17 3-ii)"
```

---

### Task 4: Full suite, design doc, dogfood — **run this inline, do not dispatch**

*Step 4 asks whether a diff against the live memory store is a composition or a
bug. That is a judgment call on real data, and a subagent will read it as a
checkbox. Whoever owns the session runs this task.*

**Files:**
- Modify: `docs/design.md` (D17 status line ~679; changelog table ~line 730)

**Interfaces:**
- Consumes: everything.
- Produces: nothing.

- [x] **Step 1: Confirm both new suites are actually collected**

Run: `make -n test-unit | tr ' ' '\n' | grep -c 'index_compose'`
Expected: `2` (both `tests/index_compose.bats` and `tests/cc_hook_index_compose.bats`). If it is not 2, the `wildcard` glob did not pick them up — fix that before proceeding. Green means nothing until you know what ran.

- [x] **Step 2: Run the whole gate**

Run: `just precommit`
Expected: version check, shellcheck, and the full bats suite all pass. The suite total should be the previous 342 plus the ~37 new cases.

- [x] **Step 3: Update the design doc**

In `docs/design.md`, extend the D17 status line (~line 679) after the tier-lockstep clause with:

```
**3-ii composition** — **done 2026-07-21** (`scripts/lib/index-compose.sh`, `scripts/cc-hooks/index-compose.sh` on `PostToolBatch` + a `SessionStart` pass; splice-up of active tiers, mirror-down into every mounted tier, four fail-safe validations, byte-idempotent; ~37 cases in `tests/index_compose.bats` and `tests/cc_hook_index_compose.bats`);
```

Add a changelog row at the top of the table:

```
| 2026-07-21 | **D17 slice 3-ii built — tier pointers reach the always-loaded index.** Composition is placement only: line identity is the path prefix, no sentinel text is injected, and the pass is byte-idempotent. Two refinements the build forced. (1) **Mirror-down runs for every *mounted* tier, splice-up only for *active* ones** — the spec's "a deactivated tier's lines persist in the carrier" only holds if they were mirrored while active, so a root line for a mounted-but-never-active tier would have been silently dropped; the fix is the same data-loss argument the commit/push lockstep used to commit every mounted tier. (2) **The root's hook text wins over a divergent carrier hook**, following D17's settled rule that the root index is canonical for a line's *text*. A fourth validation was added beyond the design's three: a non-blank non-bullet line inside the bullet region refuses the pass, because the layout rule would relocate it and lose its position. The routing guidance now sends the agent to the root index with a prefixed path — the surface it actually has loaded — instead of the tier's own `MEMORY.md`. Composition needs no change to the index→frontmatter sync: `index-sync-post.sh` already resolves an index path as `$mempath/$path`, so a prefixed path lands on the tier file. |
```

- [x] **Step 4: Dogfood against the real store**

The live store has `memory/ddaanet` mounted and active with a bulletless carrier, so the first compose mirrors down any `ddaanet/`-prefixed root lines and splices nothing up. Run the library by hand against the real store and inspect the diff before committing:

```bash
bash -c 'source scripts/lib/util.sh; source scripts/lib/index-compose.sh; gitlore_compose memory'
git -C memory diff
```

Expected: either no output and no diff (nothing to compose yet — the root index today has no prefixed lines), or a diff that only moves and reprefixes bullets. If any bullet's *text* changed, stop: that is a bug, not a composition.

- [x] **Step 5: Commit**

```bash
git add docs/design.md
git commit -m "docs: record D17 slice 3-ii composition"
```

---

## Follow-ups, explicitly not in this slice

- **`/gitlore:resolve` does not compose.** An index merged by the resolve continuation composes on the next batch or the next session. Recorded in the spec; no code here.
- **Slice 3-iii** — `/gitlore:add-tier` (mount + `--create`), which ends by editing the manifest and so triggers the `PostToolBatch` recompose built here.
- **Happy-path evals** for the finished tier flow, per the standing instruction to write them once nested memory is done.
