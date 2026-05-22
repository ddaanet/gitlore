# Plan 04 — Marketplace install

Make `memory-merger` discoverable. Plan 03 shipped the sub-agent file but `Task({subagent_type: "memory-merger"})` no-ops because the plugin isn't marketplace-installed.

## Steps

- [ ] **1. Probe `--plugin-dir` agent discovery.** In a `--plugin-dir /Users/david/code/gitlore` session: `Task({subagent_type: "memory-merger", ...})`. Record whether bare `memory-merger` or namespaced `gitlore:memory-merger` resolves. If neither: investigate before continuing (see [[reference-cc-agent-discovery]]).
- [ ] **2. Fill in `.claude-plugin/plugin.json`** — add `author`, `license: "MIT"`, `repository: "https://github.com/ddaanet/gitlore"`, `keywords` (mirror `handoff`/`gitmoji` shape). Version stays at `0.1.0`.
- [ ] **3. Inner-loop dogfood** in this `--plugin-dir` session: throwaway parent repo (`mktemp -d`), `/gitlore:install`, force branch-vs-live divergence by advancing `live` externally, `git commit`, observe end-to-end loop. Any finding gets fixed + regression-tested in the appropriate Plan-03 bats file *in this plan*.
- [ ] **4. Push `ddaanet/gitlore`** (`git push origin main`; local is N commits ahead). External action — confirm if autonomous.
- [ ] **5. Add gitlore entry to `~/code/claude-plugins/.claude-plugin/marketplace.json`** mirroring `handoff` shape; add row to that repo's `README.md`; `claude plugin validate .` in both repos must exit 0; commit + push.
- [ ] **6. Outer-loop dogfood** in a fresh CC session (no `--plugin-dir`): `/plugin marketplace add ddaanet/claude-plugins` (idempotent), `/plugin marketplace update ddaanet`, `/plugin install gitlore@ddaanet`, repeat Step 3's divergence flow. Any difference from inner loop is a real bug.
- [ ] **7. Document install pathway** in `docs/plugin-readme.md` (and root `README.md` if `ddaanet/handoff` / `ddaanet/gitmoji` have one): `/plugin marketplace add ddaanet/claude-plugins` → `/plugin install gitlore@ddaanet` → `/gitlore:install`. Memory remote requires `gh` only if parent repo has a remote.

## Scope

- **In:** the 7 steps above + in-plan backfill of dogfood findings.
- **Out:** `WorktreeCreate`/`WorktreeRemove` hooks (next plan); clone-from-remote smoke (after that); CI to sync versions between `plugin.json` and `marketplace.json` (manual per `claude-plugins/CLAUDE.md`); cleanup of Plan-02 leftover `ddaanet/gitmoji-gitlore-memory` (orthogonal).

## Open decisions during execution

- **Sub-agent namespace:** bare `memory-merger` vs `gitlore:memory-merger`. Step 1 answers.
- **Root `README.md` vs `docs/plugin-readme.md`:** match whichever pattern `ddaanet/handoff` and `ddaanet/gitmoji` use.
- **Double-prefix slash commands:** `commands/gitlore/install.md` exposes as `/gitlore:gitlore:install`. Flatten to `commands/install.md` would give `/gitlore:install` (clean). Out of scope here; flag for a follow-up.
