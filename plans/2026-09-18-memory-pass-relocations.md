# Memory-writing pass, 2026-09-18 — facts relocated instead of saved

A `/gitlore:memory-writing` pass over eighteen facts written from the handoff's
pending list saved none of them as a memory. Each was accurate; each either has
an owner that states it at the moment it matters — a skill in another repository
— or is reached unaided when the failure occurs. A memory copy held "until the
skill carries it" is the wrong home with a deadline nobody tracks. What follows
is material for one note per owning repo — ask before each write. Nothing here
is carried as pending work in gitlore once the notes are dropped.

## shell-scripting (`shell-gotchas`)

- **`references/robustness.md`, "Off inside conditions, transitively".** The
  bullet says any command in an `&&`/`||` chain runs with `-e` disabled. That
  holds for every command *but the last*: in `A || B`, errexit is suspended for
  everything `A` runs — a function's whole body included — and **armed** for
  `B`, whether `B` is a `{ … }` group or a function. A recovery arm written as
  `risky || { report; cleanup; }` reads as "the handler, where failures are
  tolerated" and is the opposite: a failing `report` (closed fd 2, full disk)
  skips `cleanup`. Put the step that must happen first, the fallible one last or
  behind its own `|| true`. Measured on bash 5.2:
  `set -e; false || { false; echo x; }` exits 1 and prints nothing;
  `set -e; f() { false; echo reached; }; f || true` prints `reached`;
  `set -e; f() { false; echo x; }; false || f` exits 1 and prints nothing.
- **`references/environments.md`, "Claude Code specifics", with a pointer from
  `references/bats.md`.** A command run by the Bash tool has a **socket** on fd
  0 (`stat -L -c %F /dev/stdin` → `socket`), and `bats` inherits it; under
  `bats … </dev/null` a test sees a character device instead. A read returns EOF
  at once (`cat | wc -c` gives 0), so `[ -t 0 ] || payload=$(cat)` takes its
  stdin branch with an empty payload, and a test branching on fd 0's type
  (`[ -p /dev/stdin ]`, `[ -c /dev/stdin ]`) sees neither the pipe a hook gets
  nor the `/dev/null` git gives `pre-commit`. A test gives its subject the stdin
  production gives it, explicitly. Measured on Linux, CC 2.1.276.
- **`references/portability.md`.** `$$` is fixed at shell startup and identical
  in every `( … ) &` subshell, so a `tmp.$$` name is shared by concurrent
  writers of one script; `$BASHPID` is per-process and absent on bash 3.2, where
  it expands empty. Use `mktemp`; distinguish test writers by an explicit id.
- **`references/bats.md`, beside "`grep -qF \"$multiline\"` matches any ONE
  line".** `grep -c` counts matching lines: `jq` emits `systemMessage` as one
  JSON string, so a doubled block inside it counts 1. Decode the field first
  (`jq -r .systemMessage | grep -c …`). And `jq -r .key` prints the string
  `null` for an absent key — `// empty`, or `jq -e 'has("key")'` in a test.

## plugin-craft (`hook-authoring`)

- **Every hook matching one event runs in parallel** — "All matching hooks run
  in parallel", code.claude.com/docs/en/hooks — across plugins and inside one
  `hooks.json`, unordered. Documented and still designed against: gitlore's
  subagent report relay first assumed registration order. Two shapes break. A
  shared file each hook read-merge-writes loses the loser's content silently;
  one file per writer has nothing to serialize. The same consumer step placed in
  each hook emits everything twice on a batch that fires both; a consumer
  belongs in one hook of its own. A suite that runs the hooks one after the
  other is green across both defects and their fixes.
- **`references/output-channels.md`, "Blocking asymmetry".** Corollary worth one
  sentence: under `set -e`, a `PreToolUse` guard whose first step is a `jq`
  parse dies with status 5 on a malformed payload (jq 1.7), which is not 2, so
  the guard fails open. A guard that must fail closed catches the parse failure
  and exits 2 itself.

## craft

- **`test-discipline`, `references/genuine-red.md` — pin the moment.** A RED for
  a defect of the form "X happens too late" or "in the wrong step" that asserts
  only the end state is green for any lookalike that gets there later — a retry,
  a second push, a repair pass — including ones that leave the window open. End
  state is the cheapest thing to assert and the fixture already exposes it. Make
  the moment observable and assert on it: a stub `git` or a `pre-receive` hook
  recording what each push offered, an append-only step log, a fixture in which
  the late route is impossible. Before accepting a GREEN, name one wrong
  implementation reaching the same end state and check the test reds it. Three
  tier-publication ordering slices in gitlore each asserted the remote's end
  state, and review, not the test, found the gap.
- **`test-discipline`, `references/genuine-red.md` — a mutation proof goes
  stale.** The mutation a born-green test's comment names is a measurement of
  one implementation. When the subject changes again — a review fix, a refactor
  — that mutation may fail for an unrelated reason, and the case passes under it
  with the defect present while the comment still claims the proof. Re-apply the
  named mutation after every subject edit and confirm the same line reds; if it
  no longer does, find the mutation expressing the same wrong implementation
  against the new code, or the test is vacuous. A reviewer who weakens a proof
  fixes it in the same pass: flagging it as a residual gives a vacuous test a
  paper trail and leaves it vacuous.
- **`test-discipline`, `references/non-vacuous-negatives.md`, "Ordering under
  errexit".** One sentence of increment: in a RED run the first failing line is
  the death point, and every assertion *and cleanup line* below it has never run
  against any code — a test review lists what sits below and says which run
  proves it.
- **`test-discipline`.** Discarded as a step from "path staleness": a case whose
  meaning depends on a fixture property asserts that property itself
  (`run ! git merge-base --is-ancestor …`, `case "$p" in *\ *)`) rather than
  trusting a helper's name, so a repointed helper reds instead of going vacuous.
- **`directive-writing`, "Distributed text never cites private files" and "Code
  comments take the same cut".** The increment: the same cut covers runbook item
  and slice ids (`Item 1.3`, `the GREEN report`) and `file:NNN` line numbers,
  which subagent-written comments carry by default because the dispatch prompt
  is their vocabulary for *why*. Sweep:
  `grep -nE 'plans/|memory/[a-z]|Item [0-9]|slice|GREEN|\.bats:[0-9]|runbook'`.

## edify (fold into the brief already listed in the handoff)

- **A report cannot cite its own commit.** A dispatch asking for "one commit per
  slice, report included" and "cite the commit sha in the report" asks for the
  impossible; executors resolve it with an extra commit, a parent sha, or an
  amend loop, and the TDD audit reads each as a defect. The dispatch decides:
  the report rides the slice commit and cites no sha, or it is its own commit by
  construction and the audit is told so.
- **A runbook's `file:NNN` goes stale once an earlier phase edits the file.**
  Runbooks name tests by `@test` name and code by function; the orchestrator
  resolves any `:NNN` to a name against the current tree before composing a
  dispatch.

## Discarded with no relocation

- **Exit status is the landed signal** — the general claim is unarguable and the
  instance is owned by `skills/resolve/SKILL.md` ("only an exit 0 is a landed
  merge").
- **Where an approval-restamp test stands** — owned by the comment in
  `tests/commit_memory.bats`'
  `a tier moved sideways off its pin aborts the commit`, which says what it
  cannot observe and names the case that can, and by
  `docs/references/git-hooks.md`.
- **A fixed-order test cannot show a race** — unarguable; its instance rides the
  parallel-hooks note above.
- **Temp-then-rename traps** (`mv` into an existing directory exits 0 and moves
  the temp inside; a temp named inside the reader's glob is consumed) — both
  were review hardening on the relay, not observed failures, and each is one
  step for a reader who writes down the reader's pattern.
- **`find` is `bfs` on the dev box** — `bfs: error: Invalid timestamp` names the
  cause and lists the accepted formats when it occurs; the silent variant under
  `2>/dev/null` is the tier fact `no-stderr-suppression`'s.
- **Ambient `CLAUDECODE=1`** — a case red by hand and green under dispatch shows
  the agent wording against the human one in its own diff, and the tier's
  conventions file already says pre-set env vars mask this under bats.
- **An unconditional fixture restore dies at GREEN** — it fails on its own
  cleanup line with `No such file or directory`, naming itself.
