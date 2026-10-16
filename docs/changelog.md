# gitlore Changelog

How the design got to its current shape. Each entry is a write-time record of
one change: what moved, and the reasoning available at the time. The living
design is [design.md](design.md).

Newest first. Entries older than 2026-07-31 are indexed in
[changelog-archive.md](changelog-archive.md).

- [2026-10-16 — The rewrite scripts name their remote and their next step](changelog/2026-10-16-the-rewrite-scripts-name-their-next-step.md)
  — `record-rewrite.sh` names the remote it used; `cross-rewrite.sh` refusals
  name the act that resolves them, fetch each child's record once, and read ids
  at the store's object-format length (40 sha1, 64 sha256); a damaged record is
  rebuilt from scratch from the commit-maps at hand (D63)
- [2026-10-16 — A script sources the libraries shipped beside it](changelog/2026-10-16-a-script-sources-the-libraries-beside-it.md)
  — the memory entry points and the push and memory-commit hooks take their
  plugin root from their own path, not from `gitlore.hooksDir`, so a newer
  script run by path no longer sources an older cache's libraries
- [2026-10-15 — A clone on rewritten history is refused, not merged back](changelog/2026-10-15-a-clone-on-rewritten-history-is-refused.md)
  — a rewritten store publishes an append-only `gitlore/rewrites` record (D61);
  a divergence whose local side holds a recorded old commit is refused at the
  yield and named at SessionStart (D62); `record-rewrite.sh` writes the record
  and `cross-rewrite.sh` crosses one store by hand
- [2026-10-12 — A dying batch hook reports instead of ending the turn](changelog/2026-10-12-a-dying-batch-hook-reports-instead-of-ending-the-turn.md)
  — a `PostToolBatch` hook that dies reports on `systemMessage` and
  `additionalContext` and exits 0 (D60), where exit 2 ended the turn silently
  and exit 1 told the agent nothing; the sync and compose hooks claim their
  baseline by rename; the upgrade notice survives an unparseable payload and an
  unwritable marker
- [2026-10-11 — A commit request is not approval](changelog/2026-10-11-a-commit-request-is-not-approval.md)
  — the standing commit orientation says a request to commit memory is not
  approval of an unseen summary (D58 made the call the only gate); the nudge
  reset runs on `SessionStart(startup|clear|compact)` only, with no `PreCompact`
  registration (D21); eval scenarios fail a commit made before approval
- [2026-10-11 — SessionStart reports and never moves memory](changelog/2026-10-11-session-start-reports-and-never-moves-memory.md)
  — the clean-only fast-forward is retired (D59): in a single checkout HEAD
  equals `live` by construction, so it never had work; SessionStart reports
  where memory stands and what the remote holds, and `/gitlore:merge` takes the
  local move; the commit instruction carries its summary on stdin
- [2026-10-11 — A memory commit is the agent's own act](changelog/2026-10-11-a-memory-commit-is-the-agents-own-act.md)
  — the parent `pre-commit` hook, its wiring and the commit nudge are retired
  (D58): `commit-memory.sh` is the one commit path and stages the moved gitlink;
  `gitlore-pre-commit` stays an exit-0 stub for tracked hook-manager configs;
  D16 and D12's orientation invert
- [2026-10-11 — The launcher stops loading the checkout](changelog/2026-10-11-the-launcher-stops-loading-the-checkout.md)
  — `GITLORE_AUTO_CLAUDE_PLUGIN_DIR` leaves the launcher shim and is now
  ignored: `--plugin-dir .` made the repository root an inline plugin root,
  under which Claude Code holds every edit; gitlore dogfoods through the
  toolkit's shim and its `dist/plugin/` copy instead
- [2026-09-26 — A tier's prepared merge outranks the screens too](changelog/2026-09-26-a-tiers-prepared-merge-outranks-the-screens-too.md)
  — `gitlore_store_mid_merge` read the root store only, so a tier's own
  head-vs-live merge missed every screen it was meant to outrank;
  `gitlore_any_store_mid_merge` composes the check over every mounted tier
- [2026-09-26 — Three briefs triaged, and the mount learns its own size](changelog/2026-09-26-three-briefs-triaged-and-the-mount-learns-its-size.md)
  — the `SessionStart` commit-protocol context drops its dangling FR id, the two
  command forms it spelled out and the machinery an agent cannot act on, keeping
  the prohibition by role and the one-line happy path; `/gitlore:index-audit`
  gains a step over the preamble, which routes nothing and is paid for by the
  loader anyway; and a tier mount reports the size of the index its compose
  produced, against the loader cutoff rather than the advisory budget that sits
  above it (D57)
- [2026-09-25 — The macOS tail, a venv python behind a symlink, and a floor under bats](changelog/2026-09-25-the-macos-tail-and-the-floor-under-bats.md)
  — the tail of the unit suite ran on a Mac for the first time and failed 50 of
  1016: a borrowed venv `python3` reached through a symlink resolves to the base
  interpreter, so the probe passed and the suites had no PyYAML; the macOS
  check's own suite read `command -v bash` after the 3.2 stand-in was on `PATH`;
  and three cases asserted on a `$stderr` that bats unsets from 1.13, so the
  README floor rises to 1.13 with `require_bats_version` enforcing it — which
  exposed `require_assertion_bash` refusing by `return`, a refusal bats 1.11
  walks past
- [2026-09-25 — A prepared merge outranks the summary screen](changelog/2026-09-25-a-prepared-merge-outranks-the-summary-screen.md)
  — the batch after a landed-then-failed commit met a prepared merge with a
  request to draft and approve a summary, because the no-summary screen sat
  ahead of the stale-merge guard on both entry points; the clean-store branch
  now really does consume both IPC files, and one `gitlore_approval_present`
  replaces the predicate each entry point spelled out for itself
- [2026-09-24 — The first full macOS run, and the launcher shim that hung it](changelog/2026-09-24-the-first-full-macos-run-and-what-it-found.md)
  — the shim compared raw `PATH` spellings when stripping its own directory, so
  a `//` (which macOS `$TMPDIR` puts in every path built from it) left it on
  `PATH` and its `exec` re-entered it forever; the rest was a symlinked
  `$TMPDIR` the fixtures kept in logical form, two GNU-isms in test bodies, and
  a narrowed `PATH` that dropped `rumdl` and a `python3` carrying PyYAML
- [2026-09-24 — The batch retry is judged by the approval's freshness](changelog/2026-09-24-the-batch-retry-is-judged-by-the-approval-freshness.md)
  — the batch hook passed the commit-message file back as `commit-memory.sh`'s
  own `-F` operand, so each retry restamped the approval and committed the index
  fix it had just asked for under a summary that never saw it; the bare
  invocation leaves that file to the mtime gate, and the hook reads its three
  failure states off the store and the IPC file rather than off the run (D56)
- [2026-09-22 — The 400-line cap is a context budget, so the checker gates scripts, hooks and suites too](changelog/2026-09-22-the-line-cap-is-a-context-budget-and-gates-code-too.md)
  — the cap rations a context window rather than tidying documentation, so
  `check-docs-links.py` walks `scripts/`, `hooks/` and `tests/` as well as
  `docs/`; recorded as D55, the first decision the index carries for a hygiene
  rule
- [2026-09-22 — The changelog index splits at the layout boundary](changelog/2026-09-22-the-changelog-index-splits-at-the-layout-boundary.md)
  — seven post-release entries do not fit under the 400-line cap at any wording;
  entries before the `docs/` + `plans/` layout move to a sibling archive index
- [2026-09-21 — The suite refuses a bats run under bash below 4.1, where its `[[ ]]` assertions pass silently](changelog/2026-09-21-the-suite-refuses-bash-below-4-1.md)
  — a failing non-final `[[ ]]` passes silently under bash 3.2, so a macOS run
  reported green from suites whose assertions never discriminated;
  `require_assertion_bash` refuses the run, and the bash floor splits — 3.2 for
  the shipped scripts, 4.1 for the suite
- [2026-09-21 — A first publish stops printing git's missing-ref line, and the `lint` gate sees the scripts under `plans/`](changelog/2026-09-21-first-publish-skips-the-fetch-and-lint-sees-plans.md)
  — `check_store_gates` skips the fetch when the caller already knows the remote
  has no `live`; the `lint` hash adds the shell files under `plans/`, whose test
  found the gates suite's input assertions holding vacuously under just 1.46;
  and `scripts/test-macos.sh` is the standing macOS run
- [2026-09-21 — Resolve publishes memory's `live` only after every tier gate](changelog/2026-09-21-resolve-publishes-memory-after-every-tier-gate.md)
  — `resolve.sh` pushed memory's `live` on sight of a remote without the branch,
  ahead of every tier gate, so a tier gate refusing afterwards left the memory
  remote holding a gitlink its tier's remote could not resolve (D17); the early
  push is gone and publication falls to the last gate
- [2026-09-20 — The bats gates keep a pass per suite, and the store fixture's copy path costs a third of what it did](changelog/2026-09-20-the-bats-gates-keep-a-pass-per-suite.md)
  — one sentinel over the whole tree made a RED step touching one suite rerun
  all ~100; `run-bats-cached.sh` keeps a key per suite beneath it, verdicts read
  from bats' junit report, and the store fixture drops to 144 ms a call
- [2026-09-20 — `lint` keeps a per-file shellcheck cache beneath its sentinel](changelog/2026-09-20-lint-keeps-a-per-file-shellcheck-cache.md)
  — any edit in the input tree sent `lint` through all 203 files at ~65 s; a key
  per passing file takes an unchanged tree to ~4 s, and the key's closure over
  basenames deliberately over-approximates what shellcheck's `-x` follows
- [2026-09-20 — `lint` covers the untracked files its own hash counts, and the gates suite stops overwriting real sentinels](changelog/2026-09-20-lint-covers-the-untracked-files-its-hash-counts.md)
  — discovery read tracked files while the gate hash counted untracked ones too,
  so a brand-new script recorded a pass shellcheck had never read; and
  `GITLORE_GATE_DIR` sends the gates suite's stubbed verdicts to scratch
- [2026-09-20 — Every script and bats suite on the split list sits under the 400-line cap, by pure moves](changelog/2026-09-20-scripts-and-suites-under-the-400-line-cap.md)
  — the `docs/` cap's argument is about what a reader takes in at one go, not
  about markdown; nineteen pure moves take `lib/resolve.sh` from 2084 lines to
  its gates plus ten siblings, with no checker outside `docs/` enforcing it
- [2026-09-19 — A landed merge whose push fails is reported as landed](changelog/2026-09-19-a-landed-merge-whose-push-fails-is-reported-as-landed.md)
  — the merger and the resolve skill recognise a post-landing push failure as a
  landed merge with its remedy still to run; the post-loop publication pass
  drops an unreachable missing-`origin/live` arm; the root-index refusal has one
  printer; and the scratch copy's two rejected alternatives are recorded (D52)
- [2026-09-19 — A tier ahead of its pin returns to it, and a stray line reaches the check](changelog/2026-09-19-a-tier-ahead-of-its-pin-returns-to-it-and-a-stray-line-reaches-the-check.md)
  — the pin guard returns a clean tier whose `live` holds its commits to the pin
  and directs to `/gitlore:merge`, and the remaining ahead-of-pin refusal no
  longer prescribes a hand rebuild of root's block (D50); the entry-wise index
  merge declines a side with a stray non-bullet line in its pointer block
  instead of dropping it, so the merged-index gate's interleaved rule is
  reachable (D44); the gate's problem lines are recorded in the merge state and
  re-emitted with the directive; a store with no root `MEMORY.md` says once per
  session that composition and the index checks are off, and install always
  scaffolds one; the commit path's unreadable-index-status aborts say why; a
  gate records a pass only for the tree its checks read, `test-unit` ignores the
  integration suites and `plans/*/reports/` is out of the wrap set; and the
  merge skill reports a repair's three outcomes and carries the
  correcting-what-arrived procedure
- [2026-09-18 — Repair and continuation failures say what they left](changelog/2026-09-18-repair-and-continuation-failures-say-what-they-left.md)
  — a failed repair now prints the whole refusal, a remedy that fits its arm and
  what the tier's `live` keeps; its scratch copy moves out of the repository; a
  repair a mid-loop take makes to an already-pushed tier is published by a pass
  after the tier loop; the repair no longer strips the newline from a line it
  leaves last; every pre-landing exit of a merge continuation that has a message
  says the merge was not committed, and the merger and the resolve skill treat
  only exit 0 as a landed merge
- [2026-09-15 — An arrival the root index cannot adopt is repaired](changelog/2026-09-15-an-arrival-the-root-index-cannot-adopt-is-repaired.md)
  — a tier carrier arriving with a duplicate pointer, a stray line or a welded
  line left every take refusing and every push failing, with no local remedy;
  the commit path now aborts on such a problem in an index file it changes
  (D50), a take repairs the arrival with a plain commit that restructures and
  never rewords and publishes it the way the take does (D52), a merge
  continuation keeps a merged index that fails the check unlanded, a push
  refused for any reason but divergence rests the tier only when its `live`
  holds the merge, and `/gitlore:resolve` gates tiers before memory
- [2026-09-13 — The relay is one file per report](changelog/2026-09-13-the-relay-is-one-file-per-report.md)
  — hooks matching one event run in parallel, so the per-agent marker the two
  `PostToolBatch` reporters merged into lost a report to the race and the drain
  branch each carried relayed the survivor twice; a report is now a write-once
  file keyed by session and agent, installed by rename, drained by one hook that
  needs no baseline, and swept by age when the session it names has ended
- [2026-09-13 — A tier merge the root index cannot adopt records nothing](changelog/2026-09-13-a-tier-merge-the-root-index-cannot-adopt-records-nothing.md)
  — a merge continuation whose up projection was refused still staged and
  committed the moved tier gitlink; the merge now lands with nothing recorded in
  the root, and the tier rests on its pin with the merge in its local `live` for
  the next take to adopt
- [2026-09-13 — A take the root index cannot adopt records nothing](changelog/2026-09-13-a-take-the-root-index-cannot-adopt-records-nothing.md)
  — a tier take whose up projection was refused still staged and committed the
  moved gitlink, so the remedy it printed composed root's older text over the
  carrier's newer line; a failed adoption now records nothing, walks the tier
  back to its pre-take commit with the arrival kept in its local `live`, and
  exits 1 so the next take retries it
- [2026-09-13 — A half-landed memory commit retries to completion](changelog/2026-09-13-a-half-landed-memory-commit-retries-to-completion.md)
  — the D50 pin guard refused, for the rest of the session, the retry of a
  commit that had landed a tier and then hit memory's `index.lock`; a landing
  record written before each tier commit lets the retry stage its own commit's
  gitlink, a failure past the freshness gate keeps the approval unless it
  prepared a merge, and the ahead-of-pin remedy stops offering the hand staging
  it refuses
- [2026-09-11 — The hooks node splits from the entry points](changelog/2026-09-11-the-hooks-node-splits-from-the-entry-points.md)
  — `git-hooks-and-entry-points.md` reached the 400-line cap, and the seam its
  own title named splits it into `git-hooks.md` (the two hooks, the gitlink
  invariant, D46, D50) and `memory-entry-points.md` (`commit-memory.sh`,
  `push-memory.sh`, the `push` skill, D16, D20), each rejected alternative
  following the decision it argues against; the room that frees moves
  `gitlore_adopt_recovered_merge` out of D50's body into
  `merge-state-recovery.md`, where the landed-merge case can say what it owes
  the enclosing store
- [2026-09-11 — The commit path composes before it commits](changelog/2026-09-11-the-commit-path-composes-before-it-commits.md)
  — a carrier left stale by a missed in-session compose self-healed at the next
  `SessionStart` but shipped if a memory commit landed first, and the carrier is
  what a tier's remote serves; `gitlore_sync_memory_to_live` now composes ahead
  of the tier commits on dirty stores only, a compose refusal reports while a
  pin refusal aborts rather than let `add -A` adopt the moved gitlink (D50), and
  the `PostToolBatch` baselines are keyed per agent, which is what lets a
  subagent's confined report relay to the parent through a keyed marker (D51)
- [2026-09-07 — The decisions index leaves the hub](changelog/2026-09-07-the-decisions-index-leaves-the-hub.md)
  — `docs/design.md` hit the 400-line cap with a decision waiting; the decision
  groups and their *Rejected* lines move whole into `docs/decisions.md` along
  the need-time seam at `## Design Decisions`, the checker reads conclusions and
  delegations from the index, the hub's two install-time sections collapse into
  one paragraph, and the cap stays uniform
- [2026-09-01 — A tier `live` ahead of its pin is adopted, not checked out](changelog/2026-09-01-a-tier-live-ahead-of-its-pin-is-adopted.md)
  — the publish gate's "put HEAD back on `live`" remedy took a tier off the
  commit the memory store records and composition then refused; a tier whose
  `live` ran ahead is now adopted by the take — working tree, root index and
  recorded pointer together — the gate branches on store kind, and the
  branch-model rationale that called tier gitdirs shared across memory worktrees
  is corrected against git 2.47.3
- [2026-09-01 — A local `live` stranded behind HEAD is advanced, not reported](changelog/2026-09-01-a-stranded-live-is-advanced.md)
  — a failed 0.5.0 merge preparation left HEAD at `origin/live` with the ref a
  push sends still behind, and `/gitlore:merge` read HEAD alone and called the
  store finished; a take and the publish preflight now advance a strictly-behind
  `live` by a local ff-checked push, ahead of the report either would have made,
  and a genuine HEAD/`live` divergence is reported once
- [2026-09-01 — Merge commits are canned and unprompted, and explicit takes leave a clean store](changelog/2026-09-01-merge-commits-canned-takes-commit-bookkeeping.md)
  — both parents of every gitlore merge already passed an approval gate, so
  merges stop prompting and carry canned messages, takes commit their own
  bookkeeping root-first, and push takes a behind store inline (D49)
- [2026-08-28 — The authoring skill is invoked at the three moments that act on facts already written](changelog/2026-08-28-the-authoring-skill-is-invoked-at-three-moments.md)
  — a skill description reaches the moment a fact is drafted, not the commit
  gate, an install that migrated a store, or a tier mount; each of those now
  carries a directive in text gitlore already emits, and the gate's rides the
  shared approval clause so the `handoff` consumer gets it too
- [2026-08-28 — Authoring guidance and index curation ship as plugin surface, not memories](changelog/2026-08-28-authoring-guidance-and-curation-are-plugin-surface.md)
  — the two largest lines in the shared tier were rules for writing memories and
  trimming the index, owned by nothing that fires at those moments; they are now
  the `memory-writing` skill and the `/gitlore:index-audit` command, with a
  write-time hook and an index-size trigger both rejected
- [2026-08-28 — A release push refused by a memory merge is resolved and re-pushed, never amended](changelog/2026-08-28-a-refused-release-push-is-resolved-not-amended.md)
  — a release commit's gitlink is always an ancestor of memory's `live`, so the
  first successful push publishes it and no `commit --amend` + `tag -f` is
  needed; the tip-amend contract of the replay stand-down and the ancestor
  invariant are now stated in the node
- [2026-08-27 — A merge preparation records its state file before it starts](changelog/2026-08-27-merge-state-is-recorded-before-the-merge.md)
  — a killed push left a real staged merge no gate could see, because the state
  file was written only after the preparation returned; a marker now goes down
  first and is completed from the merge itself, and a `MERGE_HEAD` with no state
  file means a merge gitlore did not prepare
- [2026-08-27 — SessionStart writes the root index scaffold back into a store that has none](changelog/2026-08-27-session-start-repairs-a-missing-root-index.md)
  — a store seeded from an empty auto-memory dir ran for weeks with a mounted
  tier that could never compose into it, and the stale-index report never
  noticed the file it read was absent; the scaffold now lands as a dirty file
  the next memory commit reviews
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

Entries before 2026-07-31, written under the repository's previous documentation
layout, are in [changelog-archive.md](changelog-archive.md).
