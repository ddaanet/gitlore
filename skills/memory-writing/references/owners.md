# Owners and overriding a skill

Open this once a candidate owner is in view (Q2 of the hub) or a fact is written to override an installed skill.

   - **A skill.** The body reduces to "when using \<skill\>, do X". Delete it
     and let the skill say X; if X is missing from the skill, fix the skill.
   - **A design doc.** A `project` memory logging decisions, supersessions and
     dated status. The living design doc is the memory of the design.
   - **The code.** A rule about how one call site must behave belongs in a
     comment there, read by whoever edits that line.
   - **CLAUDE.md.** A convention binding on all work in one repo, or a shared
     tier's always-loaded conventions file. Those load whole every session —
     exactly the scope such a rule wants, and the wrong scope for a fact that
     should be *found* on meeting a symptom.
   - **A hook or tool that prints the diagnosis when it fires.** Runtime output
     is an owner too, and the better teacher: it arrives with the offending
     input named, at the moment of the failure, and costs nothing on every
     unrelated session. A memory restating what a hook's own stderr already
     says reaches the reader later and says it worse.
   - **A sibling project's skill body or agent definition**, not only its name
     and description. A fix at an owner my human partner owns is preferred to
     a note; a brief in the owning repo's `inbox/` is a destination in its own
     right. Read the inventory (`owned-projects.md` in each mounted tier) here;
     an owner it does not list is asked about at the commit review and recorded
     in the same change
     ([owner-inventory.md](owner-inventory.md)).

A fact written to override an installed skill sits on that skill's own topic,
so a coverage scan flags it as owned. Check which way the claim points before
counting an owner.
