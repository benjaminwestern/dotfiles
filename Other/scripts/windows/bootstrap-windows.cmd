@echo off
setlocal EnableExtensions

for %%I in ("%~dp0.") do set "SCRIPT_DIR=%%~fI\"

set "TARGET=%SCRIPT_DIR%foundation-windows.ps1"
set "FORWARD_ARGS="

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

if /I "%~1"=="foundation" (
  shift
) else if /I "%~1"=="audit" (
  set "TARGET=%SCRIPT_DIR%audit-windows.ps1"
  shift
) else if /I "%~1"=="resign" (
  set "TARGET=%SCRIPT_DIR%resign-windows.ps1"
  shift
) else if /I "%~1"=="personal" (
  set "TARGET=%SCRIPT_DIR%personal-bootstrap-windows.ps1"
  shift
) else if /I "%~1"=="wsl" (
  set "TARGET=%SCRIPT_DIR%wsl-bootstrap-windows.ps1"
  shift
)

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

set "BOOTSTRAP_TARGET=%TARGET%"
set "SCRIPTS_ROOT=%SCRIPT_DIR%"
if not defined BOOTSTRAP_ROOT for %%I in ("%SCRIPT_DIR%..\..\..") do set "BOOTSTRAP_ROOT=%%~fI"

:collect_args
if "%~1"=="" goto run_target
set "FORWARD_ARGS=%FORWARD_ARGS% %1"
shift
goto collect_args

:run_target

powershell -NoLogo -NoProfile -Command "& { $ErrorActionPreference = 'Stop'; $effectivePolicy = Get-ExecutionPolicy; if ($effectivePolicy -eq 'Restricted') { if ((Get-ExecutionPolicy -Scope MachinePolicy) -ne 'Undefined' -or (Get-ExecutionPolicy -Scope UserPolicy) -ne 'Undefined') { throw 'PowerShell script execution is restricted by Group Policy.' }; Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force; $effectivePolicy = 'RemoteSigned' }; $scriptsRoot = [System.IO.Path]::GetFullPath('%SCRIPTS_ROOT%'); $scripts = @(Get-ChildItem $scriptsRoot -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue | Where-Object { $_.Length -ge 4 }); $scripts | ForEach-Object { Unblock-File -Path $_.FullName }; if ($effectivePolicy -eq 'AllSigned') { $cert = Get-ChildItem Cert:\CurrentUser\My -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq 'CN=LocalScoopSigner' -and $_.EnhancedKeyUsageList.FriendlyName -contains 'Code Signing' } | Select-Object -First 1; if (-not $cert) { Write-Host 'Creating local code-signing certificate (CN=LocalScoopSigner)...' -ForegroundColor Cyan; $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=LocalScoopSigner' -CertStoreLocation 'Cert:\CurrentUser\My' }; $cerPath = Join-Path $env:TEMP 'LocalScoopSigner.cer'; Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null; $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); if ($isAdmin) { certutil -f -addstore Root $cerPath | Out-Null } else { certutil -user -f -addstore Root $cerPath | Out-Null }; if ($LASTEXITCODE -ne 0) { throw 'Failed to trust LocalScoopSigner in a trusted root store.' }; certutil -user -f -addstore TrustedPublisher $cerPath | Out-Null; if ($LASTEXITCODE -ne 0) { throw 'Failed to trust LocalScoopSigner in CurrentUser TrustedPublisher.' }; Remove-Item $cerPath -ErrorAction SilentlyContinue; $scripts | ForEach-Object { Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null } } }"
if errorlevel 1 exit /b %ERRORLEVEL%

powershell -NoLogo -NoProfile -File "%TARGET%" %FORWARD_ARGS%
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%

:usage
echo Usage:
echo   bootstrap-windows.cmd [foundation^|audit^|personal^|wsl^|resign] [PowerShell args]
echo.
echo Targets:
echo   foundation  Runs foundation-windows.ps1
echo   audit       Runs audit-windows.ps1
echo   personal    Runs personal-bootstrap-windows.ps1
echo   wsl         Runs the optional WSL Linux bootstrap
echo   resign      Runs resign-windows.ps1
echo.
echo Common arguments by target:
echo   foundation  -Mode ^<setup^|ensure^|update^|personal^> -Profile_ ^<work^|home^|minimal^>
echo               -Shell ^<pwsh^> -Personal -NonInteractive -DryRun
echo               -DotfilesRepo ^<url^> -PersonalScript ^<path^> -TakeoverMiseConfig
echo   audit       -Section ^<tools^|shell^|configs^|signing^|zscaler^|wsl^|all^> -Profile_ ^<work^|home^|minimal^>
echo               -Json -PopulateState
echo   personal    -Mode personal -DotfilesRepo ^<url^> -DryRun
echo   wsl         -Mode ^<ensure^|audit^> -Profile_ ^<work^|home^|minimal^>
echo               -Distribution ^<name^> -WslVersion ^<auto^|1^|2^> -WslUser ^<name^>
echo               -WslShell ^<fish^|zsh^|bash^> -DownloadsTarget ^<Linux path^> -DryRun
echo   resign      -DryRun
echo.
echo Examples:
echo   bootstrap-windows.cmd foundation -Mode ensure -Profile_ work -Personal
echo   bootstrap-windows.cmd audit -Section tools
echo   bootstrap-windows.cmd personal -DryRun
echo   bootstrap-windows.cmd wsl -Mode ensure -Profile_ home
echo   bootstrap-windows.cmd resign -DryRun
echo.
echo Notes:
echo   Use install.cmd for normal remote or first-run usage.
echo   Use foundation-windows.cmd, audit-windows.cmd,
echo   personal-bootstrap-windows.cmd, wsl-bootstrap-windows.cmd,
echo   or resign-windows.cmd
echo   for single-purpose local entrypoints.
echo   Use Get-Help .\Other\scripts\windows\foundation-windows.ps1 -Detailed
echo   for full PowerShell help on direct script entrypoints.
endlocal & exit /b 0
