## Brief: second sighting of the launcher-shim path issue, and two points on the proposed fix

2026-10-14

Addendum to `inbox/brief-launcher-memory-path-containment.md` (2026-10-13).
Read that first; it holds the attack shape, exposure and constraints. Nothing
here replaces it.

### What happened

A background security review flagged `.gitlore/bin/claude` again, in
micro-craft (`ddaanet/micro-craft`), right after `/gitlore:install` and
`/gitlore:add-tier` ran there with gitlore 0.9.0. Finding: [MEDIUM] path
traversal at `mempath=$(git config --file "$root/.gitmodules"
submodule.gitlore-memory.path)`, with `$root/$mempath` injected as
`autoMemoryDirectory`. Same line, same cause as the earlier brief: this is a
second independent report, not a new bug. No change was made in micro-craft.

### Correction to a first-pass dismissal

The micro-craft session first judged the finding non-exploitable: the
`.gitmodules` that supplies the path lives in the same repo as the per-repo
shim, and the shim only reaches `PATH` through `.envrc` (`direnv allow`). That
holds for the per-repo copy only. It does not hold for the global shim
(`scripts/install/global-shim.sh`), where the script is user-installed and the
repo contributes only `.gitmodules` and `.claude/settings.json`. The earlier
brief's exposure section is right. Do not close the issue on the per-repo
argument.

### Two points on the fix

The reviewer's suggested fix was:

```sh
case "$mempath" in /*|*..*) exec "$real" "$@";; esac
memabs=$(cd "$root/$mempath" 2>/dev/null && pwd -P) || exec "$real" "$@"
rootabs=$(cd "$root" && pwd -P)
case "$memabs" in "$rootabs"/*) ;; *) exec "$real" "$@";; esac
json=$(jq -nc --arg p "$memabs" '{autoMemoryDirectory:$p}')
```

- The `*..*` glob rejects any path containing two dots, such as a directory
  named `my..memory`. The canonicalize-then-prefix check already covers
  traversal and symlinks, so the glob adds false positives and no protection.
  Keep `/*` only if absolute paths are to be refused outright.
- `cd "$root/$mempath" ... || exec "$real" "$@"` also passes through when the
  submodule directory does not exist yet, as in a fresh clone before
  `git submodule update --init`. Today the shim injects the path anyway. That
  is a behaviour change, so decide it on purpose: it silently disables the
  redirect until the submodule is initialised.

### Unrelated observation

`root` is empty outside a repo, so the shim reads `/.gitmodules` before the
`[ -z "$root" ]` check. Verified harmless: `git config --file` on a missing
file exits 1 with no output. Moving the `-z "$root"` test above the `git
config` call would still make the ordering match the "cheap checks first"
comment.

### Constraints

- Fix `scripts/install/launcher-shim` only, as the earlier brief says. Do not
  patch a consumer's generated `.gitlore/bin/claude`.
