@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<benchmark-csv^> [threshold-csv]
  exit /b 2
)

set "lCsvPath=%~1"
set "lThresholdPath=%~2"
if "%lThresholdPath%"=="" set "lThresholdPath=bench\scheduler-thresholds.csv"

if not exist "%lCsvPath%" (
  echo ERROR: benchmark CSV not found: %lCsvPath%
  exit /b 2
)

if not exist "%lThresholdPath%" (
  echo ERROR: threshold CSV not found: %lThresholdPath%
  exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$lCsvPath = Resolve-Path '%lCsvPath%';" ^
  "$lThresholdPath = Resolve-Path '%lThresholdPath%';" ^
  "$lThresholdRows = Import-Csv -Path $lThresholdPath;" ^
  "if (-not $lThresholdRows) { Write-Error 'Threshold CSV has no data rows.'; exit 2 }" ^
  "$lThresholdByKey = @{};" ^
  "foreach ($lRow in $lThresholdRows) {" ^
  "  $lKey = ($lRow.scheduler + '|' + $lRow.delivery).ToLowerInvariant();" ^
  "  $lThresholdByKey[$lKey] = $lRow;" ^
  "}" ^
  "$lRows = Import-Csv -Path $lCsvPath;" ^
  "if (-not $lRows) { Write-Error 'Benchmark CSV has no data rows.'; exit 2 }" ^
  "$lFailed = $false;" ^
  "foreach ($lRow in $lRows) {" ^
  "  $lKey = ($lRow.scheduler + '|' + $lRow.delivery).ToLowerInvariant();" ^
  "  if ($lRow.status -ne 'ok') {" ^
  "    Write-Host ('FAIL: scheduler={0} delivery={1} status={2} error={3}' -f $lRow.scheduler, $lRow.delivery, $lRow.status, $lRow.error);" ^
  "    $lFailed = $true;" ^
  "    continue;" ^
  "  }" ^
  "  if (-not $lThresholdByKey.ContainsKey($lKey)) {" ^
  "    Write-Host ('FAIL: missing threshold row for scheduler={0} delivery={1}' -f $lRow.scheduler, $lRow.delivery);" ^
  "    $lFailed = $true;" ^
  "    continue;" ^
  "  }" ^
  "  $lThreshold = $lThresholdByKey[$lKey];" ^
  "  [double]$lThroughput = $lRow.avg_throughput_evt_s;" ^
  "  [double]$lP95 = $lRow.p95_us;" ^
  "  [double]$lP99 = $lRow.p99_us;" ^
  "  [double]$lAvg = $lRow.avg_us;" ^
  "  if ($lThroughput -lt [double]$lThreshold.min_throughput_evt_s) {" ^
  "    Write-Host ('FAIL: scheduler={0} delivery={1} throughput {2} < min {3}' -f $lRow.scheduler, $lRow.delivery, $lThroughput, $lThreshold.min_throughput_evt_s);" ^
  "    $lFailed = $true;" ^
  "  }" ^
  "  if ($lP95 -gt [double]$lThreshold.max_p95_us) {" ^
  "    Write-Host ('FAIL: scheduler={0} delivery={1} p95 {2} > max {3}' -f $lRow.scheduler, $lRow.delivery, $lP95, $lThreshold.max_p95_us);" ^
  "    $lFailed = $true;" ^
  "  }" ^
  "  if ($lP99 -gt [double]$lThreshold.max_p99_us) {" ^
  "    Write-Host ('FAIL: scheduler={0} delivery={1} p99 {2} > max {3}' -f $lRow.scheduler, $lRow.delivery, $lP99, $lThreshold.max_p99_us);" ^
  "    $lFailed = $true;" ^
  "  }" ^
  "  if ($lAvg -gt [double]$lThreshold.max_avg_us) {" ^
  "    Write-Host ('FAIL: scheduler={0} delivery={1} avg {2} > max {3}' -f $lRow.scheduler, $lRow.delivery, $lAvg, $lThreshold.max_avg_us);" ^
  "    $lFailed = $true;" ^
  "  }" ^
  "}" ^
  "if ($lFailed) { exit 1 }" ^
  "Write-Host ('Benchmark thresholds passed: {0} row(s) checked using {1}' -f $lRows.Count, $lThresholdPath)"

set "lExitCode=%ERRORLEVEL%"
if not "%lExitCode%"=="0" exit /b %lExitCode%
exit /b 0
