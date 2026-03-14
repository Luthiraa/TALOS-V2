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

-- VHDL created from bb_switch_to_led_B0_runOnce_stall_region
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

entity bb_switch_to_led_B0_runOnce_stall_region is
    port (
        in_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end bb_switch_to_led_B0_runOnce_stall_region;

architecture normal of bb_switch_to_led_B0_runOnce_stall_region is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component i_acl_pop_i1_wt_limpop_switch_to_led0 is
        port (
            in_data_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_dir : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_feedback_in_0 : in std_logic_vector(7 downto 0);  -- Fixed Point
            in_feedback_valid_in_0 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_predicate : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_feedback_stall_out_0 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component i_acl_push_i1_wt_limpush_switch_to_led2 is
        port (
            in_data_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_feedback_stall_in_0 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_feedback_out_0 : out std_logic_vector(7 downto 0);  -- Fixed Point
            out_feedback_valid_out_0 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component switch_to_led_B0_runOnce_merge_reg is
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
    signal i_acl_pop_i1_wt_limpop_switch_to_led_out_feedback_stall_out_0 : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pop_i1_wt_limpop_switch_to_led_out_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pop_i1_wt_limpop_switch_to_led_out_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led_out_feedback_out_0 : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led_out_feedback_valid_out_0 : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led_out_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_wt_limpush_switch_to_led_out_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal switch_to_led_B0_runOnce_merge_reg_out_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal switch_to_led_B0_runOnce_merge_reg_out_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_wireValid : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_backStall : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_V0 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_i_acl_push_i1_wt_limpush_switch_to_led_wireValid : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_i_acl_push_i1_wt_limpush_switch_to_led_backStall : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_stall_entry_wireValid : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_stall_entry_backStall : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_stall_entry_V0 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_wireValid : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_wireStall : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_StallValid : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_toReg0 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg0 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_consumed0 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_toReg1 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg1 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_consumed1 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_or0 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_backStall : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_V0 : STD_LOGIC_VECTOR (0 downto 0);
    signal SE_out_switch_to_led_B0_runOnce_merge_reg_V1 : STD_LOGIC_VECTOR (0 downto 0);

begin


    -- SE_stall_entry(STALLENABLE,30)
    -- Valid signal propagation
    SE_stall_entry_V0 <= SE_stall_entry_wireValid;
    -- Backward Stall generation
    SE_stall_entry_backStall <= switch_to_led_B0_runOnce_merge_reg_out_stall_out or not (SE_stall_entry_wireValid);
    -- Computing multiple Valid(s)
    SE_stall_entry_wireValid <= in_valid_in;

    -- switch_to_led_B0_runOnce_merge_reg(BLACKBOX,19)@0
    -- in in_stall_in@20000000
    -- out out_data_out@1
    -- out out_stall_out@20000000
    -- out out_valid_out@1
    theswitch_to_led_B0_runOnce_merge_reg : switch_to_led_B0_runOnce_merge_reg
    PORT MAP (
        in_data_in => GND_q,
        in_stall_in => SE_out_switch_to_led_B0_runOnce_merge_reg_backStall,
        in_valid_in => SE_stall_entry_V0,
        out_stall_out => switch_to_led_B0_runOnce_merge_reg_out_stall_out,
        out_valid_out => switch_to_led_B0_runOnce_merge_reg_out_valid_out,
        clock => clock,
        resetn => resetn
    );

    -- SE_out_switch_to_led_B0_runOnce_merge_reg(STALLENABLE,33)
    SE_out_switch_to_led_B0_runOnce_merge_reg_clkproc: PROCESS (clock, resetn)
    BEGIN
        IF (resetn = '0') THEN
            SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg0 <= (others => '0');
            SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg1 <= (others => '0');
        ELSIF (clock'EVENT AND clock = '1') THEN
            -- Succesor 0
            SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg0 <= SE_out_switch_to_led_B0_runOnce_merge_reg_toReg0;
            -- Succesor 1
            SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg1 <= SE_out_switch_to_led_B0_runOnce_merge_reg_toReg1;
        END IF;
    END PROCESS;
    -- Input Stall processing
    SE_out_switch_to_led_B0_runOnce_merge_reg_consumed0 <= (not (i_acl_pop_i1_wt_limpop_switch_to_led_out_stall_out) and SE_out_switch_to_led_B0_runOnce_merge_reg_wireValid) or SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg0;
    SE_out_switch_to_led_B0_runOnce_merge_reg_consumed1 <= (not (i_acl_push_i1_wt_limpush_switch_to_led_out_stall_out) and SE_out_switch_to_led_B0_runOnce_merge_reg_wireValid) or SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg1;
    -- Consuming
    SE_out_switch_to_led_B0_runOnce_merge_reg_StallValid <= SE_out_switch_to_led_B0_runOnce_merge_reg_backStall and SE_out_switch_to_led_B0_runOnce_merge_reg_wireValid;
    SE_out_switch_to_led_B0_runOnce_merge_reg_toReg0 <= SE_out_switch_to_led_B0_runOnce_merge_reg_StallValid and SE_out_switch_to_led_B0_runOnce_merge_reg_consumed0;
    SE_out_switch_to_led_B0_runOnce_merge_reg_toReg1 <= SE_out_switch_to_led_B0_runOnce_merge_reg_StallValid and SE_out_switch_to_led_B0_runOnce_merge_reg_consumed1;
    -- Backward Stall generation
    SE_out_switch_to_led_B0_runOnce_merge_reg_or0 <= SE_out_switch_to_led_B0_runOnce_merge_reg_consumed0;
    SE_out_switch_to_led_B0_runOnce_merge_reg_wireStall <= not (SE_out_switch_to_led_B0_runOnce_merge_reg_consumed1 and SE_out_switch_to_led_B0_runOnce_merge_reg_or0);
    SE_out_switch_to_led_B0_runOnce_merge_reg_backStall <= SE_out_switch_to_led_B0_runOnce_merge_reg_wireStall;
    -- Valid signal propagation
    SE_out_switch_to_led_B0_runOnce_merge_reg_V0 <= SE_out_switch_to_led_B0_runOnce_merge_reg_wireValid and not (SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg0);
    SE_out_switch_to_led_B0_runOnce_merge_reg_V1 <= SE_out_switch_to_led_B0_runOnce_merge_reg_wireValid and not (SE_out_switch_to_led_B0_runOnce_merge_reg_fromReg1);
    -- Computing multiple Valid(s)
    SE_out_switch_to_led_B0_runOnce_merge_reg_wireValid <= switch_to_led_B0_runOnce_merge_reg_out_valid_out;

    -- SE_out_i_acl_push_i1_wt_limpush_switch_to_led(STALLENABLE,29)
    -- Backward Stall generation
    SE_out_i_acl_push_i1_wt_limpush_switch_to_led_backStall <= "0";
    -- Computing multiple Valid(s)
    SE_out_i_acl_push_i1_wt_limpush_switch_to_led_wireValid <= i_acl_push_i1_wt_limpush_switch_to_led_out_valid_out;

    -- i_acl_push_i1_wt_limpush_switch_to_led(BLACKBOX,14)@1
    -- in in_stall_in@20000000
    -- out out_data_out@2
    -- out out_feedback_out_0@20000000
    -- out out_feedback_valid_out_0@20000000
    -- out out_stall_out@20000000
    -- out out_valid_out@2
    thei_acl_push_i1_wt_limpush_switch_to_led : i_acl_push_i1_wt_limpush_switch_to_led2
    PORT MAP (
        in_data_in => GND_q,
        in_feedback_stall_in_0 => i_acl_pop_i1_wt_limpop_switch_to_led_out_feedback_stall_out_0,
        in_stall_in => SE_out_i_acl_push_i1_wt_limpush_switch_to_led_backStall,
        in_valid_in => SE_out_switch_to_led_B0_runOnce_merge_reg_V1,
        out_feedback_out_0 => i_acl_push_i1_wt_limpush_switch_to_led_out_feedback_out_0,
        out_feedback_valid_out_0 => i_acl_push_i1_wt_limpush_switch_to_led_out_feedback_valid_out_0,
        out_stall_out => i_acl_push_i1_wt_limpush_switch_to_led_out_stall_out,
        out_valid_out => i_acl_push_i1_wt_limpush_switch_to_led_out_valid_out,
        clock => clock,
        resetn => resetn
    );

    -- GND(CONSTANT,0)
    GND_q <= "0";

    -- i_acl_pop_i1_wt_limpop_switch_to_led(BLACKBOX,13)@1
    -- in in_stall_in@20000000
    -- out out_data_out@2
    -- out out_feedback_stall_out_0@20000000
    -- out out_stall_out@20000000
    -- out out_valid_out@2
    thei_acl_pop_i1_wt_limpop_switch_to_led : i_acl_pop_i1_wt_limpop_switch_to_led0
    PORT MAP (
        in_data_in => GND_q,
        in_dir => GND_q,
        in_feedback_in_0 => i_acl_push_i1_wt_limpush_switch_to_led_out_feedback_out_0,
        in_feedback_valid_in_0 => i_acl_push_i1_wt_limpush_switch_to_led_out_feedback_valid_out_0,
        in_predicate => GND_q,
        in_stall_in => SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_backStall,
        in_valid_in => SE_out_switch_to_led_B0_runOnce_merge_reg_V0,
        out_feedback_stall_out_0 => i_acl_pop_i1_wt_limpop_switch_to_led_out_feedback_stall_out_0,
        out_stall_out => i_acl_pop_i1_wt_limpop_switch_to_led_out_stall_out,
        out_valid_out => i_acl_pop_i1_wt_limpop_switch_to_led_out_valid_out,
        clock => clock,
        resetn => resetn
    );

    -- SE_out_i_acl_pop_i1_wt_limpop_switch_to_led(STALLENABLE,27)
    -- Valid signal propagation
    SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_V0 <= SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_wireValid;
    -- Backward Stall generation
    SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_backStall <= in_stall_in or not (SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_wireValid);
    -- Computing multiple Valid(s)
    SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_wireValid <= i_acl_pop_i1_wt_limpop_switch_to_led_out_valid_out;

    -- dupName_0_sync_out_x(GPOUT,5)@2
    out_valid_out <= SE_out_i_acl_pop_i1_wt_limpop_switch_to_led_V0;

    -- sync_out(GPOUT,21)@0
    out_stall_out <= SE_stall_entry_backStall;

END normal;
