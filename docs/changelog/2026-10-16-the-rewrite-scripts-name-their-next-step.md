# 2026-10-16 — The rewrite scripts name their remote and their next step

**A record-rewrite message names the remote it used.** The no-op message and the
unreadable-version and unreadable-map refusals of `scripts/record-rewrite.sh`
name `$remote`: the URL when the third argument is one, `origin` by default.

**A crossing refusal says what resolves it.** `scripts/cross-rewrite.sh`
refusals the reader can act on end in the act: a store or child that is not
checked out prints the `git submodule update --init` command for it; a fetch
failure says to run again once the remote is reachable; a remote with no record
prints the `record-rewrite.sh` command that publishes it; a record that cannot
be read, a chain that does not end, a mapped commit the clone lacks, trees
differing outside gitlinks and a gitlink the child's record maps elsewhere print
the rebuild of the record. The rebuild needs the rewrite's commit-map, which
only the rewritten mirror holds as `filter-repo/commit-map`; with `MIRROR` set
to it, the refusal prints the `git push --delete` that drops the damaged record
and the `record-rewrite.sh` run that records the map. A version that is an
integer above 1 says to update gitlore, and any other version is a damaged
record. A dropped commit prints the move of the ref to the remote's tip, and the
`git log` that lists local work to replay first. A commit on neither the
remote's history nor a recorded commit prints the `git log` that compares it
with the remote and says a person decides. The checkout command runs from the
repository holding the gitlink: the memory store for a tier, the project for the
memory store. A git that cannot report the object format fails with its own
message.

**A child's record is fetched once per run.** The script keeps each mounted
child's map by path, so the gitlink checks of every ref and the children scan
share one fetch.

**The record's id length follows the store's object format.** Both scripts read
`git rev-parse --show-object-format`: ids are 40 hex digits in a sha1 store and
64 in a sha256 one, and a dropped commit maps to zeros of that length. A
mismatched line is refused. The record version stays `1`; the length belongs to
the store, not to the record.
