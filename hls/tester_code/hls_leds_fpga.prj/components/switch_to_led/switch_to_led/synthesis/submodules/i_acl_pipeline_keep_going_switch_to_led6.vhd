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

-- VHDL created from i_acl_pipeline_keep_going_switch_to_led6
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

entity i_acl_pipeline_keep_going_switch_to_led6 is
    port (
        out_exiting_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_data_in : in std_logic_vector(0 downto 0);  -- ufix1
        in_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_data_out : out std_logic_vector(0 downto 0);  -- ufix1
        out_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        out_exiting_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_initeration_in : in std_logic_vector(0 downto 0);  -- ufix1
        in_initeration_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        in_not_exitcond_in : in std_logic_vector(7 downto 0);  -- ufix8
        in_not_exitcond_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        in_pipeline_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_initeration_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        out_not_exitcond_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        out_pipeline_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_acl_pipeline_keep_going_switch_to_led6;

architecture normal of i_acl_pipeline_keep_going_switch_to_led6 is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component acl_pipeline is
        generic (
            FIFO_DEPTH : INTEGER;
            ENABLED : INTEGER := 1;
            STYLE : STRING := "NON_SPECULATIVE"
        );
        port (
            data_in : in std_logic;
            initeration_in : in std_logic;
            initeration_valid_in : in std_logic;
            not_exitcond_in : in std_logic;
            not_exitcond_valid_in : in std_logic;
            pipeline_stall_in : in std_logic;
            stall_in : in std_logic;
            valid_in : in std_logic;
            data_out : out std_logic;
            exiting_valid_out : out std_logic;
            initeration_stall_out : out std_logic;
            not_exitcond_stall_out : out std_logic;
            pipeline_valid_out : out std_logic;
            stall_out : out std_logic;
            valid_out : out std_logic;
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component acl_dspba_buffer is
        generic (
            WIDTH : INTEGER := 1
        );
        port (
            buffer_in : in std_logic;
            buffer_out : out std_logic
        );
    end component;


    signal i_acl_pipeline_keep_going_switch_to_led7_data_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_data_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_initeration_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_initeration_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_initeration_valid_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_initeration_valid_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_in : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_valid_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_valid_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_pipeline_stall_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_pipeline_stall_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_stall_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_stall_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_valid_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_valid_in_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_data_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_data_out_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_exiting_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_exiting_valid_out_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_initeration_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_initeration_stall_out_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_stall_out_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_pipeline_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_pipeline_valid_out_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_stall_out_bitsignaltemp : std_logic;
    signal i_acl_pipeline_keep_going_switch_to_led7_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_pipeline_keep_going_switch_to_led7_valid_out_bitsignaltemp : std_logic;
    signal passthru_buffer_in : STD_LOGIC_VECTOR (0 downto 0);
    signal passthru_buffer_in_bitsignaltemp : std_logic;
    signal passthru_buffer_out : STD_LOGIC_VECTOR (0 downto 0);
    signal passthru_buffer_out_bitsignaltemp : std_logic;

begin


    -- i_acl_pipeline_keep_going_switch_to_led7(EXTIFACE,5)@1
    i_acl_pipeline_keep_going_switch_to_led7_data_in <= in_data_in;
    i_acl_pipeline_keep_going_switch_to_led7_initeration_in <= in_initeration_in;
    i_acl_pipeline_keep_going_switch_to_led7_initeration_valid_in <= in_initeration_valid_in;
    i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_in <= in_not_exitcond_in;
    i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_valid_in <= in_not_exitcond_valid_in;
    i_acl_pipeline_keep_going_switch_to_led7_pipeline_stall_in <= in_pipeline_stall_in;
    i_acl_pipeline_keep_going_switch_to_led7_stall_in <= in_stall_in;
    i_acl_pipeline_keep_going_switch_to_led7_valid_in <= in_valid_in;
    i_acl_pipeline_keep_going_switch_to_led7_data_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_data_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_initeration_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_initeration_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_initeration_valid_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_initeration_valid_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_valid_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_valid_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_pipeline_stall_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_pipeline_stall_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_stall_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_stall_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_valid_in_bitsignaltemp <= i_acl_pipeline_keep_going_switch_to_led7_valid_in(0);
    i_acl_pipeline_keep_going_switch_to_led7_data_out(0) <= i_acl_pipeline_keep_going_switch_to_led7_data_out_bitsignaltemp;
    i_acl_pipeline_keep_going_switch_to_led7_exiting_valid_out(0) <= i_acl_pipeline_keep_going_switch_to_led7_exiting_valid_out_bitsignaltemp;
    i_acl_pipeline_keep_going_switch_to_led7_initeration_stall_out(0) <= i_acl_pipeline_keep_going_switch_to_led7_initeration_stall_out_bitsignaltemp;
    i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_stall_out(0) <= i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_stall_out_bitsignaltemp;
    i_acl_pipeline_keep_going_switch_to_led7_pipeline_valid_out(0) <= i_acl_pipeline_keep_going_switch_to_led7_pipeline_valid_out_bitsignaltemp;
    i_acl_pipeline_keep_going_switch_to_led7_stall_out(0) <= i_acl_pipeline_keep_going_switch_to_led7_stall_out_bitsignaltemp;
    i_acl_pipeline_keep_going_switch_to_led7_valid_out(0) <= i_acl_pipeline_keep_going_switch_to_led7_valid_out_bitsignaltemp;
    thei_acl_pipeline_keep_going_switch_to_led7 : acl_pipeline
    GENERIC MAP (
        FIFO_DEPTH => 0,
        ENABLED => 1,
        STYLE => "NON_SPECULATIVE"
    )
    PORT MAP (
        data_in => i_acl_pipeline_keep_going_switch_to_led7_data_in_bitsignaltemp,
        initeration_in => i_acl_pipeline_keep_going_switch_to_led7_initeration_in_bitsignaltemp,
        initeration_valid_in => i_acl_pipeline_keep_going_switch_to_led7_initeration_valid_in_bitsignaltemp,
        not_exitcond_in => i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_in_bitsignaltemp,
        not_exitcond_valid_in => i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_valid_in_bitsignaltemp,
        pipeline_stall_in => i_acl_pipeline_keep_going_switch_to_led7_pipeline_stall_in_bitsignaltemp,
        stall_in => i_acl_pipeline_keep_going_switch_to_led7_stall_in_bitsignaltemp,
        valid_in => i_acl_pipeline_keep_going_switch_to_led7_valid_in_bitsignaltemp,
        data_out => i_acl_pipeline_keep_going_switch_to_led7_data_out_bitsignaltemp,
        exiting_valid_out => i_acl_pipeline_keep_going_switch_to_led7_exiting_valid_out_bitsignaltemp,
        initeration_stall_out => i_acl_pipeline_keep_going_switch_to_led7_initeration_stall_out_bitsignaltemp,
        not_exitcond_stall_out => i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_stall_out_bitsignaltemp,
        pipeline_valid_out => i_acl_pipeline_keep_going_switch_to_led7_pipeline_valid_out_bitsignaltemp,
        stall_out => i_acl_pipeline_keep_going_switch_to_led7_stall_out_bitsignaltemp,
        valid_out => i_acl_pipeline_keep_going_switch_to_led7_valid_out_bitsignaltemp,
        clock => clock,
        resetn => resetn
    );

    -- dupName_0_regfree_osync_x(GPOUT,2)
    out_exiting_valid_out <= i_acl_pipeline_keep_going_switch_to_led7_exiting_valid_out;

    -- dupName_0_sync_out_x(GPOUT,4)@1
    out_data_out <= i_acl_pipeline_keep_going_switch_to_led7_data_out;
    out_valid_out <= i_acl_pipeline_keep_going_switch_to_led7_valid_out;

    -- passthru(EXTIFACE,6)@20000000
    passthru_buffer_in <= in_pipeline_stall_in;
    passthru_buffer_in_bitsignaltemp <= passthru_buffer_in(0);
    passthru_buffer_out(0) <= passthru_buffer_out_bitsignaltemp;
    thepassthru : acl_dspba_buffer
    GENERIC MAP (
        WIDTH => 1
    )
    PORT MAP (
        buffer_in => passthru_buffer_in_bitsignaltemp,
        buffer_out => passthru_buffer_out_bitsignaltemp
    );

    -- regfree_osync(GPOUT,7)
    out_exiting_stall_out <= passthru_buffer_out;

    -- sync_out(GPOUT,9)@1
    out_stall_out <= i_acl_pipeline_keep_going_switch_to_led7_stall_out;

    -- unsched_sync_out(GPOUT,11)
    out_initeration_stall_out <= i_acl_pipeline_keep_going_switch_to_led7_initeration_stall_out;
    out_not_exitcond_stall_out <= i_acl_pipeline_keep_going_switch_to_led7_not_exitcond_stall_out;
    out_pipeline_valid_out <= i_acl_pipeline_keep_going_switch_to_led7_pipeline_valid_out;

END normal;
