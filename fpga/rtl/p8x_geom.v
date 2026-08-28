// p8x_geom.v -- the P8X graphics engine: the GL command port ($FF50) and
// the transform/clip/draw pipeline behind it.
//
// Stage 10 (STAGE10-DESIGN.md): a PGC-style graphics LANGUAGE. Bytes poked
// at GLDATA queue in a FIFO; the consumer FSM decodes hex-mode commands
// (opcode + int16-LE parameters) and executes each through the pipeline:
// S_MAC transform -> near/yon clip -> perspective -> window CS -> viewport
// map -> the display's own registers (gfx.v is unchanged; this module is
// still a hardware BASIC). 2D primitives skip transform and projection.
// Stage 10b adds the card-side matrices: MD*/VW* verbs compose submatrices
// (trig ROMs, muldiv datapath) into the combined parameter-file matrix at
// COMMAND time -- the per-vertex path never changed.
//
// The stage-8b/9 record interface ($FF40 GEUP/GECMD/GESEL) is RETIRED
// (stage 10b, for fabric): the GL language is the one hardware 3D path,
// and lib_g3d's GEID probe finds a floating bus and falls back to its
// software walk. The emulator's gl model is the golden model; tb_gl,
// tb_gl_pix and tb_gl_mpx pin this module against it.
//
// Pages: this module owns the framebuffer page state. draw_pg feeds
// gfx_mem (all pixels, CPU's included, and POINT's read-back); disp_pg
// feeds sdram_video. A flip (GL FLIP, opcode 02) waits for frame_tick,
// then: disp_pg <= draw_pg, draw_pg <= ~draw_pg -- the rule that makes
// the FIRST flip split the shared power-on page. GLSTAT bit6 holds busy
// through it; PGSYNC (03) rejoins the pages instantly.
//
// The gfx register port belongs to the engine while it draws (gm_own) --
// software must not race it; poll GLSTAT bit6, the house rule.
module p8x_geom (
  input             clk,
  input             rst,

  // The $FF40 record-engine register window is RETIRED (stage 10b): the
  // GL command port is the one interface. a/wdata serve the GL window.
  input      [3:0]  a,
  input      [7:0]  wdata,
  output reg [7:0]  rdata,

  // stage 10: the GL command port ($FF50-$FF57). gl_wr/gl_rd are the
  // strobes for that window; reads share the rdata mux via gl_sel.
  input             gl_sel,
  input             gl_wr,
  input             gl_rd,

  // SDRAM port (arbiter master g): stage-10c command lists -- the
  // recorder streams bytes in, the replayer streams them back out.
  output reg        g_req,
  output reg        g_we,
  output reg [22:0] g_addr,
  output reg [15:0] g_din,
  input             g_ack,
  input             g_ready,
  input      [15:0] g_dout,

  // gfx register master (p8x_top muxes this over the CPU while gm_own).
  output            gm_own,
  output reg        gm_wr,
  output reg        gm_rd,             // 10g: GDATA pops for pixel probes
  output reg [3:0]  gm_a,
  output reg [7:0]  gm_wdata,
  input      [7:0]  gm_rdata,

  // page state + the scanout's frame pulse
  input             frame_tick,
  output reg        draw_pg,
  output reg        disp_pg
);

  // ---- parameter file ------------------------------------------------------
  // 0-8 matrix m00..m22 (S7.8, row-major), 9-11 tx/ty/tz, 12 focal d,
  // 13-16 window, 17-20 viewport, 21 flags, 22 edge count,
  // 23 near plane, 24 far plane (stage 10b hither/yon; 16 / 32767 default).
  reg [15:0] par [0:24];

  // ---- walker state --------------------------------------------------------
  reg [7:0]  state;
  localparam S_IDLE=0,  S_NEXT=6,
             S_MAC=9,   S_MACW=10, S_MACB=105, S_MACC=106,
             W_LF=107,  W_LF2=108,
             S_NC=11,   S_NCW=12,  S_PRJ=13,  S_PRJW=14,
             S_CS=15,   S_CSW=16,  S_MAP=17,  S_MAPW=18,
             S_LIN=19,  S_LINB=20, S_LINC=21, S_FLIP=22,
             S_LIN2=24,
             // stage 9b: the TRI record
             T_NC=25,   T_NCA=26,  T_NI0=27,  T_NI0W=28, T_NI1=29,
             T_NI1W=30, T_CPY=31,  T_MP=32,   T_PJX=33,  T_PJXW=34,
             T_PJY=35,  T_PJYW=36, T_MX=37,   T_MXW=38,  T_MY=39,
             T_MYW=40,  T_PENW=41, T_FAN=42,  T_SRT1=43, T_SRT2=44,
             T_SRT3=45, T_DEG=46,  T_SY0=47,  T_SLOOP=48,T_SXA=49,
             T_SXAW=50, T_SXB=51,  T_SXBW=52, T_SPAN=53, T_BX=54,
             T_BXB=55,  T_BXC=56,  T_SNEXT=57,
             // stage 10: the GL box issuer (FLOOD/CLEARS/RECT fill) and
             // the RECT corner map -- walker states, launched by the GL
             // consumer below, so seq and the muldiv core are free
             W_BOX0=61, W_BOX1=62, W_BOX2=63, W_BOXW=64, W_BOXC=65,
             W_BOXD=66, W_RM=67,   W_RMW=68,  W_RC1=69,  W_RC2=70,
             // stage 10b: line far (yon) clip, TRI far pass, the matrix
             // COMPOSE microprogram, and CONVRT's projection tail
             S_FC=71,   S_FCW=72,
             F_CA=73,   F_I0=74,   F_I0W=75,  F_I1=76,   F_I1W=77, F_CP=78,
             C_NRM=79,  J_WR=80,   C_OGA=81,  C_OGW=82,
             C_MLA=83,  C_MLB=84,  C_CPA=85,  C_RCK=86,  C_RCKW=87,
             C_RCN=88,  CV_X=89,   CV_XW=90,  CV_YW=91,  J_RB3=109,
             // stage 10g: AREA/AREABC -- scanline boundary seed fill.
             // The emulator's gl_afill is the contract, step for step:
             // map the seed, push it, then pop/probe/span/paint/scan
             // with an SDRAM stack at $180000 (16384 entries; overflow
             // = error 8, deterministic partial fill).
             AF_MAP0=110, AF_MAP1=111, AF_MAP2=112, AF_MAP3=113,
             AF_L=114,    AF_R=115,
             AF_PT0=116,  AF_PT1=117,  AF_PT2=118,  AF_PT3=119,
             AF_SCAN=120, AF_SC1=121,  AF_SC2=122,
             AF_PU0=123,  AF_PU1=124,  AF_SKIP=125,
             AF_POP0=126, AF_POP1=127, AF_POP2=128, AF_CHK=129,
             // the shared pixel-probe subroutine (gm POINT + GDATA pops)
             AF_P0=130,   AF_P1=131,   AF_P2=132,   AF_P3=133,
             AF_P4=134,   AF_P5=135,   AF_P6=136,   AF_P7=137,
             AF_P8=138,   AF_P9=139,
             C_OGB=92,  C_OGC=93,  C_MTB=94,  C_MTC=95,  C_MLC=96,
             C_MLW=97,  C_CPB=98,  C_CPC=99,  J_RST2=100,
             // stage 10c: the polygon-lane (scratchpad) T-path states
             T_NIK=101, T_NIZ=102, F_CAF=103, F_IK=104;

  reg [15:0] rcol;                   // the GL pen (COLOR)
  reg        rfill;                  // T-path: FILL (GL fills always set it)
  reg        tri_m;                  // MAC writeback goes to tv (TRI mode)
  reg [2:0]  glfm;                   // 10f: LINFUN mode on its way to GMODE
  reg [3:0]  k;                      // fetch word / general microstep
  reg [15:0] tvx [0:2];              // TRI: transformed vertices
  reg [15:0] tvy [0:2];
  reg [15:0] tvz [0:2];
  reg [3:0]  np;                     // polygon vertex count
  reg [3:0]  g2n;                    // consumer state after a G_2D/G_3L load
  reg [15:0] f3x, f3y, f3z;          // G_3L: the staged vertices --
  reg [15:0] m3x, m3y, m3z;          //   first, second, (tri) third
  reg [15:0] t3x, t3y, t3z;
  reg        g3t;                    // loading a tri (9 words, fill)
  reg [15:0] fz [0:5];               // far-pass z scratch (was in v[])
  reg [3:0]  pp;                     // polygon iterator
  reg [3:0]  ft;                     // fan triangle index
  reg [15:0] nax, nay, naz;          // clip edge end A
  reg [15:0] nbx, nby, nbz;          // clip edge end B
  reg        nain, nbin;
  reg [15:0] cxv, cyv;               // map scratch
  reg [15:0] fx0, fy0, fx1, fy1, fx2, fy2;   // the fan triangle (sorted)
  reg [15:0] fy;                     // scanline
  reg [15:0] fxa, fxb;               // span ends
  reg [15:0] ox0, oy0, ox1, oy1;     // outline edge workspace
  reg [15:0] wx0, wy0, wz0, wx1, wy1, wz1;   // the working edge
  reg [15:0] px0, py0, px1, py1;     // mapped endpoints
  reg [1:0]  mp;                     // MAC: vertex 0/1
  reg [1:0]  mr;                     // MAC: output row 0..2
  reg [1:0]  mk;                     // MAC: term 0..2
  reg signed [31:0] acc;
  reg [3:0]  csn;                    // Cohen-Sutherland iteration bound
  reg [1:0]  mdph;                   // which muldiv of a 2/4-group is running
  reg        flip_pend;
  reg [2:0]  seq;                    // register-write microstep

  // ---- stage 10: the GL command port (STAGE10-DESIGN.md) -------------------
  // A byte FIFO the CPU can fill at ANY time (that is its whole point);
  // the consumer FSM below decodes hex-mode commands and executes them
  // through the walker's own pipeline states, one primitive at a time.
  reg [7:0]  cf [0:31];              // command FIFO (poll GLSTAT bit7)
  reg [5:0]  cf_wp, cf_rp;
  wire [5:0] cf_cnt  = cf_wp - cf_rp;
  wire       cf_ne   = (cf_cnt != 6'd0);
  wire       cf_full = cf_cnt[5];
  reg [7:0]  ef [0:7];               // error FIFO: 1 unknown opcode,
  // stage 10e: the read-back FIFO (GLRB pops it; GLSTAT bit0 = has byte).
  // 32 bytes distributed; producers STALL on full (busy holds -- the CPU
  // drains with GLRD / gl's printer, never inside GCHECK's wait).
  reg [7:0]  rbf [0:31];
  reg [5:0]  rb_wp, rb_rp;
  reg [9:0]  rbp_a;                  // pusher: next lane, words left
  reg [3:0]  rbp_n;
  reg        wvk;                    // G_WV tail: relaunch the K recompose
  reg [5:0]  rd_slot;                // CLRD/CLMOD: the slot
  reg [12:0] rdo;                    // CLRD: byte offset / CLMOD: target
  reg [13:0] rdn;                    // CLRD: bytes still to push
  reg [7:0]  rd_lo, rd_hi;           // fetched halfword
  reg        jrbs;                   // J_WR leg: RBS defaults, not a matrix
  reg        rcph;                   // C_RCN: which plane this cycle
  // ---- stage 10g: the fill's working set ---------------------------------
  reg [15:0] afbc;                   // boundary colour (pen for AREA)
  reg [8:0]  afx, afy;               // popped seed (screen space)
  reg [8:0]  afL, afR;               // the probed span
  reg [8:0]  afi, afrow;             // above/below scan cursor
  reg [8:0]  apx, apy;               // probe target
  reg [14:0] afsp;                   // stack pointer (cap 16384)
  reg        afovf;                  // afsp hit the cap
  reg        afrsel;                 // 0 = row y-1, 1 = row y+1
  reg [15:0] afpv;                   // probed pixel value
  reg [3:0]  afret;                  // probe return: 0 seed 1 chk 2 L
                                     //   3 R 4 scan 5 skip
  // the verdict, exactly gl_af_in's: neither boundary nor already-painted
  wire af_in = (afpv != afbc) && (afpv != rcol);
  wire af_g  = (state >= AF_MAP0 && state <= AF_P9);  // fill owns the g port
  reg [3:0]  ef_wp, ef_rp;           //   2 bad parameter, 3 mode not
  wire       rb_ne   = (rb_wp != rb_rp);
  wire [12:0] mdba   = 13'd2 + rdo;  // CLMOD: target byte's file offset
  wire       rb_full = (rb_wp - rb_rp == 6'd32);
  wire       ef_ne = (ef_wp != ef_rp);  // fitted, 4 FIFO overflow, 5
                                        // nesting, 6 undefined, 7 full
  // ---- stage 10d: the ASCII translator (STAGE10-DESIGN.md) ---------------
  // A tokenizer between the FIFO and the consumer, active in ASCII mode:
  // keywords match against the ROM at scratch word 128+ (long and short
  // forms), numbers accumulate decimal; output is hex bytes in a small
  // queue the consumer drains as its byte source. It runs only while the
  // walker and consumer are idle, so the scratchpad ports are free.
  reg        glmode;                 // 0 = hex, 1 = ASCII
  reg [7:0]  tq [0:3];               // translated-byte queue
  reg [2:0]  tq_wp, tq_rp;
  wire       tq_ne = (tq_wp != tq_rp);
  wire [2:0] tq_cnt = tq_wp - tq_rp;
  reg [7:0]  wb0, wb1, wb2, wb3, wb4, wb5;   // keyword accumulator
  reg [2:0]  wn;
  reg [15:0] tnv;                    // number accumulator
  reg        tneg, thas;
  reg [7:0]  t_op;                   // active verb state (t_*)
  reg [1:0]  t_bcnt;
  reg [9:0]  t_left;                 // params left (255 verts * 3 max)
  reg        t_var, t_act, t_skip;
  reg [1:0]  t_vw;
  reg [4:0]  t_pi;
  reg [6:0]  t_ent;                  // ROM entry cursor
  reg [1:0]  t_k;                    // fetch microstep
  reg [15:0] t_w0, t_w1, t_w2;       // fetched entry chars
  reg [2:0]  ast;                    // translator FSM
  localparam A_IDLE=0, A_M0=1, A_M1=2, A_M2=3, A_ACT=4, A_ZF=5;

  reg [7:0]  glop;                   // opcode being executed
  reg [7:0]  pbuf [0:23];            // fixed parameter bytes (max: MDMATX 24)
  reg [4:0]  pi, pneed;
  reg [7:0]  glnv;                   // POLY: vertices still to stream
  reg        glpoly3, glpfill;       // POLY: 3D flavour / fill path
  reg [1:0]  glph;                   // POLY: 0 first vertex, 1 second, 2 rest
  reg [1:0]  gred;                   // RECT outline: which edge
  reg [15:0] c2x, c2y, c3x, c3y, c3z;   // the 2D and 3D current points
  reg [15:0] vfx, vfy, vfz;          // POLY: the FIRST vertex (fan root)
  reg [15:0] vpx, vpy, vpz;          // POLY: the PREVIOUS vertex
  reg        glfill;                 // PRMFIL
  reg [15:0] glproj, gldist;         // PROJCT angle / DISTAN viewer distance
  // stage 10b: the two master matrices and the compose engine's workspace.
  // Verbs recompose the parameter file at COMMAND time -- the per-vertex
  // datapath never changes (STAGE10-DESIGN.md).
  // The two master matrices and the compose workspace live in ONE small
  // 1W2R scratchpad (a mirrored distributed-RAM pair) instead of 45
  // registers with computed-index muxes -- those muxes were ~1.5k LUT
  // sites, the reason 10b would not place. Layout: M 0-11, VR 16-24,
  // MS (submatrix) 32-43, CT (product) 48-59. Reads are registered
  // twice (address reg, then q reg): set the address, wait a state,
  // consume -- compose runs at command time, so latency is free.
  // 128 deep since stage 10c: the T-path's POLYGON arrays moved in too
  // (the same registered-read discipline; their indexed muxes were the
  // walker's largest remaining register file). Lanes: qx 64, qy 72,
  // qz 80, mapped-x 88, mapped-y 96 (8 apiece).
  // ONE true-dual-port BSRAM: port A is write-else-read (the FSM is
  // single-threaded and never captures a port-A read in a cycle it
  // writes -- reads latch on the bubble cycle before, and cm_qa HOLDS
  // through a write), port B is read-only. A mirrored pair cost either
  // 2 BSRAM (46/46, exact-fit killed placement) or ~700 LUT distributed.
  reg [15:0] cmx [0:1023];        // one BSRAM block: scratch + keyword ROM
  reg [9:0]  cm_aa, cm_ab;           // read addresses
  reg [15:0] cm_qa, cm_qb;           // registered read data
  reg        cm_we;
  reg [9:0]  cm_wa;
  reg [15:0] cm_wd;
  integer ii;
  initial begin                      // power-on: both masters identity
    for (ii = 0; ii < 1024; ii = ii + 1) cmx[ii] = 0;
    cmx[769] = 16'hFFFF;            // COLOR: white pen
    cmx[770] = 16'hFFFF;            // PROJCT: native focal
    cmx[780] = 16'd16;              // near plane
    cmx[781] = 16'd32767;           // far: disabled
    cmx[0]=16'd256;  cmx[4]=16'd256;  cmx[8]=16'd256;
    cmx[16]=16'd256; cmx[20]=16'd256; cmx[24]=16'd256;
    // stage 10d: the ASCII keyword ROM, generated by gen_glkw.py
`include "glkwtab.vh"
  end
  always @(posedge clk) begin
    if (cm_we) cmx[cm_wa] <= cm_wd;
    else cm_qa <= cmx[cm_aa];
    cm_qb <= cmx[cm_ab];
  end
  localparam [6:0] MB=7'd0, VB=7'd16, SB=7'd32, TB=7'd48,
                   LQX=7'd64, LQY=7'd72, LQZ=7'd80, LSX=7'd88, LSY=7'd96,
                   LVV=7'd112;      // the working vertices (was reg v[0:8])
  // stage 10e: FLAGRD's state mirror, above the keyword ROM (ends ~609).
  // Setters mirror into these lanes as they execute; read-back is then
  // one lane walk shared with MATXRD. +0 PRMFIL +1 COLOR +2 PROJCT
  // (FFFF = native) +3 DISTAN +4..7 WINDOW +8..11 VWPORT +12 near +13 far
  localparam [9:0] RBS = 10'd768;  // FIXED, clear of keyword-ROM growth
                                   // (ROM start 128, 4 words/entry: 124
                                   // entries end at 625; alarms below)
  reg [15:0] glvrp [0:2];            // VWRPT reference point
  reg [15:0] glorg [0:2];            // MDORG pivot
  reg [15:0] glh, glyy;              // DISTH / DISTY plane distances
  reg        glch, glcy, glpmode;    // CLIPH / CLIPY / PROJCT-drives-K
  reg [3:0]  jcnt;                   // scratch-writer job: cell index,
  reg [2:0]  jsrc;                   //   source (0 ident, 1 rot, 2 scal,
  reg [5:0]  jbase;                  //   3 tran, 4 pbuf), base, last
  reg [3:0]  jlast;                  //   cell, and the state after
  reg [6:0]  jnext;
  reg        mtf;                    // T-column ms[9+ci] prefetched...
  reg [15:0] msT;                    //   ...into here
  reg [15:0] ang;                    // rotation angle, normalized 0..359
  reg [1:0]  cax;                    // rotation axis 0/1/2
  reg        vwf;                    // composing into VR (else into M)
  reg [1:0]  cmode;                  // 0 ms*M->M  1 ms*VR->VR  2 VR*M->par
  reg [1:0]  ci, cj, ck;             // multiply loop: row / col (3=T) / term
  reg [15:0] csum;                   // int16 wrap accumulator
  reg [3:0]  cpi;                    // copy index
  reg        glcvt;                  // CONVRT: capture projection, no draw
  // far-pass polygon (TRI yon clip) vertex count; the pass writes into
  // the mapped lanes + v[0:7] (idle at that stage) and copies back
  reg [3:0]  nq2;
  reg        glact;                  // pipeline exit returns to S_IDLE
  reg        gl2d;                   // suppress projection in the T-map
  reg [1:0]  glcls;                  // CLEARS page phase (0 = plain box)
  reg [4:0]  glst;                   // consumer FSM
  reg [15:0] wcnt;                   // WAIT frames remaining
  reg [15:0] gbx0, gby0, gbx1, gby1, gbcol;    // the box issuer's box
  localparam G_OP=0, G_PRM=1, G_RUN=2, G_PV=3, G_PRUN=4, G_PCLOSE=5,
             G_WAIT=6, G_RE=7,
             // stage 10c: CLEND finish, CLAPP length read, CLRUN start
             G_LE0=8, G_LE1=9, G_LE2=10, G_AL0=11, G_AL1=12,
             G_RL0=13, G_RL1=14, G_2D=15,
             // stage 10d diet: 3D vertex loader -- stream the staged f3/m3
             // (/t3) words into the LVV scratchpad lanes, then launch S_MAC
             G_3L=16,
             // stage 10e: read-back -- the lane-walk pusher (FLAGRD/MATXRD),
             // the WINDOW/VWPORT mirror loader, the CLRD streamer and the
             // CLMOD read-modify-write
             G_RBP=17, G_WV=18,
             G_RD0=19, G_RD1=20, G_RD2=21, G_RD3=22,
             G_MD0=23, G_MD1=24, G_MD2=25, G_MD3=26;

  // ---- stage 10c: COMMAND LISTS (STAGE10-DESIGN.md) ----------------------
  // 64 lists in 4KB SDRAM slots at CL_BASE + n*4096: byte length in the
  // slot's first halfword, stream from byte 2. Recording rides the
  // decoder's byte pops (execution suppressed, bytes paired into
  // halfword writes); replay switches the consumer's byte SOURCE to a
  // fetcher walking the slot. One SDRAM op in flight (sd_busy).
  localparam [22:0] CL_BASE = 23'h100000;
  reg [63:0]  cldef;                 // the DEFINED bitmap
  reg         rec;                   // recording into rec_slot
  reg [5:0]   rec_slot;
  reg [12:0]  rec_len;               // bytes stored so far
  reg [7:0]   rec_lo;                // byte-pair latch
  reg         rskip;                 // consume one command, store/run nothing
  reg         rp;                    // replaying from rp_slot
  reg [5:0]   rp_slot;
  reg [12:0]  rp_off, rp_len;
  reg [15:0]  rp_cnt;                // CLOOP passes remaining
  reg [7:0]   rpb0, rpb1;            // replay byte buffer
  reg [1:0]   rp_have;
  reg         fst;                   // fetcher: 0 idle, 1 read in flight
  reg         sd_busy;               // one SDRAM op outstanding
  // the consumer's byte source: the command FIFO, or the replay buffer
  wire [7:0]  srcb   = rp ? rpb0 : (glmode ? tq[tq_rp[1:0]] : cf[cf_rp[4:0]]);
  wire        src_ne = rp ? (rp_have != 2'd0) : (glmode ? tq_ne : cf_ne);
  // opcode -> fixed parameter-byte count (the emulator's gl_cmdlen as a
  // wire; POLY 30-33 report their 1-byte header, vertices stream after)
  reg [4:0] opn; reg opok;
  always @(*) begin
    opok = 1'b1; opn = 5'd0;
    case (srcb)
      8'h01,8'h02,8'h03,8'h04,8'h08,8'h09,8'h90,8'hA0,8'hAF,8'h71: opn = 5'd0;
8'hE0,8'hAA,8'hAB,8'h70,8'h72,8'h74,8'h79,8'hEB,
      8'h61,8'h62,8'h76: opn = 5'd1;
      8'h78: opn = 5'd4;               // CLMOD n b off
      8'hC0: opn = 5'd0;
      8'hC1: opn = 5'd3;               // AREABC r g b
      8'h05,8'h43,8'h93,8'h94,8'h95,8'hA3,8'hA4,8'hA5,
      8'hA8,8'hA9,8'hB0,8'hB1: opn = 5'd2;
      8'h06,8'h07,8'h0F,8'h73: opn = 5'd3;
      8'h10,8'h11,8'h28,8'h29,8'h34,8'h35: opn = 5'd4;
      8'h12,8'h13,8'h2A,8'h2B,8'h91,8'h92,8'h96,8'hA1: opn = 5'd6;
      8'hB2,8'hB3: opn = 5'd8;
      8'hA7: opn = 5'd18;
      8'h97: opn = 5'd24;
      8'h30,8'h31,8'h32,8'h33: opn = 5'd1;
      default: opok = 1'b0;
    endcase
  end
  // 1MB base / 4KB slots are aligned and the recorder aborts at >=4092,
  // so the in-slot offset never carries: the address is a concat
  wire [11:0] rec_off = {rec_len[11:1], 1'b0} + 12'd2;
  wire [22:0] rec_wa = {2'd0, 1'b1, 2'd0, rec_slot, rec_off};
  wire [15:0] pw0 = {pbuf[1], pbuf[0]};        // little-endian int16 params
  wire [15:0] pw1 = {pbuf[3], pbuf[2]};
  wire [15:0] pw2 = {pbuf[5], pbuf[4]};
  wire [15:0] pw3 = {pbuf[7], pbuf[6]};
  wire [15:0] prgb = {pbuf[0][4:0], pbuf[1][5:0], pbuf[2][4:0]};  // r g b
  // POLY vertex, with the R-variants' current-point offset applied
  wire [15:0] pvx = glop[0] ? (pw0 + (glpoly3 ? c3x : c2x)) : pw0;
  wire [15:0] pvy = glop[0] ? (pw1 + (glpoly3 ? c3y : c2y)) : pw1;
  wire [15:0] pvz = glop[0] ? (pw2 + c3z) : pw2;
  // dispatch gate: the walker must be idle and the CPU must not be
  // starting record work this very cycle (its write would be lost)
  wire gl_can = (state == S_IDLE);

  assign gm_own = (state != S_IDLE) && (state != S_FLIP);


  // ---- the shared arithmetic ----------------------------------------------
  reg         md_go;
  // muldiv operands arrive as raw pairs; THREE shared subtractors form
  // the differences (was: every FSM arm carrying its own 16-bit subtract)
  reg  [15:0] md_a1, md_a2, md_b1, md_b2, md_c1, md_c2;
  wire [15:0] md_a = md_a1 - md_a2;
  // ONE shared post-adder forms every X +/- md_q apply (base loaded at
  // launch time; md_rn selects subtract)
  reg  [15:0] md_r;
  reg         md_rn;
  wire [15:0] md_b = md_b1 - md_b2;
  wire [15:0] md_c = md_c1 - md_c2;
  wire [15:0] md_q;
  wire [15:0] md_qr = md_rn ? md_r - md_q : md_r + md_q;
  wire        md_busy;
  mdu_core MD(.clk(clk), .rst(rst), .go(md_go),
              .a(md_a), .b(md_b), .c(md_c), .q(md_q), .busy(md_busy));
  wire md_done = !md_busy && !md_go;

  // stage 10b compose-engine operands and helpers. The trig ROMs are the
  // generated trigtab.v modules -- gen_trig.py keeps them and the
  // emulator's tables identical entry for entry.
  wire [8:0]  cosidx = ($signed(ang) >= 16'sd270) ? ang[8:0] - 9'd270
                                                  : ang[8:0] + 9'd90;
  wire signed [15:0] sinq, cosq, tanq;
  trig_sin  TSIN(.clk(clk), .d(ang[8:0]), .d2(cosidx), .q(sinq), .q2(cosq));
  trig_tanh TTAN(.clk(clk), .a(glproj[7:0]), .q(tanq));
  wire [15:0] cvz = ($signed(wz0) < $signed(par[23])) ? par[23]
                  : ($signed(par[24]) < $signed(wz0)) ? par[24] : wz0;
  wire [1:0]  cjmax = (cmode == 2'd1) ? 2'd2 : 2'd3;
  // aligned-lane addressing: the scratchpad bases are 8/16-aligned and no
  // offset crosses its window, so every address below is a concat, not an
  // add. Only these little 4-bit in-window offsets keep real adders.
  wire [3:0] mpk  = {2'd0, mp} * 3'd3 + {2'd0, mk};   // vertex word mp*3+mk
  wire [3:0] cick = {2'd0, ci} * 3'd3 + {2'd0, ck};   // matrix cell ci*3+ck
  wire [3:0] ckcj = {2'd0, ck} * 3'd3 + {2'd0, cj};
  wire [3:0] cicj = {2'd0, ci} * 3'd3 + {2'd0, cj};
  wire [3:0] c9i  = 4'd9 + {2'd0, ci};                // T column 9+ci
  wire [3:0] c9k  = 4'd9 + {2'd0, ck};
  // the finished element, with the T-column tails folded in (msT is the
  // prefetched ms[9+ci]; operands themselves arrive through cm_qa/cm_qb)
  wire [15:0] cm_res = md_qr
       + ((cj == 2'd3 && cmode == 2'd0) ? msT : 16'd0)
       + ((cj == 2'd3 && cmode == 2'd2 && ci == 2'd2) ? gldist : 16'd0);
  // the scratch-writer's cell value, by job source
  wire [15:0] jrot =
      (cax == 2'd0) ? ((jcnt==4'd0)?16'd256:(jcnt==4'd4)?cosq:
                       (jcnt==4'd5)?-sinq:(jcnt==4'd7)?sinq:
                       (jcnt==4'd8)?cosq:16'd0)
    : (cax == 2'd1) ? ((jcnt==4'd0)?cosq:(jcnt==4'd2)?sinq:
                       (jcnt==4'd4)?16'd256:(jcnt==4'd6)?-sinq:
                       (jcnt==4'd8)?cosq:16'd0)
    :                 ((jcnt==4'd0)?cosq:(jcnt==4'd1)?-sinq:
                       (jcnt==4'd3)?sinq:(jcnt==4'd4)?cosq:
                       (jcnt==4'd8)?16'd256:16'd0);
  wire [15:0] jval =
      (jsrc == 3'd0) ? ((jcnt==4'd0||jcnt==4'd4||jcnt==4'd8)?16'd256:16'd0)
    : (jsrc == 3'd1) ? jrot
    : (jsrc == 3'd2) ? ((jcnt==4'd0)?pw0:(jcnt==4'd4)?pw1:
                        (jcnt==4'd8)?pw2:16'd0)
    : (jsrc == 3'd3) ? ((jcnt==4'd0||jcnt==4'd4||jcnt==4'd8)?16'd256:
                        (jcnt==4'd9)?pw0:(jcnt==4'd10)?pw1:
                        (jcnt==4'd11)?pw2:16'd0)
    :                  {pbuf[{jcnt,1'b1}], pbuf[{jcnt,1'b0}]};
  wire        z0_far = $signed(wz0) > $signed(par[24]);
  wire        z1_far = $signed(wz1) > $signed(par[24]);

  // MAC operand select: the matrix element is a par[] mux; the vertex
  // arrives through the scratchpad's port B (set at S_MAC, consumed two
  // cycles later at S_MACC -- the lane pipeline)
  wire [15:0] mac_m = par[{2'd0, mr} * 3 + {2'd0, mk}];
  wire signed [31:0] mac_p = $signed(mac_m) * $signed(cm_qb);
  wire signed [31:0] acc_sh = acc >>> 8;
  wire [15:0] mac_res = acc_sh[15:0] + par[9 + {2'd0, mr}];

  // outcodes of the working endpoints against the window (combinational,
  // recomputed every CS iteration exactly as the software recomputes them)
  wire [3:0] oca = { $signed(wy0) > $signed(par[16]),
                     $signed(wy0) < $signed(par[14]),
                     $signed(wx0) > $signed(par[15]),
                     $signed(wx0) < $signed(par[13]) };
  wire [3:0] ocb = { $signed(wy1) > $signed(par[16]),
                     $signed(wy1) < $signed(par[14]),
                     $signed(wx1) > $signed(par[15]),
                     $signed(wx1) < $signed(par[13]) };

  wire z0_near = $signed(wz0) < $signed(par[23]);
  wire z1_near = $signed(wz1) < $signed(par[23]);

  // TRI helpers: screen-space outcodes against the VIEWPORT (outlines),
  // span min/max, and the degenerate triangle's x extremes
  wire [3:0] soa = { $signed(oy0) > $signed(par[20]),
                     $signed(oy0) < $signed(par[18]),
                     $signed(ox0) > $signed(par[19]),
                     $signed(ox0) < $signed(par[17]) };
  wire [3:0] sob = { $signed(oy1) > $signed(par[20]),
                     $signed(oy1) < $signed(par[18]),
                     $signed(ox1) > $signed(par[19]),
                     $signed(ox1) < $signed(par[17]) };
  wire fy_in = !($signed(fy) < $signed(par[18])) &&
               !($signed(par[20]) < $signed(fy));
  wire [15:0] sp_lo = ($signed(fxa) < $signed(fxb)) ? fxa : fxb;
  wire [15:0] sp_hi = ($signed(fxa) < $signed(fxb)) ? fxb : fxa;
  wire [15:0] sp_l  = ($signed(sp_lo) < $signed(par[17])) ? par[17] : sp_lo;
  wire [15:0] sp_r  = ($signed(par[19]) < $signed(sp_hi)) ? par[19] : sp_hi;
  wire        sp_ok = !($signed(sp_r) < $signed(sp_l));
  wire [15:0] dg_a  = ($signed(fx0) < $signed(fx1)) ? fx0 : fx1;
  wire [15:0] dg_lo = ($signed(dg_a) < $signed(fx2)) ? dg_a : fx2;
  wire [15:0] dg_b  = ($signed(fx0) < $signed(fx1)) ? fx1 : fx0;
  wire [15:0] dg_hi = ($signed(dg_b) < $signed(fx2)) ? fx2 : dg_b;

  task temit(input [15:0] v);        // one translated parameter, right
    begin                            //   width, with verb bookkeeping
      if (t_pi < {3'd0, t_bcnt}) begin
        tq[tq_wp[1:0]] <= v[7:0]; tq_wp <= tq_wp + 3'd1;
      end else begin
        tq[tq_wp[1:0]] <= v[7:0];
        tq[tq_wp[1:0] + 2'd1] <= v[15:8];
        tq_wp <= tq_wp + 3'd2;
      end
      if (t_var && t_pi == 5'd0) begin // the POLY count byte: vertices next
        t_left <= (t_vw == 2'd3) ? ({1'b0, v[7:0], 1'b0} + {2'd0, v[7:0]})
                                 : {1'b0, v[7:0], 1'b0};
        if (v[7:0] == 8'd0) t_act <= 0;
      end else begin
        t_left <= t_left - 10'd1;
        if (t_left == 10'd1) t_act <= 0;
      end
      if (t_pi != 5'd31) t_pi <= t_pi + 5'd1;
    end
  endtask

  task epush(input [7:0] c);         // one error byte, FIFO-full safe
    begin
      if (ef_wp - ef_rp != 4'd8) begin
        ef[ef_wp[2:0]] <= c; ef_wp <= ef_wp + 4'd1;
      end
    end
  endtask

  integer i;
  always @(posedge clk) begin
    md_go <= 1'b0;
    gm_wr <= 1'b0;
    gm_rd <= 1'b0;
    cm_we <= 1'b0;
    if (rst) begin
      state <= S_IDLE;
      draw_pg <= 0; disp_pg <= 0; flip_pend <= 0;
      seq <= 0; mdph <= 0; csn <= 0;
      tri_m <= 0; rfill <= 0; np <= 0; pp <= 0; ft <= 0;
      cf_wp <= 0; cf_rp <= 0; ef_wp <= 0; ef_rp <= 0;
      rb_wp <= 0; rb_rp <= 0; jrbs <= 0; wvk <= 0; rcph <= 0;
      glst <= G_OP; glop <= 0; pi <= 0; pneed <= 0; glnv <= 0;
      cldef <= 64'd0; rec <= 0; rskip <= 0; rp <= 0; rp_have <= 0;
      glmode <= 0; tq_wp <= 0; tq_rp <= 0; wn <= 0; tnv <= 0;
      tneg <= 0; thas <= 0; t_act <= 0; t_skip <= 0; ast <= A_IDLE;
      t_ent <= 0; t_k <= 0;
      fst <= 0; sd_busy <= 0; g_req <= 0; g_we <= 0;
      rec_len <= 0; rp_off <= 0; rp_len <= 0; rp_cnt <= 0;
      glpoly3 <= 0; glpfill <= 0; glph <= 0; gred <= 0;
      c2x <= 0; c2y <= 0; c3x <= 0; c3y <= 0; c3z <= 0;
      glfill <= 0; glproj <= 16'd60; gldist <= 16'd500;
      glact <= 0; gl2d <= 0; glcls <= 0; wcnt <= 0; glfm <= 0;
      rcol <= 16'hFFFF;                                     // GL pen: white
      par[0] <= 16'd256; par[4] <= 16'd256; par[8] <= 16'd256;  // identity
      par[1]<=0; par[2]<=0; par[3]<=0; par[5]<=0; par[6]<=0; par[7]<=0;
      par[9]<=0; par[10]<=0; par[11]<=0;
      par[12] <= 16'd256;                                        // focal
      par[13]<=0; par[14]<=0; par[15]<=0; par[16]<=0;
      par[17]<=0; par[18]<=0; par[19]<=0; par[20]<=0;
      par[21] <= 16'd3;                                          // erase+flip
      par[22] <= 0;
      par[23] <= 16'd16;                 // near plane (the stage-7..9 z>=16)
      par[24] <= 16'd32767;              // far plane: int16 max = no yon clip
      glvrp[0]<=0; glvrp[1]<=0; glvrp[2]<=0;
      glorg[0]<=0; glorg[1]<=0; glorg[2]<=0;
      glh <= 0; glyy <= 0; glch <= 0; glcy <= 0; glpmode <= 0;
      ang <= 0; cax <= 0; vwf <= 0; cmode <= 0;
      ci <= 0; cj <= 0; ck <= 0; csum <= 0; cpi <= 0; nq2 <= 0;
      glcvt <= 0; mtf <= 0;
      gldist <= 0;                       // dist 0 = the stage-9 camera
      // the scratchpad is initial-block clean at power-on; a WARM reset
      // (button) re-identities both masters through the writer job
      jsrc <= 0; jbase <= MB; jlast <= 4'd11; jcnt <= 0; jnext <= J_RST2;
      state <= J_WR;
    end else begin

      // ---- stage 10: GL port accesses (any time -- that is the point) ------
      if (gl_wr && a[2:0] == 3'd0) begin           // GLDATA: push one byte
        if (cf_full) begin
          if (ef_wp - ef_rp != 4'd8) begin ef[ef_wp[2:0]] <= 8'd4;
                                            ef_wp <= ef_wp + 4'd1; end
        end else begin
          cf[cf_wp[4:0]] <= wdata;
          cf_wp <= cf_wp + 6'd1;
        end
      end
      if (gl_rd && a[2:0] == 3'd3 && ef_ne)        // GLERR read pops
        ef_rp <= ef_rp + 4'd1;
      if (gl_rd && a[2:0] == 3'd2 && rb_ne)        // GLRB read pops (10e)
        rb_rp <= rb_rp + 6'd1;

      // ---- stage 10c: SDRAM op completion + the replay fetcher ------------
      if (g_req && g_ack) begin
        g_req <= 0;
        if (g_we) begin g_we <= 0; sd_busy <= 0; end
      end
      if (g_ready) sd_busy <= 0;         // read data valid this cycle

      case (fst)
        1'b0: if (rp && rp_have == 2'd0 && !sd_busy && !g_req &&
                  glst != G_RL1 && !(glst >= G_RD0 && glst <= G_MD3) &&
                  !af_g) begin
          if (rp_off >= rp_len) begin    // a pass ended at a boundary
            if (rp_cnt <= 16'd1) rp <= 0;
            else begin rp_cnt <= rp_cnt - 16'd1; rp_off <= 0; end
          end else begin
            g_addr <= {2'd0, 1'b1, 2'd0, rp_slot,
                       {rp_off[11:1], 1'b0} + 12'd2};
            g_we <= 0; g_req <= 1; sd_busy <= 1; fst <= 1'b1;
          end
        end
        1'b1: if (g_ready) begin
          rpb0 <= g_dout[7:0]; rpb1 <= g_dout[15:8];
          rp_have <= (rp_len - rp_off >= 13'd2) ? 2'd2 : 2'd1;
          fst <= 1'b0;
        end
      endcase

      // ---- stage 10d: the ASCII translator --------------------------------
      // Runs only while everything downstream is drained and idle, so the
      // scratchpad's ports (the keyword ROM lives at word 128+) are free.
      case (ast)
        A_IDLE: if (glmode && !rp && cf_ne && !tq_ne) begin : atok
          reg [7:0] b;
          b = cf[cf_rp[4:0]];
          cf_rp <= cf_rp + 6'd1;
          if (b >= 8'h61 && b <= 8'h7A) b = b - 8'h20;   // fold case
          if (b == 8'h20 || b == 8'h09 || b == 8'h2C ||
              b == 8'h3B || b == 8'h0D || b == 8'h0A) begin
            if (wn != 3'd0) begin t_ent <= 0; t_k <= 0; ast <= A_M0; end
            else if (thas) begin                          // finish a number
              if (!t_act) begin
                if (!t_skip) epush(8'd2);                 // orphaned number
              end else temit(tneg ? (16'd0 - tnv) : tnv);
              tnv <= 0; tneg <= 0; thas <= 0;
            end
          end else if (wn != 3'd0) begin                  // inside a keyword
            case (wn)
              3'd1: wb1 <= b;  3'd2: wb2 <= b;  3'd3: wb3 <= b;
              3'd4: wb4 <= b;  default: wb5 <= b;
            endcase
            if (wn != 3'd6) wn <= wn + 3'd1;
          end else if (thas || b == 8'h2D ||
                       (b >= 8'h30 && b <= 8'h39)) begin  // a number
            if (b == 8'h2D && !thas) begin tneg <= 1; thas <= 1; end
            else if (b >= 8'h30 && b <= 8'h39) begin
              tnv <= {tnv[12:0], 3'd0} + {tnv[14:0], 1'd0} + {12'd0, b[3:0]};
              thas <= 1;
            end else begin                                // junk in a number
              epush(8'd2); tnv <= 0; tneg <= 0; thas <= 0;
            end
          end else if (b >= 8'h41 && b <= 8'h5A) begin    // a keyword starts
            wb0 <= b; wb1 <= 8'h20; wb2 <= 8'h20;
            wb3 <= 8'h20; wb4 <= 8'h20; wb5 <= 8'h20;
            wn <= 3'd1;
          end else epush(8'd2);                           // stray byte
        end

        // match the keyword: fetch each ROM entry (4 halfwords at
        // 128 + entry*4) through port A, compare, walk on mismatch
        // the matcher reads the keyword ROM through port A: wait for the
        // walker (and the G_2D/G_3L loaders) to leave the scratchpad alone
        A_M0: if (state == S_IDLE && glst < G_2D) begin
          cm_aa <= 10'd128 + {1'd0, t_ent, 2'd0} + {8'd0, t_k};
          ast <= A_M1;
        end
        A_M1: ast <= A_M2;
        A_M2: begin
          case (t_k)
            2'd0: begin
              if (cm_qa == 16'd0) begin                   // table end: unknown
                epush(8'd1);
                if (t_act) begin epush(8'd2); ast <= A_ZF; t_skip <= 1; end
                else begin t_skip <= 1; wn <= 0; ast <= A_IDLE; end
                t_op <= 8'h00;                            // no verb to start
              end else if (cm_qa != {wb0, wb1}) begin
                t_ent <= t_ent + 7'd1; t_k <= 0; ast <= A_M0;
              end else begin t_k <= 2'd1; ast <= A_M0; end
            end
            2'd1: begin
              if (cm_qa != {wb2, wb3}) begin
                t_ent <= t_ent + 7'd1; t_k <= 0; ast <= A_M0;
              end else begin t_k <= 2'd2; ast <= A_M0; end
            end
            2'd2: begin
              if (cm_qa != {wb4, wb5}) begin
                t_ent <= t_ent + 7'd1; t_k <= 0; ast <= A_M0;
              end else begin t_k <= 2'd3; ast <= A_M0; end
            end
            default: begin                                // the meta word
              wn <= 0;
              if (cm_qa[7:0] == 8'hFE) begin ast <= A_IDLE; end      // CA
              else if (cm_qa[7:0] == 8'hFF) begin
                glmode <= 0; ast <= A_IDLE;                          // CX
              end else begin
                t_op <= cm_qa[7:0];
                t_w0 <= cm_qa;                            // hold the meta
                if (t_act) begin epush(8'd2); t_skip <= 0; ast <= A_ZF; end
                else begin t_skip <= 0; ast <= A_ACT; end
              end
            end
          endcase
        end

        A_ZF: begin                    // early keyword: zero-fill the rest
          if (!t_act) ast <= t_skip ? A_IDLE : A_ACT;
          else if (tq_cnt <= 3'd2) temit(16'd0);
        end

        A_ACT: if (tq_cnt <= 3'd3) begin                  // start the verb
          tq[tq_wp[1:0]] <= t_op; tq_wp <= tq_wp + 3'd1;
          t_bcnt <= t_w0[9:8];
          t_var  <= t_w0[14];
          t_vw   <= t_w0[14] ? (t_op[1] ? 2'd3 : 2'd2) : 2'd0;
          t_left <= t_w0[14] ? 10'd1 : {6'd0, t_w0[13:10]};
          t_pi   <= 0;
          t_act  <= (t_w0[14] || t_w0[13:10] != 4'd0);
          ast <= A_IDLE;
        end
      endcase

      // ---- the walker ------------------------------------------------------
      case (state)
        S_IDLE: ;

        // every GL primitive exits here; the record loop is retired
        S_NEXT: begin
          glact <= 0; gl2d <= 0;
          state <= S_IDLE;
        end

        // transform: acc = m[r][0..2] . v[p], then w = (acc>>>8) + t
        S_MAC: begin                   // aim port B at v[mp*3+mk]...
          cm_ab <= {6'd7, mpk};                    // LVV + mp*3 + mk
          state <= S_MACB;
        end
        S_MACB: state <= S_MACC;       // ...the read pipeline's bubble...
        S_MACC: begin                  // ...and accumulate the product
          acc <= acc + mac_p;
          if (mk == 2'd2) state <= S_MACW;
          else begin mk <= mk + 2'd1; state <= S_MAC; end
        end
        S_MACW: begin
          if (tri_m) begin
            case (mr)
              2'd0: tvx[mp] <= mac_res;
              2'd1: tvy[mp] <= mac_res;
              default: tvz[mp] <= mac_res;
            endcase
          end else begin
            case ({mp[0], mr})
              3'b000: wx0 <= mac_res;  3'b001: wy0 <= mac_res;  3'b010: wz0 <= mac_res;
              3'b100: wx1 <= mac_res;  3'b101: wy1 <= mac_res;  3'b110: wz1 <= mac_res;
              default: ;
            endcase
          end
          acc <= 0; mk <= 0;
          if (mr == 2'd2) begin
            mr <= 0;
            if (tri_m) begin
              if (mp == 2'd2) begin pp <= 0; np <= 0; state <= T_NC; end
              else begin mp <= mp + 2'd1; state <= S_MAC; end
            end else begin
              if (mp == 2'd1) begin
                mdph <= 0;
                state <= glcvt ? CV_X : S_NC;   // CONVRT: capture, no draw
              end
              else begin mp <= 2'd1; state <= S_MAC; end
            end
          end else begin mr <= mr + 2'd1; state <= S_MAC; end
        end

        // near clip (perspective only), lib order: end 0 first, then end 1
        S_NC: begin
          if (par[12] == 16'd0) begin csn <= 0; state <= S_CS; end
          else if (z0_near && z1_near) begin state <= S_NEXT; end
          else if (z0_near) begin
            md_a1 <= mdph[0] ? wy1 : wx1; md_a2 <= mdph[0] ? wy0 : wx0;
            md_r <= mdph[0] ? wy0 : wx0; md_rn <= 0;
            md_b1 <= par[23]; md_b2 <= wz0;  md_c1 <= wz1; md_c2 <= wz0;
            md_go <= 1; state <= S_NCW;
          end else if (z1_near) begin
            md_a1 <= mdph[0] ? wy0 : wx0; md_a2 <= mdph[0] ? wy1 : wx1;
            md_r <= mdph[0] ? wy1 : wx1; md_rn <= 0;
            md_b1 <= par[23]; md_b2 <= wz1;  md_c1 <= wz0; md_c2 <= wz1;
            md_go <= 1; state <= S_NCW;
          end else begin mdph <= 0; state <= S_FC; end
        end
        S_NCW: if (md_done) begin
          if (z0_near) begin
            if (mdph[0]==1'b0) begin wx0 <= md_qr; mdph <= 2'd1; end
            else begin wy0 <= md_qr; wz0 <= par[23]; mdph <= 0; end
          end else begin
            if (mdph[0]==1'b0) begin wx1 <= md_qr; mdph <= 2'd1; end
            else begin wy1 <= md_qr; wz1 <= par[23]; mdph <= 0; end
          end
          state <= S_NC;
        end
        // yon clip (stage 10b), the mirror image against par[24]
        S_FC: begin
          if (z0_far && z1_far) begin state <= S_NEXT; end
          else if (z0_far) begin
            md_a1 <= mdph[0] ? wy1 : wx1; md_a2 <= mdph[0] ? wy0 : wx0;
            md_r <= mdph[0] ? wy0 : wx0; md_rn <= 0;
            md_b1 <= par[24]; md_b2 <= wz0;  md_c1 <= wz1; md_c2 <= wz0;
            md_go <= 1; state <= S_FCW;
          end else if (z1_far) begin
            md_a1 <= mdph[0] ? wy0 : wx0; md_a2 <= mdph[0] ? wy1 : wx1;
            md_r <= mdph[0] ? wy1 : wx1; md_rn <= 0;
            md_b1 <= par[24]; md_b2 <= wz1;  md_c1 <= wz0; md_c2 <= wz1;
            md_go <= 1; state <= S_FCW;
          end else begin mdph <= 0; state <= S_PRJ; end
        end
        S_FCW: if (md_done) begin
          if (z0_far) begin
            if (mdph[0]==1'b0) begin wx0 <= md_qr; mdph <= 2'd1; end
            else begin wy0 <= md_qr; wz0 <= par[24]; mdph <= 0; end
          end else begin
            if (mdph[0]==1'b0) begin wx1 <= md_qr; mdph <= 2'd1; end
            else begin wy1 <= md_qr; wz1 <= par[24]; mdph <= 0; end
          end
          state <= S_FC;
        end

        // perspective projection: 4 muldivs (x0 y0 x1 y1)
        S_PRJ: begin
          case (mdph)
            2'd0: begin md_a1 <= wx0; md_a2 <= 16'd0; md_c1 <= wz0; md_c2 <= 16'd0; end
            2'd1: begin md_a1 <= wy0; md_a2 <= 16'd0; md_c1 <= wz0; md_c2 <= 16'd0; end
            2'd2: begin md_a1 <= wx1; md_a2 <= 16'd0; md_c1 <= wz1; md_c2 <= 16'd0; end
            2'd3: begin md_a1 <= wy1; md_a2 <= 16'd0; md_c1 <= wz1; md_c2 <= 16'd0; end
          endcase
          md_b1 <= par[12]; md_b2 <= 16'd0; md_go <= 1; state <= S_PRJW;
        end
        S_PRJW: if (md_done) begin
          case (mdph)
            2'd0: wx0 <= md_q;  2'd1: wy0 <= md_q;
            2'd2: wx1 <= md_q;  2'd3: wy1 <= md_q;
          endcase
          if (mdph == 2'd3) begin csn <= 0; state <= S_CS; end
          else begin mdph <= mdph + 2'd1; state <= S_PRJ; end
        end

        // Cohen-Sutherland: outcodes are combinational; one slide per pass
        S_CS: begin
          if ((oca | ocb) == 4'd0) begin mdph <= 0; state <= S_MAP; end
          else if ((oca & ocb) != 4'd0 || csn == 4'd8) begin
            state <= S_NEXT;
          end else if (oca == 4'd0) begin   // swap so end 0 is outside
            wx0 <= wx1; wx1 <= wx0; wy0 <= wy1; wy1 <= wy0;
          end else begin
            if (oca[0])      begin md_a1 <= wy1; md_a2 <= wy0; md_b1 <= par[13]; md_b2 <= wx0; md_c1 <= wx1; md_c2 <= wx0; end
            else if (oca[1]) begin md_a1 <= wy1; md_a2 <= wy0; md_b1 <= par[15]; md_b2 <= wx0; md_c1 <= wx1; md_c2 <= wx0; end
            else if (oca[2]) begin md_a1 <= wx1; md_a2 <= wx0; md_b1 <= par[14]; md_b2 <= wy0; md_c1 <= wy1; md_c2 <= wy0; end
            else             begin md_a1 <= wx1; md_a2 <= wx0; md_b1 <= par[16]; md_b2 <= wy0; md_c1 <= wy1; md_c2 <= wy0; end
            md_r <= (oca[0] || oca[1]) ? wy0 : wx0; md_rn <= 0;
            md_go <= 1; csn <= csn + 4'd1; state <= S_CSW;
          end
        end
        S_CSW: if (md_done) begin
          if (oca[0])      begin wy0 <= md_qr; wx0 <= par[13]; end
          else if (oca[1]) begin wy0 <= md_qr; wx0 <= par[15]; end
          else if (oca[2]) begin wx0 <= md_qr; wy0 <= par[14]; end
          else             begin wx0 <= md_qr; wy0 <= par[16]; end
          state <= S_CS;
        end

        // viewport map: 4 muldivs, then the y flip in the apply
        S_MAP: begin
          case (mdph)
            2'd0: begin md_a1 <= wx0; md_a2 <= par[13]; md_b1 <= par[19]; md_b2 <= par[17]; md_c1 <= par[15]; md_c2 <= par[13]; end
            2'd1: begin md_a1 <= wy0; md_a2 <= par[14]; md_b1 <= par[20]; md_b2 <= par[18]; md_c1 <= par[16]; md_c2 <= par[14]; end
            2'd2: begin md_a1 <= wx1; md_a2 <= par[13]; md_b1 <= par[19]; md_b2 <= par[17]; md_c1 <= par[15]; md_c2 <= par[13]; end
            2'd3: begin md_a1 <= wy1; md_a2 <= par[14]; md_b1 <= par[20]; md_b2 <= par[18]; md_c1 <= par[16]; md_c2 <= par[14]; end
          endcase
          md_r <= mdph[0] ? par[20] : par[17]; md_rn <= mdph[0];
          md_go <= 1; state <= S_MAPW;
        end
        S_MAPW: if (md_done) begin
          case (mdph)
            2'd0: px0 <= md_qr;   2'd1: py0 <= md_qr;
            2'd2: px1 <= md_qr;   2'd3: py1 <= md_qr;
          endcase
          if (mdph == 2'd3) begin seq <= 0; state <= S_LIN; end
          else begin mdph <= mdph + 2'd1; state <= S_MAP; end
        end

        // issue the LINE: pen (2 bytes) + 8 coordinate bytes, wait, command.
        // The pen is safe to write while the PREVIOUS line still draws --
        // px_pen was latched at ITS command time (stage 9).
        S_LIN: begin
          case (seq)
            3'd0: begin gm_a<=4'h4; gm_wdata<=rcol[7:0];  end  // GCOL
            3'd1: begin gm_a<=4'hD; gm_wdata<=rcol[15:8]; end  // GCOLH
            3'd2: begin gm_a<=4'h0; gm_wdata<=px0[7:0];  end
            3'd3: begin gm_a<=4'h9; gm_wdata<=px0[15:8]; end
            3'd4: begin gm_a<=4'h1; gm_wdata<=py0[7:0];  end
            3'd5: begin gm_a<=4'hA; gm_wdata<=py0[15:8]; end
            3'd6: begin gm_a<=4'h2; gm_wdata<=px1[7:0];  end
            3'd7: begin gm_a<=4'hB; gm_wdata<=px1[15:8]; end
          endcase
          gm_wr <= 1;
          if (seq == 3'd7) begin seq <= 0; state <= S_LIN2; end
          else seq <= seq + 3'd1;
        end
        S_LIN2: begin
          if (seq == 3'd0) begin gm_a<=4'h3; gm_wdata<=py1[7:0];  gm_wr<=1; seq<=3'd1; end
          else begin gm_a<=4'hC; gm_wdata<=py1[15:8]; gm_wr<=1; seq<=0; state<=S_LINB; end
        end
        S_LINB: begin gm_a <= 4'h6;
                      if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr) state <= S_LINC; end
        S_LINC: begin gm_a <= 4'h5; gm_wdata <= 8'h02; gm_wr <= 1;  // LINE
                      state <= S_NEXT; end

        // ==== stage 9b: the TRI record ====================================
        // near clip the polygon against z=16 (ortho copies straight through)
        T_NC: begin
          if (par[12] == 16'd0) begin pp <= 0; k <= 0; state <= T_CPY; end
          else state <= T_NCA;
        end
        T_CPY: begin                   // ortho: copy tv* into the q lanes
          cm_we <= 1;
          case (k[1:0])
            2'd0: begin cm_wa <= {7'd8,pp[2:0]}; cm_wd <= tvx[pp[1:0]]; end
            2'd1: begin cm_wa <= {7'd9,pp[2:0]}; cm_wd <= tvy[pp[1:0]]; end
            default: begin cm_wa <= {7'd10,pp[2:0]}; cm_wd <= tvz[pp[1:0]]; end
          endcase
          if (k[1:0] == 2'd2) begin
            k <= 0;
            if (pp == 4'd2) begin np <= 4'd3; pp <= 0; state <= T_MP; end
            else pp <= pp + 4'd1;
          end else k <= k + 4'd1;
        end
        T_NCA: begin
          if (pp == 4'd3) begin
            if (np < 4'd3) begin state <= S_NEXT; end
            else if (par[24] == 16'd32767) begin pp <= 0; k <= 0; state <= T_MP; end
            else begin pp <= 0; nq2 <= 0; k <= 0; state <= F_CA; end  // yon
          end else begin
            nax <= tvx[pp[1:0]]; nay <= tvy[pp[1:0]]; naz <= tvz[pp[1:0]];
            nbx <= tvx[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            nby <= tvy[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            nbz <= tvz[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            state <= T_NI0;
          end
        end
        T_NI0: begin                   // classify; keep A via the writer
          nain <= !($signed(naz) < $signed(par[23]));
          nbin <= !($signed(nbz) < $signed(par[23]));
          k <= 0;
          state <= (!($signed(naz) < $signed(par[23]))) ? T_NIK : T_NI0W;
        end
        T_NIK: begin                   // keep vertex A: three lane writes
          cm_we <= 1;
          case (k[1:0])
            2'd0: begin cm_wa <= {7'd8,np[2:0]}; cm_wd <= nax; end
            2'd1: begin cm_wa <= {7'd9,np[2:0]}; cm_wd <= nay; end
            default: begin cm_wa <= {7'd10,np[2:0]}; cm_wd <= naz; end
          endcase
          if (k[1:0] == 2'd2) begin np <= np + 4'd1; k <= 0; state <= T_NI0W; end
          else k <= k + 4'd1;
        end
        T_NI0W: begin
          if (nain == nbin) begin pp <= pp + 4'd1; state <= T_NCA; end
          else begin
            md_a1 <= nbx; md_a2 <= nax; md_b1 <= par[23]; md_b2 <= naz; md_c1 <= nbz; md_c2 <= naz;
            md_r <= nax; md_rn <= 0;
            md_go <= 1; state <= T_NI1;
          end
        end
        T_NI1: if (md_done) begin
          cm_we <= 1; cm_wa <= {7'd8,np[2:0]}; cm_wd <= md_qr;
          md_a1 <= nby; md_a2 <= nay; md_b1 <= par[23]; md_b2 <= naz; md_c1 <= nbz; md_c2 <= naz;
          md_r <= nay; md_rn <= 0;
          md_go <= 1; state <= T_NI1W;
        end
        T_NI1W: if (md_done) begin
          cm_we <= 1; cm_wa <= {7'd9,np[2:0]}; cm_wd <= md_qr;
          state <= T_NIZ;
        end
        T_NIZ: begin
          cm_we <= 1; cm_wa <= {7'd10,np[2:0]}; cm_wd <= par[23];
          np <= np + 4'd1; pp <= pp + 4'd1; state <= T_NCA;
        end

        // ==== stage 10b: the TRI far (yon) pass -- the near pass's mirror,
        // walking the q lanes (np verts) into the mapped lanes + v[] (as
        // scratch z), keeping z<=far, then copying back ====================
        F_CA: begin
          if (pp == np) begin
            if (nq2 < 4'd3) begin state <= S_NEXT; end
            else begin cpi <= 0; k <= 0; state <= F_CP; end
          end else state <= F_CAF;     // fetch edge ends A and B
        end
        F_CAF: begin                   // three lane-pair fetches, pipelined
          case (k[2:0])
            3'd0: begin cm_aa <= {7'd8,pp[2:0]};
                        cm_ab <= {7'd8, (pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1};
                        k <= k + 4'd1; end
            3'd1: k <= k + 4'd1;
            3'd2: begin nax <= cm_qa; nbx <= cm_qb;
                        cm_aa <= {7'd9,pp[2:0]};
                        cm_ab <= {7'd9, (pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1};
                        k <= k + 4'd1; end
            3'd3: k <= k + 4'd1;
            3'd4: begin nay <= cm_qa; nby <= cm_qb;
                        cm_aa <= {7'd10,pp[2:0]};
                        cm_ab <= {7'd10, (pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1};
                        k <= k + 4'd1; end
            3'd5: k <= k + 4'd1;
            default: begin naz <= cm_qa; nbz <= cm_qb; k <= 0; state <= F_I0; end
          endcase
        end
        F_I0: begin
          nain <= !($signed(par[24]) < $signed(naz));
          nbin <= !($signed(par[24]) < $signed(nbz));
          k <= 0;
          state <= (!($signed(par[24]) < $signed(naz))) ? F_IK : F_I0W;
        end
        F_IK: begin                    // keep A: two lane writes + v[] z
          cm_we <= 1;
          if (k[0] == 1'b0) begin
            cm_wa <= {7'd11,nq2[2:0]}; cm_wd <= nax;
            fz[nq2[2:0]] <= naz;
            k <= k + 4'd1;
          end else begin
            cm_wa <= {7'd12,nq2[2:0]}; cm_wd <= nay;
            nq2 <= nq2 + 4'd1; k <= 0; state <= F_I0W;
          end
        end
        F_I0W: begin
          if (nain == nbin) begin pp <= pp + 4'd1; state <= F_CA; end
          else begin
            md_a1 <= nbx; md_a2 <= nax; md_b1 <= par[24]; md_b2 <= naz; md_c1 <= nbz; md_c2 <= naz;
            md_r <= nax; md_rn <= 0;
            md_go <= 1; state <= F_I1;
          end
        end
        F_I1: if (md_done) begin
          cm_we <= 1; cm_wa <= {7'd11,nq2[2:0]}; cm_wd <= md_qr;
          md_a1 <= nby; md_a2 <= nay; md_b1 <= par[24]; md_b2 <= naz; md_c1 <= nbz; md_c2 <= naz;
          md_r <= nay; md_rn <= 0;
          md_go <= 1; state <= F_I1W;
        end
        F_I1W: if (md_done) begin
          cm_we <= 1; cm_wa <= {7'd12,nq2[2:0]}; cm_wd <= md_qr;
          fz[nq2[2:0]] <= par[24];
          nq2 <= nq2 + 4'd1;
          pp <= pp + 4'd1; state <= F_CA;
        end
        F_CP: begin                    // mapped lanes + v -> q lanes
          case (k[2:0])
            3'd0: begin cm_aa <= {7'd11,cpi[2:0]};
                        cm_ab <= {7'd12,cpi[2:0]}; k <= k + 4'd1; end
            3'd1: k <= k + 4'd1;
            3'd2: begin cm_we <= 1; cm_wa <= {7'd8,cpi[2:0]};
                        cm_wd <= cm_qa; cyv <= cm_qb; k <= k + 4'd1; end
            3'd3: begin cm_we <= 1; cm_wa <= {7'd9,cpi[2:0]};
                        cm_wd <= cyv; k <= k + 4'd1; end
            default: begin
              cm_we <= 1; cm_wa <= {7'd10,cpi[2:0]};
              cm_wd <= fz[cpi[2:0]];
              k <= 0;
              if (cpi + 4'd1 == nq2) begin np <= nq2; pp <= 0; state <= T_MP; end
              else cpi <= cpi + 4'd1;
            end
          endcase
        end

        // project + viewport-map each polygon vertex into the mapped lanes
        T_MP: begin
          if (pp == np) begin
            seq <= 0; state <= T_PENW;   // GL fills only: outline TRIs
          end else begin                 //   draw as DRAW3 edges instead
            case (k[2:0])
              3'd0: begin cm_aa <= {7'd8,pp[2:0]};
                          cm_ab <= {7'd9,pp[2:0]}; k <= k + 4'd1; end
              3'd1: k <= k + 4'd1;
              3'd2: begin cxv <= cm_qa; cyv <= cm_qb;
                          cm_aa <= {7'd10,pp[2:0]}; k <= k + 4'd1; end
              3'd3: k <= k + 4'd1;
              default: begin
                naz <= cm_qa;            // the vertex's z, held for T_PJ*
                k <= 0;
                // gl2d: a 2D fill's vertices are already window-space --
                // map only, never project
                state <= (par[12] != 16'd0 && !gl2d) ? T_PJX : T_MX;
              end
            endcase
          end
        end
        T_PJX: begin
          md_a1 <= cxv; md_a2 <= 16'd0; md_b1 <= par[12]; md_b2 <= 16'd0; md_c1 <= naz; md_c2 <= 16'd0;
          md_go <= 1; state <= T_PJXW;
        end
        T_PJXW: if (md_done) begin cxv <= md_q; state <= T_PJY; end
        T_PJY: begin
          md_a1 <= cyv; md_a2 <= 16'd0; md_b1 <= par[12]; md_b2 <= 16'd0; md_c1 <= naz; md_c2 <= 16'd0;
          md_go <= 1; state <= T_PJYW;
        end
        T_PJYW: if (md_done) begin cyv <= md_q; state <= T_MX; end
        T_MX: begin
          md_a1 <= cxv; md_a2 <= par[13]; md_b1 <= par[19]; md_b2 <= par[17]; md_c1 <= par[15]; md_c2 <= par[13];
          md_r <= par[17]; md_rn <= 0;
          md_go <= 1; state <= T_MXW;
        end
        T_MXW: if (md_done) begin
          cm_we <= 1; cm_wa <= {7'd11,pp[2:0]}; cm_wd <= md_qr;
          state <= T_MY;
        end
        T_MY: begin
          md_a1 <= cyv; md_a2 <= par[14]; md_b1 <= par[20]; md_b2 <= par[18]; md_c1 <= par[16]; md_c2 <= par[14];
          md_r <= par[20]; md_rn <= 1;
          md_go <= 1; state <= T_MYW;
        end
        T_MYW: if (md_done) begin
          cm_we <= 1; cm_wa <= {7'd12,pp[2:0]}; cm_wd <= md_qr;
          pp <= pp + 4'd1; k <= 0; state <= T_MP;
        end

        // fill: pen once, then fan (0,t,t+1), each sorted then scanned
        T_PENW: begin
          if (seq == 3'd0) begin gm_a<=4'h4; gm_wdata<=rcol[7:0];  gm_wr<=1; seq<=3'd1; end
          else begin gm_a<=4'hD; gm_wdata<=rcol[15:8]; gm_wr<=1; seq<=0;
                     ft <= 4'd1; k <= 0; state <= T_FAN; end
        end
        T_FAN: begin
          if (ft + 4'd1 >= np) begin state <= S_NEXT; end
          else case (k[2:0])           // fetch the fan corners lane-pairwise
            3'd0: begin cm_aa <= LSX; cm_ab <= LSY; k <= k + 4'd1; end
            3'd1: k <= k + 4'd1;
            3'd2: begin fx0 <= cm_qa; fy0 <= cm_qb;
                        cm_aa <= {7'd11,ft[2:0]};
                        cm_ab <= {7'd12,ft[2:0]}; k <= k + 4'd1; end
            3'd3: k <= k + 4'd1;
            3'd4: begin fx1 <= cm_qa; fy1 <= cm_qb;
                        cm_aa <= {7'd11, ft[2:0] + 3'd1};
                        cm_ab <= {7'd12, ft[2:0] + 3'd1}; k <= k + 4'd1; end
            3'd5: k <= k + 4'd1;
            default: begin fx2 <= cm_qa; fy2 <= cm_qb;
                           k <= 0; state <= T_SRT1; end
          endcase
        end
        T_SRT1: begin                  // the 3-swap network, one per cycle
          if ($signed(fy1) < $signed(fy0)) begin
            fx0<=fx1; fx1<=fx0; fy0<=fy1; fy1<=fy0;
          end
          state <= T_SRT2;
        end
        T_SRT2: begin
          if ($signed(fy2) < $signed(fy1)) begin
            fx1<=fx2; fx2<=fx1; fy1<=fy2; fy2<=fy1;
          end
          state <= T_SRT3;
        end
        T_SRT3: begin
          if ($signed(fy1) < $signed(fy0)) begin
            fx0<=fx1; fx1<=fx0; fy0<=fy1; fy1<=fy0;
          end
          state <= T_DEG;
        end
        T_DEG: begin
          if (fy2 == fy0) begin        // one scanline: span = min..max x
            fy <= fy0; fxa <= dg_lo; fxb <= dg_hi;
            state <= T_SPAN;
          end else begin fy <= fy0; state <= T_SLOOP; end
        end
        T_SLOOP: begin
          if (!fy_in) state <= T_SNEXT;
          else state <= T_SXA;
        end
        T_SXA: begin                   // long edge: v0 -> v2
          md_a1 <= fy; md_a2 <= fy0; md_b1 <= fx2; md_b2 <= fx0; md_c1 <= fy2; md_c2 <= fy0;
          md_r <= fx0; md_rn <= 0;
          md_go <= 1; state <= T_SXAW;
        end
        T_SXAW: if (md_done) begin fxa <= md_qr; state <= T_SXB; end
        T_SXB: begin                   // split edge: v0v1 above y1, else v1v2
          if (fy1 == fy0 && !($signed(fy1) <= $signed(fy))) begin
            fxb <= fx1; state <= T_SPAN;         // unreachable guard
          end else if (fy1 == fy0) begin
            fxb <= fx1; state <= T_SPAN;
          end else if ($signed(fy) < $signed(fy1)) begin
            md_a1 <= fy; md_a2 <= fy0; md_b1 <= fx1; md_b2 <= fx0; md_c1 <= fy1; md_c2 <= fy0;
            md_r <= fx0; md_rn <= 0;
            md_go <= 1; state <= T_SXBW;
          end else if (fy2 == fy1) begin
            fxb <= fx1; state <= T_SPAN;
          end else begin
            md_a1 <= fy; md_a2 <= fy1; md_b1 <= fx2; md_b2 <= fx1; md_c1 <= fy2; md_c2 <= fy1;
            md_r <= fx1; md_rn <= 0;
            md_go <= 1; state <= T_SXBW;
          end
        end
        T_SXBW: if (md_done) begin
          fxb <= md_qr;
          state <= T_SPAN;
        end
        T_SPAN: begin                  // clamp; empty spans skip
          if (!sp_ok || !fy_in) state <= T_SNEXT;
          else begin seq <= 0; state <= T_BX; end
        end
        T_BX: begin                    // BOXFILL x0=sp_l y0=fy x1=sp_r y1=fy
          case (seq)
            3'd0: begin gm_a<=4'h0; gm_wdata<=sp_l[7:0];  end
            3'd1: begin gm_a<=4'h9; gm_wdata<=sp_l[15:8]; end
            3'd2: begin gm_a<=4'h1; gm_wdata<=fy[7:0];    end
            3'd3: begin gm_a<=4'hA; gm_wdata<=fy[15:8];   end
            3'd4: begin gm_a<=4'h2; gm_wdata<=sp_r[7:0];  end
            3'd5: begin gm_a<=4'hB; gm_wdata<=sp_r[15:8]; end
            3'd6: begin gm_a<=4'h3; gm_wdata<=fy[7:0];    end
            3'd7: begin gm_a<=4'hC; gm_wdata<=fy[15:8];   end
          endcase
          gm_wr <= 1;
          if (seq == 3'd7) state <= T_BXB; else seq <= seq + 3'd1;
        end
        T_BXB: begin gm_a <= 4'h6;
                     if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr) state <= T_BXC; end
        T_BXC: begin gm_a <= 4'h5; gm_wdata <= 8'h04; gm_wr <= 1;  // BOXFILL
                     state <= T_SNEXT; end
        T_SNEXT: begin
          if (fy == fy2 || fy2 == fy0) begin ft <= ft + 4'd1; k <= 0; state <= T_FAN; end
          else begin fy <= fy + 16'd1; state <= T_SLOOP; end
        end

        // ==== stage 10: the GL box issuer =================================
        // BOXFILL gbx0/gby0-gbx1/gby1 in colour gbcol -- FLOOD, CLEARS and
        // the filled RECT all come here. CLEARS (glcls != 0) runs it twice,
        // toggling the draw page between passes so BOTH pages are cleared
        // (the stage-8b sideband lesson), and waits out each fill before
        // the toggle so no fill lands on the wrong page.
        W_BOX0: begin gm_a <= 4'h4; gm_wdata <= gbcol[7:0]; gm_wr <= 1;
                      state <= W_BOX1; end
        W_BOX1: begin gm_a <= 4'hD; gm_wdata <= gbcol[15:8]; gm_wr <= 1;
                      seq <= 0; state <= W_BOX2; end
        W_BOX2: begin
          case (seq)
            3'd0: begin gm_a<=4'h0; gm_wdata<=gbx0[7:0];  end
            3'd1: begin gm_a<=4'h9; gm_wdata<=gbx0[15:8]; end
            3'd2: begin gm_a<=4'h1; gm_wdata<=gby0[7:0];  end
            3'd3: begin gm_a<=4'hA; gm_wdata<=gby0[15:8]; end
            3'd4: begin gm_a<=4'h2; gm_wdata<=gbx1[7:0];  end
            3'd5: begin gm_a<=4'hB; gm_wdata<=gbx1[15:8]; end
            3'd6: begin gm_a<=4'h3; gm_wdata<=gby1[7:0];  end
            3'd7: begin gm_a<=4'hC; gm_wdata<=gby1[15:8]; end
          endcase
          gm_wr <= 1;
          if (seq == 3'd7) state <= W_BOXW; else seq <= seq + 3'd1;
        end
        W_BOXW: begin gm_a <= 4'h6;
                      if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr) state <= W_BOXC; end
        W_BOXC: begin gm_a <= 4'h5; gm_wdata <= 8'h04; gm_wr <= 1;  // BOXFILL
                      state <= W_BOXD; end  // NEVER straight to idle: the
                                            // strobe needs gm_own next cycle
        W_BOXD: begin
          if (glcls == 2'd0) state <= S_IDLE;
          else begin gm_a <= 4'h6;          // CLEARS: wait the fill out...
            if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr) begin
              draw_pg <= ~draw_pg;          // ...then swap pages
              if (glcls == 2'd1) begin glcls <= 2'd2; state <= W_BOX0; end
              else begin glcls <= 2'd0; state <= S_IDLE; end  // pg restored
            end
          end
        end

        // filled RECT: map both corners (4 muldivs), sort, clamp, box
        W_RM: begin
          case (mdph)
            2'd0: begin md_a1 <= c2x; md_a2 <= par[13]; md_b1 <= par[19]; md_b2 <= par[17]; md_c1 <= par[15]; md_c2 <= par[13]; end
            2'd1: begin md_a1 <= c2y; md_a2 <= par[14]; md_b1 <= par[20]; md_b2 <= par[18]; md_c1 <= par[16]; md_c2 <= par[14]; end
            2'd2: begin md_a1 <= nbx; md_a2 <= par[13]; md_b1 <= par[19]; md_b2 <= par[17]; md_c1 <= par[15]; md_c2 <= par[13]; end
            2'd3: begin md_a1 <= nby; md_a2 <= par[14]; md_b1 <= par[20]; md_b2 <= par[18]; md_c1 <= par[16]; md_c2 <= par[14]; end
          endcase
          md_r <= mdph[0] ? par[20] : par[17]; md_rn <= mdph[0];
          md_go <= 1; state <= W_RMW;
        end
        W_RMW: if (md_done) begin
          case (mdph)
            2'd0: gbx0 <= md_qr;   2'd1: gby0 <= md_qr;
            2'd2: gbx1 <= md_qr;   2'd3: gby1 <= md_qr;
          endcase
          if (mdph == 2'd3) state <= W_RC1;
          else begin mdph <= mdph + 2'd1; state <= W_RM; end
        end
        W_RC1: begin                        // normalise: any two corners
          if ($signed(gbx1) < $signed(gbx0)) begin gbx0 <= gbx1; gbx1 <= gbx0; end
          if ($signed(gby1) < $signed(gby0)) begin gby0 <= gby1; gby1 <= gby0; end
          state <= W_RC2;
        end
        W_RC2: begin                        // clamp to the viewport; empty
          if ($signed(gbx0) < $signed(par[17])) gbx0 <= par[17];  // skips
          if ($signed(par[19]) < $signed(gbx1)) gbx1 <= par[19];
          if ($signed(gby0) < $signed(par[18])) gby0 <= par[18];
          if ($signed(par[20]) < $signed(gby1)) gby1 <= par[20];
          state <= (($signed(par[19]) < $signed(gbx0)) ||
                    ($signed(gbx1) < $signed(par[17])) ||
                    ($signed(par[20]) < $signed(gby0)) ||
                    ($signed(gby1) < $signed(par[18]))) ? S_IDLE : W_BOX0;
        end

        // ==== stage 10b: CONVRT's projection tail =========================
        // The 3D current point was transformed by the MAC (duplicated, like
        // POINT3); project it with z clamped to the near/far planes and
        // land it in the 2D current point. No drawing, no gm ownership use.
        CV_X: begin
          if (par[12] == 16'd0) begin
            c2x <= wx0; c2y <= wy0; glcvt <= 0; state <= S_IDLE;
          end else begin
            md_a1 <= wx0; md_a2 <= 16'd0; md_b1 <= par[12]; md_b2 <= 16'd0; md_c1 <= cvz; md_c2 <= 16'd0;
            md_go <= 1; state <= CV_XW;
          end
        end
        CV_XW: if (md_done) begin
          c2x <= md_q;
          md_a1 <= wy0; md_a2 <= 16'd0; md_b1 <= par[12]; md_b2 <= 16'd0; md_c1 <= cvz; md_c2 <= 16'd0;
          md_go <= 1; state <= CV_YW;
        end
        CV_YW: if (md_done) begin
          c2y <= md_q; glcvt <= 0; state <= S_IDLE;
        end

        // ==== stage 10b: the matrix COMPOSE microprogram ==================
        // One multiply loop serves three products (cmode): the submatrix
        // into M, the submatrix into VR, and the recompose VR*M -> par[],
        // all in ge_md semantics (muldiv /256, int16 wrap adds) so the
        // emulator's gl_mcomp/gl_recompose agree term for term.
        C_NRM: begin                   // rotation angle to 0..359
          if ($signed(ang) < 0) ang <= ang + 16'd360;
          else if ($signed(ang) >= 16'sd360) ang <= ang - 16'd360;
          else begin                   // build the submatrix via the writer
            jsrc <= 3'd1; jbase <= SB; jlast <= 4'd11; jcnt <= 0;
            ci <= 0; cj <= 0; ck <= 0; csum <= 0; mtf <= 0;
            if (vwf) begin cmode <= 2'd1; jnext <= C_MLA; end
            else begin cmode <= 2'd0; jnext <= C_OGA; end
            state <= J_WR;
          end
        end
        J_WR: begin                    // one scratch cell per cycle
          cm_we <= 1;
          cm_wa <= jrbs ? (RBS + {6'd0, jcnt}) : {4'd0, jbase[5:4], jcnt};
          cm_wd <= jrbs ? ((jcnt == 4'd1 || jcnt == 4'd2) ? 16'hFFFF
                           : (jcnt == 4'd12) ? 16'd16
                           : (jcnt == 4'd13) ? 16'd32767 : 16'd0)
                        : jval;
          if (jcnt == jlast) begin jcnt <= 0; jrbs <= 0; state <= jnext; end
          else jcnt <= jcnt + 4'd1;
        end
        J_RST2: begin                  // warm reset, part 2: VR identity
          jsrc <= 0; jbase <= VB; jlast <= 4'd8; jcnt <= 0;
          jnext <= J_RB3; state <= J_WR;
        end
        J_RB3: begin                   // part 3: the FLAGRD mirror defaults
          jrbs <= 1; jlast <= 4'd13; jcnt <= 0;
          jnext <= W_LF; state <= J_WR; // part 4: GMODE back to replace
        end

        W_LF: begin                    // the mode must not overtake a
          gm_a <= 4'h6;                //   primitive still drawing: wait
          if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr) state <= W_LF2;
        end
        W_LF2: begin                   // one GMODE write ($FF2E's write side)
          gm_a <= 4'hE; gm_wdata <= {5'd0, glfm}; gm_wr <= 1;
          state <= S_NEXT;
        end

        // ==== stage 10g: AREA / AREABC boundary seed fill ================
        // The emulator's gl_afill IS the contract, reproduced step for
        // step: outcode the seed (err 2 off-window), viewport-map it,
        // then pop/probe/span/paint/scan with an explicit stack in SDRAM
        // at $180000 (16384 x/y halfword pairs; hitting the cap is err 8
        // and a deterministic partial fill). A fill under XOR/AND would
        // break its own visited-mark invariant, so GMODE is forced to 0
        // first -- the documented rule.
        AF_MAP0: begin
          if (oca != 4'd0) begin epush(8'd2); state <= S_NEXT; end
          else begin
            gm_a <= 4'hE; gm_wdata <= 8'd0; gm_wr <= 1; glfm <= 0;
            md_a1 <= wx0; md_a2 <= par[13]; md_b1 <= par[19];
            md_b2 <= par[17]; md_c1 <= par[15]; md_c2 <= par[13];
            md_r <= par[17]; md_rn <= 0; md_go <= 1; state <= AF_MAP1;
          end
        end
        AF_MAP1: if (md_done) begin    // x mapped; launch y (flipped)
          afx <= md_qr[8:0];
          md_a1 <= wy0; md_a2 <= par[14]; md_b1 <= par[20];
          md_b2 <= par[18]; md_c1 <= par[16]; md_c2 <= par[14];
          md_r <= par[20]; md_rn <= 1; md_go <= 1; state <= AF_MAP2;
        end
        AF_MAP2: if (md_done) begin
          afy <= md_qr[8:0]; state <= AF_MAP3;
        end
        AF_MAP3: begin                 // probe the seed itself
          afsp <= 0; afovf <= 0;
          apx <= afx; apy <= afy; afret <= 4'd0; state <= AF_P0;
        end

        // span probes: L-1 leftward, then R+1 rightward (9-bit unsigned
        // wrap turns -1 into 511, which the probe's bounds check catches)
        AF_L: begin
          apx <= afL - 9'd1; apy <= afy; afret <= 4'd2; state <= AF_P0;
        end
        AF_R: begin
          apx <= afR + 9'd1; apy <= afy; afret <= 4'd3; state <= AF_P0;
        end

        // paint the span: one device LINE, pen + both endpoints on row afy
        AF_PT0: begin
          case (seq)
            3'd0: begin gm_a<=4'h4; gm_wdata<=rcol[7:0];       end
            3'd1: begin gm_a<=4'hD; gm_wdata<=rcol[15:8];      end
            3'd2: begin gm_a<=4'h0; gm_wdata<=afL[7:0];        end
            3'd3: begin gm_a<=4'h9; gm_wdata<={7'd0,afL[8]};   end
            3'd4: begin gm_a<=4'h1; gm_wdata<=afy[7:0];        end
            3'd5: begin gm_a<=4'hA; gm_wdata<={7'd0,afy[8]};   end
            3'd6: begin gm_a<=4'h2; gm_wdata<=afR[7:0];        end
            3'd7: begin gm_a<=4'hB; gm_wdata<={7'd0,afR[8]};   end
          endcase
          gm_wr <= 1;
          if (seq == 3'd7) begin seq <= 0; state <= AF_PT1; end
          else seq <= seq + 3'd1;
        end
        AF_PT1: begin
          if (seq == 3'd0) begin gm_a<=4'h3; gm_wdata<=afy[7:0]; gm_wr<=1; seq<=3'd1; end
          else begin gm_a<=4'hC; gm_wdata<={7'd0,afy[8]}; gm_wr<=1; seq<=0;
                     state<=AF_PT2; end
        end
        AF_PT2: begin gm_a <= 4'h6;    // engine idle before the command
                      if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr)
                        state <= AF_PT3; end
        AF_PT3: begin gm_a <= 4'h5; gm_wdata <= 8'h02; gm_wr <= 1;  // LINE
                      afrsel <= 0; state <= AF_SCAN; end

        // scan rows afy-1 and afy+1 across [afL..afR]: one push per
        // interior run (the probe waits out the paint via GSTAT first)
        AF_SCAN: begin
          if (!afrsel ? (afy == 9'd0) : (afy == 9'd271)) state <= AF_SC2;
          else begin
            afrow <= !afrsel ? afy - 9'd1 : afy + 9'd1;
            afi <= afL; state <= AF_SC1;
          end
        end
        AF_SC1: begin
          if (afi > afR) state <= AF_SC2;
          else begin apx <= afi; apy <= afrow; afret <= 4'd4;
                     state <= AF_P0; end
        end
        AF_SC2: begin                  // row advance: below, then done->pop
          if (!afrsel) begin afrsel <= 1; state <= AF_SCAN; end
          else state <= AF_POP0;
        end
        AF_PU0: begin                  // push (afi, afrow): x halfword
          if (afsp == 15'd16384) begin epush(8'd8); state <= S_NEXT; end
          else if (!sd_busy && !g_req) begin
            g_addr <= {2'd0, 2'b11, 2'd0, afsp, 2'b00};
            g_din <= {7'd0, afi};
            g_we <= 1; g_req <= 1; sd_busy <= 1; state <= AF_PU1;
          end
        end
        AF_PU1: if (!sd_busy && !g_req) begin   // y halfword, bump, skip run
          g_addr <= {2'd0, 2'b11, 2'd0, afsp, 2'b10};
          g_din <= {7'd0, afrow};
          g_we <= 1; g_req <= 1; sd_busy <= 1;
          afsp <= afsp + 15'd1; afi <= afi + 9'd1; state <= AF_SKIP;
        end
        AF_SKIP: begin                 // advance past the interior run
          if (afi > afR) state <= AF_SC2;
          else begin apx <= afi; apy <= afrow; afret <= 4'd5;
                     state <= AF_P0; end
        end

        // pop a seed (x at +0, y at +2) and re-probe it -- spans painted
        // since it was pushed may have absorbed it, exactly the emulator
        AF_POP0: begin
          if (afsp == 15'd0) state <= S_NEXT;         // stack dry: done
          else begin afsp <= afsp - 15'd1; state <= AF_POP1; end
        end
        AF_POP1: if (!sd_busy && !g_req) begin
          g_addr <= {2'd0, 2'b11, 2'd0, afsp, 2'b00};
          g_we <= 0; g_req <= 1; sd_busy <= 1; state <= AF_POP2;
        end
        AF_POP2: if (g_ready) begin    // capture x, chain the y read
          afx <= g_dout[8:0];
          g_addr <= {2'd0, 2'b11, 2'd0, afsp, 2'b10};
          g_we <= 0; g_req <= 1; sd_busy <= 1; state <= AF_CHK;
        end
        AF_CHK: if (g_ready) begin
          afy <= g_dout[8:0];
          apx <= afx; apy <= g_dout[8:0]; afret <= 4'd1; state <= AF_P0;
        end

        // ---- the pixel probe (gm POINT + two GDATA pops) ----------------
        // Off-screen forces the boundary verdict by loading afpv with the
        // boundary colour itself (gl_af_in's x<0||x>=480||... return 0)
        AF_P0: begin
          if (apx > 9'd479 || apy > 9'd271) begin
            afpv <= afbc; state <= AF_P9;
          end else begin seq <= 0; state <= AF_P1; end
        end
        AF_P1: begin                   // the probe target's coordinates
          case (seq)
            3'd0: begin gm_a<=4'h0; gm_wdata<=apx[7:0];      end
            3'd1: begin gm_a<=4'h9; gm_wdata<={7'd0,apx[8]}; end
            3'd2: begin gm_a<=4'h1; gm_wdata<=apy[7:0];      end
            default: begin gm_a<=4'hA; gm_wdata<={7'd0,apy[8]}; end
          endcase
          gm_wr <= 1;
          if (seq == 3'd3) begin seq <= 0; state <= AF_P2; end
          else seq <= seq + 3'd1;
        end
        AF_P2: begin gm_a <= 4'h6;     // engine idle (paint may be live)
                     if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr)
                       state <= AF_P3; end
        AF_P3: begin gm_a <= 4'h5; gm_wdata <= 8'h09; gm_wr <= 1;  // POINT
                     state <= AF_P4; end
        AF_P4: begin gm_a <= 4'h6;     // wait for the pixel itself
                     if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr)
                       state <= AF_P5; end
        AF_P5: begin gm_a <= 4'h7; state <= AF_P6; end
        AF_P6: begin afpv[7:0] <= gm_rdata; gm_rd <= 1; state <= AF_P7; end
        AF_P7: state <= AF_P8;         // the strobe's propagation cycle
        AF_P8: begin afpv[15:8] <= gm_rdata; state <= AF_P9; end
        AF_P9: begin                   // return: dispatch on the caller
          case (afret)
            4'd0: begin                // seed: boundary -> silent no-op
              if (!af_in) state <= S_NEXT;
              else begin afL <= afx; state <= AF_L; end
            end
            4'd1: begin                // popped seed's re-probe
              if (!af_in) state <= AF_POP0;
              else begin afL <= afx; state <= AF_L; end
            end
            4'd2: begin                // extend left?
              if (af_in) begin afL <= afL - 9'd1; state <= AF_L; end
              else begin afR <= afx; state <= AF_R; end
            end
            4'd3: begin                // extend right?
              if (af_in) begin afR <= afR + 9'd1; state <= AF_R; end
              else begin seq <= 0; state <= AF_PT0; end
            end
            4'd4: begin                // scan probe: interior -> push
              if (af_in) state <= AF_PU0;
              else begin afi <= afi + 9'd1; state <= AF_SC1; end
            end
            default: begin             // skip past the pushed run
              afi <= afi + 9'd1;
              state <= af_in ? AF_SKIP : AF_SC1;
            end
          endcase
        end

        // pivot: T = org - (S*org)>>8 -- ms cells fetched from the RAM
        C_OGA: begin
          cm_aa <= {6'd2, cick};                   // SB + ci*3 + ck
          state <= C_OGB;
        end
        C_OGB: state <= C_OGC;         // the read pipeline's bubble
        C_OGC: begin
          md_a1 <= cm_qa; md_a2 <= 16'd0; md_b1 <= glorg[ck]; md_b2 <= 16'd0; md_c1 <= 16'd256; md_c2 <= 16'd0;
          md_r <= csum; md_rn <= 0;
          md_go <= 1; state <= C_OGW;
        end
        C_OGW: if (md_done) begin
          if (ck == 2'd2) begin
            cm_we <= 1; cm_wa <= {6'd2, c9i};
            cm_wd <= glorg[ci] - md_qr;
            ck <= 0; csum <= 0;
            if (ci == 2'd2) begin ci <= 0; cj <= 0; state <= C_MLA; end
            else begin ci <= ci + 2'd1; state <= C_OGA; end
          end else begin csum <= md_qr; ck <= ck + 2'd1; state <= C_OGA; end
        end

        // one product term: fetch both operands, muldiv, accumulate. A
        // mode-0 T column first prefetches ms[9+ci] (the additive tail).
        C_MLA: begin
          if (cj == 2'd3 && cmode == 2'd0 && !mtf) begin
            cm_aa <= {6'd2, c9i}; state <= C_MTB;
          end else begin
            cm_aa <= {(cmode == 2'd2) ? 6'd1 : 6'd2, cick};
            cm_ab <= (cj == 2'd3) ? {6'd0, c9k}
                   : {(cmode == 2'd1) ? 6'd1 : 6'd0, ckcj};
            state <= C_MLB;
          end
        end
        C_MTB: state <= C_MTC;
        C_MTC: begin msT <= cm_qa; mtf <= 1; state <= C_MLA; end
        C_MLB: state <= C_MLC;
        C_MLC: begin
          md_a1 <= cm_qa; md_a2 <= 16'd0;
          md_b1 <= cm_qb;
          md_b2 <= (cj == 2'd3 && cmode == 2'd2) ? glvrp[ck] : 16'd0;
          md_c1 <= 16'd256; md_c2 <= 16'd0;
          md_r <= csum; md_rn <= 0; md_go <= 1; state <= C_MLW;
        end
        C_MLW: if (md_done) begin
          if (ck == 2'd2) begin
            cm_we <= 1;
            cm_wa <= {6'd3, (cj == 2'd3) ? c9i : cicj};
            cm_wd <= cm_res;
            ck <= 0; csum <= 0; mtf <= 0;
            if (cj == cjmax) begin
              cj <= 0;
              if (ci == 2'd2) begin cpi <= 0; state <= C_CPA; end
              else begin ci <= ci + 2'd1; state <= C_MLA; end
            end else begin cj <= cj + 2'd1; state <= C_MLA; end
          end else begin csum <= md_qr; ck <= ck + 2'd1; state <= C_MLA; end
        end

        // land the product where it belongs, then chain
        C_CPA: begin cm_aa <= {6'd3, cpi[3:0]}; state <= C_CPB; end
        C_CPB: state <= C_CPC;
        C_CPC: begin
          case (cmode)
            2'd0: begin cm_we <= 1; cm_wa <= {6'd0, cpi[3:0]}; cm_wd <= cm_qa; end
            2'd1: begin cm_we <= 1; cm_wa <= {6'd1, cpi[3:0]}; cm_wd <= cm_qa; end
            default: par[cpi[3:0]] <= cm_qa;
          endcase
          if (cpi == ((cmode == 2'd1) ? 4'd8 : 4'd11)) begin
            if (cmode != 2'd2) begin   // composed a master: now recompose
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              cpi <= 0; state <= C_MLA;
            end else state <= C_RCK;
          end else begin cpi <= cpi + 4'd1; state <= C_CPA; end
        end

        C_RCK: begin                   // K: PROJCT's focal from the window
          if (!glpmode) state <= C_RCN;
          else if (glproj == 16'd0) begin par[12] <= 0; state <= C_RCN; end
          else begin
            md_a1 <= par[15]; md_a2 <= par[13]; md_b1 <= 16'd128; md_b2 <= 16'd0;
            md_c1 <= tanq; md_c2 <= 16'd0;
            md_go <= 1; state <= C_RCKW;
          end
        end
        C_RCKW: if (md_done) begin par[12] <= md_q; state <= C_RCN; end
        C_RCN: if (!rcph) begin        // near plane in eye z (+ mirror)
          par[23] <= glch ? (($signed(gldist + glh) < 16'sd16)
                             ? 16'd16 : gldist + glh)
                          : 16'd16;
          cm_we <= 1; cm_wa <= RBS + 10'd12;
          cm_wd <= glch ? (($signed(gldist + glh) < 16'sd16)
                           ? 16'd16 : gldist + glh)
                        : 16'd16;
          rcph <= 1;
        end else begin                 // far plane (+ mirror)
          par[24] <= glcy ? gldist + glyy : 16'd32767;
          cm_we <= 1; cm_wa <= RBS + 10'd13;
          cm_wd <= glcy ? gldist + glyy : 16'd32767;
          rcph <= 0; state <= S_IDLE;
        end

        // flip: applied at the scanout frame boundary, then idle
        S_FLIP: if (flip_pend && frame_tick) begin
          disp_pg <= draw_pg;
          draw_pg <= ~draw_pg;
          flip_pend <= 0;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase

      // ---- stage 10: the GL consumer ---------------------------------------
      // Decodes the command FIFO byte-at-a-time and executes each command
      // by writing state and entering the walker's own pipeline: S_MAC for
      // 3D (transform -> near clip -> project -> CS -> map -> LINE, or the
      // T-path for a fill), S_CS for 2D lines (clip -> map -> LINE), T_MP
      // for 2D fills (map -> scanline fill), W_BOX/W_RM for the boxes.
      // Every dispatch is gated on gl_can: the walker idle and the CPU not
      // starting record work this same cycle. Streaming verbs (POLY*)
      // dispatch one primitive per vertex, so a 255-vertex polygon never
      // needs more buffer than one vertex.
      case (glst)
        // pop one byte from the active source (FIFO or replay buffer);
        // while recording, pops also stream into the SDRAM store, so
        // they gate on the store being free (sd_busy)
        G_OP: if (src_ne && !(rec && sd_busy)) begin
          glop <= srcb; pi <= 0;
          if (rp) begin rpb0 <= rpb1; rp_have <= rp_have - 2'd1;
                        rp_off <= rp_off + 13'd1; end
          else if (glmode) tq_rp <= tq_rp + 3'd1;
          else cf_rp <= cf_rp + 6'd1;
          if (rec && srcb == 8'h71) begin
            glst <= G_LE0;                       // the REAL CLEND: finish
          end else if (!opok) begin              // unknown: log, skip, and
            if (ef_wp - ef_rp != 4'd8) begin     //   while recording, do
              ef[ef_wp[2:0]] <= 8'd1;            //   NOT store the byte
              ef_wp <= ef_wp + 4'd1; end
          end else begin
            pneed <= opn;
            glst <= (opn == 5'd0) ? G_RUN : G_PRM;
            if (rec) begin
              if (srcb == 8'h70 || srcb == 8'h72 ||
                  srcb == 8'h73 || srcb == 8'h79) begin
                if (ef_wp - ef_rp != 4'd8) begin // no nesting: error 5,
                  ef[ef_wp[2:0]] <= 8'd5;        //   consume unstored
                  ef_wp <= ef_wp + 4'd1; end
                rskip <= 1;
              end else if (srcb == 8'h43) begin  // CA/CX: TRANSPORT, not
                                                 //   content -- executes
                                                 //   even mid-recording
              end else begin                     // store the opcode byte
                if (rec_len >= 13'd4092) begin   // slot full: error 7,
                  epush(8'd7);                   //   recording aborts (the
                  cldef[rec_slot] <= 1'b0;       //   partial tail lies in a
                  rec <= 0; rskip <= 1;          //   slot that stays
                end else begin                   //   undefined)
                  if (!rec_len[0]) rec_lo <= srcb;
                  else begin
                    g_addr <= rec_wa; g_din <= {srcb, rec_lo};
                    g_we <= 1; g_req <= 1; sd_busy <= 1;
                  end
                  rec_len <= rec_len + 13'd1;
                end
              end
            end
          end
        end

        G_PRM: if (pi == pneed) begin
          if (glop >= 8'h30 && glop <= 8'h33) begin       // POLY header: n
            glpoly3 <= glop[1];
            glpfill <= glfill && (pbuf[0] >= 8'd3);
            glph <= 0; glnv <= pbuf[0]; pi <= 0;
            pneed <= glop[1] ? 5'd6 : 5'd4;
            if (pbuf[0] == 8'd0) begin                    // n=0: recorded
              if (!rec && !rskip) begin                   //   as-is; live =
                if (ef_wp - ef_rp != 4'd8) begin          //   bad parameter
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end
              rskip <= 0;
              glst <= G_OP;
            end else glst <= G_PV;
          end else glst <= G_RUN;
        end else if (src_ne && !(rec && sd_busy)) begin
          pbuf[pi] <= srcb;
          if (rp) begin rpb0 <= rpb1; rp_have <= rp_have - 2'd1;
                        rp_off <= rp_off + 13'd1; end
          else if (glmode) tq_rp <= tq_rp + 3'd1;
          else cf_rp <= cf_rp + 6'd1;
          pi <= pi + 5'd1;
          if (rec && !rskip && glop != 8'h43) begin       // stream to store
            if (rec_len >= 13'd4092) begin   // slot full: abort
              epush(8'd7); cldef[rec_slot] <= 1'b0; rec <= 0; rskip <= 1;
            end else begin
              if (!rec_len[0]) rec_lo <= srcb;
              else begin
                g_addr <= rec_wa; g_din <= {srcb, rec_lo};
                g_we <= 1; g_req <= 1; sd_busy <= 1;
              end
              rec_len <= rec_len + 13'd1;
            end
          end
        end

        G_RUN: if ((rec && glop != 8'h43) || rskip) begin // recorded/skipped
          rskip <= 0; glst <= G_OP;
        end else if (gl_can) begin
          glst <= G_OP;                                   // default: done
          case (glop)
            8'h01: ;                                      // NOOP
            8'h02: begin flip_pend <= 1; state <= S_FLIP; end   // FLIP
            8'h03: draw_pg <= disp_pg;                    // PGSYNC
            8'h04: begin                                  // RESETF
              cldef <= 64'd0; rec <= 0; glfm <= 0;
              par[0] <= 16'd256; par[4] <= 16'd256; par[8] <= 16'd256;
              par[1]<=0; par[2]<=0; par[3]<=0; par[5]<=0; par[6]<=0; par[7]<=0;
              par[9]<=0; par[10]<=0; par[11]<=0;
              par[12] <= 16'd256;
              par[13]<=0; par[14]<=0; par[15]<=0; par[16]<=0;
              par[17]<=0; par[18]<=0; par[19]<=0; par[20]<=0;
              par[21] <= 16'd3; par[22] <= 0;
              par[23] <= 16'd16; par[24] <= 16'd32767;
              glfill <= 0; c2x <= 0; c2y <= 0; c3x <= 0; c3y <= 0; c3z <= 0;
              glproj <= 16'd60; gldist <= 0; rcol <= 16'hFFFF;
              jsrc <= 0; jbase <= MB; jlast <= 4'd11; jcnt <= 0;
              jnext <= J_RST2; state <= J_WR;
              glvrp[0] <= 0; glvrp[1] <= 0; glvrp[2] <= 0;
              glorg[0] <= 0; glorg[1] <= 0; glorg[2] <= 0;
              glh <= 0; glyy <= 0; glch <= 0; glcy <= 0; glpmode <= 0;
            end
            8'h05: begin wcnt <= pw0; glst <= G_WAIT; end // WAIT
            8'h06: begin rcol <= prgb;                    // COLOR
              cm_we <= 1; cm_wa <= RBS + 10'd1; cm_wd <= prgb; end
            8'h07: begin                                  // FLOOD: viewport
              gbcol <= prgb; glcls <= 0;
              gbx0 <= par[17]; gby0 <= par[18];
              gbx1 <= par[19]; gby1 <= par[20];
              state <= W_BOX0;
            end
            8'h08: begin                                  // POINT: degenerate
              wx0 <= c2x; wy0 <= c2y; wx1 <= c2x; wy1 <= c2y;   //   2D line
              csn <= 0; glact <= 1; state <= S_CS;
            end
            8'h09: begin                                  // POINT3: degenerate
              f3x <= c3x; f3y <= c3y; f3z <= c3z;         //   3D line
              m3x <= c3x; m3y <= c3y; m3z <= c3z;
              g3t <= 0; k <= 0; g2n <= G_OP; glst <= G_3L;
            end
            8'h0F: begin                                  // CLEARS: BOTH pages
              gbcol <= prgb; glcls <= 2'd1;
              gbx0 <= 0; gby0 <= 0; gbx1 <= 16'd479; gby1 <= 16'd271;
              state <= W_BOX0;
            end
            8'h10: begin c2x <= pw0; c2y <= pw1; end      // MOVE
            8'h11: begin c2x <= c2x + pw0; c2y <= c2y + pw1; end
            8'h12: begin c3x <= pw0; c3y <= pw1; c3z <= pw2; end
            8'h13: begin c3x <= c3x + pw0; c3y <= c3y + pw1;
                         c3z <= c3z + pw2; end
            8'h28, 8'h29: begin                           // DRAW / DRAWR
              wx0 <= c2x; wy0 <= c2y;
              wx1 <= glop[0] ? c2x + pw0 : pw0;
              wy1 <= glop[0] ? c2y + pw1 : pw1;
              c2x <= glop[0] ? c2x + pw0 : pw0;
              c2y <= glop[0] ? c2y + pw1 : pw1;
              csn <= 0; glact <= 1; state <= S_CS;
            end
            8'h2A, 8'h2B: begin                           // DRAW3 / DRAWR3
              f3x <= c3x; f3y <= c3y; f3z <= c3z;
              m3x <= glop[0] ? c3x + pw0 : pw0;
              m3y <= glop[0] ? c3y + pw1 : pw1;
              m3z <= glop[0] ? c3z + pw2 : pw2;
              c3x <= glop[0] ? c3x + pw0 : pw0;
              c3y <= glop[0] ? c3y + pw1 : pw1;
              c3z <= glop[0] ? c3z + pw2 : pw2;
              g3t <= 0; k <= 0; g2n <= G_OP; glst <= G_3L;
            end
            8'h34, 8'h35: begin                           // RECT / RECTR
              nbx <= glop[0] ? c2x + pw0 : pw0;           // target corner
              nby <= glop[0] ? c2y + pw1 : pw1;
              if (glfill) begin
                gbcol <= rcol; glcls <= 0; mdph <= 0; state <= W_RM;
              end else begin
                gred <= 0; glst <= G_RE;
              end
            end
            8'h43: begin                                  // "CA " / "CX "
              if (pbuf[0] == 8'h58 && pbuf[1] == 8'h20) ; // CX: already hex
              else if (pbuf[0] == 8'h41 && pbuf[1] == 8'h20)
                glmode <= 1'b1;                          // -> ASCII (10d)
              else epush(8'd2);
            end
            // ---- stage 10b: the matrix verbs -------------------------------
            8'h90: begin                                  // MDIDEN
              jsrc <= 0; jbase <= MB; jlast <= 4'd11; jcnt <= 0;
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              jnext <= C_MLA; state <= J_WR;
            end
            8'h91: begin glorg[0] <= pw0; glorg[1] <= pw1;   // MDORG
                         glorg[2] <= pw2; end
            8'h92: begin                                  // MDSCAL
              jsrc <= 3'd2; jbase <= SB; jlast <= 4'd11; jcnt <= 0;
              cmode <= 2'd0; ci <= 0; cj <= 0; ck <= 0; csum <= 0; mtf <= 0;
              jnext <= C_OGA; state <= J_WR;
            end
            8'h93, 8'h94, 8'h95: begin                    // MDROTX/Y/Z
              cax <= glop[1:0] - 2'd3; ang <= pw0; vwf <= 0;
              state <= C_NRM;
            end
            8'h96: begin                                  // MDTRAN
              jsrc <= 3'd3; jbase <= SB; jlast <= 4'd11; jcnt <= 0;
              cmode <= 2'd0; ci <= 0; cj <= 0; ck <= 0; csum <= 0; mtf <= 0;
              jnext <= C_MLA; state <= J_WR;
            end
            8'h97: begin                                  // MDMATX: 12 int16
              jsrc <= 3'd4; jbase <= MB; jlast <= 4'd11; jcnt <= 0;
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              jnext <= C_MLA; state <= J_WR;
            end
            8'hA0: begin                                  // VWIDEN
              jsrc <= 0; jbase <= VB; jlast <= 4'd8; jcnt <= 0;
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              jnext <= C_MLA; state <= J_WR;
            end
            8'hA1: begin                                  // VWRPT
              glvrp[0] <= pw0; glvrp[1] <= pw1; glvrp[2] <= pw2;
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA;
            end
            8'hA3, 8'hA4, 8'hA5: begin                    // VWROTX/Y/Z: the
              cax <= glop[1:0] - 2'd3;                    //   viewer orbits,
              ang <= 16'd0 - pw0; vwf <= 1;               //   so -angle
              state <= C_NRM;
            end
            8'hA7: begin                                  // VWMATX: 9 int16
              jsrc <= 3'd4; jbase <= VB; jlast <= 4'd8; jcnt <= 0;
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              jnext <= C_MLA; state <= J_WR;
            end
            8'hA8: begin glh <= pw0;                      // DISTH
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA; end
            8'hA9: begin glyy <= pw0;                     // DISTY
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA; end
            8'hAA: begin glch <= pbuf[0][0];              // CLIPH
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA; end
            8'hAB: begin glcy <= pbuf[0][0];              // CLIPY
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA; end
            8'hAF: begin                                  // CONVRT
              f3x <= c3x; f3y <= c3y; f3z <= c3z;
              m3x <= c3x; m3y <= c3y; m3z <= c3z;
              glcvt <= 1;              // G_3L launches S_MAC; CV_X captures
              g3t <= 0; k <= 0; g2n <= G_OP; glst <= G_3L;
            end
            8'hB0:                                        // PROJCT
              if ($signed(pw0) < 0 || $signed(pw0) > 16'sd179) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else begin
                glproj <= pw0; glpmode <= 1;
                cm_we <= 1; cm_wa <= RBS + 10'd2; cm_wd <= pw0;
                cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
                state <= C_MLA;
              end
            8'hB1: begin gldist <= pw0;                   // DISTAN
              cm_we <= 1; cm_wa <= RBS + 10'd3; cm_wd <= pw0;
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA; end
            8'hB2: begin par[17] <= pw0; par[19] <= pw1;  // VWPORT x1 x2 y1 y2
                         par[18] <= pw2; par[20] <= pw3;
                         wvk <= 0; k <= 0; glst <= G_WV; end
            8'hB3: begin par[13] <= pw0; par[15] <= pw1;  // WINDOW x1 x2 y1 y2
                         par[14] <= pw2; par[16] <= pw3;
                         // K recompose (if any) launches from G_WV's tail
                         wvk <= glpmode; k <= 0; glst <= G_WV; end
            8'hE0: begin glfill <= pbuf[0][0];            // PRMFIL
              cm_we <= 1; cm_wa <= RBS; cm_wd <= {15'd0, pbuf[0][0]}; end
            8'hC0: begin                                  // AREA (10g)
              afbc <= rcol;                               //   pen-bounded
              wx0 <= c2x; wy0 <= c2y;                     //   seed -> outcode
              glact <= 1; state <= AF_MAP0;
            end
            8'hC1: begin                                  // AREABC r g b
              afbc <= prgb;
              wx0 <= c2x; wy0 <= c2y;
              glact <= 1; state <= AF_MAP0;
            end
            8'hEB:                                        // LINFUN (10f)
              if (pbuf[0] > 8'd4) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else begin
                glfm <= pbuf[0][2:0];
                glact <= 1; state <= W_LF;                // one GMODE write
              end
            // ---- stage 10e: read-back ------------------------------------
            8'h61: begin                                  // FLAGRD n
              k <= 0; glst <= G_RBP;
              case (pbuf[0])
                8'd1: begin rbp_a <= RBS;          rbp_n <= 4'd1; end
                8'd2: begin rbp_a <= RBS + 10'd1;  rbp_n <= 4'd1; end
                8'd3: begin rbp_a <= RBS + 10'd2;  rbp_n <= 4'd1; end
                8'd4: begin rbp_a <= RBS + 10'd3;  rbp_n <= 4'd1; end
                8'd5: begin rbp_a <= RBS + 10'd4;  rbp_n <= 4'd4; end
                8'd6: begin rbp_a <= RBS + 10'd8;  rbp_n <= 4'd4; end
                8'd9: begin rbp_a <= RBS + 10'd12; rbp_n <= 4'd2; end
                default: begin glst <= G_OP;              // unknown flag
                  if (ef_wp - ef_rp != 4'd8) begin
                    ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
                end
              endcase
            end
            8'h62: begin                                  // MATXRD 1|2
              k <= 0; glst <= G_RBP;
              case (pbuf[0])
                8'd1: begin rbp_a <= 10'd0;  rbp_n <= 4'd12; end   // M
                8'd2: begin rbp_a <= 10'd16; rbp_n <= 4'd9;  end   // VR
                default: begin glst <= G_OP;
                  if (ef_wp - ef_rp != 4'd8) begin
                    ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
                end
              endcase
            end
            8'h76: begin                                  // CLRD n
              if (pbuf[0] >= 8'd64) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else if (!cldef[pbuf[0][5:0]]) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd6; ef_wp <= ef_wp + 4'd1; end
              end else begin
                rd_slot <= pbuf[0][5:0]; rdo <= 0; glst <= G_RD0;
              end
            end
            8'h78: begin                                  // CLMOD n b off
              if (rp) begin                               //   no self-patching
                if (ef_wp - ef_rp != 4'd8) begin          //   mid-replay
                  ef[ef_wp[2:0]] <= 8'd5; ef_wp <= ef_wp + 4'd1; end
              end else if (pbuf[0] >= 8'd64) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else if (!cldef[pbuf[0][5:0]]) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd6; ef_wp <= ef_wp + 4'd1; end
              end else begin
                rd_slot <= pbuf[0][5:0];
                rdo <= {pbuf[3][4:0], pbuf[2]}; glst <= G_MD0;
              end
            end

            // ---- stage 10c: the list verbs -----------------------------
            8'h71: begin                                  // stray CLEND
              if (ef_wp - ef_rp != 4'd8) begin            //   (a real one is
                ef[ef_wp[2:0]] <= 8'd5;                   //   caught at G_OP
                ef_wp <= ef_wp + 4'd1; end                //   while recording)
            end
            8'h70: begin                                  // CLBEG
              if (rp) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd5; ef_wp <= ef_wp + 4'd1; end
              end else if (pbuf[0] >= 8'd64) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else begin
                rec <= 1; rec_slot <= pbuf[0][5:0]; rec_len <= 0;
                cldef[pbuf[0][5:0]] <= 1'b0;
              end
            end
            8'h79: begin                                  // CLAPP (P8X)
              if (rp) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd5; ef_wp <= ef_wp + 4'd1; end
              end else if (pbuf[0] >= 8'd64) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else if (!cldef[pbuf[0][5:0]]) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd6; ef_wp <= ef_wp + 4'd1; end
              end else begin
                rec_slot <= pbuf[0][5:0]; cldef[pbuf[0][5:0]] <= 1'b0;
                glst <= G_AL0;           // fetch the stored length first
              end
            end
            8'h72, 8'h73: begin                           // CLRUN / CLOOP
              if (rp) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd5; ef_wp <= ef_wp + 4'd1; end
              end else if (pbuf[0] >= 8'd64) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else if (!cldef[pbuf[0][5:0]]) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd6; ef_wp <= ef_wp + 4'd1; end
              end else if (glop == 8'h73 && {pbuf[2], pbuf[1]} == 16'd0)
                ;                        // CLOOP 0 times: nothing to do
              else begin
                rp_slot <= pbuf[0][5:0];
                rp_cnt <= (glop == 8'h73) ? {pbuf[2], pbuf[1]} : 16'd1;
                glst <= G_RL0;
              end
            end
            8'h74: begin                                  // CLDEL
              if (pbuf[0] >= 8'd64) begin
                if (ef_wp - ef_rp != 4'd8) begin
                  ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
              end else cldef[pbuf[0][5:0]] <= 1'b0;
            end
            default: ;
          endcase
        end

        G_PV: if (pi == pneed) glst <= G_PRUN;            // one vertex ready
              else if (src_ne && !(rec && sd_busy)) begin
                pbuf[pi] <= srcb;
                if (rp) begin rpb0 <= rpb1; rp_have <= rp_have - 2'd1;
                              rp_off <= rp_off + 13'd1; end
                else if (glmode) tq_rp <= tq_rp + 3'd1;
                else cf_rp <= cf_rp + 6'd1;
                pi <= pi + 5'd1;
                if (rec && !rskip) begin                  // stream to store
                  if (rec_len >= 13'd4092) begin   // slot full: abort
                    epush(8'd7); cldef[rec_slot] <= 1'b0; rec <= 0; rskip <= 1;
                  end else begin
                    if (!rec_len[0]) rec_lo <= srcb;
                    else begin
                      g_addr <= rec_wa; g_din <= {srcb, rec_lo};
                      g_we <= 1; g_req <= 1; sd_busy <= 1;
                    end
                    rec_len <= rec_len + 13'd1;
                  end
                end
              end

        G_PRUN: if (rec || rskip) begin      // recorded/skipped: count only
          glnv <= glnv - 8'd1; pi <= 0;
          if (glnv == 8'd1) begin rskip <= 0; glst <= G_OP; end
          else glst <= G_PV;
        end else if (gl_can) begin                        // consume the vertex
          glnv <= glnv - 8'd1; pi <= 0;
          glst <= (glnv == 8'd1) ? (glpfill ? G_OP : G_PCLOSE) : G_PV;
          vpx <= pvx; vpy <= pvy; vpz <= pvz;
          case (glph)
            2'd0: begin                                   // first: remember it
              vfx <= pvx; vfy <= pvy; vfz <= pvz;
              glph <= 2'd1;
            end
            2'd1: begin
              glph <= 2'd2;
              if (!glpfill) begin                         // outline: edge 0-1
                if (glpoly3) begin
                  f3x <= vpx; f3y <= vpy; f3z <= vpz;   // OLD vp: staged
                  m3x <= pvx; m3y <= pvy; m3z <= pvz;   //   before vp<=pv
                  g3t <= 0; k <= 0;
                  g2n <= (glnv == 8'd1) ? G_PCLOSE : G_PV;
                  glst <= G_3L;
                end else begin
                  wx0 <= vpx; wy0 <= vpy; wx1 <= pvx; wy1 <= pvy;
                  csn <= 0; glact <= 1; state <= S_CS;
                end
              end                                         // fill: wait for 3rd
            end
            default:
              if (glpfill) begin                          // fan tri vf,vp,v
                if (glpoly3) begin
                  f3x <= vfx; f3y <= vfy; f3z <= vfz;
                  m3x <= vpx; m3y <= vpy; m3z <= vpz;     // OLD vp
                  t3x <= pvx; t3y <= pvy; t3z <= pvz;
                  g3t <= 1; k <= 0;
                  g2n <= (glnv == 8'd1) ? G_OP : G_PV;
                  glst <= G_3L;
                end else begin                            // 2D: map-only fill
                  g2n <= (glnv == 8'd1) ? G_OP : G_PV;    // where to resume
                  k <= 0;
                  glst <= G_2D;                           // load the q lanes
                end
              end else begin                              // outline: next edge
                if (glpoly3) begin
                  f3x <= vpx; f3y <= vpy; f3z <= vpz;   // OLD vp: staged
                  m3x <= pvx; m3y <= pvy; m3z <= pvz;   //   before vp<=pv
                  g3t <= 0; k <= 0;
                  g2n <= (glnv == 8'd1) ? G_PCLOSE : G_PV;
                  glst <= G_3L;
                end else begin
                  wx0 <= vpx; wy0 <= vpy; wx1 <= pvx; wy1 <= pvy;
                  csn <= 0; glact <= 1; state <= S_CS;
                end
              end
          endcase
        end

        G_PCLOSE: if (gl_can) begin                       // closing edge vp->vf
          glst <= G_OP;
          if (glpoly3) begin
            f3x <= vpx; f3y <= vpy; f3z <= vpz;
            m3x <= vfx; m3y <= vfy; m3z <= vfz;
            g3t <= 0; k <= 0; g2n <= G_OP; glst <= G_3L;
          end else begin
            wx0 <= vpx; wy0 <= vpy; wx1 <= vfx; wy1 <= vfy;
            csn <= 0; glact <= 1; state <= S_CS;
          end
        end

        G_RE: if (gl_can) begin                           // RECT outline edges
          gred <= gred + 2'd1;
          if (gred == 2'd3) glst <= G_OP;
          case (gred)                                     // the emulator order
            2'd0: begin wx0 <= c2x; wy0 <= c2y; wx1 <= nbx; wy1 <= c2y; end
            2'd1: begin wx0 <= nbx; wy0 <= c2y; wx1 <= nbx; wy1 <= nby; end
            2'd2: begin wx0 <= nbx; wy0 <= nby; wx1 <= c2x; wy1 <= nby; end
            2'd3: begin wx0 <= c2x; wy0 <= nby; wx1 <= c2x; wy1 <= c2y; end
          endcase
          csn <= 0; glact <= 1; state <= S_CS;
        end

        G_2D: if (gl_can) begin        // load a 2D fan triangle's window
          cm_we <= 1;                  //   coords into the q lanes, then
          case (k[2:0])                //   launch the map-only fill
            3'd0: begin cm_wa <= LQX;          cm_wd <= vfx; end
            3'd1: begin cm_wa <= LQX + 7'd1;   cm_wd <= vpx; end
            3'd2: begin cm_wa <= LQX + 7'd2;   cm_wd <= pvx; end
            3'd3: begin cm_wa <= LQY;          cm_wd <= vfy; end
            3'd4: begin cm_wa <= LQY + 7'd1;   cm_wd <= vpy; end
            default: begin cm_wa <= LQY + 7'd2; cm_wd <= pvy; end
          endcase
          if (k[2:0] == 3'd5) begin
            k <= 0;
            np <= 4'd3; pp <= 0; rfill <= 1; gl2d <= 1;
            glact <= 1; state <= T_MP;
            glst <= g2n;
          end else k <= k + 4'd1;
        end

        G_3L: if (gl_can) begin        // stream staged 3D verts into the
          cm_we <= 1;                  //   LVV lanes (x,y,z per vertex),
          cm_wa <= {6'd7, k[3:0]};            //   LVV + k, then transform
          case (k)
            4'd0: cm_wd <= f3x;  4'd1: cm_wd <= f3y;  4'd2: cm_wd <= f3z;
            4'd3: cm_wd <= m3x;  4'd4: cm_wd <= m3y;  4'd5: cm_wd <= m3z;
            4'd6: cm_wd <= t3x;  4'd7: cm_wd <= t3y;  default: cm_wd <= t3z;
          endcase
          if (k == (g3t ? 4'd8 : 4'd5)) begin
            k <= 0;
            tri_m <= g3t; if (g3t) rfill <= 1;
            mp <= 0; mr <= 0; mk <= 0; acc <= 0;
            glact <= 1; state <= S_MAC;
            glst <= g2n;
          end else k <= k + 4'd1;
        end

        G_WV: begin                    // mirror WINDOW/VWPORT into RBS
          cm_we <= 1;                  //   (glop[0]: B3 window, B2 vwport)
          cm_wa <= RBS + (glop[0] ? 10'd4 : 10'd8) + {8'd0, k[1:0]};
          cm_wd <= (k[1:0] == 2'd0) ? pw0 : (k[1:0] == 2'd1) ? pw1
                 : (k[1:0] == 2'd2) ? pw2 : pw3;
          if (k[1:0] == 2'd3) begin
            k <= 0; glst <= G_OP;
            if (wvk) begin             // WINDOW moved under PROJCT: K tracks
              wvk <= 0;
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA;
            end
          end else k <= k + 4'd1;
        end

        G_RBP: begin                   // push rbp_n lane words to the RB
          case (k[1:0])                //   FIFO, low byte first; stall on
            2'd0: begin cm_aa <= rbp_a; k <= 4'd1; end       // full
            2'd1: k <= 4'd2;
            2'd2: if (!rb_full) begin
              rbf[rb_wp[4:0]] <= cm_qa[7:0];
              rb_wp <= rb_wp + 6'd1; k <= 4'd3;
            end
            default: if (!rb_full) begin
              rbf[rb_wp[4:0]] <= cm_qa[15:8];
              rb_wp <= rb_wp + 6'd1;
              rbp_a <= rbp_a + 10'd1; k <= 0;
              if (rbp_n == 4'd1) glst <= G_OP;
              else rbp_n <= rbp_n - 4'd1;
            end
          endcase
        end

        G_RD0: if (!sd_busy && !g_req) begin  // CLRD: fetch one halfword
          g_addr <= {2'd0, 1'b1, 2'd0, rd_slot, rdo[11:0]};
          g_we <= 0; g_req <= 1; sd_busy <= 1; glst <= G_RD1;
        end
        G_RD1: if (g_ready) begin
          rd_lo <= g_dout[7:0]; rd_hi <= g_dout[15:8]; glst <= G_RD2;
        end
        G_RD2: if (!rb_full) begin            // push low byte (stall on full)
          rbf[rb_wp[4:0]] <= rd_lo; rb_wp <= rb_wp + 6'd1;
          if (rdo == 13'd0) glst <= G_RD3;    // header: both bytes always
          else if (rdn == 13'd1) glst <= G_OP;   // odd tail: done
          else begin rdn <= rdn - 13'd1; glst <= G_RD3; end
        end
        G_RD3: if (!rb_full) begin            // push high byte
          rbf[rb_wp[4:0]] <= rd_hi; rb_wp <= rb_wp + 6'd1;
          rdo <= rdo + 13'd2;
          if (rdo == 13'd0) begin             // that was the length halfword
            rdn <= {rd_hi[4:0], rd_lo};
            glst <= ({rd_hi, rd_lo} == 16'd0) ? G_OP : G_RD0;
          end else begin
            if (rdn == 13'd1) glst <= G_OP;
            else begin rdn <= rdn - 13'd1; glst <= G_RD0; end
          end
        end

        G_MD0: if (!sd_busy && !g_req) begin  // CLMOD: read the length
          g_addr <= {2'd0, 1'b1, 2'd0, rd_slot, 12'd0};
          g_we <= 0; g_req <= 1; sd_busy <= 1; glst <= G_MD1;
        end
        G_MD1: if (g_ready) begin             // offset must be inside
          if ({3'd0, rdo} >= g_dout) begin
            if (ef_wp - ef_rp != 4'd8) begin
              ef[ef_wp[2:0]] <= 8'd2; ef_wp <= ef_wp + 4'd1; end
            glst <= G_OP;
          end else glst <= G_MD2;
        end
        G_MD2: if (!sd_busy && !g_req) begin  // read the target halfword
          g_addr <= {2'd0, 1'b1, 2'd0, rd_slot, mdba[11:1], 1'b0};
          g_we <= 0; g_req <= 1; sd_busy <= 1; glst <= G_MD3;
        end
        G_MD3: if (g_ready) begin             // write it back, one byte new
          g_addr <= {2'd0, 1'b1, 2'd0, rd_slot, mdba[11:1], 1'b0};
          g_din <= rdo[0] ? {pbuf[1], g_dout[7:0]}
                          : {g_dout[15:8], pbuf[1]};
          g_we <= 1; g_req <= 1; sd_busy <= 1; glst <= G_OP;
        end

        G_WAIT: begin                                     // WAIT: real frames
          if (wcnt == 16'd0) glst <= G_OP;
          else if (frame_tick) wcnt <= wcnt - 16'd1;
        end

        // ---- stage 10c: CLEND finish -- flush the dangling byte, write
        // the length halfword, set the DEFINED bit ------------------------
        G_LE0: if (!sd_busy && !g_req) begin
          if (rec_len[0]) begin
            g_addr <= rec_wa; g_din <= {8'h00, rec_lo};
            g_we <= 1; g_req <= 1; sd_busy <= 1;
          end
          glst <= G_LE1;
        end
        G_LE1: if (!sd_busy && !g_req) begin
          g_addr <= {2'd0, 1'b1, 2'd0, rec_slot, 12'd0};
          g_din <= {3'd0, rec_len};
          g_we <= 1; g_req <= 1; sd_busy <= 1;
          glst <= G_LE2;
        end
        G_LE2: if (!sd_busy) begin
          cldef[rec_slot] <= 1'b1; rec <= 0; glst <= G_OP;
        end

        // CLAPP: read the stored length, resume recording after it
        G_AL0: if (!sd_busy && !g_req) begin
          g_addr <= {2'd0, 1'b1, 2'd0, rec_slot, 12'd0};
          g_we <= 0; g_req <= 1; sd_busy <= 1;
          glst <= G_AL1;
        end
        G_AL1: if (g_ready) begin
          rec_len <= g_dout[12:0]; rec <= 1; glst <= G_OP;
        end

        // CLRUN/CLOOP: read the length, then the fetcher takes over
        G_RL0: if (!sd_busy && !g_req) begin
          g_addr <= CL_BASE + {5'd0, rp_slot, 12'd0};
          g_we <= 0; g_req <= 1; sd_busy <= 1;
          glst <= G_RL1;
        end
        G_RL1: if (g_ready) begin
          rp_len <= g_dout[12:0]; rp_off <= 0; rp_have <= 0;
          rp <= 1; glst <= G_OP;
        end

        default: glst <= G_OP;
      endcase
    end
  end

  // GL busy: the consumer is mid-command or bytes wait in the FIFO
  // busy covers the consumer AND the walker: with GESTAT retired,
  // GLSTAT bit6 is how software waits out its own GL work
  wire glbusy = (glst != G_OP) || cf_ne || (state != S_IDLE) || rp;

  always @(*) begin
    case (a[2:0])
      3'd1:    rdata = {cf_full, glbusy, 4'd0, ef_ne, rb_ne};  // GLSTAT
      3'd2:    rdata = rb_ne ? rbf[rb_rp[4:0]] : 8'h00;        // GLRB
      3'd3:    rdata = ef_ne ? ef[ef_rp[2:0]] : 8'h00;        // GLERR
      3'd4:    rdata = 8'h47;                 // GLID: 'G'
      default: rdata = 8'hFF;
    endcase
  end

endmodule
