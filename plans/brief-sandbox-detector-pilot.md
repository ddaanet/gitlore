## Brief: pilot sandbox-symptom detectors before packaging a plugin

2026-09-02

### Decisions

- **`sandbox-effects` knowledge moves from the memory index to hooks wherever
  the symptom is mechanically detectable.** Its index line is 988 bytes of a
  26,171-byte root index measured against Claude Code's ~24,985-byte loader
  cutoff — 3.8% of the budget on one fact, and the overshoot is ~1,186 bytes.
  Retiring that line alone nearly closes the gap, before any of the craft,
  plugin-craft or shell-gotchas relocations land.
- **The gain is bigger than context.** A memory line can only teach a
  discriminator; a hook can *run* it and inject the verdict. `.git/index.lock`
  spends the file's longest section teaching a three-way test whose first step
  is "run `ls -la .git/index.lock` unsandboxed" — a hook does that itself and
  reports "mask, re-run unsandboxed" or "genuinely stale, safe to `rm`". Same
  for `/tmp` full (`du` vs `df`) and phantom dotfiles
  (`find "$CLAUDE_PROJECT_DIR" -maxdepth 1 -type c`).
- **Pilot three detectors, not ten:** `.git/index.lock` (highest value, has an
  executable discriminator), phantom dotfiles (highest false-positive risk, so
  it is the real test of the idea), and sandboxed `claude -p` silently dropping
  `SessionStart` hooks (the only `PreToolUse` of the three, matched on the
  command rather than the output, and a case memory cannot reach at all because
  it produces no symptom).
- **No plugin exists yet.** Packaging is what the pilot decides; it is not a
  precondition. A matcher is a shell function reading stdin and exiting 0/1.
- **Of the twelve sections, ~10 are hook-detectable.** Seven match a clean error
  string, three match output content. The `excludedCommands` whole-call
  semantics has no symptom — it fires while you are *writing* an exclusion list
  — so it becomes a skill. Its home is open: `craft`, or the new plugin if one
  is created.

### Constraints

- **`additionalContext` spills to a file past ~2KB**, so an injected section
  must stay short — a hub-sized paragraph plus the discriminator's verdict,
  never the section verbatim.
- **No hook fires on the `` !`cmd` `` slash-command context-expansion path.**
  Measured 2026-09-02 on CC 2.1.258: a scratch project-level command whose
  `## Context` ran a side-effecting `!` block wrote its flag file, while
  `PreToolUse` and `PostToolUse` with `matcher: "*"` logged only the control
  `Bash` call. Wildcard was used specifically to separate "no hooks on this
  path" from "different tool name". Consequence: the `/commit` `## Context`
  phantom-dotfile case is permanently out of hook reach and must stay prose —
  memory, or a line in `shared-claude.md`. Static corroboration from the bundle
  is in `plans/2026-09-02-bang-expansion-hook-decompile.md`.
- Hooks load at session start, so testing a hook change needs a restart
  (`/handoff:restart`).
- The transcript corpus is this machine's own history. For a plugin only
  ddaanet repos enable, that is the right population, not a sampling flaw.
- Other repos are read-only. `craft`, `plugin-craft` and `prohibitions` get a
  proposal, never an edit.

### Rejected approaches

- **`craft`** — wrong trigger axis. Craft's premise is that its facts fire on a
  *design moment* with no token to match, which is why a skill's task-shaped
  trigger fixes them. Sandbox facts are symptom-keyed error strings, the class
  the memory index routes *well*; their defect is body size (13% reachable), not
  trigger shape.
- **`prohibitions`** — every item there forbids an action the agent is about to
  take. An annotator enriches a tool result instead. The plugin's `SessionStart`
  `excludedCommands` warning is itself a prohibition ("do not run those commands
  sandboxed") enforced by config rather than a deny, so it is not the precedent
  it looked like.
- **A one-hook plugin** for phantom dotfiles alone — not a package. Ten
  detectors justify a repo; one does not.
- **Splitting `sandbox-effects` into a hub plus siblings first** — the content
  survives either way (a hook carries its section as injected text), but the
  file layout would be thrown away. This is the fallback if the pilot fails, not
  a prerequisite.

### The pilot

**Layer 1 — corpus replay. This is the pilot.** Fixtures test whether a matcher
fires on the symptom, which is the easy half; how often it fires when the
symptom is *absent* cannot be synthesized. Run each candidate matcher over every
Bash `tool_result` in `~/.claude/projects` (~1,685 JSONL files across 60
projects — the corpus `plans/2026-09-02-recall-log-analysis.py` already walks).
Count hits, sample them, classify true vs. false positive. Then the recall side:
grep for the incidents `sandbox-effects` documents by date and confirm the
matcher would have caught them. Read-only, nothing installed.

**Layer 2 — fixture suite, after replay.** Recorded stderr in, decision out, as
bats. The ordering is load-bearing: the replay *produces* the fixtures.
Hand-writing them first encodes what the output was expected to look like rather
than what it is.

**Layer 3 — live discriminator checks.** For `index.lock` and `/tmp`-full the
hook runs a probe and injects a verdict; each probe needs one live run against a
real reproduction to prove it returns what the memory claims. Three or four
manual runs, not a suite.

**Decision rule.** Per detector: a hit count and a false-positive rate over real
history. A detector that fires mostly on innocuous output either dies or gains a
confirming probe. If all three hold, name and create the plugin and convert the
remaining seven; if they do not, split `sandbox-effects` in memory as originally
queued and send the `excludedCommands` skill to `craft`.

### Pending

The store still says `PreToolUse` does not run on the `!` path and is silent on
`PostToolUse`. Both are now measured. Fold the correction into whichever
restructuring wins rather than editing a file that may be split or retired.
