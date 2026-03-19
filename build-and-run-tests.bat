@echo off
setlocal

pushd "%~dp0"

rem Run build, tests, static analysis, and analysis-threshold gate in one default flow.
if not exist build\analysis mkdir build\analysis

call build-delphi.bat tests\MaxEventNexusTests.dproj -config Debug -enforce-diagnostics-policy -diagnostics-policy build\diagnostics-policy.regex && ^
call tests\MaxEventNexusTests.exe && ^
call build-delphi.bat bench\SchedulerCompare.dproj -config Release -enforce-diagnostics-policy -diagnostics-policy build\diagnostics-policy.regex && ^
call bench\SchedulerCompare.exe --events=200 --consumers=1 --runs=1 --delivery=async --metrics-readers=0 --metrics-reads=0 --framework=weak --csv=build\analysis\benchmark-smoke.csv && ^
call build\check-benchmark-smoke.bat build\analysis\benchmark-smoke.csv && ^
call build-static-analysis.bat && ^
call build\check-analysis-thresholds.bat build\analysis\summary.md build\analysis\analysis-thresholds.csv && ^
call build\report-api-test-coverage.bat -EnforceTarget

rem Preserve the exit code from whichever stage ran last.
set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
