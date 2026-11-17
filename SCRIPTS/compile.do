.main clear

quit -sim

if {[file exists work]} {
    vdel -lib work -all
}

vlib work

vlog -sv ../RTL/axi4_RTL_pkg.sv
vlog -sv +acc ../RTL/axi4_slave.sv
vlog -sv +acc ../TB/axi4_protocol_checker.sv
vlog -f file.f



do wave.do