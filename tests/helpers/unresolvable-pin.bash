#!/usr/bin/env bash
# Fixtures and paragraph assertions shared by the unresolvable-pin suites
# (unresolvable_pin.bats, unresolvable_pin_channels.bats): a tier gitlink or a
# parent pin on a commit no repository holds, an ssh stub serving a local bare
# repo, and per-paragraph matchers over the hook JSON in $output.
#
# $stderr and $output are bats' `run` captures; shellcheck cannot see them. The
# fixtures leave $lost, $tier_remote, $memory_remote, $gitlink_before and
# $recording for the @test bodies that load this file.
# shellcheck disable=SC2154,SC2034

# --- assertions ---------------------------------------------------------------

session_start() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
}

# Succeed when ONE paragraph of channel $1 contains every literal after it; one
# starting with `!` must be absent. Reads the hook JSON from $output.
para_fixed() {
  local channel="$1" lits
  shift
  lits=$(jq -nc '$ARGS.positional' --args "$@") || return 1
  jq -e --argjson lits "$lits" "($channel // \"\") | split(\"\\n\\n\") | any(.[]; . as \$p | all(\$lits[]; . as \$l | if (\$l | startswith(\"!\")) then (\$p | contains(\$l[1:]) | not) else (\$p | contains(\$l)) end))" <<<"$output" >/dev/null
}

# Succeed when NO paragraph of channel $1 holds anchor $2 together with any of
# the literals after it (compared without case). Reads the hook JSON from
# $output. The negative form of para_fixed: "some paragraph naming the anchor
# lacks X" is satisfied by the remedy's own paragraph, so a second paragraph
# carrying X slips past it; this fails on any paragraph that holds both.
para_none() {
  local channel="$1" anchor="$2" lits
  shift 2
  lits=$(jq -nc '$ARGS.positional | map(ascii_downcase)' --args "$@") || return 1
  jq -e --arg a "$anchor" --argjson lits "$lits" "($channel // \"\") | split(\"\\n\\n\") | all(.[]; ascii_downcase as \$p | (\$p | contains(\$a | ascii_downcase)) and any(\$lits[]; . as \$l | \$p | contains(\$l)) | not)" <<<"$output" >/dev/null
}

sys_has() { para_fixed .systemMessage "$@" || { printf 'no systemMessage paragraph holds [%s]; systemMessage:\n%s\n' "$*" "$(jq -r '.systemMessage // ""' <<<"$output")" >&2; return 1; }; }
ctx_has() { para_fixed .hookSpecificOutput.additionalContext "$@" || { printf 'no additionalContext paragraph holds [%s]\n' "$*" >&2; return 1; }; }

sys_none() { para_none .systemMessage "$@" || { printf 'a systemMessage paragraph holds [%s]; systemMessage:\n%s\n' "$*" "$(jq -r '.systemMessage // ""' <<<"$output")" >&2; return 1; }; }
ctx_none() { para_none .hookSpecificOutput.additionalContext "$@" || { printf 'an additionalContext paragraph holds [%s]; additionalContext:\n%s\n' "$*" "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$output")" >&2; return 1; }; }

# The whole text a command printed, for the resolver and the commit.
said() { printf '%s\n%s\n' "$output" "$stderr"; }

# --- fixtures -----------------------------------------------------------------

# Serve every ssh fetch from local repository $1, and assert that the module at
# $2 reads its remote back as ssh and can fetch through the stub. The stub
# ignores the host and the command git sends; GIT_SSH_COMMAND is exported
# because the sandbox exports its own, which overrides core.sshCommand. No
# `insteadOf` rewrite: git's own url readers (`remote get-url`) would apply it
# and hand the code under test the local path instead of the ssh form.
serve_ssh_from() {
  local bare="$1" module="$2" stub="$BATS_TEST_TMPDIR/ssh-stub.sh"
  printf '#!/bin/sh\nexec git upload-pack "%s"\n' "$bare" > "$stub"
  chmod +x "$stub"
  export GIT_SSH_COMMAND="$stub"
  case "$(git -C "$module" remote get-url origin)" in
    git@github.com:*|ssh://*) ;;
    *) return 1 ;;
  esac
  [ -n "$(git -C "$module" ls-remote origin refs/heads/live)" ]
}

# A published, composed store whose memory commit on `live` records tier
# ddaanet at a commit that exists in no repository: the shape a raw push in
# memory leaves. Leaves $lost (the commit), $old (the gitlink before) and
# $tier_remote (the tier's origin url).
tier_gitlink_nobody_holds() {
  take_base_store
  gitlink_before=$(git -C memory rev-parse :ddaanet)
  lost=$(unpublished_tier_commit ddaanet)
  tier_remote=$(git -C memory/ddaanet config --get remote.origin.url)
  seed_root_bullet "ddaanet/lost.md" "held by one checkout only"
  # The same memory commit also carries a project fact of root's own.
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet "proj.md" "a project fact"
  git -C memory add proj.md
  # Two more files whose names break a whitespace split: a space, and a newline.
  printf 'x\n' > "memory/proj notes.md"
  printf 'x\n' > "$(printf 'memory/odd\nname.md')"
  git -C memory add "proj notes.md" "$(printf 'odd\nname.md')"
  git -C memory update-index --add --cacheinfo "160000,$lost,ddaanet"
  git -C memory add MEMORY.md
  git -C memory commit -qm "record a tier commit nobody holds"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
  recording=$(git -C memory rev-parse HEAD)
  git -C memory/ddaanet rev-parse -q --verify "${lost}^{commit}" >/dev/null && return 1
  return 0
}

# A memory commit the parent records, that memory's remote does not hold: a
# contributor's pin whose memory was never merged upstream. Leaves $lost and
# $memory_remote.
parent_pin_nobody_holds() {
  wire_memory_remote
  memory_remote=$(git -C memory config --get remote.origin.url)
  local work
  work="$(mktemp -d "$TMP_REPO/mwork.XXXXXX")"
  git clone -q -b live "$memory_remote" "$work"
  (
    cd "$work" || exit 1
    git config user.email other@example.com
    git config user.name Other
    printf 'unmerged\n' > unmerged.md
    git add unmerged.md
    git commit -qm "memory commit nobody merged"
  )
  lost=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"
  git add memory
  git update-index --add --cacheinfo "160000,$lost,memory"
  git commit -qm "record a memory commit nobody merged"
  git -C memory rev-parse -q --verify "${lost}^{commit}" >/dev/null && return 1
  return 0
}
