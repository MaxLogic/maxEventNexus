@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<benchmark-csv^> [full^|framework-only]
  exit /b 2
)

set "lCsvPath=%~1"
set "lMode=%~2"
if "%lMode%"=="" set "lMode=full"

if /I not "%lMode%"=="full" if /I not "%lMode%"=="framework-only" (
  echo ERROR: mode must be full or framework-only
  exit /b 2
)

if not exist "%lCsvPath%" (
  echo ERROR: benchmark CSV not found: %lCsvPath%
  exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$lCsvPath = Resolve-Path '%lCsvPath%';" ^
  "$lMode = '%lMode%';" ^
  "$lRows = Import-Csv -Path $lCsvPath;" ^
  "if (-not $lRows) { Write-Error 'Benchmark CSV has no data rows.'; exit 2 }" ^
  "$lColumns = $lRows[0].PSObject.Properties.Name;" ^
  "$lRequiredColumns = @('scenario','scheduler','delivery','consumers','events','runs','clock','percentile_method','status','error');" ^
  "foreach ($lName in $lRequiredColumns) {" ^
  "  if ($lColumns -notcontains $lName) { Write-Error ('Benchmark CSV missing required column: ' + $lName); exit 2 }" ^
  "}" ^
  "$lFrameworkRow = $lRows | Where-Object { $_.scenario -eq 'framework-compare' -and $_.scheduler -eq 'EventNexus(TTask-weak)' } | Select-Object -First 1;" ^
  "if (-not $lFrameworkRow) { Write-Error 'Missing framework-compare row for EventNexus(TTask-weak).'; exit 1 }" ^
  "if ($lFrameworkRow.status -ne 'ok') { Write-Error ('Framework row failed: ' + $lFrameworkRow.error); exit 1 }" ^
  "if ($lMode -eq 'full') {" ^
  "  $lExpectedSchedulers = @('raw-thread','maxAsync','TTask');" ^
  "  foreach ($lScheduler in $lExpectedSchedulers) {" ^
  "    $lRow = $lRows | Where-Object { $_.scenario -eq 'scheduler-compare' -and $_.scheduler -eq $lScheduler } | Select-Object -First 1;" ^
  "    if (-not $lRow) { Write-Error ('Missing scheduler-compare row for ' + $lScheduler); exit 1 }" ^
  "    if ($lRow.status -ne 'ok') { Write-Error ('Scheduler row failed for ' + $lScheduler + ': ' + $lRow.error); exit 1 }" ^
  "  }" ^
  "  Write-Host ('Benchmark smoke passed: {0} scheduler rows + framework row verified in {1}' -f $lExpectedSchedulers.Count, $lCsvPath)" ^
  "} else {" ^
  "  Write-Host ('Framework-only benchmark smoke passed: weak EventNexus row verified in {0}' -f $lCsvPath)" ^
  "}"

set "lExitCode=%ERRORLEVEL%"
if not "%lExitCode%"=="0" exit /b %lExitCode%
exit /b 0
