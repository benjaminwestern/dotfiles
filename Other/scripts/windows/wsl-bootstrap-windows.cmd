@echo off
setlocal EnableExtensions
call "%~dp0bootstrap-windows.cmd" wsl %*
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
