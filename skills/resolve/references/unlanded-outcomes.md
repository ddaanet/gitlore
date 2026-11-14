# Summarizing a merge that did not land

The outcomes of `/gitlore:resolve` other than a landed merge. Read this when the
continuation did not exit 0, or was denied.

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
