# setup name of the clock in your design.
set clkname clk

# set variable "modname" to the name of topmost module in design
set modname top

# set variable "RTL_DIR" to the HDL directory w.r.t synthesis directory
set RTL_DIR ./../

# set variable "type" to a name that distinguishes this synthesis run
set type cpu_synth

#set the number of digits to be used for delay results
set report_default_significant_digits 4

set CLK_PER 25
#------------------------------------------------------------
#
# Basic Synthesis Script (TCL format)
#                                  
# Revision History                
#   1/15/03  : Author Shane T. Gehring - from class example
#   2/09/07  : Author Zhengtao Yu      - from class example
#   12/14/07 : Author Ravi Jenkal      - updated to 180 nm & tcl
#   S 2020   : P. Franzon             - general updates
#   2024     : Modified for multi-file CPU design
#
#------------------------------------------------------------

#---------------------------------------------------------
# Set up search path to find all RTL files and includes
#---------------------------------------------------------
set search_path [concat $search_path $RTL_DIR]

#---------------------------------------------------------
# Read in all SystemVerilog files.
# defines.svh is a package so it must be read first.
# MAKE SURE THAT YOU CORRECT ALL WARNINGS THAT APPEAR
# during the execution of the read command are fixed
# or understood to have no impact.
# ALSO CHECK your latch/flip-flop list for unintended
# latches
#---------------------------------------------------------
#---------------------------------------------------------
# Analyze all files (analyze handles packages/includes cleanly)
#---------------------------------------------------------
analyze -format sverilog -lib WORK [list \
    $RTL_DIR/defines.svh     \
    $RTL_DIR/control_unit.sv \
    $RTL_DIR/fetch.sv        \
    $RTL_DIR/decode.sv       \
    $RTL_DIR/execute.sv      \
    $RTL_DIR/memory.sv       \
    $RTL_DIR/write_back.sv   \
    $RTL_DIR/top.sv          \
]
puts "###################################"
puts "#       ELABORATION DONE          #"
puts "###################################"
#---------------------------------------------------------
# Elaborate the top level design
#---------------------------------------------------------
elaborate $modname
puts "###################################"
puts "#       COMPILATION DONE          #"
puts "###################################"

#---------------------------------------------------------
# Set the current design to the top level instance name
# to make sure that you are working on the right design
# at the time of constraint setting and compilation
#---------------------------------------------------------
current_design $modname

#---------------------------------------------------------
# Set the synthetic library variable to enable use of
# designware blocks
#---------------------------------------------------------
set synthetic_library [list dw_foundation.sldb]

#---------------------------------------------------------
# Specify the worst case (slowest) libraries and
# slowest temperature/Vcc conditions
#---------------------------------------------------------
set target_library NangateOpenCellLibrary_PDKv1_2_v2008_10_slow_nldm.db
set link_library   [concat $target_library $synthetic_library]

#---------------------------------------------------------
# Specify clock period with 50% duty cycle
# and a skew of 50ps
#---------------------------------------------------------
set CLK_SKEW 0.05
create_clock -name $clkname -period $CLK_PER \
    -waveform "0 [expr $CLK_PER / 2]" $clkname
set_clock_uncertainty $CLK_SKEW $clkname

#---------------------------------------------------------
# Set up I/O constraints
#---------------------------------------------------------
set DFF_CKQ    0.638
set IP_DELAY   [expr 0.02 + $DFF_CKQ]
set_input_delay $IP_DELAY -clock $clkname \
    [remove_from_collection [all_inputs] $clkname]

set DFF_SETUP  0.546
set OP_DELAY   [expr 0.02 + $DFF_SETUP]
set_output_delay $OP_DELAY -clock $clkname [all_outputs]

set DR_CELL_NAME DFFR_X1
set DR_CELL_PIN  Q
set_driving_cell -lib_cell "$DR_CELL_NAME" -pin "$DR_CELL_PIN" \
    [remove_from_collection [all_inputs] $clkname]

set PORT_LOAD_CELL  NangateOpenCellLibrary_PDKv1_2_v2008_10_slow_nldm/DFFR_X1/D
set WIRE_LOAD_EST   0.013
set FANOUT          4
set PORT_LOAD [expr $WIRE_LOAD_EST + $FANOUT * [load_of $PORT_LOAD_CELL]]
set_load $PORT_LOAD [all_outputs]

#---------------------------------------------------------
# Set area goal
#---------------------------------------------------------
set_max_area 0

#---------------------------------------------------------
# Prevent feedthroughs
#---------------------------------------------------------
set_fix_multiple_port_nets -all -buffer_constants [get_designs]

#---------------------------------------------------------
# Flatten design for logic reduction
#---------------------------------------------------------
ungroup -flatten -all

#---------------------------------------------------------
# Check and link design
#---------------------------------------------------------
check_design
link

#---------------------------------------------------------
# Compile
#---------------------------------------------------------
compile_ultra

 
#---------------------------------------------------------
# Report critical (slowest) path - setup timing check
# If slack is NOT MET you have a problem and need to
# redesign or apply further optimization techniques
#---------------------------------------------------------
puts "#########################################"
puts "#       TIMING MAX SLOW REPORT          #"
puts "#########################################"
report_timing > timing_max_slow.rpt
 
#---------------------------------------------------------
# This is your section to do different things to
# improve timing or area - RTFM (Read The Manual) :)
#---------------------------------------------------------
 
 
 
#---------------------------------------------------------
# Re-run check_design to confirm no new issues after compile
#---------------------------------------------------------
check_design
 
#---------------------------------------------------------
# Now resynthesize for the fastest corner to check
# hold time conditions are met
#---------------------------------------------------------
set target_library NangateOpenCellLibrary_PDKv1_2_v2008_10_fast_nldm.db
set link_library   NangateOpenCellLibrary_PDKv1_2_v2008_10_slow_nldm.db
set link_library   [concat $link_library dw_foundation.sldb]
translate

set_fix_hold $clkname
compile -only_design_rule -incremental 
puts "########################################"
puts "#       TIMING MIN FAST HOLDFIX         #"
puts "########################################"
report_timing -delay min > timing_min_fast_holdcheck_${type}.rpt
 
 
#---------------------------------------------------------
# Recheck setup timing after hold fixing with slow corner
# YOU have problems if the slack is NOT MET
#---------------------------------------------------------
set target_library NangateOpenCellLibrary_PDKv1_2_v2008_10_slow_nldm.db
set link_library   NangateOpenCellLibrary_PDKv1_2_v2008_10_slow_nldm.db
set link_library   [concat $link_library dw_foundation.sldb]
translate
puts "#########################################"
puts "#       TIMING MAX SLOW HOLDFIX         #"
puts "########################################"
report_timing > timing_max_slow_holdfixed_${type}.rpt
 
#---------------------------------------------------------
# Write out area distribution for the final design
#---------------------------------------------------------
report_cell > cell_report_final.rpt
 
report_timing > ${type}_timing_${CLK_PER}.rpt
report_area   > ${type}_area_${CLK_PER}.rpt
report_power  > ${type}_power_${CLK_PER}.rpt
report_constraint -all_violators > ${type}_constraints_${CLK_PER}.rpt
report_timing
report_power
report_constraint -all_violators
report_area
