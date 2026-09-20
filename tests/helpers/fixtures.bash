#!/usr/bin/env bash
# Factories for common test fixtures.

# Create a parent repo with a memory submodule pointing at a local bare repo.
# Args: $1 = memory subpath (default "memory")
#
# Every call site in the suite uses the default subpath, and the fixture's
# content never varies, so the ~13-git-subprocess build below runs once per
# `bats` invocation (cached under BATS_RUN_TMPDIR — the same directory
# bats-core itself uses for cross-file --jobs coordination, see
# /usr/lib/bats-core/semaphore.bash) and every call just copies it. A
# non-default subpath falls back to the original build-from-scratch path,
# since the template can't serve it.
make_parent_with_memory() {
  cd "$TMP_REPO" || return 1
  local subpath="${1:-memory}"

  if [ "$subpath" != "memory" ]; then
    _gitlore_build_parent_with_memory "$TMP_REPO" "$subpath"
    return
  fi

  local template old_root new_root f old_esc new_esc
  template="$(_gitlore_ensure_parent_with_memory_template)" || return 1
  old_root="$(cd "$template" && pwd -P)"
  new_root="$(pwd -P)"

  cp -a "$template/." "$TMP_REPO/" \
    || { echo "make_parent_with_memory: failed to copy the fixture template" >&2; return 1; }

  # Escaped once per call: every candidate file below shares the same
  # old/new pair.
  _gitlore_escape_sed_pattern "$old_root"; old_esc="$reply"
  _gitlore_escape_sed_replacement "$new_root"; new_esc="$reply"

  # The template's own absolute path is baked into whichever of these ended
  # up storing it (git's relative-vs-absolute submodule URL resolution isn't
  # worth relying on from memory); every candidate is offered, and one that
  # doesn't contain it is left alone.
  for f in .gitmodules .git/config .git/modules/gitlore-memory/config "$subpath/.git"; do
    [ -f "$TMP_REPO/$f" ] || continue
    _gitlore_sed_replace_path "$old_root" "$old_esc" "$new_esc" "$TMP_REPO/$f"
  done

  # What the copy can get wrong is the race the template builder guards
  # against: `$subpath` present but empty. `rev-parse HEAD` alone does not
  # catch that — with no `.git` file inside it, `git -C "$subpath"` walks up
  # and resolves the *parent* repo's HEAD. The gitlink file is the signal: a
  # real submodule checkout always has a non-empty `$subpath/.git`. Not
  # `git submodule status`: it exits 0 for a clean, an out-of-sync and an
  # uninitialized submodule alike.
  [ -s "$TMP_REPO/$subpath/.git" ] \
    || { echo "make_parent_with_memory: template copy left $subpath without a submodule gitlink" >&2; return 1; }
  git -C "$subpath" rev-parse HEAD >/dev/null \
    || { echo "make_parent_with_memory: template copy broke the memory submodule's HEAD" >&2; return 1; }
}

# Escapes for use as the *search* side of `_gitlore_sed_replace_path`'s sed
# expression (a literal path, not a general regex tool). Sets $reply rather
# than echoing: a command substitution forks even around a builtin, and a
# fork is what this path is counted in.
# Backslash first, then the rest of what's special in sed's own regex syntax.
_gitlore_escape_sed_pattern() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//./\\.}"
  s="${s//\[/\\[}"
  s="${s//\*/\\*}"
  s="${s//^/\\^}"
  s="${s//\$/\\$}"
  s="${s//\//\\/}"
  s="${s//&/\\&}"
  reply="$s"
}

# Escapes for the *replacement* side: only backslash, `/` and `&` are special
# there. See _gitlore_escape_sed_pattern for the $reply convention.
_gitlore_escape_sed_replacement() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\//\\/}"
  s="${s//&/\\&}"
  reply="$s"
}

# Literal path substitution in $file (not a general regex tool — old is a
# plain filesystem path). $old_esc/$new_esc are old/new already escaped by
# the caller. A file that doesn't carry $old is left alone without forking
# `sed` and `mv` — the submodule's gitlink, which git writes as a relative
# path. `$(<file)` rather than `cat`: no exec.
# Temp file + mv rather than `sed -i`: BSD sed takes the backup extension as a
# separate argument and GNU sed attached, so no -i spelling runs on both.
_gitlore_sed_replace_path() {
  local old="$1" old_esc="$2" new_esc="$3" file="$4" content
  content="$(<"$file")"
  case "$content" in
    *"$old"*) ;;
    *) return 0 ;;
  esac
  sed "s/${old_esc}/${new_esc}/g" "$file" > "$file.tmp" && mv -f "$file.tmp" "$file"
}

_gitlore_fixture_cache_dir() {
  printf '%s\n' "${BATS_RUN_TMPDIR:-${TMPDIR:-/tmp}}/gitlore-fixture-cache"
}

# Build the parent+memory-submodule template at most once per `bats` run.
# Racing callers coordinate through an atomic `mkdir` lock (mirroring
# bats-core's own semaphore pattern) and a `.ready` marker; a caller that
# loses the race waits for `.ready` rather than rebuilding, bounded so a
# crashed builder can't hang the suite — it retries the lock instead.
_gitlore_ensure_parent_with_memory_template() {
  local cache_dir template lock ready tries=0
  cache_dir="$(_gitlore_fixture_cache_dir)"
  template="$cache_dir/parent-with-memory"
  ready="$template.ready"
  lock="$template.building"

  mkdir -p "$cache_dir"

  while [ ! -f "$ready" ]; do
    if mkdir "$lock" 2>/dev/null; then
      # Re-check under the lock. The winner can publish `$ready` and release
      # the lock in the window between this loop's check and the `mkdir` above,
      # and a loser that then rebuilds is destructive: the builder's first act
      # is `rm -rf "$template"`, which deletes the template out from under every
      # caller mid-`cp -a`. `$ready` is a sibling path, so it survives that `rm`
      # and keeps handing the half-built tree to everyone else for the whole
      # rebuild — a copy that then silently lacks `memory/`.
      if [ -f "$ready" ]; then
        rmdir "$lock"
        break
      fi
      if _gitlore_build_parent_with_memory "$template" memory; then
        touch "$ready"
      else
        echo "make_parent_with_memory: failed to build the fixture template" >&2
      fi
      rmdir "$lock"
      break
    fi
    tries=$((tries + 1))
    [ "$tries" -lt 200 ] \
      || { echo "make_parent_with_memory: timed out waiting for the fixture template" >&2; return 1; }
    sleep 0.05
  done

  [ -f "$ready" ] || return 1
  printf '%s\n' "$template"
}

# The original from-scratch build, parameterized over where it runs. Used
# directly for a non-default subpath, and to build the cached template.
_gitlore_build_parent_with_memory() {
  local repo="$1" subpath="$2"
  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name  "Test"

    local bare="$repo/.bare-memory.git"
    # Seed the bare repo via a temporary clone so it has a valid HEAD.
    local seed_dir
    seed_dir="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-seed.XXXXXX")"
    git init -q -b main "$seed_dir"
    (
      cd "$seed_dir" || exit 1
      git config user.email "test@example.com"
      git config user.name  "Test"
      echo "# memory" > MEMORY.md
      git add MEMORY.md
      git commit -q -m "Initial memory"
    )
    git clone -q --bare "$seed_dir" "$bare"
    rm -rf "$seed_dir"

    git -c protocol.file.allow=always submodule add --name gitlore-memory "$bare" "$subpath" >/dev/null 2>&1
    (
      cd "$subpath" || exit 1
      git config user.email "test@example.com"
      git config user.name  "Test"
      # Branch model (D17): `live` is the only branch, and it is never checked out
      # as a branch — the worktree sits detached at its commit.
      git branch live
      git checkout -q --detach live
    )
    # The memory commit-message IPC file lives in the parent tree under .claude/
    # (relocated 2026-07-16 from the submodule gitdir). Mirror production: create
    # the dir and gitignore the file so an untracked message never pollutes a
    # parent `git add -A`.
    mkdir -p .claude
    printf '/.claude/gitlore-memory-message\n/.claude/gitlore-commit-memory\n' > .gitignore
    git add .gitmodules "$subpath" .gitignore
    git commit -q -m "Add memory submodule"
  )
}

# Locate the one relay file `gitlore_relay_write` staged for agent $2 under
# memory path $1, by glob rather than by predicted name — D51 (revised) names
# each write `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>`, so nothing outside the
# writer's own process can predict a file BEFORE it exists the way the retired
# `gitlore_relay_marker_file` did. Excludes a writer's in-progress `.tmp`.
# Anchored on the whole `-<agent>-<epoch>-<pid>-<tag>` tail rather than on a
# bare `-$agent-*`: epoch and pid are decimal and the tag comes from a closed
# set, so the pattern can only match where $agent occupies the agent field. A
# loose `-$agent-*` would also match an agent id that $agent is a prefix of,
# and a session id that happens to embed "-$agent-". The tail anchor excludes
# a writer's in-progress `<name>.tmp` by construction — it ends in `.tmp`, not
# in a tag.
#
# Exactly one match or a failure: two matches would otherwise be returned as a
# two-line string and fail the caller's `[ -f "$marker" ]` with nothing said
# about why.
relay_marker_for() {
  local mempath="$1" agent="$2" gitdir found n
  gitdir=$(git -C "$mempath" rev-parse --absolute-git-dir) || return 1
  found=$(find "$gitdir" -maxdepth 1 -type f \
    '(' -name "gitlore-relay-*-$agent-[0-9]*-[0-9]*-sync" \
    -o -name "gitlore-relay-*-$agent-[0-9]*-[0-9]*-compose" ')' -print)
  n=$(printf '%s' "$found" | grep -c . || true)
  if [ "$n" -ne 1 ]; then
    printf 'relay_marker_for: %s relay files for agent %s under %s\n' \
      "$n" "$agent" "$gitdir" >&2
    return 1
  fi
  printf '%s\n' "$found"
}
