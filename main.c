#define _CRT_SECURE_NO_WARNINGS

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <unistd.h>
#endif

static void usage(const char *argv0) {
    fprintf(stderr,
            "usage: %s [--steps N] [--temperature T] [--seed N]\n"
            "\n"
            "Starts the RTL microgpt generator from BOS over the JTAG/MMIO bridge.\n",
            argv0);
}

static int parse_int_arg(const char *name, const char *value, int min_value, int max_value) {
    char *end = NULL;
    long parsed = strtol(value, &end, 0);
    if (end == value || *end != '\0' || parsed < min_value || parsed > max_value) {
        fprintf(stderr, "%s must be between %d and %d\n", name, min_value, max_value);
        exit(2);
    }
    return (int)parsed;
}

static double parse_double_arg(const char *name, const char *value, double min_value, double max_value) {
    char *end = NULL;
    double parsed = strtod(value, &end);
    if (end == value || *end != '\0' || parsed < min_value || parsed > max_value) {
        fprintf(stderr, "%s must be between %.3f and %.3f\n", name, min_value, max_value);
        exit(2);
    }
    return parsed;
}

static void write_tcl(FILE *f, int steps, int temp_q8_8, int seed) {
    fprintf(f,
            "proc rd32 {m addr} { return [lindex [master_read_32 $m $addr 1] 0] }\n"
            "proc tok_char {token} {\n"
            "    if {$token == 26} { return \"\" }\n"
            "    if {$token >= 0 && $token < 26} { return [string index \"abcdefghijklmnopqrstuvwxyz\" $token] }\n"
            "    return \"?\"\n"
            "}\n"
            "refresh_connections\n"
            "set device_path [lindex [get_service_paths device] 0]\n"
            "if {$device_path eq \"\"} { error \"No device service found.\" }\n"
            "set jdi_path [file normalize [file join [pwd] \"de1_soc_microgpt_rtl.jdi\"]]\n"
            "if {![file exists $jdi_path]} { error \"JDI file not found: $jdi_path\" }\n"
            "set design_path [design_load $jdi_path]\n"
            "set design_inst [design_instantiate $design_path]\n"
            "design_link $design_inst $device_path\n"
            "set service_path [lindex [get_service_paths master] 0]\n"
            "if {$service_path eq \"\"} { error \"No JTAG master service found.\" }\n"
            "open_service master $service_path\n"
            "puts [format {ID=0x%%08X} [rd32 $service_path 0x00]]\n"
            "puts [format {VERSION=0x%%08X} [rd32 $service_path 0x04]]\n"
            "puts [format {BOS=%%d} [expr {[rd32 $service_path 0x1C] & 0xff}]]\n"
            "master_write_32 $service_path 0x08 0x00000002\n"
            "master_write_32 $service_path 0x10 0x%08X\n"
            "master_write_32 $service_path 0x14 0x%08X\n"
            "master_write_32 $service_path 0x08 0x00000001\n"
            "set timeout 20000\n"
            "set streamed_len 0\n"
            "set status 0\n"
            "while {$timeout > 0} {\n"
            "    set status [rd32 $service_path 0x0C]\n"
            "    set out_len_now [expr {($status >> 16) & 0xff}]\n"
            "    if {$out_len_now > $streamed_len} {\n"
            "        for {set i $streamed_len} {$i < $out_len_now} {incr i} {\n"
            "            set token_word [rd32 $service_path [expr {0x60 + ($i * 4)}]]\n"
            "            puts [format {STREAM_TOKEN=%%d} [expr {$token_word & 0xff}]]\n"
            "        }\n"
            "        set streamed_len $out_len_now\n"
            "    }\n"
            "    if {$status & 0x8} { puts ERROR=1; break }\n"
            "    if {$status & 0x4} { puts DONE=1; break }\n"
            "    after 5\n"
            "    incr timeout -1\n"
            "}\n"
            "set out_len [expr {($status >> 16) & 0xff}]\n"
            "puts [format {STATUS=0x%%08X} $status]\n"
            "puts [format {OUT_LEN=%%d} $out_len]\n"
            "set outputs {}\n"
            "set output_text \"\"\n"
            "for {set i 0} {$i < $out_len} {incr i} {\n"
            "    set token_word [rd32 $service_path [expr {0x60 + ($i * 4)}]]\n"
            "    set token [expr {$token_word & 0xff}]\n"
            "    lappend outputs $token_word\n"
            "    append output_text [tok_char $token]\n"
            "}\n"
            "puts [format {OUTPUT_TOKENS=%%s} $outputs]\n"
            "puts [format {OUTPUT_TEXT=%%s} $output_text]\n"
            "puts [format {PERF_CYCLES=%%u} [rd32 $service_path 0xD8]]\n"
            "puts [format {TOKENS_PER_SEC=%%u} [rd32 $service_path 0xDC]]\n"
            "close_service master $service_path\n",
            ((temp_q8_8 & 0xffff) << 16) | ((steps & 0xff) << 8),
            seed);
}

int main(int argc, char **argv) {
    int steps = 15;
    int seed = 1;
    double temperature = 0.5;
    int i;

    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--steps") == 0 && i + 1 < argc) {
            steps = parse_int_arg("--steps", argv[++i], 1, 15);
        } else if (strcmp(argv[i], "--seed") == 0 && i + 1 < argc) {
            seed = parse_int_arg("--seed", argv[++i], 0, 0x7fffffff);
        } else if (strcmp(argv[i], "--temperature") == 0 && i + 1 < argc) {
            temperature = parse_double_arg("--temperature", argv[++i], 0.001, 16.0);
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    int temp_q8_8 = (int)(temperature * 256.0 + 0.5);

#ifdef _WIN32
    char temp_dir[MAX_PATH];
    char tcl_path[MAX_PATH];
    if (GetTempPathA((DWORD)sizeof(temp_dir), temp_dir) == 0 ||
        GetTempFileNameA(temp_dir, "bos", 0, tcl_path) == 0) {
        fprintf(stderr, "failed to create temporary Tcl path\n");
        return 1;
    }
#else
    char tcl_path[] = "/tmp/microgpt_bos_start_XXXXXX";
    int fd = mkstemp(tcl_path);
    if (fd < 0) {
        perror("mkstemp");
        return 1;
    }
    close(fd);
#endif

    FILE *f = fopen(tcl_path, "w");
    if (!f) {
        fprintf(stderr, "failed to open %s: %s\n", tcl_path, strerror(errno));
        return 1;
    }
    write_tcl(f, steps, temp_q8_8, seed);
    fclose(f);

    char command[4096];
    snprintf(command, sizeof(command),
             "cd /d \"rtl\" && "
             "\"C:\\\\intelFPGA\\\\18.1\\\\quartus\\\\sopc_builder\\\\bin\\\\system-console.exe\" "
             "-cli -disable_readline < \"%s\"",
             tcl_path);

    printf("Starting RTL microgpt from BOS over JTAG: steps=%d temperature=%.6g seed=%d\n",
           steps, temperature, seed);
    fflush(stdout);
    int rc = system(command);

    remove(tcl_path);
    return rc == 0 ? 0 : 1;
}
