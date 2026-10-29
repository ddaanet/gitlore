#!/usr/bin/env bash
# Drivers for commit-memory.sh's one input: a sectioned summary on stdin. Loaded
# by helpers/setup, so every suite and fixture helper has them.
#
# A suite whose subject is not the section check calls commit_sections, which
# builds the summary the contract asks for from the stores that have changes:
# one `== <tier> ==` section per dirty tier, then `== memory ==` when root has a
# change beyond the tier-only ones (a tier gitlink, MEMORY.md lines under a tier
# prefix), each carrying the same message. The section
# check itself is exercised only in commit_memory_summary.bats, which writes its
# summaries out literally.

# commit_with <summary-text>: pipe the text, verbatim, to the script.
commit_with() {
  printf '%s\n' "$1" | bash "${COMMIT_SCRIPT:-$PLUGIN_ROOT/scripts/commit-memory.sh}"
}

# stub_commit_script <shell-text>: copy scripts/ under the test's tmp dir with
# <shell-text> defined right after commit-memory.sh loads its libraries, and
# point COMMIT_SCRIPT at the copy, so commit_with and commit_sections drive a
# script whose git or compose step is a stand-in for a state no fixture reaches.
stub_commit_script() {
  local root="$BATS_TEST_TMPDIR/stubbed-plugin" script
  rm -rf "$root"; mkdir -p "$root"
  cp -R "$PLUGIN_ROOT/scripts" "$root/scripts"
  script="$root/scripts/commit-memory.sh"
  STUB="$1" awk '{ print } /^source "\$PLUGIN_ROOT\/scripts\/lib\/resolve.sh"/ { print ENVIRON["STUB"] }' "$script" > "$script.new"
  mv "$script.new" "$script"
  grep -qF "$(printf '%s' "$1" | head -1)" "$script"
  COMMIT_SCRIPT="$script"
  export COMMIT_SCRIPT
}

# commit_sections <message>: commit_with over the summary built from the dirty
# stores under ./memory.
commit_sections() {
  commit_with "$(sectioned_summary "$1")"
}

# index_change_is_root <tier>...: succeed when a changed MEMORY.md line in
# ./memory points at a path outside every tier prefix.
index_change_is_root() {
  local ptr tier under
  while IFS= read -r ptr; do
    under=0
    for tier in "$@"; do
      case "$ptr" in "$tier"/*) under=1 ;; esac
    done
    [ "$under" = 1 ] || return 0
  done < <(git -C memory diff HEAD -U0 -- MEMORY.md | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ' | grep -oE '\]\([^)]*\)' | sed -e 's/^](//' -e 's/)$//')
  return 1
}

# sectioned_summary <message>: print the summary commit_sections sends.
sectioned_summary() {
  local msg="$1" mem=memory tier line path root_dirty=0 out=""
  if [ -e "$mem/.git" ]; then
    local tiers=()
    if [ -f "$mem/.gitmodules" ]; then
      while IFS= read -r -d '' rec; do
        tiers+=("${rec#*$'\n'}")
      done < <(git config --file "$mem/.gitmodules" -z --get-regexp '^submodule\..*\.path$')
    fi
    for tier in "${tiers[@]+"${tiers[@]}"}"; do
      [ -e "$mem/$tier/.git" ] || continue
      if [ -n "$(git -C "$mem/$tier" status --porcelain)" ]; then
        out+="== $tier =="$'\n'"$msg"$'\n'
      fi
    done
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      path="${line:3}"
      local is_tier=0
      for tier in "${tiers[@]+"${tiers[@]}"}"; do
        [ "$path" = "$tier" ] && is_tier=1
      done
      # A tier-only change takes no section: the gitlink moving, and MEMORY.md
      # lines under a tier prefix. A bare-path line there is root content.
      [ "$path" = MEMORY.md ] && ! index_change_is_root "${tiers[@]+"${tiers[@]}"}" && is_tier=1
      [ "$is_tier" = 1 ] || root_dirty=1
    done < <(git -C "$mem" status --porcelain)
  else
    root_dirty=1
  fi
  # A call that finds nothing dirty still carries one section: an empty summary
  # is refused before any store is read, and any other exits 0 on clean stores.
  if [ "$root_dirty" = 1 ] || [ -z "$out" ]; then
    out+="== memory =="$'\n'"$msg"$'\n'
  fi
  printf '%s' "$out"
}

# claude_files: the files under ./.claude, sorted. The script keeps no state
# there, so a run leaves this listing as it found it.
claude_files() {
  if [ -d .claude ]; then find .claude -type f | sort; fi
}

# merge_gate: the entry point that reconciles each store's branch with its
# local `live` (fast-forward, else a prepared merge). The commit path never
# prepares or takes a merge (it fast-forwards `live` or reports), so the suites
# that meet a diverged store drive /gitlore:merge's script.
merge_gate() {
  wire_memory_origin
  bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
}

# resolve_gate: the standalone resolver, for the suites that are about resolve
# itself (recovery, composition) rather than about reaching a merge.
resolve_gate() {
  bash "$PLUGIN_ROOT/scripts/resolve.sh"
}

# wire_memory_origin: give memory a bare origin that already holds its local
# `live`, unless it has one that does. /gitlore:merge fetches before it
# reconciles, and the fixtures' placeholder origin has no `live` to fetch.
wire_memory_origin() {
  local bare="$TMP_REPO/.memory-remote.git"
  if git -C memory ls-remote --exit-code origin live >/dev/null 2>&1; then
    return 0
  fi
  [ -d "$bare" ] || git init -q --bare "$bare"
  git -C memory remote remove origin || true
  git -C memory remote add origin "$bare"
  git -C memory push -q origin live
}
