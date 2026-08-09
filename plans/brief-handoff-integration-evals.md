## Brief: handoff+gitlore integration evals — commit-awareness routing

2026-08-05

Add eval scenarios covering the seam between the two plugins: handoff's
commit-awareness decision selects a routing, and the observable consequence is
entirely gitlore's — which commit ends up carrying the memory.

### Decisions

- **The evals live here, not in handoff.** They test handoff paths that are
  gitlore-specific, and every assertion is about gitlore state. handoff's own
  bats can assert what the directive *says*; nothing anywhere asserts that the
  resulting commit routing works.
- **Mechanism only, not judgement.** Scenario prompts declare the mode outright
  — the same scripted shape as scenarios 01/02, per this suite's rule that
  telling the agent to go find something grades a search instead of the flow.
  Whether the agent *picks* the right mode is deliberately out of scope (see
  Rejected).
- **Two scenarios, one per branch of the routing.**
  - `with-commit`: memory dirty, agent writes `.claude/gitlore-memory-message`
    and **not** the trigger file; the assertion fires the parent `git commit`
    and proves one commit carries both the source change and the gitlink bump.
  - `without-commit`: agent writes the message file **and**
    `.claude/gitlore-commit-memory`; gitlore's `PostToolBatch` commits memory
    standalone, with no parent commit involved.
- **The load-bearing assertion is the negative** — under `with-commit` the agent
  never writes the trigger file. handoff's checkpoint deliberately never names
  that path in its `with-commit` directive text, on the reasoning that a fresh
  agent has no other source for the filename, so silence is what makes the
  standalone commit unreachable. This eval is the behavioural check on that
  reasoning; handoff's unit-level version of it is mutation-checked, this one
  should be too.
- **The payload is read from `transcript.jsonl`**, which the runner already
  captures — `jq` over `.message.content[] | select(.type=="tool_use")`,
  selecting `Bash` and reading `.input.command`, then extracting the JSON
  heredoc handed to `handoff-checkpoint`. Same shape as `asserts/recall.sh`'s
  tool-call query. No new capture mechanism is needed.

### Constraints

- **handoff lives at `/Users/david/code/handoff`.** Its skills invoke
  `handoff-checkpoint` **by bare name from PATH** — Claude Code puts every
  enabled plugin's `bin/` on PATH. This fixture bypasses plugin installation
  (copies skills/commands into `.claude/`, resolves hooks into
  `settings.json`), so PATH will not carry it and the call dies with
  `command not found`. Solve before anything else: either export
  `PATH="$HANDOFF_ROOT/bin:$PATH"` from the runner, or install handoff as a
  real plugin in the fixture. This is the single largest unknown in the task.
- **`lib/setup.sh` wires exactly one plugin** — it resolves `$PLUGIN_ROOT` from
  gitlore's own `hooks/hooks.json` and copies gitlore's skills and commands. It
  needs to become two-plugin aware. Keep the derived-never-hand-listed rule for
  handoff's hooks too: read its `hooks/hooks.json` wholesale, substituting its
  own `${CLAUDE_PLUGIN_ROOT}`.
- **handoff's checkpoint refuses without a session root pointer** at
  `/tmp/claude/handoff-root-<session_id>`, written by its wildcard-matcher
  `SessionStart` hook. Wiring handoff's hooks whole should satisfy this; verify
  it early, because the refusal is the first thing a misconfigured fixture will
  produce. Note this mechanism is under active redesign in handoff (a
  `PreToolUse(Bash)` hook injecting the root via `updatedInput`), so do not
  build an assertion that pins the pointer file itself — assert the outcome.
- **The `commit` field's *semantics* are changing in handoff; its *routing* is
  not.** A pending pass rewrites how the agent decides the field (from "will a
  commit land" to "does the ask imply a commit"). Both branches' downstream
  consequence — trigger file or no trigger file, and where memory lands — is
  untouched. That is why this can be built now.
- Assertions get tested in `lib/asserts.bats` against a good end state and
  against the specific breakage each catches, per this suite's existing rule.
- Budget: the current 2-scenario × 5-trial matrix runs ~$0.5 and ~2 minutes, so
  two more scenarios roughly doubles it. Evals are opt-in, not in the default
  gate.

### Rejected approaches

- **claude-plugin-dev as the home.** It is shared release mechanism and carries
  nothing consumer-specific by design.
- **handoff hosting its own copy of the runner.** Duplicates 162 lines of
  harness, and the state every assertion inspects belongs to gitlore anyway.
- **Evals for handoff's routing/judgement fields** (did the agent pick the right
  mode; does the ask imply a commit). Faithfulness is the entire value there and
  it is exactly what a fixture cannot manufacture — every trial is a fresh
  throwaway repo with a two-sentence prompt, i.e. zero context noise, while the
  real decisions are made deep in loaded sessions. Retroactive scraping of real
  session transcripts is the better instrument for that half, and it costs
  nothing.
- **A payload-capturing stub `handoff-checkpoint` earlier on PATH.**
  Unnecessary — `transcript.jsonl` already carries the tool_use verbatim.
- **Having the checkpoint log its judgement fields.** A strict subset of what
  the transcript already holds, not retroactive, and it discards the context the
  judgement was made in.

### Additional context

The routing being tested, in one line each: handoff's checkpoint emits a memory
directive when the `gitlore-memory` submodule is registered and dirty; under
`without-commit` it also tells the agent to write
`.claude/gitlore-commit-memory`, which gitlore's `PostToolBatch` consumes to
commit memory standalone; under `with-commit` that trigger is withheld and the
parent commit's pre-commit hook bundles memory into the source commit. Both
paths end with the approved-summary gate, so both scenarios need the approval
turn (`approval_message`).

The failure this protects against is silent and asymmetric. A spurious
`without-commit` makes a noisy standalone commit — recoverable. A spurious
`with-commit` withholds the trigger and, if no parent commit follows, leaves
memory uncommitted until the next session's memory write stales the approved
summary and aborts the commit that would have collected it.
