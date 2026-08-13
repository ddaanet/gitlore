## Current task

Applying the briefs listed in the todo file, in the order given — increasing
risk and size. Nothing is part-done; item 1 is next.

## Open decisions

- Todo item 4's request 4: a self-retiring `PreToolUse` marker keyed on the
  risky `Edit` argument shape. It introduces a new hook, so it is separable
  from the glued-bullet rule and was left undecided.
- Todo item 6: which of the three fixes the orphaned-`MERGE_HEAD` brief offers
  — read `pending` from `live`, make the stale-merge guard `MERGE_HEAD`-aware,
  or write the state file before the risky work. The brief recommends none
  decisively.
- Whether to delete two brief files whose work has already landed:
  `brief-stale-plugin-root-detector-confirmed.md` (in `c016a67`) and
  `plans/brief-push-misreads-behind-as-diverged.md` (in `afb02b9`).