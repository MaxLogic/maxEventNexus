@echo off
setlocal

set SCRIPT_DIR=%~dp0
pushd "%SCRIPT_DIR%"
call build-delphi.bat tests\MaxEventNexusTests.dproj
set EXITCODE=%ERRORLEVEL%
popd

exit /b %EXITCODE%
