param(
    [switch]$ValidateOnly,
    [string]$TdRoot = 'D:\AnlogicTD_6.2.1_Engineer_6.2.168.116',
    [string]$OpenOcd = 'D:\workspace\fpga\contest\final_solution\candidates\sc520_lightwall_2026-10-23\tools\xpack-openocd-0.12.0-7\bin\openocd.exe'
)

$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Get-Content:Encoding']='UTF8'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(!$ValidateOnly){
    $taskUserState=Get-Content -LiteralPath (Join-Path $root 'reports/当前候选状态_2026-11-01.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if($taskUserState.hardware_download_deferred_by_user){throw 'User explicitly deferred SRAM testing until they request it. Offline validation remains allowed.'}
}
if (!$ValidateOnly) {
    $taskStatePath=Join-Path $root 'reports/当前候选状态_2026-11-01.json'
    if (Test-Path -LiteralPath $taskStatePath) {
        $taskState=Get-Content -LiteralPath $taskStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($taskState.hardware_download_deferred_by_user) {throw 'User requested offline work only until returning; SRAM download is deferred.'}
    }
}
$phy = Join-Path $root 'candidate/sc520_shapes/td_project/camera_to_dsi_display_Runs/phy_1'
$bit = Join-Path $phy 'camera_to_dsi_display.bit'
$area = Join-Path $phy 'camera_to_dsi_display_phy.area'
$timing = Join-Path $phy 'final_timing.rpt'
$buildPath = Join-Path $root 'reports/build_receipt.json'
$build = Get-Content -LiteralPath $buildPath -Raw | ConvertFrom-Json
if ($build.project -ne 'sc520_cal_final_2026-11-01' -or !$build.completed -or !$build.timing_passed) {
    throw 'Unexpected video candidate identity/panel count.'
}
$expectedHash = $build.bit_sha256
foreach ($item in $build.source_sha256.PSObject.Properties) {
    $sourcePath = Join-Path (Join-Path $root 'candidate/sc520_shapes') $item.Name
    if ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $item.Value) {
        throw "Source changed after validated build: $($item.Name)"
    }
}
$bitWizard = Join-Path $TdRoot 'bin/bw_commands_prompt.exe'

foreach ($path in @($bit, $area, $timing)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Required file is missing: $path" }
}

$hash = (Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $expectedHash) { throw "Bitstream SHA-256 mismatch: $hash" }

$areaText = Get-Content -LiteralPath $area -Raw
if ($areaText -notmatch 'O_ws2812_data\s+OUTPUT\s+P5\s+LVCMOS33') {
    throw 'Refusing to program: final routed IO report does not assign O_ws2812_data to P5.'
}
if ((Get-FileHash -LiteralPath $timing -Algorithm SHA256).Hash -ne $build.timing_sha256 -or
    (Get-FileHash -LiteralPath $area -Algorithm SHA256).Hash -ne $build.area_sha256 -or
    $build.setup_wns_ns -lt 0 -or $build.hold_wns_ns -lt 0 -or
    $build.setup_tns_ns -ne 0 -or $build.hold_tns_ns -ne 0) {
    throw 'Timing/area report identity mismatch or timing violation.'
}

$simPath = Join-Path $root 'reports/simulation_receipt.json'
$sim = Get-Content -LiteralPath $simPath -Raw | ConvertFrom-Json
if (!$sim.all_passed -or $sim.suites.Count -ne 40) {throw '40-suite simulation receipt missing or failed.'}
foreach ($item in $sim.sha256.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $root $item.Name) -Algorithm SHA256).Hash -ne $item.Value) {
        throw ('Simulation source/vector changed: '+$item.Name)
    }
}
foreach ($suite in $sim.suites) {
    if ((Get-FileHash -LiteralPath (Join-Path $root ('reports/'+$suite.log)) -Algorithm SHA256).Hash -ne $suite.log_sha256) {
        throw ('Simulation log changed: '+$suite.log)
    }
}
if ($ValidateOnly) {Write-Output 'OFFLINE_ARTIFACT_VALIDATION_PASSED_NO_HARDWARE_ACCESSED';return}
foreach ($path in @($bitWizard,$OpenOcd)) {if (!(Test-Path -LiteralPath $path)) {throw ('Missing download tool: '+$path)}}

$devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_0403&PID_6042' })
$mi0 = @($devices | Where-Object { $_.InstanceId.Contains('&MI_00\') })
$mi1 = @($devices | Where-Object { $_.InstanceId.Contains('&MI_01\') })
if ($mi0.Count -ne 1 -or $mi1.Count -ne 1 -or $mi0[0].Status -ne 'OK' -or $mi1[0].Status -ne 'OK') {
    throw 'USB-JTAG interfaces are not both present and healthy.'
}
$service0 = (Get-PnpDeviceProperty -InstanceId $mi0[0].InstanceId -ErrorAction SilentlyContinue |
    Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data
$service1 = (Get-PnpDeviceProperty -InstanceId $mi1[0].InstanceId -ErrorAction SilentlyContinue |
    Where-Object KeyName -eq 'DEVPKEY_Device_Service').Data
if ($service0 -ne 'WINUSB' -or $service1 -ne 'FTDIBUS') {
    throw "Unexpected USB-JTAG services: A=$service0; B=$service1"
}

$run = Join-Path $root ('reports/interactive_sram_' + [DateTime]::Now.ToString('yyyyMMdd_HHmmss_fff'))
[IO.Directory]::CreateDirectory($run) | Out-Null
$portableBit = $bit.Replace('\', '/')
$svfTcl = @"
if {[catch {
    svfgen -scan_mode prog_sram -bit {$portableBit} -svf candidate.svf
    svfgen -scan_mode check_status_done -bit {$portableBit} -svf candidate_done.svf
} message]} {puts stderr `$message; exit 1}
puts "INTERACTIVE_CANVAS_SRAM_SVF_COMPLETED"
exit 0
"@
[IO.File]::WriteAllText((Join-Path $run 'generate.tcl'), $svfTcl, (New-Object Text.UTF8Encoding($false)))

$openOcdCfg = @'
adapter driver ftdi
ftdi vid_pid 0x0403 0x6042
ftdi channel 0
ftdi layout_init 0x0008 0x000b
transport select jtag
adapter speed 1000
jtag newtap fpga tap -irlen 8 -expected-id 0x4808f0e7
init
svf candidate.svf -quiet
svf candidate_done.svf -quiet
echo INTERACTIVE_CANVAS_SRAM_AND_DONE_PASSED
shutdown
'@
[IO.File]::WriteAllText((Join-Path $run 'program.cfg'), $openOcdCfg, (New-Object Text.UTF8Encoding($false)))

Push-Location $run
try {
    $svfOutput = @(& $bitWizard 'generate.tcl' 2>&1)
    $svfExit = $LASTEXITCODE
} finally {
    Pop-Location
}
[IO.File]::WriteAllLines((Join-Path $run 'generate.log'), [string[]]$svfOutput)
if ($svfExit -ne 0 -or -not (($svfOutput -join "`n").Contains('INTERACTIVE_CANVAS_SRAM_SVF_COMPLETED'))) {
    throw "SVF generation failed. Inspect $run\generate.log"
}

Push-Location $run
try {
    $program = Start-Process -FilePath $OpenOcd -ArgumentList '-f program.cfg' -WorkingDirectory $run `
        -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $run 'program.stdout.log') `
        -RedirectStandardError (Join-Path $run 'program.stderr.log')
    $programExit = $program.ExitCode
} finally {
    Pop-Location
}
$programOutput = @(
    Get-Content -LiteralPath (Join-Path $run 'program.stdout.log') -ErrorAction SilentlyContinue
    Get-Content -LiteralPath (Join-Path $run 'program.stderr.log') -ErrorAction SilentlyContinue
)
[IO.File]::WriteAllLines((Join-Path $run 'program.log'), [string[]]$programOutput)
if ($programExit -ne 0 -or -not (($programOutput -join "`n").Contains('INTERACTIVE_CANVAS_SRAM_AND_DONE_PASSED'))) {
    throw "SRAM/DONE verification failed. Inspect $run\program.log"
}

$receipt = [ordered]@{
    timestamp = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
    project = 'sc520_cal_final_2026-11-01'
    td_version = '6.2.168116 (TD 6.2.1)'
    method = 'TD 6.2.1 prog_sram SVF via OpenOCD FTDI/JTAG'
    bit_sha256 = $hash
    output_pin = 'P5 / J1-15 (fixed-background light canvas / GRB / 32x16 / two panels)'
    output_pin_verified = $true
    final_setup_wns_ns = $build.setup_wns_ns
    final_hold_wns_ns = $build.hold_wns_ns
    usb_interface_a_service = $service0
    usb_interface_b_service = $service1
    jtag_id = '0x4808F0E7'
    svf_generated = $true
    sram_downloaded = $true
    done_passed = $true
    visual_accepted = $false
    flash_written = $false
    generated_svf_sha256 = (Get-FileHash -LiteralPath (Join-Path $run 'candidate.svf') -Algorithm SHA256).Hash
    done_svf_sha256 = (Get-FileHash -LiteralPath (Join-Path $run 'candidate_done.svf') -Algorithm SHA256).Hash
}
[IO.File]::WriteAllText((Join-Path $run 'receipt.json'), ($receipt | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
Write-Output "INTERACTIVE_CANVAS_SRAM_AND_DONE_PASSED: $run"
Write-Output "BIT_SHA256: $hash"

$build.sram_downloaded = $true
$build | Add-Member -NotePropertyName done_passed -NotePropertyValue $true -Force
$build | Add-Member -NotePropertyName latest_sram_receipt -NotePropertyValue $run -Force
[IO.File]::WriteAllText($buildPath, ($build | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
