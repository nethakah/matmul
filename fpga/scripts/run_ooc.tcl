# synthize + implement 1 design at 1 parameter set then emit PPA results

# cd fpga/scripts/
# vivado -mode batch -source run_ooc.tcl -tclargs <version> <N> [<M> <K>]

set version [lindex $argv 0]
set N [lindex $argv 1]
set M [expr {$argc > 2 ? [lindex $argv 2] : $N}]
set K [expr {$argc > 3 ? [lindex $argv 3] : $N}]

set part xczu7ev-ffvc1156-2-e

set here [file dirname [file normalize [info script]]]
set root [file normalize $here/../..]

set outdir $root/fpga/results/${version}_M${M}_N${N}_K${K}
file mkdir $outdir

puts "=== $version M=$M N=$N K=$K part=$part ==="

read_verilog -sv [glob $root/$version/rtl/*.sv]
read_xdc $root/fpga/constraints/clk.xdc

# OOC - no i/o buffer insertion so we don't need pin assignments
# only sys_bram paramaterized by all 3 dims
if {$version eq "systolic_bram"} {
    synth_design -top chip -part $part -mode out_of_context -generic M=$M -generic N=$N -generic K=$K
} else {
    synth_design -top chip -part $part -mode out_of_context -generic N=$N
}

opt_design
place_design
phys_opt_design
route_design

report_utilization -file $outdir/utilization.rpt
report_timing_summary -file $outdir/timing.rpt
report_power -file $outdir/power.rpt

# Fmax
set wns [get_property SLACK [get_timing_paths -delay_type max]]
set period 2.000
set fmax [expr {1000.0 / ($period - $wns)}]

set luts [llength [get_cells -hier -filter {PRIMITIVE_GROUP == LUT}]]
set ffs [llength [get_cells -hier -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]
set dsps [llength [get_cells -hier -filter {PRIMITIVE_GROUP == ARITHMETIC}]]
set brams [llength [get_cells -hier -filter {PRIMITIVE_GROUP == BLOCKRAM}]]

set fh [open $outdir/summary.txt w]
puts $fh "version $version"
puts $fh "M $M N $N K $K"
puts $fh "LUT $luts"
puts $fh "FF $ffs"
puts $fh "DSP $dsps"
puts $fh "BRAM $brams"
puts $fh "WNS $wns ns"
puts $fh "Fmax [format %.1f $fmax] MHz"
close $fh

puts "=== DONE $version M=$M N=$N K=$K -> Fmax [format %.1f $fmax] MHz, $luts LUT, $dsps DSP ==="