#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
# Planted file contents carry literal `$output`, `$local_var_name` and
# backticked spans on purpose — they are fixtures for the checker to read, not
# expansions this suite wants.
# shellcheck disable=SC2016
#
# The checker reads the working tree under the git toplevel, so every case
# plants files in a throwaway repo rather than asserting against this one.
# Two cases at the end do run it against the real repo: one pins the known
# live `.claude/rules/shell.md` violations the sweep exists to clear, the
# other pins the invocation path (`just precommit` must actually reach it).

load helpers/setup

CHECKER=

setup() {
  setup_tmp_repo
  CHECKER="$PLUGIN_ROOT/scripts/check-memory-hygiene.py"
}
teardown() { teardown_tmp_repo; }

# Plant a memory fact. $1 = path under memory/, $2 = frontmatter name,
# remaining args are body lines.
plant_fact() {
  local path="memory/$1" name="$2"
  shift 2
  mkdir -p "$(dirname "$path")"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: a fact\n'
    printf 'metadata:\n  type: reference\n'
    printf -- '---\n\n'
    printf '%s\n' "$@"
  } > "$path"
}

# --- check 6: name drift ---------------------------------------------------

@test "name drift: frontmatter name differing from the basename blocks" {
  plant_fact "ddaanet/git-hook-env-leak.md" "git_hook_env_leak" "A body."
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"name-drift"* ]]
  [[ "$output" == *"git-hook-env-leak.md"* ]]
}

@test "name drift: matching name and basename is clean" {
  plant_fact "ddaanet/git-hook-env-leak.md" "git-hook-env-leak" "A body."
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "name drift: unparseable frontmatter is reported, not skipped" {
  mkdir -p memory/ddaanet
  printf -- '---\nname: [unclosed\n---\n\nbody\n' > memory/ddaanet/broken.md
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"frontmatter"* ]]
}

# --- check 1: first person -------------------------------------------------

@test "first person: a bare I in a body blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" "Then I concluded the opposite."
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"first-person"* ]]
  [[ "$output" == *"a-fact.md:8"* ]]
}

@test "first person: 'my own' blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" "It raced my own edits."
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"first-person"* ]]
}

@test "first person: 'My own' opening a sentence blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" "My own audit reported zero."
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"first-person"* ]]
}

# The `my own` half is case-insensitive; the bare-pronoun half must not be, or
# every `i.e.` in the store becomes a violation.
@test "first person: a lowercase standalone i is not a pronoun hit" {
  plant_fact "ddaanet/a-fact.md" "a-fact" "Parse it, i.e. never regex it."
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "first person: an embedded capital I does not trip the word boundary" {
  plant_fact "ddaanet/a-fact.md" "a-fact" "The API and the CLI agree."
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "first person: 'my human partner' is the required phrase, not a hit" {
  plant_fact "ddaanet/a-fact.md" "a-fact" "Ask my human partner first."
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "first person: a hit inside a fenced code block is ignored" {
  plant_fact "ddaanet/a-fact.md" "a-fact" \
    '```sh' 'grep -n "I am output" log' '```' 'Prose without the pronoun.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "first person: a hit inside an inline code span is ignored" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'The error reads `no I here` verbatim.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

# --- check 3: direct naming ------------------------------------------------

@test "direct naming: the capitalised given name blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'David flagged this twice.'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"direct-naming"* ]]
}

@test "direct naming: a lowercase home path is not a naming violation" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'The repo lives at /Users/david/code/x.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

# --- check 2: deictics (warn, never block) ---------------------------------

@test "deictics: a session-anchored word warns without blocking" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'The flag is currently unset.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN"* ]]
  [[ "$output" == *"deictic"* ]]
}

@test "deictics: 'this session' warns" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'Measured this session at 2%.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"deictic"* ]]
}

# --- check 4b: pre-rename tokens -------------------------------------------

@test "pre-rename token: a stale snake_case memory name in live context blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'A plain body.'
  mkdir -p .claude/rules
  printf 'See `memory/feedback_whitespace_safety.md` for detail.\n' \
    > .claude/rules/shell.md
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pre-rename"* ]]
  [[ "$output" == *".claude/rules/shell.md:1"* ]]
}

@test "pre-rename token: a shell comment in scripts/ blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'A plain body.'
  mkdir -p scripts/lib
  printf '#!/usr/bin/env bash\n# see memory/reference_git_hook_env_leak.md\n' \
    > scripts/lib/x.sh
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"pre-rename"* ]]
}

@test "pre-rename token: tests/ and plans/ are out of scope" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'A plain body.'
  mkdir -p tests plans
  printf 'fixture uses memory/feedback_whitespace_safety.md\n' > tests/x.bats
  printf 'history cites memory/reference_git_hook_env_leak.md\n' > plans/x.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "pre-rename token: an ordinary snake_case identifier is not a hit" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'A plain body.'
  mkdir -p scripts
  printf '#!/usr/bin/env bash\nlocal_var_name=1\necho "$local_var_name"\n' \
    > scripts/x.sh
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

# --- check 4a: broken memory references ------------------------------------

@test "broken reference: a memory path cited from a fact that does not exist blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'See `memory/ddaanet/gone.md`.'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"broken-reference"* ]]
}

@test "broken reference: a memory path that resolves is clean" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'See `memory/ddaanet/b-fact.md`.'
  plant_fact "ddaanet/b-fact.md" "b-fact" 'A body.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

# --- check 5: dangling wikilinks (warn) ------------------------------------

@test "wikilink: an unresolved slug warns without blocking" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'Related: [[not-written-yet]].'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dangling-wikilink"* ]]
}

@test "wikilink: a slug matching another fact's frontmatter name is clean" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'Related: [[b-fact]].'
  plant_fact "ddaanet/b-fact.md" "b-fact" 'A body.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"dangling-wikilink"* ]]
}

@test "wikilink: a bash [[ test ]] inside a fence is not read as a link" {
  plant_fact "ddaanet/a-fact.md" "a-fact" \
    '```bash' '[[ "$output" == *"x"* ]] || exit 1' '```'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"dangling-wikilink"* ]]
}

# --- suppression, scope, discovery -----------------------------------------

# --- check 7: volatile git state -------------------------------------------

@test "volatile state: an abbreviated sha in a fact body blocks" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'Fixed in commit `7c0471b`.'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"volatile-state"* ]]
  [[ "$output" == *"7c0471b"* ]]
}

@test "volatile state: read raw, since a sha's habitat is a code span" {
  plant_fact "ddaanet/a-fact.md" "a-fact" '```' 'fixed (`e205aa6`)' '```'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"e205aa6"* ]]
}

@test "volatile state: frontmatter originSessionId is not a violation" {
  mkdir -p memory/ddaanet
  {
    printf -- '---\n'
    printf 'name: a-fact\ndescription: a fact\n'
    printf 'metadata:\n  type: reference\n'
    printf '  originSessionId: 94e0a066-a634-4a25-a32d-b0f53b992c25\n'
    printf -- '---\n\nA body naming no sha.\n'
  } > memory/ddaanet/a-fact.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"94e0a066"* ]]
}

@test "volatile state: all-digit runs are numbers, not shas" {
  plant_fact "ddaanet/a-fact.md" "a-fact" \
    'Mode 100644 and a 160000 gitlink; the budget is 25600 bytes, seen at 26754.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"100644"* ]]
}

@test "volatile state: a hex word is a word, not a sha" {
  plant_fact "ddaanet/a-fact.md" "a-fact" \
    'The next line added a facade; the entry acceded and was defaced.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"acceded"* ]]
}

@test "volatile state: uppercase hex is an acronym, a sha is lowercase" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'The FDA and the CDC once used EBCDIC.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"EBCDIC"* ]]
}

@test "suppression: a hygiene-ok marker clears the line it sits on" {
  plant_fact "ddaanet/a-fact.md" "a-fact" \
    'The brief said "I cut only elaboration". <!-- hygiene-ok -->'
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "scope: the index and the always-on tier file skip the prose checks" {
  mkdir -p memory/ddaanet
  printf '# Memory Index\n\nI maintain this by hand, currently.\n' > memory/MEMORY.md
  printf '# Shared\n\nRefer to my human partner. I am the voice here.\n' \
    > memory/ddaanet/shared-claude.md
  run "$CHECKER"
  [ "$status" -eq 0 ]
}

@test "whitespace: a fact path containing a space is scanned, not split" {
  plant_fact "ddaanet/a b.md" "a b" 'Then I concluded the opposite.'
  run "$CHECKER"
  [ "$status" -eq 1 ]
  [[ "$output" == *"a b.md"* ]]
}

@test "clean tree: the gate signs off with the checks it ran" {
  plant_fact "ddaanet/a-fact.md" "a-fact" 'A plain body.'
  run "$CHECKER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"name-drift"* ]]
  [[ "$output" == *"first-person"* ]]
  [[ "$output" == *"direct-naming"* ]]
  [[ "$output" == *"pre-rename"* ]]
  [[ "$output" == *"broken-reference"* ]]
  [[ "$output" == *"1 fact"* ]]
}

@test "empty store: no memory directory is an error, not a silent pass" {
  run "$CHECKER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no memory"* ]]
}

@test "discovery: the checker is executable" {
  [ -x "$PLUGIN_ROOT/scripts/check-memory-hygiene.py" ]
}

@test "discovery: just precommit reaches the checker" {
  # The recipe body between `precommit:` and the next recipe header must name
  # the checker — a mention anywhere else in the justfile would not run it.
  run awk '/^precommit:/{inr=1;next} /^[a-z-]+:/{inr=0} inr' "$PLUGIN_ROOT/justfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-memory-hygiene"* ]]
}

@test "real repo: the checker reports zero blocking violations" {
  run "$CHECKER" --root "$PLUGIN_ROOT"
  [ "$status" -eq 0 ]
}
