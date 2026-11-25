/* Address to slave selection. A region owns an address only if the offset also fits the region
   size, so an access past the end of a region is a decode error instead of aliasing onto the
   start of the same region. The instruction memory is not on the bus, so its region decodes to
   no slave: a data access to it is reported, not served. */
module soc_axil_addr_decoder
  import soc_pkg::*;
#(
    parameter int DMEM_BYTES = DMEM_BYTES_DEFAULT
) (
    input  logic [AXIL_ADDR_WIDTH-1:0] addr_i,
    output logic [NUM_SLAVES-1:0] sel_o,
    output logic decerr_o
);

  always_comb begin
    sel_o = '0;
    sel_o[SLV_DMEM] = soc_in_region(addr_i, DMEM_BASE, DMEM_BYTES);
    sel_o[SLV_DMAREG] = soc_in_region(addr_i, DMAREG_BASE, DMAREG_BYTES);
    sel_o[SLV_ACCEL] = soc_in_region(addr_i, ACCEL_BASE, ACCEL_BYTES);
  end

  assign decerr_o = (sel_o == '0);

endmodule
