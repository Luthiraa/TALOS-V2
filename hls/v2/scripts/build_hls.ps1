python tools/export_microgpt_weights.py
python tools/export_microgpt_roms.py
& 'C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-generate.exe' 'microgpt_step_fpga.prj\components\microgpt_step\microgpt_step.qsys' --synthesis=VERILOG --output-directory='components\microgpt_step' --family='Cyclone V' --part=5CSEMA5F31C6

$componentDir = Join-Path $PSScriptRoot '..\microgpt_step_fpga.prj\components\microgpt_step'
$hwTclPath = Join-Path $componentDir 'microgpt_step_internal_hw.tcl'
$qipDir = Join-Path $componentDir 'synthesis'
$qipPath = Join-Path $qipDir 'microgpt_step_direct.qip'

New-Item -ItemType Directory -Force -Path $qipDir | Out-Null

$qipLines = New-Object System.Collections.Generic.List[string]
$qipLines.Add('set_global_assignment -name SYNTHESIS_ONLY_QIP ON')
$qipLines.Add('set_instance_assignment -entity "microgpt_step_internal" -library "microgpt_step" -name AUTO_SHIFT_REGISTER_RECOGNITION OFF -to *_NO_SHIFT_REG*')

foreach ($line in Get-Content $hwTclPath) {
    if ($line -match '^add_fileset_file\s+\S+\s+(\S+)\s+PATH\s+(.+)$') {
        $kind = $matches[1]
        $relativePath = $matches[2]
        $assignment = switch ($kind) {
            'VHDL' { 'VHDL_FILE' }
            'SYSTEM_VERILOG' { 'SYSTEMVERILOG_FILE' }
            'VERILOG' { 'VERILOG_FILE' }
            'HEX' { 'MISC_FILE' }
            default { $null }
        }

        if ($assignment) {
            $qipRelativePath = ('../' + $relativePath).Replace('\', '/')
            $qipLines.Add("set_global_assignment -library `"microgpt_step`" -name $assignment [file join `$::quartus(qip_path) `"$qipRelativePath`"]")
        }
    }
}

Set-Content -Path $qipPath -Value $qipLines

& 'C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-script.exe' --script=qsys\create_jtag_microgpt_bridge.tcl
& 'C:\intelFPGA\18.1\quartus\sopc_builder\bin\qsys-generate.exe' 'jtag_microgpt_bridge.qsys' --synthesis=VERILOG
