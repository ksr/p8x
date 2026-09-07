; wmkernel.asm -- the resident P8X window-manager kernel (skeleton, v1).
;
; Assembled at WMBASE ($5600, in the OS growth reserve below the TPA) and
; loaded there ONCE by the launcher (`desk`); resident thereafter, surviving
; apps that come and go in the TPA ABOVE it (proven by wm_reside_test). Living
; below the TPA, it leaves apps the full TPA $6A00..CSTACKTOP. The jump table
; at the base is bios()-callable at fixed addresses, exactly like the BIOS
; table at $0100 or the OS syscalls at $2000:
;
;   WMBASE+0  wk_init          clear the window list
;   WMBASE+3  wk_open   P1 ->  a 22-byte record [x,y,w,h (LE pairs),
;                              list, tlen, title(12)]; copied resident
;   WMBASE+6  wk_repaint       FLOOD the desktop + draw every window's
;                              chrome, title and CONTENT from the records
;   WMBASE+9  wk_run           the resident event loop (keyboard + mouse)
;   WMBASE+12 wk_save   P1=blob(4) A=win -> save the window's state
;   WMBASE+15 wk_load   P1=dest(4) A=win -> load the window's state
;   WMBASE+18 .byte 'W','M'    presence signature (the launcher checks it
;                              to skip reloading a resident kernel)
;
; Draws chrome + stroke-font title + CONTENT: each window's content is a
; card-resident command list (its `list` field), replayed with CLRUN into
; the content rect -- so the picture lives on the CARD and redraws even
; when the program that recorded it is gone. wk_repaint must NOT RESETF
; (RESETF clears the card lists); it sets the text camera directly.
; All coordinates are window space, y UP (the GL default).

GLDATA = $FF50
GLSTAT = $FF51

        .org $5600                       ; WMBASE (match --base; OS reserve, below TPA)

; ---- jump table: MUST be first so the entries land at fixed offsets ---------
        JMP  wk_init                    ; +0
        JMP  wk_open                    ; +3
        JMP  wk_repaint                 ; +6
        JMP  wk_run                     ; +9   the resident event loop
        JMP  wk_save                    ; +12  P1=blob(4), A=win -> save state
        JMP  wk_load                    ; +15  P1=dest(4), A=win -> load state
ksig:   .byte $57, $4D                  ; +18  'W','M'


        .include "wmkernel_body.asm"
