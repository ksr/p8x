// tb_gfx_mem.v -- the pixel back-end against a model of the arbiter + memory.
// Checks the things that would silently corrupt a picture: address arithmetic in
// both modes, that mode 0 preserves the OTHER three pixels in a byte, that
// off-screen touches memory not at all, and that a span covers exactly four
// pixels in each mode -- not one, and not sixteen.
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;
  reg mode=0, px_go=0, px_read=0, px_word=0;
  reg signed [17:0] px_x=0, px_y=0;
  reg [7:0] px_pen=0;
  wire px_busy; wire [7:0] px_out;
  wire e_req,e_we,e_word; wire [22:0] e_addr; wire [7:0] e_din;
  reg  e_ack=0, e_ready=0; reg [7:0] e_dout=0;

  gfx_mem dut(.clk(clk),.rst(rst),.mode(mode),.px_x(px_x),.px_y(px_y),
    .px_pen(px_pen),.px_go(px_go),.px_read(px_read),.px_word(px_word),
    .px_busy(px_busy),.px_out(px_out),
    .e_req(e_req),.e_we(e_we),.e_word(e_word),.e_addr(e_addr),.e_din(e_din),
    .e_ack(e_ack),.e_ready(e_ready),.e_dout(e_dout));

  reg [7:0] mem [0:200000];
  integer ops=0, bad=0;
  integer i;
  initial for(i=0;i<200000;i=i+1) mem[i]=0;

  // arbiter+memory model: ack a cycle after req, answer a read 3 later
  reg [2:0] lat=0; reg pend=0; reg [22:0] alat;
  always @(posedge clk) begin
    e_ack<=0; e_ready<=0;
    if(rst) begin lat<=0; pend<=0; end
    else if(e_req && !e_ack && lat==0 && !pend) begin
      e_ack<=1; ops=ops+1; alat<=e_addr;
      if(e_we) begin
        if(e_word) begin mem[{e_addr[22:2],2'd0}]<=e_din; mem[{e_addr[22:2],2'd1}]<=e_din;
                         mem[{e_addr[22:2],2'd2}]<=e_din; mem[{e_addr[22:2],2'd3}]<=e_din; end
        else mem[e_addr]<=e_din;
      end else begin pend<=1; lat<=3; end
    end else if(pend) begin
      if(lat==1) begin e_dout<=mem[alat]; e_ready<=1; pend<=0; lat<=0; end
      else lat<=lat-1;
    end
  end

  // Stimulus is driven on the NEGEDGE. Driving DUT inputs with blocking
  // assignments at the posedge races with the DUT sampling them -- Verilog
  // defines no order between an initial block and an always block at the same
  // instant, and iverilog duly executed the deassignment first, so px_go was
  // never seen and every single check failed while the DUT was correct.
  task plot(input integer x,y,pen,rd,wd);
    begin
      @(negedge clk);
      px_x=x; px_y=y; px_pen=pen; px_read=rd[0]; px_word=wd[0]; px_go=1;
      @(negedge clk); px_go=0;
      while(px_busy) @(negedge clk);
      @(negedge clk);
    end
  endtask
  task chk;
    input integer got;
    input integer want;
    input [8*48:1] what;
    begin
      if(got!==want) begin
        $display("FAIL: %0s (got %0d, want %0d)", what, got, want); bad=bad+1;
      end
    end
  endtask

  initial begin
    repeat(3) @(posedge clk); rst=0; @(posedge clk);

    // mode 0: four pixels share a byte at y*60+(x>>2)
    mode=0;
    plot(4,2,3,0,0); chk(mem[2*60+1], 8'b11000000, "mode0 x=4 -> top 2 bits");
    plot(5,2,1,0,0); chk(mem[2*60+1], 8'b11010000, "mode0 x=5 must PRESERVE x=4");
    plot(7,2,2,0,0); chk(mem[2*60+1], 8'b11010010, "mode0 x=7 must preserve the rest");
    plot(5,2,0,1,0); chk(px_out, 1, "mode0 POINT reads back the pen");

    // off-screen touches memory not at all
    ops=0; plot(240,2,3,0,0); chk(ops,0,"mode0 off-screen x issued an access");
    plot(0,136,3,0,0);        chk(ops,0,"mode0 off-screen y issued an access");
    plot(-1,2,3,0,0);         chk(ops,0,"mode0 negative x issued an access");
    plot(500,500,0,1,0); chk(px_out,0,"off-screen POINT must read 0");

    // mode 0 span: ONE byte = four pixels, and NOT four bytes
    ops=0; plot(8,3,2,0,1);
    chk(ops,1,"mode0 span should be a single write");
    chk(mem[3*60+2], 8'b10101010, "mode0 span byte");
    chk(mem[3*60+3], 0, "mode0 span must not spill into the next byte");

    // mode 1: a pixel is a byte at y*480+x
    mode=1; @(posedge clk);
    ops=0; plot(100,5,8'hC3,0,0);
    chk(ops,1,"mode1 plot must be ONE write, no read-modify-write");
    chk(mem[5*480+100], 8'hC3, "mode1 pixel address");
    plot(100,5,0,1,0); chk(px_out,8'hC3,"mode1 POINT");
    plot(479,271,8'h5A,0,0); chk(mem[271*480+479],8'h5A,"mode1 far corner");
    ops=0; plot(480,0,1,0,0); chk(ops,0,"mode1 x=480 is off-screen");

    // mode 1 span: four lanes = four pixels
    ops=0; plot(200,6,8'h77,0,1);
    chk(ops,1,"mode1 span should be a single write");
    for(i=0;i<4;i=i+1) chk(mem[6*480+200+i], 8'h77, "mode1 span covers 4 pixels");
    chk(mem[6*480+204], 0, "mode1 span must not cover a fifth");

    if(bad) begin $display("TB-GFXMEM: FAIL (%0d)",bad); $finish(1); end
    $display("TB-GFXMEM: PASS (addressing, RMW preservation, clipping, spans)");
    $finish(0);
  end
endmodule
