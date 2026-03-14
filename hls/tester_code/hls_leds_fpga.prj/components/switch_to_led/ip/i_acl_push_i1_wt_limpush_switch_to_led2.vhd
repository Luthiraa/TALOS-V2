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

-- VHDL created from i_acl_push_i1_wt_limpush_switch_to_led2
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

entity i_acl_push_i1_wt_limpush_switch_to_led2 is
    port (
        in_data_in : in std_logic_vector(0 downto 0);  -- ufix1
        in_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_data_out : out std_logic_vector(0 downto 0);  -- ufix1
        out_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_feedback_stall_in_0 : in std_logic_vector(0 downto 0);  -- ufix1
        out_feedback_out_0 : out std_logic_vector(7 downto 0);  -- ufix8
        out_feedback_valid_out_0 : out std_logic_vector(0 downto 0);  -- ufix1
        in_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_acl_push_i1_wt_limpush_switch_to_led2;

architecture normal of i_acl_push_i1_wt_limpush_switch_to_led2 is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component acl_push is
        generic (
            FIFO_DEPTH : INTEGER;
            INF_LOOP : INTEGER;
            INF_LOOP_INITIALIZATION : STD_LOGIC_VECTOR(7 downto 0);
            MIN_FIFO_LATENCY : INTEGER;
            STYLE : STRING;
            DATA_WIDTH : INTEGER := 8;
            ENABLED : INTEGER := 0;
            RAM_FIFO_DEPTH_INC : INTEGER := 0;
            STALLFREE : INTEGER := 0
        );
        port (
            data_in : in std_logic_vector(7 downto 0);
            dir : in std_logic;
            feedback_stall_in : in std_logic;
            predicate : in std_logic;
            stall_in : in std_logic;
            valid_in : in std_logic;
            data_out : out std_logic_vector(7 downto 0);
            feedback_out : out std_logic_vector(7 downto 0);
            feedback_valid_out : out std_logic;
            stall_out : out std_logic;
            valid_out : out std_logic;
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component i_acl_push_i1_wt_limpush_switch_to_led_reg is
        port (
            in_data_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal GND_q : STD_LOGIC_VECTOR (0 downto 0);
    signal adapt_scalar_trunc_in : STD_LOGIC_VECTOR (0 downto 0);
    signal adapt_scalar_trunc_q : STD_LOGIC_VECTOR (0 downto 0);
    signal c_i7_0gr_q : STD_LOGIC_VECTOR (6 downto 0);
    signal element_extension_q : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_data_in : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_dir : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_dir_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led3_feedback_stall_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_feedback_stall_in_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led3_predicate : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_predicate_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led3_stall_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_stall_in_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led3_valid_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_valid_in_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led3_data_out : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_feedback_out : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_feedback_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_feedback_valid_out_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led3_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_stall_out_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led3_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led3_valid_out_bitsignaltemp : std_logic;
    signal i_acl_push_i1_wt_limpush_switch_to_led_reg_out_data_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led_reg_out_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led_reg_out_valid_out : STD_LOGIC_VECTOR (0 downto 0);

begin


    -- GND(CONSTANT,0)
    GND_q <= "0";

    -- c_i7_0gr(CONSTANT,6)
    c_i7_0gr_q <= "0000000";

    -- element_extension(BITJOIN,7)
    element_extension_q <= c_i7_0gr_q & in_data_in;

    -- i_acl_push_i1_wt_limpush_switch_to_led3(EXTIFACE,10)
    i_acl_push_i1_wt_limpush_switch_to_led3_data_in <= element_extension_q;
    i_acl_push_i1_wt_limpush_switch_to_led3_dir <= GND_q;
    i_acl_push_i1_wt_limpush_switch_to_led3_feedback_stall_in <= in_feedback_stall_in_0;
    i_acl_push_i1_wt_limpush_switch_to_led3_predicate <= GND_q;
    i_acl_push_i1_wt_limpush_switch_to_led3_stall_in <= i_acl_push_i1_wt_limpush_switch_to_led_reg_out_stall_out;
    i_acl_push_i1_wt_limpush_switch_to_led3_valid_in <= in_valid_in;
    i_acl_push_i1_wt_limpush_switch_to_led3_dir_bitsignaltemp <= i_acl_push_i1_wt_limpush_switch_to_led3_dir(0);
    i_acl_push_i1_wt_limpush_switch_to_led3_feedback_stall_in_bitsignaltemp <= i_acl_push_i1_wt_limpush_switch_to_led3_feedback_stall_in(0);
    i_acl_push_i1_wt_limpush_switch_to_led3_predicate_bitsignaltemp <= i_acl_push_i1_wt_limpush_switch_to_led3_predicate(0);
    i_acl_push_i1_wt_limpush_switch_to_led3_stall_in_bitsignaltemp <= i_acl_push_i1_wt_limpush_switch_to_led3_stall_in(0);
    i_acl_push_i1_wt_limpush_switch_to_led3_valid_in_bitsignaltemp <= i_acl_push_i1_wt_limpush_switch_to_led3_valid_in(0);
    i_acl_push_i1_wt_limpush_switch_to_led3_feedback_valid_out(0) <= i_acl_push_i1_wt_limpush_switch_to_led3_feedback_valid_out_bitsignaltemp;
    i_acl_push_i1_wt_limpush_switch_to_led3_stall_out(0) <= i_acl_push_i1_wt_limpush_switch_to_led3_stall_out_bitsignaltemp;
    i_acl_push_i1_wt_limpush_switch_to_led3_valid_out(0) <= i_acl_push_i1_wt_limpush_switch_to_led3_valid_out_bitsignaltemp;
    thei_acl_push_i1_wt_limpush_switch_to_led3 : acl_push
    GENERIC MAP (
        FIFO_DEPTH => 1,
        INF_LOOP => 0,
        INF_LOOP_INITIALIZATION => "00000000",
        MIN_FIFO_LATENCY => 0,
        STYLE => "TOKEN",
        DATA_WIDTH => 8,
        ENABLED => 0,
        RAM_FIFO_DEPTH_INC => 0,
        STALLFREE => 0
    )
    PORT MAP (
        data_in => element_extension_q,
        dir => i_acl_push_i1_wt_limpush_switch_to_led3_dir_bitsignaltemp,
        feedback_stall_in => i_acl_push_i1_wt_limpush_switch_to_led3_feedback_stall_in_bitsignaltemp,
        predicate => i_acl_push_i1_wt_limpush_switch_to_led3_predicate_bitsignaltemp,
        stall_in => i_acl_push_i1_wt_limpush_switch_to_led3_stall_in_bitsignaltemp,
        valid_in => i_acl_push_i1_wt_limpush_switch_to_led3_valid_in_bitsignaltemp,
        data_out => i_acl_push_i1_wt_limpush_switch_to_led3_data_out,
        feedback_out => i_acl_push_i1_wt_limpush_switch_to_led3_feedback_out,
        feedback_valid_out => i_acl_push_i1_wt_limpush_switch_to_led3_feedback_valid_out_bitsignaltemp,
        stall_out => i_acl_push_i1_wt_limpush_switch_to_led3_stall_out_bitsignaltemp,
        valid_out => i_acl_push_i1_wt_limpush_switch_to_led3_valid_out_bitsignaltemp,
        clock => clock,
        resetn => resetn
    );

    -- adapt_scalar_trunc(ROUND,4)
    adapt_scalar_trunc_in <= i_acl_push_i1_wt_limpush_switch_to_led3_data_out(0 downto 0);
    adapt_scalar_trunc_q <= adapt_scalar_trunc_in(0 downto 0);

    -- i_acl_push_i1_wt_limpush_switch_to_led_reg(BLACKBOX,11)@20000000
    -- out out_data_out@20000001
    -- out out_valid_out@20000001
    thei_acl_push_i1_wt_limpush_switch_to_led_reg : i_acl_push_i1_wt_limpush_switch_to_led_reg
    PORT MAP (
        in_data_in => adapt_scalar_trunc_q,
        in_stall_in => in_stall_in,
        in_valid_in => i_acl_push_i1_wt_limpush_switch_to_led3_valid_out,
        out_data_out => i_acl_push_i1_wt_limpush_switch_to_led_reg_out_data_out,
        out_stall_out => i_acl_push_i1_wt_limpush_switch_to_led_reg_out_stall_out,
        out_valid_out => i_acl_push_i1_wt_limpush_switch_to_led_reg_out_valid_out,
        clock => clock,
        resetn => resetn
    );

    -- dupName_0_sync_out_x(GPOUT,3)@2
    out_data_out <= i_acl_push_i1_wt_limpush_switch_to_led_reg_out_data_out;
    out_valid_out <= i_acl_push_i1_wt_limpush_switch_to_led_reg_out_valid_out;

    -- feedback_sync_out(GPOUT,9)
    out_feedback_out_0 <= i_acl_push_i1_wt_limpush_switch_to_led3_feedback_out;
    out_feedback_valid_out_0 <= i_acl_push_i1_wt_limpush_switch_to_led3_feedback_valid_out;

    -- sync_out(GPOUT,13)@20000000
    out_stall_out <= i_acl_push_i1_wt_limpush_switch_to_led3_stall_out;

END normal;
