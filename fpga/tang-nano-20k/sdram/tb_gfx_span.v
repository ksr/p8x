// tb_gfx_span.v -- the span filler driving the real gfx_mem into a model memory.
// The property that matters is COVERAGE: every pixel of the run painted exactly
// once, and nothing outside it disturbed. Exhaustive over every start and end
// alignment, because the bugs here are all at the ends -- a word write that
// runs three pixels past x1, or a head pixel skipped because the run happened
// to start aligned.
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;
  reg mode=1;
  reg signed [17:0] sp_x0=0, sp_x1=0, sp_y=0;
  reg [7:0] sp_pen=0; reg sp_go=0; wire sp_busy;

  wire signed [17:0] px_x, px_y; wire [7:0] px_pen; wire px_go, px_word, px_busy;
  wire [7:0] px_out;
  wire e_req,e_we,e_word; wire [22:0] e_addr; wire [7:0] e_din;
  reg  e_ack=0, e_ready=0; reg [7:0] e_dout=0;

  gfx_span sp(.clk(clk),.rst(rst),.sp_x0(sp_x0),.sp_x1(sp_x1),.sp_y(sp_y),
    .sp_pen(sp_pen),.sp_go(sp_go),.sp_busy(sp_busy),
    .px_x(px_x),.px_y(px_y),.px_pen(px_pen),.px_go(px_go),.px_word(px_word),
    .px_busy(px_busy));

  gfx_mem mem_i(.clk(clk),.rst(rst),.mode(mode),.px_x(px_x),.px_y(px_y),
    .px_pen(px_pen),.px_go(px_go),.px_read(1'b0),.px_word(px_word),
    .px_busy(px_busy),.px_out(px_out),
    .e_req(e_req),.e_we(e_we),.e_word(e_word),.e_addr(e_addr),.e_din(e_din),
    .e_ack(e_ack),.e_ready(e_ready),.e_dout(e_dout));

  reg [7:0] mem [0:200000];
  integer i, bad=0, writes=0;
  initial for(i=0;i<200000;i=i+1) mem[i]=0;

  reg [2:0] lat=0; reg pend=0; reg [22:0] alat;
  always @(posedge clk) begin
    e_ack<=0; e_ready<=0;
    if(rst) begin lat<=0; pend<=0; end
    else if(e_req && !e_ack && lat==0 && !pend) begin
      e_ack<=1; alat<=e_addr;
      if(e_we) begin
        writes = writes+1;
        if(e_word) for(i=0;i<4;i=i+1) mem[{e_addr[22:2],2'd0}+i] <= e_din;
        else mem[e_addr] <= e_din;
      end else begin pend<=1; lat<=3; end
    end else if(pend) begin
      if(lat==1) begin e_dout<=mem[alat]; e_ready<=1; pend<=0; lat<=0; end
      else lat<=lat-1;
    end
  end

  task run_span(input integer x0,x1,y,pen);
    begin
      @(negedge clk);
      sp_x0=x0; sp_x1=x1; sp_y=y; sp_pen=pen; sp_go=1;
      @(negedge clk); sp_go=0;
      while(sp_busy) @(negedge clk);
      repeat(8) @(negedge clk);
    end
  endtask

  integer x0,x1,x,base,w0;
  initial begin
    repeat(3) @(posedge clk); rst=0; @(posedge clk);

    // Exhaustive over alignments: every start 0..7 against every length 1..12.
    for (x0=0; x0<8; x0=x0+1)
      for (x1=x0; x1<x0+12; x1=x1+1) begin
        for(i=0;i<200000;i=i+1) mem[i]=0;
        writes = 0;
        run_span(x0+64, x1+64, 3, 8'hE7);      // +64 keeps it clear of address 0
        for (x=0; x<200; x=x+1) begin
          base = 3*480 + x;
          if (x >= x0+64 && x <= x1+64) begin
            if (mem[base] !== 8'hE7) begin
              $display("FAIL: x0=%0d x1=%0d -- pixel %0d not painted", x0+64, x1+64, x);
              bad=bad+1;
            end
          end else if (mem[base] !== 8'h00) begin
            $display("FAIL: x0=%0d x1=%0d -- pixel %0d painted but OUTSIDE the run",
                     x0+64, x1+64, x);
            bad=bad+1;
          end
        end
        if (bad > 6) begin $display("(stopping after 6)"); $finish(1); end
      end

    // an empty run must do nothing at all rather than hang or paint one pixel
    for(i=0;i<200000;i=i+1) mem[i]=0;
    writes = 0;
    run_span(100, 99, 5, 8'hFF);
    if (writes != 0) begin $display("FAIL: empty run issued %0d writes", writes); bad=bad+1; end

    // a full 480-wide row: 480/4 = 120 word writes, not 480 single ones
    for(i=0;i<200000;i=i+1) mem[i]=0;
    writes = 0;
    run_span(0, 479, 7, 8'h5C);
    $display("full row: %0d writes (480 pixels)", writes);
    if (writes != 120) begin
      $display("FAIL: aligned full row should be 120 word writes, got %0d", writes);
      bad=bad+1;
    end
    for (x=0; x<480; x=x+1)
      if (mem[7*480+x] !== 8'h5C) begin
        $display("FAIL: full row pixel %0d missing", x); bad=bad+1;
        x = 480;
      end

    if (bad) begin $display("TB-GFXSPAN: FAIL (%0d)", bad); $finish(1); end
    $display("TB-GFXSPAN: PASS (exhaustive alignment coverage, empty run, word rate)");
    $finish(0);
  end
endmodule
