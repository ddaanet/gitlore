# Authoring-Time One-Way Index→Frontmatter Sync — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the agent edits the root `MEMORY.md` index one-liner for a memory
file, automatically mirror the edited hook text into that file's frontmatter
`description` — one-way, index→frontmatter only.

**Architecture:** *(Superseded 2026-07-15 after execution: the post half moved
to `PostToolBatch` so a turn with several index edits syncs and reports once,
and it now reports the replacement on `systemMessage`/`additionalContext`. See
D17 in `docs/design.md` for the current wiring; the rest of this plan stands as
executed. **Superseded again 2026-07-16:** the SPOT question is settled and the
added-line semantics are corrected — see "D17 SPOT settled + reconcile spec"
below; the post-hook's added-line branch must change from overwrite to
fill-if-empty.)* A `PreToolUse(Write|Edit)` hook stashes the pre-edit
`MEMORY.md`; a `PostToolUse(Write|Edit)` hook diffs the post-edit `MEMORY.md`
against the stash and, for **only the index lines whose hook actually changed**,
rewrites the target file's frontmatter `description`. One-way because the index
is canonical (D17): the hook never writes the index, and a frontmatter-only edit
never triggers propagation. Diffing pre-vs-post (not a blanket sweep) is what
protects fresh frontmatter sitting under an unrelated *stale* index line.

**Tech Stack:** POSIX-ish bash (must run on macOS bash 3.2 and Linux), `jq`
(already a hard dependency), `awk` (portable one-true-awk/BSD + gawk), bats
tests.

## Global Constraints

- **Portability:** scripts run on macOS (bash 3.2, BSD awk/sed, no GNU
  `realpath`) and Linux. No bash associative arrays. No `sed` `\t` (BSD sed
  emits literal `t`). No GNU-only `awk match(s,re,arr)`. Same-file identity via
  the bash builtin `-ef` test, never `realpath`.
- **YAML safety:** a frontmatter `description` value is emitted as a JSON-quoted
  scalar via `jq -Rn --arg` (a JSON string is a valid YAML flow scalar), so
  hooks containing `:`, `"`, backticks, `[[...]]`, or em-dashes never corrupt
  the YAML.
- **Never dirty the tracked tree from a hook:** the pre-image stash lives inside
  the memory submodule's **gitdir**
  (`git -C <mempath> rev-parse --git-path gitlore-index-preimage`), mirroring
  `gitlore_commit_msg_file`, so it is untracked and cannot trip the FR11 commit
  gate. In the gitlore layout the submodule gitdir is under the parent's
  `.git/modules/<name>/`, so `--git-path` returns an **absolute** path whose
  parent dir already exists — used verbatim, never prefixed with `<mempath>`,
  never `mkdir`'d.
- **Non-blocking, but never silent:** every hook script `exit 0` on every path
  (success, no-op, nothing-to-do, *and genuine failure*) and must never
  `exit 2`. But `exit 0` is **not** licence to swallow errors: a real failure
  (stash `cp` fails; a frontmatter write fails) must surface to the user on
  `systemMessage` (the D14 channel — `docs/design.md:581`, verified 2026-06-10:
  the only reliably user-visible hook channel; stderr reaches the user only on
  `exit 2` / `--verbose`). Exit 0 is *required* for visibility, not merely
  tolerated: **stdout JSON is parsed only on exit 0**, so a non-zero exit
  discards the `systemMessage` and makes the error less visible, not more.
  Mirror `scripts/cc-hooks/worktree-drift.sh` (a PostToolUse hook already
  emitting `systemMessage` via `jq -n --arg`). Note the asymmetry driving the
  never-`exit 2` rule: at **PreToolUse** `exit 2` blocks the tool outright; at
  **PostToolUse** nothing can block (the tool already ran — "PostToolUse hooks
  can't undo actions"), so there the exit code buys nothing and only the channel
  matters. `|| true` and bare `|| exit 0` on a fallible command are
  **rejected**: errors must never pass silently.
- **Scope = single tier (project `MEMORY.md`).** Only `<mempath>/MEMORY.md` is
  handled. Tier carriers (`memory/<tier>/MEMORY.md`) and net-new-line seeding
  are the structural-recompose slice (later), out of scope here.
- **Tool scope:** matcher `Write|Edit` only. Edits made through other tools
  simply don't sync (low-harm); noted, not handled.
- Reuse existing lib helpers: `gitlore_has_submodule`, `gitlore_memory_path`
  from `scripts/lib/util.sh`. New helpers live in a new
  `scripts/lib/index-sync.sh`.

---

## File Structure

- `scripts/lib/index-sync.sh` — **new.** Pure, sourceable helpers: parse index
  lines → `path<TAB>hook`, rewrite a file's frontmatter `description`, compute
  the stash path. No I/O side effects beyond the one explicit file write in the
  setter. Independently unit-testable.
- `scripts/cc-hooks/index-sync-pre.sh` — **new.** PreToolUse entry: stash
  `MEMORY.md`.
- `scripts/cc-hooks/index-sync-post.sh` — **new.** PostToolUse entry: diff +
  propagate.
- `hooks/hooks.json` — **modify.** Add a `PreToolUse` array (matcher
  `Write|Edit`) and a third `PostToolUse` entry (matcher `Write|Edit`).
- `tests/index_sync.bats` — **new.** Grows across tasks: lib units, pre, post,
  end-to-end.
- `Makefile` — **modify.** Add `tests/index_sync.bats` to `test-unit`.

---

### Task 1: Library helpers (`scripts/lib/index-sync.sh`)

**Files:**
- Create: `scripts/lib/index-sync.sh`
- Create/Test: `tests/index_sync.bats`
- Modify: `Makefile:11` (append the new bats file to `test-unit`)

**Interfaces:**
- Produces:
  - `gitlore_index_pairs <memory_md_path>` → stdout, one `path<TAB>hook` line
    per index bullet matching `- [title](path) — hook`. Lines without a `) — `
    separator are skipped.
  - `gitlore_set_frontmatter_description <file> <newdesc>` → rewrites the first
    `description:` line inside the file's leading frontmatter block (between the
    1st and 2nd `---`) to `description: "<json-escaped newdesc>"`. In place.
  - `gitlore_index_preimage_file <mempath>` → prints the abs/relative stash path
    inside the submodule gitdir.

- [ ] **Step 1: Write the failing tests**

Create `tests/index_sync.bats`:

```bash
#!/usr/bin/env bats

load helpers/setup

SRC="$PLUGIN_ROOT/scripts/lib/index-sync.sh"

setup() { setup_tmp_repo; . "$SRC"; }
teardown() { teardown_tmp_repo; }

@test "index_pairs: extracts path and hook, tab-separated" {
  printf '# Memory Index\n\n- [Proj](project_overview.md) — current state, next steps\n- [Gitmoji](feedback_gitmoji.md) — prefixes required\n' > MEMORY.md
  run gitlore_index_pairs MEMORY.md
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf 'project_overview.md\tcurrent state, next steps')" ]
  [ "${lines[1]}" = "$(printf 'feedback_gitmoji.md\tprefixes required')" ]
}

@test "index_pairs: skips non-bullet and separatorless lines" {
  printf '# Header\n- [x](a.md) no dash here\n- [y](b.md) — has hook\n' > MEMORY.md
  run gitlore_index_pairs MEMORY.md
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "$(printf 'b.md\thas hook')" ]
}

@test "index_pairs: hook containing an em-dash keeps everything after the FIRST separator" {
  printf -- '- [z](c.md) — front — back\n' > MEMORY.md
  run gitlore_index_pairs MEMORY.md
  [ "${lines[0]}" = "$(printf 'c.md\tfront — back')" ]
}

@test "set_frontmatter_description: replaces the description line in place" {
  printf -- '---\nname: foo\ndescription: old text\nmetadata:\n  type: project\n---\n\nbody\n' > f.md
  gitlore_set_frontmatter_description f.md "new hook text"
  run grep -c '^description:' f.md
  [ "$output" = "1" ]
  run grep '^description:' f.md
  [ "$output" = 'description: "new hook text"' ]
  run grep -c '^name: foo' f.md   # untouched
  [ "$output" = "1" ]
  run tail -n1 f.md               # body untouched
  [ "$output" = "body" ]
}

@test "set_frontmatter_description: YAML-escapes quotes, colons, backticks" {
  printf -- '---\ndescription: x\n---\n' > f.md
  gitlore_set_frontmatter_description f.md 'has "quote": a `tick` and \ slash'
  run grep '^description:' f.md
  [ "$output" = 'description: "has \"quote\": a `tick` and \\ slash"' ]
}

@test "set_frontmatter_description: only touches the FIRST frontmatter block" {
  printf -- '---\ndescription: real\n---\nbody with\n---\ndescription: not-frontmatter\n---\n' > f.md
  gitlore_set_frontmatter_description f.md "changed"
  run grep -c '^description: not-frontmatter' f.md
  [ "$output" = "1" ]
  run grep -c '^description: "changed"' f.md
  [ "$output" = "1" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/index_sync.bats`
Expected: FAIL — `index-sync.sh` does not exist / functions not found.

- [ ] **Step 3: Write `scripts/lib/index-sync.sh`**

```bash
#!/usr/bin/env bash
# One-way index→frontmatter sync helpers (D17). Sourced by the Pre/Post hooks
# and unit-tested directly. No side effects except the one write in the setter.

# Print "path<TAB>hook" for every root-index bullet of the form
#   - [title](path) — hook
# Lines lacking the ") — " separator are skipped. All width arithmetic uses
# length() so byte-vs-char counting stays self-consistent across awk flavors.
gitlore_index_pairs() {
  awk '
    /^- \[/ {
      sep = ") — "
      d = index($0, sep)
      if (d == 0) next
      left = substr($0, 1, d)              # "...(path)"
      hook = substr($0, d + length(sep))   # everything after the first ") — "
      lp = index(left, "](")
      if (lp == 0) next
      rest = substr(left, lp + 2)          # "path)"
      rp = index(rest, ")")
      if (rp == 0) next
      path = substr(rest, 1, rp - 1)
      print path "\t" hook                 # awk "\t" is a real tab, portably
    }
  ' "$1"
}

# Rewrite the first `description:` line inside a file's leading frontmatter
# block to a JSON-quoted (=> YAML-safe) scalar of $2. In place.
gitlore_set_frontmatter_description() {
  local file="$1" newdesc="$2" quoted repl
  quoted=$(jq -Rn --arg d "$newdesc" '$d')   # e.g. "has \"quote\": ..."
  repl="description: $quoted"
  # Pass repl via ENVIRON so awk does no escape processing on it.
  GITLORE_REPL="$repl" awk '
    BEGIN { dashes = 0; done = 0 }
    /^---[[:space:]]*$/ { dashes++; print; next }
    (dashes == 1 && !done && /^description:/) {
      print ENVIRON["GITLORE_REPL"]; done = 1; next
    }
    { print }
  ' "$file" > "$file.gitlore.tmp" && mv "$file.gitlore.tmp" "$file"
}

# Abs/relative path of the pre-edit MEMORY.md stash, inside the submodule
# gitdir (untracked; mirrors gitlore_commit_msg_file). $1 = memory path.
gitlore_index_preimage_file() {
  git -C "$1" rev-parse --git-path gitlore-index-preimage
}
```

- [ ] **Step 4: Add the test file to the Makefile**

In `Makefile:11`, append ` tests/index_sync.bats` to the end of the `test-unit`
bats line.

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/index_sync.bats`
Expected: PASS (6 tests).

- [ ] **Step 6: Lint**

Run: `scripts/lint-shell.sh`
Expected: exit 0 (new lib is clean).

- [ ] **Step 7: Commit**

```bash
git add scripts/lib/index-sync.sh tests/index_sync.bats Makefile
git commit -m "feat: index-sync lib helpers (parse pairs, set frontmatter description)"
```

---

### Task 2: PreToolUse stash hook (`scripts/cc-hooks/index-sync-pre.sh`)

**Files:**
- Create: `scripts/cc-hooks/index-sync-pre.sh`
- Modify/Test: `tests/index_sync.bats` (append)

**Interfaces:**
- Consumes: `gitlore_has_submodule`, `gitlore_memory_path` (util.sh);
  `gitlore_index_preimage_file` (index-sync.sh).
- Produces: on a `Write|Edit` whose `file_path` **is** `<mempath>/MEMORY.md`
  (bash `-ef` identity), copies the current on-disk `MEMORY.md` to the stash
  path. No output. Exit 0 always.

- [ ] **Step 1: Write the failing tests** (append to `tests/index_sync.bats`)

```bash
PRE="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"

pre_stdin() { printf '%s' "$1" | bash "$PRE"; }

@test "pre: stashes MEMORY.md when the edited file is the index" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '- [a](a.md) — before\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  payload=$(jq -n --arg f "$abs" '{tool_name:"Edit",tool_input:{file_path:$f}}')
  run pre_stdin "$payload"
  [ "$status" -eq 0 ]
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  [ -f "$stash" ]
}

@test "pre: no-op when the edited file is not the index" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '- [a](a.md) — before\n' > memory/MEMORY.md
  payload=$(jq -n --arg f "$PWD/memory/other.md" '{tool_name:"Write",tool_input:{file_path:$f}}')
  run pre_stdin "$payload"
  [ "$status" -eq 0 ]
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  [ ! -f "$stash" ]
}
```

(`--git-path` returns an absolute path under `.git/modules/gitlore-memory/`; the
hook resolves it the same way, so producer and checker agree.)

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/index_sync.bats -f "pre:"`
Expected: FAIL — `index-sync-pre.sh` missing.

- [ ] **Step 3: Write `scripts/cc-hooks/index-sync-pre.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
case "$tool" in Write|Edit) ;; *) exit 0 ;; esac

file=$(jq -r '.tool_input.file_path // empty' <<<"$payload")
[ -n "$file" ] || exit 0

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"

# Only the project index; identity via -ef (portable, no realpath).
[ -e "$index" ] || exit 0
[ "$file" -ef "$index" ] || exit 0

stash=$(gitlore_index_preimage_file "$mempath")   # absolute; parent dir exists
cp "$index" "$stash" || exit 0   # stash failed → no baseline; never block the Write
exit 0
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/index_sync.bats -f "pre:"`
Expected: PASS (2 tests).

- [ ] **Step 5: Lint**

Run: `scripts/lint-shell.sh`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/cc-hooks/index-sync-pre.sh tests/index_sync.bats
git commit -m "feat: PreToolUse hook stashes pre-edit MEMORY.md for index sync"
```

---

### Task 3: PostToolUse propagate hook (`scripts/cc-hooks/index-sync-post.sh`)

**Files:**
- Create: `scripts/cc-hooks/index-sync-post.sh`
- Modify/Test: `tests/index_sync.bats` (append)

**Interfaces:**
- Consumes: util.sh helpers; `gitlore_index_pairs`,
  `gitlore_set_frontmatter_description`, `gitlore_index_preimage_file`.
- Produces: on a `Write|Edit` whose `file_path` is `<mempath>/MEMORY.md`, for
  each index path whose hook **differs from the stash**, rewrites
  `<mempath>/<path>`'s frontmatter `description` to the new hook. Consumes
  (removes) the stash. Unchanged lines are left untouched. Exit 0 always.

- [ ] **Step 1: Write the failing tests** (append)

```bash
POST="$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"

post_stdin() { printf '%s' "$1" | bash "$POST"; }

# Seed a stash + a memory file, edit the index, run post.
@test "post: propagates a CHANGED index hook into the file's frontmatter" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: stale desc\n---\nbody\n' > memory/a.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)   # abs
  printf -- '- [A](a.md) — old hook\n' > "$stash"             # pre-image
  printf -- '- [A](a.md) — new hook\n' > memory/MEMORY.md     # post-edit
  payload=$(jq -n --arg f "$PWD/memory/MEMORY.md" '{tool_name:"Edit",tool_input:{file_path:$f},tool_response:{}}')
  run post_stdin "$payload"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new hook"' ]
  [ ! -f "memory/$stash" ]   # stash consumed
}

@test "post: does NOT touch a file whose index line is UNCHANGED (protects fresh frontmatter)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: fresh frontmatter\n---\n' > memory/b.md
  stash=$(git -C memory rev-parse --git-path gitlore-index-preimage)
  # b's line is identical in pre and post (stale index, unchanged this edit);
  # only a's line changed.
  printf -- '---\ndescription: x\n---\n' > memory/a.md
  printf -- '- [A](a.md) — old\n- [B](b.md) — stale index for b\n' > "$stash"
  printf -- '- [A](a.md) — new\n- [B](b.md) — stale index for b\n' > memory/MEMORY.md
  payload=$(jq -n --arg f "$PWD/memory/MEMORY.md" '{tool_name:"Edit",tool_input:{file_path:$f},tool_response:{}}')
  run post_stdin "$payload"
  run grep '^description:' memory/b.md
  [ "$output" = 'description: fresh frontmatter' ]   # untouched — the key guard
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new"' ]
}

@test "post: no-op when no stash exists (no baseline to diff)" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\ndescription: keep\n---\n' > memory/a.md
  printf -- '- [A](a.md) — whatever\n' > memory/MEMORY.md
  payload=$(jq -n --arg f "$PWD/memory/MEMORY.md" '{tool_name:"Edit",tool_input:{file_path:$f},tool_response:{}}')
  run post_stdin "$payload"
  [ "$status" -eq 0 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: keep' ]
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bats tests/index_sync.bats -f "post:"`
Expected: FAIL — `index-sync-post.sh` missing.

- [ ] **Step 3: Write `scripts/cc-hooks/index-sync-post.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
case "$tool" in Write|Edit) ;; *) exit 0 ;; esac

file=$(jq -r '.tool_input.file_path // empty' <<<"$payload")
[ -n "$file" ] || exit 0

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
[ -e "$index" ] || exit 0
[ "$file" -ef "$index" ] || exit 0

stashfile=$(gitlore_index_preimage_file "$mempath")   # absolute
[ -f "$stashfile" ] || exit 0   # no baseline → nothing to diff

pre_pairs=$(gitlore_index_pairs "$stashfile")
post_pairs=$(gitlore_index_pairs "$index")

while IFS=$'\t' read -r path hook; do
  [ -n "$path" ] || continue
  prehook=$(awk -F'\t' -v p="$path" '$1==p{sub(/^[^\t]*\t/,""); print; exit}' <<<"$pre_pairs")
  [ "$hook" = "$prehook" ] && continue        # unchanged this edit → skip
  target="$mempath/$path"
  [ -f "$target" ] || continue                # orphan line → skip
  gitlore_set_frontmatter_description "$target" "$hook"
done <<<"$post_pairs"

rm -f "$stashfile"
exit 0
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/index_sync.bats -f "post:"`
Expected: PASS (3 tests).

- [ ] **Step 5: Lint**

Run: `scripts/lint-shell.sh`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/cc-hooks/index-sync-post.sh tests/index_sync.bats
git commit -m "feat: PostToolUse hook propagates changed index hooks to frontmatter"
```

---

### Task 4: Wire hooks + end-to-end test

**Files:**
- Modify: `hooks/hooks.json`
- Modify/Test: `tests/index_sync.bats` (append an end-to-end pre→post test)

**Interfaces:**
- Consumes: both hook scripts from Tasks 2–3.
- Produces: CC fires `index-sync-pre.sh` on every `Write|Edit` (PreToolUse) and
  `index-sync-post.sh` on every `Write|Edit` (PostToolUse), alongside the
  existing Bash/worktree PostToolUse entries.

- [ ] **Step 1: Write the failing end-to-end test** (append)

```bash
@test "e2e: pre-then-post syncs a description edited only in the index" {
  make_parent_with_memory
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  printf -- '---\nname: a\ndescription: OLD\n---\nbody\n' > memory/a.md
  printf -- '- [A](a.md) — old hook line\n' > memory/MEMORY.md
  abs="$PWD/memory/MEMORY.md"
  pre_payload=$(jq -n --arg f "$abs" '{tool_name:"Edit",tool_input:{file_path:$f}}')
  printf '%s' "$pre_payload" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-pre.sh"
  # the "edit" happens between pre and post:
  printf -- '- [A](a.md) — brand new hook line\n' > memory/MEMORY.md
  post_payload=$(jq -n --arg f "$abs" '{tool_name:"Edit",tool_input:{file_path:$f},tool_response:{}}')
  printf '%s' "$post_payload" | bash "$PLUGIN_ROOT/scripts/cc-hooks/index-sync-post.sh"
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "brand new hook line"' ]
}

@test "e2e: hooks.json registers both Write|Edit index-sync hooks" {
  run jq -r '.hooks.PreToolUse[] | select(.matcher=="Write|Edit") | .hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *index-sync-pre.sh ]]
  run jq -r '.hooks.PostToolUse[] | select(.matcher=="Write|Edit") | .hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [[ "$output" == *index-sync-post.sh ]]
}
```

- [ ] **Step 2: Run to verify the hooks.json test fails**

Run: `bats tests/index_sync.bats -f "e2e:"` Expected: the `hooks.json registers`
test FAILS (matcher not present yet); the pre-then-post test PASSES already.

- [ ] **Step 3: Edit `hooks/hooks.json`**

Add a top-level `PreToolUse` array and a third entry in `PostToolUse`. Result:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/session-start.sh" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/index-sync-pre.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/post-tool-use.sh" }
        ]
      },
      {
        "matcher": "EnterWorktree|ExitWorktree",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/worktree-drift.sh" }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/index-sync-post.sh" }
        ]
      }
    ],
    "WorktreeRemove": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/scripts/cc-hooks/worktree-remove.sh" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bats tests/index_sync.bats`
Expected: PASS (all tests — 6 lib + 2 pre + 3 post + 2 e2e = 13).

- [ ] **Step 5: Full suite + lint (no regressions)**

Run: `make lint && make test-unit` Expected: exit 0. Confirm
`plugin_distribution.bats` (matcher-scoped `select`) and
`integration_happy_path.bats` still pass — the new entries are additive.

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json tests/index_sync.bats
git commit -m "feat: wire PreToolUse/PostToolUse Write|Edit index-sync hooks"
```

---

## Dogfood (after Task 4)

The sync is now live in this repo. Before the reconcile slice, sanity-check by
editing one real `memory/MEMORY.md` hook in a session and confirming the target
file's frontmatter follows. This is the D17 sequence's step-1 exit criterion;
the one-time **reconcile** (fixing pre-existing *stale-index* drift the one-way
sync can't heal) is the next plan, dogfooded here first.

## D17 SPOT settled + reconcile spec (2026-07-16)

The single-point-of-truth question this plan left open (is the index one-liner
really canonical?) is now **settled by eval** (MemoryEval sub-agent, 528 session
transcripts + a 136-file native baseline across 7 other projects where gitlore's
sync hook has not yet acted): index-canonical holds — agents refine the index
hook ≈3:1 over the frontmatter `description:`, others-only, so it is native
curation, not a gitlore artifact. Full evidence in
`memory/project_gitlore_global_memory.md` (RESOLVED block).

**Settled sync rule — keyed by DESTINATION path, not line position.** Parse the
pre- and post-edit `MEMORY.md` into `{path → hook}` maps and, per destination:

| pre-image state | action on the file's frontmatter `description:` |
|---|---|
| destination ABSENT (added line) | **fill** only if the description is EMPTY; else leave it |
| present, hook CHANGED | **overwrite** (propagate) with the new hook |
| present, hook UNCHANGED (incl. reordered) | no-op |
| destination removed | no-op |

Keying by destination (not position) makes reordering and grouped mid-list
insertion no-ops — required, since the eval found ~25% of index insertions land
mid-list, grouped by type prefix. Fill-if-empty at add-time is a no-op on real
creations (write-order: the file carries its authored `description:` before the
index line is added), so "don't clobber a fresh creation" falls out with **no
file-added check**. A deliberate hook *edit* still overwrites — the intended
propagation of the canonical side. REJECTED by the eval: bidirectional sync,
slug-detection (0/136 native descriptions are slug-like), and the
hook-authors-index-via-`additionalContext` reframe (a new line is not reliably
end-appended).

**Required correction to the live post-hook (`scripts/lib/index-sync.sh`).** The
post loop already keys by destination, but its added-line branch OVERWRITES:
when a destination is absent from the pre-image, `prehook` is empty, the
`[ "$hook" = "$prehook" ]` test is false, and it calls
`gitlore_set_frontmatter_description` unconditionally — clobbering an authored
description (reproduced twice live). Fix: split the branch — if the destination
was ABSENT in the pre-image, fill only when
`gitlore_get_frontmatter_description "$target"` returns empty/none; otherwise
skip. The CHANGED-hook path is unchanged. TDD: add a failing
`post: an ADDED index line fills only an EMPTY description, never clobbers` test
first. MUST land before reconcile runs the rule at scale.

**Reconcile slice (its own plan, after the correction).** One-time,
per-project + once-per-shared-tier, applies the settled rule as a sweep over the
~40 files whose index line and frontmatter already drifted. The one-way live
sync only heals going forward; reconcile is the semantic catch-up. On a genuine
divergence the tie-break is index-canonical; a missing description is filled
from the hook. Dogfood on this repo first.

## Out of scope (later slices)

- Tier carriers `memory/<tier>/MEMORY.md` and net-new-line frontmatter seeding →
  structural recompose slice.
- The semantic **reconcile** sweep (`/gitlore:reconcile`) → its own plan; must
  run *after* this sync is deployed.
- Edits via tools other than `Write|Edit` (e.g. MultiEdit) — currently unsynced,
  low-harm.

## Self-Review

- **Spec coverage:** one-way index→frontmatter (Tasks 1–4 ✓); pre-image diff
  scoping to changed lines only, protecting fresh frontmatter under stale index
  lines (Task 3 test #2 ✓); index-canonical / hook never writes index (no code
  path writes MEMORY.md ✓); YAML-safe frontmatter write (Task 1 test #5 ✓);
  global plugin-hook deployment (Task 4 ✓). Reconcile + tiers explicitly
  deferred ✓.
- **Placeholder scan:** none — every step carries real code/commands.
- **Type consistency:** `gitlore_index_pairs`,
  `gitlore_set_frontmatter_description`, `gitlore_index_preimage_file` used with
  identical names/arity in Tasks 2–3 as defined in Task 1 ✓. Stash path is the
  helper's absolute output, used verbatim (no prefix, no fallback) in both pre
  and post ✓.
- **Shell-gotchas audit:** absolute `--git-path` verified empirically (no
  dishonest `2>/dev/null` fallback); awk `"\t"` not `sed \t`; `-ef` not
  `realpath`; no bash-4 assoc arrays; `printf` for data; hooks never block
  **and never fail silently** — every fallible command (the stash `cp`; each
  `gitlore_set_frontmatter_description`) has its status checked explicitly and
  reports on `systemMessage` + `exit 0`, never `|| true` / bare `|| exit 0`
  (corrected 2026-07-15: the original `cp … || exit 0` was a dishonest error
  path, and an unguarded setter call let `set -e` abort the post-hook mid-loop —
  skipping both the stash `rm` and the final `exit 0`, reproduced via
  `chmod 555`); the stash `rm` is unconditional so a stale pre-image can never
  be diffed against a later index; `set -e` command-subs guarded by prior
  `gitlore_has_submodule`. `awk -v p="$path"` carries only slug paths (no
  backslashes); the fallible hook text goes through `jq --arg` + `ENVIRON`,
  never `-v`.
