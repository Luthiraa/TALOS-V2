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

-- VHDL created from i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo
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

entity i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo is
    port (
        in_data_in_0 : in std_logic_vector(0 downto 0);  -- ufix1
        in_data_in_1 : in std_logic_vector(31 downto 0);  -- ufix32
        in_valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_data_out_0 : out std_logic_vector(0 downto 0);  -- ufix1
        out_data_out_1 : out std_logic_vector(31 downto 0);  -- ufix32
        out_valid_out : out std_logic_vector(0 downto 0);  -- ufix1
        in_stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        out_stall_out : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo;

architecture normal of i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led27_data_fifo is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component acl_data_fifo is
        generic (
            DEPTH : INTEGER;
            ALLOW_FULL_WRITE : INTEGER := 1;
            DATA_WIDTH : INTEGER := 64;
            IMPL : STRING := "ram"
        );
        port (
            data_in : in std_logic_vector(63 downto 0);
            stall_in : in std_logic;
            valid_in : in std_logic;
            data_out : out std_logic_vector(63 downto 0);
            stall_out : out std_logic;
            valid_out : out std_logic;
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal dupName_0_ip_dsdk_adapt_bitselect_x_b : STD_LOGIC_VECTOR (31 downto 0);
    signal adapt_scalar_trunc_in : STD_LOGIC_VECTOR (0 downto 0);
    signal adapt_scalar_trunc_q : STD_LOGIC_VECTOR (0 downto 0);
    signal c_i24_0gr_q : STD_LOGIC_VECTOR (23 downto 0);
    signal c_i7_0gr_q : STD_LOGIC_VECTOR (6 downto 0);
    signal dsdk_ip_adapt_bitjoin_q : STD_LOGIC_VECTOR (63 downto 0);
    signal element_extension_q : STD_LOGIC_VECTOR (7 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_data_in : STD_LOGIC_VECTOR (63 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_in_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_in : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_in_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_data_out : STD_LOGIC_VECTOR (63 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_out_bitsignaltemp : std_logic;
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_out : STD_LOGIC_VECTOR (0 downto 0);
    signal i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_out_bitsignaltemp : std_logic;
    signal ip_dsdk_adapt_bitselect_b : STD_LOGIC_VECTOR (0 downto 0);
    signal ip_dsdk_adapt_cast_b : STD_LOGIC_VECTOR (31 downto 0);

begin


    -- c_i24_0gr(CONSTANT,6)
    c_i24_0gr_q <= "000000000000000000000000";

    -- c_i7_0gr(CONSTANT,7)
    c_i7_0gr_q <= "0000000";

    -- element_extension(BITJOIN,9)
    element_extension_q <= c_i7_0gr_q & in_data_in_0;

    -- dsdk_ip_adapt_bitjoin(BITJOIN,8)
    dsdk_ip_adapt_bitjoin_q <= in_data_in_1 & c_i24_0gr_q & element_extension_q;

    -- i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28(EXTIFACE,10)
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_data_in <= dsdk_ip_adapt_bitjoin_q;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_in <= in_stall_in;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_in <= in_valid_in;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_in_bitsignaltemp <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_in(0);
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_in_bitsignaltemp <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_in(0);
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_out(0) <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_out_bitsignaltemp;
    i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_out(0) <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_out_bitsignaltemp;
    thei_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28 : acl_data_fifo
    GENERIC MAP (
        DEPTH => 8,
        ALLOW_FULL_WRITE => 1,
        DATA_WIDTH => 64,
        IMPL => "ram"
    )
    PORT MAP (
        data_in => dsdk_ip_adapt_bitjoin_q,
        stall_in => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_in_bitsignaltemp,
        valid_in => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_in_bitsignaltemp,
        data_out => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_data_out,
        stall_out => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_out_bitsignaltemp,
        valid_out => i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_out_bitsignaltemp,
        clock => clock,
        resetn => resetn
    );

    -- dupName_0_ip_dsdk_adapt_bitselect_x(BITSELECT,4)
    dupName_0_ip_dsdk_adapt_bitselect_x_b <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_data_out(63 downto 32);

    -- ip_dsdk_adapt_cast(BITSELECT,12)
    ip_dsdk_adapt_cast_b <= dupName_0_ip_dsdk_adapt_bitselect_x_b(31 downto 0);

    -- ip_dsdk_adapt_bitselect(BITSELECT,11)
    ip_dsdk_adapt_bitselect_b <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_data_out(0 downto 0);

    -- adapt_scalar_trunc(ROUND,5)
    adapt_scalar_trunc_in <= ip_dsdk_adapt_bitselect_b;
    adapt_scalar_trunc_q <= adapt_scalar_trunc_in(0 downto 0);

    -- dupName_0_sync_out_aunroll_x(GPOUT,3)@20000003
    out_data_out_0 <= adapt_scalar_trunc_q;
    out_data_out_1 <= ip_dsdk_adapt_cast_b;
    out_valid_out <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_valid_out;

    -- sync_out(GPOUT,14)@20000000
    out_stall_out <= i_acl_sfc_exit_c1_wt_entry_switch_to_led_c1_exit_switch_to_led28_stall_out;

END normal;
