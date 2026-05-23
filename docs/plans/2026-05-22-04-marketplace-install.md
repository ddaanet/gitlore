# Plan 04 — Marketplace install

Make `memory-merger` discoverable. Plan 03 shipped the sub-agent file but `Task({subagent_type: "memory-merger"})` no-ops because the plugin isn't marketplace-installed.

## Steps

- [x] **1. Probe `--plugin-dir` agent discovery.** Resolved: `gitlore:memory-merger` works, bare `memory-merger` does not. Updated `commands/gitlore/resolve.md` dispatch site accordingly.
- [x] **2. Fill in `.claude-plugin/plugin.json`** — added `author`, `license: "MIT"`, `repository`, `keywords`, real homepage. Version stays at `0.1.0`.
- [x] **3. Inner-loop dogfood.** Three findings, all fixed in-plan:
  - **GIT_INDEX_FILE leak.** `git commit` sets `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_WORK_TREE` (relative paths) in the hook env. Any `git -C memory <cmd>` inherits them, tries `memory/.git/index`, hits "fatal: .git/index: index file open failed: Not a directory" because `memory/.git` is a gitfile. Fixed by `unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_PREFIX` at the top of `scripts/git-hooks/pre-commit` and `pre-push`. Regression test added: `tests/git_hook_pre_commit.bats` "ignores parent GIT_DIR/GIT_INDEX_FILE leaked by 'git commit'".
  - **Sub-agent approval gate bypassed.** Old contract said "SendMessage the parent" but didn't give the sub-agent a way to address the parent; on `SendMessage to: "parent"` failing, the sub-agent rationalized proceeding without approval and ran the continuation. Fixed by rewriting `agents/memory-merger.md` to a two-turn flow (synthesize → return → resume on approval) and updating `commands/gitlore/resolve.md` to dispatch + read return + `SendMessage` approval to the sub-agent's `agentId`. SendMessage removed from sub-agent's allowed-tools.
  - **Sub-agent namespace.** Bare `memory-merger` does not resolve; `gitlore:memory-merger` does. Fixed in resolve.md (Step 1's recording).
  - **In-session caching limitation.** CC caches agent definitions at session start. The new contract for `memory-merger` won't take effect until a fresh CC session, so the new two-turn flow can't be fully verified in this dogfood — needs re-dogfood in a fresh `--plugin-dir` session before Step 6.
- [x] **4. Push `ddaanet/gitlore`** — done 2026-05-23 (`1d4b38d..3efbb4d main`).
- [x] **5. Add gitlore entry to `~/code/claude-plugins/.claude-plugin/marketplace.json`** — entry + README row added (mirrors `gitmoji`/`handoff` github-source shape); `claude plugin validate` exit 0 in both repos (gitlore has a benign pre-existing CLAUDE.md warning); committed + pushed (`9088b2a`).
- [ ] **6. Outer-loop dogfood** in a fresh CC session (no `--plugin-dir`): `/plugin marketplace add ddaanet/claude-plugins` (idempotent), `/plugin marketplace update ddaanet`, `/plugin install gitlore@ddaanet`, repeat Step 3's divergence flow. Any difference from inner loop is a real bug. Requires a fresh interactive session (cannot be run from this session).
- [x] **7. Document install pathway** in `docs/plugin-readme.md` — done; marketplace add → install → `/gitlore:install`, `gh`-only-if-remote note, and a known-limitation note for the unbuilt redirect launcher (D10). Status table updated.

## Scope

- **In:** the 7 steps above + in-plan backfill of dogfood findings.
- **Out:** `WorktreeCreate`/`WorktreeRemove` hooks (next plan); clone-from-remote smoke (after that); CI to sync versions between `plugin.json` and `marketplace.json` (manual per `claude-plugins/CLAUDE.md`); cleanup of Plan-02 leftover `ddaanet/gitmoji-gitlore-memory` (orthogonal).

## Open decisions during execution

- **Sub-agent namespace:** bare `memory-merger` vs `gitlore:memory-merger`. Step 1 answers.
- **Root `README.md` vs `docs/plugin-readme.md`:** match whichever pattern `ddaanet/handoff` and `ddaanet/gitmoji` use.
- **Double-prefix slash commands:** `commands/gitlore/install.md` exposes as `/gitlore:gitlore:install`. Flatten to `commands/install.md` would give `/gitlore:install` (clean). Out of scope here; flag for a follow-up.
