// prims.v -- behavioral Verilog models of the 74-series parts, for the P8X
// gate-level netlist simulator (tools/gatesim/netlist2v.py wires these up from
// the gen_eagle card netlists). Port names are the SANITISED device pin names
// ('!X' -> 'nX', '-X' -> 'nX'), so the translator can connect by name.
//
// These are LOGIC models (combinational truth + clocked latches), enough to
// validate decode / control wiring. They are NOT timing/analog models.
`timescale 1ns/1ns

module dev_7430(input A,B,C,D,E,F,G,H, output Y, input VCC,GND);
  assign Y = ~(A&B&C&D&E&F&G&H);           // 8-input NAND
endmodule

// 3-to-8 decoder, active-low outputs, enabled by G1 & ~nG2A & ~nG2B
module dev_74138(input A,B,C,G1,nG2A,nG2B,
                 output Y0,Y1,Y2,Y3,Y4,Y5,Y6,Y7, input VCC,GND);
  wire en = G1 & ~nG2A & ~nG2B;
  wire [2:0] s = {C,B,A};
  assign Y0 = ~(en & (s==0)); assign Y1 = ~(en & (s==1));
  assign Y2 = ~(en & (s==2)); assign Y3 = ~(en & (s==3));
  assign Y4 = ~(en & (s==4)); assign Y5 = ~(en & (s==5));
  assign Y6 = ~(en & (s==6)); assign Y7 = ~(en & (s==7));
endmodule

// quad 2-input gates (GATES14 body; the translator picks the type from the value)
module dev_7400(input P1A,P1B,P2A,P2B,P3A,P3B,P4A,P4B,
                output P1Y,P2Y,P3Y,P4Y, input VCC,GND);
  assign P1Y=~(P1A&P1B); assign P2Y=~(P2A&P2B);
  assign P3Y=~(P3A&P3B); assign P4Y=~(P4A&P4B);   // NAND
endmodule
module dev_7408(input P1A,P1B,P2A,P2B,P3A,P3B,P4A,P4B,
                output P1Y,P2Y,P3Y,P4Y, input VCC,GND);
  assign P1Y=P1A&P1B; assign P2Y=P2A&P2B;
  assign P3Y=P3A&P3B; assign P4Y=P4A&P4B;         // AND
endmodule
module dev_7432(input P1A,P1B,P2A,P2B,P3A,P3B,P4A,P4B,
                output P1Y,P2Y,P3Y,P4Y, input VCC,GND);
  assign P1Y=P1A|P1B; assign P2Y=P2A|P2B;
  assign P3Y=P3A|P3B; assign P4Y=P4A|P4B;         // OR
endmodule
module dev_7486(input P1A,P1B,P2A,P2B,P3A,P3B,P4A,P4B,
                output P1Y,P2Y,P3Y,P4Y, input VCC,GND);
  assign P1Y=P1A^P1B; assign P2Y=P2A^P2B;
  assign P3Y=P3A^P3B; assign P4Y=P4A^P4B;         // XOR
endmodule

// hex inverter (74x04/74x14)
module dev_HEX14(input P1A,P2A,P3A,P4A,P5A,P6A,
                 output P1Y,P2Y,P3Y,P4Y,P5Y,P6Y, input VCC,GND);
  assign P1Y=~P1A; assign P2Y=~P2A; assign P3Y=~P3A;
  assign P4Y=~P4A; assign P5Y=~P5A; assign P6Y=~P6A;
endmodule

// triple 3-input NAND (7410)
module dev_7410(input P1A,P1B,P1C,P2A,P2B,P2C,P3A,P3B,P3C,
                output P1Y,P2Y,P3Y, input VCC,GND);
  assign P1Y=~(P1A&P1B&P1C); assign P2Y=~(P2A&P2B&P2C); assign P3Y=~(P3A&P3B&P3C);
endmodule

// dual 4-input OR/NOR (74260 is dual 5-in NOR) -- provide dual 5-in NOR
module dev_74260(input A1,B1,C1,D1,E1,A2,B2,C2,D2,E2,
                 output Y1,Y2, input VCC,GND);
  assign Y1=~(A1|B1|C1|D1|E1); assign Y2=~(A2|B2|C2|D2|E2);
endmodule

// quad 2:1 mux, S=0 -> A, S=1 -> B; !G high forces the outputs low (2026-11-27)
module dev_74157(input S,A1,B1,A2,B2,A3,B3,A4,B4,nG,
                 output Y1,Y2,Y3,Y4, input VCC,GND);
  assign Y1 = ~nG & (S ? B1 : A1); assign Y2 = ~nG & (S ? B2 : A2);
  assign Y3 = ~nG & (S ? B3 : A3); assign Y4 = ~nG & (S ? B4 : A4);
endmodule

// quad D flip-flop, rising CLK, async active-low clear
module dev_74175(input nCLR,CLK,D1,D2,D3,D4,
                 output reg Q1,Q2,Q3,Q4, output nQ1,nQ2,nQ3,nQ4, input VCC,GND);
  always @(posedge CLK or negedge nCLR)
    if (!nCLR) {Q1,Q2,Q3,Q4} <= 4'b0; else {Q1,Q2,Q3,Q4} <= {D1,D2,D3,D4};
  assign nQ1=~Q1; assign nQ2=~Q2; assign nQ3=~Q3; assign nQ4=~Q4;
endmodule

// dual D flip-flop, rising CLK, async active-low preset and clear
module dev_7474(input n1CLR,P1D,P1CLK,n1PRE,n2CLR,P2D,P2CLK,n2PRE,
                output reg P1Q,P2Q, output n1Q,n2Q, input VCC,GND);
  always @(posedge P1CLK or negedge n1CLR or negedge n1PRE)
    if (!n1CLR) P1Q <= 1'b0; else if (!n1PRE) P1Q <= 1'b1; else P1Q <= P1D;
  always @(posedge P2CLK or negedge n2CLR or negedge n2PRE)
    if (!n2CLR) P2Q <= 1'b0; else if (!n2PRE) P2Q <= 1'b1; else P2Q <= P2D;
  assign n1Q=~P1Q; assign n2Q=~P2Q;
endmodule
