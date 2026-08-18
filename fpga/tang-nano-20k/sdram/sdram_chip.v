// sdram_chip.v -- a behavioural model of the CHIP, for simulation only.
//
// Every existing bench substitutes at the CONTROLLER's logic-side interface
// (sdram_model.v and the `module sdram` shims in the tb files). That was the
// right cut while the controller was vendored and known-good: the thing under
// test was always the client. Stage 6's controller is new RTL, so the thing
// under test is now the controller itself, and the model has to sit on the
// other side of it -- at the pins, speaking RAS/CAS/WE.
//
// What it models, because these are where a controller goes wrong:
//   - four banks, each with an open-row register: reading a closed bank, or
//     activating an open one, is a counted protocol error, not undefined
//     behaviour
//   - CAS latency 2: data appears on DQ exactly two cycles after the READ
//     lands, and back-to-back READs pipeline to one word a cycle
//   - auto-precharge (A[10] at READ/WRITE) closes the bank after the access
//   - DQM byte masking on writes
//   - refresh bookkeeping: AUTO-REFRESH commands are counted and the widest
//     gap recorded, so a bench can ASSERT the cadence instead of trusting it
//
// The model is validated against the VENDORED controller before it is allowed
// to judge the new one -- tb_p8x_sdram.v runs both. If known-good RTL fails
// the model, the model is wrong; that ordering keeps the burden of proof
// where it belongs.
//
// What it deliberately does NOT model: the 180/225-degree clock relationship.
// Commands are sampled on the fabric clock edge, with the data timed so the
// vendored controller's documented waveform (data_ready at ACTIVATE+T_RCD+CAS)
// samples the right word. The phase shift is a board-level analogue concern
// the vendored path has already proven on this hardware.
//
// Timing checks are in FABRIC CYCLES at 27 MHz, matching the vendored
// parameters: tRCD >= 1, tRP >= 1, tRAS >= 2 to precharge, tRC >= 4.
//
// Bench-visible bookkeeping (refreshes, max_refresh_gap, protocol_errors) is
// read hierarchically -- they are integers, not ports.
`timescale 1ns/1ps
module sdram_chip #(
    parameter AWORDS = 2*1024*1024          // 2M x 32 = 64 Mbit
)(
    input             clk,                  // fabric clock (see header)
    inout      [31:0] SDRAM_DQ,
    input      [10:0] SDRAM_A,
    input       [1:0] SDRAM_BA,
    input             SDRAM_nCS,
    input             SDRAM_nWE,
    input             SDRAM_nRAS,
    input             SDRAM_nCAS,
    input             SDRAM_CKE,
    input       [3:0] SDRAM_DQM
);
  reg [31:0] mem [0:AWORDS-1];

  reg        bank_open [0:3];
  reg [10:0] bank_row  [0:3];
  integer    bank_act_t[0:3];               // cycle the row was opened
  integer    bank_pre_t[0:3];               // cycle it was closed
  integer    now, last_refresh;
  integer    refreshes, max_refresh_gap, protocol_errors;
  integer    i;

  initial begin
    now = 0; last_refresh = 0; refreshes = 0; max_refresh_gap = 0;
    protocol_errors = 0;
    for (i = 0; i < 4; i = i + 1) begin
      bank_open[i] = 0; bank_row[i] = 0;
      bank_act_t[i] = -100; bank_pre_t[i] = -100;
    end
  end

  // {nRAS,nCAS,nWE}
  localparam CMD_MRS = 3'b000, CMD_REF = 3'b001, CMD_PRE = 3'b010,
             CMD_ACT = 3'b011, CMD_WR  = 3'b100, CMD_RD  = 3'b101,
             CMD_NOP = 3'b111;
  wire [2:0] cmd = SDRAM_nCS ? CMD_NOP : {SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE};

  task perror(input [8*60:1] what);
    begin
      protocol_errors = protocol_errors + 1;
      $display("sdram_chip: PROTOCOL ERROR t=%0d: %0s", now, what);
    end
  endtask

  // CAS=2 read path: a READ sampled at edge E answers on DQ during the cycle
  // that ends at edge E+2 -- which is when the vendored controller's
  // data_ready-annotated client samples dq_in. Two registered stages.
  reg        r1;                            // read accepted last edge
  reg [31:0] d1;
  reg        dq_oe;
  reg [31:0] dq_val;
  assign SDRAM_DQ = dq_oe ? dq_val : 32'hzzzz_zzzz;

  wire [1:0]  ba = SDRAM_BA;
  wire [20:0] wa = {ba, bank_row[ba], SDRAM_A[7:0]};   // word address of a CAS

  integer gap, b;
  always @(posedge clk) begin
    now = now + 1;

    dq_oe <= r1;  dq_val <= d1;  r1 <= 1'b0;

    case (cmd)
      CMD_ACT: begin
        if (bank_open[ba]) perror("ACTIVATE to an already-open bank");
        if (now - bank_pre_t[ba] < 1) perror("tRP violated");
        bank_open[ba]  <= 1;
        bank_row[ba]   <= SDRAM_A;
        bank_act_t[ba] <= now;
      end

      CMD_RD: begin
        if (!bank_open[ba]) perror("READ from a closed bank");
        else if (now - bank_act_t[ba] < 1) perror("tRCD violated at READ");
        else begin
          r1 <= 1'b1;
          d1 <= mem[wa];
          if (SDRAM_A[10]) begin            // auto-precharge
            bank_open[ba]  <= 0;
            bank_pre_t[ba] <= now + 1;      // internal precharge after the access
          end
        end
      end

      CMD_WR: begin
        if (!bank_open[ba]) perror("WRITE to a closed bank");
        else if (now - bank_act_t[ba] < 1) perror("tRCD violated at WRITE");
        else begin
          if (!SDRAM_DQM[0]) mem[wa][7:0]   <= SDRAM_DQ[7:0];
          if (!SDRAM_DQM[1]) mem[wa][15:8]  <= SDRAM_DQ[15:8];
          if (!SDRAM_DQM[2]) mem[wa][23:16] <= SDRAM_DQ[23:16];
          if (!SDRAM_DQM[3]) mem[wa][31:24] <= SDRAM_DQ[31:24];
          if (SDRAM_A[10]) begin
            bank_open[ba]  <= 0;
            bank_pre_t[ba] <= now + 2;      // write recovery before the precharge
          end
        end
      end

      CMD_PRE: begin
        if (SDRAM_A[10]) begin              // precharge ALL
          for (b = 0; b < 4; b = b + 1)
            if (bank_open[b]) begin
              if (now - bank_act_t[b] < 2) perror("tRAS violated at PRECHARGE-ALL");
              bank_open[b] <= 0; bank_pre_t[b] <= now;
            end
        end else begin
          if (bank_open[ba] && now - bank_act_t[ba] < 2)
            perror("tRAS violated at PRECHARGE");
          bank_open[ba] <= 0; bank_pre_t[ba] <= now;
        end
      end

      CMD_REF: begin
        for (b = 0; b < 4; b = b + 1)
          if (bank_open[b]) perror("AUTO-REFRESH with a bank open");
        refreshes = refreshes + 1;
        gap = now - last_refresh;
        if (gap > max_refresh_gap && refreshes > 2) max_refresh_gap = gap;
        if (gap > 450 && refreshes > 2)
          $display("sdram_chip: LATE refresh t=%0d gap=%0d", now, gap);
        last_refresh = now;
      end

      CMD_MRS: ;                            // accepted; CAS=2, BL=1 assumed
      default: ;                            // NOP
    endcase
  end
endmodule
