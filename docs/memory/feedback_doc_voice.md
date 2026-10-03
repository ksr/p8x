---
name: feedback-doc-voice
description: "Ken's project docs read as his own documentation - plain voice, never \"Ken asked/Ken's pick/Claude\"; Claude's part stated once on the home page/README"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 05007751-a1c3-49f6-8fff-5b14d1ceec67
  modified: 2026-10-03T03:01:59.506Z
---

Documentation I write in Ken's repos (YACC1-D first, 2026-10-02; the same spirit for P8X and the cottageworker sites) must read as Ken's own project documentation. Use the plain documentation voice:
- the subject is the machine or the document;
- decisions become dated facts ("chosen 2026-09-25");
- procedures are in the imperative;
- "I" (Ken) only where a person must be in the sentence.

Never narrate requests or collaborators: no "Ken asked", "Ken's pick", "at Ken's request", "Claude", "this session" or "the agent".

**Why:** Ken said the doc plan's "Ken asked for complete hardware documentation..." shouldn't be third person or describe the instructions he gave. It should just be the plan. He states Claude's involvement once himself: the README "Who made it" paragraph and the project-site home page say "Claude, Anthropic's AI, has been directly involved in its design, coding and documentation".

**How to apply:**
- This applies to new docs, comments and commit-adjacent prose alike.
- Exempt: CLAUDE.md, the authorship headers and `tools/authors.tsv`, commit messages, `deprecated/`, `archive/`, third-party and generated files.
- The rule is written into YACC1-D's CLAUDE.md, so it travels to the other Mac.
- Related: [[project_yacc1]].
