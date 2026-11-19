# Routing the sub-agent's report after the continuation

The route for each line the sub-agent quotes when the continuation did not exit
0, or exited 0 and printed one of these. Read this when its report quotes a
`gitlore:` line or the continuation call was denied.

- `gitlore: the merged index fails the check, so the merge was not committed` or `gitlore: these files still hold conflict markers, so the merge was not committed` — **Approve or reject** in the skill handles these two lines; no route below applies to them.
- `gitlore: the merge message file could not be created`, `gitlore: the merge message could not be built` or `gitlore: the merge commit was refused` — the merge stays prepared for a reason outside the merged files. Send no `rejected:` and do not go to **Loop**: a rerun re-emits the same directive and meets the same refusal. Go to **Summarize**, skipping **Resume commit**: memory is not resolved.
- `gitlore: memory merge prepared` — the merge landed and the local `live` advance after it prepared a fresh one. Go to **Loop**, which picks the new merge up; stopping here would strand the merge the triggering git operation needs.
- `holds a merge state file but no MERGE_HEAD` — the prepared merge lost its `MERGE_HEAD`, and nothing was committed. The line names `/gitlore:resolve`, which repairs the state: go to **Loop**. The repair prints a directive for the merge it still needs when one remains.
- `gitlore: pushing '` … `failed, and not because of divergence` — the merge landed, but local `live` was not advanced. Send no `rejected:` and do not go to **Loop**: a rerun meets the same refusal, which no merge fixes. Go to **Summarize**, skipping **Resume commit**.
- The continuation call was denied before it ran — no exit status, no `gitlore:` output. Nothing moved and the merge stays prepared with its synthesis staged. Do not run the continuation yourself and do not re-dispatch: a refusal is the user's to lift. Go to **Summarize**, skipping **Resume commit**.
- Anything else with a non-zero status — the outcome is unrecognised. Go to **Summarize**, skipping **Resume commit**.
