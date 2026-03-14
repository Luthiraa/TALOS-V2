DE1-SoC HLS Button Counter + UART Development Environment

Files
- hls_leds.cpp: Intel HLS C++ component with the push-button counter
- de1_soc_hls_leds.v: FPGA top-level wrapper for CLOCK_50, KEY[1:0], LEDR[9:0], HEX[5:0], UART_TXD, and JTAG probe
- de1_soc_hls_leds.qpf/.qsf/.sdc: Quartus project and timing constraints
- hls_leds_fpga.prj: generated HLS project with RTL/Qsys collateral
- de1_soc_hls_leds.sof: compiled FPGA bitstream
- run_hls_build.bat: rebuild HLS RTL
- jtag_count_monitor.tcl: live counter monitor over USB-Blaster/System Console

Build flow
1. Run run_hls_build.bat
2. Run quartus_sh --flow compile de1_soc_hls_leds
3. Run program_fpga.bat

Notes
- Target board: DE1-SoC
- FPGA device: 5CSEMA5F31C6
- This is FPGA-only logic, not HPS/ARM
- The HLS component counts debounced presses on KEY[0]
- KEY[1] resets the counter to zero
- run_hls_build.bat regenerates the HLS component and copies the fresh collateral into components/switch_to_led for Quartus
- LEDR[9:0] shows the low 10 bits of the count
- HEX5..HEX0 show the low 24 bits of the count in hexadecimal
- jtag_count_monitor.tcl reads the counter over USB-Blaster using In-System Sources and Probes
- UART_TXD transmits at 115200-8-N-1 and prints lines like: count=0x00000005
- On DE1-SoC the onboard USB-UART is tied to the HPS, so FPGA UART output is routed to GPIO_0[0] instead
- Connect GPIO_0[0] to an external USB-UART adapter RX pin and connect grounds together
