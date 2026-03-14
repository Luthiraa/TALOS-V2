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

-- VHDL created from i_iord_bl_do_unnamed_switch_to_led1_switch_to_led12
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

entity i_iord_bl_do_unnamed_switch_to_led1_switch_to_led12 is
    port (
        out_o_data_0 : out std_logic_vector(0 downto 0);  -- ufix1
        out_o_data_1 : out std_logic_vector(0 downto 0);  -- ufix1
        out_o_valid : out std_logic_vector(0 downto 0);  -- ufix1
        in_iord_bl_do_i_fifovalid : in std_logic_vector(0 downto 0);  -- ufix1
        in_i_valid : in std_logic_vector(0 downto 0);  -- ufix1
        in_iord_bl_do_i_fifodata : in std_logic_vector(15 downto 0);  -- ufix16
        out_iord_bl_do_o_fifoready : out std_logic_vector(0 downto 0);  -- ufix1
        in_i_stall : in std_logic_vector(0 downto 0);  -- ufix1
        out_o_stall : out std_logic_vector(0 downto 0);  -- ufix1
        clock : in std_logic;
        resetn : in std_logic
    );
end i_iord_bl_do_unnamed_switch_to_led1_switch_to_led12;

architecture normal of i_iord_bl_do_unnamed_switch_to_led1_switch_to_led12 is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component st_read is
        generic (
            DATA_WIDTH : INTEGER := 16;
            NON_BLOCKING : INTEGER := 0
        );
        port (
            i_fifodata : in std_logic_vector(15 downto 0);
            i_fifoendofpacket : in std_logic;
            i_fifosize : in std_logic_vector(31 downto 0);
            i_fifostartofpacket : in std_logic;
            i_fifovalid : in std_logic;
            i_init : in std_logic;
            i_predicate : in std_logic;
            i_stall : in std_logic;
            i_valid : in std_logic;
            o_data : out std_logic_vector(15 downto 0);
            o_fifoready : out std_logic;
            o_stall : out std_logic;
            o_valid : out std_logic;
            profile_total_fifo_size_incr : out std_logic_vector(31 downto 0);
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal GND_q : STD_LOGIC_VECTOR (0 downto 0);
    signal dupName_0_adapt_scalar_trunc_x_in : STD_LOGIC_VECTOR (0 downto 0);
    signal dupName_0_adapt_scalar_trunc_x_q : STD_LOGIC_VECTOR (0 downto 0);
    signal dupName_0_ip_dsdk_adapt_bitselect_x_b : STD_LOGIC_VECTOR (0 downto 0);
    signal adapt_scalar_trunc_in : STD_LOGIC_VECTOR (0 downto 0);
    signal adapt_scalar_trunc_q : STD_LOGIC_VECTOR (0 downto 0);
    signal c32_0_q : STD_LOGIC_VECTOR (31 downto 0);
    signal iord_i_fifodata : STD_LOGIC_VECTOR (15 downto 0);
    signal iord_i_fifoendofpacket : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_i_fifoendofpacket_bitsignaltemp : std_logic;
    signal iord_i_fifosize : STD_LOGIC_VECTOR (31 downto 0);
    signal iord_i_fifostartofpacket : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_i_fifostartofpacket_bitsignaltemp : std_logic;
    signal iord_i_fifovalid : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_i_fifovalid_bitsignaltemp : std_logic;
    signal iord_i_init : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_i_init_bitsignaltemp : std_logic;
    signal iord_i_predicate : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_i_predicate_bitsignaltemp : std_logic;
    signal iord_i_stall : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_i_stall_bitsignaltemp : std_logic;
    signal iord_i_valid : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_i_valid_bitsignaltemp : std_logic;
    signal iord_o_data : STD_LOGIC_VECTOR (15 downto 0);
    signal iord_o_fifoready : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_o_fifoready_bitsignaltemp : std_logic;
    signal iord_o_stall : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_o_stall_bitsignaltemp : std_logic;
    signal iord_o_valid : STD_LOGIC_VECTOR (0 downto 0);
    signal iord_o_valid_bitsignaltemp : std_logic;
    signal iord_profile_total_fifo_size_incr : STD_LOGIC_VECTOR (31 downto 0);
    signal ip_dsdk_adapt_bitselect_b : STD_LOGIC_VECTOR (0 downto 0);

begin


    -- c32_0(CONSTANT,9)
    c32_0_q <= "00000000000000000000000000000000";

    -- GND(CONSTANT,0)
    GND_q <= "0";

    -- iord(EXTIFACE,12)
    iord_i_fifodata <= in_iord_bl_do_i_fifodata;
    iord_i_fifoendofpacket <= GND_q;
    iord_i_fifosize <= c32_0_q;
    iord_i_fifostartofpacket <= GND_q;
    iord_i_fifovalid <= in_iord_bl_do_i_fifovalid;
    iord_i_init <= GND_q;
    iord_i_predicate <= GND_q;
    iord_i_stall <= in_i_stall;
    iord_i_valid <= in_i_valid;
    iord_i_fifoendofpacket_bitsignaltemp <= iord_i_fifoendofpacket(0);
    iord_i_fifostartofpacket_bitsignaltemp <= iord_i_fifostartofpacket(0);
    iord_i_fifovalid_bitsignaltemp <= iord_i_fifovalid(0);
    iord_i_init_bitsignaltemp <= iord_i_init(0);
    iord_i_predicate_bitsignaltemp <= iord_i_predicate(0);
    iord_i_stall_bitsignaltemp <= iord_i_stall(0);
    iord_i_valid_bitsignaltemp <= iord_i_valid(0);
    iord_o_fifoready(0) <= iord_o_fifoready_bitsignaltemp;
    iord_o_stall(0) <= iord_o_stall_bitsignaltemp;
    iord_o_valid(0) <= iord_o_valid_bitsignaltemp;
    theiord : st_read
    GENERIC MAP (
        DATA_WIDTH => 16,
        NON_BLOCKING => 0
    )
    PORT MAP (
        i_fifodata => in_iord_bl_do_i_fifodata,
        i_fifoendofpacket => iord_i_fifoendofpacket_bitsignaltemp,
        i_fifosize => c32_0_q,
        i_fifostartofpacket => iord_i_fifostartofpacket_bitsignaltemp,
        i_fifovalid => iord_i_fifovalid_bitsignaltemp,
        i_init => iord_i_init_bitsignaltemp,
        i_predicate => iord_i_predicate_bitsignaltemp,
        i_stall => iord_i_stall_bitsignaltemp,
        i_valid => iord_i_valid_bitsignaltemp,
        o_data => iord_o_data,
        o_fifoready => iord_o_fifoready_bitsignaltemp,
        o_stall => iord_o_stall_bitsignaltemp,
        o_valid => iord_o_valid_bitsignaltemp,
        clock => clock,
        resetn => resetn
    );

    -- dupName_0_ip_dsdk_adapt_bitselect_x(BITSELECT,4)
    dupName_0_ip_dsdk_adapt_bitselect_x_b <= iord_o_data(8 downto 8);

    -- dupName_0_adapt_scalar_trunc_x(ROUND,3)
    dupName_0_adapt_scalar_trunc_x_in <= dupName_0_ip_dsdk_adapt_bitselect_x_b;
    dupName_0_adapt_scalar_trunc_x_q <= dupName_0_adapt_scalar_trunc_x_in(0 downto 0);

    -- ip_dsdk_adapt_bitselect(BITSELECT,13)
    ip_dsdk_adapt_bitselect_b <= iord_o_data(0 downto 0);

    -- adapt_scalar_trunc(ROUND,7)
    adapt_scalar_trunc_in <= ip_dsdk_adapt_bitselect_b;
    adapt_scalar_trunc_q <= adapt_scalar_trunc_in(0 downto 0);

    -- dupName_0_sync_out_aunroll_x(GPOUT,2)@1
    out_o_data_0 <= adapt_scalar_trunc_q;
    out_o_data_1 <= dupName_0_adapt_scalar_trunc_x_q;
    out_o_valid <= iord_o_valid;

    -- regfree_osync(GPOUT,15)
    out_iord_bl_do_o_fifoready <= iord_o_fifoready;

    -- sync_out(GPOUT,17)@20000000
    out_o_stall <= iord_o_stall;

END normal;
