@echo off
setlocal EnableExtensions

set "ROOT_DIR=%~dp0"
set "PROJECT_PATH=%ROOT_DIR%tests\MaxEventNexusTests.dproj"
set "OUT_DIR=%ROOT_DIR%build\analysis"
set "SKILL_DIR=%STATIC_ANALYSIS_SKILL_DIR%"
set "PAL_EXE="

if not defined SKILL_DIR set "SKILL_DIR=%USERPROFILE%\.codex\skills\delphi-static-analysis"
if not exist "%SKILL_DIR%\doctor.bat" (
  for /f "usebackq delims=" %%I in (`wsl.exe wslpath -w "/home/%USERNAME%/.codex/skills/delphi-static-analysis" 2^>nul`) do (
    set "SKILL_DIR=%%I"
  )
)

if not exist "%PROJECT_PATH%" (
  echo ERROR: Missing project: %PROJECT_PATH%
  set "EXITCODE=2"
  goto :cleanup
)

if not exist "%SKILL_DIR%\doctor.bat" (
  echo ERROR: Missing doctor script: %SKILL_DIR%\doctor.bat
  set "EXITCODE=2"
  goto :cleanup
)

if not exist "%SKILL_DIR%\analyze.bat" (
  echo ERROR: Missing analyze script: %SKILL_DIR%\analyze.bat
  set "EXITCODE=2"
  goto :cleanup
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

call "%SKILL_DIR%\doctor.bat" "%PROJECT_PATH%" > "%OUT_DIR%\doctor.txt" 2>&1
if errorlevel 1 (
  type "%OUT_DIR%\doctor.txt"
  set "EXITCODE=2"
  goto :cleanup
)

set "DAK_OUT=%OUT_DIR%"
set "DAK_CLEAN=1"
set "DAK_WRITE_SUMMARY=1"

if defined PALCMD_PATH if exist "%PALCMD_PATH%" set "PAL_EXE=%PALCMD_PATH%"
if not defined PAL_EXE if exist "C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe" set "PAL_EXE=C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe"
if not defined PAL_EXE if exist "C:\Program Files\Peganza\Pascal Analyzer 9\PAL32\palcmd32.exe" set "PAL_EXE=C:\Program Files\Peganza\Pascal Analyzer 9\PAL32\palcmd32.exe"
if not defined PAL_EXE (
  for /f "usebackq delims=" %%I in (`where PALCMD.exe 2^>nul`) do (
    if not defined PAL_EXE set "PAL_EXE=%%I"
  )
)

if defined PAL_EXE (
  set "PA_PATH=%PAL_EXE%"
  set "DAK_PASCAL_ANALYZER=1"
) else (
  findstr /C:"PascalAnalyzer.Path=<empty>" "%OUT_DIR%\doctor.txt" >nul
  if %ERRORLEVEL%==0 (
    set "DAK_PASCAL_ANALYZER=0"
  ) else (
    set "DAK_PASCAL_ANALYZER=1"
  )
)

if not defined PAL_EXE if not defined DAK_PASCAL_ANALYZER (
  set "DAK_PASCAL_ANALYZER=0"
)

call "%SKILL_DIR%\analyze.bat" "%PROJECT_PATH%" > "%OUT_DIR%\analyze.log" 2>&1
set "ANALYZE_EXIT=%ERRORLEVEL%"

if not exist "%OUT_DIR%\summary.md" (
  type "%OUT_DIR%\analyze.log"
  set "EXITCODE=%ANALYZE_EXIT%"
  if "%EXITCODE%"=="0" set "EXITCODE=1"
  goto :cleanup
)

if not "%ANALYZE_EXIT%"=="0" (
  if exist "%OUT_DIR%\fixinsight\fixinsight.txt" (
    >> "%OUT_DIR%\summary.md" echo.
    >> "%OUT_DIR%\summary.md" echo Non-zero analyzer exit ^(%ANALYZE_EXIT%^)^ accepted because reports were produced.
  ) else (
    type "%OUT_DIR%\analyze.log"
    set "EXITCODE=%ANALYZE_EXIT%"
    goto :cleanup
  )
)

if exist "%OUT_DIR%\fixinsight\fixinsight.txt" (
  copy /Y "%OUT_DIR%\fixinsight\fixinsight.txt" "%OUT_DIR%\fixinsight.txt" >nul
) else (
  > "%OUT_DIR%\fixinsight.txt" echo TOOL_UNAVAILABLE: FixInsight report was not produced.
  >> "%OUT_DIR%\fixinsight.txt" echo See build/analysis/doctor.txt and build/analysis/analyze.log for details.
)

if exist "%OUT_DIR%\pascal-analyzer\pascal-analyzer.log" (
  copy /Y "%OUT_DIR%\pascal-analyzer\pascal-analyzer.log" "%OUT_DIR%\pascal-analyzer.txt" >nul
) else if exist "%OUT_DIR%\pascal-analyzer.log" (
  copy /Y "%OUT_DIR%\pascal-analyzer.log" "%OUT_DIR%\pascal-analyzer.txt" >nul
) else (
  > "%OUT_DIR%\pascal-analyzer.txt" echo TOOL_UNAVAILABLE: Pascal Analyzer was skipped or not configured.
  >> "%OUT_DIR%\pascal-analyzer.txt" echo See build/analysis/doctor.txt and build/analysis/summary.md for details.
)

echo Static analysis outputs:
echo   %OUT_DIR%\summary.md
echo   %OUT_DIR%\fixinsight.txt
echo   %OUT_DIR%\pascal-analyzer.txt
echo   %OUT_DIR%\doctor.txt
echo   %OUT_DIR%\analyze.log

set "EXITCODE=0"

:cleanup
if not defined EXITCODE set "EXITCODE=1"
endlocal & exit /b %EXITCODE%
