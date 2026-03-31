@echo off
setlocal EnableExtensions

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

call "%~dp0bootstrap-windows.cmd" personal %*
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%

:usage
echo Usage:
echo   personal-bootstrap-windows.cmd [PowerShell args]
echo.
echo Safe wrapper for personal-bootstrap-windows.ps1. Routes through
echo bootstrap-windows.cmd so the local signing path is applied before the
echo personal-layer implementation runs.
echo.
echo Examples:
echo   personal-bootstrap-windows.cmd
echo   personal-bootstrap-windows.cmd -DryRun
endlocal & exit /b 0
