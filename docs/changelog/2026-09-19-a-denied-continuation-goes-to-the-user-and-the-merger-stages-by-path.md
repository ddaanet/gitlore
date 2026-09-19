# 2026-09-19 — A denied continuation goes to the user, and the merger stages by path (D49, D50)

A `/gitlore:push` met a diverged `ddaanet` tier, the `memory-merger` sub-agent
reported `No conflict.`, and on approval its continuation call was refused by
the auto-mode classifier before the script started. Neither the agent nor
`/gitlore:resolve` had a route for that outcome: there is no exit status to
branch on, so the merge sat prepared and staged with nobody assigned to land it.
The agent now reports the refusal with its stated reason and the continuation
command verbatim, and does not retry, reword or reach the script another way.
The skill sends that report to the user rather than running the command itself.
Escalating is the point, not a fallback: the user lands the merge with a `!`
command, or names the command in a prompt, after which the main session runs it
and the skill continues from its output as from the sub-agent's report.

The same run had the sub-agent's `git add -A` refused by a session hook that
blocks sweeping adds. It fell back to `git add -u`, which staged the right tree
only because the synthesis created no file. The agent now stages by explicit
path — every path in `changed_files` plus any file it wrote — and never `-A`,
`-u` or `.`.

The pin guard's skipped-take residual is accepted and recorded under D50 in
`references/git-hooks.md`: a retry that does not run `/gitlore:merge` commits
normally, and the next commit to that tier meets a non-fast-forward `HEAD:live`
push that classifies as divergence and prepares a `head-vs-live` merge. It costs
one later merge and no fact. Refusing the commit while a tier's local `live` is
ahead of its pin is recorded as rejected.

`scripts/mutate-and-run.sh`'s header states that its EXIT trap and post-restore
verification are pinned by no test, and why that is accepted.
