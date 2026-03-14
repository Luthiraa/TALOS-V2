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

-- VHDL created from i_sfc_logic_c1_wt_entry_switch_to_led_c1_enter_switch_to_led13
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

entity i_sfc_logic_c1_wt_entry_switch_to_led_c1_enter_switch_to_led13 is
    port (
        in_c1_eni2_0 : in std_logic_vector(0 downto 0);  -- ufix1
        in_c1_eni2_1 : in std_logic_vector(0 downto 0);  -- ufix1
        in_c1_eni2_2 : in std_logic_vector(0 downto 0);  -- ufix1
        in_c1_eni2_3 : in std_logic_vector(0 downto 0);  -- ufix1
        in_i_valid : in std_logic_vector(0 downto 0);  -- ufix1
        out_c1_exi1_0 : out std_logic_vector(0 downto 0);  -- ufix1
        out_c1_exi1_1 : out std_logic_vector(31 downto 0);  -- ufix32
        out_o_valid : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_sfc_logic_c1_wt_entry_switch_to_led_c1_enter_switch_to_led13;

architecture normal of i_sfc_logic_c1_wt_entry_switch_to_led_c1_enter_switch_to_led13 is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led19 is
        port (
            in_data_in : in std_logic_vector(31 downto 0);  -- Fixed Point
            in_dir : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_feedback_in_3 : in std_logic_vector(31 downto 0);  -- Fixed Point
            in_feedback_valid_in_3 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_predicate : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(31 downto 0);  -- Fixed Point
            out_feedback_stall_out_3 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led15 is
        port (
            in_data_in : in std_logic_vector(7 downto 0);  -- Fixed Point
            in_dir : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_feedback_in_4 : in std_logic_vector(7 downto 0);  -- Fixed Point
            in_feedback_valid_in_4 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_predicate : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(7 downto 0);  -- Fixed Point
            out_feedback_stall_out_4 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led21 is
        port (
            in_data_in : in std_logic_vector(31 downto 0);  -- Fixed Point
            in_feedback_stall_in_3 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(31 downto 0);  -- Fixed Point
            out_feedback_out_3 : out std_logic_vector(31 downto 0);  -- Fixed Point
            out_feedback_valid_out_3 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led23 is
        port (
            in_data_in : in std_logic_vector(7 downto 0);  -- Fixed Point
            in_feedback_stall_in_4 : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_data_out : out std_logic_vector(7 downto 0);  -- Fixed Point
            out_feedback_out_4 : out std_logic_vector(7 downto 0);  -- Fixed Point
            out_feedback_valid_out_4 : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal GND_q : STD_LOGIC_VECTOR (0 downto 0);
    signal VCC_q : STD_LOGIC_VECTOR (0 downto 0);
    signal bgTrunc_i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_sel_x_b : STD_LOGIC_VECTOR (31 downto 0);
    signal i_frombool7_switch_to_led_sel_x_b : STD_LOGIC_VECTOR (7 downto 0);
    signal i_unnamed_switch_to_led18_sel_x_b : STD_LOGIC_VECTOR (31 downto 0);
    signal c_i32_0gr_q : STD_LOGIC_VECTOR (31 downto 0);
    signal c_i32_1gr_q : STD_LOGIC_VECTOR (31 downto 0);
    signal c_i8_0gr_q : STD_LOGIC_VECTOR (7 downto 0);
    signal c_i8_1gr_q : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_switch_to_led_s : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_switch_to_led_q : STD_LOGIC_VECTOR (31 downto 0);
    signal i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led_out_data_out : STD_LOGIC_VECTOR (31 downto 0);
    signal i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led_out_feedback_stall_out_3 : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led_out_data_out : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led_out_feedback_stall_out_4 : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led_out_feedback_out_3 : STD_LOGIC_VECTOR (31 downto 0);
    signal i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led_out_feedback_valid_out_3 : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led_out_feedback_out_4 : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led_out_feedback_valid_out_4 : STD_LOGIC_VECTOR (0 downto 0);
    signal i_brmerge_switch_to_led_q : STD_LOGIC_VECTOR (0 downto 0);
    signal i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_a : STD_LOGIC_VECTOR (32 downto 0);
    signal i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_b : STD_LOGIC_VECTOR (32 downto 0);
    signal i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_o : STD_LOGIC_VECTOR (32 downto 0);
    signal i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_q : STD_LOGIC_VECTOR (32 downto 0);
    signal i_frombool7_switch_to_led_vt_const_7_q : STD_LOGIC_VECTOR (6 downto 0);
    signal i_frombool7_switch_to_led_vt_join_q : STD_LOGIC_VECTOR (7 downto 0);
    signal i_frombool7_switch_to_led_vt_select_0_b : STD_LOGIC_VECTOR (0 downto 0);
    signal i_inc_switch_to_led_q : STD_LOGIC_VECTOR (31 downto 0);
    signal i_inc_switch_to_led_vt_const_31_q : STD_LOGIC_VECTOR (30 downto 0);
    signal i_inc_switch_to_led_vt_join_q : STD_LOGIC_VECTOR (31 downto 0);
    signal i_inc_switch_to_led_vt_select_0_b : STD_LOGIC_VECTOR (0 downto 0);
    signal i_tobool2_switch_to_led_qi : STD_LOGIC_VECTOR (0 downto 0);
    signal i_tobool2_switch_to_led_q : STD_LOGIC_VECTOR (0 downto 0);
    signal i_unnamed_switch_to_led18_vt_join_q : STD_LOGIC_VECTOR (31 downto 0);
    signal i_unnamed_switch_to_led18_vt_select_0_b : STD_LOGIC_VECTOR (0 downto 0);
    signal redist0_sync_in_aunroll_x_in_c1_eni2_1_1_q : STD_LOGIC_VECTOR (0 downto 0);
    signal redist1_sync_in_aunroll_x_in_c1_eni2_2_1_q : STD_LOGIC_VECTOR (0 downto 0);
    signal redist2_sync_in_aunroll_x_in_c1_eni2_3_1_q : STD_LOGIC_VECTOR (0 downto 0);
    signal redist3_sync_in_aunroll_x_in_i_valid_1_q : STD_LOGIC_VECTOR (0 downto 0);

begin


    -- VCC(CONSTANT,1)
    VCC_q <= "1";

    -- redist3_sync_in_aunroll_x_in_i_valid_1(DELAY,44)
    redist3_sync_in_aunroll_x_in_i_valid_1 : dspba_delay
    GENERIC MAP ( width => 1, depth => 1, reset_kind => "ASYNC", reset_high => '0' )
    PORT MAP ( xin => in_i_valid, xout => redist3_sync_in_aunroll_x_in_i_valid_1_q, clk => clock, aclr => resetn );

    -- i_inc_switch_to_led_vt_const_31(CONSTANT,28)
    i_inc_switch_to_led_vt_const_31_q <= "0000000000000000000000000000000";

    -- c_i32_1gr(CONSTANT,13)
    c_i32_1gr_q <= "00000000000000000000000000000001";

    -- redist0_sync_in_aunroll_x_in_c1_eni2_1_1(DELAY,41)
    redist0_sync_in_aunroll_x_in_c1_eni2_1_1 : dspba_delay
    GENERIC MAP ( width => 1, depth => 1, reset_kind => "ASYNC", reset_high => '0' )
    PORT MAP ( xin => in_c1_eni2_1, xout => redist0_sync_in_aunroll_x_in_c1_eni2_1_1_q, clk => clock, aclr => resetn );

    -- c_i8_0gr(CONSTANT,14)
    c_i8_0gr_q <= "00000000";

    -- i_frombool7_switch_to_led_vt_const_7(CONSTANT,24)
    i_frombool7_switch_to_led_vt_const_7_q <= "0000000";

    -- i_frombool7_switch_to_led_sel_x(BITSELECT,6)@1
    i_frombool7_switch_to_led_sel_x_b <= std_logic_vector(resize(unsigned(in_c1_eni2_1(0 downto 0)), 8));

    -- i_frombool7_switch_to_led_vt_select_0(BITSELECT,26)@1
    i_frombool7_switch_to_led_vt_select_0_b <= i_frombool7_switch_to_led_sel_x_b(0 downto 0);

    -- i_frombool7_switch_to_led_vt_join(BITJOIN,25)@1
    i_frombool7_switch_to_led_vt_join_q <= i_frombool7_switch_to_led_vt_const_7_q & i_frombool7_switch_to_led_vt_select_0_b;

    -- i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led(BLACKBOX,20)@1
    -- out out_feedback_out_4@20000000
    -- out out_feedback_valid_out_4@20000000
    thei_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led : i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led23
    PORT MAP (
        in_data_in => i_frombool7_switch_to_led_vt_join_q,
        in_feedback_stall_in_4 => i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led_out_feedback_stall_out_4,
        in_stall_in => GND_q,
        in_valid_in => in_i_valid,
        out_feedback_out_4 => i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led_out_feedback_out_4,
        out_feedback_valid_out_4 => i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led_out_feedback_valid_out_4,
        clock => clock,
        resetn => resetn
    );

    -- c_i8_1gr(CONSTANT,15)
    c_i8_1gr_q <= "00000001";

    -- i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led(BLACKBOX,18)@1
    -- out out_feedback_stall_out_4@20000000
    thei_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led : i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led15
    PORT MAP (
        in_data_in => c_i8_1gr_q,
        in_dir => in_c1_eni2_3,
        in_feedback_in_4 => i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led_out_feedback_out_4,
        in_feedback_valid_in_4 => i_acl_push_i8_prev_button_n_switch_to_led_4_na_addr_0_push4_switch_to_led_out_feedback_valid_out_4,
        in_predicate => GND_q,
        in_stall_in => GND_q,
        in_valid_in => in_i_valid,
        out_data_out => i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led_out_data_out,
        out_feedback_stall_out_4 => i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led_out_feedback_stall_out_4,
        clock => clock,
        resetn => resetn
    );

    -- i_tobool2_switch_to_led(LOGICAL,31)@1 + 1
    i_tobool2_switch_to_led_qi <= "1" WHEN i_acl_pop_i8_prev_button_n_switch_to_led_4_na_addr_0_pop4_switch_to_led_out_data_out = c_i8_0gr_q ELSE "0";
    i_tobool2_switch_to_led_delay : dspba_delay
    GENERIC MAP ( width => 1, depth => 1, reset_kind => "ASYNC", reset_high => '0' )
    PORT MAP ( xin => i_tobool2_switch_to_led_qi, xout => i_tobool2_switch_to_led_q, clk => clock, aclr => resetn );

    -- i_brmerge_switch_to_led(LOGICAL,21)@2
    i_brmerge_switch_to_led_q <= i_tobool2_switch_to_led_q or redist0_sync_in_aunroll_x_in_c1_eni2_1_1_q;

    -- i_unnamed_switch_to_led18_sel_x(BITSELECT,7)@2
    i_unnamed_switch_to_led18_sel_x_b <= std_logic_vector(resize(unsigned(i_brmerge_switch_to_led_q(0 downto 0)), 32));

    -- i_unnamed_switch_to_led18_vt_select_0(BITSELECT,35)@2
    i_unnamed_switch_to_led18_vt_select_0_b <= i_unnamed_switch_to_led18_sel_x_b(0 downto 0);

    -- i_unnamed_switch_to_led18_vt_join(BITJOIN,34)@2
    i_unnamed_switch_to_led18_vt_join_q <= i_inc_switch_to_led_vt_const_31_q & i_unnamed_switch_to_led18_vt_select_0_b;

    -- i_inc_switch_to_led(LOGICAL,27)@2
    i_inc_switch_to_led_q <= i_unnamed_switch_to_led18_vt_join_q xor c_i32_1gr_q;

    -- i_inc_switch_to_led_vt_select_0(BITSELECT,30)@2
    i_inc_switch_to_led_vt_select_0_b <= i_inc_switch_to_led_q(0 downto 0);

    -- i_inc_switch_to_led_vt_join(BITJOIN,29)@2
    i_inc_switch_to_led_vt_join_q <= i_inc_switch_to_led_vt_const_31_q & i_inc_switch_to_led_vt_select_0_b;

    -- i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led(BLACKBOX,19)@2
    -- out out_feedback_out_3@20000000
    -- out out_feedback_valid_out_3@20000000
    thei_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led : i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led21
    PORT MAP (
        in_data_in => i_acl_switch_to_led_q,
        in_feedback_stall_in_3 => i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led_out_feedback_stall_out_3,
        in_stall_in => GND_q,
        in_valid_in => redist3_sync_in_aunroll_x_in_i_valid_1_q,
        out_feedback_out_3 => i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led_out_feedback_out_3,
        out_feedback_valid_out_3 => i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led_out_feedback_valid_out_3,
        clock => clock,
        resetn => resetn
    );

    -- redist2_sync_in_aunroll_x_in_c1_eni2_3_1(DELAY,43)
    redist2_sync_in_aunroll_x_in_c1_eni2_3_1 : dspba_delay
    GENERIC MAP ( width => 1, depth => 1, reset_kind => "ASYNC", reset_high => '0' )
    PORT MAP ( xin => in_c1_eni2_3, xout => redist2_sync_in_aunroll_x_in_c1_eni2_3_1_q, clk => clock, aclr => resetn );

    -- i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led(BLACKBOX,17)@2
    -- out out_feedback_stall_out_3@20000000
    thei_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led : i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led19
    PORT MAP (
        in_data_in => c_i32_0gr_q,
        in_dir => redist2_sync_in_aunroll_x_in_c1_eni2_3_1_q,
        in_feedback_in_3 => i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led_out_feedback_out_3,
        in_feedback_valid_in_3 => i_acl_push_i32_count_switch_to_led_4ia_addr_0_push3_switch_to_led_out_feedback_valid_out_3,
        in_predicate => GND_q,
        in_stall_in => GND_q,
        in_valid_in => redist3_sync_in_aunroll_x_in_i_valid_1_q,
        out_data_out => i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led_out_data_out,
        out_feedback_stall_out_3 => i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led_out_feedback_stall_out_3,
        clock => clock,
        resetn => resetn
    );

    -- i_count_switch_to_led_4ia_addr_0_inc_switch_to_led(ADD,22)@2
    i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_a <= STD_LOGIC_VECTOR("0" & i_acl_pop_i32_count_switch_to_led_4ia_addr_0_pop3_switch_to_led_out_data_out);
    i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_b <= STD_LOGIC_VECTOR("0" & i_inc_switch_to_led_vt_join_q);
    i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_o <= STD_LOGIC_VECTOR(UNSIGNED(i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_a) + UNSIGNED(i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_b));
    i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_q <= i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_o(32 downto 0);

    -- bgTrunc_i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_sel_x(BITSELECT,2)@2
    bgTrunc_i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_sel_x_b <= i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_q(31 downto 0);

    -- c_i32_0gr(CONSTANT,12)
    c_i32_0gr_q <= "00000000000000000000000000000000";

    -- redist1_sync_in_aunroll_x_in_c1_eni2_2_1(DELAY,42)
    redist1_sync_in_aunroll_x_in_c1_eni2_2_1 : dspba_delay
    GENERIC MAP ( width => 1, depth => 1, reset_kind => "ASYNC", reset_high => '0' )
    PORT MAP ( xin => in_c1_eni2_2, xout => redist1_sync_in_aunroll_x_in_c1_eni2_2_1_q, clk => clock, aclr => resetn );

    -- i_acl_switch_to_led(MUX,16)@2
    i_acl_switch_to_led_s <= redist1_sync_in_aunroll_x_in_c1_eni2_2_1_q;
    i_acl_switch_to_led_combproc: PROCESS (i_acl_switch_to_led_s, c_i32_0gr_q, bgTrunc_i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_sel_x_b)
    BEGIN
        CASE (i_acl_switch_to_led_s) IS
            WHEN "0" => i_acl_switch_to_led_q <= c_i32_0gr_q;
            WHEN "1" => i_acl_switch_to_led_q <= bgTrunc_i_count_switch_to_led_4ia_addr_0_inc_switch_to_led_sel_x_b;
            WHEN OTHERS => i_acl_switch_to_led_q <= (others => '0');
        END CASE;
    END PROCESS;

    -- GND(CONSTANT,0)
    GND_q <= "0";

    -- sync_out_aunroll_x(GPOUT,9)@2
    out_c1_exi1_0 <= GND_q;
    out_c1_exi1_1 <= i_acl_switch_to_led_q;
    out_o_valid <= redist3_sync_in_aunroll_x_in_i_valid_1_q;

END normal;
