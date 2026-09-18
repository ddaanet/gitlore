# Item 4.1, slice 3 — GREEN

## Diff, `scripts/resolve.sh`

```diff
@@ -306,12 +306,18 @@ if [ $# -ge 1 ]; then
       # Via a file, not a pipe: the sentinel has to be in the environment of
       # `git commit` itself, and `VAR=1 printf … | git commit` exports it to
       # the wrong end of the pipeline.
-      merge_msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-merge-msg.XXXXXX")
-      # A refused commit or a failed message build keeps MERGE_HEAD and the
-      # merge state, so a rerun lands it; only the message file is this run's
-      # to remove. Removal comes first in each `||` group below: errexit stays
-      # armed on its right-hand side, so a failing write to stderr there would
-      # skip whatever follows it and leave the scratch file behind.
+      merge_msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-merge-msg.XXXXXX") \
+        || {
+          echo "gitlore: the merge message file could not be created, so the merge was not committed; the merge stays prepared." >&2
+          exit 1
+        }
+      # A refused commit, a failed message build, or the failed mktemp above
+      # keeps MERGE_HEAD and the merge state, so a rerun lands it; only the
+      # message file is this run's to remove, and mktemp's own failure leaves
+      # none to remove. Removal comes first in each `||` group below that has a
+      # file: errexit stays armed on its right-hand side, so a failing write to
+      # stderr there would skip whatever follows it and leave the scratch file
+      # behind.
       gitlore_merge_commit_message "$memroot" "$mempath" > "$merge_msgfile" \
         || {
             rm -f "$merge_msgfile"
```

The `mktemp` assignment gains its own `|| { … ; exit 1; }`, matching the shape
of its two siblings (message build, commit). No `rm` in this arm's brace group:
`mktemp` failed, so there is no scratch file to remove. The comment immediately
below is extended to cover all three arms and to state that this one alone has
nothing to remove.

The comment at `scripts/resolve.sh:105-109` (the `compose_merged_indexes`
docstring covering the staging-failure residual) already states the bound —
landed in an earlier slice — so no change was needed there.

## Tests

Targeted run:

```
$ GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats \
    --filter "a failed mktemp for the merge message file leaves the merge prepared"
bats: 1 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.J8eIab
```

Full file:

```
$ GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats
bats: 25 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.v3gpqa
```

BSD-portability suite (touched a shell script):

```
$ GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/bsd_portability.bats
bats: 3 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.SpJNxA
```

`shellcheck -x scripts/resolve.sh tests/resolve_compose.bats`: clean, no output.

## Test text change

None — the slice-3 test landed as reviewed in
`plans/tier-arrival-review-minors/reports/item-4-1-s3-test-review.md`, with no
further edits needed against the fix above.

## Commit

Staged `scripts/resolve.sh` and `tests/resolve_compose.bats` only; every other
working-tree change (inbox/, plans/brief-*, the s3 red/test-review reports) left
untouched.

Subject:
`fix: Item 4.1/3 — a failed message file mktemp says the merge stays prepared`
(the gitmoji hook prefixed it 🐛 on commit)

Hash: `1e9a6e1`

`git status --porcelain=v1` after the commit shows no tracked change left in
`scripts/resolve.sh` or `tests/resolve_compose.bats`; the same untracked paths
from before the dispatch remain untracked.
