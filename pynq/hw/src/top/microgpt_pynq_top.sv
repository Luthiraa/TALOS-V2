// -----------------------------------------------------------------------------
// microgpt_pynq_top.sv
//
// PYNQ-Z2 / Zynq-7000 top wrapper for the TALOS-V2 microGPT exact core.
//
// Deviations from the original DE1-SoC top (de1_soc_microgpt_rtl.sv):
//   * Avalon-MM JTAG-master replaced with a 12-bit / 32-bit AXI4-Lite slave
//     mapped at 0x4000_0000 (4 KB) on the PS GP0 port.
//   * Single clock domain (s_axi_aclk == FCLK_CLK0 @ 50 MHz). All toggle-bit
//     CDC synchronizers removed; control "toggles" become 1-cycle pulses.
//   * Altera PLL (sys_pll_56_25) removed -- the PS supplies the clock.
//   * SW[1:0] inputs removed; reset comes from FCLK_RESET0_N (s_axi_aresetn)
//     and "enable" is implied (always running, gated only by host commands).
//   * 7-segment HEX0..HEX5 outputs removed.
//   * Only 4 PL outputs remain, wired to PYNQ-Z2 LD0..LD3:
//         led_busy, led_done, led_error, led_heartbeat.
//   * WSTRB is ignored -- only aligned 32-bit writes are accepted.
//   * host_toggle_reg still toggles on every successful AXI transaction so the
//     host can detect that its access landed (kept for behavioural parity).
// -----------------------------------------------------------------------------

`default_nettype none

module microgpt_pynq_top #(
    // Width of the free-running heartbeat counter feeding led_heartbeat.
    // Synth default 26 gives 50 MHz / 2^26 = ~0.74 Hz visible blink. The cocotb
    // Makefile overrides this to a much smaller value so test_08 can observe a
    // led_heartbeat toggle within a short sim window.
    parameter integer HEARTBEAT_BITS = 26
) (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET s_axi_aresetn, FREQ_HZ 50000000" *)
    (* X_INTERFACE_INFO      = "xilinx.com:signal:clock:1.0 s_axi_aclk CLK" *)
    input  wire        s_axi_aclk,
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO      = "xilinx.com:signal:reset:1.0 s_axi_aresetn RST" *)
    input  wire        s_axi_aresetn,

    // AXI4-Lite write address channel
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWADDR"  *)
    input  wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWPROT"  *)
    input  wire [2:0]  s_axi_awprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWVALID" *)
    input  wire        s_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi AWREADY" *)
    output wire        s_axi_awready,

    // AXI4-Lite write data channel
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WDATA"   *)
    input  wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WSTRB"   *)
    input  wire [3:0]  s_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WVALID"  *)
    input  wire        s_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi WREADY"  *)
    output wire        s_axi_wready,

    // AXI4-Lite write response channel
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BRESP"   *)
    output wire [1:0]  s_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BVALID"  *)
    output wire        s_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi BREADY"  *)
    input  wire        s_axi_bready,

    // AXI4-Lite read address channel
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARADDR"  *)
    input  wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARPROT"  *)
    input  wire [2:0]  s_axi_arprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARVALID" *)
    input  wire        s_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi ARREADY" *)
    output wire        s_axi_arready,

    // AXI4-Lite read data channel
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RDATA"   *)
    output wire [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RRESP"   *)
    output wire [1:0]  s_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RVALID"  *)
    output wire        s_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 s_axi RREADY"  *)
    input  wire        s_axi_rready,

    // PL LEDs (LD0..LD3 on PYNQ-Z2)
    output wire        led_busy,
    output wire        led_done,
    output wire        led_error,
    output wire        led_heartbeat,

    // Active-high level interrupt asserted when a generation completes
    // (rising edge of done_latched_reg). Cleared automatically when the
    // host writes a new start_pulse via REG_CMD bit0, so the driver pattern
    // is: write start, wait on irq, read tokens, return. No explicit ACK.
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 done_irq INTERRUPT" *)
    (* X_INTERFACE_PARAMETER = "SENSITIVITY LEVEL_HIGH" *)
    output wire        done_irq
);

    // ---------------------------------------------------------------------
    // Local parameters
    // ---------------------------------------------------------------------
    localparam [7:0]  BOS_TOKEN  = 8'd26;
    localparam [2:0]  ST_READY   = 3'd0;
    localparam [2:0]  ST_WAIT_CORE = 3'd1;
    localparam [2:0]  ST_DONE    = 3'd2;

    // Word-address map (s_axi_*addr[11:2])
    localparam [9:0] A_MAGIC      = 10'h000;
    localparam [9:0] A_VERSION    = 10'h001;
    localparam [9:0] A_CMD        = 10'h002; // WO: bit0=start, bit1=clear
    localparam [9:0] A_STATUS     = 10'h003;
    localparam [9:0] A_CONFIG     = 10'h004; // {temp[31:16], max_gen[15:8], 8'd0}
    localparam [9:0] A_SEED       = 10'h005;
    localparam [9:0] A_LOGIT_INFO = 10'h006;
    localparam [9:0] A_BOS        = 10'h007;
    localparam [9:0] A_STEP_CFG   = 10'h008;
    localparam [9:0] A_STEP_TRIG  = 10'h009;
    localparam [9:0] A_HEARTBEAT  = 10'h00A; // RO debug: heartbeat_reg as a 32-b word
    localparam [9:0] A_OUT_BASE   = 10'h018; // 0x060/4 -> 16 words
    localparam [9:0] A_OUT_LAST   = 10'h027;
    localparam [9:0] A_PERF_CYC   = 10'h036;
    localparam [9:0] A_TPS        = 10'h037;
    localparam [9:0] A_LOGITS_BASE = 10'h040; // 27 entries
    localparam [9:0] A_LOGITS_LAST = 10'h05A;

    // ---------------------------------------------------------------------
    // AXI4-Lite slave FSM (very small, single outstanding txn)
    // ---------------------------------------------------------------------
    reg        awready_reg;
    reg        wready_reg;
    reg        bvalid_reg;
    reg        arready_reg;
    reg        rvalid_reg;
    reg [31:0] rdata_reg;

    reg [11:0] awaddr_reg;
    reg [11:0] araddr_reg;

    assign s_axi_awready = awready_reg;
    assign s_axi_wready  = wready_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = arready_reg;
    assign s_axi_rvalid  = rvalid_reg;
    assign s_axi_rdata   = rdata_reg;
    assign s_axi_rresp   = 2'b00;

    wire read_handshake  = s_axi_arvalid && arready_reg;

    // Latch write-strobe of the cycle so register-write logic can use it.
    reg        write_pulse_reg;
    reg [11:0] write_addr_reg;
    reg [31:0] write_data_reg;

    // Per-channel "transferred and pending" bits used by the rewritten
    // AXI4-Lite write FSM below (Xilinx-template style).
    reg        aw_latched;
    reg        w_latched;

    // ---------------------------------------------------------------------
    // Host-facing registers
    // ---------------------------------------------------------------------
    reg [15:0] host_temperature_reg;
    reg [7:0]  host_max_gen_reg;
    reg [31:0] host_seed_reg;
    reg        host_direct_mode_reg;
    reg        host_step_clear_reg;
    reg [7:0]  host_step_token_reg;
    reg [7:0]  host_step_pos_reg;
    reg        host_toggle_reg;        // toggles on every AXI transaction

    // 1-cycle pulses (replaces Avalon toggle-bit CDC)
    reg start_pulse;
    reg clear_pulse;
    reg step_pulse;

    // ---------------------------------------------------------------------
    // Core control plane (single-clock now, was on the 56.25 MHz domain)
    // ---------------------------------------------------------------------
    reg [2:0]  state_reg;
    reg [7:0]  token_reg;
    reg [7:0]  pos_reg;
    reg [7:0]  out_len_reg;
    reg [31:0] rng_reg;
    reg [15:0] temperature_reg;
    reg [7:0]  max_gen_reg;
    reg        start_core_reg;
    reg        clear_cache_reg;
    reg        done_latched_reg;
    reg [7:0]  last_token_reg;
    reg [31:0] perf_cycles_reg;
    reg [31:0] tokens_per_sec_reg;
    reg        error_reg;
    reg        host_run_reg;
    reg        direct_mode_reg;
    reg        step_clear_reg;
    reg [7:0]  step_token_reg;
    reg [7:0]  step_pos_reg;
    reg [7:0]  output_mem [0:15];
    // Heartbeat counter widened from 24b to 26b so led_heartbeat blinks
    // at ~0.74 Hz (50 MHz / 2^26) -- unambiguously visible to the eye.
    // The 24-bit MSB toggled at ~3 Hz which read as a steady half-bright
    // glow rather than a blink on the deployed bitstream.
    (* DONT_TOUCH = "true" *) reg [HEARTBEAT_BITS-1:0] heartbeat_reg;

    integer out_i;

    // ---------------------------------------------------------------------
    // Core instance
    // ---------------------------------------------------------------------
    wire core_busy;
    wire core_done;
    wire [7:0] core_next_token;
    wire [7:0] core_argmax_token;
    wire [31:0] core_rng_state;
    wire signed [15:0] core_top_logit;
    wire signed [(27*16)-1:0] core_logits_flat;

    // KEEP_HIERARCHY blocks Vivado synth from peering inside the core for
    // signal-equivalence merging. Without it, Vivado 2024.1 was tying the
    // wrapper's heartbeat_reg synchronous-reset pin to an internal control
    // signal of the unmodified core (GEN_ATTN_DIV[0].attn_div_inst/p_0_in),
    // which left led_heartbeat dark on hardware even though every netlist
    // probe of the synth checkpoint showed the counter wired correctly.
    (* KEEP_HIERARCHY = "yes" *)
    microgpt_exact_core core_inst (
        .clk              (s_axi_aclk),
        .resetn           (s_axi_aresetn),
        .start            (start_core_reg),
        .clear_cache      (clear_cache_reg),
        .sample_mode      (~direct_mode_reg),
        .temperature_q8_8 (temperature_reg),
        .rng_state_in     (rng_reg),
        .token_in         (token_reg),
        .pos_in           (pos_reg),
        .busy             (core_busy),
        .done             (core_done),
        .next_token       (core_next_token),
        .argmax_token     (core_argmax_token),
        .rng_state_out    (core_rng_state),
        .top_logit_q12    (core_top_logit),
        .logits_flat      (core_logits_flat)
    );

    // ---------------------------------------------------------------------
    // AXI4-Lite write channel  (FIXED -- 2026-05-09)
    //
    // PRODUCTION BUG (wedged the entire Zynq PS bus on the first write):
    //   The previous implementation kept AWREADY/WREADY perpetually high
    //   in idle and only latched the transaction when AWVALID, AWREADY,
    //   WVALID, and WREADY were all high in the SAME cycle (the
    //   `write_handshake` wire). Per AXI4 spec, however, once the slave
    //   samples READY high while VALID is high the handshake on that
    //   channel is COMPLETE, regardless of what the other channel is
    //   doing. The Zynq PS M_AXI_GP0 (AXI3) through axi_interconnect:2.1
    //   routinely staggers AW and W by a cycle, so:
    //     cycle N   : AWVALID=1, AWREADY=1 -> master considers AW done,
    //                 drops AWVALID; slave never latched anything.
    //     cycle N+1 : WVALID=1,  WREADY=1  -> master considers W done,
    //                 drops WVALID; slave still never latched anything.
    //     cycle N+2..inf : master waits for BVALID. BVALID never asserts.
    //                 The PS master is now wedged on an outstanding write,
    //                 the kernel locks up, hard power cycle required.
    //
    // FIX: standard Xilinx-template AXI4-Lite slave FSM. AWREADY pulses
    // for one cycle when AWVALID is observed and no AW is currently
    // pending, and the address is captured in awaddr_reg. WREADY behaves
    // identically and independently. When BOTH sides are latched
    // (aw_latched && w_latched) we fire the actual register-write pulse
    // and assert BVALID. BVALID is held until BREADY is observed, after
    // which the latches clear and the slave is ready for the next txn.
    //
    // BRESP is left at 2'b00 (OKAY); unmapped writes still complete the
    // BVALID handshake (they just don't have an effect in the decode
    // case statement below) -- which is the contract the cocotb suite
    // checks in test_06.
    // ---------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            awready_reg     <= 1'b0;
            wready_reg      <= 1'b0;
            bvalid_reg      <= 1'b0;
            aw_latched      <= 1'b0;
            w_latched       <= 1'b0;
            awaddr_reg      <= 12'd0;
            write_pulse_reg <= 1'b0;
            write_addr_reg  <= 12'd0;
            write_data_reg  <= 32'd0;
        end else begin
            write_pulse_reg <= 1'b0;

            // ----- AW channel: one-cycle AWREADY pulse + latch ------------
            if (!aw_latched && !awready_reg && s_axi_awvalid) begin
                awready_reg <= 1'b1;
                awaddr_reg  <= s_axi_awaddr;
                aw_latched  <= 1'b1;
            end else begin
                awready_reg <= 1'b0;
            end

            // ----- W channel: independent of AW, same shape --------------
            if (!w_latched && !wready_reg && s_axi_wvalid) begin
                wready_reg     <= 1'b1;
                write_data_reg <= s_axi_wdata;
                w_latched      <= 1'b1;
            end else begin
                wready_reg <= 1'b0;
            end

            // ----- B channel: fire write + BVALID once both sides in -----
            if (aw_latched && w_latched && !bvalid_reg) begin
                bvalid_reg      <= 1'b1;
                write_pulse_reg <= 1'b1;
                write_addr_reg  <= awaddr_reg;
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg <= 1'b0;
                aw_latched <= 1'b0;
                w_latched  <= 1'b0;
            end
        end
    end

    // ---------------------------------------------------------------------
    // AXI read channel
    // ---------------------------------------------------------------------
    reg [31:0] read_data_comb;
    reg        read_pulse_reg;

    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            arready_reg    <= 1'b1;
            rvalid_reg     <= 1'b0;
            rdata_reg      <= 32'd0;
            araddr_reg     <= 12'd0;
            read_pulse_reg <= 1'b0;
        end else begin
            read_pulse_reg <= 1'b0;
            if (read_handshake) begin
                arready_reg    <= 1'b0;
                araddr_reg     <= s_axi_araddr;
                rvalid_reg     <= 1'b1;
                rdata_reg      <= read_data_comb;
                read_pulse_reg <= 1'b1;
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg  <= 1'b0;
                arready_reg <= 1'b1;
            end
        end
    end

    // Word-address slices used by the read mux. For reads we look up against
    // the live s_axi_araddr in the same cycle we accept it.
    wire [9:0] r_word_addr = s_axi_araddr[11:2];
    wire [9:0] w_word_addr = write_addr_reg[11:2];

    // ---------------------------------------------------------------------
    // Read data mux (combinational)
    // ---------------------------------------------------------------------
    integer rd_i;
    always @* begin
        read_data_comb = 32'd0;
        rd_i           = 0;
        case (r_word_addr)
            A_MAGIC:      read_data_comb = 32'h4D475254; // "MGRT"
            A_VERSION:    read_data_comb = 32'h00020001;
            A_CMD:        read_data_comb = 32'd0;        // WO -> reads as 0
            A_STATUS:     read_data_comb = {
                              pos_reg,
                              out_len_reg,
                              8'd0,
                              2'd0,
                              direct_mode_reg,
                              host_toggle_reg,
                              error_reg,
                              done_latched_reg,
                              (state_reg == ST_WAIT_CORE),
                              (state_reg == ST_READY)
                          };
            A_CONFIG:     read_data_comb = {temperature_reg, max_gen_reg, 8'd0};
            A_SEED:       read_data_comb = rng_reg;
            A_LOGIT_INFO: read_data_comb = {core_top_logit[15:0], core_argmax_token, last_token_reg};
            A_BOS:        read_data_comb = {16'd0, 8'd0, BOS_TOKEN};
            A_STEP_CFG:   read_data_comb = {8'd0, step_token_reg, step_pos_reg, step_clear_reg, direct_mode_reg};
            A_STEP_TRIG:  read_data_comb = 32'd0;        // WO -> reads as 0
            A_HEARTBEAT:  read_data_comb = {{(32-HEARTBEAT_BITS){1'b0}}, heartbeat_reg};
            A_PERF_CYC:   read_data_comb = perf_cycles_reg;
            A_TPS:        read_data_comb = tokens_per_sec_reg;
            default: begin
                if ((r_word_addr >= A_OUT_BASE) && (r_word_addr <= A_OUT_LAST)) begin
                    rd_i = r_word_addr - A_OUT_BASE;
                    read_data_comb = {24'd0, output_mem[rd_i[3:0]]};
                end else if ((r_word_addr >= A_LOGITS_BASE) &&
                             (r_word_addr <= A_LOGITS_LAST)) begin
                    rd_i = r_word_addr - A_LOGITS_BASE;
                    read_data_comb = {{16{core_logits_flat[(rd_i*16)+15]}},
                                      core_logits_flat[(rd_i*16) +: 16]};
                end else begin
                    read_data_comb = 32'd0;
                end
            end
        endcase
    end

    // ---------------------------------------------------------------------
    // Register write decode + control pulses
    // ---------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            host_temperature_reg <= 16'h0080;
            host_max_gen_reg     <= 8'd15;
            host_seed_reg        <= 32'h0000_0001;
            host_direct_mode_reg <= 1'b0;
            host_step_clear_reg  <= 1'b0;
            host_step_token_reg  <= BOS_TOKEN;
            host_step_pos_reg    <= 8'd0;
            host_toggle_reg      <= 1'b0;
            start_pulse          <= 1'b0;
            clear_pulse          <= 1'b0;
            step_pulse           <= 1'b0;
        end else begin
            // Default: clear pulses every cycle
            start_pulse <= 1'b0;
            clear_pulse <= 1'b0;
            step_pulse  <= 1'b0;

            // Toggle on any successful AXI transaction (read or write).
            if (write_pulse_reg || read_pulse_reg)
                host_toggle_reg <= ~host_toggle_reg;

            if (write_pulse_reg) begin
                case (w_word_addr)
                    A_CMD: begin
                        if (write_data_reg[0]) start_pulse <= 1'b1;
                        if (write_data_reg[1]) clear_pulse <= 1'b1;
                    end
                    A_CONFIG: begin
                        host_max_gen_reg     <= write_data_reg[15:8];
                        host_temperature_reg <= write_data_reg[31:16];
                    end
                    A_SEED: begin
                        host_seed_reg <= write_data_reg;
                    end
                    A_STEP_CFG: begin
                        host_direct_mode_reg <= write_data_reg[0];
                        host_step_clear_reg  <= write_data_reg[1];
                        host_step_pos_reg    <= write_data_reg[15:8];
                        host_step_token_reg  <= write_data_reg[23:16];
                    end
                    A_STEP_TRIG: begin
                        if (write_data_reg[0]) step_pulse <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // ---------------------------------------------------------------------
    // Core control state machine (functional twin of DE1 top, single clock)
    // ---------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            state_reg          <= ST_READY;
            token_reg          <= BOS_TOKEN;
            pos_reg            <= 8'd0;
            out_len_reg        <= 8'd0;
            rng_reg            <= host_seed_reg;
            temperature_reg    <= 16'h0080;
            max_gen_reg        <= 8'd15;
            start_core_reg     <= 1'b0;
            clear_cache_reg    <= 1'b0;
            done_latched_reg   <= 1'b0;
            last_token_reg     <= 8'd0;
            perf_cycles_reg    <= 32'd0;
            tokens_per_sec_reg <= 32'd0;
            error_reg          <= 1'b0;
            host_run_reg       <= 1'b0;
            direct_mode_reg    <= 1'b0;
            step_clear_reg     <= 1'b0;
            step_token_reg     <= BOS_TOKEN;
            step_pos_reg       <= 8'd0;
            for (out_i = 0; out_i < 16; out_i = out_i + 1)
                output_mem[out_i] <= 8'd0;
        end else begin
            start_core_reg  <= 1'b0;
            clear_cache_reg <= 1'b0;

            if (state_reg == ST_WAIT_CORE)
                perf_cycles_reg <= perf_cycles_reg + 32'd1;

            // Latch host config on a fresh start request.
            if (start_pulse) begin
                max_gen_reg     <= host_max_gen_reg;
                temperature_reg <= host_temperature_reg;
                rng_reg         <= host_seed_reg;
                direct_mode_reg <= 1'b0;
                host_run_reg    <= 1'b1;
            end

            if (step_pulse) begin
                direct_mode_reg <= host_direct_mode_reg;
                step_clear_reg  <= host_step_clear_reg;
                step_token_reg  <= host_step_token_reg;
                step_pos_reg    <= host_step_pos_reg;
            end

            if (clear_pulse) begin
                state_reg          <= ST_READY;
                token_reg          <= BOS_TOKEN;
                pos_reg            <= 8'd0;
                out_len_reg        <= 8'd0;
                done_latched_reg   <= 1'b0;
                last_token_reg     <= 8'd0;
                perf_cycles_reg    <= 32'd0;
                tokens_per_sec_reg <= 32'd0;
                error_reg          <= 1'b0;
                host_run_reg       <= 1'b0;
                direct_mode_reg    <= 1'b0;
                for (out_i = 0; out_i < 16; out_i = out_i + 1)
                    output_mem[out_i] <= 8'd0;
            end else begin
                case (state_reg)
                    ST_READY: begin
                        if (step_pulse && host_direct_mode_reg) begin
                            token_reg          <= host_step_token_reg;
                            pos_reg            <= host_step_pos_reg;
                            out_len_reg        <= 8'd0;
                            done_latched_reg   <= 1'b0;
                            last_token_reg     <= 8'd0;
                            perf_cycles_reg    <= 32'd0;
                            tokens_per_sec_reg <= 32'd0;
                            error_reg          <= 1'b0;
                            if (host_step_clear_reg)
                                rng_reg <= host_seed_reg;
                            clear_cache_reg <= host_step_clear_reg;
                            start_core_reg  <= 1'b1;
                            state_reg       <= ST_WAIT_CORE;
                        end else if (start_pulse) begin
                            token_reg          <= BOS_TOKEN;
                            pos_reg            <= 8'd0;
                            out_len_reg        <= 8'd0;
                            done_latched_reg   <= 1'b0;
                            last_token_reg     <= 8'd0;
                            perf_cycles_reg    <= 32'd0;
                            tokens_per_sec_reg <= 32'd0;
                            error_reg          <= 1'b0;
                            for (out_i = 0; out_i < 16; out_i = out_i + 1)
                                output_mem[out_i] <= 8'd0;
                            clear_cache_reg <= 1'b1;
                            if (host_max_gen_reg == 8'd0 || host_max_gen_reg > 8'd15) begin
                                error_reg        <= 1'b1;
                                done_latched_reg <= 1'b1;
                                state_reg        <= ST_DONE;
                            end else begin
                                start_core_reg <= 1'b1;
                                state_reg      <= ST_WAIT_CORE;
                            end
                        end
                    end

                    ST_WAIT_CORE: begin
                        if (core_done) begin
                            rng_reg        <= core_rng_state;
                            last_token_reg <= core_next_token;
                            if (direct_mode_reg) begin
                                done_latched_reg <= 1'b1;
                                state_reg        <= ST_DONE;
                            end else if ((core_next_token == BOS_TOKEN) || (pos_reg == 8'd15)) begin
                                done_latched_reg <= 1'b1;
                                state_reg        <= ST_DONE;
                            end else begin
                                output_mem[out_len_reg[3:0]] <= core_next_token;
                                token_reg   <= core_next_token;
                                pos_reg     <= pos_reg + 8'd1;
                                out_len_reg <= out_len_reg + 8'd1;
                                if ((out_len_reg + 8'd1) >= max_gen_reg) begin
                                    done_latched_reg <= 1'b1;
                                    state_reg        <= ST_DONE;
                                end else begin
                                    start_core_reg <= 1'b1;
                                    state_reg      <= ST_WAIT_CORE;
                                end
                            end
                        end
                    end

                    ST_DONE: begin
                        if (step_pulse && host_direct_mode_reg) begin
                            token_reg          <= host_step_token_reg;
                            pos_reg            <= host_step_pos_reg;
                            out_len_reg        <= 8'd0;
                            done_latched_reg   <= 1'b0;
                            last_token_reg     <= 8'd0;
                            perf_cycles_reg    <= 32'd0;
                            tokens_per_sec_reg <= 32'd0;
                            error_reg          <= 1'b0;
                            if (host_step_clear_reg)
                                rng_reg <= host_seed_reg;
                            clear_cache_reg <= host_step_clear_reg;
                            start_core_reg  <= 1'b1;
                            state_reg       <= ST_WAIT_CORE;
                        end else if (start_pulse) begin
                            token_reg          <= BOS_TOKEN;
                            pos_reg            <= 8'd0;
                            out_len_reg        <= 8'd0;
                            done_latched_reg   <= 1'b0;
                            last_token_reg     <= 8'd0;
                            perf_cycles_reg    <= 32'd0;
                            tokens_per_sec_reg <= 32'd0;
                            error_reg          <= 1'b0;
                            for (out_i = 0; out_i < 16; out_i = out_i + 1)
                                output_mem[out_i] <= 8'd0;
                            clear_cache_reg <= 1'b1;
                            if (host_max_gen_reg == 8'd0 || host_max_gen_reg > 8'd15) begin
                                error_reg        <= 1'b1;
                                done_latched_reg <= 1'b1;
                                state_reg        <= ST_DONE;
                            end else begin
                                start_core_reg <= 1'b1;
                                state_reg      <= ST_WAIT_CORE;
                            end
                        end
                    end

                    default: state_reg <= ST_READY;
                endcase
            end
        end
    end

    // ---------------------------------------------------------------------
    // Free-running heartbeat counter -- isolated in its own always block.
    //
    // Why a separate block: when this counter lived inside the giant FSM
    // control always block above, Vivado synth (2024.1) lifted its reset
    // path through the unmodified microgpt_exact_core's sampler and the
    // resulting bitstream left led_heartbeat dark on hardware even though
    // every checkpoint introspection showed heartbeat_reg_reg[25] driving
    // the OBUF input correctly. Moving the counter to a minimal isolated
    // always block prevents the optimisation from straying into the core's
    // sampler instance. (* KEEP = "true" *) on the reg keeps a future
    // synth release from merging it back in.
    // ---------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            heartbeat_reg <= {HEARTBEAT_BITS{1'b0}};
        else
            heartbeat_reg <= heartbeat_reg + 1'b1;
    end

    // ---------------------------------------------------------------------
    // LED outputs (PYNQ-Z2 LD0..LD3)
    // ---------------------------------------------------------------------
    assign led_busy      = (state_reg == ST_WAIT_CORE);
    assign led_done      = done_latched_reg;
    assign led_error     = error_reg;
    assign led_heartbeat = heartbeat_reg[HEARTBEAT_BITS-1];

    // ---------------------------------------------------------------------
    // PL->PS interrupt: asserts on rising edge of done_latched_reg, holds
    // until the host writes a new start_pulse (or a clear_pulse). The PS
    // sees a level-high IRQ; the GIC + PYNQ Interrupt driver wakes the
    // userspace coroutine the moment the line goes high.
    //
    // Why latched-and-cleared-by-start instead of a 1-cycle pulse:
    //  * a 1-cycle pulse at 50 MHz is technically observable by the GIC
    //    after synchronisation, but it is more fragile across IRQ_F2P
    //    metastability than a level signal,
    //  * letting start_pulse be the implicit ACK saves one MMIO
    //    transaction per call (no separate IRQ_ACK register write),
    //  * because every generate() call begins with a start, the line
    //    is guaranteed to be low when the next wait() is armed.
    // ---------------------------------------------------------------------
    reg done_latched_reg_d;
    reg irq_pending_reg;
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            done_latched_reg_d <= 1'b0;
            irq_pending_reg    <= 1'b0;
        end else begin
            done_latched_reg_d <= done_latched_reg;
            if (start_pulse || clear_pulse)
                irq_pending_reg <= 1'b0;
            else if (done_latched_reg && !done_latched_reg_d)
                irq_pending_reg <= 1'b1;
        end
    end

    assign done_irq = irq_pending_reg;

endmodule

`default_nettype wire
