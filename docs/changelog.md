# gitlore Changelog

How the design got to its current shape. Each entry is a write-time record of
one change: what moved, and the reasoning available at the time. The living
design is [design.md](design.md).

Newest first.

- [2026-08-27 — The hook-manager sentinel is replayed from an allow-list, not handed to a shell](changelog/2026-08-27-sentinel-replay-is-an-allow-list.md)
  — the tracked sentinel's fallback arm was `sh -c` on its first line, so a
  clone's first session start ran whatever the clone carried; the replay now
  matches the five lines the wire scripts write and reports anything else
- [2026-08-27 — A prepared merge met by a later gate is continued, never aborted](changelog/2026-08-27-a-prepared-merge-is-always-continued.md)
  — a stale `MERGE_HEAD` used to mean `merge --abort` and prepare again, which
  discarded whatever the merger sub-agent had already synthesized and staged;
  the directive is now the ordinary `continue-after-merge`, and a merge whose
  authority moved meanwhile is re-prepared by the continuation's own refused
  push
- [2026-08-26 — The down projection refuses a tier that was moved off its pin](changelog/2026-08-26-compose-refuses-a-tier-off-its-pin.md)
  — a hand-run `reset --hard` in a tier left the carrier ahead with nothing
  adopted up, and the next recompose wrote root's older text over approved
  upstream facts and called it success; the pin is now checked against the
  memory store's index, and staging the gitlink is the fix
- [2026-08-26 — A merge state file whose MERGE_HEAD a checkout cleared is classified and repaired, not declared unrecoverable](changelog/2026-08-26-stale-merge-state-repairs-itself.md)
  — the state every gate called manual-intervention now sorts into landed,
  staged, or dead, and only a state file naming no pending commit stays a dead
  end
- [2026-08-25 — Every `docs/` file is capped at 400 lines, and the checker enforces it](changelog/2026-08-25-docs-nodes-capped-at-400-lines.md)
  — five files still ran 475–930 lines after the graph split; each cut along a
  need-time seam into 19 reference nodes, the hub's decision conclusions moved
  into each node's opening summary, and `oversized-file` became a blocking check
- [2026-08-25 — docs/ and plans/ are hard-wrapped by a formatter, so a line count means something](changelog/2026-08-25-docs-hard-wrap.md)
  — rumdl (MD013 reflow only) was the one candidate with zero rendering changes
  and untouched emphasis markers; pinned through `uv.lock`, run without a
  sentinel because a pass is ~0.4 s
- [2026-08-24 — The retry wrapper drops its one-checkout-per-branch exception, which the detached model had already made unreachable (D13)](changelog/2026-08-24-retry-wrapper-drops-the-checkout-lock-case.md)
  — every `gitlore_git` checkout has been `--detach` since the branch model
  unified, so no call under the wrapper could produce
  `is already used by worktree at`; the message fails fast through the general
  path regardless, making the deletion behaviour-preserving in the case it
  claimed to cover
- [2026-08-20 — `docs/` becomes a crosslinked graph: the living design split into a hub and reference nodes, with a checker holding the links](changelog/2026-08-20-design-doc-split-into-a-graph.md)
  — at 168.4 KB the doc could no longer be loaded before a structural change,
  and trimming narration recovers ~5.6% before it starts cutting the argument;
  measuring per-section instead produced a need-time split to 44.0 KB, 56.8 ktok
  to 15.2, for +9.4% on the graph as a whole, and `check-docs-links.py` now
  enforces that every pointer resolves and every moved argument left its
  conclusion behind
- [2026-08-14 — Direct hook wiring refuses instead of silently appending after an existing `exec` (D25)](changelog/2026-08-14-hook-install-refuses-after-exec.md)
  — an existing hook body ending in `exec` made the appended gitlore block
  unreachable, so commits succeeded while memory sync silently never ran; the
  installer now refuses and names the fix instead of appending
- [2026-08-14 — The merge directive authorizes its own dispatch instead of offering it (D24)](changelog/2026-08-14-merge-directive-authorizes-its-dispatch.md)
  — a harness rule no repo surface can qualify forbids an unrequested sub-agent
  call, so text that merely names the merger read as an option and a consumer's
  release stalled on a round trip; the directive now says the git operation that
  triggered it is the request for it (D24)
- [2026-08-14 — The divergence merge survives an unterminated final line too, on both the read and the concatenation](changelog/2026-08-14-index-merge-unterminated-final-line.md)
  — the same class one file over: a bare `read` cost a side its last path and
  the presence rule read that as a deletion, and `git merge-file` passes the
  missing newline through so the concatenation welded the first bullet onto the
  preamble
- [2026-08-13 — Every index read survives an unterminated final line, and the writer stops welding a bullet onto an unterminated preamble](changelog/2026-08-13-index-reads-survive-unterminated-final-line.md)
  — a bare `read` discards the last line of an index that ends without a
  newline, and the order merge reads that absence as a deletion, so a carrier
  silently lost a pointer in a real store
- [2026-08-12 — A push classifies a refusal by ancestry, not by git's wording, and a failed diagnosis stops moving HEAD](changelog/2026-08-12-behind-is-not-diverged.md)
  — git rejects a merely *behind* ref with the same reason it gives a diverged
  one, so a store with nothing to publish was sent into a merge that found
  nothing and left HEAD detached on the authority, silently un-adopting the tier
- [2026-08-08 — Active recall became a skill the agent runs, and the hook, request file and ledger came out](changelog/2026-08-08-recall-skill-no-hook.md)
  — `additionalContext` spills past ~2KB and never satisfies
  `Read`-before-`Edit`, so injecting bodies delivered a preview and charged
  twice for anything the agent then corrected
- [2026-08-04 — The shipped surface got its own gate, so a skills-only edit stops reporting cached](changelog/2026-08-04-distribution-gate.md)
  — `precommit_inputs` excludes `agents`/`commands`/`skills` to keep a 7m30s
  suite off prose edits, and `prerelease` is `precommit`, so nothing on the
  release path re-read what the plugin distributes
- [2026-08-03 — Advancing a tier stages its moved gitlink, so the next `SessionStart` stops eating the merge](changelog/2026-08-03-tier-gitlink-staged-after-advance.md)
  — `submodule update` pins from the index, so an unstaged gitlink let the tier
  pass silently revert a just-landed merge while its recomposed index survived
- [2026-08-03 — A tier can carry always-on conventions, and mounting one reports the `CLAUDE.md` import line](changelog/2026-08-03-tier-shared-claude-import.md)
  — a rule that acts without being looked up has no lookup step for an index
  pointer to serve; `shared-claude.md` at a tier root loads whole via an `@`
  import
- [2026-08-03 — A memory store with no remote of its own stops withholding the tiers, in both `/gitlore:push` and `/gitlore:merge`](changelog/2026-08-03-push-tiers-when-memory-has-no-remote.md)
  — a deliberately local-only memory store failed the whole operation, and the
  placeholder url it is recognized by never matched where the checks looked for
  it
- [2026-07-31 — The `docs/` + `plans/` layout adopted: prospective content to a root `plans/`, the changelog split into an index and per-entry bodies](changelog/2026-07-31-docs-plans-layout-adopted.md)
  — plans and specs moved out of `docs/`, and the 61-entry changelog became an
  index plus one frozen file per entry
- [2026-07-31 — A mid-session plugin upgrade is reported, not repaired (D21)](changelog/2026-07-31-plugin-upgrade-reported-not-repaired.md)
  — a live session can't adopt a plugin upgrade; exit + `claude -c` is the only
  fix, so a new hook reports the drift instead (D21)
- [2026-07-30 — Tiers are pinned at the gitlink, composition is two projections, and `/gitlore:merge` is the taking half](changelog/2026-07-30-tiers-pinned-compose-projections.md)
  — auto-fast-forwarding tiers silently reverted upstream facts; tiers now pin
  at the gitlink, compose splits into down/up projections
- [2026-07-29 — Memory can be published without pushing the parent (`/gitlore:push`, D20)](changelog/2026-07-29-standalone-memory-push.md)
  — standalone memory commits (D16) could sit unpushed a whole session;
  `/gitlore:push` publishes tiers and memory without a parent push (D20)
- [2026-07-29 — The memory-approval body became one paragraph per file, with a template, and the clause stopped being a sentence fragment](changelog/2026-07-29-memory-approval-paragraph-per-file.md)
  — one line per changed file dropped the why; approval body is now one
  paragraph per file with a bold Kind prefix and a template
- [2026-07-29 — The changelog became its own file, and the design doc dropped the narrative it had been carrying](changelog/2026-07-29-changelog-split-from-design-doc.md)
  — design.md fused living mechanism with dated history; the changelog split out
  here, catching two claims it had left stale
- [2026-07-28 — The memory-approval wording moved into one file, discovered externally by a git-config key](changelog/2026-07-28-memory-approval-clause-single-file.md)
  — four call sites had drifted once already; canonical approval wording now
  lives in one file, discovered via a git-config key
- [2026-07-27 — `tests/evals/lib/judge.sh` gained a third exit state, so a hedged verdict stops reading as a rubric failure](changelog/2026-07-27-judge-sh-third-exit-state.md)
  — a hedged judge verdict was misread as a rubric failure; judge.sh now
  separates invocation failure from unparseable output
- [2026-07-27 — `refs/gitlore/compose-base` became an audit chain, so a compose can be replayed after the fact](changelog/2026-07-27-compose-base-audit-chain.md)
  — the compose-base ref was overwritten every pass, losing what a merge had
  read; it's now a commit chain any past base recovers from
- [2026-07-27 — Index ordering became merged rather than imposed, in both the divergence merge and the root↔carrier compose](changelog/2026-07-27-index-ordering-merged-not-imposed.md)
  — both merges appended incoming lines at the end, discarding authored
  placement; `gitlore_order_merge` merges the path sequence itself
- [2026-07-27 — The memory merge stopped reading an index as prose, and the compose trigger stopped trusting tool calls](changelog/2026-07-27-memory-merge-and-compose-trigger-fixes.md)
  — five fixes, one shape: what a merge or batch declared was a poor proxy for
  what it did, from diff3 conflicts to `.tool_calls[]`-blind triggers
- [2026-07-27 — `pre-push`'s memory-absent skip warns instead of staying silent when the gitlink it is about to publish is unpublished](changelog/2026-07-27-pre-push-memory-absent-skip-warns.md)
  — the no-memory skip also fired when memory was ahead of its remote, silently
  publishing an unresolvable gitlink; it now warns
- [2026-07-26 — The gate sentinel hashes declared inputs instead of a throwaway index; `run-gate.sh` and the Makefile are both gone](changelog/2026-07-26-gate-sentinel-declared-inputs.md)
  — hashing a real `git add -A` index took a silent dependency on sandbox
  phantom dotfiles; sentinel now hashes only declared paths
- [2026-07-25 — Root↔carrier composition became a path-keyed three-way merge, replacing two point-fixes that each guessed one direction](changelog/2026-07-25-root-carrier-three-way-merge.md)
  — two point-fixes each guessed one propagation direction and both lost data
  live; a three-way merge against a base fixes both at once
- [2026-07-24 — `/gitlore:add-tier` activates as it mounts — dropping the "list it yourself" step, on review that its rationale didn't cover this case](changelog/2026-07-24-add-tier-activates-on-mount.md)
  — the never-auto-populate rule didn't apply to an agent-directed mount;
  `add-tier.sh` now activates instead of a manual listing step
- [2026-07-24 — `prerelease` narrowed back to plain `precommit`; the evals are opt-in, run by name](changelog/2026-07-24-prerelease-narrowed-evals-opt-in.md)
  — the paid eval grid on every release's prerelease gate bought nothing for
  most releases; evals now run by name, on demand
- [2026-07-23 — `resolve` moved from `commands/` to `skills/resolve/SKILL.md`, where the design has placed it since 2026-05-26](changelog/2026-07-23-resolve-moved-to-skill.md)
  — design called it a self-triggering skill since 2026-05-26 but the file
  location lagged; moved to skills/, `/gitlore:resolve` unaffected
- [2026-07-23 — `just release` runs the evals, because the toolkit now binds `release` to a consumer-defined `prerelease`](changelog/2026-07-23-release-depends-on-prerelease.md)
  — plain `just release` used to skip the evals; fixed upstream so `release` now
  requires a consumer-defined `prerelease` recipe
- [2026-07-23 — Two routing-key advisories ride the index→frontmatter sync — and the obvious version of the check was refuted first](changelog/2026-07-23-routing-key-advisory-checks.md)
  — a tf-idf hook-quality scorer was prototyped and killed on the real store; a
  byte-budget check and a missing-trigger check landed instead
- [2026-07-22 — The merge continuation composes, closing the last uncomposed write path](changelog/2026-07-22-merge-continuation-composes.md)
  — a landed merge left the store uncomposed until the next unrelated edit;
  `continue-after-merge` now composes before it commits
- [2026-07-22 — Dangling-pointer report built — the fifth compose validation, and the only one that does not refuse](changelog/2026-07-22-dangling-pointer-report.md)
  — a pointer line naming an absent file was the last presence-authority gap; it
  reports rather than refuses, output stays correct
- [2026-07-22 — One merge policy at every level — a diverged tier now resolves exactly like diverged memory](changelog/2026-07-22-tier-divergence-same-merge-policy.md)
  — a diverged tier just repeated "not yet automated" every session; it now
  resolves through the same gate/yield path memory uses
- [2026-07-22 — Presence-authority settled: the index is authoritative over a pointer line's presence, and nothing is deleted to enforce it](changelog/2026-07-22-presence-authority-settled.md)
  — the index, not the file set, decides whether a pointer line exists; removing
  a line never deletes the file it names
- [2026-07-22 — Happy-path evals now cover the tier flow, active recall, and `/gitlore:add-tier`](changelog/2026-07-22-eval-scenarios-pluggable.md)
  — the eval harness only ever graded one fixed flow; scenarios became
  pluggable, hooks now derived from the plugin's real hooks.json
- [2026-07-22 — D17 slice 3-iii built — mounting a tier is a command, and the agent still runs no git](changelog/2026-07-22-add-tier-command-no-network.md)
  — `add-tier` writes a trigger file because mounting clones and the agent
  sandbox has no network; ends mounted but inactive
- [2026-07-22 — Active recall (FR16/D18) — a memory body can now be fetched from a trigger the prompt never carried](changelog/2026-07-22-active-recall-fr16-d18.md)
  — native recall classifies once against the prompt and never reselects; a new
  skill lets the agent request bodies by path (FR16/D18)
- [2026-07-21 — Tier commit/push lockstep — a fact authored in a tier now persists and publishes with it](changelog/2026-07-21-tier-commit-push-lockstep.md)
  — writing into a tier left it dirty with nothing for the parent commit to
  record, blocking it; tiers now commit/push in lockstep
- [2026-07-21 — Quality gates skip when the tree is what it was the last time they passed](changelog/2026-07-21-quality-gate-sentinel-skip.md)
  — `run-gate.sh` hashes the whole tree via a throwaway index and skips
  precommit/evals when nothing changed since the last green run
- [2026-07-21 — D17 slice 3-ii built — tier pointers reach the always-loaded index](changelog/2026-07-21-tier-pointers-reach-root-index.md)
  — mirror-down now runs for every mounted tier, not just active ones, so a
  never-activated tier's root line stops being dropped
- [2026-07-21 — The memory sync stands down while a rebase, cherry-pick or revert is replaying](changelog/2026-07-21-memory-sync-skips-during-replay.md)
  — staging the gitlink every commit made history surgery hazardous — an amend
  mid-rebase could re-pin the wrong SHA; sync now stands down
- [2026-07-21 — The parent commit now records the memory pointer its own hook just created](changelog/2026-07-21-parent-commit-stages-memory-gitlink.md)
  — pre-commit advanced memory but never staged the gitlink, so every parent
  commit pinned the pre-hook SHA; it now stages $mempath
- [2026-07-21 — Push/fetch-rejection discriminator pinned — and a dead divergence arm found by pinning it](changelog/2026-07-21-push-fetch-rejection-discriminator.md)
  — pinning the rejection-reason call sites found a live bug: `fetch -q` prints
  nothing on non-fast-forward, hiding tier divergence
- [2026-07-20 — Branch model unified — memory is detached at `live`, and there is one commit path](changelog/2026-07-20-branch-model-unified-detached-live.md)
  — the per-parent-branch working branch is gone; memory and tiers detach at
  live with one merge/commit path instead of two
- [2026-07-20 — D17 slice 3-i-a dogfooded — the first real tier is mounted](changelog/2026-07-20-first-real-tier-mounted.md)
  — ddaanet/ddaanet-memory mounted as the first real tier, private since a tier
  takes the stricter visibility of its consumers
- [2026-07-18 — D17 slice 3 (tier composition) designed — free-form multi-tier, ready to spec](changelog/2026-07-18-tier-composition-designed.md)
  — converged the composition mechanism: discovery by enclosure, path-prefix
  identity, self-describing routing, a precedence manifest
- [2026-07-17 — D17 slice 3a (structural recompose) built, then reverted the same day on review](changelog/2026-07-17-structural-recompose-built-then-reverted.md)
  — dedup/prune/coverage were built then reverted the same day — dedup guards an
  unused merge driver, prune/coverage presuppose an open question
- [2026-07-17 — Eval harness dropped the Agent SDK for `claude --print --resume`](changelog/2026-07-17-eval-harness-drops-agent-sdk.md)
  — the SDK's one-process-per-turn framing was false about its own code; dropped
  for a 35-line bash runner, exposing a suite red for a day
- [2026-07-17 — D17 slice 2 (one-time reconcile) dogfooded on this repo's memory](changelog/2026-07-17-one-time-reconcile-dogfooded.md)
  — 5 parallel judges over 60 index lines found only 4 stale ones; two had stale
  bodies too, needing re-verification not just propagation
- [2026-07-16 — D17 SPOT settled empirically + fill-if-empty landed (slice 1 done)](changelog/2026-07-16-spot-settled-fill-if-empty.md)
  — a 528-transcript eval confirmed the index one-liner as canonical ~3:1 over
  frontmatter; sync now fills description only when empty
- [2026-07-14 — Revised D17 — index one-liner is canonical; composition is structural, not frontmatter-derived](changelog/2026-07-14-d17-revised-index-canonical.md)
  — a git-history audit refuted "frontmatter is source of truth" — both surfaces
  drift; index is now canonical, recompose owns presence only
- [2026-07-14 — Designed tiered global/org memory (FR15 + D17)](changelog/2026-07-14-tiered-global-org-memory-designed.md)
  — retrieval instrumentation showed only the root MEMORY.md always loads;
  design: nested submodule tiers, agent-picked routing (FR15/D17)
- [2026-06-18 — Trimmed the standing SessionStart `additionalContext` (refines D12) — prohibition up-front, procedure just-in-time](changelog/2026-06-18-sessionstart-context-trimmed.md)
  — front-loading the full persist procedure made the agent pause for approval
  before even writing; split into prohibition plus just-in-time
- [2026-06-12 — Implemented D16 — standalone memory-commit entry point](changelog/2026-06-12-d16-standalone-memory-commit.md)
  — `commit-memory.sh` commits the memory submodule directly, no parent commit,
  discovered via a re-pinned git-config key (D16)
- [2026-06-10 — Implemented D15 — in-process-worktree memory-drift guard](changelog/2026-06-10-d15-worktree-drift-guard.md)
  — `EnterWorktree` freezes CLAUDE_PROJECT_DIR, stranding memory writes in the
  launch repo; a new hook warns once per episode (D15)
- [2026-06-10 — Implemented D14 — user-facing SessionStart output on `systemMessage`](changelog/2026-06-10-d14-sessionstart-systemmessage.md)
  — fatal notices used to exit 1 to stderr, effectively invisible; they now ride
  `systemMessage`, the only reliably visible channel (D14)
- [2026-06-10 — Documented D13 — lock-contention retry wrapper (`gitlore_git`)](changelog/2026-06-10-d13-lock-contention-retry.md)
  — `gitlore_git` retries a mutating git call on lock contention with backoff,
  threaded through every hook and install script (D13)
- [2026-06-09 — Implemented D12 — submodule-side commit gate closes the FR11 bypass](changelog/2026-06-09-d12-submodule-commit-gate.md)
  — a direct commit inside the submodule bypassed the parent's review gate;
  `memory-pre-commit` now blocks any commit lacking the sentinel (D12)
- [2026-05-31 — Wrapper degrades on a stale (GC'd) hooks dir, not just an unset one (D5 extension)](changelog/2026-05-31-wrapper-degrades-on-stale-hooksdir.md)
  — a plugin upgrade GC's the pinned hooksDir between sessions, hard-failing a
  plain-terminal commit; wrappers now skip-with-hint (D5 ext.)
- [2026-05-29 — Hook detection defaults to `direct`, not `manual`](changelog/2026-05-29-hook-detection-defaults-to-direct.md)
  — a repo with no recognized hook manager fell through to manual, wiring
  nothing; gitlore's own pre-push double-commit hook never fired
- [2026-05-27 — `source_up_if_exists` added to fresh `.envrc`](changelog/2026-05-27-envrc-source-up-if-exists.md)
  — a freshly created .envrc now sources parent-directory direnv configs first
- [2026-05-27 — Prep for 0.2.0 release](changelog/2026-05-27-prep-for-0-2-0-release.md)
  — direnv allow made non-fatal for read-only sandboxes; 2>/dev/null
  suppressions removed except where an error is genuinely expected
- [2026-05-26 — Fixed FR7 clone-restore bug](changelog/2026-05-26-fr7-clone-restore-bug-fix.md)
  — a clone without --recurse-submodules died on checkout -b live; SessionStart
  now materializes a local live from origin/live
- [2026-05-26 — Commands made script-driven (D7 / 12-factor-agents)](changelog/2026-05-26-commands-made-script-driven.md)
  — install.md collapsed to two steps, dispatch moved into run.sh; resolve.md
  became a self-triggering skill on the merge marker (D7)
- [2026-05-25 — Implemented D11](changelog/2026-05-25-d11-gitlink-aware-wrappers.md)
  — all five hook managers now anchor wrappers at the git-common-dir, fixing
  linked-worktree breakage (D11)
- [2026-05-25 — Plan 06 rethink → D11 (gitlink-aware wrappers)](changelog/2026-05-25-plan-06-rethink-d11.md)
  — the wrapper indirection hardcoded .git/gitlore-<hook>, unusable from a
  linked worktree; resolved via git-common-dir anchoring
- [2026-05-25](changelog/2026-05-25-plan-06-worktree-hook-design.md) —
  WorktreeCreate turned out unusable for setup; memory-worktree creation moved
  to SessionStart, covering every worktree entry point
- [2026-05-25](changelog/2026-05-25-released-0-1-1.md) — released to migrate 6
  stranded pre-launcher memories and force /plugin update past the same-version
  stale-cache trap (v0.1.1)
- [2026-05-24](changelog/2026-05-24-plan-05-memory-redirect-launcher-built.md) —
  Plan 05 built the Memory Redirect Launcher and removed the dead
  settings.local.json autoMemoryDirectory writes CC ignores (D10)
- [2026-05-23](changelog/2026-05-23-memory-redirect-reworked-d10.md) — CC only
  honors autoMemoryDirectory from policy/flag/user settings, not
  settings.local.json, so memory was silently stranding (D10)
- [2026-04-23](changelog/2026-04-23-full-design-review.md) — agent-driven commit
  flow replaces user-driven; /gitlore:resolve grew to cover both branch-vs-live
  and local-vs-remote divergence
- [2026-04-11](changelog/2026-04-11-initial-design.md) — the original design
  document, before any code existed
