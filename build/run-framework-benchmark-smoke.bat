@echo off
setlocal

set "lCsvPath=build\analysis\benchmark-framework-smoke.csv"

if not exist build\analysis mkdir build\analysis
if exist "%lCsvPath%" del /q "%lCsvPath%" >nul 2>&1

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop';" ^
  "$lExe = Resolve-Path 'bench\SchedulerCompare.exe';" ^
  "$lArgs = @('--skip-schedulers','--framework=weak','--events=2000','--consumers=2','--runs=1','--delivery=async','--max-inflight=0','--csv=%lCsvPath%');" ^
  "$lProc = Start-Process -FilePath $lExe -ArgumentList $lArgs -PassThru -NoNewWindow;" ^
  "if (-not $lProc.WaitForExit(30000)) { $lProc.Kill(); $lProc.WaitForExit(); exit 124 }" ^
  "exit $lProc.ExitCode"
if errorlevel 1 exit /b %ERRORLEVEL%

if not exist "%lCsvPath%" (
  echo ERROR: framework benchmark smoke did not emit %lCsvPath%
  exit /b 1
)

call build\check-benchmark-smoke.bat "%lCsvPath%" framework-only
if errorlevel 1 exit /b %ERRORLEVEL%

exit /b 0
