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

-- VHDL created from switch_to_led_function_wrapper
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

entity switch_to_led_function_wrapper is
    port (
        avst_iord_bl_do_data : in std_logic_vector(15 downto 0);  -- ufix16
        avst_iord_bl_do_valid : in std_logic_vector(0 downto 0);  -- ufix1
        avst_iowr_bl_return_almostfull : in std_logic_vector(0 downto 0);  -- ufix1
        avst_iowr_bl_return_ready : in std_logic_vector(0 downto 0);  -- ufix1
        button_n : in std_logic_vector(0 downto 0);  -- ufix1
        reset_button_n : in std_logic_vector(0 downto 0);  -- ufix1
        stall : in std_logic_vector(0 downto 0);  -- ufix1
        stall_in : in std_logic_vector(0 downto 0);  -- ufix1
        start : in std_logic_vector(0 downto 0);  -- ufix1
        valid_in : in std_logic_vector(0 downto 0);  -- ufix1
        avst_iord_bl_do_ready : out std_logic_vector(0 downto 0);  -- ufix1
        avst_iowr_bl_return_data : out std_logic_vector(31 downto 0);  -- ufix32
        avst_iowr_bl_return_valid : out std_logic_vector(0 downto 0);  -- ufix1
        busy : out std_logic_vector(0 downto 0);  -- ufix1
        done : out std_logic_vector(0 downto 0);  -- ufix1
        returndata : out std_logic_vector(31 downto 0);  -- ufix32
        clock : in std_logic;
        resetn : in std_logic
    );
end switch_to_led_function_wrapper;

architecture normal of switch_to_led_function_wrapper is

    attribute altera_attribute : string;
    attribute altera_attribute of normal : architecture is "-name AUTO_SHIFT_REGISTER_RECOGNITION OFF; -name PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION ON; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 10037; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 15400; -name MESSAGE_DISABLE 14130; -name MESSAGE_DISABLE 10036; -name MESSAGE_DISABLE 12020; -name MESSAGE_DISABLE 12030; -name MESSAGE_DISABLE 12010; -name MESSAGE_DISABLE 12110; -name MESSAGE_DISABLE 14320; -name MESSAGE_DISABLE 13410; -name MESSAGE_DISABLE 113007";
    
    component acl_reset_wire is
        port (
            o_resetn : out std_logic;
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    component switch_to_led_function is
        port (
            in_arg_do : in std_logic_vector(63 downto 0);  -- Fixed Point
            in_arg_return : in std_logic_vector(63 downto 0);  -- Fixed Point
            in_iord_bl_do_i_fifodata : in std_logic_vector(15 downto 0);  -- Fixed Point
            in_iord_bl_do_i_fifovalid : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_iowr_bl_return_i_fifoready : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_stall_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            in_valid_in : in std_logic_vector(0 downto 0);  -- Fixed Point
            out_iord_bl_do_o_fifoready : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_iowr_bl_return_o_fifodata : out std_logic_vector(31 downto 0);  -- Fixed Point
            out_iowr_bl_return_o_fifovalid : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_stall_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            out_valid_out : out std_logic_vector(0 downto 0);  -- Fixed Point
            clock : in std_logic;
            resetn : in std_logic
        );
    end component;


    signal GND_q : STD_LOGIC_VECTOR (0 downto 0);
    signal VCC_q : STD_LOGIC_VECTOR (0 downto 0);
    signal busy_and_q : STD_LOGIC_VECTOR (0 downto 0);
    signal busy_or_q : STD_LOGIC_VECTOR (0 downto 0);
    signal do_const_q : STD_LOGIC_VECTOR (63 downto 0);
    signal implicit_input_q : STD_LOGIC_VECTOR (15 downto 0);
    signal implicit_input_pad_const_1_q : STD_LOGIC_VECTOR (6 downto 0);
    signal not_ready_q : STD_LOGIC_VECTOR (0 downto 0);
    signal not_stall_q : STD_LOGIC_VECTOR (0 downto 0);
    signal pos_reset_q : STD_LOGIC_VECTOR (0 downto 0);
    signal reset_wire_inst_o_resetn : STD_LOGIC_VECTOR (0 downto 0);
    signal reset_wire_inst_o_resetn_bitsignaltemp : std_logic;
    signal return_bits_b : STD_LOGIC_VECTOR (31 downto 0);
    signal switch_to_led_function_out_iord_bl_do_o_fifoready : STD_LOGIC_VECTOR (0 downto 0);
    signal switch_to_led_function_out_iowr_bl_return_o_fifodata : STD_LOGIC_VECTOR (31 downto 0);
    signal switch_to_led_function_out_iowr_bl_return_o_fifovalid : STD_LOGIC_VECTOR (0 downto 0);

begin


    -- VCC(CONSTANT,1)
    VCC_q <= "1";

    -- GND(CONSTANT,0)
    GND_q <= "0";

    -- not_stall(LOGICAL,21)
    not_stall_q <= not (stall);

    -- implicit_input_pad_const_1(CONSTANT,8)
    implicit_input_pad_const_1_q <= "0000000";

    -- implicit_input(BITJOIN,7)
    implicit_input_q <= implicit_input_pad_const_1_q & reset_button_n & implicit_input_pad_const_1_q & button_n;

    -- do_const(CONSTANT,6)
    do_const_q <= "0000000000000000000000000000000000000000000000000000000000000000";

    -- switch_to_led_function(BLACKBOX,32)
    theswitch_to_led_function : switch_to_led_function
    PORT MAP (
        in_arg_do => do_const_q,
        in_arg_return => do_const_q,
        in_iord_bl_do_i_fifodata => implicit_input_q,
        in_iord_bl_do_i_fifovalid => start,
        in_iowr_bl_return_i_fifoready => not_stall_q,
        in_stall_in => GND_q,
        in_valid_in => VCC_q,
        out_iord_bl_do_o_fifoready => switch_to_led_function_out_iord_bl_do_o_fifoready,
        out_iowr_bl_return_o_fifodata => switch_to_led_function_out_iowr_bl_return_o_fifodata,
        out_iowr_bl_return_o_fifovalid => switch_to_led_function_out_iowr_bl_return_o_fifovalid,
        clock => clock,
        resetn => resetn
    );

    -- avst_iord_bl_do_ready(GPOUT,22)
    avst_iord_bl_do_ready <= switch_to_led_function_out_iord_bl_do_o_fifoready;

    -- avst_iowr_bl_return_data(GPOUT,23)
    avst_iowr_bl_return_data <= switch_to_led_function_out_iowr_bl_return_o_fifodata;

    -- avst_iowr_bl_return_valid(GPOUT,24)
    avst_iowr_bl_return_valid <= switch_to_led_function_out_iowr_bl_return_o_fifovalid;

    -- not_ready(LOGICAL,20)
    not_ready_q <= not (switch_to_led_function_out_iord_bl_do_o_fifoready);

    -- busy_and(LOGICAL,2)
    busy_and_q <= not_ready_q and start;

    -- reset_wire_inst(EXTIFACE,29)
    reset_wire_inst_o_resetn(0) <= reset_wire_inst_o_resetn_bitsignaltemp;
    thereset_wire_inst : acl_reset_wire
    PORT MAP (
        o_resetn => reset_wire_inst_o_resetn_bitsignaltemp,
        clock => clock,
        resetn => resetn
    );

    -- pos_reset(LOGICAL,28)
    pos_reset_q <= not (reset_wire_inst_o_resetn);

    -- busy_or(LOGICAL,3)
    busy_or_q <= pos_reset_q or busy_and_q;

    -- busy(GPOUT,25)
    busy <= busy_or_q;

    -- done(GPOUT,26)
    done <= switch_to_led_function_out_iowr_bl_return_o_fifovalid;

    -- return_bits(BITSELECT,30)
    return_bits_b <= switch_to_led_function_out_iowr_bl_return_o_fifodata(31 downto 0);

    -- returndata(GPOUT,27)
    returndata <= return_bits_b;

END normal;
