---
name: feedback_pdf_timestamp_per_page
description: "When asked to generate documentation-type PDFs, stamp the date AND time on every page"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-14T16:32:06.171Z
---

Whenever the user asks to generate a documentation-type PDF (backlog, memory
map, programmer's guide, reference/report exports, etc.), put the **date and
time of generation on each page**, not just once on a title page.

**Why:** these PDFs are printed and marked up, and several revisions circulate;
without a per-page timestamp you cannot tell which printout is current. A date
alone is not enough when more than one version can be generated the same day.

**How to apply:** draw the timestamp in the per-page furniture callback
(reportlab `onFirstPage`/`onLaterPages`, or the equivalent header/footer hook),
so it repeats on every page. Include both date and time, e.g.
`datetime.now().strftime("%Y-%m-%d %H:%M")`, computed once at build time and
closed over by the callback. Keep it in the running footer/header alongside the
page number and document name; a title-page-only "Generated ..." subtitle does
NOT satisfy this. Applies to the P8X generators too:
`tools/mkbacklogpdf.py`, `tools/mkgitignorepdf.py`, `microcode/gen_progguide.py`,
and `generators/gen_memmap.py` PDF output. Related: [[feedback_p8x_docs_before_sync]].
