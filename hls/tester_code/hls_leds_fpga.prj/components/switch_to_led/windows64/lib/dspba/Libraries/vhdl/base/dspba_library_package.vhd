-- Legal Notice: Copyright 2017 Intel Corporation.  All rights reserved.
-- Your use of  Intel  Corporation's design tools,  logic functions and other
-- software and tools,  and its AMPP  partner logic functions, and  any output
-- files  any of the  foregoing  device programming or simulation files),  and
-- any associated  documentation or information are expressly subject  to  the
-- terms and conditions  of the Intel FPGA Software License Agreement,
-- Intel  MegaCore  Function  License  Agreement, or other applicable license
-- agreement,  including,  without limitation,  that your use  is for the sole
-- purpose of  programming  logic  devices  manufactured by Intel and sold by
-- Intel or its authorized  distributors.  Please  refer  to  the  applicable
-- agreement for further details.


library IEEE;
use IEEE.std_logic_1164.all;

package dspba_library_package is

    component dspba_delay is
        generic (
            width : natural := 8;
            depth : natural := 1;
            reset_high : std_logic := '1';
            reset_kind : string := "ASYNC" 
        );
        port (
            clk   : in  std_logic;
            aclr  : in  std_logic;
            ena   : in  std_logic := '1';
            xin   : in  std_logic_vector(width-1 downto 0);
            xout  : out std_logic_vector(width-1 downto 0)
        );
    end component;

    component dspba_sync_reg is
        generic (
            width1 : natural := 8;
            width2 : natural := 8;
            depth : natural := 2;
            init_value : std_logic_vector;
            pulse_multiplier : natural := 1;
            counter_width : natural := 8;
            reset1_high : std_logic := '1';
            reset2_high : std_logic := '1';
            reset_kind : string := "ASYNC"
        );
        port (
            clk1    : in std_logic;
            aclr1   : in std_logic;
            ena     : in std_logic_vector(0 downto 0);
            xin     : in std_logic_vector(width1-1 downto 0);
            xout    : out std_logic_vector(width1-1 downto 0);
            clk2    : in std_logic;
            aclr2   : in std_logic;
            sxout   : out std_logic_vector(width2-1 downto 0)
        );
    end component;

    component dspba_pipe is
        generic(
            num_bits   : positive;
            num_stages : natural;
            init_value : std_logic := 'X'
        );
        port(
            clk: in    std_logic;
            d  : in    std_logic_vector(num_bits-1 downto 0);
            q  :   out std_logic_vector(num_bits-1 downto 0)
        );
    end component dspba_pipe;

end dspba_library_package;
