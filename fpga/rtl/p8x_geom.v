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

  // gfx register master (p8x_top muxes this over the CPU while gm_own).
  output            gm_own,
  output reg        gm_wr,
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
  reg [6:0]  state;
  localparam S_IDLE=0,  S_NEXT=6,
             S_MAC=9,   S_MACW=10,
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
             C_RCN=88,  CV_X=89,   CV_XW=90,  CV_YW=91,
             C_OGB=92,  C_OGC=93,  C_MTB=94,  C_MTC=95,  C_MLC=96,
             C_MLW=97,  C_CPB=98,  C_CPC=99,  J_RST2=100;

  reg [15:0] rcol;                   // the GL pen (COLOR)
  reg        rfill;                  // T-path: FILL (GL fills always set it)
  reg        tri_m;                  // MAC writeback goes to tv (TRI mode)
  reg [3:0]  k;                      // fetch word / general microstep
  reg [15:0] v [0:8];                // fetched vertex words (TRI: 9)
  reg [15:0] tvx [0:2];              // TRI: transformed vertices
  reg [15:0] tvy [0:2];
  reg [15:0] tvz [0:2];
  reg [15:0] qx [0:7];               // near-clipped polygon
  reg [15:0] qy [0:7];
  reg [15:0] qz [0:7];
  reg [15:0] qsx [0:7];              // ...mapped to screen space
  reg [15:0] qsy [0:7];
  reg [3:0]  np;                     // polygon vertex count
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
  reg [7:0]  cf [0:63];              // command FIFO (poll GLSTAT bit7)
  reg [6:0]  cf_wp, cf_rp;
  wire [6:0] cf_cnt  = cf_wp - cf_rp;
  wire       cf_ne   = (cf_cnt != 7'd0);
  wire       cf_full = cf_cnt[6];
  reg [7:0]  ef [0:15];              // error FIFO: 1 unknown opcode,
  reg [4:0]  ef_wp, ef_rp;           //   2 bad parameter, 3 mode not
  wire       ef_ne = (ef_wp != ef_rp);  // fitted, 4 command-FIFO overflow
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
  reg [15:0] cmxa [0:63];            // the mirror pair: written together,
  reg [15:0] cmxb [0:63];            //   read on independent ports
  reg [5:0]  cm_aa, cm_ab;           // read addresses
  reg [15:0] cm_qa, cm_qb;           // registered read data
  reg        cm_we;
  reg [5:0]  cm_wa;
  reg [15:0] cm_wd;
  integer ii;
  initial begin                      // power-on: both masters identity
    for (ii = 0; ii < 64; ii = ii + 1) begin cmxa[ii]=0; cmxb[ii]=0; end
    cmxa[0]=16'd256;  cmxa[4]=16'd256;  cmxa[8]=16'd256;
    cmxb[0]=16'd256;  cmxb[4]=16'd256;  cmxb[8]=16'd256;
    cmxa[16]=16'd256; cmxa[20]=16'd256; cmxa[24]=16'd256;
    cmxb[16]=16'd256; cmxb[20]=16'd256; cmxb[24]=16'd256;
  end
  always @(posedge clk) begin
    if (cm_we) begin cmxa[cm_wa] <= cm_wd; cmxb[cm_wa] <= cm_wd; end
    cm_qa <= cmxa[cm_aa];
    cm_qb <= cmxb[cm_ab];
  end
  localparam [5:0] MB=6'd0, VB=6'd16, SB=6'd32, TB=6'd48;
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
  // far-pass polygon (TRI yon clip)
  reg [15:0] q2x [0:7]; reg [15:0] q2y [0:7]; reg [15:0] q2z [0:7];
  reg [3:0]  nq2;
  reg        glact;                  // pipeline exit returns to S_IDLE
  reg        gl2d;                   // suppress projection in the T-map
  reg [1:0]  glcls;                  // CLEARS page phase (0 = plain box)
  reg [2:0]  glst;                   // consumer FSM
  reg [15:0] wcnt;                   // WAIT frames remaining
  reg [15:0] gbx0, gby0, gbx1, gby1, gbcol;    // the box issuer's box
  localparam G_OP=0, G_PRM=1, G_RUN=2, G_PV=3, G_PRUN=4, G_PCLOSE=5,
             G_WAIT=6, G_RE=7;
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
  reg  [15:0] md_a, md_b, md_c;
  wire [15:0] md_q;
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
  // the finished element, with the T-column tails folded in (msT is the
  // prefetched ms[9+ci]; operands themselves arrive through cm_qa/cm_qb)
  wire [15:0] cm_res = csum + md_q
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

  // MAC operand select (registered indices, combinational product)
  wire [15:0] mac_m = par[{2'd0, mr} * 3 + {2'd0, mk}];
  wire [15:0] mac_v = v[{1'd0, mp} * 3 + {1'd0, mk}];
  wire signed [31:0] mac_p = $signed(mac_m) * $signed(mac_v);
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

  integer i;
  always @(posedge clk) begin
    md_go <= 1'b0;
    gm_wr <= 1'b0;
    cm_we <= 1'b0;
    if (rst) begin
      state <= S_IDLE;
      draw_pg <= 0; disp_pg <= 0; flip_pend <= 0;
      seq <= 0; mdph <= 0; csn <= 0;
      tri_m <= 0; rfill <= 0; np <= 0; pp <= 0; ft <= 0;
      cf_wp <= 0; cf_rp <= 0; ef_wp <= 0; ef_rp <= 0;
      glst <= G_OP; glop <= 0; pi <= 0; pneed <= 0; glnv <= 0;
      glpoly3 <= 0; glpfill <= 0; glph <= 0; gred <= 0;
      c2x <= 0; c2y <= 0; c3x <= 0; c3y <= 0; c3z <= 0;
      glfill <= 0; glproj <= 16'd60; gldist <= 16'd500;
      glact <= 0; gl2d <= 0; glcls <= 0; wcnt <= 0;
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
          if (ef_wp - ef_rp != 5'd16) begin ef[ef_wp[3:0]] <= 8'd4;
                                            ef_wp <= ef_wp + 5'd1; end
        end else begin
          cf[cf_wp[5:0]] <= wdata;
          cf_wp <= cf_wp + 7'd1;
        end
      end
      if (gl_rd && a[2:0] == 3'd3 && ef_ne)        // GLERR read pops
        ef_rp <= ef_rp + 5'd1;

      // ---- the walker ------------------------------------------------------
      case (state)
        S_IDLE: ;

        // every GL primitive exits here; the record loop is retired
        S_NEXT: begin
          glact <= 0; gl2d <= 0;
          state <= S_IDLE;
        end

        // transform: acc = m[r][0..2] . v[p], then w = (acc>>>8) + t
        S_MAC: begin
          acc <= acc + mac_p;
          if (mk == 2'd2) state <= S_MACW; else mk <= mk + 2'd1;
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
            md_a <= (mdph[0]==1'b0) ? (wx1 - wx0) : (wy1 - wy0);
            md_b <= par[23] - wz0;  md_c <= wz1 - wz0;
            md_go <= 1; state <= S_NCW;
          end else if (z1_near) begin
            md_a <= (mdph[0]==1'b0) ? (wx0 - wx1) : (wy0 - wy1);
            md_b <= par[23] - wz1;  md_c <= wz0 - wz1;
            md_go <= 1; state <= S_NCW;
          end else begin mdph <= 0; state <= S_FC; end
        end
        S_NCW: if (md_done) begin
          if (z0_near) begin
            if (mdph[0]==1'b0) begin wx0 <= wx0 + md_q; mdph <= 2'd1; end
            else begin wy0 <= wy0 + md_q; wz0 <= par[23]; mdph <= 0; end
          end else begin
            if (mdph[0]==1'b0) begin wx1 <= wx1 + md_q; mdph <= 2'd1; end
            else begin wy1 <= wy1 + md_q; wz1 <= par[23]; mdph <= 0; end
          end
          state <= S_NC;
        end
        // yon clip (stage 10b), the mirror image against par[24]
        S_FC: begin
          if (z0_far && z1_far) begin state <= S_NEXT; end
          else if (z0_far) begin
            md_a <= (mdph[0]==1'b0) ? (wx1 - wx0) : (wy1 - wy0);
            md_b <= par[24] - wz0;  md_c <= wz1 - wz0;
            md_go <= 1; state <= S_FCW;
          end else if (z1_far) begin
            md_a <= (mdph[0]==1'b0) ? (wx0 - wx1) : (wy0 - wy1);
            md_b <= par[24] - wz1;  md_c <= wz0 - wz1;
            md_go <= 1; state <= S_FCW;
          end else begin mdph <= 0; state <= S_PRJ; end
        end
        S_FCW: if (md_done) begin
          if (z0_far) begin
            if (mdph[0]==1'b0) begin wx0 <= wx0 + md_q; mdph <= 2'd1; end
            else begin wy0 <= wy0 + md_q; wz0 <= par[24]; mdph <= 0; end
          end else begin
            if (mdph[0]==1'b0) begin wx1 <= wx1 + md_q; mdph <= 2'd1; end
            else begin wy1 <= wy1 + md_q; wz1 <= par[24]; mdph <= 0; end
          end
          state <= S_FC;
        end

        // perspective projection: 4 muldivs (x0 y0 x1 y1)
        S_PRJ: begin
          case (mdph)
            2'd0: begin md_a <= wx0; md_c <= wz0; end
            2'd1: begin md_a <= wy0; md_c <= wz0; end
            2'd2: begin md_a <= wx1; md_c <= wz1; end
            2'd3: begin md_a <= wy1; md_c <= wz1; end
          endcase
          md_b <= par[12]; md_go <= 1; state <= S_PRJW;
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
            if (oca[0])      begin md_a <= wy1 - wy0; md_b <= par[13] - wx0; md_c <= wx1 - wx0; end
            else if (oca[1]) begin md_a <= wy1 - wy0; md_b <= par[15] - wx0; md_c <= wx1 - wx0; end
            else if (oca[2]) begin md_a <= wx1 - wx0; md_b <= par[14] - wy0; md_c <= wy1 - wy0; end
            else             begin md_a <= wx1 - wx0; md_b <= par[16] - wy0; md_c <= wy1 - wy0; end
            md_go <= 1; csn <= csn + 4'd1; state <= S_CSW;
          end
        end
        S_CSW: if (md_done) begin
          if (oca[0])      begin wy0 <= wy0 + md_q; wx0 <= par[13]; end
          else if (oca[1]) begin wy0 <= wy0 + md_q; wx0 <= par[15]; end
          else if (oca[2]) begin wx0 <= wx0 + md_q; wy0 <= par[14]; end
          else             begin wx0 <= wx0 + md_q; wy0 <= par[16]; end
          state <= S_CS;
        end

        // viewport map: 4 muldivs, then the y flip in the apply
        S_MAP: begin
          case (mdph)
            2'd0: begin md_a <= wx0 - par[13]; md_b <= par[19] - par[17]; md_c <= par[15] - par[13]; end
            2'd1: begin md_a <= wy0 - par[14]; md_b <= par[20] - par[18]; md_c <= par[16] - par[14]; end
            2'd2: begin md_a <= wx1 - par[13]; md_b <= par[19] - par[17]; md_c <= par[15] - par[13]; end
            2'd3: begin md_a <= wy1 - par[14]; md_b <= par[20] - par[18]; md_c <= par[16] - par[14]; end
          endcase
          md_go <= 1; state <= S_MAPW;
        end
        S_MAPW: if (md_done) begin
          case (mdph)
            2'd0: px0 <= par[17] + md_q;   2'd1: py0 <= par[20] - md_q;
            2'd2: px1 <= par[17] + md_q;   2'd3: py1 <= par[20] - md_q;
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
          if (par[12] == 16'd0) begin pp <= 0; state <= T_CPY; end
          else state <= T_NCA;
        end
        T_CPY: begin
          qx[pp] <= tvx[pp[1:0]]; qy[pp] <= tvy[pp[1:0]]; qz[pp] <= tvz[pp[1:0]];
          if (pp == 4'd2) begin np <= 4'd3; pp <= 0; state <= T_MP; end
          else pp <= pp + 4'd1;
        end
        T_NCA: begin
          if (pp == 4'd3) begin
            if (np < 4'd3) begin state <= S_NEXT; end
            else if (par[24] == 16'd32767) begin pp <= 0; state <= T_MP; end
            else begin pp <= 0; nq2 <= 0; state <= F_CA; end  // yon fitted
          end else begin
            nax <= tvx[pp[1:0]]; nay <= tvy[pp[1:0]]; naz <= tvz[pp[1:0]];
            nbx <= tvx[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            nby <= tvy[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            nbz <= tvz[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            state <= T_NI0;
          end
        end
        T_NI0: begin                   // classify; keep A; start x-intersect
          nain <= !($signed(naz) < $signed(par[23]));
          nbin <= !($signed(nbz) < $signed(par[23]));
          if (!($signed(naz) < $signed(par[23]))) begin
            qx[np] <= nax; qy[np] <= nay; qz[np] <= naz; np <= np + 4'd1;
          end
          state <= T_NI0W;
        end
        T_NI0W: begin
          if (nain == nbin) begin pp <= pp + 4'd1; state <= T_NCA; end
          else begin
            md_a <= nbx - nax; md_b <= par[23] - naz; md_c <= nbz - naz;
            md_go <= 1; state <= T_NI1;
          end
        end
        T_NI1: if (md_done) begin
          qx[np] <= nax + md_q;
          md_a <= nby - nay; md_b <= par[23] - naz; md_c <= nbz - naz;
          md_go <= 1; state <= T_NI1W;
        end
        T_NI1W: if (md_done) begin
          qy[np] <= nay + md_q; qz[np] <= par[23]; np <= np + 4'd1;
          pp <= pp + 4'd1; state <= T_NCA;
        end

        // ==== stage 10b: the TRI far (yon) pass -- the near pass's mirror,
        // walking the near-clipped polygon qx/qy/qz (np verts) into q2,
        // keeping z<=far and inserting intersections, then copying back ====
        F_CA: begin
          if (pp == np) begin
            if (nq2 < 4'd3) begin state <= S_NEXT; end
            else begin cpi <= 0; state <= F_CP; end
          end else begin
            nax <= qx[pp[2:0]]; nay <= qy[pp[2:0]]; naz <= qz[pp[2:0]];
            nbx <= qx[(pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1];
            nby <= qy[(pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1];
            nbz <= qz[(pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1];
            state <= F_I0;
          end
        end
        F_I0: begin
          nain <= !($signed(par[24]) < $signed(naz));
          nbin <= !($signed(par[24]) < $signed(nbz));
          if (!($signed(par[24]) < $signed(naz))) begin
            q2x[nq2[2:0]] <= nax; q2y[nq2[2:0]] <= nay; q2z[nq2[2:0]] <= naz;
            nq2 <= nq2 + 4'd1;
          end
          state <= F_I0W;
        end
        F_I0W: begin
          if (nain == nbin) begin pp <= pp + 4'd1; state <= F_CA; end
          else begin
            md_a <= nbx - nax; md_b <= par[24] - naz; md_c <= nbz - naz;
            md_go <= 1; state <= F_I1;
          end
        end
        F_I1: if (md_done) begin
          q2x[nq2[2:0]] <= nax + md_q;
          md_a <= nby - nay; md_b <= par[24] - naz; md_c <= nbz - naz;
          md_go <= 1; state <= F_I1W;
        end
        F_I1W: if (md_done) begin
          q2y[nq2[2:0]] <= nay + md_q; q2z[nq2[2:0]] <= par[24];
          nq2 <= nq2 + 4'd1;
          pp <= pp + 4'd1; state <= F_CA;
        end
        F_CP: begin                    // q2 -> q, then the normal map path
          qx[cpi[2:0]] <= q2x[cpi[2:0]];
          qy[cpi[2:0]] <= q2y[cpi[2:0]];
          qz[cpi[2:0]] <= q2z[cpi[2:0]];
          if (cpi + 4'd1 == nq2) begin
            np <= nq2; pp <= 0; state <= T_MP;
          end else cpi <= cpi + 4'd1;
        end

        // project + viewport-map each polygon vertex into qsx/qsy
        T_MP: begin
          if (pp == np) begin
            seq <= 0; state <= T_PENW;   // GL fills only: outline TRIs
          end else begin                 //   draw as DRAW3 edges instead
            cxv <= qx[pp[2:0]]; cyv <= qy[pp[2:0]];
            // gl2d: a 2D fill's vertices are already window-space -- map
            // only, never project, whatever the focal parameter says
            state <= (par[12] != 16'd0 && !gl2d) ? T_PJX : T_MX;
          end
        end
        T_PJX: begin
          md_a <= cxv; md_b <= par[12]; md_c <= qz[pp[2:0]];
          md_go <= 1; state <= T_PJXW;
        end
        T_PJXW: if (md_done) begin cxv <= md_q; state <= T_PJY; end
        T_PJY: begin
          md_a <= cyv; md_b <= par[12]; md_c <= qz[pp[2:0]];
          md_go <= 1; state <= T_PJYW;
        end
        T_PJYW: if (md_done) begin cyv <= md_q; state <= T_MX; end
        T_MX: begin
          md_a <= cxv - par[13]; md_b <= par[19] - par[17]; md_c <= par[15] - par[13];
          md_go <= 1; state <= T_MXW;
        end
        T_MXW: if (md_done) begin qsx[pp[2:0]] <= par[17] + md_q; state <= T_MY; end
        T_MY: begin
          md_a <= cyv - par[14]; md_b <= par[20] - par[18]; md_c <= par[16] - par[14];
          md_go <= 1; state <= T_MYW;
        end
        T_MYW: if (md_done) begin
          qsy[pp[2:0]] <= par[20] - md_q;
          pp <= pp + 4'd1; state <= T_MP;
        end

        // fill: pen once, then fan (0,t,t+1), each sorted then scanned
        T_PENW: begin
          if (seq == 3'd0) begin gm_a<=4'h4; gm_wdata<=rcol[7:0];  gm_wr<=1; seq<=3'd1; end
          else begin gm_a<=4'hD; gm_wdata<=rcol[15:8]; gm_wr<=1; seq<=0;
                     ft <= 4'd1; state <= T_FAN; end
        end
        T_FAN: begin
          if (ft + 4'd1 >= np) begin state <= S_NEXT; end
          else begin
            fx0 <= qsx[0];        fy0 <= qsy[0];
            fx1 <= qsx[ft[2:0]];  fy1 <= qsy[ft[2:0]];
            fx2 <= qsx[ft[2:0] + 3'd1]; fy2 <= qsy[ft[2:0] + 3'd1];
            state <= T_SRT1;
          end
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
          md_a <= fy - fy0; md_b <= fx2 - fx0; md_c <= fy2 - fy0;
          md_go <= 1; state <= T_SXAW;
        end
        T_SXAW: if (md_done) begin fxa <= fx0 + md_q; state <= T_SXB; end
        T_SXB: begin                   // split edge: v0v1 above y1, else v1v2
          if (fy1 == fy0 && !($signed(fy1) <= $signed(fy))) begin
            fxb <= fx1; state <= T_SPAN;         // unreachable guard
          end else if (fy1 == fy0) begin
            fxb <= fx1; state <= T_SPAN;
          end else if ($signed(fy) < $signed(fy1)) begin
            md_a <= fy - fy0; md_b <= fx1 - fx0; md_c <= fy1 - fy0;
            md_go <= 1; state <= T_SXBW;
          end else if (fy2 == fy1) begin
            fxb <= fx1; state <= T_SPAN;
          end else begin
            md_a <= fy - fy1; md_b <= fx2 - fx1; md_c <= fy2 - fy1;
            md_go <= 1; state <= T_SXBW;
          end
        end
        T_SXBW: if (md_done) begin
          fxb <= (($signed(fy) < $signed(fy1)) ? fx0 : fx1) + md_q;
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
          if (fy == fy2 || fy2 == fy0) begin ft <= ft + 4'd1; state <= T_FAN; end
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
            2'd0: begin md_a <= c2x - par[13]; md_b <= par[19] - par[17]; md_c <= par[15] - par[13]; end
            2'd1: begin md_a <= c2y - par[14]; md_b <= par[20] - par[18]; md_c <= par[16] - par[14]; end
            2'd2: begin md_a <= nbx - par[13]; md_b <= par[19] - par[17]; md_c <= par[15] - par[13]; end
            2'd3: begin md_a <= nby - par[14]; md_b <= par[20] - par[18]; md_c <= par[16] - par[14]; end
          endcase
          md_go <= 1; state <= W_RMW;
        end
        W_RMW: if (md_done) begin
          case (mdph)
            2'd0: gbx0 <= par[17] + md_q;   2'd1: gby0 <= par[20] - md_q;
            2'd2: gbx1 <= par[17] + md_q;   2'd3: gby1 <= par[20] - md_q;
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
            md_a <= wx0; md_b <= par[12]; md_c <= cvz;
            md_go <= 1; state <= CV_XW;
          end
        end
        CV_XW: if (md_done) begin
          c2x <= md_q;
          md_a <= wy0; md_b <= par[12]; md_c <= cvz;
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
          cm_we <= 1; cm_wa <= jbase + {2'd0, jcnt}; cm_wd <= jval;
          if (jcnt == jlast) begin jcnt <= 0; state <= jnext; end
          else jcnt <= jcnt + 4'd1;
        end
        J_RST2: begin                  // warm reset, part 2: VR identity
          jsrc <= 0; jbase <= VB; jlast <= 4'd8; jcnt <= 0;
          jnext <= S_IDLE; state <= J_WR;
        end

        // pivot: T = org - (S*org)>>8 -- ms cells fetched from the RAM
        C_OGA: begin
          cm_aa <= SB + {2'd0,ci}*3 + {2'd0,ck};
          state <= C_OGB;
        end
        C_OGB: state <= C_OGC;         // the read pipeline's bubble
        C_OGC: begin
          md_a <= cm_qa; md_b <= glorg[ck]; md_c <= 16'd256;
          md_go <= 1; state <= C_OGW;
        end
        C_OGW: if (md_done) begin
          if (ck == 2'd2) begin
            cm_we <= 1; cm_wa <= SB + 6'd9 + {4'd0,ci};
            cm_wd <= glorg[ci] - (csum + md_q);
            ck <= 0; csum <= 0;
            if (ci == 2'd2) begin ci <= 0; cj <= 0; state <= C_MLA; end
            else begin ci <= ci + 2'd1; state <= C_OGA; end
          end else begin csum <= csum + md_q; ck <= ck + 2'd1; state <= C_OGA; end
        end

        // one product term: fetch both operands, muldiv, accumulate. A
        // mode-0 T column first prefetches ms[9+ci] (the additive tail).
        C_MLA: begin
          if (cj == 2'd3 && cmode == 2'd0 && !mtf) begin
            cm_aa <= SB + 6'd9 + {4'd0,ci}; state <= C_MTB;
          end else begin
            cm_aa <= ((cmode == 2'd2) ? VB : SB) + {2'd0,ci}*3 + {2'd0,ck};
            cm_ab <= (cj == 2'd3) ? (MB + 6'd9 + {4'd0,ck})
                   : (((cmode == 2'd1) ? VB : MB) + {2'd0,ck}*3 + {2'd0,cj});
            state <= C_MLB;
          end
        end
        C_MTB: state <= C_MTC;
        C_MTC: begin msT <= cm_qa; mtf <= 1; state <= C_MLA; end
        C_MLB: state <= C_MLC;
        C_MLC: begin
          md_a <= cm_qa;
          md_b <= (cj == 2'd3 && cmode == 2'd2) ? cm_qb - glvrp[ck] : cm_qb;
          md_c <= 16'd256; md_go <= 1; state <= C_MLW;
        end
        C_MLW: if (md_done) begin
          if (ck == 2'd2) begin
            cm_we <= 1;
            cm_wa <= TB + ((cj == 2'd3) ? 6'd9 + {4'd0,ci}
                                        : {2'd0,ci}*3 + {2'd0,cj});
            cm_wd <= cm_res;
            ck <= 0; csum <= 0; mtf <= 0;
            if (cj == cjmax) begin
              cj <= 0;
              if (ci == 2'd2) begin cpi <= 0; state <= C_CPA; end
              else begin ci <= ci + 2'd1; state <= C_MLA; end
            end else begin cj <= cj + 2'd1; state <= C_MLA; end
          end else begin csum <= csum + md_q; ck <= ck + 2'd1; state <= C_MLA; end
        end

        // land the product where it belongs, then chain
        C_CPA: begin cm_aa <= TB + {2'd0,cpi}; state <= C_CPB; end
        C_CPB: state <= C_CPC;
        C_CPC: begin
          case (cmode)
            2'd0: begin cm_we <= 1; cm_wa <= MB + {2'd0,cpi}; cm_wd <= cm_qa; end
            2'd1: begin cm_we <= 1; cm_wa <= VB + {2'd0,cpi}; cm_wd <= cm_qa; end
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
            md_a <= par[15] - par[13]; md_b <= 16'd128;
            md_c <= tanq;
            md_go <= 1; state <= C_RCKW;
          end
        end
        C_RCKW: if (md_done) begin par[12] <= md_q; state <= C_RCN; end
        C_RCN: begin                   // near/far planes in eye z
          par[23] <= glch ? (($signed(gldist + glh) < 16'sd16)
                             ? 16'd16 : gldist + glh)
                          : 16'd16;
          par[24] <= glcy ? gldist + glyy : 16'd32767;
          state <= S_IDLE;
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
        G_OP: if (cf_ne) begin
          glop <= cf[cf_rp[5:0]]; cf_rp <= cf_rp + 7'd1; pi <= 0;
          case (cf[cf_rp[5:0]])
            8'h01, 8'h02, 8'h03, 8'h04,
            8'h08, 8'h09,
            8'h90, 8'hA0, 8'hAF:        begin pneed <= 5'd0; glst <= G_RUN; end
            8'hE0, 8'hAA, 8'hAB:        begin pneed <= 5'd1; glst <= G_PRM; end
            8'h05, 8'h43, 8'hB0, 8'hB1,
            8'h93, 8'h94, 8'h95,
            8'hA3, 8'hA4, 8'hA5,
            8'hA8, 8'hA9:               begin pneed <= 5'd2; glst <= G_PRM; end
            8'h06, 8'h07, 8'h0F:        begin pneed <= 5'd3; glst <= G_PRM; end
            8'h10, 8'h11, 8'h28, 8'h29,
            8'h34, 8'h35:               begin pneed <= 5'd4; glst <= G_PRM; end
            8'h12, 8'h13, 8'h2A, 8'h2B,
            8'h91, 8'h92, 8'h96, 8'hA1: begin pneed <= 5'd6; glst <= G_PRM; end
            8'h30, 8'h31, 8'h32, 8'h33: begin pneed <= 5'd1; glst <= G_PRM; end
            8'hB2, 8'hB3:               begin pneed <= 5'd8; glst <= G_PRM; end
            8'hA7:                      begin pneed <= 5'd18; glst <= G_PRM; end
            8'h97:                      begin pneed <= 5'd24; glst <= G_PRM; end
            default:                    // unknown opcode: log, skip a byte
              if (ef_wp - ef_rp != 5'd16) begin
                ef[ef_wp[3:0]] <= 8'd1; ef_wp <= ef_wp + 5'd1; end
          endcase
        end

        G_PRM: if (pi == pneed) begin
          if (glop >= 8'h30 && glop <= 8'h33) begin       // POLY header: n
            glpoly3 <= glop[1];
            glpfill <= glfill && (pbuf[0] >= 8'd3);
            glph <= 0; glnv <= pbuf[0]; pi <= 0;
            pneed <= glop[1] ? 5'd6 : 5'd4;
            if (pbuf[0] == 8'd0) begin                    // n=0: bad parameter
              if (ef_wp - ef_rp != 5'd16) begin
                ef[ef_wp[3:0]] <= 8'd2; ef_wp <= ef_wp + 5'd1; end
              glst <= G_OP;
            end else glst <= G_PV;
          end else glst <= G_RUN;
        end else if (cf_ne) begin
          pbuf[pi] <= cf[cf_rp[5:0]];
          cf_rp <= cf_rp + 9'd1; pi <= pi + 5'd1;
        end

        G_RUN: if (gl_can) begin
          glst <= G_OP;                                   // default: done
          case (glop)
            8'h01: ;                                      // NOOP
            8'h02: begin flip_pend <= 1; state <= S_FLIP; end   // FLIP
            8'h03: draw_pg <= disp_pg;                    // PGSYNC
            8'h04: begin                                  // RESETF
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
            8'h06: rcol <= prgb;                          // COLOR
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
              v[0] <= c3x; v[1] <= c3y; v[2] <= c3z;      //   3D line
              v[3] <= c3x; v[4] <= c3y; v[5] <= c3z;
              tri_m <= 0; mp <= 0; mr <= 0; mk <= 0; acc <= 0;
              glact <= 1; state <= S_MAC;
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
              v[0] <= c3x; v[1] <= c3y; v[2] <= c3z;
              v[3] <= glop[0] ? c3x + pw0 : pw0;
              v[4] <= glop[0] ? c3y + pw1 : pw1;
              v[5] <= glop[0] ? c3z + pw2 : pw2;
              c3x <= glop[0] ? c3x + pw0 : pw0;
              c3y <= glop[0] ? c3y + pw1 : pw1;
              c3z <= glop[0] ? c3z + pw2 : pw2;
              tri_m <= 0; mp <= 0; mr <= 0; mk <= 0; acc <= 0;
              glact <= 1; state <= S_MAC;
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
            8'h43:                                        // "CA " / "CX "
              if (pbuf[0] == 8'h58 && pbuf[1] == 8'h20) ; // CX: already hex
              else if (pbuf[0] == 8'h41 && pbuf[1] == 8'h20) begin
                if (ef_wp - ef_rp != 5'd16) begin         // ASCII: stage 10d
                  ef[ef_wp[3:0]] <= 8'd3; ef_wp <= ef_wp + 5'd1; end
              end else
                if (ef_wp - ef_rp != 5'd16) begin
                  ef[ef_wp[3:0]] <= 8'd2; ef_wp <= ef_wp + 5'd1; end
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
              v[0] <= c3x; v[1] <= c3y; v[2] <= c3z;
              v[3] <= c3x; v[4] <= c3y; v[5] <= c3z;
              tri_m <= 0; mp <= 0; mr <= 0; mk <= 0; acc <= 0;
              glcvt <= 1; state <= S_MAC;
            end
            8'hB0:                                        // PROJCT
              if ($signed(pw0) < 0 || $signed(pw0) > 16'sd179) begin
                if (ef_wp - ef_rp != 5'd16) begin
                  ef[ef_wp[3:0]] <= 8'd2; ef_wp <= ef_wp + 5'd1; end
              end else begin
                glproj <= pw0; glpmode <= 1;
                cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
                state <= C_MLA;
              end
            8'hB1: begin gldist <= pw0;                   // DISTAN
              cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
              state <= C_MLA; end
            8'hB2: begin par[17] <= pw0; par[19] <= pw1;  // VWPORT x1 x2 y1 y2
                         par[18] <= pw2; par[20] <= pw3; end
            8'hB3: begin par[13] <= pw0; par[15] <= pw1;  // WINDOW x1 x2 y1 y2
                         par[14] <= pw2; par[16] <= pw3;
                         if (glpmode) begin               // K tracks the window
                           cmode <= 2'd2; ci <= 0; cj <= 0; ck <= 0; csum <= 0;
                           state <= C_MLA;
                         end end
            8'hE0: glfill <= pbuf[0][0];                  // PRMFIL
            default: ;
          endcase
        end

        G_PV: if (pi == pneed) glst <= G_PRUN;            // one vertex ready
              else if (cf_ne) begin
                pbuf[pi] <= cf[cf_rp[5:0]];
                cf_rp <= cf_rp + 9'd1; pi <= pi + 5'd1;
              end

        G_PRUN: if (gl_can) begin                         // consume the vertex
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
                  v[0] <= vpx; v[1] <= vpy; v[2] <= vpz;
                  v[3] <= pvx; v[4] <= pvy; v[5] <= pvz;
                  tri_m <= 0; mp <= 0; mr <= 0; mk <= 0; acc <= 0;
                  glact <= 1; state <= S_MAC;
                end else begin
                  wx0 <= vpx; wy0 <= vpy; wx1 <= pvx; wy1 <= pvy;
                  csn <= 0; glact <= 1; state <= S_CS;
                end
              end                                         // fill: wait for 3rd
            end
            default:
              if (glpfill) begin                          // fan tri vf,vp,v
                if (glpoly3) begin
                  v[0] <= vfx; v[1] <= vfy; v[2] <= vfz;
                  v[3] <= vpx; v[4] <= vpy; v[5] <= vpz;
                  v[6] <= pvx; v[7] <= pvy; v[8] <= pvz;
                  tri_m <= 1; rfill <= 1; mp <= 0; mr <= 0; mk <= 0; acc <= 0;
                  glact <= 1; state <= S_MAC;
                end else begin                            // 2D: map-only fill
                  qx[0] <= vfx; qy[0] <= vfy; qz[0] <= 0;
                  qx[1] <= vpx; qy[1] <= vpy; qz[1] <= 0;
                  qx[2] <= pvx; qy[2] <= pvy; qz[2] <= 0;
                  np <= 4'd3; pp <= 0; rfill <= 1; gl2d <= 1;
                  glact <= 1; state <= T_MP;
                end
              end else begin                              // outline: next edge
                if (glpoly3) begin
                  v[0] <= vpx; v[1] <= vpy; v[2] <= vpz;
                  v[3] <= pvx; v[4] <= pvy; v[5] <= pvz;
                  tri_m <= 0; mp <= 0; mr <= 0; mk <= 0; acc <= 0;
                  glact <= 1; state <= S_MAC;
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
            v[0] <= vpx; v[1] <= vpy; v[2] <= vpz;
            v[3] <= vfx; v[4] <= vfy; v[5] <= vfz;
            tri_m <= 0; mp <= 0; mr <= 0; mk <= 0; acc <= 0;
            glact <= 1; state <= S_MAC;
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

        G_WAIT: begin                                     // WAIT: real frames
          if (wcnt == 16'd0) glst <= G_OP;
          else if (frame_tick) wcnt <= wcnt - 16'd1;
        end

        default: glst <= G_OP;
      endcase
    end
  end

  // GL busy: the consumer is mid-command or bytes wait in the FIFO
  // busy covers the consumer AND the walker: with GESTAT retired,
  // GLSTAT bit6 is how software waits out its own GL work
  wire glbusy = (glst != G_OP) || cf_ne || (state != S_IDLE);

  always @(*) begin
    case (a[2:0])
      3'd1:    rdata = {cf_full, glbusy, 4'd0, ef_ne, 1'b0};  // GLSTAT
      3'd2:    rdata = 8'h00;                 // GLRB: empty until 10e
      3'd3:    rdata = ef_ne ? ef[ef_rp[3:0]] : 8'h00;        // GLERR
      3'd4:    rdata = 8'h47;                 // GLID: 'G'
      default: rdata = 8'hFF;
    endcase
  end

endmodule
