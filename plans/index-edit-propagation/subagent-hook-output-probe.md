---
name: subagent-hook-output-probe
---

# Does subagent hook output reach the parent session?

## Question

When a Claude Code hook fires from inside a subagent (a Task/Agent tool
invocation), does any of its output — `systemMessage` or
`hookSpecificOutput.additionalContext` — reach the parent session's context or
the parent's user-visible output, or is it confined to the subagent?

Working hypothesis under test: subagent hook output is NOT visible to the
parent. The method below tries to falsify that, with a control run that confirms
the harness surfaces both channels at all.

CC version: 2.1.261 (`claude --version`).

## Method

All work happened under `$TMPDIR/probe-subagent-hook/` (two throwaway git repos,
`probe/` and `control/`), never inside the gitlore working tree. Nothing in
`/Users/david/code/gitlore` was modified except this file.

### Hook script (`/tmp/claude-1000/probe-subagent-hook/hook.sh`)

Takes a log-file path as `$1`, appends its full stdin to that log (so hook
firing and `agent_id` are independently checkable), then emits on stdout with
`exit 0`:

```json
{"systemMessage":"PROBE-SYSMSG-a1b2c3","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"PROBE-ADDCTX-d4e5f6"}}
```

### Wiring

Each scratch repo has its own `.claude/settings.json` wiring `PostToolUse`
(matcher `Edit|Write`) and `PostToolBatch` to the same script, pointed at a
per-repo log file. Each repo is a fresh `git init` with one committed `dummy.md`
containing `hello world`.

### Control run (validity check — no subagent)

```
cd /tmp/claude-1000/probe-subagent-hook/control && \
claude -p "Use the Edit tool to append the line 'edited by main agent' to \
dummy.md. Then reply with exactly the word done." \
  --setting-sources project --permission-mode acceptEdits \
  --output-format stream-json --verbose \
  > stdout.jsonl 2> stderr.log
```

The main agent edits the file itself; no Task/Agent tool call. Session id
`79b41555-1f48-4f79-864f-824686942510`.

### Probe run (the file edit happens only inside a subagent)

```
cd /tmp/claude-1000/probe-subagent-hook/probe && \
claude -p "You must not edit any file yourself. Instead, use the Task tool \
to spawn exactly one subagent (general-purpose type) whose sole job is to \
use the Edit tool to append the line 'edited by subagent' to dummy.md. Wait \
for the subagent to finish, then reply with exactly the word done." \
  --setting-sources project --permission-mode acceptEdits \
  --output-format stream-json --verbose \
  > stdout.jsonl 2> stderr.log
```

Session id `d8a72d35-a49f-4ec6-a5cf-2c4b1ba6601a`, subagent
`agent_id=aa739ebc544370f7a`, `agent_type=general-purpose`. The subagent's own
transcript is
`~/.claude/projects/-tmp-claude-1000-probe-subagent-hook-probe/d8a72d35-a49f-4ec6-a5cf-2c4b1ba6601a/subagents/agent-aa739ebc544370f7a.jsonl`.

Both `dummy.md` files show exactly the expected single edit (`hello world` /
`edited by main agent` resp. `edited by subagent`), confirming each run did
exactly one Edit and no other file touch.

### What was checked, for each run

- Did the hook fire, and (probe run only) does its logged stdin carry
  `agent_id`?
- Do the sentinels appear in the run's own transcript JSONL, and — for the probe
  run specifically — do they appear in the **subagent's** JSONL
  (`subagents/agent-<id>.jsonl`) as native `attachment` records of type
  `hook_system_message` / `hook_additional_context` / `hook_success`?
- Do the sentinels appear anywhere in the **parent** transcript JSONL (the file
  at `hook_event`'s own `transcript_path`, which for the probe run's hook
  invocations points at the parent per
  [[hook-input-schema]]/[[jsonl-sidechain-segregation]])?
- Do the sentinels appear in the `claude -p` stdout stream (the parent's
  user-visible/programmatic channel)?
- Did the parent's final assistant text (`result` field) show awareness of
  either sentinel?

## Results

| Channel checked | Control (no subagent) | Probe (subagent edits) |
|---|---|---|
| Hook fired at all (log has an entry) | yes | yes |
| Hook stdin carries `agent_id` | n/a (no subagent) | **yes** — `agent_id":"aa739ebc544370f7a"` |
| `PROBE-SYSMSG` in the run's own/parent transcript JSONL | yes (3 occurrences, incl. `hook_success` attachment) | **no** (0 occurrences anywhere in parent transcript) |
| `PROBE-ADDCTX` in the run's own/parent transcript JSONL as a native `hook_additional_context` attachment | yes (1 occurrence) | **no** (0 `hook_*` attachment types of any kind in parent transcript) |
| `PROBE-SYSMSG` in subagent's own JSONL (`subagents/agent-*.jsonl`) | n/a | **yes** — `hook_system_message` attachment |
| `PROBE-ADDCTX` in subagent's own JSONL | n/a | **yes** — `hook_additional_context` attachment |
| `PROBE-SYSMSG` in parent's `claude -p` stdout stream | yes (1 occurrence) | **no** (0 occurrences) |
| `PROBE-ADDCTX` in parent's `claude -p` stdout stream | not directly checked (systemMessage was the stdout-visible one; see below) | **yes, but only inside the subagent's own final report text**, relayed as ordinary `Agent`/Task tool output — not as a hook side-channel |
| Parent's final assistant text (`result`) mentions either sentinel | n/a (task was "reply done"; not asked to relay) | no — final reply is literally `done` |

Parent transcript's only `attachment` entries in the probe run (6 total):
`agent_listing_delta`, `deferred_tools_delta`, `mcp_instructions_delta`,
`skill_listing`, `total_tokens_reminder` ×2 — none of type `hook_*`. The
subagent's own transcript, by contrast, carries all four: `hook_system_message`,
`hook_additional_context`, `hook_success`, `hook_non_blocking_error`.

Decisive raw evidence:

Hook log line from the probe run's `PostToolUse:Edit` firing, showing `agent_id`
present (proves the hook ran *inside* the subagent):

```
{"session_id":"d8a72d35-...","agent_id":"aa739ebc544370f7a","agent_type":"general-purpose",...,"hook_event_name":"PostToolUse","tool_name":"Edit",...}
```

Subagent's own transcript line carrying the native `systemMessage` record (this
attachment type and content exist ONLY here, never in the parent transcript):

```
{"parentUuid":"236bf22b-...","isSidechain":true,"agentId":"aa739ebc544370f7a",
 "attachment":{"type":"hook_system_message","content":"PROBE-SYSMSG-a1b2c3",
 "hookName":"PostToolUse:Edit",...},"type":"attachment",...}
```

Parent transcript's only mention of either sentinel — inside the ordinary
`tool_result` for the `Agent` tool call, i.e. the subagent's own generated
prose, not a hook attachment:

```
{"parentUuid":"42e71dea-...","type":"user","message":{"role":"user","content":
 [{"tool_use_id":"toolu_01UFFcx7B2dSBMbP4gaoQ65U","type":"tool_result",
 "content":[{"type":"text","text":"Done. ... One incidental observation: a
 PostToolUse:Edit hook fired and injected additional context with the token
 `PROBE-ADDCTX-d4e5f6`."}, ...]}]}, "toolUseResult":{"status":"completed",
 "agentId":"aa739ebc544370f7a","agentType":"general-purpose", ...}}
```

`grep -c '"type":"hook_'` over the parent transcript for the probe run: `0`.
Same grep over the subagent's own JSONL: `4` (one of each hook attachment type).
`PROBE-SYSMSG` count over the parent transcript: `0`. Over the parent's
`stdout.jsonl`: `0`.

Control run confirms the harness surfaces both channels when there is no
subagent involved: `PROBE-SYSMSG` appears once in `stdout.jsonl` (the
user-visible channel working as expected) and both sentinels appear as native
`hook_success`/`hook_additional_context` attachments in that run's own (and
only) transcript.

## Verdict: CONFINED

Subagent hook output — both `systemMessage` and
`hookSpecificOutput.additionalContext` — is confined to the subagent. It never
appears as a native hook-channel artifact anywhere in the parent's transcript or
in the parent's `claude -p` stdout stream. `systemMessage` never reached the
parent at all, by any path, in this run.

`additionalContext` did end up quoted in the parent's stdout stream in the probe
run, but only because the subagent model itself chose to mention the sentinel
token in its own final report text — that text is the normal return value of the
`Agent`/Task tool call, the same channel through which a subagent reports any
other fact it noticed. Nothing about the hook's output channel special-cases the
parent; the parent sees exactly what the subagent chose to say, subject to the
subagent noticing and narrating it. Deleting that one sentence from the
subagent's prompt/behavior would remove the only path by which `PROBE-ADDCTX`
reached the parent — confirmed by the fact that `PROBE-SYSMSG`, `systemMessage`,
never got relayed at all (nothing in the subagent's instructions asked it to
mention that field, and apparently nothing made it notice/quote it), while
`additionalContext` (delivered to the subagent as a `<system-reminder>` per
[[hook-output-channels]]) was visible enough in the subagent's own context for
the model to comment on it unprompted.

## What this does not establish

- Whether a *differently-worded* subagent prompt, or a different subagent type,
  would ever mention or omit the sentinel — the relay is mediated by model
  behavior, not a deterministic channel, so this single run's "the subagent
  happened to narrate it" is not proof that a subagent always (or never) will.
  It only proves the parent has no *direct* view of the channel — whatever
  reaches the parent must first pass through the subagent's own generated text.
- Whether other events (`PreToolUse`, `Stop`, `SubagentStop`) behave the same
  way — only `PostToolUse`/`PostToolBatch` were probed, matching what gitlore's
  own hooks use.
- Whether `--output-format stream-json` under `-p` differs from the interactive
  TUI in how it would render subagent hook attachments to a human — the check
  here was the transcript JSONL and the programmatic stdout stream, not visual
  TUI rendering.
- Whether the harness ever copies a `hook_*` attachment record itself (as
  opposed to model-generated text) from a subagent transcript into the parent
  transcript under some other condition not exercised here (e.g. a
  `decision:"block"` on `PostToolBatch`, or a `SubagentStop` hook). This probe
  only exercised the non-blocking `additionalContext`/`systemMessage`
  combination.
