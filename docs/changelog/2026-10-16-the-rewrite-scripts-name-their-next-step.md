# 2026-10-16 — The rewrite scripts name their remote and their next step

**A record-rewrite message names the remote it used.** The no-op message and the
unreadable-version and unreadable-map refusals of `scripts/record-rewrite.sh`
name `$remote`, the URL when the third argument is one, where they said "origin"
whatever was passed.

**A crossing refusal says what resolves it.** `scripts/cross-rewrite.sh`
refusals the reader can act on end in the act: a store or child that is not
checked out prints the `git submodule update --init` command for it; a fetch
failure says to run again once the remote is reachable; a remote with no record
names `record-rewrite.sh`; an unreadable or malformed record, or a chain that
does not end, sends the reader to the owner of the rewrite to repair
`gitlore/rewrites`; a record of another version says to update gitlore. The
refusals that are diagnoses (a dropped commit, trees differing outside gitlinks,
unrelated history) stay as they are.

**A child's record is fetched once per run.** A mounted tier's record was
fetched once per gitlink per ref and again in the children scan. The script
keeps each child's map by path for the run.

**The record's id length follows the store's object format.** Both scripts read
`git rev-parse --show-object-format`: ids are 40 hex digits in a sha1 store and
64 in a sha256 one, and a dropped commit maps to zeros of that length. A
mismatched line is refused. The record version stays `1`; the length belongs to
the store, not to the record.
