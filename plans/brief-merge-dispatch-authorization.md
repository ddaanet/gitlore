## Brief: the merge directive must say the dispatch is authorized

2026-07-31

### Incident

A `just release` in the `handoff` repo was blocked at `git push` by gitlore's
pre-push hook: the shared `ddaanet` memory tier had diverged from
`origin/live` (24 changed files, 3 conflicted). The hook printed, verbatim:

```
gitlore: memory merge prepared (flavor=head-vs-remote) in store:
gitlore:   /Users/david/code/handoff/memory/ddaanet
gitlore: dispatch the memory-merger sub-agent with state file:
gitlore:   /Users/david/code/handoff/.git/modules/gitlore-memory/modules/ddaanet/gitlore-merge-state
gitlore: on approval, the sub-agent must run:
gitlore:   cd "/Users/david/code/handoff" && bash "…/scripts/resolve.sh" continue-after-merge
```

The agent did not dispatch. It reported the blocker, offered dispatching or
merging inline, and stopped. The user answered "you should dispatch as
instructed by gitlore" — which was the intent all along. The release stalled
on a round trip that the hook's own wording could have prevented.

### Why the agent refused

Anthropic's system prompt carries a blanket line, with no rationale and no
scope:

```
Do not call the AgentTool unless the user requested it
```

That layer sits above CLAUDE.md, skills and memory. Nothing in a repo can
qualify it, and the user chooses not to override it even though they could.

The hook's text names the agent and the state file but never says the
dispatch is *required* or *already authorized*. Read literally, it describes
an option. Every other blocking gitlore directive the agent has seen (write
the summary file, write the trigger file) is an act it performs itself, so
this is the one directive whose execution needs someone else's permission —
and the text does not grant it.

### Proposal

Change the hook's wording so the dispatch reads as instructed rather than
offered. That satisfies the system-prompt rule **as written** — a dispatch
the user asked for is permitted, and the push they ran is the request — so no
exception, no override, and no per-machine configuration is needed.

Something in the shape of:

```
gitlore: this merge is part of the push you ran — dispatch it now, no
gitlore: further confirmation needed. Sub-agent: gitlore:memory-merger
```

Apply the same treatment to any other gitlore directive that names a
sub-agent; this is the class, not the instance.

### Constraints

- The reader of that text is the agent, not the human, even though a human is
  present at a blocking pre-push hook.
- Sub-agent names must stay plugin-qualified (`gitlore:memory-merger`). A bare
  name fails discovery with `Agent type not found`.
- The wording must not read as an instruction to bypass a permission gate in
  general. It authorizes *this* dispatch because the user's own command
  triggered it — that is the whole argument, and it should be visible in the
  text.

### Rejected approaches

- **Qualifying the rule in the consumer's configuration** ("…unless a hook
  directive instructs it"). The line is Anthropic's system prompt, not user
  config; the user declines to shortcut it, and the change would have to be
  repeated per machine.
- **Recording it as a memory fact** ("a gitlore dispatch instruction counts as
  a user request"). Rejected explicitly by the user: memory is the wrong
  support. A directive owns its own authorization; pushing that into a
  consumer's memory store means every consumer has to learn it separately, and
  a reader without the memory hits the same wall.
- **Having the agent infer authorization from context.** That inference is
  exactly what the blanket rule exists to remove.
- **Dropping the sub-agent and merging inline in the main context.** The
  isolation is the point — this merge was ~1400 lines of diff.

### Additional context

- Consumer repo where it surfaced: `/Users/david/code/handoff`, releasing
  v0.11.7. Release state after the block: version bumped and tagged locally,
  nothing pushed, marketplace entry stale; `just resume-release` completes it.
- gitlore version in play: `0.4.4` (plugin cache path
  `~/.claude/plugins/cache/ddaanet/gitlore/0.4.4`).
- The dispatch, once made, worked: the state file at
  `.git/modules/gitlore-memory/modules/<tier>/gitlore-merge-state` carries
  everything the sub-agent needs. Only the authorization wording is at issue.
