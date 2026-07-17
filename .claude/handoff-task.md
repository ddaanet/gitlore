## Current task

D17 slice-2 memory reconcile shipped; two follow-ups are parked awaiting a decision.

## Open decisions

- unsandbox-git-status plugin (separate repo, `~/.claude/plugins/cache/ddaanet/unsandbox-git-status`): adopt the drafted generic `additionalContext` wording AND move the auto-unsandbox notice from `systemMessage` (user-only channel — why agents miss it and wrongly infer the sandbox is clean) to `additionalContext` (model channel). Pending a check that a PreToolUse hook honours `additionalContext`; if it doesn't, fold the notice into the command's own output.
- Eval harness: whether to switch `tests/evals/` from the Agent SDK to `claude --print --resume`. The false "SDK because --print suppresses hooks" rationale is already corrected; the SDK is kept only for efficiency (~40k-token context repriming + ~10s startup per `--print` spawn). Decision: does that efficiency edge justify keeping the SDK dependency, or is `--print --resume` the simpler harness?
