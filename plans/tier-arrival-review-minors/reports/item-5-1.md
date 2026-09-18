# Item 5.1 report

## Diff

```diff
diff --git a/tests/index_compose.bats b/tests/index_compose.bats
index 7bdc53c..905bf8b 100644
--- a/tests/index_compose.bats
+++ b/tests/index_compose.bats
@@ -1111,6 +1111,7 @@ b" ]
     "my mem.d/a/MEMORY.md: duplicate pointer path other.md" \
     "my mem.d/ab/MEMORY.md: duplicate pointer path third.md" \
     "my memXd/MEMORY.md: duplicate pointer path decoy.md" \
+    "nested/my mem.d/MEMORY.md: duplicate pointer path suffix.md" \
     "root index line 'gone/x.md' has a prefix naming no mounted tier — it is a leftover from a removed tier and must be fixed by hand")
 
   run gitlore_compose_problems_in "my mem.d/a/MEMORY.md" <<< "$input"
@@ -1140,7 +1141,7 @@ b" ]
   cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
 }
 
-# --- gitlore_repair_index (K3): welds, then interleaved lines, then duplicates ---
+# --- gitlore_repair_index: welds, then interleaved lines, then duplicates ---
 #
 # A plain scratch file stands in for the arrival's carrier, and a plain
 # directory for the tier a weld's second path must resolve under — the
```

## Mutant

Applied to `scripts/lib/index-compose.sh`, `gitlore_compose_problems_in`
(temporary, reverted — `git diff -- scripts/` confirmed empty afterward):

```diff
 gitlore_compose_problems_in() {
   local file="$1" line found=1
   while IFS= read -r line || [ -n "$line" ]; do
-    case "$line" in
-      "$file: "*) ;;
-      *) continue ;;
-    esac
-    printf '%s\n' "$line"
-    found=0
+    if grep -F -- "$file: " <<< "$line" > /dev/null; then
+      printf '%s\n' "$line"
+      found=0
+    fi
   done
   return "$found"
 }
```

Failing `not ok` block, run against the mutant:

```
not ok 1 problem attribution matches the exact file prefix
# (in test file tests/index_compose.bats, line 1123)
#   `[ "$output" = "my mem.d/MEMORY.md: duplicate pointer path dup.md" ]' failed

bats: 0 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.vLTTSI
```

Assertion line: `tests/index_compose.bats:1123` — the exact-output check on the
`my mem.d/MEMORY.md` query. The mutant's unanchored `grep -F` matches the decoy
line `nested/my mem.d/MEMORY.md: duplicate pointer path suffix.md` as a
substring, leaking it into the output and breaking the exact-equality assertion.
The `case` prefix match excludes it, as the unmutated code does.

## Green run

Full file, unmutated, foreground:

```
bats: 84 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.QyEtbj
```

`shellcheck -x tests/index_compose.bats`: clean (no output).

## Commit

`574083fc0f416dc6500ad0aa9bba8f09f42cf96d` —
`test: Item 5.1 — a suffix decoy pins the prefix match` (gitmoji hook rewrote
the subject prefix to ✅). `tests/index_compose.bats` only;
`git diff -- scripts/` empty.
