; cp.asm — hand-coded CP command (asm counterpart of os/commands/cp.c).
;   CP [-r] src dst   copy a file, or -r a directory tree.
; abspath() inline; copy_tree recursion uses depth-indexed per-level arrays
; (sp/dp/names/isd/n/idx) keyed by a global w_depth (P3 is the stack pointer).
; Iterates on FSDIRBUF page $A0. BIOS: FRESOLVE $0133, FOPEN $0124, FGETB $0127,
; FWOPEN $012A, FPUTB $012D, FCLOSE $0130, FOPENDIR $0139, FNEXT $013C, FSDIRBUF
; $0145, SYS_DIRENTRY $201B. OS: SYS_GETCWD $2003, SYS_MKDIR $2021, SYS_PUTS/PUTC.
; A `*`/`?` source is a glob (lib_globx): every match is copied into the dst
; directory. copy_tree iterates on FSDIRBUF page $E0 (above the enlarged binary).
; Entry: P2 = arg tail.
;#use glob
;#use globx
;#use abi

        .org $6A00
        TPA2L
        STA c_arg
        TPA2H
        STA c_arg+1
        LDA #0
        STA rec
c_sk:   LPW2 c_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #32
        CMP
        JNZ c_opt
        INCW c_arg                ; <- tierA: 16-bit INCW chain before JMP c_sk (next: JMP c_sk -> LDA)
        JMP c_sk
c_opt:  LDA (P2)
        LDB #'-'
        CMP
        JNZ c_args
        INP2
        LDA (P2)
        LDB #'h'
        CMP
        JZ c_usage
        LDB #'H'
        CMP
        JZ c_usage
        LDB #'r'
        CMP
        JZ c_setr
        LDB #'R'
        CMP
        JZ c_setr
        JMP c_args
c_setr: LDA #1
        STA rec
        LDA c_arg
        LDB #2
        ADD
        STA c_arg
        JNC csr_s
        LDA c_arg+1
        INC
        STA c_arg+1
csr_s:  LPW2 c_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #32
        CMP
        JNZ c_args
        INCW c_arg                ; <- tierA: 16-bit INCW chain before JMP csr_s (next: JMP csr_s -> LDA)
        JMP csr_s
c_args: LPW2 c_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #0
        CMP
        JZ c_usage2
        LDB #13
        CMP
        JZ c_usage2
        LDA #0                       ; copy src WORD into patw, note glob (cg)
        STA cg
        LDP1 #patw                ; <- tierA: pointer constant (next: LDA)
        LPW2 c_arg                ; <- tierA: pointer load (next: LDA)
        LDA #0
        STA cpw
cpw_l:  LDA (P2)
        LDB #0
        CMP
        JZ cpw_d
        LDB #13
        CMP
        JZ cpw_d
        LDB #32
        CMP
        JZ cpw_d
        LDB #'*'
        CMP
        JZ cpw_g
        LDB #'?'
        CMP
        JZ cpw_g
        JMP cpw_s
cpw_g:  LDA #1
        STA cg
        LDA (P2)
cpw_s:  STA (P1)+
        INP2
        LDA cpw
        INC
        STA cpw
        JMP cpw_l
cpw_d:  LDA #0
        STA (P1)
        LDA c_arg                    ; c_arg += cpw
        LDB cpw
        ADD
        STA c_arg
        JNC ca_sk
        LDA c_arg+1
        INC
        STA c_arg+1
ca_sk:  LPW2 c_arg                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #32
        CMP
        JNZ ca_d
        INCW c_arg                ; <- tierA: 16-bit INCW chain before JMP ca_sk (next: JMP ca_sk -> LDA)
        JMP ca_sk
ca_d:   LDA (P2)
        LDB #0
        CMP
        JZ c_usage2
        LDB #13
        CMP
        JZ c_usage2
        LDW ap_out,#dst                ; <- tierA: address constant (next: LDA)
        MOVW ap_a,c_arg                ; <- tierA: word move (next: JSR abspath)
        JSR abspath                  ; abspath(dst, arg)
        LDA cg                       ; glob source? -> c_glob
        LDB #0
        CMP
        JNZ c_glob
        LDW ap_out,#src                ; <- tierA: address constant (next: LDA)
        LDW ap_a,#patw                ; <- tierA: address constant (next: JSR abspath)
        JSR abspath
        LDA rec
        LDB #0
        CMP
        JZ c_dofile
        LDW id_p,#src                ; <- tierA: address constant (next: JSR isdir)
        JSR isdir
        LDB #0
        CMP
        JZ c_dofile
        LDW ct_s,#src                ; <- tierA: address constant (next: LDA)
        LDW ct_d,#dst                ; <- tierA: address constant (next: LDA)
        LDA #0
        STA w_depth
        JSR copy_tree
        RTS
c_dofile:
        LDW cf_s,#src                ; <- tierA: address constant (next: LDA)
        LDW cf_d,#dst                ; <- tierA: address constant (next: JSR copy_file)
        JSR copy_file
        LDB #1
        CMP
        JZ c_srcnf
        RTS
; --- glob: dst must be a dir; copy each match into it -----------------------
c_glob: LDW id_p,#dst                ; <- tierA: address constant (next: JSR isdir)
        JSR isdir
        LDB #0
        CMP
        JZ c_notdir
        LDW ge_pat,#patw                ; <- tierA: address constant (next: LDA)
        LDW ge_out,#gfiles                ; <- tierA: address constant (next: LDA)
        LDA #24
        STA ge_max
        JSR glob_expand
        LDA ge_cnt
        LDB #0
        CMP
        JZ c_nomatch
        LDA #0
        STA cgi
cg_l:   LDA cgi
        LDB ge_cnt
        CMP
        JC cg_done                   ; i >= cnt
        JSR cg_ptr                   ; cgp = gfiles + cgi*64
        LDW ap_out,#src                ; <- tierA: address constant (next: LDA)
        MOVW ap_a,cgp                ; <- tierA: word move (next: JSR abspath)
        JSR abspath
        JSR cg_base                  ; cgbp = basename of the match
        LDW jp_out,#jdst                ; <- tierA: address constant (next: LDA)
        LDW jp_dir,#dst                ; <- tierA: address constant (next: LDA)
        MOVW jp_name,cgbp                ; <- tierA: word move (next: JSR joinp)
        JSR joinp
        LDA rec                      ; -r && dir -> copy_tree, else copy_file
        LDB #0
        CMP
        JZ cg_file
        LDW id_p,#src                ; <- tierA: address constant (next: JSR isdir)
        JSR isdir
        LDB #0
        CMP
        JZ cg_file
        LDW ct_s,#src                ; <- tierA: address constant (next: LDA)
        LDW ct_d,#jdst                ; <- tierA: address constant (next: LDA)
        LDA #0
        STA w_depth
        JSR copy_tree
        JMP cg_next
cg_file:LDW cf_s,#src                ; <- tierA: address constant (next: LDA)
        LDW cf_d,#jdst                ; <- tierA: address constant (next: JSR copy_file)
        JSR copy_file
cg_next:LDA cgi
        INC
        STA cgi
        JMP cg_l
cg_done:RTS
c_notdir:
        LDP1 #u_notdir                ; <- tierA: pointer constant (next: JMP c_eput -> LDA)
        JMP c_eput
c_nomatch:
        LDP1 #u_nomat                ; <- tierA: pointer constant (next: JMP c_eput -> LDA)
        JMP c_eput
; cg_ptr: cgp = gfiles + cgi*64
cg_ptr: LDW cgp,#0                ; <- tierA: zero word (next: LDA)
        LDA cgi
        STA cgt
cgp_l:  LDA cgt
        LDB #0
        CMP
        JZ cgp_d
        ADDW cgp,#64                ; <- tierA: 16-bit ADDW chain, skip label cgp_1 dropped (next: LDA)
        LDA cgt
        DEC
        STA cgt
        JMP cgp_l
cgp_d:  LDA cgp
        LDB #<gfiles
        ADD
        STA cgp
        LDA #0
        JNC cgp_2
        LDA #1
cgp_2:  STA cgcar
        LDA cgp+1
        LDB #>gfiles
        ADD
        LDB cgcar
        ADD
        STA cgp+1
        RTS
; cg_base: cgbp = cgp advanced past the last '/', else cgp
cg_base:MOVW cgbp,cgp                ; <- tierA: word move (next: LDA)
        LPW1 cgp                ; <- tierA: pointer load (next: LDA)
        LDA #0
        STA cgk
cgb_l:  LDA (P1)
        LDB #0
        CMP
        JZ cgb_d
        LDB #'/'
        CMP
        JNZ cgb_adv
        LDA cgk                      ; cgbp = cgp + cgk + 1
        INC
        STA cgt
        LDA cgp
        LDB cgt
        ADD
        STA cgbp
        LDA #0
        JNC cgb_hi
        LDA #1
cgb_hi: LDB cgp+1
        ADD
        STA cgbp+1
cgb_adv:INP1
        LDA cgk
        INC
        STA cgk
        JMP cgb_l
cgb_d:  RTS
; c_usage: -h was asked for, so this is requested OUTPUT: it stays on stdout via
; SYS_PUTS/SYS_PUTC and `cp -h >notes` still captures it. Everything below it is
; on a failure path and takes the c_eput tail instead.
c_usage:LDP1 #u_use                ; <- tierA: pointer constant (next: JMP c_put -> LDA)
        JMP c_put
c_usage2:
        LDP1 #u_use2                ; <- tierA: pointer constant (next: JMP c_eput -> LDA)
        JMP c_eput
c_srcnf:LDP1 #u_nf                ; <- tierA: pointer constant (next: LDA)
; c_eput: ERROR tail — print P1's string on the raw console (PUTS/CONOUT), never
; to stdout, which may be a redirect or a pipe: `cp x y >F` would otherwise write
; the message INTO F and `cp x y | wc` would feed it to wc as data. The newline
; goes to CONOUT for the same reason, or the message would split across two
; sinks. Matches cp.c's eputs(). c_put below is the plain stdout tail (-h only).
c_eput: LDA #0
        JSR PUTS
        LDA #10
        JSR CONOUT
        RTS
c_put:  LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        RTS

; ======================= copy_file / isdir =================================
; copy_file: byte-copy the file named by cf_s (src abspath) to cf_d (dst
;   abspath). Opens src read-only at page $FC00 (FOPEN buffer above the binary),
;   opens dst for write (FWOPEN), then FGETB->FPUTB until EOF (FGETB sets C).
;   FGETB/FPUTB clobber P1/P2, so cfch stashes each byte between the two calls.
;   Returns A=0 on success, A=1 if the source could not be opened (cf_nf).
copy_file:
        LPW1 cf_s                ; <- tierA: pointer load (next: LDA)
        LDA #0
        JSR FRESOLVE
        LDA #$00
        TAP1L
        LDA #$FC
        TAP1H
        LDA #0
        JSR FOPEN
        JC cf_nf
        LPW1 cf_d                ; <- tierA: pointer load (next: LDA)
        LDA #0
        JSR FRESOLVE
        LDA #0
        JSR FWOPEN
cf_cp:  LDA #0
        JSR FGETB
        JC cf_done
        STA cfch
        LDA #0
        TAP1L
        TAP1H
        LDA cfch
        JSR FPUTB
        JMP cf_cp
cf_done:LDA #0
        JSR FCLOSE
        LDA #0
        RTS
cf_nf:  LDA #1
        RTS
; isdir: return A=1 if the path at id_p is a directory (FOPENDIR succeeds,
;   C clear), else A=0. FOPENDIR sets C on failure.
isdir:  LPW1 id_p                ; <- tierA: pointer load (next: LDA)
        LDA #0
        JSR FOPENDIR
        JC id_no
        LDA #1
        RTS
id_no:  LDA #0
        RTS

; ======================= copy_tree =========================================
; copy_tree: recursively copy directory ct_s -> ct_d. w_depth is the current
;   recursion level; all per-level scratch (sp/dp/names/isd/nn/cidx) is indexed
;   by w_depth via the index helpers below, so the P8X hardware stack (P3) only
;   holds return addresses. Steps: stash src/dst abspaths into sp[d]/dp[d],
;   SYS_MKDIR the dst, then FOPENDIR src and buffer the whole listing (dir page
;   $E0, chosen above the enlarged binary) into names[d]/isd[d] BEFORE any
;   recursion — FSDIRBUF/FNEXT share one global dir buffer, so the child names
;   must be captured up front. Entries named "." (and ".." — first char '.')
;   are skipped; so is every entry past the 24th of a level (names[d]/isd[d]
;   hold 24), and each name is truncated to its 12-byte slot. Both caps are
;   silent. Pass two (ct_proc) walks the captured
;   entries: joinp the child src/dst, then recurse if isd[d][i], else copy_file.
copy_tree:
        JSR spd_a                    ; sp[d] = *ct_s
        TPA1L
        STA sc_d
        TPA1H
        STA sc_d+1
        MOVW sc_s,ct_s                ; <- tierA: word move (next: JSR scopy)
        JSR scopy
        JSR dpd_a                    ; dp[d] = *ct_d
        TPA1L
        STA sc_d
        TPA1H
        STA sc_d+1
        MOVW sc_s,ct_d                ; <- tierA: word move (next: JSR scopy)
        JSR scopy
        JSR dpd_a                    ; SYS_MKDIR(dp[d])
        LDA #0
        JSR SYS_MKDIR
        JSR spd_a                    ; FOPENDIR(sp[d])
        LDA #0
        JSR FOPENDIR
        LDA #0
        TAP1L
        TAP1H
        LDA #$E0
        JSR FSDIRBUF
        JSR nn_a
        LDA #0
        STA (P1)
ct_nl:  LDA #0
        TAP1L
        TAP1H
        LDA #0
        JSR FNEXT
        JC ct_proc
        LDP1 #de                ; <- tierA: pointer constant (next: LDA)
        LDA #0
        JSR SYS_DIRENTRY
        LDA de
        LDB #'.'
        CMP
        JZ ct_nl
        JSR nn_a
        LDA (P1)
        LDB #24
        CMP
        JC ct_nl                     ; n>=24 -> skip
        JSR nn_a
        LDA (P1)
        STA cti
        LDA #0
        STA ctk
ct_tl:  LDA ctk
        LDB #12
        CMP
        JZ ct_isd
        LDA #<de
        LDB ctk
        ADD
        TAP2L
        LDA #>de
        JNC ct1
        INC
ct1:    TAP2H
        LDA (P2)
        STA ctc
        LDB #32
        CMP
        JZ ct_padl
        JSR names_a
        LDA ctc
        STA (P1)
        LDA ctk
        INC
        STA ctk
        JMP ct_tl
ct_padl:LDA ctk
        LDB #12
        CMP
        JZ ct_isd
        JSR names_a
        LDA #0
        STA (P1)
        LDA ctk
        INC
        STA ctk
        JMP ct_padl
ct_isd: JSR names_a                  ; both paths arrive with ctk==12: force the
        LDA #0                       ; slot's NUL (a 12-char name has no pad byte)
        STA (P1)
        LDA de+12
        LDB #2
        CMP
        JZ ct_isd1
        JSR isd_a
        LDA #0
        STA (P1)
        JMP ct_ninc
ct_isd1:JSR isd_a
        LDA #1
        STA (P1)
ct_ninc:JSR nn_a
        LDA (P1)
        INC
        STA (P1)
        JMP ct_nl
ct_proc:JSR idx_a
        LDA #0
        STA (P1)
ct_pl:  JSR idx_a
        LDA (P1)
        STA cti
        JSR nn_a
        LDA (P1)
        LDB cti
        CMP
        JZ ct_ret
        LDW jp_out,#jsrc                ; <- tierA: address constant (next: JSR spd_a)
        JSR spd_a
        TPA1L
        STA jp_dir
        TPA1H
        STA jp_dir+1
        LDA #0
        STA ctk
        JSR names_a
        TPA1L
        STA jp_name
        TPA1H
        STA jp_name+1
        JSR joinp
        LDW jp_out,#jdst                ; <- tierA: address constant (next: JSR dpd_a)
        JSR dpd_a
        TPA1L
        STA jp_dir
        TPA1H
        STA jp_dir+1
        LDA #0
        STA ctk
        JSR names_a
        TPA1L
        STA jp_name
        TPA1H
        STA jp_name+1
        JSR joinp
        JSR isd_a
        LDA (P1)
        LDB #0
        CMP
        JZ ct_file
        LDW ct_s,#jsrc                ; <- tierA: address constant (next: LDA)
        LDW ct_d,#jdst                ; <- tierA: address constant (next: LDA)
; Depth cap: the per-level arrays hold exactly 8 levels (sp/dp 8*80, names 8*312,
; isd 8*24), so descending at w_depth==8 would make spd_a run off sp into dp and
; names_a/isd_a into their neighbours. Skip the subtree instead of corrupting it.
        LDA w_depth
        INC
        LDB #8                        ; MAXD (sp/dp .fill 640 = 8*80)
        CMP
        JC  ct_pinc                   ; depth+1 >= 8 -> too deep, skip this subtree
        STA w_depth
        JSR copy_tree
        LDA w_depth
        DEC
        STA w_depth
        JMP ct_pinc
ct_file:LDW cf_s,#jsrc                ; <- tierA: address constant (next: LDA)
        LDW cf_d,#jdst                ; <- tierA: address constant (next: JSR copy_file)
        JSR copy_file
ct_pinc:JSR idx_a
        LDA (P1)
        INC
        STA (P1)
        JMP ct_pl
ct_ret: RTS

; ======================= scopy / joinp =====================================
; scopy: strcpy from sc_s to sc_d (NUL-terminated). Returns A = length copied
;   (not counting the terminator). Clobbers P1/P2.
scopy:  LPW1 sc_d                ; <- tierA: pointer load (next: LDA)
        LPW2 sc_s                ; <- tierA: pointer load (next: LDA)
        LDA #0
        STA sc_n
sc_l:   LDA (P2)
        LDB #0
        CMP
        JZ sc_dn
        STA (P1)+
        INP2
        LDA sc_n
        INC
        STA sc_n
        JMP sc_l
sc_dn:  LDA #0
        STA (P1)
        LDA sc_n
        RTS
; joinp: build jp_out = jp_dir + "/" + jp_name, inserting a single '/' only if
;   jp_dir does not already end in one. Returns A = total length. Clobbers P1/P2.
joinp:  MOVW sc_d,jp_out                ; <- tierA: word move (next: LDA)
        MOVW sc_s,jp_dir                ; <- tierA: word move (next: JSR scopy)
        JSR scopy
        STA jp_i
        LDB #0
        CMP
        JZ jp_addsl
        LDA jp_out                   ; out[i-1] == '/' ?
        LDB jp_i
        ADD
        TAP1L
        LDA jp_out+1
        JNC jp1
        INC
jp1:    TAP1H
        DEP1
        LDA (P1)
        LDB #'/'
        CMP
        JZ jp_cn
jp_addsl:
        LDA jp_out
        LDB jp_i
        ADD
        TAP1L
        LDA jp_out+1
        JNC jp2
        INC
jp2:    TAP1H
        LDA #'/'
        STA (P1)
        LDA jp_i
        INC
        STA jp_i
jp_cn:  LPW2 jp_name                ; <- tierA: pointer load (next: LDA)
        LDA jp_out
        LDB jp_i
        ADD
        TAP1L
        LDA jp_out+1
        JNC jp3
        INC
jp3:    TAP1H
jp_nl:  LDA (P2)
        LDB #0
        CMP
        JZ jp_nd
        STA (P1)+
        INP2
        LDA jp_i
        INC
        STA jp_i
        JMP jp_nl
jp_nd:  LDA #0
        STA (P1)
        LDA jp_i
        RTS

; ======================= abspath (P2 source, P1 dest) ======================
; abspath: write an absolute path for ap_a into ap_out. If ap_a already starts
;   with '/', copy it verbatim; otherwise prefix SYS_GETCWD, ensure it ends in
;   '/', then append ap_a. The source copy stops at NUL, CR (13), or space (32)
;   so a trailing arg on the command line is not included.
abspath:LDA #0
        STA ap_n
        LPW2 ap_a                ; <- tierA: pointer load (next: LDA)
        LDA (P2)
        LDB #'/'
        CMP
        JZ ab_abs
        LPW1 ap_out                ; <- tierA: pointer load (next: LDA)
        LDA #0
        JSR SYS_GETCWD
        LPW1 ap_out                ; <- tierA: pointer load (next: LDA)
ab_sl:  LDA (P1)
        LDB #0
        CMP
        JZ ab_sld
        INP1
        JMP ab_sl
ab_sld: DEP1
        LDA (P1)
        INP1
        LDB #'/'
        CMP
        JZ ab_setp
        LDA #'/'
        STA (P1)+
        JMP ab_setp
ab_abs: LPW1 ap_out                ; <- tierA: pointer load (next: LDA)
ab_setp:LPW2 ap_a                ; <- tierA: pointer load (next: LDA)
ab_cp:  LDA (P2)
        LDB #0
        CMP
        JZ ab_dn
        LDB #13
        CMP
        JZ ab_dn
        LDB #32
        CMP
        JZ ab_dn
        STA (P1)+
        INP2
        LDA ap_n
        INC
        STA ap_n
        JMP ab_cp
ab_dn:  LDA #0
        STA (P1)
        RTS

; ======================= index helpers =====================================
; Each helper returns in P1 the address of the current recursion level's slot in
;   a per-depth array, since the ISA has no indexed addressing — the offset is
;   built by repeated addition (mul80 loops w_depth times, etc.). Stride per
;   depth level: nn/cidx = 1 byte, sp/dp = 80, isd = 24, names = 288
;   (= 24 entries * 12 chars). cti/ctk select the entry/char within a level.
; nn_a:  P1 = nn + w_depth  (entry count for this level)
nn_a:   LDA #<nn
        LDB w_depth
        ADD
        TAP1L
        LDA #>nn
        JNC nna1
        INC
nna1:   TAP1H
        RTS
; idx_a: P1 = cidx + w_depth  (pass-two loop cursor for this level)
idx_a:  LDA #<cidx
        LDB w_depth
        ADD
        TAP1L
        LDA #>cidx
        JNC ixa1
        INC
ixa1:   TAP1H
        RTS
; spd_a: P1 = sp + w_depth*80
spd_a:  LDW ha,#sp                ; <- tierA: address constant (next: JMP mul80 -> LDA)
        JMP mul80
; dpd_a: P1 = dp + w_depth*80
dpd_a:  LDW ha,#dp                ; <- tierA: address constant (next: LDA)
mul80:  LDW ht,#0                ; <- tierA: zero word (next: LDA)
        LDA w_depth
        STA hn
m80l:   LDA hn
        LDB #0
        CMP
        JZ m80d
        ADDW ht,#80                ; <- tierA: 16-bit ADDW chain, skip label m801 dropped (next: LDA)
        LDA hn
        DEC
        STA hn
        JMP m80l
m80d:   LDA ht
        LDB ha
        ADD
        STA ht
        LDA #0
        JNC m80b
        LDA #1
m80b:   STA hcar
        LDA ht+1
        LDB ha+1
        ADD
        LDB hcar
        ADD
        STA ht+1
        LPW1 ht                ; <- tierA: pointer load (next: RTS)
        RTS
; isd_a: P1 = isd + w_depth*24 + cti
isd_a:  LDW ht,#0                ; <- tierA: zero word (next: LDA)
        LDA w_depth
        STA hn
isa_m:  LDA hn
        LDB #0
        CMP
        JZ isa_md
        ADDW ht,#24                ; <- tierA: 16-bit ADDW chain, skip label isa_1 dropped (next: LDA)
        LDA hn
        DEC
        STA hn
        JMP isa_m
isa_md: LDA ht
        LDB cti
        ADD
        STA ht
        JNC isa_2
        LDA ht+1
        INC
        STA ht+1
isa_2:  LDA ht
        LDB #<isd
        ADD
        STA ht
        LDA #0
        JNC isa_b
        LDA #1
isa_b:  STA hcar
        LDA ht+1
        LDB #>isd
        ADD
        LDB hcar
        ADD
        STA ht+1
        LPW1 ht                ; <- tierA: pointer load (next: RTS)
        RTS
; names_a: P1 = names + w_depth*312 + cti*13 + ctk
;   Slot stride is 13, not 12: de[0..11] is a 12-byte space-padded name field, so
;   a full 12-char name has no pad -- byte 12 of the slot is the forced NUL.
names_a:LDW ht,#0                ; <- tierA: zero word (next: LDA)
        LDA w_depth
        STA hn
na_m:   LDA hn
        LDB #0
        CMP
        JZ na_md
        LDA ht+1                     ; +312 = +256 +56
        INC
        STA ht+1
        ADDW ht,#56                ; <- tierA: 16-bit ADDW chain, skip label na_1 dropped (next: LDA)
        LDA hn
        DEC
        STA hn
        JMP na_m
na_md:  LDA cti                      ; + cti*13
        STA hk
na_cl:  LDA hk
        LDB #0
        CMP
        JZ na_cd
        ADDW ht,#13                ; <- tierA: 16-bit ADDW chain, skip label na_c1 dropped (next: LDA)
        LDA hk
        DEC
        STA hk
        JMP na_cl
na_cd:  LDA ht                       ; + ctk
        LDB ctk
        ADD
        STA ht
        JNC na_k
        LDA ht+1
        INC
        STA ht+1
na_k:   LDA ht
        LDB #<names
        ADD
        STA ht
        LDA #0
        JNC na_b
        LDA #1
na_b:   STA hcar
        LDA ht+1
        LDB #>names
        ADD
        LDB hcar
        ADD
        STA ht+1
        LPW1 ht                ; <- tierA: pointer load (next: RTS)
        RTS

u_use:  .asciiz "usage: CP [-r] src dst   copy a file/glob, or -r a directory tree"
u_use2: .asciiz "usage: CP [-r] src dst"
u_nf:   .asciiz "cp: source not found"
u_notdir:.asciiz "cp: target is not a directory"
u_nomat:.asciiz "cp: no match"

; --- static scratch / BSS (zero-initialized .fill) --------------------------
; patw holds the copied source word; gfiles is glob_expand output (24 * 64).
; The per-depth recursion arrays follow: sp/dp (8 levels * 80 bytes of path),
; names (8 * 24 * 13), isd (8 * 24 is-dir flags), nn/cidx (8 counts/cursors) --
; so copy_tree supports up to 8 nested directory levels.
c_arg:  .fill 2                      ; pointer to current position in arg tail
rec:    .fill 1                      ; -r flag (recurse into directories)
cg:     .fill 1
cpw:    .fill 1
cgi:    .fill 1
cgp:    .fill 2
cgbp:   .fill 2
cgk:    .fill 1
cgt:    .fill 1
cgcar:  .fill 1
patw:   .fill 80
gfiles: .fill 1536
w_depth:.fill 1
cti:    .fill 1
ctk:    .fill 1
ctc:    .fill 1
cfch:   .fill 1
sc_d:   .fill 2
sc_s:   .fill 2
sc_n:   .fill 1
jp_out: .fill 2
jp_dir: .fill 2
jp_name:.fill 2
jp_i:   .fill 1
ap_out: .fill 2
ap_a:   .fill 2
ap_n:   .fill 1
cf_s:   .fill 2
cf_d:   .fill 2
id_p:   .fill 2
ct_s:   .fill 2
ct_d:   .fill 2
ha:     .fill 2
ht:     .fill 2
hn:     .fill 1
hk:     .fill 1
hcar:   .fill 1
src:    .fill 80
dst:    .fill 80
jsrc:   .fill 80
jdst:   .fill 80
sp:     .fill 640
dp:     .fill 640
names:  .fill 2496                   ; 8 levels * 24 entries * 13 (12 + forced NUL)
isd:    .fill 192
nn:     .fill 8
cidx:   .fill 8
