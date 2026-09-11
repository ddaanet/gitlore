# RED: atomic relay write

Three cases added to `tests/index_sync.bats`, immediately after
`an unreadable marker costs the relay, not the hook` (:1181) and before the
`--- routing-key advisories ---` section. No implementation change, no staging,
no commit — `scripts/lib/index-sync.sh` is unmodified.

Command: `scripts/run-bats.sh tests/index_sync.bats -f "relay"` — 11 passed (the
ten pre-existing relay cases, untouched), 2 failed (the new red cases below);
the third new case passes (born green, see Case 3).

## Case 1 — `relay_drain does not fold a stranded .tmp marker`

Died on **`[ -z "$GITLORE_RELAY_SYSMSG" ]`** (line 1290) — the first assertion
after the drain call, before any of the later selective checks (pairing with a
real `a1` marker, the `!= *"TORN-BODY"*` / `!= *"orphan"*` checks) ever execute.

Fixture: a `gitlore-relay-orphan.tmp` file is written directly in the memory
gitdir carrying a torn sysmsg block (delimiter + body, no ctx delimiter — no
`gitlore_relay_write` call, so the torn shape is exact). `gitlore_relay_drain`
is run with that `.tmp` as the *only* file present.

Quoted failure:
```
not ok 1 relay_drain does not fold a stranded .tmp marker
# (in test file tests/index_sync.bats, line 1290)
#   `[ -z "$GITLORE_RELAY_SYSMSG" ]' failed
```

Captured value at failure (via a temporary `>&3` probe, removed before the final
run):
```
DEBUG SYSMSG=[--- gitlore-relay agent orphan.tmp ---
TORN-BODY
] CTX=[--- gitlore-relay agent orphan.tmp ---

]
```
Confirms today's code enumerates the `.tmp` as if it were a real marker
(`-name 'gitlore-relay-*'` has no extension check), frames it under the bogus
agent id `orphan.tmp`, and folds the torn body into `SYSMSG`.

The test then (unreached today, but will run once this case is green) recreates
the `.tmp`, stages a real `a1` marker, drains again, and asserts `a1` is folded
and framed while the `.tmp`'s body and agent name never appear in either channel
— proving the exclusion is selective, not the drain returning early.

## Case 2 — `relay_write does not destroy a staged report when the install fails`

Died on **`[ "$status" -ne 0 ]`** (line 1328) — reached after the first write's
own `[ "$status" -eq 0 ]` passed normally.

Mechanism: stage `S1`/`C1` for `a1`, record the marker's bytes, then
`mkdir "$marker.tmp"` — squatting the path the atomic write is expected to land
on before its `mv`, the same shape as the existing "squatted marker path" case
(:1127) one path segment over. A second write (`S2`/`C2`, same agent id) is run
against that squat.

Quoted failure:
```
not ok 1 relay_write does not destroy a staged report when the install fails
# (in test file tests/index_sync.bats, line 1329)
#   `[ "$status" -ne 0 ]' failed
```
(line number shifted by 1 between runs depending on an in-flight debug line; the
assertion is the same one.)

Captured values at failure (via a temporary `>&3` probe, removed before the
final run):
```
DEBUG status=[0] marker_now=[--- gitlore-relay-sysmsg ---
S1
S2
--- gitlore-relay-ctx ---
C1
C2]
```
Today's `gitlore_relay_write` never touches `$marker.tmp` — it writes `$marker`
directly — so squatting that path is irrelevant to it: the second write succeeds
(status 0) and merges `S2`/`C2` into the existing marker exactly as designed
today. Once the write goes through `$marker.tmp` + `mv`, this same squat blocks
the write before anything is renamed into place, returning non-zero, and —
because the following assertions (unreached today) require the squat directory
to remain a directory and `$marker`'s bytes to equal `$before` — those also
confirm the ORIGINAL report is never touched.

## Case 3 — `relay_drain removes a .tmp stranded alongside the marker it drains`

**Does not red against the current code — passes today.** Evidence:

```
bats: 1 passed, 0 failed
```

Root cause: today's drain has no `.tmp` exclusion, so `gitlore-relay-a1.tmp` is
enumerated as its own "marker" (agent id `a1.tmp`) right alongside the real
`gitlore-relay-a1`, and the loop's `rm -f "$marker"` removes *every* enumerated
name — so both files vanish today too, just because each is independently
drained-and-removed as if it were a legitimate report, not because the intended
cleanup step exists. Captured via a temporary `>&3` probe before reverting:
```
DEBUG SYSMSG=[--- gitlore-relay agent a1 ---
S1
--- gitlore-relay agent a1.tmp ---

]
DEBUG marker_exists=[no] tmp_exists=[no]
```

I confirmed the case is still a meaningful regression pin (not vacuous) by
mutating a scratch copy of `gitlore_relay_drain`'s `find` to add
`'!' -name '*.tmp'` (fix item 2, the enumeration exclusion) WITHOUT adding the
explicit `rm -f "$marker.tmp"` (fix item 3, the cleanup line). Against that
partial mutation:
- Case 1 goes green (the exclusion alone is enough for it).
- Case 3 goes red:
  ```
  not ok 1 relay_drain removes a .tmp stranded alongside the marker it drains
  # (in test file tests/index_sync.bats, line 1351)
  #   `[ ! -e "$marker.tmp" ]' failed
  ```
  because excluding the `.tmp` from enumeration also means the drain never
  reaches it to remove it, and nothing else does.

The mutation was applied to `scripts/lib/index-sync.sh`, tested, and fully
reverted (`git diff scripts/lib/index-sync.sh` is empty) — the working tree
carries no implementation change, only the three new test cases in
`tests/index_sync.bats`.

Per the task's instruction to report rather than weaken the assertion when a
case can't be made to red against the current code: Case 3 is kept exactly as
specified (`gitlore-relay-<id>` + `gitlore-relay-<id>.tmp` both present, assert
neither exists after drain) because it correctly pins fix item 3 against a
partial implementation, even though the current unfixed baseline happens to
satisfy it by accident.
