# SimVision view of a run recorded with WAVES=1 (make uvm-gui): the pins of the system, the data
# port of the CPU, the master port of the DMA and the commands and status of the accelerator.
database require wv -search waves.shm
set top $env(MM_TOP)
if {$top eq "tb_soc"} {
    set sub $top.u_dut.u_subsys
} else {
    set sub $top.u_dut
}
set w [waveform new]
window geometry $w 1600x900+20+20

waveform add -using $w -signals [list wv::$top.clk wv::$top.sys.rst_n wv::$top.sys.irq]
waveform add -using $w -signals [list \
    wv::$top.cpu_tap.awaddr wv::$top.cpu_tap.awvalid wv::$top.cpu_tap.wdata \
    wv::$top.cpu_tap.araddr wv::$top.cpu_tap.arvalid wv::$top.cpu_tap.rdata \
    wv::$top.cpu_tap.rvalid]
waveform add -using $w -signals [list \
    wv::$top.dma_tap.awaddr wv::$top.dma_tap.awvalid wv::$top.dma_tap.wdata \
    wv::$top.dma_tap.araddr wv::$top.dma_tap.arvalid wv::$top.dma_tap.rdata \
    wv::$top.dma_tap.rvalid]
waveform add -using $w -signals [list \
    wv::$sub.acc_load wv::$sub.acc_start wv::$sub.acc_status]

foreach s [list cpu_tap.awaddr cpu_tap.wdata cpu_tap.araddr cpu_tap.rdata \
               dma_tap.awaddr dma_tap.wdata dma_tap.araddr dma_tap.rdata] {
    waveform format -using $w wv::$top.$s -radix %x
}
waveform format -using $w wv::$sub.acc_status -radix %x

# The whole first operation fits in the view; T0 and T1 (e.g. 0ns, 6000ns) change the window.
set t0 [expr {[info exists env(T0)] ? $env(T0) : "0ns"}]
set t1 [expr {[info exists env(T1)] ? $env(T1) : "6000ns"}]
waveform xview limits -using $w $t0 $t1
