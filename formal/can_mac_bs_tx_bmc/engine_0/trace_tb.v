`ifndef VERILATOR
module testbench;
  reg [4095:0] vcdfile;
  reg clock;
`else
module testbench(input clock, output reg genclock);
  initial genclock = 1;
`endif
  reg genclock = 1;
  reg [31:0] cycle = 0;
  reg [0:0] PI_clk_i;
  reg [0:0] PI_rst_i;
  reg [1:0] \PI_bs_i[data] ;
  reg [0:0] \PI_bs_i[start] ;
  reg [0:0] \PI_bs_i[valid] ;
  can_mac_bs_tx UUT (
    .clk_i(PI_clk_i),
    .rst_i(PI_rst_i),
    .\bs_i[data] (\PI_bs_i[data] ),
    .\bs_i[start] (\PI_bs_i[start] ),
    .\bs_i[valid] (\PI_bs_i[valid] )
  );
`ifndef VERILATOR
  initial begin
    if ($value$plusargs("vcd=%s", vcdfile)) begin
      $dumpfile(vcdfile);
      $dumpvars(0, testbench);
    end
    #5 clock = 0;
    while (genclock) begin
      #5 clock = 0;
      #5 clock = 1;
    end
  end
`endif
  initial begin
`ifndef VERILATOR
    #1;
`endif
    // UUT.$auto$ghdl.\cc:846:import_module$107  = 3'b001;
    // UUT.$auto$ghdl.\cc:846:import_module$119  = 3'b001;
    // UUT.$auto$ghdl.\cc:846:import_module$134  = 3'b001;
    // UUT.$auto$ghdl.\cc:846:import_module$137  = 8'b00000001;
    // UUT.$auto$ghdl.\cc:846:import_module$162  = 8'b00000001;
    // UUT.$auto$ghdl.\cc:846:import_module$42  = 2'b01;
    // UUT.$auto$ghdl.\cc:846:import_module$45  = 3'b001;
    // UUT.$auto$ghdl.\cc:846:import_module$92  = 3'b001;
    UUT.\bs_o[data]  = 2'b00;
    UUT.\bs_o[sbc]  = 4'b0000;
    UUT.\bs_o[valid]  = 1'b0;
    UUT.consecutive_count = 3'b000;
    UUT.consecutive_count_prev = 3'b000;
    UUT.last_polarity = 2'b01;
    UUT.reset_done = 1'b0;
    UUT.stuff_count = 3'b000;
    UUT.stuff_count_prev = 3'b000;
    UUT.stuff_valid_prev = 1'b0;

    // state 0
    PI_clk_i = 1'b0;
    PI_rst_i = 1'b1;
    \PI_bs_i[data]  = 2'b00;
    \PI_bs_i[start]  = 1'b0;
    \PI_bs_i[valid]  = 1'b1;
  end
  always @(posedge clock) begin
    // state 1
    if (cycle == 0) begin
      PI_clk_i <= 1'b0;
      PI_rst_i <= 1'b0;
      \PI_bs_i[data]  <= 2'b01;
      \PI_bs_i[start]  <= 1'b0;
      \PI_bs_i[valid]  <= 1'b1;
    end

    // state 2
    if (cycle == 1) begin
      PI_clk_i <= 1'b0;
      PI_rst_i <= 1'b0;
      \PI_bs_i[data]  <= 2'b01;
      \PI_bs_i[start]  <= 1'b0;
      \PI_bs_i[valid]  <= 1'b1;
    end

    // state 3
    if (cycle == 2) begin
      PI_clk_i <= 1'b0;
      PI_rst_i <= 1'b0;
      \PI_bs_i[data]  <= 2'b01;
      \PI_bs_i[start]  <= 1'b0;
      \PI_bs_i[valid]  <= 1'b1;
    end

    // state 4
    if (cycle == 3) begin
      PI_clk_i <= 1'b0;
      PI_rst_i <= 1'b0;
      \PI_bs_i[data]  <= 2'b01;
      \PI_bs_i[start]  <= 1'b0;
      \PI_bs_i[valid]  <= 1'b1;
    end

    // state 5
    if (cycle == 4) begin
      PI_clk_i <= 1'b0;
      PI_rst_i <= 1'b0;
      \PI_bs_i[data]  <= 2'b01;
      \PI_bs_i[start]  <= 1'b1;
      \PI_bs_i[valid]  <= 1'b1;
    end

    // state 6
    if (cycle == 5) begin
      PI_clk_i <= 1'b0;
      PI_rst_i <= 1'b0;
      \PI_bs_i[data]  <= 2'b00;
      \PI_bs_i[start]  <= 1'b0;
      \PI_bs_i[valid]  <= 1'b1;
    end

    genclock <= cycle < 6;
    cycle <= cycle + 1;
  end
endmodule
