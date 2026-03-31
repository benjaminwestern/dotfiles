@echo off
setlocal EnableExtensions

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

call "%~dp0bootstrap-windows.cmd" audit %*
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%

:usage
echo Usage:
echo   audit-windows.cmd [-Section ^<tools^|shell^|configs^|signing^|zscaler^|all^>] [-Json] [-PopulateState]
echo.
echo Safe wrapper for audit-windows.ps1. Routes through bootstrap-windows.cmd
echo so the local signing and PowerShell 7 precursor path run before the
echo audit implementation.
echo.
echo Examples:
echo   audit-windows.cmd -Section tools
echo   audit-windows.cmd -Json
echo   audit-windows.cmd -PopulateState
endlocal & exit /b 0
