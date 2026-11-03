param([ValidateSet('high','ultra')][string]$Effort='high',[string]$TdRoot='D:\AnlogicTD_6.2.1_Engineer_6.2.168.116')
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskProject=Join-Path $taskRoot 'candidate/sc520_shapes'
$taskReceiptPath=Join-Path $taskRoot 'reports/build_receipt.json'
$taskReceipt=Get-Content -LiteralPath $taskReceiptPath -Raw | ConvertFrom-Json
if(!$taskReceipt.completed){throw 'Need a completed routed build first'}
foreach($taskEntry in $taskReceipt.source_sha256.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $taskProject $taskEntry.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskEntry.Value){throw ('Changed source: '+$taskEntry.Name)}}
$taskRun=Join-Path $taskProject 'td_project/camera_to_dsi_display_Runs/phy_1'
$taskScript=(Join-Path $PSScriptRoot 'close_timing.tcl').Replace('\','/')
$taskLaunch="set taskEffort $Effort`nif {[catch {source {$taskScript}} message]} {puts stderr `"FLOW_FAILED: `$message`"; exit 1}`nexit 0`n"
[IO.File]::WriteAllText((Join-Path $taskRun 'postopt_launch.tcl'),$taskLaunch,(New-Object Text.UTF8Encoding($false)))
$taskStamp=[DateTimeOffset]::Now.ToString('yyyyMMdd_HHmmss')
$taskLog=Join-Path $taskRoot ('reports/td_postopt_'+$taskStamp+'_'+$Effort+'.log')
$taskStarted=Get-Date
$taskReceipt.timing_passed=$false
[IO.File]::WriteAllText($taskReceiptPath,($taskReceipt|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Push-Location $taskRun
try{& (Join-Path $TdRoot 'bin/td_commands_prompt.exe') postopt_launch.tcl *> $taskLog;$taskExit=$LASTEXITCODE}finally{Pop-Location}
$taskText=Get-Content -LiteralPath $taskLog -Raw
if($taskExit -ne 0 -or !$taskText.Contains('POST_ROUTE_TIMING_AND_BIT_PASSED') -or $taskText -match '\bERROR\b'){throw ('Post-route closure failed; timing remains unapproved: '+$taskLog)}
$taskTiming=Join-Path $taskRun 'final_timing.rpt'
$taskArea=Join-Path $taskRun 'camera_to_dsi_display_phy.area'
$taskBit=Join-Path $taskRun 'camera_to_dsi_display.bit'
if((Get-Item -LiteralPath $taskBit).LastWriteTime -lt $taskStarted){throw 'Stale postopt bit'}
$taskMatch=[regex]::Match((Get-Content -LiteralPath $taskTiming -Raw),'SWNS:\s*([\-\d.]+)ns, STNS:\s*([\-\d.]+)ns\s+HWNS:\s*([\-\d.]+)ns, HTNS:\s*([\-\d.]+)ns')
if(!$taskMatch.Success){throw 'Missing final timing'}
$taskReceipt.setup_wns_ns=[double]$taskMatch.Groups[1].Value;$taskReceipt.setup_tns_ns=[double]$taskMatch.Groups[2].Value
$taskReceipt.hold_wns_ns=[double]$taskMatch.Groups[3].Value;$taskReceipt.hold_tns_ns=[double]$taskMatch.Groups[4].Value
$taskAreaText=Get-Content -LiteralPath $taskArea -Raw
foreach($taskResource in @('slice','eram','dsp')){
 $taskRes=[regex]::Match($taskAreaText,'(?m)^#'+$taskResource+'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%')
 if(!$taskRes.Success){throw 'Resource summary missing'}
 $taskReceipt.$taskResource=[int]$taskRes.Groups[1].Value
}
if($taskAreaText -notmatch 'O_ws2812_data\s+OUTPUT\s+P5\s+LVCMOS33'){throw 'Wrong output pin'}
$taskReceipt.bit_sha256=(Get-FileHash -LiteralPath $taskBit -Algorithm SHA256).Hash.ToLowerInvariant()
$taskReceipt.timing_sha256=(Get-FileHash -LiteralPath $taskTiming -Algorithm SHA256).Hash.ToLowerInvariant()
$taskReceipt.area_sha256=(Get-FileHash -LiteralPath $taskArea -Algorithm SHA256).Hash.ToLowerInvariant()
$taskReceipt.timing_passed=$taskReceipt.setup_wns_ns -ge 0 -and $taskReceipt.hold_wns_ns -ge 0 -and $taskReceipt.setup_tns_ns -eq 0 -and $taskReceipt.hold_tns_ns -eq 0
if(!$taskReceipt.timing_passed){throw 'Final postopt timing still violates'}
foreach($taskEntry in $taskReceipt.source_sha256.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $taskProject $taskEntry.Name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskEntry.Value){throw ('Source changed during closure: '+$taskEntry.Name)}}
$taskReceipt.run_logs | Add-Member -NotePropertyName postopt -NotePropertyValue $taskLog -Force
$taskReceipt | Add-Member -NotePropertyName postopt_effort -NotePropertyValue $Effort -Force
$taskReceipt.PSObject.Properties.Remove('failure')
$taskReceipt.finished=[DateTimeOffset]::Now.ToString('o')
[IO.File]::WriteAllText($taskReceiptPath,($taskReceipt|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
Write-Output 'INTERACTIVE_POST_ROUTE_BUILD_AND_TIMING_PASSED'
