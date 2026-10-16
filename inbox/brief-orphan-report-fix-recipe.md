## Brief: make the index-drift fix discoverable at the symptom

2026-10-13

### Goal

When `gitlore_compose` reports an orphan or dangling pointer, the report names which of three fixes applies and the exact command, so an agent cleaning index drift does not have to derive the rule from `docs/references/index-composition.md` (D31, D36).

### Why it matters

A session cleaning ~80 stale duplicate pointers out of the root and ddaanet tier indexes concluded that "editing only one side gets silently refilled from the other, so edit both". A read-only check of the current source (scripts/lib/index-compose.sh `gitlore_compose`, verified 2026-10-13) shows that is wrong in general. Composition projects root DOWN into the tier; nothing is adopted UP in-session. What the session hit were the exceptions, and they are indistinguishable from the normal case without a `git show HEAD:memory/MEMORY.md` lookup the agent had no prompt to run.

### The three branches (verify against the source before encoding)

1. The path is in root at `HEAD`: delete the line from root only. The next compose drops the tier copy, because the code reads it as "root deleted it".
2. The path is not in root at `HEAD` (arrived from an uncommitted take, or added and deleted within one uncommitted window): the tier copy stays and is reported as an orphan. Delete it from the tier index directly.
3. The deletion would leave root with no line at all for that tier: compose adopts the whole tier index back into root and every line returns. Deactivate the tier instead.

Also true: a tier-index-only deletion (root still has the line) is restored from root, but only at the next trigger, since a tier-index edit does not trigger composition by itself. A dangling pointer (file gone) is reported, never auto-pruned; deleting it from root is a normal one-edit fix.

### Proposed change, for you to design

- The orphan report carries the branch and the fix. Detecting the branch is deterministic (`HEAD` lookup, per-tier line count), so it belongs in the harness, not in an agent's recall.
- D31/D36 gain the three-branch recipe as an operational note.
- No memory fact is written for this on the consuming side: the mechanism is already documented here, and a recipe at the symptom beats one an agent must recall.
