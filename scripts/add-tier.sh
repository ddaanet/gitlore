#!/usr/bin/env bash
# Mount (or create then mount) a memory tier: a submodule inside the memory
# submodule. D17 slice 3-iii, the doer behind `/gitlore:add-tier`.
#
# The intent arrives on stdin from a direct agent call: a quoted heredoc to
# gitlore-add-tier. The agent runs this in its command sandbox, with the url's
# host in allowed_domains (D71), because mounting clones the tier over the
# network. The agent never runs git itself.
#
# Activates the tier as its own final step — appends it to
# memory/.gitlore-tiers, lowest precedence (bottom of the file). The intent
# already named this exact tier, so there is no half-formed-tier ambiguity left
# for a second, separate deliberate edit to resolve (unlike SessionStart's
# passive discovery-by-enclosure, which must never assume a submodule's mere
# presence means it should be active). Reordering afterward, or listing a tier
# mounted by hand, stays a plain manual edit to the file.
#
# Then it composes the root index and reports the size, and commits itself on a
# clean memory store: one canned `== memory ==` commit on live, with the memory
# gitlink staged in the parent. A store with pending work keeps the mount staged
# for the next gitlore:commit. The compose baselines a batch hook took for this
# run are refreshed last, so the hooks do not report the same mount twice.
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture

PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# gitlore_get_frontmatter_description, to echo the tier's routing guidance back.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"
# gitlore_compose_and_report, gitlore_sync_memory_to_live, gitlore_stage_memory_pointer.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
# check_url.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/add-tier-url.sh"

# Temp paths this run owns: the create branch's seed repo and the pre-run copy
# of MEMORY.md. One EXIT trap covers both on every exit, including the die paths.
seed=""
pre_index=""
# shellcheck disable=SC2317  # reached only through the EXIT trap set below
cleanup() {
  [ -z "$seed" ] || rm -rf "$seed"
  [ -z "$pre_index" ] || rm -f "$pre_index"
}
trap cleanup EXIT

die() { printf 'gitlore: add-tier failed — %s\n' "$1" >&2; exit 1; }
no_intent() {
  die "no intent on stdin; pass it through a quoted heredoc: gitlore-add-tier <<'EOF' ... EOF"
}

gitlore_has_submodule || die "this repo has no gitlore memory submodule; run /gitlore:install first."
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || die "the memory submodule is not checked out here."

# A terminal on stdin means no intent was piped: refuse rather than block on it.
if [ -t 0 ]; then no_intent; fi

# Before any write: whether the store was clean (a clean store gets the canned
# commit below), and the compose baselines this run must account for.
pending=$(git -C "$mempath" status --porcelain)
pre_stamp=$(gitlore_compose_stamp "$mempath/MEMORY.md" "$mempath/.gitlore-tiers")
pre_index_ok=0
if [ -f "$mempath/MEMORY.md" ]; then
  pre_index=$(mktemp "${TMPDIR:-/tmp}/gitlore-add-tier-index.XXXXXX")
  cp "$mempath/MEMORY.md" "$pre_index"
  pre_index_ok=1
fi

# ---------------------------------------------------------------- parse intent
# `key=value`, value is the REST OF THE LINE verbatim — a description carries
# spaces by construction and a url may. Only the line's outer whitespace is
# trimmed. Unknown keys are an error, not a silent drop: a typo'd `descripton=`
# would otherwise seed a tier with no routing guidance at all.
mode="" name="" url="" description=""
lineno=0 seen=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] || continue
  case "$line" in \#*) continue ;; esac
  seen=1
  case "$line" in
    *=*) key="${line%%=*}"; value="${line#*=}" ;;
    *)   die "intent line $lineno is not key=value: $line" ;;
  esac
  key="${key%"${key##*[![:space:]]}"}"
  value="${value#"${value%%[![:space:]]*}"}"
  case "$key" in
    mode)        mode="$value" ;;
    name)        name="$value" ;;
    url)         url="$value" ;;
    description) description="$value" ;;
    *)           die "unknown intent key '$key' on line $lineno." ;;
  esac
done
[ "$seen" = 1 ] || no_intent

# ------------------------------------------------------------------ validation
case "$mode" in
  mount|create) ;;
  "") die "intent has no 'mode='; write mode=mount or mode=create." ;;
  *)  die "unknown mode '$mode'; write mode=mount or mode=create." ;;
esac

[ -n "$name" ] || die "intent has no 'name=' (the directory the tier mounts at, under $mempath/)."
case "$name" in
  */*)  die "tier name '$name' contains a slash; a tier mounts directly under $mempath/." ;;
  .*)   die "tier name '$name' starts with a dot." ;;
esac
# A name with whitespace would mount fine but could never be LISTED: the
# activation manifest is line-oriented and trims its entries. Refuse up front
# rather than produce a tier that composition can never activate.
case "$name" in
  *[[:space:]]*) die "tier name '$name' contains whitespace; the activation manifest could never list it." ;;
esac

[ ! -e "$mempath/$name" ] || die "$mempath/$name already exists."
while IFS= read -r existing; do
  if [ "$existing" = "$name" ]; then die "'$name' is already a mounted tier."; fi
done < <(gitlore_tier_paths "$mempath")

if [ "$mode" = "mount" ]; then
  [ -n "$url" ] || die "mount needs a 'url=' for the existing tier remote."
  check_url "$url"
else
  [ -n "$description" ] || \
    die "create needs a 'description=' — it becomes the tier's routing guidance, which is how every consumer learns what belongs in it."
fi

# --------------------------------------------------------------- create branch
# Seed the tier's content and its remote BEFORE mounting, so the mount below is
# the identical code path in both modes.
#
# created_visibility is "private" once this script has made the remote with
# `gh repo create --private`; empty otherwise, where the remote's visibility is
# not ours to know.
created_visibility=""
if [ "$mode" = "create" ]; then
  # A url supplied for create is pushed to before anything is mounted, so it is
  # checked here as well as at the mount below.
  if [ -n "$url" ]; then check_url "$url"; fi
  if [ -z "$url" ]; then
    command -v gh >/dev/null 2>&1 || \
      die "create without a 'url=' needs the gh CLI to make the remote. Install gh, or create the repo yourself and re-run with url=."
    gh auth status >/dev/null 2>&1 || \
      die "create without a 'url=' needs gh to be authenticated (gh auth login), or create the repo yourself and re-run with url=."
    owner=$(gh api user -q .login) || die "could not determine the gh account to create the tier remote under."
    full_name="${owner}/${name}-memory"
    gh repo create "$full_name" --private || die "gh repo create $full_name failed."
    url=$(gh repo view "$full_name" --json sshUrl -q .sshUrl) || url=""
    [ -n "$url" ] || die "created $full_name but could not resolve its URL."
    created_visibility="private"
  fi

  seed=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-tier-seed.XXXXXX")
  # `-b main`: the tier remote's default branch MUST stay `main` with `live`
  # alongside. A `live` default gets checked out AS A BRANCH by the mount, and
  # the ff-only `fetch origin live:live` then refuses to update a checked-out
  # branch — propagation-in would die at the first hop.
  git init -q -b main "$seed"
  # jq quotes the description into a JSON string, which is a valid YAML double-
  # quoted scalar. Interpolating it raw truncates the frontmatter at the first
  # `"` the agent supplied — `Facts about the "core" team` reads back as garbage
  # — and a trailing backslash would eat the closing quote outright. Same
  # treatment gitlore_set_frontmatter_description already gives an edit.
  desc_quoted=$(jq -Rn --arg d "$description" '$d')
  {
    printf -- '---\ndescription: %s\n---\n\n' "$desc_quoted"
    printf '# %s tier index\n\n' "$name"
    printf 'One line per fact, same format as a project index. Facts here travel\n'
    printf 'to every repo that mounts this tier.\n'
  } > "$seed/MEMORY.md"
  git -C "$seed" add MEMORY.md
  git -C "$seed" commit -q -m "Seed $name tier index"
  git -C "$seed" branch live
  git -C "$seed" remote add origin "$url"
  # main first so the remote's default branch settles on it, live second.
  if ! push_err=$(git -C "$seed" push -q -u origin main 2>&1); then
    die "could not push the seeded tier to $url. git said: $push_err"
  fi
  if ! push_err=$(git -C "$seed" push -q origin live 2>&1); then
    die "pushed main but not live to $url. git said: $push_err"
  fi
  rm -rf "$seed"
  seed=""
fi

# ---------------------------------------------------------------- mount branch
# --name pins the submodule's registered name to the mount path, so discovery by
# enclosure and the manifest agree on one identifier. Re-check the url: in create
# mode it may have been derived from gh since the check above.
check_url "$url"
if ! add_err=$(git -C "$mempath" submodule add --name "$name" -- "$url" "$name" 2>&1); then
  die "submodule add failed for $url. git said: $add_err"
fi

tierpath="$mempath/$name"
# Guard the submodule escape: without this, a failed add would leave `git -C`
# operating on the memory store itself.
[ -e "$tierpath/.git" ] || die "submodule add reported success but $tierpath is not a checkout."

# `submodule add` recorded $url as given: the tier's own remote keeps it, so
# pushes stay on the transport the person chose. The tracked entry takes the
# https form, which a clone fetches with no GitHub SSH key. The rewrite dirties
# the .gitmodules `submodule add` staged, so it is staged again.
https_url=$(gitlore_github_https_url "$url")
if [ "$https_url" != "$url" ]; then
  git config --file "$mempath/.gitmodules" "submodule.${name}.url" "$https_url" || \
    die "could not record the https url for tier '$name' in $mempath/.gitmodules."
  git -C "$mempath" add -- .gitmodules || \
    die "could not stage $mempath/.gitmodules after recording the https url for tier '$name'."
fi
gitlore_warn_private_under_public "tier remote" "$url" "$created_visibility"

warnings=""
# Propagation-in: create the local `live` from the remote. Fast-forward-only for
# free — a refspec fetch into a branch ref refuses a non-ff without `+`.
if ! fetch_err=$(git -C "$tierpath" fetch origin "live:live" 2>&1); then
  case "$fetch_err" in
    *"couldn't find remote ref"*|*"does not appear to be"*)
      warnings="$warnings
  - the remote has no 'live' branch. gitlore's tiers are detached at 'live'; push one to $url (main and live together, main default) before this tier can carry facts." ;;
    *)
      warnings="$warnings
  - could not fetch 'live' from the tier remote. git said: $fetch_err" ;;
  esac
fi

if git -C "$tierpath" show-ref --verify --quiet refs/heads/live; then
  if ! co_err=$(git -C "$tierpath" checkout -q --detach live 2>&1); then
    warnings="$warnings
  - could not detach the tier at 'live'. git said: $co_err"
  # Stage the gitlink that detach just moved. `submodule add` recorded the
  # remote's DEFAULT branch and `submodule update` pins from the memory store's
  # INDEX (D43), so an unstaged move is walked back to that branch at the next
  # SessionStart while the root index composed from the live carrier survives to
  # describe facts the tier no longer holds. The mount advances a tier, so it
  # owes the same hand-off every other advancing path performs — and until it
  # does, the composition that follows this mount refuses the tier as moved off
  # its pin.
  elif ! stage_err=$(git -C "$mempath" add -- "$name" 2>&1); then
    warnings="$warnings
  - the tier is detached at 'live' but its pointer could not be staged in the memory store, so the next session will reset it to the remote's default branch. Run: git -C \"$mempath\" add -- \"$name\". git said: $stage_err"
  fi
else
  warnings="$warnings
  - the tier is left on its default branch, not detached at 'live'."
fi

desc=""
if [ -f "$tierpath/MEMORY.md" ]; then
  desc=$(gitlore_get_frontmatter_description "$tierpath/MEMORY.md") || desc=""
fi
if [ -z "$desc" ]; then
  warnings="$warnings
  - the tier's MEMORY.md carries no frontmatter 'description:', so it advertises no routing guidance. Add one in $tierpath/MEMORY.md."
fi

printf 'gitlore: tier "%s" mounted at %s (%s).\n' "$name" "$tierpath" "$url"
if [ -n "$desc" ]; then
  printf 'gitlore: it describes itself as: %s\n' "$desc"
fi

# A tier may carry `shared-claude.md`: cross-repo conventions that must act
# without being looked up, so they belong in always-on context rather than
# behind an index pointer. Nothing loads it until the consuming repo imports it,
# and a dangling `@` import is silent — so only report the line once the file is
# actually there. The import path is $tierpath, which is already repo-root
# relative, and the check for an existing import keeps a re-run quiet.
if [ -f "$tierpath/shared-claude.md" ] &&
   ! { [ -f CLAUDE.md ] && grep -qF "@$tierpath/shared-claude.md" CLAUDE.md; }; then
  printf 'gitlore: the tier carries always-on conventions. Append to CLAUDE.md, as its final line:\n'
  printf 'gitlore:   @%s/shared-claude.md\n' "$tierpath"
  printf 'gitlore: then read that file and delete from CLAUDE.md every rule it already states.\n'
fi
if [ -n "$warnings" ]; then
  printf 'gitlore: mounted with warnings:%s\n' "$warnings"
fi

# Activate as the final mechanical step. The intent that named this exact tier
# is already unambiguous — unlike SessionStart's passive discovery-by-enclosure
# (which must not assume presence implies activation, since a stray or
# manually-added submodule could exist for unrelated reasons), this run only
# happens because the agent explicitly asked to add THIS tier. Appended at the
# bottom (lowest precedence, file order top-to-bottom): the least surprising
# default, since it never outranks a tier this repo already trusted. Reordering
# afterward is a plain edit to $mempath/.gitlore-tiers, same as before.
manifest="$mempath/.gitlore-tiers"
# The manifest is documented as hand-editable (final message below), so a hand
# edit, an agent Edit, or any writer that leaves the last line bare must not
# have this append weld onto it — same guard gitlore_compose_write and
# gitlore_index_merge already carry, separator-only, never normalisation.
if [ -s "$manifest" ] && [ "$(tail -c 1 "$manifest" | wc -l | tr -d ' ')" = 0 ]; then
  printf '\n' >> "$manifest"
fi
printf '%s\n' "$name" >> "$manifest"
printf 'gitlore: activated — appended to %s/.gitlore-tiers (lowest precedence; reorder the file by hand to change that).\n' \
  "$mempath"

# Compose the root index over the new active set. Measured after the compose,
# so the size is the file the session will load.
gitlore_compose_and_report "$mempath" 1
if [ -n "$GITLORE_COMPOSE_SYSMSG" ]; then printf '%s\n' "$GITLORE_COMPOSE_SYSMSG"; fi
if [ -n "$GITLORE_COMPOSE_CTX" ]; then printf '%s\n' "$GITLORE_COMPOSE_CTX"; fi
size_line=$(gitlore_index_mount_size_line "$mempath/MEMORY.md") || size_line=""
if [ -n "$size_line" ]; then printf '%s\n' "$size_line"; fi

# Commit on a clean store, as the one canned commit the mount owes: the mount
# message, the tier's routing description, then the memory gitlink staged in the
# parent. A store with pending work keeps the mount staged for its own commit.
if [ -z "$pending" ]; then
  if [ "$mode" = "create" ]; then
    head_line="create $name tier at $url"
  else
    head_line="mount $name tier from $url"
  fi
  summary="== memory ==
$head_line"
  if [ -n "$desc" ]; then summary="$summary

$desc"; fi
  gitlore_sync_memory_to_live "$mempath" "$summary" || \
    die "the mount is staged, but its commit was refused. See the message above."
  gitlore_stage_memory_pointer "$mempath"
else
  git -C "$mempath" add -- .gitlore-tiers || \
    die "could not stage $manifest after the mount."
  printf 'gitlore: the memory store held uncommitted work before this mount, so the mount is left staged for the next gitlore:commit.\n'
fi

# Refresh the compose baselines this run's batch took, keyed by an agent id this
# script cannot see. The PostToolBatch hooks would otherwise report the mount a
# second time. A baseline equal to the pre-run state was taken by the batch
# running this call, so it is moved to the post-run state: that stops the second
# report, and still catches that agent's later edits. A differing baseline
# belongs to another batch and is left alone. Only existing files are rewritten:
# none is created or deleted.
gitdir=$(git -C "$mempath" rev-parse --absolute-git-dir)
post_stamp=$(gitlore_compose_stamp "$mempath/MEMORY.md" "$mempath/.gitlore-tiers")
# The unmatched-glob case: a pattern with no file stays literal and fails -f.
for f in "$gitdir/gitlore-compose-stamp" "$gitdir/gitlore-compose-stamp-"*; do
  [ -f "$f" ] || continue
  if printf '%s\n' "$pre_stamp" | cmp -s - "$f"; then
    printf '%s\n' "$post_stamp" > "$f"
  fi
done
if [ "$pre_index_ok" = 1 ] && [ -f "$mempath/MEMORY.md" ]; then
  for f in "$gitdir/gitlore-index-preimage" "$gitdir/gitlore-index-preimage-"*; do
    [ -f "$f" ] || continue
    if cmp -s "$pre_index" "$f"; then
      cp "$mempath/MEMORY.md" "$f"
    fi
  done
fi
exit 0
