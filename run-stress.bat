@echo off
setlocal

pushd "%~dp0"

call build-tests.bat || exit /b %ERRORLEVEL%
call tests\MaxEventNexusTests.exe --stress-suite
set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
