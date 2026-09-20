#!/usr/bin/env bats
# scripts/run-bats-cached.sh against tiny real suites: bats itself decides
# pass/fail, and each suite's own marker file says whether IT actually ran —
# the junit report is the plumbing, not the thing asserted on.

load helpers/setup

setup()    { setup_tmp_repo; MARK="$TMP_REPO/marks"; mkdir -p "$MARK"; KEYS="$TMP_REPO/keys"; }
teardown() { teardown_tmp_repo; }

# A suite that touches "$MARK/<name>.ran" and then passes or fails.
plant() {
  local name="$1" outcome="${2:-pass}"
  local ok=true
  [ "$outcome" = "pass" ] || ok=false
  cat > "$name" <<EOF
#!/usr/bin/env bats
@test "$name runs" {
  : > "$MARK/$name.ran"
  $ok
}
EOF
}

ran() {
  [ -e "$MARK/$1.ran" ]
}

clear_marks() { rm -f "$MARK"/*.ran; }

cached() {
  "$PLUGIN_ROOT/scripts/run-bats-cached.sh" "$@"
}

@test "a second run over unchanged suites runs nothing, exits 0, reports all cached" {
  plant a.bats; plant b.bats
  run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  clear_marks
  run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 suites cached"* ]]
  [[ "$output" == *"0 run"* ]]
  run ! ran a.bats
  run ! ran b.bats
}

@test "editing one suite runs that suite only" {
  plant a.bats; plant b.bats
  run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  clear_marks
  printf '# touched\n' >> a.bats
  run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  ran a.bats
  run ! ran b.bats
}

@test "a different shared hash runs everything" {
  plant a.bats; plant b.bats
  run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  clear_marks
  run cached "$KEYS" h2 -- a.bats b.bats
  [ "$status" -eq 0 ]
  ran a.bats
  ran b.bats
}

@test "adding a suite runs everything" {
  plant a.bats; plant b.bats
  run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  clear_marks
  plant c.bats
  run cached "$KEYS" h1 -- a.bats b.bats c.bats
  [ "$status" -eq 0 ]
  ran a.bats
  ran b.bats
  ran c.bats
}

@test "a failing suite is not recorded and runs again; the passing misses beside it are recorded" {
  plant p1.bats pass; plant p2.bats pass; plant f1.bats fail
  run cached "$KEYS" h3 -- p1.bats p2.bats f1.bats
  [ "$status" -ne 0 ]
  ran p1.bats
  ran p2.bats
  ran f1.bats
  clear_marks
  run cached "$KEYS" h3 -- p1.bats p2.bats f1.bats
  [ "$status" -ne 0 ]
  run ! ran p1.bats
  run ! ran p2.bats
  ran f1.bats
}

@test "a --reads-all suite runs when a sibling's contents change" {
  plant r.bats; plant s.bats
  run cached "$KEYS" h1 --reads-all r.bats -- r.bats s.bats
  [ "$status" -eq 0 ]
  clear_marks
  printf '# touched\n' >> s.bats
  run cached "$KEYS" h1 --reads-all r.bats -- r.bats s.bats
  [ "$status" -eq 0 ]
  ran r.bats
  ran s.bats
}

@test "GITLORE_GATE_FORCE=1 runs everything" {
  plant a.bats; plant b.bats
  run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  clear_marks
  GITLORE_GATE_FORCE=1 run cached "$KEYS" h1 -- a.bats b.bats
  [ "$status" -eq 0 ]
  ran a.bats
  ran b.bats
}

@test "a suite edited while the run is in flight is not recorded" {
  cat > m.bats <<EOF
#!/usr/bin/env bats
@test "m runs" {
  : > "$MARK/m.bats.ran"
  printf '\n# touched\n' >> "\$BATS_TEST_FILENAME"
  true
}
EOF
  run cached "$KEYS" h1 -- m.bats
  [ "$status" -eq 0 ]
  clear_marks
  run cached "$KEYS" h1 -- m.bats
  [ "$status" -eq 0 ]
  ran m.bats
}

@test "the exit status is bats' own on failure" {
  plant f1.bats fail
  run cached "$KEYS" h1 -- f1.bats
  [ "$status" -ne 0 ]
}

@test "a report whose verdicts are not in the order the suites were given records nothing" {
  # Position is how a verdict finds its suite, so a report in another order
  # would hand the failing suite the passing one's verdict. The scripts are
  # copied beside a parser that reverses the real one's lines.
  mkdir alt
  cp "$PLUGIN_ROOT/scripts/run-bats-cached.sh" "$PLUGIN_ROOT/scripts/run-bats.sh" alt/
  cat > alt/parse-bats-junit.py <<PARSER
#!/usr/bin/env bash
"$PLUGIN_ROOT/scripts/parse-bats-junit.py" "\$@" | sed '1!G;h;\$!d'
PARSER
  chmod +x alt/parse-bats-junit.py
  plant f1.bats fail; plant p1.bats pass
  run alt/run-bats-cached.sh "$KEYS" h9 -- f1.bats p1.bats
  [ "$status" -ne 0 ]
  [[ "$output" == *"nothing recorded"* ]]
  clear_marks
  run alt/run-bats-cached.sh "$KEYS" h9 -- f1.bats p1.bats
  ran f1.bats
  ran p1.bats
}
