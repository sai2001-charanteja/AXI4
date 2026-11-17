.main clear

vsim -assertdebug -sv_lib C:/questasim64_2021.1/uvm-1.2/win64/uvm_dpi \
    work.axi4_slave_tb

     
do wave.do

run -all



