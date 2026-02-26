@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0report-api-test-coverage.ps1" %*
set "lExitCode=%ERRORLEVEL%"
exit /b %lExitCode%
