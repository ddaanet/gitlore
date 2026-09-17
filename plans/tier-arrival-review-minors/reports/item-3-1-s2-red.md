# Item 3.1 / Slice 2 — RED (guard)

**Test added:** `tests/index_compose.bats`, "a moved stray at the end keeps the
newline the last bullet had", placed directly after slice 1's "a duplicate
dropped from the end terminates the new last line" test.

Fixture: `- [A](a.md) — hook\nStray line\n- [B](b.md) — hook\n` unterminated via
`unterminate_index`. Preconditions asserted before the repair: unterminated
(`tail -c 1 | wc -l` = 0), line 1 and line 3 are the two bullets, line 2 is the
stray between them, line 3 (the last line) is a bullet.

## Guard run

```
$ shellcheck tests/index_compose.bats
(clean, no output)
$ scripts/run-bats.sh tests/index_compose.bats --filter "a moved stray at the end keeps the newline the last bullet had"
bats: 1 passed, 0 failed
```

Passes against the current tree, as expected for a guard slice (slice 1's GREEN
already implemented the whole termination rule).

## Mutation (teeth check)

Backed up `scripts/lib/index-compose.sh`, then changed the stray splice's tag
from the real per-element tag to a literal `1`:

```
-      p2last+=("${straylast[@]}")
+      p2last+=(1)
```

This makes the moved stray inherit "last line was terminated" instead of its own
(untagged) status, so the repair leaves the output unterminated.

```
$ scripts/run-bats.sh tests/index_compose.bats --filter "a moved stray at the end keeps the newline the last bullet had"
not ok 1 a moved stray at the end keeps the newline the last bullet had
# (in test file tests/index_compose.bats, line 1378)
#   `cmp -s file.md expected.md' failed
bats: 0 passed, 1 failed
```

Reds on the `cmp -s` assertion, as expected.

## Restoration

Restored `scripts/lib/index-compose.sh` from the backup.
`git diff --stat -- scripts` and `git status --porcelain -- scripts` are both
empty — no production change left behind.

## Full-file run

```
$ scripts/run-bats.sh tests/index_compose.bats
bats: 83 passed, 0 failed
```
