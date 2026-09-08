transcript on
if ![file isdirectory verilog_libs] {
	file mkdir verilog_libs
}

vlib verilog_libs/altera_ver
vmap altera_ver ./verilog_libs/altera_ver
vlog -vlog01compat -work altera_ver {e:/quartus/altera/quartus/eda/sim_lib/altera_primitives.v}

vlib verilog_libs/lpm_ver
vmap lpm_ver ./verilog_libs/lpm_ver
vlog -vlog01compat -work lpm_ver {e:/quartus/altera/quartus/eda/sim_lib/220model.v}

vlib verilog_libs/sgate_ver
vmap sgate_ver ./verilog_libs/sgate_ver
vlog -vlog01compat -work sgate_ver {e:/quartus/altera/quartus/eda/sim_lib/sgate.v}

vlib verilog_libs/altera_mf_ver
vmap altera_mf_ver ./verilog_libs/altera_mf_ver
vlog -vlog01compat -work altera_mf_ver {e:/quartus/altera/quartus/eda/sim_lib/altera_mf.v}

vlib verilog_libs/altera_lnsim_ver
vmap altera_lnsim_ver ./verilog_libs/altera_lnsim_ver
vlog -sv -work altera_lnsim_ver {e:/quartus/altera/quartus/eda/sim_lib/altera_lnsim.sv}

vlib verilog_libs/cycloneive_ver
vmap cycloneive_ver ./verilog_libs/cycloneive_ver
vlog -vlog01compat -work cycloneive_ver {e:/quartus/altera/quartus/eda/sim_lib/cycloneive_atoms.v}

if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+d:/yscore/src {d:/yscore/src/core_ctl.v} \
                                             {d:/yscore/src/ctl_ifid.v} \
                                             {d:/yscore/src/ctl_exe.v} \
                                             {d:/yscore/src/ctl_perips.v} \
                                             {d:/yscore/src/ctl_wb.v} \
                                             {d:/yscore/src/core_ifid.v} \
                                             {d:/yscore/src/core_if.v} \
                                             {d:/yscore/src/core_id.v} \
                                             {d:/yscore/src/ifid_insmem.v} \
                                             {d:/yscore/src/ifid_immex.v} \
                                             {d:/yscore/src/ifid_mux_alusrc1.v} \
                                             {d:/yscore/src/ifid_mux_alusrc2.v} \
                                             {d:/yscore/src/core_exe.v} \
                                             {d:/yscore/src/exe_alu.v} \
                                             {d:/yscore/src/exe_next.v} \
                                             {d:/yscore/src/core_perips.v} \
                                             {d:/yscore/src/mem_ctl.v} \
                                             {d:/yscore/src/mem_cell.v} \
                                             {d:/yscore/src/core_wb.v} \
                                             {d:/yscore/src/regfile.v}  \
                                             {d:/yscore/src/regfile_csr.v}\
                                             {d:/yscore/src/wb_mux_pc.v} \
                                             {d:/yscore/src/axil_master.v} \
                                             {d:/yscore/src/axil_uart.v} \
                                             {d:/yscore/src/axil_gpio.v} \
                                             {d:/yscore/src/clint.v}

vlog -vlog01compat -work work +incdir+d:/yscore/tb {d:/yscore/tb/mycpu_sim.v}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cycloneive_ver -L rtl_work -L work -voptargs="+acc"  mycpu_sim

add wave *
view structure
view signals
run -all
