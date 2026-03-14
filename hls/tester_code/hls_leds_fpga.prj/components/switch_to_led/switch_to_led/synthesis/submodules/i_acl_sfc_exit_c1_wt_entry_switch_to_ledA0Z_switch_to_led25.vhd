-- ------------------------------------------------------------------------- 
-- High Level Design Compiler for Intel(R) FPGAs Version 18.1 (Release Build #625)
-- 
-- Legal Notice: Copyright 2018 Intel Corporation.  All rights reserved.
-- Your use of  Intel Corporation's design tools,  logic functions and other
-- software and  tools, and its AMPP partner logic functions, and any output
-- files any  of the foregoing (including  device programming  or simulation
-- files), and  any associated  documentation  or information  are expressly
-- subject  to the terms and  conditions of the  Intel FPGA Software License
-- Agreement, Intel MegaCore Function License Agreement, or other applicable
-- license agreement,  including,  without limitation,  that your use is for
-- the  sole  purpose of  programming  logic devices  manufactured by  Intel
-- and  sold by Intel  or its authorized  distributors. Please refer  to the
-- applicable agreement for further details.
-- ---------------------------------------------------------------------------

-- VHDL created from i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led25
-- VHDL created on Sat Mar 14 14:14:06 2026


library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.NUMERIC_STD.all;
use IEEE.MATH_REAL.all;
use std.TextIO.all;
use work.dspba_library_package.all;

LIBRARY altera_mf;
USE altera_mf.altera_mf_components.all;
LIBRARY altera_lnsim;
USE altera_lnsim.altera_lnsim_components.altera_syncram;
LIBRARY lpm;
USE lpm.lpm_components.all;

entity i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led25 is
    port (
        in_data_in_0 : in std_logic_vector(0 downto 0);  -- ufix1
        in_data_in_1 : in std_logic_vector(31 downto 0);  -- ufix32
        in_dec_pipelined_thread : in std_logic_vector(0 downto 0);  -- ufix1
        in_inc_pipelined_thread : in std_logic_vector(0 downto 0);  -- ufix1
        in_input_accepted : in std_logic_vector(0 downto 0);  -- ufix1
        in_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_data_out_0 : out std_logic_vector(0 downto 0);  -- ufix1
        out_data_out_1 : out std_logic_vector(31 downto 0);  -- ufix32
        out_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_stall_entry : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led25;

architecture normal of i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led25 is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo is
        port (
            in_data_in_0 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_data_in_1 : in std_logic_vector(31 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out_0 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out_1 : out std_logic_vector(31 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector is
        port (
            in_dec_pipelined_thread : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_decrement : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_inc_pipelined_thread : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_increment : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_full : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_throttle : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal VCC_q : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_data_out_0 : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_data_out_1 : STD_LOGIC_VECTOR (31 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_out_full : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_out_throttle : STD_LOGIC_VECTOR (0 downto 0);
    signal not_keep_going_q : STD_LOGIC_VECTOR (0 downto 0);
    signal not_stall_in_q : STD_LOGIC_VECTOR (0 downto 0);
    signal output_accepted_and_q : STD_LOGIC_VECTOR (0 downto 0);
    signal stall_out_or_q : STD_LOGIC_VECTOR (0 downto 0);

begin


    -- i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x(BLACKBOX,4)@20000000
    -- out out_data_out_0@20000003
    -- out out_data_out_1@20000003
    -- out out_valid_out@20000003
    thei_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x : i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo
    PORT MAP (
        in_data_in_0 => in_data_in_0,
        in_data_in_1 => in_data_in_1,
        in_stall_in => in_stall_in,
        in_valid_in => in_valid_in,
        out_data_out_0 => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_data_out_0,
        out_data_out_1 => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_data_out_1,
        out_valid_out => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_valid_out,
        clock => clock,
        resetn => resetn
    );

    -- dupName_0_sync_out_aunroll_x(GPOUT,3)@20000003
    out_data_out_0 <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_data_out_0;
    out_data_out_1 <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_data_out_1;
    out_valid_out <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_valid_out;

    -- VCC(CONSTANT,1)
    VCC_q <= "1";

    -- not_stall_in(LOGICAL,7)
    not_stall_in_q <= not (in_stall_in);

    -- output_accepted_and(LOGICAL,8)
    output_accepted_and_q <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo_aunroll_x_out_valid_out and not_stall_in_q;

    -- not_keep_going(LOGICAL,6)
    not_keep_going_q <= not (in_dec_pipelined_thread);

    -- i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector(BLACKBOX,5)@20000000
    thei_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector : i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector
    PORT MAP (
        in_dec_pipelined_thread => not_keep_going_q,
        in_decrement => output_accepted_and_q,
        in_inc_pipelined_thread => in_inc_pipelined_thread,
        in_increment => in_input_accepted,
        out_full => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_out_full,
        out_throttle => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_out_throttle,
        clock => clock,
        resetn => resetn
    );

    -- stall_out_or(LOGICAL,9)
    stall_out_or_q <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_out_full or i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_out_throttle;

    -- sync_out(GPOUT,11)@20000000
    out_stall_entry <= stall_out_or_q;

END normal;
