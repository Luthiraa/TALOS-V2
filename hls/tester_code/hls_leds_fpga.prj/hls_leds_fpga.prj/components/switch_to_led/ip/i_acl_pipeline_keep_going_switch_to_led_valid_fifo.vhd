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

-- VHDL created from i_acl_pipeline_keep_going_switch_to_led_valid_fifo
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

entity i_acl_pipeline_keep_going_switch_to_led_valid_fifo is
    port (
        in_data_in : in std_logic_vector(1 downto 0);  -- ufix2
        in_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        in_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_data_out : out std_logic_vector(1 downto 0);  -- ufix2
        out_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        out_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_acl_pipeline_keep_going_switch_to_led_valid_fifo;

architecture normal of i_acl_pipeline_keep_going_switch_to_led_valid_fifo is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component acl_data_fifo is
        generic (
            DATA_WIDTH : INTEGER := 2;
            DEPTH : INTEGER := 1;
            IMPL : STRING := "passthrough"
        );
        port (
            data_in : in std_logic_vector(1 downto 0);
            stall_in : in std_logic;
            valid_in : in std_logic;
            data_out : out std_logic_vector(1 downto 0);
            stall_out : out std_logic;
            valid_out : out std_logic;
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_data_in : STD_LOGIC_VECTOR (1 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_data_out : STD_LOGIC_VECTOR (1 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_out_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_out_bitsignaltemp : std_logic;

begin


    -- i_acl_pipeline_keep_going_switch_to_led_valid_fifo(EXTIFACE,2)
    i_acl_pipeline_keep_going_switch_to_led_valid_fifo_data_in <= in_data_in;
    i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_in <= in_stall_in;
    i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_in <= in_valid_in;
    i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_in(0);
    i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_in(0);
    i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_out(0) <= i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_out_bitsignaltemp;
    i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_out(0) <= i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_out_bitsignaltemp;
    thei_acl_pipeline_keep_going_switch_to_led_valid_fifo : acl_data_fifo
    GENERIC MAP (
        DATA_WIDTH => 2,
        DEPTH => 1,
        IMPL => "passthrough"
    )
    PORT MAP (
        data_in => in_data_in,
        stall_in => i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_in_bitsignaltemp,
        valid_in => i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_in_bitsignaltemp,
        data_out => i_acl_pipeline_keep_going_switch_to_led_valid_fifo_data_out,
        stall_out => i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_out_bitsignaltemp,
        valid_out => i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_out_bitsignaltemp,
        clock => clock,
        resetn => resetn
    );

    -- out_data_out(GPOUT,6)
    out_data_out <= i_acl_pipeline_keep_going_switch_to_led_valid_fifo_data_out;

    -- out_stall_out(GPOUT,7)
    out_stall_out <= i_acl_pipeline_keep_going_switch_to_led_valid_fifo_stall_out;

    -- out_valid_out(GPOUT,8)
    out_valid_out <= i_acl_pipeline_keep_going_switch_to_led_valid_fifo_valid_out;

END normal;
