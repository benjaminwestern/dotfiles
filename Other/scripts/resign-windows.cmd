@echo off
setlocal EnableExtensions

call "%~dp0bootstrap-windows.cmd" resign %*
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%
