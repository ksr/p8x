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
  reg [4:0]  state;
  localparam S_IDLE=0,  S_ERA0=1,  S_ERA1=2,  S_ERAW=3,  S_ERAC=4,
             S_PEN=5,   S_NEXT=6,  S_FRD=7,   S_FRDW=8,
             S_MAC=9,   S_MACW=10,
             S_NC=11,   S_NCW=12,  S_PRJ=13,  S_PRJW=14,
             S_CS=15,   S_CSW=16,  S_MAP=17,  S_MAPW=18,
             S_LIN=19,  S_LINB=20, S_LINC=21, S_FLIP=22, S_START=23;

  reg [12:0] ei, ecnt;               // edge index / count
  reg [22:0] eaddr;                  // fetch cursor (bytes)
  reg [2:0]  k;                      // fetch word / general microstep
  reg [15:0] v [0:5];                // fetched vertex words
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

        // pen white for the lines (GCOL low first -- clears high -- then high)
        S_PEN: begin
          if (seq == 3'd0) begin gm_a <= 4'h4; gm_wdata <= 8'hFF; gm_wr <= 1; seq <= 3'd1; end
          else begin gm_a <= 4'hD; gm_wdata <= 8'hFF; gm_wr <= 1; seq <= 0; state <= S_NEXT; end
        end

        S_NEXT: begin
          if (ei == ecnt) begin
            if (par[21][1]) begin flip_pend <= 1; state <= S_FLIP; end
            else state <= S_IDLE;
          end else begin
            // ei*12 = ei*16 - ei*4: adders only, no multiplier
            eaddr <= LIST_BASE + {6'd0, ei, 4'd0} - {8'd0, ei, 2'd0};
            k <= 0; state <= S_FRD;
          end
        end
        S_FRD: begin                        // one halfword of the edge
          if (!g_req && uf_empty) begin
            g_addr <= eaddr + {19'd0, k, 1'b0};
            g_we <= 0; g_req <= 1; state <= S_FRDW;
          end
        end
        S_FRDW: if (g_ready) begin
          v[k] <= g_dout;
          if (k == 3'd5) begin
            mp <= 0; mr <= 0; mk <= 0; acc <= 0; state <= S_MAC;
          end else begin k <= k + 3'd1; state <= S_FRD; end
        end

        // transform: acc = m[r][0..2] . v[p], then w = (acc>>>8) + t
        S_MAC: begin
          acc <= acc + mac_p;
          if (mk == 2'd2) state <= S_MACW; else mk <= mk + 2'd1;
        end
        S_MACW: begin
          case ({mp[0], mr})
            3'b000: wx0 <= mac_res;  3'b001: wy0 <= mac_res;  3'b010: wz0 <= mac_res;
            3'b100: wx1 <= mac_res;  3'b101: wy1 <= mac_res;  3'b110: wz1 <= mac_res;
            default: ;
          endcase
          acc <= 0; mk <= 0;
          if (mr == 2'd2) begin
            mr <= 0;
            if (mp == 2'd1) begin mdph <= 0; state <= S_NC; end
            else begin mp <= 2'd1; state <= S_MAC; end
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

        // issue the LINE: 8 coordinate bytes, wait engine idle, command
        S_LIN: begin
          case (seq)
            3'd0: begin gm_a<=4'h0; gm_wdata<=px0[7:0];  end
            3'd1: begin gm_a<=4'h9; gm_wdata<=px0[15:8]; end
            3'd2: begin gm_a<=4'h1; gm_wdata<=py0[7:0];  end
            3'd3: begin gm_a<=4'hA; gm_wdata<=py0[15:8]; end
            3'd4: begin gm_a<=4'h2; gm_wdata<=px1[7:0];  end
            3'd5: begin gm_a<=4'hB; gm_wdata<=px1[15:8]; end
            3'd6: begin gm_a<=4'h3; gm_wdata<=py1[7:0];  end
            3'd7: begin gm_a<=4'hC; gm_wdata<=py1[15:8]; end
          endcase
          gm_wr <= 1;
          if (seq == 3'd7) state <= S_LINB; else seq <= seq + 3'd1;
        end
        S_LINB: begin gm_a <= 4'h6;
                      if (gm_a == 4'h6 && !gm_rdata[7] && !gm_wr) state <= S_LINC; end
        S_LINC: begin gm_a <= 4'h5; gm_wdata <= 8'h02; gm_wr <= 1;  // LINE
                      ei <= ei + 13'd1; state <= S_NEXT; end

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
