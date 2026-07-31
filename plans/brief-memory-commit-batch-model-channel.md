## Brief: memory-commit-batch.sh reports only on the user channel

2026-07-26

Findings from a transcript-corpus measurement run in `/Users/david/code/handoff`.
Everything below concerns `scripts/cc-hooks/memory-commit-batch.sh` in this repo.
Proposed patch alongside this file:
`plans/brief-memory-commit-batch-model-channel.patch`.

### Decisions

- `memory-commit-batch.sh`'s `emit()` should take the two-argument dual-channel
  form the sibling batch hooks already use — `{systemMessage, suppressOutput,
  hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext}}` —
  and all four branches should pass an `additionalContext`.
- The success branch should name the new memory HEAD (`git -C "$mempath" log -1
  --format='%h %s'`). That is precisely the value the agent was running
  `git -C memory log --oneline -1` to obtain.
- The success `additionalContext` should state the outcome is authoritative and
  stand the agent down from confirming it. The stand-down is not speculative —
  it records a defect measured at 62/68.

### Constraints

- `systemMessage` is user-visible and model-blind. This repo already records
  that as D14; `scripts/cc-hooks/session-start.sh` carries the comment
  *"systemMessage is user-only (D14), so without this the agent has no idea"*.
- `add-tier-batch.sh`, `recall-batch.sh` and `index-compose.sh` all pair the two
  channels. `memory-commit-batch.sh` is the only batch hook that does not.
  `add-tier-batch.sh:40-44` is the shape to copy.
- The script runs under `set -euo pipefail` after `gitlore_cd_project_root`, so
  `$mempath` is project-root-relative and `git -C "$mempath"` is correct there.
  Guard the HEAD lookup with `|| memhead='(unavailable)'`; do not name the
  variable `head`.

### Evidence

82 memory-commit landings across ~2179 transcripts, `type:"assistant"` entries
grouped by `message.id` before counting (per-entry counting misreports — one
assistant message is written as N entries).

| path | landings | followed by a verification call |
|---|---|---|
| standalone (trigger file → `PostToolBatch`) | 68 | **62 (91%)** |
| parent commit (`git commit` via Bash) | 14 | 5 (35%) |

The checks are uniform: `ls` the two IPC files, then `git -C memory log
--oneline` or `git -C memory status`. Cost on the standalone path is 1.97 extra
assistant messages per landing (134 total; 0:6, 1:26, 2:18, 3:8, 4:4, 5:5, 7:1),
median 6.4 s each (quartiles 4.7 / 6.4 / 9.6), 539 s in total.

What differs between the two paths is the channel: the parent path returns the
pre-commit hook's output inside a Bash tool result the model reads. One
transcript makes the blindness explicit — after the trigger-cleared message had
already fired, the agent said the hook *"should pick up both files and
commit/push the submodule momentarily"*.

Two further branches are affected. **deferred** fired **144 times** and the
agent never learned; the retry is automatic, so a blind agent either does
nothing or re-triggers pointlessly. **pending** is written as an instruction to
the agent (summarize → get approval → write the summary) on a channel it cannot
read — zero occurrences in the corpus, and `post-tool-use.sh` covers dirty
memory on the model channel, so it is latent rather than live.

### Rejected approaches

- **Blaming the handoff plugin's directive.** `handoff`'s `_probe-lib.sh` tells
  the agent *"If they remain, the commit did not run"*, which would explain the
  checking. Cross-tab rules it out: standalone verifies 58/64 with that
  directive present and 4/4 without it; parent verifies 4/9 with and 1/5
  without. The rate tracks the path, not the directive.
- **Fixing this with a handoff-side directive.** The signal the agent lacks
  belongs to the hook that has it.

### Downstream

Once this lands, handoff's `without-commit` directive text should drop its
closing *"gitlore's PostToolBatch hook commits the submodule and removes both
files on success. If they remain, the commit did not run — report that rather
than retrying."* It is the agent's only signal today, so it must not be cut
before this patch ships. No change is needed on the handoff side otherwise.
