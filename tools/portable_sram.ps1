param([switch]$ValidateOnly, [switch]$CheckConnection)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskRunDir = $null
function Read-Json([string]$Path) {
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Package-Path([string]$Relative) {
    $taskPath = [IO.Path]::GetFullPath((Join-Path $taskRoot $Relative))
    if (!$taskPath.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw ('Invalid package path: ' + $Relative)
    }
    return $taskPath
}
function Assert-Hash([string]$Relative, [string]$Expected) {
    $taskPath = Package-Path $Relative
    if (!(Test-Path -LiteralPath $taskPath -PathType Leaf)) { throw ('Missing file: ' + $Relative) }
    $taskStream = [IO.File]::OpenRead($taskPath)
    $taskHasher = [Security.Cryptography.SHA256]::Create()
    try { $taskActual = [BitConverter]::ToString($taskHasher.ComputeHash($taskStream)).Replace('-','') }
    finally { $taskStream.Dispose(); $taskHasher.Dispose() }
    if ($taskActual -ne $Expected) {
        throw ('File changed or incomplete: ' + $Relative + '. Extract a fresh copy of the ZIP.')
    }
}
function Read-Connection {
    if (!(Get-Command Get-PnpDevice -ErrorAction SilentlyContinue)) {
        throw 'Get-PnpDevice unavailable. Use Windows PowerShell 5.1 on Windows 10/11 x64.'
    }
    $taskA = @(); $taskB = @(); $taskDevices = @()
    for ($taskTry = 0; $taskTry -lt 4; $taskTry++) {
        $taskDevices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'VID_0403&PID_6042' })
        $taskA = @($taskDevices | Where-Object { $_.InstanceId.Contains('&MI_00\') })
        $taskB = @($taskDevices | Where-Object { $_.InstanceId.Contains('&MI_01\') })
        if ($taskA.Count -eq 1 -and $taskB.Count -eq 1 -and $taskA[0].Status -eq 'OK' -and $taskB[0].Status -eq 'OK') { break }
        if ($taskTry -lt 3) { Write-Host 'Waiting for USB-JTAG interfaces...'; Start-Sleep -Seconds 1 }
    }
    if ($taskDevices.Count) { $taskDevices | Format-Table Status,FriendlyName,InstanceId -AutoSize | Out-Host }
    if ($taskA.Count -ne 1 -or $taskB.Count -ne 1 -or $taskA[0].Status -ne 'OK' -or $taskB[0].Status -ne 'OK') {
        throw 'USB-JTAG not ready. Power the board and connect its DOWNLOAD USB port with a data cable. Replug/wait, then run 03_check_connection.cmd. The LED panels are NOT required for downloading.'
    }
    $taskServiceA = (Get-PnpDeviceProperty -InstanceId $taskA[0].InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction Stop).Data
    $taskServiceB = (Get-PnpDeviceProperty -InstanceId $taskB[0].InstanceId -KeyName DEVPKEY_Device_Service -ErrorAction Stop).Data
    if ($taskServiceA -ne 'WINUSB' -or $taskServiceB -ne 'FTDIBUS') {
        throw ('Driver mismatch: Interface A=' + $taskServiceA + ', Interface B=' + $taskServiceB + '. This portable downloader needs A/MI_00=WinUSB and B/MI_01=FTDIBUS. Read 03_USB驱动与故障排查.md. This script NEVER changes drivers.')
    }
    Write-Host 'USB_DRIVER_CHECK_PASSED: A=WINUSB, B=FTDIBUS' -ForegroundColor Green
    return [pscustomobject]@{interface_a=$taskA[0].InstanceId; interface_b=$taskB[0].InstanceId; service_a=$taskServiceA; service_b=$taskServiceB}
}
function Run-OpenOcd([string]$Config, [string]$Prefix) {
    $taskExe = Package-Path 'hardware/openocd/bin/openocd.exe'
    $taskOut = Join-Path $taskRunDir ($Prefix + '.stdout.log')
    $taskErr = Join-Path $taskRunDir ($Prefix + '.stderr.log')
    $taskProcess = Start-Process -FilePath $taskExe -ArgumentList @('-f',$Config) -WorkingDirectory (Package-Path 'sram') `
        -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput $taskOut -RedirectStandardError $taskErr
    $taskLog = (@(Get-Content -LiteralPath $taskOut -ErrorAction SilentlyContinue) + @(Get-Content -LiteralPath $taskErr -ErrorAction SilentlyContinue)) -join "`n"
    [IO.File]::WriteAllText((Join-Path $taskRunDir ($Prefix + '.log')), $taskLog, (New-Object Text.UTF8Encoding($false)))
    Write-Host $taskLog
    if ($taskProcess.ExitCode -ne 0) { throw ('OpenOCD failed; inspect ' + $taskRunDir) }
    return $taskLog
}
try {
    if ($ValidateOnly -and $CheckConnection) { throw 'Choose only one of -ValidateOnly / -CheckConnection.' }
    if (![Environment]::Is64BitOperatingSystem) { throw 'This tool bundle requires Windows x64.' }
    Write-Host 'Verifying package files and fixed SRAM version...'
    $taskManifest = Read-Json (Join-Path $taskRoot 'MANIFEST_SHA256.json')
    foreach ($taskEntry in $taskManifest.PSObject.Properties) { Assert-Hash $taskEntry.Name $taskEntry.Value }
    $taskMeta = Read-Json (Join-Path $taskRoot 'VERSION.json')
    if ($taskMeta.candidate -ne 'sc520_cal_final_2026-11-01' -or !$taskMeta.sram_only -or $taskMeta.flash_commands_included) { throw 'Unexpected package identity.' }
    # The complete source is an optional nested ZIP to keep the runnable
    # handoff extractable under Windows MAX_PATH. Build evidence is at root.
    $taskBuild = Read-Json (Package-Path 'evidence/build_receipt.json')
    $taskSim = Read-Json (Package-Path 'evidence/simulation_receipt.json')
    if (!$taskBuild.completed -or !$taskBuild.timing_passed -or !$taskSim.all_passed -or $taskSim.suites.Count -ne 40) { throw 'Validated build/simulation evidence missing.' }
    if ($taskBuild.setup_wns_ns -lt 0 -or $taskBuild.hold_wns_ns -lt 0 -or $taskBuild.setup_tns_ns -ne 0 -or $taskBuild.hold_tns_ns -ne 0) { throw 'Final timing is not passing.' }
    foreach ($taskKind in @('slice','eram','dsp')) {
        if ($taskBuild.$taskKind -gt $taskBuild.($taskKind + '_capacity')) { throw ('Resource overflow: ' + $taskKind) }
    }
    if (!$taskMeta.source_snapshot_included) { throw 'Package metadata does not identify the optional source snapshot.' }
    Assert-Hash 'sram/demo.bit' $taskBuild.bit_sha256
    Assert-Hash 'sram/demo.svf' $taskMeta.svf_sha256
    Assert-Hash 'sram/done.svf' $taskMeta.done_svf_sha256
    Assert-Hash 'evidence/final_area.rpt' $taskBuild.area_sha256
    Assert-Hash 'evidence/final_timing.rpt' $taskBuild.timing_sha256
    if ($taskMeta.bit_sha256 -ne $taskBuild.bit_sha256) { throw 'Metadata/build bitstream mismatch.' }
    $taskArea = Get-Content -LiteralPath (Package-Path 'evidence/final_area.rpt') -Raw
    if ($taskArea -notmatch 'O_ws2812_data\s+OUTPUT\s+P5\s+LVCMOS33') { throw 'Expected panel output P5 missing in final routed IO.' }
    Write-Host ('PACKAGE_VALIDATED: ' + $taskMeta.candidate + '; 40 suites passed; SRAM only.') -ForegroundColor Green
    if ($CheckConnection) {
        $taskConnection = Read-Connection
        Write-Host 'CONNECTION_CHECK_ONLY: no JTAG scan, no SRAM download, no Flash write.' -ForegroundColor Green
        exit 0
    }
    if (!$ValidateOnly) { $taskConnection = Read-Connection }
    $taskStamp = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('yyyyMMdd_HHmmss_fff')
    $taskRunDir = Join-Path $taskRoot ('logs/' + $taskStamp + '_' + [Guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory($taskRunDir) | Out-Null
    if ($ValidateOnly) {
        # This config has no init and exits before any USB/JTAG access.
        $taskLog = Run-OpenOcd 'verify.cfg' 'offline_runtime'
        if (!$taskLog.Contains('PORTABLE_CONFIG_OK_NO_HARDWARE')) { throw 'Offline OpenOCD runtime check failed.' }
        Write-Host 'OFFLINE_VALIDATION_PASSED_NO_HARDWARE_ACCESSED' -ForegroundColor Green
        exit 0
    }
    Write-Host 'Downloading the validated design into volatile SRAM and checking DONE...'
    $taskLog = Run-OpenOcd 'program.cfg' 'sram'
    if (!$taskLog.Contains('SRAM_AND_DONE_PASSED') -or $taskLog -notmatch '(?i)tap/device found:\s*0x4808f0e7') {
        throw 'SRAM/DONE or target identity verification incomplete.'
    }
    $taskReceipt = [ordered]@{
        timestamp=[DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(8)).ToString('o')
        candidate=$taskMeta.candidate; bit_sha256=$taskMeta.bit_sha256; sram_downloaded=$true
        done_passed=$true; flash_written=$false; visual_accepted=$false; white_capture_pending=$true
        jtag_id='0x4808F0E7'; connection=$taskConnection; log_directory=$taskRunDir
    }
    [IO.File]::WriteAllText((Join-Path $taskRunDir 'receipt.json'), ($taskReceipt | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Write-Host 'SUCCESS: SRAM and DONE passed. FLASH WAS NOT WRITTEN.' -ForegroundColor Green
    Write-Host 'Wait 10 s. Short K2 -> RGB. Cover view with uniform white paper; hold K1+K2 ~2 s, release both; keep white still ~1 s until CAL ON.'
    Write-Host 'Wall defaults OFF. Hold K3 ~2 s to enable; clear the scene and short K3 to capture its background.'
    Write-Host ('Receipt: ' + (Join-Path $taskRunDir 'receipt.json'))
    exit 0
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    if ($taskRunDir) { Write-Host ('Logs: ' + $taskRunDir) }
    Write-Host 'No successful SRAM result is claimed. Do not change wiring while powered.'
    exit 1
}
