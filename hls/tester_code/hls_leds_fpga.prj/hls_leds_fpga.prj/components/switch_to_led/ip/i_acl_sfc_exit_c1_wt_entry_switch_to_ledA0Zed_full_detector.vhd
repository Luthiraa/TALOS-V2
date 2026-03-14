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

-- VHDL created from i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector
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

entity i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector is
    port (
        in_dec_pipelined_thread : in std_logic_vector(0 downto 0);  -- ufix1
        in_decrement : in std_logic_vector(0 downto 0);  -- ufix1
        in_inc_pipelined_thread : in std_logic_vector(0 downto 0);  -- ufix1
        in_increment : in std_logic_vector(0 downto 0);  -- ufix1
        out_full : out std_logic_vector(0 downto 0);  -- ufix1
        out_throttle : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector;

architecture normal of i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component acl_full_detector is
        generic (
            ALWAYS_THROTTLE : INTEGER;
            SCHEDULEII : INTEGER;
            WIDTH : INTEGER
        );
        port (
            dec_pipelined_thread : in std_logic;
            decrement : in std_logic;
            inc_pipelined_thread : in std_logic;
            increment : in std_logic;
            full : out std_logic;
            throttle : out std_logic;
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_dec_pipelined_thread : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_dec_pipelined_thread_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_decrement : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_decrement_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_inc_pipelined_thread : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_inc_pipelined_thread_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_increment : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_increment_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_full : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_full_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_throttle : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_throttle_bitsignaltemp : std_logic;

begin


    -- i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector(EXTIFACE,2)
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_dec_pipelined_thread <= in_dec_pipelined_thread;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_decrement <= in_decrement;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_inc_pipelined_thread <= in_inc_pipelined_thread;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_increment <= in_increment;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_dec_pipelined_thread_bitsignaltemp <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_dec_pipelined_thread(0);
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_decrement_bitsignaltemp <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_decrement(0);
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_inc_pipelined_thread_bitsignaltemp <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_inc_pipelined_thread(0);
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_increment_bitsignaltemp <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_increment(0);
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_full(0) <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_full_bitsignaltemp;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_throttle(0) <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_throttle_bitsignaltemp;
    thei_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector : acl_full_detector
    GENERIC MAP (
        ALWAYS_THROTTLE => 0,
        SCHEDULEII => 1,
        WIDTH => 4
    )
    PORT MAP (
        dec_pipelined_thread => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_dec_pipelined_thread_bitsignaltemp,
        decrement => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_decrement_bitsignaltemp,
        inc_pipelined_thread => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_inc_pipelined_thread_bitsignaltemp,
        increment => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_increment_bitsignaltemp,
        full => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_full_bitsignaltemp,
        throttle => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_throttle_bitsignaltemp,
        clock => clock,
        resetn => resetn
    );

    -- sync_out(GPOUT,4)@20000000
    out_full <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_full;
    out_throttle <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led_full_detector_throttle;

END normal;
