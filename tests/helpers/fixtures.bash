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

  local template old_root new_root f
  template="$(_gitlore_ensure_parent_with_memory_template)" || return 1
  old_root="$(cd "$template" && pwd -P)"
  new_root="$(pwd -P)"

  cp -a "$template/." "$TMP_REPO/" \
    || { echo "make_parent_with_memory: failed to copy the fixture template" >&2; return 1; }

  # The template's own absolute path is baked into whichever of these ended
  # up storing it (git's relative-vs-absolute submodule URL resolution isn't
  # worth relying on from memory); rewrite unconditionally, it's a no-op on
  # a file that doesn't contain it.
  for f in .gitmodules .git/config .git/modules/gitlore-memory/config "$subpath/.git"; do
    [ -f "$TMP_REPO/$f" ] || continue
    _gitlore_sed_replace_path "$old_root" "$new_root" "$TMP_REPO/$f"
  done

  git submodule status >/dev/null \
    || { echo "make_parent_with_memory: template copy broke submodule status" >&2; return 1; }
  git -C "$subpath" rev-parse HEAD >/dev/null \
    || { echo "make_parent_with_memory: template copy broke the memory submodule's HEAD" >&2; return 1; }
}

# Literal path substitution in $3 (not a general regex tool — old and new are
# both plain filesystem paths). Escapes sed's regex/replacement metacharacters
# so a path segment like a dot or an ampersand can't corrupt the match.
# Temp file + mv rather than `sed -i`: BSD sed takes the backup extension as a
# separate argument and GNU sed attached, so no -i spelling runs on both.
_gitlore_sed_replace_path() {
  local old="$1" new="$2" file="$3" old_esc new_esc
  old_esc="$(printf '%s' "$old" | sed -e 's/[.[\*^$\/&]/\\&/g')"
  new_esc="$(printf '%s' "$new" | sed -e 's/[\/&]/\\&/g')"
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
