// Simulation stand-in for the rPLL primitive (not synthesised).
module rPLL #(parameter FCLKIN="27", parameter IDIV_SEL=0, parameter FBDIV_SEL=0,
  parameter ODIV_SEL=8, parameter PSDA_SEL="0000", parameter DUTYDA_SEL="1000",
  parameter DEVICE="GW2A-18C", parameter DYN_IDIV_SEL="false",
  parameter DYN_FBDIV_SEL="false", parameter DYN_ODIV_SEL="false",
  parameter DYN_DA_EN="false", parameter CLKFB_SEL="internal",
  parameter CLKOUT_BYPASS="false", parameter CLKOUTP_BYPASS="false",
  parameter CLKOUTD_BYPASS="false", parameter CLKOUTD_SRC="CLKOUT",
  parameter CLKOUT_DLY_STEP=0, parameter CLKOUTP_DLY_STEP=0)
 (input CLKIN, CLKFB, RESET, RESET_P, input [5:0] FBDSEL, IDSEL, ODSEL,
  input [3:0] PSDA, DUTYDA, FDLY,
  output CLKOUT, CLKOUTP, CLKOUTD, CLKOUTD3, output LOCK);
  assign CLKOUT  = CLKIN;      // 27 -> 27 for this configuration
  assign CLKOUTP = CLKIN;      // phase shift is irrelevant to a functional sim
  assign CLKOUTD = 1'b0; assign CLKOUTD3 = 1'b0;
  assign LOCK = 1'b1;
endmodule
