# 2026-09-13 — The relay is one file per report (D51)

The relay keyed one marker per agent and each reporting hook merged its report
into it. That rests on hooks running one at a time, and they do not: every hook
matching one event runs in parallel ("All matching hooks run in parallel",
code.claude.com/docs/en/hooks). Two `PostToolBatch` hooks staging in one batch
therefore raced on a read-merge-write, and the loser's report was overwritten:
over 200 iterations of two concurrent writes for one agent, 86 lost a report and
2 left a torn marker. The same parallelism doubled the delivery, because both
hooks also carried a drain branch — over the same 200 iterations of two
concurrent drains, 144 relayed the block twice and 51 framed an empty one,
leaving 5 correct.

Two further defects rode the same design. The markers keyed on agent id alone,
so a peer session in the same checkout drained them into a conversation that
never dispatched the agent. And each drain ran only when its own hook's baseline
had fired, which the batch whose `Agent` call returned never does: it changes no
index and leaves no stash and no stamp, so the report it was staged for waited
for an unrelated index edit or for the next `SessionStart`. No test drove the
two hooks concurrently, so all of it was green.

A report is now its own file, `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>` in the
memory gitdir — sanitized session id, sanitized agent id, `date +%s`, the
writing process's pid, and the writer's tag, `sync` or `compose`.
`gitlore_relay_write` never reads or folds an existing file: it builds
`<name>.tmp` and installs it with `mv` inside the gitdir, a same-filesystem
rename, and refuses an occupied name rather than overwriting it, since POSIX
`mv` moves a source *into* an existing directory. Two hooks in one batch write
two files and have nothing shared to race on. The residual is stated in the code
rather than fixed: two writes agreeing on session, agent, tag and wall-clock
second **from one process** collide and the second is refused through that
caller's "could not be staged" line. No caller does that.

`scripts/cc-hooks/relay-drain.sh` is new and is the only consumer. It is its own
`PostToolBatch` hook precisely because a drain living in the two reporting hooks
inherits both of their defects — run twice under parallelism, and gated on a
baseline the dispatching batch never sets. It takes no baseline, so it runs on
every batch of the main thread; a keyed run exits at once, since a subagent only
ever writes toward the next parent-side run. Both reporting hooks lost their
drain branches entirely: they write when keyed and emit when unkeyed.

Keying on session as well as agent is what makes the drain safe in a checkout
with several sessions live. It rests on the D51 probe, which logged a subagent's
hook stdin carrying the **parent's** `session_id` — so the name says which
conversation the report is owed to, and `relay-drain.sh` enumerates
`gitlore-relay-<S>-*` for its own session only. Unique names also retired
claim-by-rename before it was written: a drain cannot remove a file it did not
read, which is all the unlink race needed, and a claimed file a killed claimer
stranded would be worse than the window it closed.

`session-start.sh` drains its own session — `compact` and `resume` keep the
session id and fire no batch — and then sweeps every relay file older than seven
days regardless of session, temps included. The `.tmp` exclusion is a drain rule
and not a sweep rule, which is what makes the sweep the only collector of a temp
whose writer was killed mid-install. A report addressed to a session that ended
is left to that sweep rather than folded into a stranger's session: the
conversation it describes is gone, and the store state it reported on is
re-covered by `SessionStart`'s own structural pass.

Two residuals bound delivery and are stated rather than solved. Between the
drain and the emit the reports live only in the hook's variables and the files
are already gone, so a hook killed in that window loses them — narrowed by
parsing the payload first, which establishes that `jq` works at all. And a
background subagent whose report lands after the parent's last batch of a turn
waits for the parent's next batch or for the next compact or resume; a session
that ends with no further batch loses it to the sweep.

The suites now drive the concurrency the old tests could not see: twenty
concurrent writes for one agent yielding twenty framed blocks with every body
present once, and both reporting hooks running at once over ten iterations with
each report delivered exactly once. The writers are separate `bash -c` processes
rather than backgrounded subshells, because `$$` is shared across a shell's
subshells and `BASHPID` does not exist on bash 3.2 — so only processes reproduce
the guarantee production actually rests on.
