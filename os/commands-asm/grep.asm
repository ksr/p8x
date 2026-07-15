; grep.asm — hand-coded GREP command (asm counterpart of os/commands/grep.c).
;   GREP [-r] regex [file|glob]   print lines matching a basic regex (. * + ? ^ $)
; Shares match() via `;#use regex` and the file/glob/stdin engine + de[] via
; `;#use stdin`. Non-recursive: read a file/glob/stdin and print matching lines.
; -r: walk the CWD tree (collect file paths, find-style depth-indexed recursion
; on FSDIRBUF page $EA), then grep each, printing "path:line".
; Entry: P2 = arg tail.
;#use stdin
;#use regex
;#use abi

; ---- entry: parse args (skip leading spaces, detect -r/-h) -----------------
; g_arg (word) = a moving cursor into the arg tail (P2 on entry). We keep the
; pointer in the g_arg RAM word and reload P2 from it whenever we dereference,
; since match()/syscalls clobber P1/P2.
        .org $6A00
        TPA2L
        STA g_arg
        TPA2H
        STA g_arg+1
        LDA #0
        STA recurse
; g_sk: skip spaces (ASCII 32) at the front of the arg tail.
g_sk:   LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ g_chk
        LDA g_arg
        LDB #1
        ADD
        STA g_arg
        JNC g_sk
        LDA g_arg+1
        INC
        STA g_arg+1
        JMP g_sk
; g_chk: first non-space char. Empty (NUL) or CR => print usage. A leading '-'
; means an option: -h/-H show usage, -r enables recursion; any other '-...' is
; treated as the regex itself (falls through to g_re using the original g_arg).
g_chk:  LDA (P2)
        LDB #0
        CMP
        JZ g_usage
        LDB #13
        CMP
        JZ g_usage
        LDB #'-'
        CMP
        JNZ g_re
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ g_usage
        LDB #'H'
        CMP
        JZ g_usage
        LDB #'r'
        CMP
        JNZ g_re                      ; '-' not -r/-h: treat rest as regex (from g_arg)
        LDA #1
        STA recurse
        ; skip the "-r" token (2 chars), then its trailing spaces (grs loop)
        LDA g_arg
        LDB #2
        ADD
        STA g_arg
        JNC grs
        LDA g_arg+1
        INC
        STA g_arg+1
grs:    LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        LDA (P2)
        LDB #32
        CMP
        JNZ g_re
        LDA g_arg
        LDB #1
        ADD
        STA g_arg
        JNC grs
        LDA g_arg+1
        INC
        STA g_arg+1
        JMP grs
; g_re: copy the regex word (up to first space/CR/NUL, max 63 chars) into re[],
; NUL-terminated. fi counts chars copied so g_arg can be advanced past it.
g_re:   LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        LDA #<re
        TAP1L
        LDA #>re
        TAP1H
        LDA #0
        STA fi
gre_l:  LDA fi                        ; stop at 63 chars (leave room for NUL in 64-byte re[])
        LDB #63
        CMP
        JC gre_d
        LDA (P2)
        LDB #0
        CMP
        JZ gre_d
        LDB #32
        CMP
        JZ gre_d
        LDB #13
        CMP
        JZ gre_d
        LDA (P2)
        STA (P1)+
        INP2
        LDA fi
        INC
        STA fi
        JMP gre_l
gre_d:  LDA #0
        STA (P1)
        ; g_arg += fi  (advance past the regex word)
        LDA g_arg
        LDB fi
        ADD
        STA g_arg
        JNC gad
        LDA g_arg+1
        INC
        STA g_arg+1
; gad_s: skip spaces after the regex, leaving g_arg at the optional file/glob arg.
gad:    LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
gad_s:  LDA (P2)
        LDB #32
        CMP
        JNZ g_go
        LDA g_arg
        LDB #1
        ADD
        STA g_arg
        JNC gad_s2
        LDA g_arg+1
        INC
        STA g_arg+1
gad_s2: LDA g_arg
        TAP2L
        LDA g_arg+1
        TAP2H
        JMP gad_s
; g_go: dispatch. recurse==0 -> non-recursive path; else the -r tree walk.
g_go:   LDA recurse
        LDB #0
        CMP
        JZ g_plain
; ---- -r : collect CWD tree, grep each --------------------------------------
        ; Phase 1: collect() fills rfiles[] with up to 36 file paths under CWD.
        ; Phase 2: grep each collected path, prefixing output with "path:".
        LDA #0
        STA nrf                       ; nrf = count of collected files
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        JSR SYS_GETCWD               ; cur[] = absolute CWD string (path prefix base)
        LDA #<cur
        TAP1L
        LDA #>cur
        TAP1H
        LDA #0
        STA fi
gcl:    LDA (P1)
        LDB #0
        CMP
        JZ gcl0
        INP1
        LDA fi
        INC
        STA fi
        JMP gcl
; fi now = strlen(cur). parr[0] records the path length at depth 0 so nested
; collect() calls know where to append/truncate the "cur" path as they recurse.
gcl0:   LDA #0
        STA w_depth
        JSR parr_a
        LDA fi
        STA (P1)
        LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR SYS_OPENCWD              ; SYS_OPENCWD
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR FSDIRBUF                  ; point the dir-scan buffer at RAM page $EA
        JSR collect                   ; fill rfiles[]/nrf with the tree's file paths
; Phase 2: for gi in 0..nrf, grep rfiles[gi] with "path:" line prefix.
        LDA #0
        STA gi
gp2_l:  LDA gi
        LDB nrf
        CMP
        JC gp2_d
        LDA gi
        STA rfi
        JSR rf_addr                   ; rfp -> rfiles[gi] (the path string)
        LDA #0
        STA fromfile
        LDA rfp
        STA op_a
        LDA rfp+1
        STA op_a+1
        JSR open_path                 ; returns A: 1 = opened OK
        LDB #1
        CMP
        JNZ gp2_n                      ; open failed -> skip this path
        LDA #1
        STA fromfile
        LDA rfp
        STA gs_pfx
        LDA rfp+1
        STA gs_pfx+1
        JSR grep_stream
gp2_n:  LDA gi
        INC
        STA gi
        JMP gp2_l
gp2_d:  RTS
; ---- non-recursive: file/glob/stdin ----------------------------------------
; openarg opens the file/glob at g_arg, or falls back to stdin if no arg.
; Return A: 2 = "not found" -> print error; otherwise the stream is ready.
g_plain:LDA g_arg
        STA oa_a
        LDA g_arg+1
        STA oa_a+1
        JSR openarg
        LDB #2
        CMP
        JZ g_nf
        LDA #0
        STA gs_pfx
        STA gs_pfx+1
        JSR grep_stream
        RTS
g_nf:   LDA #<u_nf
        TAP1L
        LDA #>u_nf
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS
g_usage:LDA #<u_use
        TAP1L
        LDA #>u_use
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ======================= grep_stream =======================================
; Read the currently-open stream one char at a time via nextc, accumulate a
; line in line[] (LF/CR terminated), and run do_match on each complete line.
; In:  gs_pfx (word) = 0 for no prefix, else pointer to a "pfx" printed as
;      "pfx:" before each matching line (used to show the file path under -r).
; gn = current line length. Lines longer than 255 chars are truncated (the
; overflow chars are consumed but dropped once gn reaches 255).
grep_stream:
        LDA #0
        STA gn
gst_l:  JSR nextc                     ; A = next char, C set at end of stream
        JC gst_end
        STA g_sc
        LDB #10                        ; LF ends a line
        CMP
        JZ gst_eol
        LDA g_sc
        LDB #13
        CMP
        JZ gst_eol
        LDA gn                        ; at 175 chars: drop overflow, keep scanning
        LDB #175                      ;   (line[] is 176 bytes: 175 data + NUL)
        CMP
        JC gst_l
        LDA #<line
        LDB gn
        ADD
        TAP1L
        LDA #>line
        JNC gsl1
        INC
gsl1:   TAP1H
        LDA g_sc
        STA (P1)
        LDA gn
        INC
        STA gn
        JMP gst_l
; gst_eol: NUL-terminate line[] at gn, and match it (skip empty lines).
gst_eol:LDA #<line
        LDB gn
        ADD
        TAP1L
        LDA #>line
        JNC gse1
        INC
gse1:   TAP1H
        LDA #0
        STA (P1)
        LDA gn
        LDB #0
        CMP
        JZ gst_reset                  ; empty line: nothing to match
        JSR do_match
gst_reset:
        LDA #0
        STA gn
        JMP gst_l
; gst_end: stream ended. Flush any partial last line (no trailing newline).
gst_end:LDA gn
        LDB #0
        CMP
        JZ gst_ret
        LDA #<line
        LDB gn
        ADD
        TAP1L
        LDA #>line
        JNC gsf1
        INC
gsf1:   TAP1H
        LDA #0
        STA (P1)
        JSR do_match
gst_ret:RTS

; do_match: run the shared regex match() on line[] against re[]. If it matches,
; print the line (preceded by "gs_pfx:" when gs_pfx is non-zero) plus a newline.
; match() returns A: nonzero = match. match/SYS_PUTC clobber P1/P2.
do_match:
        LDA #<re
        STA rx_re
        LDA #>re
        STA rx_re+1
        LDA #<line
        STA rx_t
        LDA #>line
        STA rx_t+1
        JSR match
        LDB #0
        CMP
        JZ dm_ret                      ; no match: nothing to print
        ; print prefix only if gs_pfx (either byte) is non-zero
        LDA gs_pfx
        LDB #0
        CMP
        JNZ dm_pfx
        LDA gs_pfx+1
        LDB #0
        CMP
        JZ dm_line
dm_pfx: LDA gs_pfx
        TAP1L
        LDA gs_pfx+1
        TAP1H
dmp_l:  LDA (P1)
        LDB #0
        CMP
        JZ dmp_d
        JSR SYS_PUTC
        INP1
        JMP dmp_l
dmp_d:  LDA #':'
        JSR SYS_PUTC
dm_line:LDA #<line
        TAP1L
        LDA #>line
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
dm_ret: RTS

; ======================= collect (-r walk) =================================
; Recursively walk the currently-open directory, appending each regular file's
; full path to rfiles[] (capped at 36 entries). Subdirectories are remembered
; in the per-depth clba[]/cn[] tables and then re-opened one level deeper.
; State is indexed by w_depth (recursion depth) via the *_a helpers below; the
; "cur" string is extended with "/name" on the way down and truncated on return.
; This is the find-style, explicit-index recursion (no CPU call stack for dirs).
; Reentrant through w_depth; uses FSDIRBUF page $EA for the active dir scan.
collect:JSR nsub_a
        LDA #0
        STA (P1)
        JSR parr_a
        LDA (P1)
        STA fpl
; c_next: advance to the next dir entry; C set = no more -> descend into subdirs.
c_next: LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR FNEXT
        JC c_desc
        LDA #<de
        TAP1L
        LDA #>de
        TAP1H
        LDA #0
        JSR SYS_DIRENTRY
        LDA de                        ; skip entries beginning with '.' (., .., hidden)
        LDB #'.'
        CMP
        JZ c_next
        JSR rdname                    ; de[0..11] -> nm (space-trimmed name)
        LDA de+12                      ; de+12 = entry type: 1 = regular file
        LDB #1
        CMP
        JNZ c_chkdir
        LDA nrf                        ; only record a file while below the 36-file cap
        LDB #36
        CMP
        JC c_chkdir
        JSR append_file
; c_chkdir: type 2 = subdirectory. Record its LBA + name for later descent,
; up to 24 subdirs per level (nsub[w_depth] is the running count).
c_chkdir:
        LDA de+12
        LDB #2
        CMP
        JNZ c_next
        JSR nsub_a
        LDA (P1)
        LDB #24
        CMP
        JC c_next
        JSR nsub_a
        LDA (P1)
        STA fi
        JSR clba_a                     ; P1 -> clba slot for this (depth, subdir index)
        LDA de+15                      ; de+15/16 = subdir start LBA (little-endian word)
        STA (P1)+
        LDA de+16
        STA (P1)
        ; copy nm (NUL-terminated) into the cn[] name slot for this subdir
        LDA #0
        STA fk
crn_l:  JSR cn_a
        LDA #<nm
        LDB fk
        ADD
        TAP2L
        LDA #>nm
        JNC crn1
        INC
crn1:   TAP2H
        LDA (P2)
        STA (P1)
        LDB #0
        CMP
        JZ crn_d
        LDA fk
        INC
        STA fk
        JMP crn_l
crn_d:  JSR nsub_a
        LDA (P1)
        INC
        STA (P1)
        JMP c_next
; c_desc: all entries of this dir seen. Now descend into each recorded subdir.
; gidxr[w_depth] iterates 0..nsub[w_depth]; for each, reopen the subdir by LBA,
; extend "cur" with "/name", recurse via collect(), then restore "cur".
c_desc: JSR idx_a
        LDA #0
        STA (P1)
c_dl:   JSR idx_a
        LDA (P1)
        STA fi
        JSR nsub_a
        LDA (P1)
        LDB fi
        CMP
        JZ c_ret
        JSR clba_a
        LDA (P1)+
        STA flba
        LDA (P1)
        STA flba+1
        LDA flba
        TAP1L
        LDA flba+1
        TAP1H
        LDA #0
        JSR SYS_OPENDIR
        LDA #0
        TAP1L
        TAP1H
        LDA #$EA
        JSR FSDIRBUF
        JSR parr_a
        LDA (P1)
        STA fpl
        LDA fpl
        STA cp                        ; cp = write cursor into cur[] (starts at parent len)
        ; if cur is exactly "/" (len 1) don't append a second '/'
        LDA fpl
        LDB #1
        CMP
        JNZ c_addsl
        LDA cur
        LDB #'/'
        CMP
        JZ c_nameonly
c_addsl:LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC ca1
        INC
ca1:    TAP1H
        LDA #'/'
        STA (P1)
        LDA cp
        INC
        STA cp
c_nameonly:
        LDA #0
        STA fk
cnm_l:  JSR cn_a
        LDA (P1)
        STA fch
        LDB #0
        CMP
        JZ cnm_d
        LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC cn1
        INC
cn1:    TAP1H
        LDA fch
        STA (P1)
        LDA cp
        INC
        STA cp
        LDA fk
        INC
        STA fk
        JMP cnm_l
cnm_d:  LDA #<cur
        LDB cp
        ADD
        TAP1L
        LDA #>cur
        JNC cn2
        INC
cn2:    TAP1H
        LDA #0
        STA (P1)
        ; recurse one level deeper: save this level's cur length in parr[depth+1]
        LDA w_depth
        INC
        STA w_depth
        JSR parr_a
        LDA cp
        STA (P1)
        JSR collect
        LDA w_depth
        DEC
        STA w_depth                    ; back up; restore cur to the parent length below
        JSR parr_a
        LDA (P1)
        STA fpl
        LDA #<cur
        LDB fpl
        ADD
        TAP1L
        LDA #>cur
        JNC cr1
        INC
cr1:    TAP1H
        LDA #0
        STA (P1)
        JSR idx_a
        LDA (P1)
        INC
        STA (P1)
        JMP c_dl
c_ret:  RTS

; append_file: rfiles[nrf] = cur[0..fpl) + sep + nm ; nrf++
append_file:
        LDA nrf
        STA rfi
        JSR rf_addr
        LDA #0
        STA afk
af_cl:  LDA afk
        LDB fpl
        CMP
        JZ af_sep
        LDA #<cur
        LDB afk
        ADD
        TAP2L
        LDA #>cur
        JNC af1
        INC
af1:    TAP2H
        LDA (P2)
        STA afc
        LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA afc
        STA (P1)
        LDA rfp
        LDB #1
        ADD
        STA rfp
        JNC af2
        LDA rfp+1
        INC
        STA rfp+1
af2:    LDA afk
        INC
        STA afk
        JMP af_cl
af_sep: LDA fpl
        LDB #1
        CMP
        JNZ af_slash
        LDA cur
        LDB #'/'
        CMP
        JZ af_name
af_slash:
        LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA #'/'
        STA (P1)
        LDA rfp
        LDB #1
        ADD
        STA rfp
        JNC af_name
        LDA rfp+1
        INC
        STA rfp+1
af_name:LDA #0
        STA afk
af_nl:  LDA #<nm
        LDB afk
        ADD
        TAP2L
        LDA #>nm
        JNC afn1
        INC
afn1:   TAP2H
        LDA (P2)
        STA afc
        LDB #0
        CMP
        JZ af_nd
        LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA afc
        STA (P1)
        LDA rfp
        LDB #1
        ADD
        STA rfp
        JNC afn2
        LDA rfp+1
        INC
        STA rfp+1
afn2:   LDA afk
        INC
        STA afk
        JMP af_nl
af_nd:  LDA rfp
        TAP1L
        LDA rfp+1
        TAP1H
        LDA #0
        STA (P1)
        LDA nrf
        INC
        STA nrf
        RTS

; rf_addr: rfp (word) = rfiles + rfi*80. rfiles[] holds up to 36 collected
; paths, each in an 80-byte fixed slot. Multiply is done by repeated add of 80
; (rfn counts down), then the rfiles base is added with an explicit carry.
rf_addr:LDA #0
        STA rfp
        STA rfp+1
        LDA rfi
        STA rfn
rfa_l:  LDA rfn
        LDB #0
        CMP
        JZ rfa_d
        LDA rfp
        LDB #80
        ADD
        STA rfp
        JNC rfa1
        LDA rfp+1
        INC
        STA rfp+1
rfa1:   LDA rfn
        DEC
        STA rfn
        JMP rfa_l
rfa_d:  LDA rfp
        LDB #<rfiles
        ADD
        STA rfp
        LDA #0
        JNC rfa2
        LDA #1
rfa2:   STA rfcar
        LDA rfp+1
        LDB #>rfiles
        ADD
        LDB rfcar
        ADD
        STA rfp+1
        RTS

; rdname: de[0..11] (non-space) -> nm
rdname: LDA #<nm
        TAP1L
        LDA #>nm
        TAP1H
        LDA #<de
        TAP2L
        LDA #>de
        TAP2H
        LDA #0
        STA fk
rd_l:   LDA fk
        LDB #12
        CMP
        JZ rd_d
        LDA (P2)
        LDB #32
        CMP
        JZ rd_sk
        STA (P1)+
rd_sk:  INP2
        LDA fk
        INC
        STA fk
        JMP rd_l
rd_d:   LDA #0
        STA (P1)
        RTS

; ======================= index helpers (find-style) ========================
; Address calculators for the per-depth walk state, all indexed by w_depth:
;   nsub_a  -> &nsub[depth]   (subdir count at this level)
;   idx_a   -> &gidxr[depth]  (which subdir we're currently descending)
;   parr_a  -> &parr[depth]   (length of "cur" path at this level, for truncation)
;   clba_a  -> &clba[depth][fi]  (2-byte LBA of subdir fi; stride 48 per depth, 2 per fi)
;   cn_a    -> &cn[depth][fi][fk] (name char fk of subdir fi; stride 32 per depth,
;              16 per subdir). All compute a 16-bit address via add-with-carry.
nsub_a: LDA #<nsub
        LDB w_depth
        ADD
        TAP1L
        LDA #>nsub
        JNC nsa1
        INC
nsa1:   TAP1H
        RTS
idx_a:  LDA #<gidxr
        LDB w_depth
        ADD
        TAP1L
        LDA #>gidxr
        JNC ixa1
        INC
ixa1:   TAP1H
        RTS
parr_a: LDA #<parr
        LDB w_depth
        ADD
        TAP1L
        LDA #>parr
        JNC pra1
        INC
pra1:   TAP1H
        RTS
clba_a: LDA #0
        STA ft
        STA ft+1
        LDA w_depth
        STA fn
cla_m:  LDA fn
        LDB #0
        CMP
        JZ cla_md
        LDA ft
        LDB #48
        ADD
        STA ft
        JNC cla_1
        LDA ft+1
        INC
        STA ft+1
cla_1:  LDA fn
        DEC
        STA fn
        JMP cla_m
cla_md: LDA fi
        SHL
        LDB ft
        ADD
        STA ft
        JNC cla_2
        LDA ft+1
        INC
        STA ft+1
cla_2:  LDA ft
        LDB #<clba
        ADD
        STA ft
        LDA #0
        JNC cla_3
        LDA #1
cla_3:  STA fcar
        LDA ft+1
        LDB #>clba
        ADD
        LDB fcar
        ADD
        STA ft+1
        LDA ft
        TAP1L
        LDA ft+1
        TAP1H
        RTS
cn_a:   LDA #0
        STA ft
        STA ft+1
        LDA w_depth
        STA fn
cna_m:  LDA fn
        LDB #0
        CMP
        JZ cna_md
        LDA ft+1
        INC
        STA ft+1
        LDA ft
        LDB #128             ; cn per-depth stride = 24*16 = 384 (256 hi + 128 lo);
        ADD                  ;   was 32 (=288), which overlapped the parent depth's
        STA ft               ;   name table for subdir indices >= 19
        JNC cna_1
        LDA ft+1
        INC
        STA ft+1
cna_1:  LDA fn
        DEC
        STA fn
        JMP cna_m
cna_md: LDA fi
        STA fk2
cna_fl: LDA fk2
        LDB #0
        CMP
        JZ cna_fd
        LDA ft
        LDB #16
        ADD
        STA ft
        JNC cna_f1
        LDA ft+1
        INC
        STA ft+1
cna_f1: LDA fk2
        DEC
        STA fk2
        JMP cna_fl
cna_fd: LDA ft
        LDB fk
        ADD
        STA ft
        JNC cna_k1
        LDA ft+1
        INC
        STA ft+1
cna_k1: LDA ft
        LDB #<cn
        ADD
        STA ft
        LDA #0
        JNC cna_b
        LDA #1
cna_b:  STA fcar
        LDA ft+1
        LDB #>cn
        ADD
        LDB fcar
        ADD
        STA ft+1
        LDA ft
        TAP1L
        LDA ft+1
        TAP1H
        RTS

; ======================= strings & RAM scratch =============================
u_nf:   .asciiz "grep: not found"
; Usage line. The message contains a literal semicolon, which cannot appear in a
; quoted string (the assembler strips from ';' to end-of-line as a comment), so
; it is emitted as .byte 59 (ASCII ';') between the two .ascii fragments. The
; trailing .byte 0 NUL-terminates the whole concatenated string.
u_use:  .ascii "usage: GREP [-r] regex [file|glob]   match regex (. * + ? ^ $)"
        .byte 59
        .ascii " -r walks the CWD tree"
        .byte 0

g_arg:  .fill 2
recurse:.fill 1
gi:     .fill 1
gn:     .fill 1
g_sc:    .fill 1
gs_pfx: .fill 2
w_depth:.fill 1
fpl:    .fill 1
cp:     .fill 1
fi:     .fill 1
fk:     .fill 1
fk2:    .fill 1
fch:    .fill 1
flba:   .fill 2
nrf:    .fill 1
rfi:    .fill 1
rfp:    .fill 2
rfn:    .fill 1
rfcar:  .fill 1
afk:    .fill 1
afc:    .fill 1
ft:     .fill 2
fn:     .fill 1
fcar:   .fill 1
re:     .fill 64                      ; compiled/copied regex pattern (63 chars + NUL)
line:   .fill 176                     ; current input line (up to 175 data + NUL)
nm:     .fill 16                      ; one dir entry name, space-trimmed + NUL
cur:    .fill 176                     ; running absolute path during the -r walk
nsub:   .fill 8                       ; nsub[depth]  = subdir count (max depth 8)
gidxr:  .fill 8                       ; gidxr[depth] = subdir currently descending
parr:   .fill 8                       ; parr[depth]  = cur[] length at this depth
clba:   .fill 384                     ; clba[8][24] LBAs: 8 depths * 24 subdirs * 2 bytes
cn:     .fill 3072                    ; cn[8][24][16] subdir names: 8*24*16 bytes
rfiles: .fill 2880                    ; 36 collected paths * 80-byte slots
