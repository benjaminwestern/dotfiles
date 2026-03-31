@echo off
setlocal EnableExtensions

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

call "%~dp0bootstrap-windows.cmd" foundation %*
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%

:usage
echo Usage:
echo   foundation-windows.cmd [-Mode ^<setup^|ensure^|update^|personal^>] [PowerShell args]
echo.
echo Safe wrapper for foundation-windows.ps1. Routes through bootstrap-windows.cmd
echo so the local signing and PowerShell 7 precursor path run before the
echo foundation implementation.
echo.
echo Examples:
echo   foundation-windows.cmd -Mode ensure -Profile_ work -Personal
echo   foundation-windows.cmd -Mode update -DryRun
endlocal & exit /b 0
