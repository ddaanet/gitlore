Piloting three sandbox-symptom detectors — `.git/index.lock`, phantom
dotfiles, and sandboxed `claude -p` — to decide whether `sandbox-effects`
knowledge moves out of always-loaded memory index lines and into hooks that
fire only when the symptom appears. The plan is
`plans/brief-sandbox-detector-pilot.md`, which carries the decisions, the
rejected homes (`craft`, `prohibitions`), and the three pilot layers. Layer 1,
the corpus replay over `~/.claude/projects`, is the next step and the one whose
numbers decide whether a plugin gets created at all.

A second thread was left mid-flight: a subagent decompiling CC 2.1.258 to
corroborate statically that no hook is dispatched on the `` !`cmd` ``
slash-command expansion path, which a live probe already measured.