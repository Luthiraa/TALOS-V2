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

-- VHDL created from i_sfc_logic_c0_wt_entry_switch_to_led_c0_enter_switch_to_led4
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

entity i_sfc_logic_c0_wt_entry_switch_to_led_c0_enter_switch_to_led4 is
    port (
        out_c0_exi1_0 : out std_logic_vector(0 downto 0);  -- ufix1
        out_c0_exi1_1 : out std_logic_vector(0 downto 0);  -- ufix1
        out_o_valid : out std_logic_vector(0 downto 0);  -- ufix1
        out_aclp_to_limiter_i_acl_pipeline_keep_going_switch_to_led_exiting_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        out_aclp_to_limiter_i_acl_pipeline_keep_going_switch_to_led_exiting_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_pipeline_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_pipeline_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_enable : in std_logic_vector(0 downto 0);  -- ufix1
        in_i_valid : in std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_sfc_logic_c0_wt_entry_switch_to_led_c0_enter_switch_to_led4;

architecture normal of i_sfc_logic_c0_wt_entry_switch_to_led_c0_enter_switch_to_led4 is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component i_acl_pipeline_keep_going_switch_to_led6 is
        port (
            in_data_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_initeration_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_initeration_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_not_exitcond_in : in std_logic_vector(7 downto 0);  -- Fixed Point
            in_not_exitcond_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_pipeline_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_exiting_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_exiting_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_initeration_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_not_exitcond_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_pipeline_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component i_acl_push_i1_notexitcond_switch_to_led8 is
        port (
            in_data_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_feedback_stall_in_2 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_feedback_out_2 : out std_logic_vector(7 downto 0);  -- Fixed Point
            out_feedback_valid_out_2 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal GND_q : STD_LOGIC_VECTOR (0 downto 0);
    signal VCC_q : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_out_exiting_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_out_exiting_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_out_not_exitcond_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led_out_pipeline_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_notexitcond_switch_to_led_out_data_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i1_notexitcond_switch_to_led_out_feedback_out_2 : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_push_i1_notexitcond_switch_to_led_out_feedback_valid_out_2 : STD_LOGIC_VECTOR (0 downto 0);
    signal dupName_0_enable_stall_connector_x_not_enable_q : STD_LOGIC_VECTOR (0 downto 0);

begin


    -- dupName_0_enable_stall_connector_x_not_enable(LOGICAL,16)
    dupName_0_enable_stall_connector_x_not_enable_q <= STD_LOGIC_VECTOR(not (in_enable));

    -- i_acl_pipeline_keep_going_switch_to_led(BLACKBOX,11)@1
    -- out out_exiting_stall_out@20000000
    -- out out_exiting_valid_out@20000000
    -- out out_initeration_stall_out@20000000
    -- out out_not_exitcond_stall_out@20000000
    -- out out_pipeline_valid_out@20000000
    thei_acl_pipeline_keep_going_switch_to_led : i_acl_pipeline_keep_going_switch_to_led6
    PORT MAP (
        in_data_in => VCC_q,
        in_initeration_in => GND_q,
        in_initeration_valid_in => GND_q,
        in_not_exitcond_in => i_acl_push_i1_notexitcond_switch_to_led_out_feedback_out_2,
        in_not_exitcond_valid_in => i_acl_push_i1_notexitcond_switch_to_led_out_feedback_valid_out_2,
        in_pipeline_stall_in => in_pipeline_stall_in,
        in_stall_in => dupName_0_enable_stall_connector_x_not_enable_q,
        in_valid_in => in_i_valid,
        out_exiting_stall_out => i_acl_pipeline_keep_going_switch_to_led_out_exiting_stall_out,
        out_exiting_valid_out => i_acl_pipeline_keep_going_switch_to_led_out_exiting_valid_out,
        out_not_exitcond_stall_out => i_acl_pipeline_keep_going_switch_to_led_out_not_exitcond_stall_out,
        out_pipeline_valid_out => i_acl_pipeline_keep_going_switch_to_led_out_pipeline_valid_out,
        clock => clock,
        resetn => resetn
    );

    -- VCC(CONSTANT,1)
    VCC_q <= "1";

    -- i_acl_push_i1_notexitcond_switch_to_led(BLACKBOX,12)@1
    -- out out_feedback_out_2@20000000
    -- out out_feedback_valid_out_2@20000000
    thei_acl_push_i1_notexitcond_switch_to_led : i_acl_push_i1_notexitcond_switch_to_led8
    PORT MAP (
        in_data_in => VCC_q,
        in_feedback_stall_in_2 => i_acl_pipeline_keep_going_switch_to_led_out_not_exitcond_stall_out,
        in_stall_in => dupName_0_enable_stall_connector_x_not_enable_q,
        in_valid_in => in_i_valid,
        out_data_out => i_acl_push_i1_notexitcond_switch_to_led_out_data_out,
        out_feedback_out_2 => i_acl_push_i1_notexitcond_switch_to_led_out_feedback_out_2,
        out_feedback_valid_out_2 => i_acl_push_i1_notexitcond_switch_to_led_out_feedback_valid_out_2,
        clock => clock,
        resetn => resetn
    );

    -- GND(CONSTANT,0)
    GND_q <= "0";

    -- sync_out_aunroll_x(GPOUT,5)@1
    out_c0_exi1_0 <= GND_q;
    out_c0_exi1_1 <= i_acl_push_i1_notexitcond_switch_to_led_out_data_out;
    out_o_valid <= in_i_valid;

    -- ext_sig_sync_out(GPOUT,10)
    out_aclp_to_limiter_i_acl_pipeline_keep_going_switch_to_led_exiting_valid_out <= i_acl_pipeline_keep_going_switch_to_led_out_exiting_valid_out;
    out_aclp_to_limiter_i_acl_pipeline_keep_going_switch_to_led_exiting_stall_out <= i_acl_pipeline_keep_going_switch_to_led_out_exiting_stall_out;

    -- pipeline_valid_out_sync(GPOUT,14)
    out_pipeline_valid_out <= i_acl_pipeline_keep_going_switch_to_led_out_pipeline_valid_out;

END normal;
