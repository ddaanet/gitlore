# GREEN: atomic relay write

`scripts/lib/index-sync.sh` only. Nothing staged, nothing committed.

## Diff applied

```diff
--- a/scripts/lib/index-sync.sh
+++ b/scripts/lib/index-sync.sh
@@ -179,12 +179,42 @@ $sysmsg"; fi
     if [ -n "$old_ctx" ]; then ctx="$old_ctx
 $ctx"; fi
   fi
+  # Built at "$marker.tmp" and installed with `mv` rather than written
+  # straight to "$marker": a process killed mid-write (or ENOSPC, or EIO)
+  # would otherwise leave a torn prefix on the marker path itself, and
+  # _gitlore_relay_sysblock/_gitlore_relay_ctxblock cannot tell a torn file
+  # from a whole one — the next drain folds the partial body in as if it
+  # were a real report and destroys it, taking down whatever was already
+  # staged for this agent along with it. A killed writer instead leaves only
+  # the temp; the marker this drain reads is untouched. `mv` within one
+  # gitdir is a same-filesystem rename, so the install itself cannot tear.
+  #
+  # `&&`, not a bare sequence relying on the function's `set -e`: both call
+  # sites are `if ! gitlore_relay_write …`, a condition context where
+  # errexit is off, so a failed write here must return non-zero itself
+  # rather than let the shell abort — that non-zero is what routes into the
+  # callers' own "could not be staged" reporting instead of silently losing
+  # the report.
   {
     printf -- '--- gitlore-relay-sysmsg ---\n'
     printf '%s\n' "$sysmsg"
     printf -- '--- gitlore-relay-ctx ---\n'
     printf '%s\n' "$ctx"
-  } > "$marker"
+  } > "$marker.tmp" || return 1
+  if [ -d "$marker" ]; then
+    # A directory already squatting the marker path is refused, the same
+    # shape gitlore_relay_drain's own `-type f` filter names as "what makes a
+    # relay write fail in the first place". Refused explicitly rather than
+    # left to `mv`: POSIX `mv` treats an existing directory destination as a
+    # target directory and moves the source *into* it instead of failing, so
+    # without this check the squat would silently succeed at
+    # "$marker/$(basename "$marker.tmp")" — landing nowhere the drain's glob
+    # (`gitlore-relay-*` at `-maxdepth 1`) ever looks. The temp is removed so
+    # the squat leaves nothing on disk for a later run to trip over.
+    rm -f "$marker.tmp"
+    return 1
+  fi
+  mv "$marker.tmp" "$marker"
 }
 
 # Fold every keyed relay marker in the memory gitdir into
@@ -215,10 +245,20 @@ gitlore_relay_drain() {
   # cannot remove it, so every later run would frame it again. That shape is
   # what makes a relay write fail in the first place — a directory already
   # occupying the marker path — not something a failed write leaves behind.
+  #
+  # `'!' -name '*.tmp'` excludes gitlore_relay_write's in-progress temp: a
+  # writer killed between opening "$marker.tmp" and its `mv` leaves that temp
+  # standing beside (or alone, if this is the agent's first write) the real
+  # marker, and without this exclusion it is enumerated as a "marker" of its
+  # own — framed under the bogus agent id its `.tmp` suffix becomes part of,
+  # its torn body folded in, and then rm -f'd as evidence. Excluding it here
+  # is also why the loop below never removes it itself: only the temp that
+  # belongs to a marker this drain actually drains is cleaned up, further
+  # down, once that marker is known to be a real one.
   names=""
   while IFS= read -r -d '' marker; do
     names="$names${marker##*/}"$'\n'
-  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' -print0)
+  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print0)
   [ -n "$names" ] || return 0
   # Sorted, because find's own directory order is not guaranteed. Basenames
   # rather than whole paths: a basename is `gitlore-relay-` plus the
@@ -252,6 +292,20 @@ $ctxblock
     # shape, so a marker this drain can read fine still costs its caller
     # everything if the directory it lives in refuses the remove.
     rm -f "$marker" || true
+    # A stranded "$marker.tmp" for THIS agent id — the writer that produced
+    # this very marker died on some *later* write than the one that landed,
+    # rather than on its first — is cleaned up here rather than left for the
+    # next drain to trip over again. Scoped to a marker actually drained
+    # above, not a blanket sweep of every `.tmp` in the gitdir: two main
+    # sessions in the same repo are not sequential the way hooks within one
+    # session are, and a blanket sweep could unlink a concurrent session's
+    # own in-flight temp out from under its `mv`, turning a harmless stranded
+    # file into a lost report for a session that is still running. The
+    # residual this leaves is one stranded temp per agent whose very first
+    # write died — no prior marker for `rm -f "$marker.tmp"` here to reach —
+    # which is bounded for the same reason the pre-image/compose-stamp pair
+    # already is: an agent id is never reused.
+    rm -f "$marker.tmp" || true
   done < <(printf '%s' "$names" | LC_ALL=C sort)
   return 0
 }
```

## Deviation from the dispatch — a real regression, fixed

The dispatch's change 1 specified `gitlore_relay_write`'s final statement as a
bare `{ … } > "$marker.tmp" && mv "$marker.tmp" "$marker"`. Applied verbatim, it
broke a pre-existing case in the same file:
`relay_write refuses a squatted marker path` (:1127) — squats `$marker` itself
as a directory before the call and asserts non-zero status, a directory left
standing, and no `gitlore-relay*` file surviving.

Cause: once the write no longer touches `$marker` directly (only `$marker.tmp`),
the write to the temp succeeds regardless of what `$marker` is. The failure has
to come from the `mv`, and POSIX `mv` does not fail when its destination is an
existing directory — it moves the source *into* that directory instead, landing
at `"$marker/$(basename "$marker.tmp")"`, a path the drain's `-maxdepth 1` glob
never reaches. `run gitlore_relay_write` returned 0, the count of
`gitlore-relay*` regular files under the gitdir was 1 (the misplaced temp, now
nested one level too deep to be seen by the test's own `-maxdepth 1` probe but
still on disk), and the case went red.

Fixed by checking `[ -d "$marker" ]` explicitly between the write-to-temp and
the `mv`, removing the temp and returning 1 on that branch — refusing the squat
instead of leaving it to `mv`'s directory-destination semantics. Confirmed
against the tree: without this check,
`relay_write refuses a squatted marker path` fails as described; with it, all 14
relay cases in the file pass. No other case in the file exercises `mv` against a
squatted `$marker`, so nothing else was silently depending on the old
direct-write failure mode.

## Per-case pass output

`scripts/run-bats.sh tests/index_sync.bats -f "relay"`:

```
bats: 14 passed, 0 failed
```

All ten pre-existing relay cases plus the four new ones (including the squat
regression above) pass together.

## Whole-file and neighbouring suites

`scripts/run-bats.sh tests/index_sync.bats`:

```
bats: 88 passed, 0 failed
```

`scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats tests/resolve_recovery.bats`:

```
bats: 71 passed, 0 failed
```

## Lint

`scripts/lint-shell.sh`: `137 files clean`.

## Not run

`just precommit` — per dispatch, left for the orchestrator. Nothing staged,
nothing committed; `git status --porcelain` shows only `tests/index_sync.bats`
and `scripts/lib/index-sync.sh` modified.

## Everything else in the dispatch checked out

- The `&&`-vs-`set -e` reasoning, the `.tmp` naming via
  `gitlore_relay_marker_file`, the `find … '!' -name '*.tmp'` exclusion, and the
  `rm -f "$marker.tmp"` cleanup scoped to a marker actually drained (not a
  blanket sweep) — all applied as specified, with the "why" comments in the
  surrounding functions' register.
- The lone-orphan `.tmp` survives a drain (case 1's `[ -e "$tmp" ]`): confirmed
  by the passing case; the drain never reaches an orphan's temp because it never
  reaches the orphan's (nonexistent) marker.
- Portability: `'!'` as a `find` primary, `mv` as a same-directory POSIX rename,
  `"$marker.tmp"` quoted everywhere it is expanded. No GNU-only flag was reached
  for.
