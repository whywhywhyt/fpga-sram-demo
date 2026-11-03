param([string]$TdRoot='D:\AnlogicTD_6.2.1_Engineer_6.2.168.116',[switch]$Resume)
$ErrorActionPreference='Stop'
# TD 6.2.1 has legacy Windows path limits in XML/IP includes. Enter the
# same workspace through a verified short drive before invoking TD.
if($PSScriptRoot.StartsWith('D:\workspace\fpga\',[StringComparison]::OrdinalIgnoreCase)){
 if(!(Test-Path -LiteralPath 'X:/contest/final_solution')){
  & subst.exe X: 'D:\workspace\fpga'
  if($LASTEXITCODE -ne 0){throw 'Cannot create short TD workspace drive'}
 }
 $taskShortScript='X:'+ $PSCommandPath.Substring('D:\workspace\fpga'.Length)
 if((Get-FileHash -LiteralPath $taskShortScript).Hash -ne (Get-FileHash -LiteralPath $PSCommandPath).Hash){throw 'X: is not the intended workspace'}
 & $taskShortScript -TdRoot $TdRoot -Resume:$Resume
 return
}
$taskRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskProject=Join-Path $taskRoot 'candidate/sc520_shapes'
$taskTd=Join-Path $TdRoot 'bin/td_commands_prompt.exe'
$taskStamp=[DateTimeOffset]::Now.ToString('yyyyMMdd_HHmmss')
$taskPrevious=$null
if($Resume){
 $taskPrevious=Get-Content -LiteralPath (Join-Path $taskRoot 'reports/build_receipt.json') -Raw | ConvertFrom-Json
 if($taskPrevious.completed -or $taskPrevious.stages.Count -ne 1 -or $taskPrevious.stages[0] -ne 'syn_1'){throw 'Resume requires interrupted physical build with completed synthesis'}
 $taskRunning=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'td_commands_prompt.exe' })
 # Different candidates may run concurrently. Reject an active process whose
 # working source is this candidate when its command line identifies it.
 if(@($taskRunning | Where-Object {$_.CommandLine -like ('*'+$taskPrevious.project+'*')}).Count){throw 'Candidate build is still running'}
}
$taskReceipt=[ordered]@{project='sc520_cal_final_2026-11-01';td_version='6.2.168116';started=[DateTimeOffset]::Now.ToString('o');completed=$false;timing_passed=$false;stages=@();source_sha256=@{};run_logs=@{};sram_downloaded=$false;hardware_tested=$false;flash_written=$false}
foreach($taskFolder in @('user_source','td_project/al_ip')) {
 Get-ChildItem -LiteralPath (Join-Path $taskProject $taskFolder) -File -Recurse | ForEach-Object {
  $taskRel=$_.FullName.Substring($taskProject.Length+1).Replace('\','/')
  $taskReceipt.source_sha256[$taskRel]=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
 }
}
foreach($taskRel in @('td_project/camera_to_dsi_display.al','td_project/camera_to_dsi_display.sdc')){
 $taskReceipt.source_sha256[$taskRel]=(Get-FileHash -LiteralPath (Join-Path $taskProject $taskRel) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$taskReceiptPath=Join-Path $taskRoot 'reports/build_receipt.json'
if($Resume){
 if($taskPrevious.project -ne $taskReceipt.project -or @($taskPrevious.source_sha256.PSObject.Properties).Count -ne $taskReceipt.source_sha256.Count){throw 'Resume project/source inventory mismatch'}
 foreach($taskEntry in $taskReceipt.source_sha256.GetEnumerator()){
  if($taskPrevious.source_sha256.($taskEntry.Key) -ne $taskEntry.Value){throw ('Source changed since synthesis: '+$taskEntry.Key)}
 }
 $taskSynLog=$taskPrevious.run_logs.syn_1
 $taskSynDb=Join-Path $taskProject 'td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display_gate.db'
 $taskSynText=Get-Content -LiteralPath $taskSynLog -Raw
 if(!$taskSynText.Contains('FLOW_SCRIPT_COMPLETED') -or $taskSynText -match '\bERROR\b' -or !(Test-Path -LiteralPath $taskSynDb)){throw 'Original synthesis completion evidence missing'}
 if((Get-Item -LiteralPath $taskSynDb).LastWriteTime -lt [DateTimeOffset]::Parse($taskPrevious.started).LocalDateTime){throw 'Stale synthesis database'}
 Copy-Item -LiteralPath $taskReceiptPath -Destination (Join-Path $taskRoot ('reports/interrupted_build_receipt_'+$taskStamp+'.json'))
 $taskReceipt.stages=@('syn_1');$taskReceipt.run_logs.syn_1=$taskSynLog
 $taskReceipt.resumed_from=$taskPrevious.started
 $taskReceipt.reused_synthesis_db_sha256=(Get-FileHash -LiteralPath $taskSynDb -Algorithm SHA256).Hash.ToLowerInvariant()
}

# TD's standalone stage runner consumes a stage-local exported .prj. Rebuild
# it from THIS candidate's .al on every invocation; never copy stale sources.
$taskAlText=Get-Content -LiteralPath (Join-Path $taskProject 'td_project/camera_to_dsi_display.al') -Raw -Encoding UTF8
$taskSourceBlock=[regex]::Match($taskAlText,'(?s)<Source_Files>.*?</Source_Files>').Value
if(!$taskSourceBlock){throw 'Project source list missing'}
$taskSourceBlock=[regex]::Replace($taskSourceBlock,'Path="([^"]+)"', {param($m) 'Path="../../'+$m.Groups[1].Value+'"'})
$taskStageProject='<?xml version="1.0" encoding="UTF-8"?>'+"`n"+'<Project Version="3" Minor="2"><TD_Encoding>UTF-8</TD_Encoding><TD_Version>6.2.168116</TD_Version><Name>camera_to_dsi_display</Name><HardWare><Family>PH1</Family><Device>PH1P35MDG324</Device><Speed>-3</Speed></HardWare>'+$taskSourceBlock+'<FileSets><FileSet Name="design_1" Type="DesignFiles"></FileSet><FileSet Name="constraint_1" Type="ConstrainFiles"></FileSet></FileSets><TOP_MODULE><LABEL>design_top_wrapper</LABEL><MODULE>design_top_wrapper</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE><Property></Property><Device_Settings></Device_Settings><Configurations><Control0><mclk_freq>33MHz</mclk_freq></Control0><FeatureRow><boot_mode>mspix4</boot_mode></FeatureRow></Configurations></Project>'
foreach($taskStage in @('syn_1','phy_1')){
 $taskExport=Join-Path $taskProject ('td_project/camera_to_dsi_display_Runs/'+$taskStage+'/camera_to_dsi_display.prj')
 [IO.File]::WriteAllText($taskExport,$taskStageProject,(New-Object Text.UTF8Encoding($false)))
}
function Save-Receipt {[IO.File]::WriteAllText($taskReceiptPath,($taskReceipt|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))}
Save-Receipt
try {
foreach($taskStage in @('syn_1','phy_1')) {
  if($Resume -and $taskStage -eq 'syn_1'){Write-Output 'VERIFIED_SYNTHESIS_REUSED';continue}
  $taskRun=Join-Path $taskProject ('td_project/camera_to_dsi_display_Runs/'+$taskStage)
  $taskLog=Join-Path $taskRoot ('reports/td_'+$taskStamp+'_'+$taskStage+'.log')
  $taskStarted=Get-Date
  Push-Location $taskRun
  try {& $taskTd 'run_flow.tcl' *> $taskLog;$taskExit=$LASTEXITCODE} finally {Pop-Location}
  $taskText=Get-Content -LiteralPath $taskLog -Raw -Encoding UTF8
  if($taskExit -ne 0 -or -not $taskText.Contains('FLOW_SCRIPT_COMPLETED') -or $taskText -match '\bERROR\b'){throw ('TD stage failed: '+$taskStage+'; '+$taskLog)}
  $taskArtifact=if($taskStage -eq 'syn_1'){'camera_to_dsi_display_gate.db'}else{'camera_to_dsi_display.bit'}
  $taskOutput=Join-Path $taskRun $taskArtifact
  if((Get-Item -LiteralPath $taskOutput).LastWriteTime -lt $taskStarted){throw ('Stale artifact: '+$taskOutput)}
  foreach($taskEntry in $taskReceipt.source_sha256.GetEnumerator()){
   if((Get-FileHash -LiteralPath (Join-Path $taskProject $taskEntry.Key) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskEntry.Value){throw ('Source changed during build: '+$taskEntry.Key)}
  }
  $taskReceipt.stages+=@($taskStage);$taskReceipt.run_logs[$taskStage]=$taskLog;Save-Receipt
  Write-Output ('INTERACTIVE_'+$taskStage+'_COMPLETED')
 }
 $taskPhy=Join-Path $taskProject 'td_project/camera_to_dsi_display_Runs/phy_1'
 $taskTiming=Join-Path $taskPhy 'final_timing.rpt'
 $taskArea=Join-Path $taskPhy 'camera_to_dsi_display_phy.area'
 $taskTimingText=Get-Content -LiteralPath $taskTiming -Raw
 $taskMatch=[regex]::Match($taskTimingText,'SWNS:\s*([\-\d.]+)ns, STNS:\s*([\-\d.]+)ns\s+HWNS:\s*([\-\d.]+)ns, HTNS:\s*([\-\d.]+)ns')
 if(!$taskMatch.Success){throw 'Final timing summary missing'}
 $taskReceipt.setup_wns_ns=[double]$taskMatch.Groups[1].Value;$taskReceipt.setup_tns_ns=[double]$taskMatch.Groups[2].Value
 $taskReceipt.hold_wns_ns=[double]$taskMatch.Groups[3].Value;$taskReceipt.hold_tns_ns=[double]$taskMatch.Groups[4].Value
 $taskAreaText=Get-Content -LiteralPath $taskArea -Raw
 foreach($taskResource in @('slice','eram','dsp')){
  $taskRes=[regex]::Match($taskAreaText,'(?m)^#'+$taskResource+'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%')
  if(!$taskRes.Success){throw ('Resource missing: '+$taskResource)}
  $taskReceipt[$taskResource]=[int]$taskRes.Groups[1].Value;$taskReceipt[$taskResource+'_capacity']=[int]$taskRes.Groups[2].Value
 }
 if($taskAreaText -notmatch 'O_ws2812_data\s+OUTPUT\s+P5\s+LVCMOS33'){throw 'Final lamp data pin is not P5'}
 $taskReceipt.bit_sha256=(Get-FileHash -LiteralPath (Join-Path $taskPhy 'camera_to_dsi_display.bit') -Algorithm SHA256).Hash.ToLowerInvariant()
 $taskReceipt.timing_sha256=(Get-FileHash -LiteralPath $taskTiming -Algorithm SHA256).Hash.ToLowerInvariant()
 $taskReceipt.area_sha256=(Get-FileHash -LiteralPath $taskArea -Algorithm SHA256).Hash.ToLowerInvariant()
 $taskReceipt.completed=$true;$taskReceipt.finished=[DateTimeOffset]::Now.ToString('o')
 $taskReceipt.timing_passed=$taskReceipt.setup_wns_ns -ge 0 -and $taskReceipt.hold_wns_ns -ge 0 -and $taskReceipt.setup_tns_ns -eq 0 -and $taskReceipt.hold_tns_ns -eq 0
 Save-Receipt
 if(!$taskReceipt.timing_passed){& (Join-Path $PSScriptRoot 'close_timing.ps1') -TdRoot $TdRoot;return}
 Write-Output 'INTERACTIVE_BUILD_AND_TIMING_PASSED'
} catch {$taskReceipt.failure=$_.Exception.Message;Save-Receipt;throw}
