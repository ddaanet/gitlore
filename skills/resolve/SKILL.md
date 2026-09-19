---
name: resolve
description: Resolve or repair a diverged gitlore memory store or tier. Use when a git commit or push fails with output containing "gitlore: memory merge prepared" — invoke it without waiting to be asked. Also use when the user runs /gitlore:resolve, reports that memory has stopped publishing, or hands back a divergence message from a push they ran in their own terminal.
allowed-tools: ["Bash", "Task", "SendMessage"]
---

# gitlore:resolve

You are resolving a gitlore memory submodule from divergence.

## Entry mode

**Commit-triggered**: The pre-commit hook already emitted a merge directive — it is visible in the output that caused you to invoke this skill. Proceed directly to **Parse directive**.

**Standalone** (user ran `/gitlore:resolve` or state is unclear): Run the resolver:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"
```

Exit codes:
- `0` — healthy or simple repair complete. Summarize and stop.
- Non-zero + "memory merge prepared" on stderr → proceed to **Parse directive**.
- Non-zero without that → surface stderr verbatim and stop.

## Parse directive

The directive looks like:

```
gitlore: memory merge prepared (flavor=<X>) in store:
gitlore:   <abs-path-to-store>
gitlore: dispatch sub-agent gitlore:memory-merger with state file:
gitlore:   <abs-path-to-state-file>
gitlore: that dispatch is a required step of the git operation that triggered
gitlore: this merge, not an option: the request for that operation is the
gitlore: request for this dispatch, so make it now without asking first. Review
gitlore: the synthesis it returns yourself — both sides of this merge already
gitlore: passed an approval gate, so do not prompt the user (D49).
gitlore: on approval of its synthesis, the sub-agent must run:
gitlore:   cd "<parent-repo>" && bash "<abs-path-to-resolve.sh>" <continuation-subcommand>
```

Extract the state-file path and the full continuation command (the entire `cd ... && bash ... <subcommand>` line, absolute paths intact — the sub-agent runs it verbatim).

A merge whose last synthesis failed the merged-index check carries its problem lines too, between the state-file path and the dispatch paragraph:

```
gitlore: the synthesis this merge holds fails the merged-index check. Brief the
gitlore: sub-agent to clear these lines, each in the file it names:
gitlore:   <problem line>
```

Extract them verbatim and pass them in the dispatch prompt. They are the objection a previous synthesis drew, against a merge this session may never have seen, and clearing them is what lets the continuation land it.

The directive authorizes its own dispatch: the git operation that triggered the merge is the request for it. Dispatch without a confirming round trip. Your own review still governs the merge the sub-agent proposes, below — but not the user's: both sides of the merge already passed an approval gate, so the whole resolution runs without prompting them (D49).

The store line names which repository diverged: the project memory store, or a tier mounted inside it. One merge policy covers every level, so the flow below is identical either way — but say which store you merged when you summarize, because a tier is shared with other repositories and the project store is not.

## Dispatch memory-merger sub-agent (turn 1 — synthesis)

Use the `Task` tool with `subagent_type: "gitlore:memory-merger"`. Pass the state-file path, the continuation command, and any problem lines the directive carried. The sub-agent synthesizes, stages the paths it merged in the store, and returns a prose summary. Capture the `agentId`.

## Approve or reject (turn 2 — resume)

Read the sub-agent's summary. Compare against session context: does the synthesis match what we'd expect from the changes seen this session?

`No conflict.` is one of its valid answers — the prepared merge was already right and it changed nothing. Judge it as you would any other summary, against what the two sides actually did; it is a finding to check, not an admission that the sub-agent skipped the work.

Resume via `SendMessage` to the `agentId`:
- If correct: `"approved"`.
- If anything is off: `"rejected: <specific reason>"` — the sub-agent re-synthesizes and returns a new summary; loop back to evaluating it.

Do not escalate to the user: a merge is automated from their perspective, because both of its sides already passed an approval gate — the local one at its own commit, the upstream one in the repo that published it (D49). Approve unless you can name a concrete defect; judge against the two side diffs, not against a hunch.

On approval, the sub-agent runs the continuation command. The merge commit's message is canned — the continuation writes it; the summary is for your review and your report to the user, not for the commit.

If the sub-agent reports that the continuation exited 1 with `gitlore: the merged index fails the check, so the merge was not committed`, the merge did not land and stays prepared. Resume the sub-agent with `rejected:` followed by the problem lines it quoted, and evaluate the new synthesis as before. If a re-synthesis draws the same problem line again, stop and relay the lines to the user verbatim — a failure report, not an approval request.

The sub-agent reports the continuation's exit status, and only an exit 0 is a landed merge. Route its other reports by the line it quotes:
- `gitlore: the merge message file could not be created`, `gitlore: the merge message could not be built` or `gitlore: the merge commit was refused` — the merge stays prepared for a reason outside the merged files. Send no `rejected:` and do not go to **Loop**: a rerun re-emits the same directive and meets the same refusal. Go to **Summarize**, skipping **Resume commit**: memory is not resolved.
- `gitlore: memory merge prepared` — the merge landed and the local `live` advance after it, or the push of `live` to `origin`, prepared a fresh one. Go to **Loop**, which picks the new merge up; stopping here would strand the merge the triggering git operation needs.
- `gitlore: pushing '` … `failed, and not because of divergence` — the merge landed, but `live` was not advanced or not published. Send no `rejected:` and do not go to **Loop**: a rerun meets the same refusal, which no merge fixes. Go to **Summarize**, skipping **Resume commit**.
- The continuation call was denied before it ran — no exit status, no `gitlore:` output. Nothing moved and the merge stays prepared with its synthesis staged. Do not run the continuation yourself and do not re-dispatch: a refusal is the user's to lift. Go to **Summarize**, skipping **Resume commit**.
- Anything else with a non-zero status — the outcome is unrecognised. Go to **Summarize**, skipping **Resume commit**.

## Loop

After the sub-agent exits, run `${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh` again to check for a second flavor. Repeat from **Parse directive** until the script exits 0.

## Resume commit

If this skill was triggered by a commit failure, retry the original git commit now that memory is resolved.

## Summarize

Tell the user what was merged and what state the repo is in now.

Only a continuation that exited 0 is summarized as a landed merge. The other outcomes:
- A message-file, message-build or refused-commit line: relay it with whatever the
  failing command printed above it. The merge stays prepared; the remedy is to fix
  that cause and run `/gitlore:resolve` again.
- A `pushing '…' failed, and not because of divergence` line: report the merge as
  landed and the push as failed, with git's reason under it. Any remedy printed
  below it is still to run.
- A denied continuation: say the synthesis is approved and staged and the merge is
  unlanded, and hand over the continuation command verbatim. The user lands it
  either by running it with a `!` prefix or by asking for it by name, after which
  this session runs it; continue from its output as from the sub-agent's report
  — **Loop**, then **Resume commit**.
- An unrecognised non-zero outcome: relay the output verbatim with its exit status,
  as a state to inspect, not a landing to report.

The continuation checks and composes the memory indexes before it commits, so its
output may carry index problems. Keep the two kinds apart. Problems in the merged
index blocked the landing until a new synthesis cleared them; say which they were.
On a landed merge, any other `gitlore:` line — a composition refusal naming another
index, index pointers naming files that are not there, a refused push with its
remedy — came after the merge commit landed; relay it, because it is a problem only
you can fix.
A printed remedy (`gitlore: tier '<t>' stays on the merge commit … Run:` and the
command lines under it) is outstanding whenever it was printed — on an outcome
that never reaches **Loop** as much as on one where the **Loop**'s `resolve.sh`
then reports the state healthy. Run those lines, or relay them as not yet run.
