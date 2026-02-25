@echo off
setlocal

if "%~1"=="" (
  echo Usage: %~nx0 ^<analysis-summary-md^> [threshold-csv]
  exit /b 2
)

set "lSummaryPath=%~1"
set "lThresholdPath=%~2"
if "%lThresholdPath%"=="" set "lThresholdPath=build\analysis\analysis-thresholds.csv"

if not exist "%lSummaryPath%" (
  echo ERROR: analysis summary not found: %lSummaryPath%
  exit /b 2
)

if not exist "%lThresholdPath%" (
  echo ERROR: threshold CSV not found: %lThresholdPath%
  exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$lSummaryPath = Resolve-Path '%lSummaryPath%';" ^
  "$lThresholdPath = Resolve-Path '%lThresholdPath%';" ^
  "$lThresholdRows = Import-Csv -Path $lThresholdPath;" ^
  "if (-not $lThresholdRows) { Write-Error ('Threshold CSV has no data rows: ' + $lThresholdPath); exit 2 }" ^
  "$lMaxByCode = @{};" ^
  "foreach ($lRow in $lThresholdRows) {" ^
  "  $lCode = ('' + $lRow.code).Trim().ToUpperInvariant();" ^
  "  if ([string]::IsNullOrWhiteSpace($lCode)) { continue }" ^
  "  $lRawMax = ('' + $lRow.max_count).Trim();" ^
  "  [int]$lMaxCount = 0;" ^
  "  if (-not [int]::TryParse($lRawMax, [ref]$lMaxCount)) { Write-Error ('Invalid max_count for code ' + $lCode + ' in ' + $lThresholdPath + ': ' + $lRawMax); exit 2 }" ^
  "  $lMaxByCode[$lCode] = $lMaxCount;" ^
  "}" ^
  "if ($lMaxByCode.Count -eq 0) { Write-Error ('Threshold CSV has no usable code rows: ' + $lThresholdPath); exit 2 }" ^
  "$lFoundByCode = @{};" ^
  "$lPattern = '^\s*-\s*(?<Code>[A-Za-z]\d{3})\s*:\s*(?<Count>\d+)\s*$';" ^
  "foreach ($lLine in [System.IO.File]::ReadAllLines($lSummaryPath)) {" ^
  "  $lMatch = [Regex]::Match($lLine, $lPattern);" ^
  "  if (-not $lMatch.Success) { continue }" ^
  "  $lCode = $lMatch.Groups['Code'].Value.ToUpperInvariant();" ^
  "  $lCount = [int]$lMatch.Groups['Count'].Value;" ^
  "  $lFoundByCode[$lCode] = $lCount;" ^
  "}" ^
  "$lChecked = 0;" ^
  "$lFailed = $false;" ^
  "foreach ($lCode in $lMaxByCode.Keys) {" ^
  "  if (-not $lFoundByCode.ContainsKey($lCode)) {" ^
  "    Write-Host ('FAIL: summary missing code ' + $lCode);" ^
  "    $lFailed = $true;" ^
  "    continue;" ^
  "  }" ^
  "  $lCurrent = [int]$lFoundByCode[$lCode];" ^
  "  $lAllowed = [int]$lMaxByCode[$lCode];" ^
  "  if ($lCurrent -gt $lAllowed) {" ^
  "    Write-Host ('FAIL: code=' + $lCode + ' current=' + $lCurrent + ' max=' + $lAllowed);" ^
  "    $lFailed = $true;" ^
  "  }" ^
  "  $lChecked++;" ^
  "}" ^
  "if ($lChecked -eq 0) { Write-Error ('No threshold codes were checked against ' + $lSummaryPath); exit 2 }" ^
  "if ($lFailed) { exit 1 }" ^
  "Write-Host ('Analysis thresholds passed: ' + $lChecked + ' code(s) checked using ' + $lThresholdPath)"

set "lExitCode=%ERRORLEVEL%"
if not "%lExitCode%"=="0" exit /b %lExitCode%
exit /b 0
