// p8x_geom.v -- stage 8b: the geometry engine ($FF40-$FF4F).
//
// The whole wireframe pipeline in fabric (STAGE8B-DESIGN.md): the edge list
// lives in SDRAM at $100000 (uploaded through GEUP), a 12-word S7.8
// matrix+translation lives in an indexed parameter file, and one RENDER
// command fetches, transforms, near-clips, projects, window-clips, maps and
// draws every edge -- by driving the DISPLAY'S OWN registers, exactly as
// software would (gfx.v is unchanged; this module is a hardware BASIC).
// The arithmetic is one mdu_core -- the same silicon contract as the MDU --
// plus a sequential MAC for the matrix. The math is lib_g3d.c's pipeline
// STEP FOR STEP (operand order changes truncation; don't "improve" it):
// the emulator's ge_render() is the golden model all three answer to.
//
// GECMD: 1 rewinds the upload cursor, 2 RENDER, 3 FLIP, 4 PGSYNC (the
// draw page rejoins the display page -- the only way back to the
// single-buffer state, since a flip always leaves the pages opposite).
//
// Pages: this module owns the framebuffer page state. draw_pg feeds
// gfx_mem (all pixels, CPU's included, and POINT's read-back); disp_pg
// feeds sdram_video. A flip waits for frame_tick, then: disp_pg <= draw_pg
// (show what was drawn), draw_pg <= ~draw_pg -- the rule that makes the
// FIRST flip split the shared power-on page. GESTAT holds busy until a
// pending flip is consumed, so back-to-back renders pace to the panel.
//
// CPU writes while busy are dropped (poll GESTAT, the house rule), and the
// gfx register port belongs to the engine while it renders -- don't draw
// during a render. GEID reads 'E' ($45): the presence probe.

module p8x_geom (
  input             clk,
  input             rst,

  // CPU register port: sel covers $FF40-$FF4F, a is the low nibble.
  input             sel,
  input      [3:0]  a,
  input             wr,
  input      [7:0]  wdata,
  output reg [7:0]  rdata,

  // gfx register master (p8x_top muxes this over the CPU while gm_own).
  output            gm_own,
  output reg        gm_wr,
  output reg [3:0]  gm_a,
  output reg [7:0]  gm_wdata,
  input      [7:0]  gm_rdata,

  // SDRAM port (arbiter master g): list fetches and uploads, halfwords.
  output reg        g_req,
  output reg        g_we,
  output reg [22:0] g_addr,
  output reg [15:0] g_din,
  input             g_ack,
  input             g_ready,
  input      [15:0] g_dout,

  // page state + the scanout's frame pulse
  input             frame_tick,
  output reg        draw_pg,
  output reg        disp_pg
);

  localparam [22:0] LIST_BASE = 23'h100000;
  localparam [12:0] LIST_MAX  = 13'd4096;

  // ---- parameter file ------------------------------------------------------
  // 0-8 matrix m00..m22 (S7.8, row-major), 9-11 tx/ty/tz, 12 focal d,
  // 13-16 window, 17-20 viewport, 21 flags, 22 edge count.
  reg [15:0] par [0:22];
  reg [4:0]  gesel;
  reg [7:0]  gevlo;
  reg        geerr;

  // ---- upload path ---------------------------------------------------------
  // GEUP bytes pair into halfwords and drain through a 4-deep FIFO: the g
  // port can wait out a scanout chunk (~100 cycles), longer than the gap
  // between CPU pokes, so an unbuffered write would lose bytes.
  reg [16:0] upcur;                  // BYTE cursor into the list
  reg [7:0]  uplo;                   // latched even byte
  reg [15:0] uf_data [0:3];
  reg [15:0] uf_addr [0:3];          // halfword offset within the list
  reg [2:0]  uf_wp, uf_rp;
  wire [2:0] uf_fill = uf_wp - uf_rp;
  wire       uf_empty = (uf_wp == uf_rp);

  // ---- walker state --------------------------------------------------------
  reg [5:0]  state;
  localparam S_IDLE=0,  S_ERA0=1,  S_ERA1=2,  S_ERAW=3,  S_ERAC=4,
             S_PEN=5,   S_NEXT=6,  S_FRD=7,   S_FRDW=8,
             S_MAC=9,   S_MACW=10,
             S_NC=11,   S_NCW=12,  S_PRJ=13,  S_PRJW=14,
             S_CS=15,   S_CSW=16,  S_MAP=17,  S_MAPW=18,
             S_LIN=19,  S_LINB=20, S_LINC=21, S_FLIP=22, S_START=23,
             S_LIN2=24,
             // stage 9b: the TRI record
             T_NC=25,   T_NCA=26,  T_NI0=27,  T_NI0W=28, T_NI1=29,
             T_NI1W=30, T_CPY=31,  T_MP=32,   T_PJX=33,  T_PJXW=34,
             T_PJY=35,  T_PJYW=36, T_MX=37,   T_MXW=38,  T_MY=39,
             T_MYW=40,  T_PENW=41, T_FAN=42,  T_SRT1=43, T_SRT2=44,
             T_SRT3=45, T_DEG=46,  T_SY0=47,  T_SLOOP=48,T_SXA=49,
             T_SXAW=50, T_SXB=51,  T_SXBW=52, T_SPAN=53, T_BX=54,
             T_BXB=55,  T_BXC=56,  T_SNEXT=57,T_ED=58,   T_EC=59,
             T_ECW=60;

  reg [12:0] ei, ecnt;               // record index / count
  reg [22:0] eaddr;                  // record cursor (bytes) -- records are
                                     //   self-sizing, so this ADVANCES by
                                     //   type instead of being computed
  reg [15:0] rcol;                   // the record's colour (stage 9)
  reg [7:0]  rtype;                  // record type: 1 = LINE, 2 = TRI
  reg        rfill;                  // TRI: the FILL flag
  reg        tri_m;                  // MAC writeback goes to tv (TRI mode)
  reg        lret;                   // S_LINC returns to the outline loop
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

  assign gm_own = (state != S_IDLE) && (state != S_FLIP);
  wire busy = (state != S_IDLE) || !uf_empty;

  // ---- the shared arithmetic ----------------------------------------------
  reg         md_go;
  reg  [15:0] md_a, md_b, md_c;
  wire [15:0] md_q;
  wire        md_busy;
  mdu_core MD(.clk(clk), .rst(rst), .go(md_go),
              .a(md_a), .b(md_b), .c(md_c), .q(md_q), .busy(md_busy));
  wire md_done = !md_busy && !md_go;

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

  wire z0_near = $signed(wz0) < $signed(16'd16);
  wire z1_near = $signed(wz1) < $signed(16'd16);

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
    if (rst) begin
      state <= S_IDLE; geerr <= 0; gesel <= 0; gevlo <= 0;
      upcur <= 0; uplo <= 0; uf_wp <= 0; uf_rp <= 0;
      g_req <= 0; g_we <= 0;
      draw_pg <= 0; disp_pg <= 0; flip_pend <= 0;
      ei <= 0; ecnt <= 0; seq <= 0; mdph <= 0; csn <= 0;
      tri_m <= 0; lret <= 0; rfill <= 0; np <= 0; pp <= 0; ft <= 0;
      par[0] <= 16'd256; par[4] <= 16'd256; par[8] <= 16'd256;  // identity
      par[1]<=0; par[2]<=0; par[3]<=0; par[5]<=0; par[6]<=0; par[7]<=0;
      par[9]<=0; par[10]<=0; par[11]<=0;
      par[12] <= 16'd256;                                        // focal
      par[13]<=0; par[14]<=0; par[15]<=0; par[16]<=0;
      par[17]<=0; par[18]<=0; par[19]<=0; par[20]<=0;
      par[21] <= 16'd3;                                          // erase+flip
      par[22] <= 0;
    end else begin

      // ---- CPU register writes: gated on the WALKER, not on `busy` -- busy
      // includes the upload FIFO, and a GEUP burst must not drop its own
      // successor bytes (the FIFO carries its own overrun check). Writes
      // during a render or a pending flip are dropped, the house rule. ----
      if (sel && wr && state == S_IDLE) begin
        case (a)
          4'h0: gesel <= wdata[4:0];
          4'h1: gevlo <= wdata;
          4'hA: begin                       // GEVALH commits, auto-increments
            if (gesel < 5'd23) par[gesel] <= {wdata, gevlo};
            gesel <= gesel + 5'd1;
          end
          4'h2: begin                       // GEUP: pair bytes, queue halfwords
            if (upcur[0] == 1'b0) uplo <= wdata;
            else if (uf_fill < 3'd4) begin
              uf_data[uf_wp[1:0]] <= {wdata, uplo};
              uf_addr[uf_wp[1:0]] <= upcur[16:1];
              uf_wp <= uf_wp + 3'd1;
            end else geerr <= 1;            // overrun: visible, not silent
            upcur <= upcur + 17'd1;
          end
          4'h3: case (wdata)
            8'h01: upcur <= 0;              // rewind the upload cursor
            8'h02: begin                    // RENDER
              geerr <= 0; seq <= 0;
              if (par[22] > {3'd0, LIST_MAX}) geerr <= 1;
              else begin
                ecnt <= par[22][12:0]; ei <= 0;
                eaddr <= LIST_BASE;     // the record cursor walks from here
                state <= S_START;       // busy NOW; work starts once the
              end                       //   upload FIFO has drained
            end
            8'h03: begin flip_pend <= 1; state <= S_FLIP; end
            8'h04: draw_pg <= disp_pg;  // PGSYNC: back to single-buffer,
                                        //   instant (no vsync involved)
            default: geerr <= 1;
          endcase
          default: ;
        endcase
      end

      // ---- upload FIFO drain (runs whenever the walker owns no fetch) ------
      if (!uf_empty && !g_req &&
          (state == S_IDLE || state == S_FLIP || state == S_START)) begin
        g_addr <= LIST_BASE + {6'd0, uf_addr[uf_rp[1:0]], 1'b0};
        g_din  <= uf_data[uf_rp[1:0]];
        g_we   <= 1; g_req <= 1;
      end
      if (g_req && g_ack) begin
        g_req <= 0;
        if (g_we) begin g_we <= 0; uf_rp <= uf_rp + 3'd1; end
      end

      // ---- the walker ------------------------------------------------------
      case (state)
        S_IDLE: ;

        S_START: if (uf_empty && !g_req)
          state <= (par[21][0]) ? S_ERA0 : S_PEN;

        // erase: pen 0, box = viewport, BOXFILL (through the gfx registers)
        S_ERA0: begin gm_a <= 4'h4; gm_wdata <= 8'h00; gm_wr <= 1;  // GCOL=0
                      seq <= 0; state <= S_ERA1; end
        S_ERA1: begin                       // 8 coordinate-byte writes
          case (seq)
            3'd0: begin gm_a<=4'h0; gm_wdata<=par[17][7:0];  end
            3'd1: begin gm_a<=4'h9; gm_wdata<=par[17][15:8]; end
            3'd2: begin gm_a<=4'h1; gm_wdata<=par[18][7:0];  end
            3'd3: begin gm_a<=4'hA; gm_wdata<=par[18][15:8]; end
            3'd4: begin gm_a<=4'h2; gm_wdata<=par[19][7:0];  end
            3'd5: begin gm_a<=4'hB; gm_wdata<=par[19][15:8]; end
            3'd6: begin gm_a<=4'h3; gm_wdata<=par[20][7:0];  end
            3'd7: begin gm_a<=4'hC; gm_wdata<=par[20][15:8]; end
          endcase
          gm_wr <= 1;
          if (seq == 3'd7) state <= S_ERAW; else seq <= seq + 3'd1;
        end
        S_ERAW: begin gm_a <= 4'h6;         // poll GSTAT until idle
                      if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr) state <= S_ERAC; end
        S_ERAC: begin gm_a <= 4'h5; gm_wdata <= 8'h04; gm_wr <= 1;  // BOXFILL
                      state <= S_PEN; seq <= 0; end

        // stage 9: no forced pen -- each record writes its own colour at
        // S_LIN; the pen ends holding the LAST record's colour.
        S_PEN: state <= S_NEXT;

        S_NEXT: begin
          if (ei == ecnt) begin
            if (par[21][1]) begin flip_pend <= 1; state <= S_FLIP; end
            else state <= S_IDLE;
          end else begin
            k <= 0; state <= S_FRD;    // eaddr already sits on the record
          end
        end
        S_FRD: begin                        // one halfword of the edge
          if (!g_req && uf_empty) begin
            g_addr <= eaddr + {19'd0, k, 1'b0};
            g_we <= 0; g_req <= 1; state <= S_FRDW;
          end
        end
        S_FRDW: if (g_ready) begin
          if (k == 4'd0) begin
            rtype <= g_dout[7:0];      // type + flags halfword
            rfill <= g_dout[8];
            if (g_dout[7:0] != 8'd1 && g_dout[7:0] != 8'd2) begin
              geerr <= 1; state <= S_IDLE;
            end else begin k <= 4'd1; state <= S_FRD; end
          end else if (k == 4'd1) begin
            rcol <= g_dout;            // the record's colour
            k <= 4'd2; state <= S_FRD;
          end else begin
            v[k - 2] <= g_dout;
            if (rtype == 8'd1 && k == 4'd7) begin
              eaddr <= eaddr + 23'd16; // LINE record: 16 bytes
              tri_m <= 0;
              mp <= 0; mr <= 0; mk <= 0; acc <= 0; state <= S_MAC;
            end else if (rtype == 8'd2 && k == 4'd10) begin
              eaddr <= eaddr + 23'd22; // TRI record: 22 bytes
              tri_m <= 1;
              mp <= 0; mr <= 0; mk <= 0; acc <= 0; state <= S_MAC;
            end else begin k <= k + 4'd1; state <= S_FRD; end
          end
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
              if (mp == 2'd1) begin mdph <= 0; state <= S_NC; end
              else begin mp <= 2'd1; state <= S_MAC; end
            end
          end else begin mr <= mr + 2'd1; state <= S_MAC; end
        end

        // near clip (perspective only), lib order: end 0 first, then end 1
        S_NC: begin
          if (par[12] == 16'd0) begin csn <= 0; state <= S_CS; end
          else if (z0_near && z1_near) begin ei <= ei + 13'd1; state <= S_NEXT; end
          else if (z0_near) begin
            md_a <= (mdph[0]==1'b0) ? (wx1 - wx0) : (wy1 - wy0);
            md_b <= 16'd16 - wz0;  md_c <= wz1 - wz0;
            md_go <= 1; state <= S_NCW;
          end else if (z1_near) begin
            md_a <= (mdph[0]==1'b0) ? (wx0 - wx1) : (wy0 - wy1);
            md_b <= 16'd16 - wz1;  md_c <= wz0 - wz1;
            md_go <= 1; state <= S_NCW;
          end else begin mdph <= 0; state <= S_PRJ; end
        end
        S_NCW: if (md_done) begin
          if (z0_near) begin
            if (mdph[0]==1'b0) begin wx0 <= wx0 + md_q; mdph <= 2'd1; end
            else begin wy0 <= wy0 + md_q; wz0 <= 16'd16; mdph <= 0; end
          end else begin
            if (mdph[0]==1'b0) begin wx1 <= wx1 + md_q; mdph <= 2'd1; end
            else begin wy1 <= wy1 + md_q; wz1 <= 16'd16; mdph <= 0; end
          end
          state <= S_NC;
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
            ei <= ei + 13'd1; state <= S_NEXT;
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
                      if (lret) begin lret <= 0; pp <= pp + 4'd1; state <= T_ED; end
                      else begin ei <= ei + 13'd1; state <= S_NEXT; end end

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
            if (np < 4'd3) begin ei <= ei + 13'd1; state <= S_NEXT; end
            else begin pp <= 0; state <= T_MP; end
          end else begin
            nax <= tvx[pp[1:0]]; nay <= tvy[pp[1:0]]; naz <= tvz[pp[1:0]];
            nbx <= tvx[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            nby <= tvy[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            nbz <= tvz[(pp == 4'd2) ? 2'd0 : pp[1:0] + 2'd1];
            state <= T_NI0;
          end
        end
        T_NI0: begin                   // classify; keep A; start x-intersect
          nain <= !($signed(naz) < $signed(16'd16));
          nbin <= !($signed(nbz) < $signed(16'd16));
          if (!($signed(naz) < $signed(16'd16))) begin
            qx[np] <= nax; qy[np] <= nay; qz[np] <= naz; np <= np + 4'd1;
          end
          state <= T_NI0W;
        end
        T_NI0W: begin
          if (nain == nbin) begin pp <= pp + 4'd1; state <= T_NCA; end
          else begin
            md_a <= nbx - nax; md_b <= 16'd16 - naz; md_c <= nbz - naz;
            md_go <= 1; state <= T_NI1;
          end
        end
        T_NI1: if (md_done) begin
          qx[np] <= nax + md_q;
          md_a <= nby - nay; md_b <= 16'd16 - naz; md_c <= nbz - naz;
          md_go <= 1; state <= T_NI1W;
        end
        T_NI1W: if (md_done) begin
          qy[np] <= nay + md_q; qz[np] <= 16'd16; np <= np + 4'd1;
          pp <= pp + 4'd1; state <= T_NCA;
        end

        // project + viewport-map each polygon vertex into qsx/qsy
        T_MP: begin
          if (pp == np) begin
            if (rfill) begin seq <= 0; state <= T_PENW; end
            else begin pp <= 0; state <= T_ED; end
          end else begin
            cxv <= qx[pp[2:0]]; cyv <= qy[pp[2:0]];
            state <= (par[12] != 16'd0) ? T_PJX : T_MX;
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
          if (ft + 4'd1 >= np) begin ei <= ei + 13'd1; state <= S_NEXT; end
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

        // outline: each polygon edge, screen-space CS against the viewport,
        // then the LINE issuer (S_LIN) with a return ticket (lret)
        T_ED: begin
          if (pp == np) begin ei <= ei + 13'd1; state <= S_NEXT; end
          else begin
            ox0 <= qsx[pp[2:0]]; oy0 <= qsy[pp[2:0]];
            ox1 <= qsx[(pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1];
            oy1 <= qsy[(pp + 4'd1 == np) ? 3'd0 : pp[2:0] + 3'd1];
            csn <= 0; state <= T_EC;
          end
        end
        T_EC: begin
          if ((soa | sob) == 4'd0) begin
            px0 <= ox0; py0 <= oy0; px1 <= ox1; py1 <= oy1;
            lret <= 1; seq <= 0; state <= S_LIN;
          end else if ((soa & sob) != 4'd0 || csn == 4'd8) begin
            pp <= pp + 4'd1; state <= T_ED;
          end else if (soa == 4'd0) begin
            ox0 <= ox1; ox1 <= ox0; oy0 <= oy1; oy1 <= oy0;
          end else begin
            if (soa[0])      begin md_a <= oy1 - oy0; md_b <= par[17] - ox0; md_c <= ox1 - ox0; end
            else if (soa[1]) begin md_a <= oy1 - oy0; md_b <= par[19] - ox0; md_c <= ox1 - ox0; end
            else if (soa[2]) begin md_a <= ox1 - ox0; md_b <= par[18] - oy0; md_c <= oy1 - oy0; end
            else             begin md_a <= ox1 - ox0; md_b <= par[20] - oy0; md_c <= oy1 - oy0; end
            md_go <= 1; csn <= csn + 4'd1; state <= T_ECW;
          end
        end
        T_ECW: if (md_done) begin
          if (soa[0])      begin oy0 <= oy0 + md_q; ox0 <= par[17]; end
          else if (soa[1]) begin oy0 <= oy0 + md_q; ox0 <= par[19]; end
          else if (soa[2]) begin ox0 <= ox0 + md_q; oy0 <= par[18]; end
          else             begin ox0 <= ox0 + md_q; oy0 <= par[20]; end
          state <= T_EC;
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
    end
  end

  always @(*) begin
    case (a)
      4'h4:    rdata = {busy, 6'd0, geerr};   // GESTAT
      4'h5:    rdata = 8'h45;                 // GEID: 'E'
      default: rdata = 8'hFF;
    endcase
  end

endmodule
