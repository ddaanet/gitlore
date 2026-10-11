#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup

WIRE_LEFTHOOK="$PLUGIN_ROOT/scripts/hook-manager/wire-lefthook.sh"
WIRE_HUSKY="$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"

# setup() creates a bare tmp repo only; individual tests seed their own
# fixtures so lefthook and husky tests remain independent.
setup() {
  setup_tmp_repo
}
teardown() { teardown_tmp_repo; }

# ---------------------------------------------------------------------------
# lefthook tests — each seeds lefthook.yml before calling the script
# ---------------------------------------------------------------------------

@test "wire-lefthook adds the gitlore command under pre-push only" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' lefthook.yml
  grep -qF 'git rev-parse --git-common-dir' lefthook.yml
  grep -q 'gitlore-pre-push' lefthook.yml
  run ! grep -q 'gitlore-pre-commit' lefthook.yml
}

@test "wire-lefthook is idempotent (marker present → no change)" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  bash "$WIRE_LEFTHOOK"
  cp lefthook.yml lefthook.yml.before
  bash "$WIRE_LEFTHOOK"
  diff lefthook.yml lefthook.yml.before
}

@test "wire-lefthook writes sentinel file" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  mkdir -p .claude
  bash "$WIRE_LEFTHOOK"
  [ -f .claude/gitlore-hook-setup ]
  [ "$(cat .claude/gitlore-hook-setup)" = "lefthook install" ]
}

@test "wire-lefthook preserves existing pre-commit commands" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  bash "$WIRE_LEFTHOOK"
  grep -q 'eslint' lefthook.yml
  run ! grep -q 'gitlore-pre-commit' lefthook.yml
  grep -q 'gitlore-pre-push' lefthook.yml
}

@test "wire-lefthook works with .lefthook.yml filename" {
  cat > .lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' .lefthook.yml
}

@test "wire-lefthook exits 1 when no config found" {
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# husky tests — start from clean state (no lefthook.yml)
# ---------------------------------------------------------------------------

@test "wire-husky appends the guarded exec line to .husky/pre-push only" {
  mkdir .husky
  : > .husky/pre-commit
  : > .husky/pre-push
  run bash "$WIRE_HUSKY"
  [ "$status" -eq 0 ]
  [ ! -s .husky/pre-commit ]
  grep -q '# gitlore: managed' .husky/pre-push
  grep -qF 'git rev-parse --git-common-dir' .husky/pre-push
  grep -q 'gitlore-pre-push' .husky/pre-push
}

@test "wire-husky creates a missing pre-push file and no pre-commit file" {
  mkdir .husky
  bash "$WIRE_HUSKY"
  [ -f .husky/pre-push ]
  [ ! -e .husky/pre-commit ]
}

@test "wire-husky is idempotent" {
  mkdir .husky
  bash "$WIRE_HUSKY"
  [ -f .husky/pre-push ]
  cp .husky/pre-push .husky/pre-push.before
  bash "$WIRE_HUSKY"
  diff .husky/pre-push .husky/pre-push.before
}

@test "wire-husky writes sentinel" {
  mkdir .husky .claude
  bash "$WIRE_HUSKY"
  [ "$(cat .claude/gitlore-hook-setup)" = "npx husky" ]
}

# ---------------------------------------------------------------------------
# overcommit tests
# ---------------------------------------------------------------------------

WIRE_OVERCOMMIT="$PLUGIN_ROOT/scripts/hook-manager/wire-overcommit.sh"

@test "wire-overcommit adds the gitlore PrePush entry and no PreCommit one" {
  cat > .overcommit.yml <<'EOF'
PreCommit:
  RuboCop:
    enabled: true
EOF
  run bash "$WIRE_OVERCOMMIT"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' .overcommit.yml
  run ! grep -q 'gitlore-pre-commit' .overcommit.yml
  grep -q 'gitlore-pre-push' .overcommit.yml
  grep -qF 'git rev-parse --git-common-dir' .overcommit.yml
  [ "$(cat .claude/gitlore-hook-setup)" = "overcommit --install" ]
}

@test "overcommit command array forwards appended files to the wrapper as \$@ (D11 verification)" {
  cat > .overcommit.yml <<'EOF'
PreCommit:
  RuboCop:
    enabled: true
EOF
  bash "$WIRE_OVERCOMMIT"

  # Reproduce overcommit's invocation: it exec's the command array directly
  # (no shell) and appends staged files as extra argv. We swap the embedded
  # wrapper path for a capture stub, then run the array + files and check the
  # stub saw the files — spaces intact — as positional args.
  cap="$TMP_REPO/cap.sh"
  printf '#!/usr/bin/env sh\nprintf "%%s\\n" "$@"\n' > "$cap"
  chmod +x "$cap"

  run python3 - "$cap" <<'PY'
import sys, subprocess, yaml
cap = sys.argv[1]
cmd = yaml.safe_load(open('.overcommit.yml'))['PrePush']['gitlore']['command']
cmd = [c.replace('"$(git rev-parse --git-common-dir)/gitlore-pre-push"', '"%s"' % cap) for c in cmd]
out = subprocess.run(cmd + ['a.rb', 'b c.rb'], capture_output=True, text=True)
sys.stdout.write(out.stdout)
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "a.rb" ]
  [ "${lines[1]}" = "b c.rb" ]
}

# ---------------------------------------------------------------------------
# direct tests
# ---------------------------------------------------------------------------

WIRE_DIRECT="$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
EMIT="$PLUGIN_ROOT/scripts/emit-wrappers.sh"

@test "wire-direct installs the .git/hooks/pre-push stub and no pre-commit hook" {
  run bash "$WIRE_DIRECT"
  [ "$status" -eq 0 ]
  [ -x .git/hooks/pre-push ]
  [ ! -e .git/hooks/pre-commit ]
  grep -qF 'git rev-parse --git-common-dir' .git/hooks/pre-push
  grep -q 'gitlore-pre-push' .git/hooks/pre-push
  grep -q '# gitlore: managed' .git/hooks/pre-push
  [ "$(cat .claude/gitlore-hook-setup)" = "direct" ]
}

# The shim wire-direct used to write for pre-commit, byte for byte. .git/hooks
# is not a published boundary, so the one this tool wrote is removed.
@test "wire-direct removes a .git/hooks/pre-commit shim byte-identical to the one it used to write" {
  # shellcheck disable=SC2016  # the shim text is literal; git expands it at hook time
  printf '#!/usr/bin/env sh\n# gitlore: managed\nexec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  run bash "$WIRE_DIRECT"
  [ "$status" -eq 0 ]
  [ ! -e .git/hooks/pre-commit ]
  [ -x .git/hooks/pre-push ]
}

@test "wire-direct leaves a user's own pre-commit hook untouched" {
  printf '#!/bin/sh\necho user hook\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  cp .git/hooks/pre-commit .git/hooks/pre-commit.before
  bash "$WIRE_DIRECT"
  diff .git/hooks/pre-commit .git/hooks/pre-commit.before
  [ -x .git/hooks/pre-push ]
}

# What the old wire-direct appended to an existing hook, byte for byte:
# "\n# gitlore: managed\nexec \"$(git rev-parse --git-common-dir)/gitlore-pre-commit\" \"$@\"\n".
# .git/hooks is not a published boundary, so the block it wrote goes; the user's
# own lines stay.
@test "wire-direct strips the block the old version appended to a user's pre-commit hook" {
  printf '#!/bin/sh\necho user hook\n' > .git/hooks/pre-commit
  # shellcheck disable=SC2016  # the block text is literal; git expands it at hook time
  printf '\n# gitlore: managed\nexec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"\n' >> .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  run bash "$WIRE_DIRECT"
  [ "$status" -eq 0 ]
  [ -x .git/hooks/pre-commit ]
  grep -q 'echo user hook' .git/hooks/pre-commit
  run ! grep -q 'gitlore-pre-commit' .git/hooks/pre-commit
  run ! grep -q 'gitlore: managed' .git/hooks/pre-commit
}

@test "wire-direct is idempotent and preserves existing user hooks" {
  printf '#!/bin/sh\necho user hook\n' > .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  bash "$WIRE_DIRECT"
  grep -q 'echo user hook' .git/hooks/pre-push
  grep -q 'gitlore-pre-push' .git/hooks/pre-push
  # Second run: no duplicate lines.
  cp .git/hooks/pre-push .git/hooks/pre-push.before
  bash "$WIRE_DIRECT"
  diff .git/hooks/pre-push .git/hooks/pre-push.before
}

@test "wire-direct refuses to append after an existing hook body that execs" {
  printf '#!/bin/sh\nexec just prepush\n' > .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  cp .git/hooks/pre-push .git/hooks/pre-push.before
  run --separate-stderr bash "$WIRE_DIRECT"
  [ "$status" -ne 0 ]
  # File untouched: no unreachable append landed.
  diff .git/hooks/pre-push .git/hooks/pre-push.before
  [[ "$stderr" == *"exec"* ]]
  [[ "$stderr" == *"pre-push"* ]]
}

@test "wire-direct stub resolves the wrapper from a linked worktree (D11)" {
  echo seed > f && git add f && git commit -q -m seed
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  cd "$WT"
  bash "$EMIT"          # emit wrappers into the shared common dir
  bash "$WIRE_DIRECT"   # wire the stub via --git-path hooks/<hook>

  # A fake "real hook" the wrapper will exec, proving the whole chain resolves.
  fake="$WT/fakehooks" && mkdir -p "$fake"
  printf '#!/usr/bin/env sh\necho real-hook-ran\n' > "$fake/pre-push"
  chmod +x "$fake/pre-push"
  git config gitlore.hooksDir "$fake"

  hookfile=$(git rev-parse --git-path hooks/pre-push)
  run "$hookfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real-hook-ran"* ]]
  rm -rf "$WT"
}

# ---------------------------------------------------------------------------
# manual tests
# ---------------------------------------------------------------------------

WIRE_MANUAL="$PLUGIN_ROOT/scripts/hook-manager/wire-manual.sh"

@test "wire-manual writes a manual sentinel without modifying any files" {
  ls > .before
  run bash "$WIRE_MANUAL"
  [ "$status" -eq 0 ]
  [ "$(cat .claude/gitlore-hook-setup)" = "manual" ]
  # No new files beyond the sentinel (.claude/ already excluded by ls default).
  ls > .after
  diff .before .after
}

@test "wire-manual lists detected managers when called with a list argument" {
  run --separate-stderr bash "$WIRE_MANUAL" "lefthook,husky"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"multiple hook managers detected"* ]]
  [[ "$stderr" == *"lefthook,husky"* ]]
}

@test "wire-manual instructions reference the common-dir wrapper path (D11)" {
  run --separate-stderr bash "$WIRE_MANUAL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"git rev-parse --git-common-dir"* ]]
  [[ "$stderr" == *"gitlore-pre-push"* ]]
  [[ "$stderr" != *"gitlore-pre-commit"* ]]
}
