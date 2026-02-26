@echo off
setlocal

pushd "%~dp0"

rem Run build, tests, static analysis, and analysis-threshold gate in one default flow.
call build-delphi.bat tests\MaxEventNexusTests.dproj -config Debug -enforce-diagnostics-policy -diagnostics-policy build\diagnostics-policy.regex && ^
call tests\MaxEventNexusTests.exe && ^
call build-static-analysis.bat && ^
call build\check-analysis-thresholds.bat build\analysis\summary.md build\analysis\analysis-thresholds.csv && ^
call build\report-api-test-coverage.bat -EnforceTarget

rem Preserve the exit code from whichever stage ran last.
set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
