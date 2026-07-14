## Current task

D17 (tiered memory) design is revised and captured in `docs/design.md` + memory; the resumable next step is writing implementation plan 1 = authoring-time bidirectional index↔frontmatter sync (Pre/Post `Write|Edit`), per the D17 sequence: sync → one-time reconcile (dogfood here) → structural recompose + first nested tier.

## Open decisions

- Whether to build the authoring-time bidi sync at all, or declare the index one-liner canonical and skip it (frontmatter drift is low-harm — it's the weaker retrieval lever). The reconcile depends on the sync existing first, so this choice gates the whole sequence; decide before planning.
