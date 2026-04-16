@echo off
setlocal

set "lDirectCsv=build\analysis\mailbox-direct.csv"
set "lBusCsv=build\analysis\mailbox-bus.csv"

if not exist build\analysis mkdir build\analysis
if exist "%lDirectCsv%" del /q "%lDirectCsv%" >nul 2>&1
if exist "%lBusCsv%" del /q "%lBusCsv%" >nul 2>&1

bench\BenchHarness.exe --mode=mailbox-direct --producers=4 --events=50000 --timeout-ms=30000 --csv=%lDirectCsv%
if errorlevel 1 exit /b %ERRORLEVEL%

bench\BenchHarness.exe --mode=mailbox-bus --producers=4 --events=50000 --timeout-ms=30000 --csv=%lBusCsv%
if errorlevel 1 exit /b %ERRORLEVEL%

if not exist "%lDirectCsv%" (
  echo ERROR: mailbox direct benchmark did not emit %lDirectCsv%
  exit /b 1
)

if not exist "%lBusCsv%" (
  echo ERROR: mailbox bus benchmark did not emit %lBusCsv%
  exit /b 1
)

echo Mailbox benchmark outputs:
echo   %lDirectCsv%
echo   %lBusCsv%

exit /b 0
