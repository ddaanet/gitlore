# gitlore Plan 04 — Marketplace install (make `memory-merger` discoverable)

> **Status:** spec / design. Implementation plan (task-by-task breakdown) will be expanded from this document by `superpowers:writing-plans`.

**Goal:** End users can install gitlore from a Claude Code marketplace, after which `/gitlore:resolve` dispatches the `memory-merger` sub-agent successfully. Today, Plan 03's `agents/memory-merger.md` is present in the repo but only loaded when the plugin is marketplace-installed; the script-side state machine works, but `Task({subagent_type: "memory-merger"})` silently fails with "agent not found." Plan 04 closes that gap.

**Reference:** `docs/design.md` is the authoritative spec (FR 6, FR 7, D9 in particular). Plan 03 (`docs/plans/2026-05-21-03-semantic-merge-resolve.md`) is the immediate predecessor — it shipped the sub-agent file, scripts, and directive emission; Plan 04 makes the sub-agent reachable in practice.

---

## 1. Lessons-learned opener (Plan 03 retrospective)

Plan 03 shipped 89/89 + 1/1 green and patched three real-world bugs surfaced by its own dogfood gate (changed_files coverage, literal `$CLAUDE_PLUGIN_ROOT` expansion, CWD assumption in the continuation), all backfilled with regression tests in commit `dcaaf75`. The state machine itself is correct.

What Plan 03's dogfood gate *couldn't* observe — because the plugin wasn't marketplace-installed — was the `Task` dispatch step. The directive was emitted; the sub-agent dispatch silently no-op'd. The full loop has therefore never run end-to-end in a real CC session. [[reference-cc-agent-discovery]] captured the cause: plugin agents at `<plugin-root>/agents/<name>.md` are only discoverable to `Task` when the plugin is loaded via marketplace install (or now: via `--plugin-dir`). Skill discovery and agent discovery use different code paths; Plan 03's skills *were* visible (`gitlore:install`, `gitlore:resolve`).

The Plan 04 lesson is operational, not architectural:

**Dogfood the actual install pathway, not a simulation of it.** Plan 03 ran its dogfood with the plugin at the cwd, which loaded the commands but not the agent. The gap wasn't caught at design time; it surfaced post-ship. Plan 04 must run dogfood against a session that has gitlore loaded *the way an end user will load it* — first via `--plugin-dir` (for fast iteration), then via `/plugin install gitlore@ddaanet` (for the ship gate). Anything that surfaces only in the second of those is a real-world bug the inner loop missed.

---

## 2. Scope

### 2.1 In scope

- **gitlore plugin manifest.** `gitlore/.claude-plugin/plugin.json` filled in with `author`, `license`, `repository`, `keywords`, accurate `description`. Version stays at `0.1.0` (not yet published).
- **Inner-loop dogfood (`--plugin-dir`).** Run `claude --plugin-dir /Users/david/code/gitlore` from a throwaway parent repo; install gitlore via `/gitlore:install`; force a branch-vs-live divergence; observe `Task({subagent_type: "memory-merger"})` dispatched end-to-end. This is the fast iteration loop where most fixes will land.
- **Publish `ddaanet/gitlore` to GitHub.** Local `main` is 25 commits ahead of `origin/main`. Push.
- **Add gitlore to `ddaanet/claude-plugins`.** New entry in `~/code/claude-plugins/.claude-plugin/marketplace.json` (shape mirrors `handoff`/`gitmoji`); matching row in its `README.md`. Commit + push.
- **Validate.** `claude plugin validate .` in both repos must exit 0.
- **Outer-loop dogfood (ship gate).** Install gitlore via `/plugin install gitlore@ddaanet` into a fresh parent repo; rerun the divergence; observe identical behaviour to the inner loop.
- **Install-pathway documentation.** `docs/plugin-readme.md` (and the gitlore root, if a README is added) document the marketplace prerequisite: `/plugin marketplace add ddaanet/claude-plugins` → `/plugin install gitlore@ddaanet`, then `/gitlore:install` inside the target repo.
- **In-plan backfill of dogfood findings.** Per [[feedback-dogfood-early]] / [[feedback-automate-default]] and Plan 03 §6.4: anything either dogfood tier surfaces gets a Layer 1 or Layer 2 fixture *in this plan* before Plan 04 is considered shipped.

### 2.2 Out of scope (deferred)

- `WorktreeCreate` / `WorktreeRemove` hooks (was original Plan 04 — now Plan 05).
- Clone-from-remote smoke test, polish, expanded docs (was Plan 05 — now Plan 06).
- Solo gitlore marketplace (`.claude-plugin/marketplace.json` in the gitlore repo itself). Decided against: matches no existing ddaanet/ plugin; doubles maintenance.
- Automated CI to keep `gitlore/plugin.json` version in sync with `claude-plugins/marketplace.json` entries. Manual sync per the existing `claude-plugins/CLAUDE.md` convention.
- Public/anthropic plugin-registry publication.
- Cleanup of `ddaanet/gitmoji-gitlore-memory` (Plan 02 leftover, requires `gh auth refresh -h github.com -s delete_repo`). Orthogonal.
- Version bumping. `0.1.0` is the unpublished first version; no bump until first published release after Plan 04.

---

## 3. Architecture — the missing edge

There's no new code path to design; Plan 03 already drew the state machine. The "architecture" of Plan 04 is the **end-user install flow**, of which gitlore has owned only the back half:

```
   ┌────────────────────────────────────────────────────────────────┐
   │ End-user install flow                                          │
   ├────────────────────────────────────────────────────────────────┤
   │                                                                │
   │  /plugin marketplace add ddaanet/claude-plugins  ←── NEW       │
   │                                                                │
   │  /plugin install gitlore@ddaanet                 ←── NEW       │
   │      ↓                                                         │
   │      CC loads .claude-plugin/plugin.json,                      │
   │      registers skills, commands, AND agents/memory-merger.md   │
   │                                                                │
   │  cd <project>                                                  │
   │  /gitlore:install [memory-path] [precommit-cmd] ─── covered    │
   │      ↓                                                          │
   │      submodule + remote + hooks wired                          │
   │                                                                │
   │  ... normal work; first divergence ...                         │
   │                                                                │
   │  git commit → pre-commit hook detects divergence               │
   │             → script emits directive with state-file path      │
   │             → CC slash-command dispatches memory-merger        │ ←── now works
   │             → memory-merger synthesizes, asks for approval     │
   │             → continuation script commits, retries push        │
   │                                                                │
   └────────────────────────────────────────────────────────────────┘
```

The top two lines are Plan 04's surface. Everything below is already covered by Plans 01–03 and only *appears* to work today because the dogfood loop bypassed marketplace install. Plan 04 ships the missing edge AND uses it to discover anything that breaks under real marketplace-load semantics.

---

## 4. Inner loop — `--plugin-dir` for fast iteration

`claude --plugin-dir /Users/david/code/gitlore` loads the plugin from a filesystem path, bypassing the marketplace machinery. This collapses the dogfood loop: no GitHub push, no marketplace.json bump, no `/plugin marketplace update`. Verification at this layer answers:

- Does `--plugin-dir` expose `agents/<name>.md` for `Task` dispatch, the same way marketplace install does? (Hypothesis: yes — `--plugin-dir` is a fully-loaded plugin from a local source. Verified by Task 1.)
- Is the directive emitted by Plan 03's hooks consumed correctly by a real Claude Code slash-command-to-`Task` dispatch? (Plan 03's tests verified directive *shape*; they did not verify the full agent-tool round-trip.)
- Does the state-file path emitted by the directive resolve correctly from the sub-agent's CWD? (Plan 03 added `cd "<parent-repo>" && ` to the continuation; verify it still holds when the sub-agent is loaded from a `--plugin-dir` source rather than the marketplace cache.)
- Does the memory-merger system prompt produce coherent synthesis on a non-trivial divergence? (Not testable below this layer.)

The inner-loop test rig is bash + a real Claude Code session, not bats. It is exploratory by design — any structural issue uncovered gets a Layer 1 or Layer 2 bats fixture before Plan 04 ships.

---

## 5. Outer loop — marketplace install as the ship gate

Once the inner loop is clean, the outer loop runs once:

1. Push `ddaanet/gitlore` (`main`).
2. Add gitlore entry to `~/code/claude-plugins/.claude-plugin/marketplace.json` mirroring the `handoff` entry shape (GitHub source, owner, repository link, version `0.1.0`, license, keywords).
3. Add gitlore row to `~/code/claude-plugins/README.md`.
4. `claude plugin validate .` in both repos.
5. Push `claude-plugins`.
6. In a fresh CC session (no `--plugin-dir`), in a throwaway parent repo: `/plugin marketplace update ddaanet`, `/plugin install gitlore@ddaanet`, `/gitlore:install`, force divergence, observe identical behaviour to the inner loop.

If the inner loop was clean and the outer loop is too, ship. If the outer loop surfaces anything the inner loop didn't, that's a real difference between `--plugin-dir` and marketplace install — fix it, then encode the difference as a `[[reference-cc-...]]` memory.

---

## 6. Cross-repo coordination

Two repos change in this plan: `ddaanet/gitlore` (this one) and `ddaanet/claude-plugins`. Per the existing `claude-plugins/CLAUDE.md` convention, the gitlore version in its own `plugin.json` must match the entry in `marketplace.json`; same-version updates are skipped by users' `/plugin marketplace update`.

Convention to follow when updating gitlore post-Plan-04:

1. Bump `gitlore/.claude-plugin/plugin.json` `version`.
2. Update the matching `version` in `claude-plugins/.claude-plugin/marketplace.json`.
3. Push both. Users run `/plugin marketplace update` to see the new version.

This plan does NOT introduce automation for that sync — the manual workflow is already documented and small.

---

## 7. Testing strategy — three layers

Same layered approach as Plan 03, scaled to this plan's smaller surface.

### 7.1 Layer 1 — Unit (bats)

`tests/plugin_manifest.bats` (new) — sanity-check `gitlore/.claude-plugin/plugin.json`:

- File parses as JSON.
- Required fields present (`name`, `version`, `description`).
- Plan-04-mandated fields present (`author`, `license`, `repository`, `keywords`).
- `version` is semver-shaped.
- `name` is exactly `gitlore` (matches the marketplace entry, matches the sub-agent's plugin namespace).

The intent is to catch accidental edits — not to validate against the full CC schema (that's Layer 2's job).

### 7.2 Layer 2 — `claude plugin validate`

`make validate` (or equivalent target) runs `claude plugin validate .` in:

- `/Users/david/code/gitlore`
- `/Users/david/code/claude-plugins`

Both must exit 0. This is the authoritative manifest check.

### 7.3 Layer 3 — Manual dogfood (two-tier)

- **Inner loop (mandatory).** `claude --plugin-dir /Users/david/code/gitlore` in a throwaway parent repo; full `/gitlore:install` → induced divergence → `git commit` → observe `memory-merger` dispatched and complete. Pass = parent repo's memory submodule has a clean merge commit on `live`, retry-push succeeded.
- **Outer loop (ship gate).** Same scenario in a fresh CC session, gitlore installed via `/plugin install gitlore@ddaanet`. Pass = identical outcome to inner loop.

### 7.4 In-plan backfill

Per [[feedback-dogfood-early]]: every finding from §7.3 gets a Layer 1 or Layer 2 fixture *inside Plan 04* before ship. Following Plan 02 (commit `192d7e8`) and Plan 03 (commit `dcaaf75`) — same-plan backfill, not handoff to Plan 05.

If a finding is fundamentally untestable by bats (e.g., "the sub-agent prompt is too vague when files have no textual conflicts but semantic ones"), encode it in `agents/memory-merger.md` (system prompt update) and verify by re-running the inner-loop dogfood. That counts as Layer 2-equivalent.

---

## 8. Open questions to resolve during writing-plans

1. **Does `--plugin-dir <path>` expose `agents/<name>.md` for `Task` dispatch?** Hypothesis: yes; `--plugin-dir` is a fully-loaded plugin. Verify in Task 1; if no, the plan grows (need to find the missing manifest declaration, or symlink trick from [[reference-cc-agent-discovery]]).
2. **Sub-agent namespace from a marketplace-installed plugin.** Plan 03 emitted directives naming `memory-merger` (bare). Confirm `Task({subagent_type: "memory-merger"})` vs `Task({subagent_type: "gitlore:memory-merger"})` — whichever CC actually accepts. Plan 03's `commands/gitlore/resolve.md` already chose one; verify it matches.
3. **What `claude plugin validate` actually checks.** Existing `ddaanet/claude-plugins/CLAUDE.md` references the tool but doesn't enumerate what it enforces. Discover during Task 5 (validate); if `plugin.json` rejects something, fix and add to the Layer 1 fixture set.
4. **Marketplace entry shape — full or minimal.** `handoff` entry has `version`, `license`, `keywords`, `repository`, etc. `edify` entry omits `version`. Pick the explicit-everything style (matches `handoff`/`gitmoji`); list deliberately for Plan 04.
5. **README presence.** `gitlore` repo has `docs/plugin-readme.md` but no root `README.md`. The marketplace entry's `repository` link will land users on the GitHub page; CC may render `docs/plugin-readme.md` or expect `README.md`. Decide during Task 4 (manifest polish).
6. **Inner-loop fixture: which throwaway repo.** Per [[feedback-dogfood-b]] the gitmoji repo was used previously. Use a fresh `mktemp -d` repo with a single initial commit — no leftover Plan 02 state, no parent submodule history to navigate around.
7. **`/gitlore:install`'s pre-flight under marketplace load.** The existing preflight checks `gh` + `gh auth` + warns on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. Verify nothing in it depends on the plugin source being a cwd or symlink rather than a marketplace cache directory.

---

## Self-review checklist (spec phase)

- ✅ Spec coverage: §2.1's eight in-scope bullets each have a section that owns them (manifest → §6 + Tasks; inner-loop dogfood → §4; publish gitlore → §5; add to claude-plugins → §5/§6; validate → §7.2; outer-loop dogfood → §5/§7.3; install-pathway docs → §3; in-plan backfill → §7.4).
- ✅ Placeholder scan: no TBDs. §8 enumerates explicit open questions for writing-plans, not placeholders.
- ✅ Internal consistency: §6's version-sync convention matches `claude-plugins/CLAUDE.md`. §5's outer-loop steps match the manifest schema referenced in §8.4.
- ✅ Two-repo plan: Plan 04 touches both `gitlore` and `claude-plugins`. Both have changes in §2.1.
- ✅ Test layers map to risks: Layer 1 protects against accidental edits; Layer 2 catches schema errors; Layer 3 catches the only thing that hasn't been exercised in a real CC session — the `Task` dispatch.
- ✅ Dogfood gate is two-tier and explicit (§7.3). Inner loop is the fast iteration; outer loop is the ship gate.
- ✅ Single source of truth for plugin metadata: `gitlore/.claude-plugin/plugin.json`. `claude-plugins/marketplace.json` entries reference it; sync convention documented in §6.
- ✅ Open questions enumerated (§8) for writing-plans to resolve.
- ✅ No code architecture change — Plan 04 is packaging + distribution. Plans 01–03 own the runtime behaviour.

---

# Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make gitlore installable from the `ddaanet/claude-plugins` marketplace such that `/gitlore:resolve` dispatches `memory-merger` end-to-end.

**Architecture:** No new runtime architecture. Two-repo change: polish `gitlore/.claude-plugin/plugin.json`, push `ddaanet/gitlore`, add gitlore to `~/code/claude-plugins/.claude-plugin/marketplace.json`, validate, dogfood twice (inner loop via `--plugin-dir`, outer loop via marketplace install).

**Tech stack:** `bash`, `jq`, `bats-core`, `claude` CLI for `plugin validate`. `git` and `gh` for publishing. Real Claude Code session (with `--plugin-dir` and then without) for §7.3 dogfood.

---

## File layout (target end state)

```
gitlore/
  .claude-plugin/plugin.json              # MODIFY — fill in author/license/repository/keywords
  docs/plugin-readme.md                   # MODIFY — install pathway (marketplace step first)
  tests/plugin_manifest.bats              # NEW — Layer 1 sanity check
  Makefile                                # MODIFY — add `validate` target
  README.md                               # POSSIBLY NEW — see Task 4 / §8.5

claude-plugins/                           # sibling repo
  .claude-plugin/marketplace.json         # MODIFY — add gitlore entry
  README.md                               # MODIFY — add gitlore row to plugin table
```

---

## Conventions for every task

- Same as Plan 03 (`docs/plans/2026-05-21-03-semantic-merge-resolve.md`): bats files load `helpers/setup`, shell scripts begin with `#!/usr/bin/env bash` + `set -euo pipefail`, library functions namespaced `gitlore_<verb>_<noun>`, commit prefix per gitmoji convention.
- Cross-repo: when editing `~/code/claude-plugins`, commit there and push to its `origin` (the `claude-plugins/CLAUDE.md` note about `github` remote name is repo-specific; check before pushing).
- Dogfood (Layer 3) findings get backfilled to Layer 1 or 2 *in this plan*, not in Plan 05.

---

## Task 1: Verify `--plugin-dir` exposes the sub-agent

**Files:** none modified. This is a verification pass — its only output is "yes, agents are exposed" (proceed to Task 2) or "no, manifest declaration needed" (plan grows).

- [ ] **Step 1: Start a session with `--plugin-dir`.**

  ```bash
  # In a fresh terminal:
  cd /tmp
  mkdir -p test-gitlore-discovery && cd test-gitlore-discovery
  git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  claude --plugin-dir /Users/david/code/gitlore
  ```

- [ ] **Step 2: From the session, confirm available skills + agents.**

  Look at the system-reminder skills list — should show `gitlore:install` and `gitlore:resolve`. Then ask the model: "List the sub-agent types you can dispatch via the Task tool." Confirm `memory-merger` (or `gitlore:memory-merger` — whichever CC reports) appears.

- [ ] **Step 3: Record the result.**

  - **If `memory-merger` appears:** plan proceeds as designed. Record the exact `subagent_type` string (bare vs namespaced) in this task's "outcome" notes. Plan 03's `commands/gitlore/resolve.md` may need a one-character tweak to match.
  - **If it does not appear:** halt. Investigate via [[reference-cc-agent-discovery]] — likely need an explicit declaration in `plugin.json` (CC docs reference). Append a Task 1b "research + update plugin.json" before Task 2 can proceed.

- [ ] **Step 4: Commit nothing.**

  This task changes no files; the outcome is captured in the plan checkbox and next session's working memory.

---

## Task 2: Polish `gitlore/.claude-plugin/plugin.json`

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Create: `tests/plugin_manifest.bats`

- [ ] **Step 1: Write `tests/plugin_manifest.bats` (red).**

  ```bash
  #!/usr/bin/env bats

  load helpers/setup

  MANIFEST="$PLUGIN_ROOT/.claude-plugin/plugin.json"

  @test "plugin manifest: file exists" {
    [ -f "$MANIFEST" ]
  }

  @test "plugin manifest: parses as JSON" {
    run jq . "$MANIFEST"
    [ "$status" -eq 0 ]
  }

  @test "plugin manifest: required + Plan-04 fields populated" {
    for key in name version description author license repository keywords; do
      run jq -er ".$key" "$MANIFEST"
      [ "$status" -eq 0 ] || { echo "missing/empty field: $key"; return 1; }
    done
  }

  @test "plugin manifest: name is exactly 'gitlore'" {
    [ "$(jq -r .name "$MANIFEST")" = "gitlore" ]
  }

  @test "plugin manifest: version is semver-shaped" {
    v=$(jq -r .version "$MANIFEST")
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  }

  @test "plugin manifest: repository points at GitHub" {
    repo=$(jq -r .repository "$MANIFEST")
    [[ "$repo" == https://github.com/* ]]
  }
  ```

- [ ] **Step 2: Run; confirm red.**

  Run: `bats tests/plugin_manifest.bats`
  Expected: ≥4 failures (missing author/license/repository/keywords; placeholder homepage).

- [ ] **Step 3: Update `.claude-plugin/plugin.json`.**

  Target shape (mirror handoff/gitmoji entries' field set):

  ```json
  {
    "name": "gitlore",
    "version": "0.1.0",
    "description": "Versioned, shared, git-backed memory for Claude Code — survives /clear, syncs across worktrees and machines.",
    "author": {
      "name": "David Allouche",
      "email": "david@ddaa.net"
    },
    "license": "MIT",
    "repository": "https://github.com/ddaanet/gitlore",
    "homepage": "https://github.com/ddaanet/gitlore",
    "keywords": [
      "memory",
      "git",
      "submodule",
      "claude-code",
      "sub-agent",
      "semantic-merge"
    ]
  }
  ```

  Adjust description if writing-plans has a better one-liner from `docs/design.md` §FRs.

- [ ] **Step 4: Run; confirm all green.**

  Run: `bats tests/plugin_manifest.bats`
  Expected: 6/6 passing.

- [ ] **Step 5: Commit.**

  ```bash
  git add .claude-plugin/plugin.json tests/plugin_manifest.bats
  git commit -m "📝 docs: fill in plugin.json metadata + sanity-check fixture"
  ```

---

## Task 3: Inner-loop dogfood — `--plugin-dir` end-to-end

**Files:** none modified directly. Findings (if any) feed Task 3b (in-plan backfill).

The point of this task is to be the first time the full memory-merger flow runs in a real CC session.

- [ ] **Step 1: Construct a throwaway parent repo.**

  ```bash
  workdir=$(mktemp -d /tmp/gitlore-dogfood.XXXXXX)
  cd "$workdir"
  git init -q
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "init"
  # gh-create a private memory remote for the install. Reuse Plan 02's expectation:
  # /gitlore:install will gh-create the memory remote in $owner/<name>-memory.
  ```

- [ ] **Step 2: Start a CC session with `--plugin-dir`.**

  ```bash
  claude --plugin-dir /Users/david/code/gitlore
  ```

  In the session: confirm `gitlore:install` skill is loaded; confirm `memory-merger` is a dispatchable sub-agent (recap of Task 1).

- [ ] **Step 3: Run `/gitlore:install`.**

  Accept defaults (memory path = `memory`); precommit command = something trivial that always exits 0 (e.g., `true`). Observe full install: submodule created, remote created (will be `ddaanet/gitlore-dogfood-NNN-memory` or similar — manually delete afterwards), hooks wired.

- [ ] **Step 4: Induce a branch-vs-live divergence.**

  After `/gitlore:install`, both `live` and the worktree branch (e.g. `main`) point at the initial memory commit. To create the divergence, simulate "another session" advancing `live` directly:

  ```bash
  # In the dogfood parent repo, alongside the open CC session:
  parent_branch=$(git rev-parse --abbrev-ref HEAD)   # whatever the parent's current branch is
  (
    cd memory
    git checkout -q live
    echo "live-side" > LIVE.md
    git add LIVE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Live commit (simulated other session)"
    git checkout -q "$parent_branch"                 # back to the memory worktree branch
  )
  ```

  Then, inside the CC session, ask Claude to edit `memory/MEMORY.md` (adding any content) and commit:

  ```
  edit MEMORY.md to add a note, then commit
  ```

  Claude runs through its commit flow: edits MEMORY.md, runs the precommit cmd (`true`), summarizes, asks for approval, writes the commit-msg file, runs `git commit` in the parent. The pre-commit hook fires, commits memory on the worktree branch (which now diverges from `live`), tries to ff-push into `live`, fails → directive emitted.

- [ ] **Step 5: Observe the directive + dispatch.**

  The session should pick up the directive and dispatch `memory-merger`. The sub-agent should: read the state file, read `MEMORY.md` (or whatever's in `changed_files`), synthesize, present a summary, and on approval run the continuation. Approve.

- [ ] **Step 6: Verify the merge landed.**

  After the continuation: `git -C memory log --first-parent live --oneline` should show `live` as a linear trunk with the new merge commit; `git -C memory rev-parse worktree` should equal `git -C memory rev-parse live`. The original `git commit` retry should now succeed (or surface naturally as the next step in the session).

- [ ] **Step 7: Catalog findings.**

  For every surprise (directive shape, sub-agent confusion, state-file path issue, CWD assumption, anything): write it down. Each finding becomes a Task 3b sub-step.

- [ ] **Step 8: Repeat the scenario for local-vs-remote if time permits.**

  Optional; only if Step 7 surfaced nothing significant. If branch-vs-live revealed issues, fix them first and re-run before tackling local-vs-remote.

- [ ] **Step 9: Clean up.**

  Delete the throwaway parent repo and any GitHub `gitlore-dogfood-*-memory` repos created during install. Document the cleanup in the task notes.

---

## Task 3b: In-plan backfill of Task 3 findings

**Files:** depends on findings. Likely candidates from prior plans' analogous tasks:

- `scripts/lib/resolve.sh` (directive shape, state-file IO)
- `agents/memory-merger.md` (sub-agent prompt clarity)
- `commands/gitlore/resolve.md` (Task dispatch invocation shape)
- `tests/resolve_merge_*.bats` (regression fixtures for new failure modes)

- [ ] **Step 1: For each Task 3 finding, write a failing test.**

  If the finding is something bats can express (state-file content, directive substring, file path resolution), add it to the relevant existing test file. If the finding is sub-agent-prompt-related, encode the expected behaviour as a comment in the prompt and re-run inner-loop dogfood.

- [ ] **Step 2: Fix in the appropriate file.**

- [ ] **Step 3: Re-run inner-loop dogfood to confirm fix.**

- [ ] **Step 4: Run full bats suite to confirm no regression.**

  Run: `make test` (or equivalent — Plan 02 uses `bats tests/`).

- [ ] **Step 5: Commit per finding** (one commit per logical fix; never lump unrelated fixes).

  ```bash
  git commit -m "🐛 fix: <one-line description of finding> [Plan 04 dogfood]"
  ```

---

## Task 4: Install-pathway documentation

**Files:**
- Modify: `docs/plugin-readme.md`
- Possibly create: `README.md` (per §8.5 — decide after looking at how CC renders the GitHub landing page)

- [ ] **Step 1: Look at current `docs/plugin-readme.md`.**

  Read the file. Decide whether to (a) point users to a root `README.md` or (b) keep landing content in `docs/plugin-readme.md`. Match the pattern used by `ddaanet/handoff` and `ddaanet/gitmoji`.

- [ ] **Step 2: Document the install pathway.**

  Top of the README should answer: "what is gitlore, how do I install it, how do I use it?" Install section explicit shape:

  ```markdown
  ## Install

  ```
  /plugin marketplace add ddaanet/claude-plugins
  /plugin install gitlore@ddaanet
  ```

  Then, in any project you want to use gitlore in:

  ```
  /gitlore:install
  ```

  Requires `gh` CLI authenticated to create the memory remote.
  ```

- [ ] **Step 3: Commit.**

  ```bash
  git add docs/plugin-readme.md README.md  # if both
  git commit -m "📝 docs: document marketplace install pathway"
  ```

---

## Task 5: Add `validate` Makefile target + run it

**Files:** modify `Makefile`.

- [ ] **Step 1: Add `validate` target.**

  ```makefile
  validate:
  	claude plugin validate .
  ```

  Use a tab for the recipe line, per Makefile syntax.

- [ ] **Step 2: Run it.**

  ```bash
  make validate
  ```

  If `claude plugin validate .` exits 0: proceed. If non-zero: fix per the validator's output, re-run, repeat. Add any new field requirements that surface here to `tests/plugin_manifest.bats` (Task 2).

- [ ] **Step 3: Commit.**

  ```bash
  git add Makefile
  git commit -m "🔧 chore: make validate runs claude plugin validate"
  ```

---

## Task 6: Push `ddaanet/gitlore`

External action — D8-equivalent: visible side effect outside the local machine. Confirm with the user before pushing if the working session is autonomous.

- [ ] **Step 1: Verify pre-push state.**

  ```bash
  git -C /Users/david/code/gitlore status
  git -C /Users/david/code/gitlore log --oneline origin/main..HEAD | wc -l   # should match handoff's "25 commits ahead"
  ```

- [ ] **Step 2: Push.**

  ```bash
  git -C /Users/david/code/gitlore push origin main
  ```

  The plugin's own pre-push hook will fire — gitlore is not installed on itself, so the `git config --file .gitmodules submodule.gitlore-memory.path` guard should make it a silent no-op. If anything fires, investigate before pushing again.

- [ ] **Step 3: Sanity check the GitHub side.**

  ```bash
  gh repo view ddaanet/gitlore | head
  ```

  Confirm latest commit appears.

---

## Task 7: Add gitlore to `ddaanet/claude-plugins`

**Files:**
- Modify (in sibling repo): `~/code/claude-plugins/.claude-plugin/marketplace.json`
- Modify (in sibling repo): `~/code/claude-plugins/README.md`

- [ ] **Step 1: Add the entry.**

  In `~/code/claude-plugins/.claude-plugin/marketplace.json`, append a `plugins[]` entry matching the `handoff` shape:

  ```json
  {
    "name": "gitlore",
    "source": {
      "source": "github",
      "repo": "ddaanet/gitlore"
    },
    "description": "Versioned, shared, git-backed memory for Claude Code — survives /clear, syncs across worktrees and machines.",
    "version": "0.1.0",
    "author": {
      "name": "David Allouche"
    },
    "repository": "https://github.com/ddaanet/gitlore",
    "license": "MIT",
    "keywords": [
      "memory",
      "git",
      "submodule",
      "claude-code",
      "sub-agent",
      "semantic-merge"
    ]
  }
  ```

  Keep description identical to `gitlore/plugin.json` (single source of truth elsewhere; this is a mirror).

- [ ] **Step 2: Update `README.md`.**

  Add a row to the plugin table:

  ```markdown
  | [gitlore](https://github.com/ddaanet/gitlore) | Versioned, shared, git-backed memory for Claude Code | `ddaanet/gitlore` |
  ```

- [ ] **Step 3: Validate.**

  ```bash
  (cd ~/code/claude-plugins && claude plugin validate .)
  ```

- [ ] **Step 4: Commit + push.**

  ```bash
  cd ~/code/claude-plugins
  git add .claude-plugin/marketplace.json README.md
  git commit -m "🎉 list gitlore 0.1.0"
  git push origin main   # or `github main` per claude-plugins/CLAUDE.md — check first
  ```

---

## Task 8: Outer-loop dogfood — marketplace install

**Files:** none modified directly. Findings (if any) get backfilled per Step 4 below, reusing Task 3b's pattern.

- [ ] **Step 1: Fresh CC session, no `--plugin-dir`.**

  ```bash
  workdir=$(mktemp -d /tmp/gitlore-marketplace.XXXXXX)
  cd "$workdir"
  git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  claude   # plain, no --plugin-dir
  ```

- [ ] **Step 2: Install gitlore from the marketplace.**

  ```
  /plugin marketplace update ddaanet
  /plugin install gitlore@ddaanet
  ```

  Wait for the plugin to load. Confirm `gitlore:install` is now in the available skills list.

- [ ] **Step 3: Repeat Task 3's full divergence flow.**

  Identical to Task 3 steps 3–6. Pass criterion: identical observable behaviour to the inner loop.

- [ ] **Step 4: If anything differs from inner-loop, backfill.**

  Any difference between `--plugin-dir` and marketplace-install semantics is a real-world bug *and* a new reference memory worth saving. Follow the same loop as Task 3b.

- [ ] **Step 5: Clean up.**

  Delete the throwaway parent repo and any `*-memory` repos created.

---

## Task 9: Ship-ready commit + handoff

- [ ] **Step 1: Run the full test suite.**

  ```bash
  make test         # bats
  make validate     # claude plugin validate
  ```

  Both must be green.

- [ ] **Step 2: Tick the Plan 04 checkboxes in this file.**

- [ ] **Step 3: Update memory.**

  - If Task 1 / Task 8 surfaced anything novel about `--plugin-dir` vs marketplace, update [[reference-cc-agent-discovery]] in user memory.
  - Add or update `[[reference-cc-plugin-validate]]` if the validator surfaced anything non-obvious about its checks.
  - Trim the Plan 03 `[[reference-cc-agent-discovery]]` "Implication for gitlore Plan 04" section now that Plan 04 has shipped — replace with the live state.

- [ ] **Step 4: Commit the ship.**

  ```bash
  git add docs/plans/2026-05-22-04-marketplace-install.md
  git commit -m "📝 docs: tick Plan 04 checkboxes — shipped end-to-end"
  ```

- [ ] **Step 5: Write the Plan 05 handoff.**

  Plan 05 candidates per Plan 03 §2.2:
  - `WorktreeCreate` / `WorktreeRemove` hooks (original Plan 04, deferred here)
  - Clone-from-remote smoke + docs polish (original Plan 05)

  Don't pre-decide. Per [[feedback-plan-late]], the next session writes Plan 05 after Plan 04 is fully shipped.
