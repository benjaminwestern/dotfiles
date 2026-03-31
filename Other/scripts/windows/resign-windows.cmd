@echo off
setlocal EnableExtensions

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

call "%~dp0bootstrap-windows.cmd" resign %*
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%

:usage
echo Usage:
echo   resign-windows.cmd [-DryRun]
echo.
echo Re-signs Scoop scripts, mise scripts, repo-local Windows bootstrap
echo scripts, and the current PowerShell profile.
echo.
echo Examples:
echo   resign-windows.cmd
echo   resign-windows.cmd -DryRun
endlocal & exit /b 0
