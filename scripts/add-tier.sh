#!/usr/bin/env bash
# Mount (or create then mount) a memory tier: a submodule inside the memory
# submodule. D17 slice 3-iii, the doer behind `/gitlore:add-tier`.
#
# Reads the intent from the add-tier IPC file so the agent never runs git — the
# same route as the FR11 commit path, and doubly necessary here because mounting
# CLONES and the agent's command sandbox has no network.
#
# Activates the tier as its own final step — appends it to
# memory/.gitlore-tiers, lowest precedence (bottom of the file). The intent
# already named this exact tier, so there is no half-formed-tier ambiguity left
# for a second, separate deliberate edit to resolve (unlike SessionStart's
# passive discovery-by-enclosure, which must never assume a submodule's mere
# presence means it should be active). Reordering afterward, or listing a tier
# mounted by hand, stays a plain manual edit to the file.
#
# It also makes no commit inside the memory store: gitlore_tier_paths reads
# memory/.gitmodules from the WORKING TREE, so a staged `submodule add` is
# already discoverable and the FR11 gate stays the sole committer — the
# manifest write is the same kind of working-tree-only edit.
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# gitlore_get_frontmatter_description, to echo the tier's routing guidance back.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

die() { printf 'gitlore: add-tier failed — %s\n' "$1" >&2; exit 1; }

# Refuse any url that is not a plain transport or a local path.
#
# Not a shell-injection guard — the url is a quoted argument after `--`, never
# interpolated. It bounds which git TRANSPORT the url can select. Git's own
# `protocol.ext.allow` already defaults to `never` (2.47.3: `fatal: transport
# 'ext' not allowed`), so `ext::sh -c …` is dead out of the box; this makes that
# independent of the user's git config, and closes the same class for any other
# `helper::address` transport.
#
# It matters here more than in an ordinary script because this runs from a HOOK,
# outside the agent's command sandbox and with network. A url the agent hands us
# would otherwise reach further than one the agent could use itself, which is
# exactly the escalation the sandbox exists to prevent.
check_url() {
  local url="$1" head rest
  case "$url" in
    "")   die "empty url." ;;
    -*)   die "url '$url' starts with '-'; git would read it as an option." ;;
    /*|./*|../*) return 0 ;;                     # local path
  esac
  case "$url" in
    *:*) head="${url%%:*}"; rest="${url#*:}" ;;
    *)   die "url '$url' is neither a path nor a remote; use https://, ssh://, git@host:path, or an absolute path." ;;
  esac
  case "$rest" in
    //*)
      head=$(printf '%s' "$head" | tr '[:upper:]' '[:lower:]')
      case "$head" in
        http|https|ssh|git|file) return 0 ;;
        *) die "url scheme '$head' is not allowed; use https, ssh, git, or file." ;;
      esac ;;
    :*)
      # `helper::address` — git's remote-helper form, of which `ext::` runs a
      # shell command. Never needed to reach a tier remote.
      die "url '$url' selects the git transport helper '$head'; that form is not allowed." ;;
    *)
      # scp-like [user@]host:path — a host has no slash and no whitespace.
      case "$head" in
        ""|*[/[:space:]]*) die "url '$url' is not a usable remote." ;;
        *) return 0 ;;
      esac ;;
  esac
}

gitlore_has_submodule || die "this repo has no gitlore memory submodule; run /gitlore:install first."
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || die "the memory submodule is not checked out here."

intent=$(gitlore_add_tier_file "$mempath")
[ -f "$intent" ] || die "no add-tier intent file at $intent."

# ---------------------------------------------------------------- parse intent
# `key=value`, value is the REST OF THE LINE verbatim — a description carries
# spaces by construction and a url may. Only the line's outer whitespace is
# trimmed. Unknown keys are an error, not a silent drop: a typo'd `descripton=`
# would otherwise seed a tier with no routing guidance at all.
mode="" name="" url="" description=""
lineno=0
while IFS= read -r line || [ -n "$line" ]; do
  lineno=$((lineno + 1))
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] || continue
  case "$line" in \#*) continue ;; esac
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
done < "$intent"

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
    rm -rf "$seed"
    die "could not push the seeded tier to $url. git said: $push_err"
  fi
  if ! push_err=$(git -C "$seed" push -q origin live 2>&1); then
    rm -rf "$seed"
    die "pushed main but not live to $url. git said: $push_err"
  fi
  rm -rf "$seed"
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
printf '%s\n' "$name" >> "$mempath/.gitlore-tiers"
printf 'gitlore: activated — appended to %s/.gitlore-tiers (lowest precedence; reorder the file by hand to change that).\n' \
  "$mempath"
exit 0
