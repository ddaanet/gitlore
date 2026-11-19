---
name: resolve
description: 'Resolve or repair a diverged gitlore memory store or tier. Use when a memory merge or push fails with output containing "gitlore: memory merge prepared" — invoke it without waiting to be asked. Also use when the user runs /gitlore:resolve, reports that memory has stopped publishing, or hands back a divergence message from a push they ran in their own terminal.'
allowed-tools: ["Bash", "Task", "SendMessage"]
---

# gitlore:resolve

You are resolving a gitlore memory submodule from divergence.

## Entry mode

**Commit-triggered**: A merge path already emitted a merge directive — `gitlore-merge` or `gitlore-push`, whose reconcile prepares the merge, the `pre-push` hook on a store diverged from its remote, or `gitlore-commit` meeting a merge already prepared — and it is visible in the output that caused you to invoke this skill. Proceed directly to **Parse directive**.

**Standalone** (user ran `/gitlore:resolve` or state is unclear): Run the resolver:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"
```

Exit codes:
- `0` — healthy, or a report with nothing to do here (a store ahead, behind or staying local). Summarize, relaying every `gitlore:` line the script printed, and stop.
- Non-zero + "memory merge prepared" on stderr → proceed to **Parse directive**.
- Non-zero with a line starting `gitlore: memory records` or `gitlore: this repository records memory at` → a recorded commit its repository lacks, or one a failed fetch left unconfirmed. Relay it, never call the state healthy, and follow [pin-and-abort.md](references/pin-and-abort.md); it also covers `abort-merge`, which abandons a prepared merge.
- Non-zero without any of those → surface stderr verbatim and stop.

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

The directive authorizes its own dispatch: the git operation that triggered the merge is the request for it. Dispatch without a confirming round trip.

The store line names which repository diverged: the project memory store, or a tier mounted inside it. One merge policy covers every level, so the flow below is identical either way — but say which store you merged when you summarize, because a tier is shared with other repositories and the project store is not.

## Dispatch memory-merger sub-agent (turn 1 — synthesis)

Use the `Task` tool with `subagent_type: "gitlore:memory-merger"`. Pass the state-file path, the continuation command, and any problem lines the directive carried. The sub-agent synthesizes, stages the paths it merged in the store, and returns a prose summary. Leave the dispatch's `name` unset: an unnamed sub-agent returns once, as the tool result, while a named one becomes a teammate whose report and idle notices each arrive as a separate message. Capture the `agentId`.

## Approve or reject (turn 2 — resume)

Read the sub-agent's summary. Compare against session context: does the synthesis match what we'd expect from the changes seen this session?

`No conflict.` is one of its valid answers — the prepared merge was already right and it changed nothing. Judge it as you would any other summary, against what the two sides actually did; it is a finding to check, not an admission that the sub-agent skipped the work.

Resume via `SendMessage` to the `agentId`:
- If correct: `"approved"`.
- If anything is off: `"rejected: <specific reason>"` — the sub-agent re-synthesizes and returns a new summary; loop back to evaluating it.

Do not escalate to the user: a merge is automated from their perspective, because both of its sides already passed an approval gate — the local one at its own commit, the upstream one in the repo that published it (D49). Approve unless you can name a concrete defect; judge against the two side diffs, not against a hunch.

On approval, the sub-agent runs the continuation command. The merge commit's message is canned — the continuation writes it; the summary is for your review and your report to the user, not for the commit.

If the sub-agent reports that the continuation exited 1 with `gitlore: the merged index fails the check, so the merge was not committed` or `gitlore: these files still hold conflict markers, so the merge was not committed`, the merge did not land and stays prepared. Resume the sub-agent with `rejected:` followed by the problem lines or file names it quoted, and evaluate the new synthesis as before. If a re-synthesis draws the same line again, relay the lines to the user verbatim in **Summarize**, skipping **Resume commit** — a failure report, not an approval request.

The sub-agent reports the continuation's exit status. The merge landed once its commit did, so a non-zero status can follow a landed merge: the local advance of `live` that comes after the commit was refused. Route the report by the line it quotes; each route is in [turn-2-routes.md](references/turn-2-routes.md), which you read before routing it.

## Loop

After the sub-agent exits, run `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve.sh"` again to check for a second flavor. Its outcomes:
- A directive: go to **Parse directive**.
- Exit 0: the merge is resolved; go on to **Resume commit**.
- A non-zero exit whose output holds a pin line: handle it as [pin-and-abort.md](references/pin-and-abort.md) says, then go to **Summarize**, skipping **Resume commit**.
- Any other non-zero exit: relay the output verbatim, then go on to **Resume commit**; `gitlore-commit` refuses on its own while a merge is still prepared.

## Resume commit

If this skill was triggered by a commit failure, pass the summary again to `gitlore-commit` now that memory is resolved, through the `gitlore:commit` skill. Re-approve it first if the merge brought content the summary did not cover: present it again, amended for what the merge brought, and commit once the user approves it. `gitlore-commit` on a store with no changes exits 0 whatever the summary says, so a commit that had landed before the merge needs no retry. Publishing is `/gitlore:push`, which this skill does not run. An empty summary on stdin is refused (exit 2), so a retry always carries an approved summary.

## Summarize

Tell the user what was merged and what state the repo is in now.

The merge landed when the continuation's commit did, and exit 0 says `live` advanced locally too. Nothing was published. Relay every `gitlore:` report line the script printed, verbatim and ending with the last of them, so the user sees each command it names; for example `gitlore: merged without publishing. Run /gitlore:push to publish.` after a landing. For a non-zero outcome read [unlanded-outcomes.md](references/unlanded-outcomes.md) first: it separates the merges that did not land from the landed one whose advance of `live` failed.

The continuation checks and composes the memory indexes before it commits, so its
output may carry index problems. Keep the two kinds apart. Problems in the merged
index blocked the landing until a new synthesis cleared them, or left it unlanded; say which they were.
On a landed merge, any other `gitlore:` line — a composition refusal naming another
index, index pointers naming files that are not there, a refused advance of `live`
with git's text — came after the merge commit landed; relay it; only you can fix it.
