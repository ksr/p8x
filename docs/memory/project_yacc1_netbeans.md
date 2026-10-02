---
name: project-yacc1-netbeans
description: NetBeans 8.2 is Ken's current C IDE/compiler front end for the YACC1 host tools; nbproject/ dirs are kept in YACC1-D for that reason, but he plans to migrate to something else eventually
metadata:
  type: project
---

Ken uses NetBeans (8.2, with JDK 8, installers listed under YACC1-D/vm/) as the compiler IDE for the YACC1 host
tools (assembler, emulator, disasm/disasm2, uCode-Generator2, gen test vectors). That is why `nbproject/`
(minus `nbproject/private/`) is kept beside each C tool in ~/Developer/YACC1-D (decided 2026-09-20).
He said he "will want to migrate to something else eventually" (no target chosen).

**Why:** the nbproject folders look like junk but are the only build definitions for those tools today.
**How to apply:** don't strip `nbproject/`; when the IDE move happens, replace them with plain Makefiles (some
tools already have one) and retire the NetBeans/JDK 8 entries in `vm/`. Noted as open decision 7 in the
YACC1-D README. See [[project-yacc1-kicad]].
