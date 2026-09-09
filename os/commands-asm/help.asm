; help.asm — hand-coded HELP command (asm counterpart of os/commands/help.c).
;   HELP   print the shell command reference.
; A table of string pointers (htab) terminated by 0; the loop prints each with
; SYS_PUTS + a newline. Keep in step with help.c. OS: SYS_PUTS $200F, SYS_PUTC
; $2009. No args. Entry: nothing needed.
;#use abi

        .org $6A00
        LDA #<htab
        STA hp
        LDA #>htab
        STA hp+1
h_lp:   LDA hp                       ; P2 = &htab[i]
        TAP2L
        LDA hp+1
        TAP2H
        LDA (P2)                     ; string ptr, low byte
        STA sp
        INP2
        LDA (P2)                     ; string ptr, high byte
        STA sp+1
        LDA hp                       ; hp += 2
        LDB #2
        ADD
        STA hp
        JNC h_ck
        LDA hp+1
        INC
        STA hp+1
h_ck:   LDA sp                       ; ptr == 0 (both bytes) -> done
        LDB #0
        CMP
        JNZ h_pr
        LDA sp+1
        CMP
        JZ h_done
h_pr:   LDA sp                       ; SYS_PUTS(sp) + newline
        TAP1L
        LDA sp+1
        TAP1H
        LDA #0
        JSR SYS_PUTS
        LDA #10
        JSR SYS_PUTC
        JMP h_lp
h_done: RTS


htab:   .word s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20,s21,s22,s23,s24,s25,s26,s27,0

s0 :    .asciiz "P8X/OS COMMANDS:"
s1 :    .asciiz "/d1           drive 1 is mounted here (cd /d1, cat /d1/FILE)"
s2 :    .asciiz "bootload file install file as the boot OS, then exit + B to run"
s3 :    .asciiz "cd path       change directory (/abs, rel, .., .)"
s4 :    .asciiz "del name      delete file(s)"
s5 :    .asciiz "exit / mon    return to the ROM monitor"
s6 :    .asciiz "format        erase card, make a fresh v2 volume (asks Y/N)"
s7 :    .asciiz "fsck          check filesystem integrity (read-only)"
s8 :    .asciiz "help          this help"
s9 :    .asciiz "load path     read a file to its load address"
s10:    .asciiz "make [target] build a target from the Makefile in the CWD"
s11:    .asciiz "man name      show a command's manual page (/man)"
s12:    .asciiz "graphics      tri/rotate/camera/cube/gl in /bin -- man gl, man basic"
s13:    .asciiz "desk / wdesk  the windowed GUI -- man wdesk"
s14:    .asciiz "mkdir path    create a subdirectory"
s15:    .asciiz "name args     run a program by bare name, found on PATH (/bin)"
s16:    .asciiz "pack          reclaim deleted space"
s17:    .asciiz "path [dirs]   show/set the program search path (default /bin)"
s18:    .asciiz "rmdir path    remove an empty subdirectory"
s19:    .asciiz "run path args load+run a program (args in P2, RTS to exit)"
s20:    .asciiz "save path s e save memory [s,e) to a new file"
s21:    .asciiz "sh file       run shell commands from a script file (streamed)"
s22:    .asciiz "umount/mount  swap the /d1 card: umount, swap, mount"
s23:    .asciiz "cmd >FILE     send output to FILE instead of the screen"
s24:    .asciiz "cmd <FILE     take input from FILE instead of the keyboard"
s25:    .asciiz "a | b         pipe a's output into b's input"
s26:    .asciiz "programs:     run /bin/basic.bin | edit.bin f | asm.bin s o"
s27:    .asciiz "  path=file/dir (drive 1 at /d1), s e a=hex, b=byte"

hp:     .fill 2
sp:     .fill 2
