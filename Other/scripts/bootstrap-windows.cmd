@echo off
setlocal EnableExtensions

for %%I in ("%~dp0.") do set "SCRIPT_DIR=%%~fI\"

set "TARGET=%SCRIPT_DIR%foundation-windows.ps1"
set "MODE=foundation"

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

if /I "%~1"=="foundation" (
  set "MODE=foundation"
  shift
) else if /I "%~1"=="audit" (
  set "MODE=audit"
  set "TARGET=%SCRIPT_DIR%audit-windows.ps1"
  shift
) else if /I "%~1"=="resign" (
  set "MODE=resign"
  set "TARGET=%SCRIPT_DIR%resign-windows.ps1"
  shift
) else if /I "%~1"=="personal" (
  set "MODE=personal"
  set "TARGET=%SCRIPT_DIR%personal-bootstrap-windows.ps1"
  shift
)

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage
if /I "%~1"=="help" goto usage

set "BOOTSTRAP_TARGET=%TARGET%"
set "BOOTSTRAP_ROOT=%SCRIPT_DIR%"

powershell -NoLogo -NoProfile -Command "& { $ErrorActionPreference = 'Stop'; $scriptsRoot = [System.IO.Path]::GetFullPath('%BOOTSTRAP_ROOT%'); $targetScript = [System.IO.Path]::GetFullPath('%BOOTSTRAP_TARGET%'); $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object Subject -eq 'CN=LocalScoopSigner' | Select-Object -First 1; if (-not $cert) { Write-Host 'Creating local code-signing certificate (CN=LocalScoopSigner)...' -ForegroundColor Cyan; $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=LocalScoopSigner' -CertStoreLocation 'Cert:\CurrentUser\My'; $cerPath = Join-Path $env:TEMP 'LocalScoopSigner.cer'; Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null; certutil -user -addstore Root $cerPath -f | Out-Null; certutil -user -addstore TrustedPublisher $cerPath -f | Out-Null; Remove-Item $cerPath -ErrorAction SilentlyContinue }; Get-ChildItem $scriptsRoot -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue | Where-Object { $_.Length -ge 4 -and [System.IO.Path]::GetFullPath($_.FullName) -ne $targetScript } | ForEach-Object { Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null }; if (Test-Path $targetScript) { Set-AuthenticodeSignature -FilePath $targetScript -Certificate $cert | Out-Null } }"
if errorlevel 1 exit /b %ERRORLEVEL%

powershell -NoLogo -NoProfile -File "%TARGET%" %*
set "EXITCODE=%ERRORLEVEL%"

endlocal & exit /b %EXITCODE%

:usage
echo Usage:
echo   bootstrap-windows.cmd [foundation^|audit^|personal^|resign] [PowerShell args]
echo.
echo Targets:
echo   foundation  Runs foundation-windows.ps1
echo   audit       Runs audit-windows.ps1
echo   personal    Runs personal-bootstrap-windows.ps1
echo   resign      Runs resign-windows.ps1
echo.
echo Common arguments by target:
echo   foundation  -Mode ^<setup^|ensure^|update^|personal^> -Profile_ ^<work^|home^|minimal^>
echo               -Shell ^<pwsh^> -Personal -NonInteractive -DryRun
echo               -DotfilesRepo ^<url^> -PersonalScript ^<path^> -TakeoverMiseConfig
echo   audit       -Section ^<tools^|shell^|configs^|signing^|zscaler^|all^> -Json -PopulateState
echo   personal    -Mode personal -DotfilesRepo ^<url^> -DryRun
echo   resign      -DryRun
echo.
echo Examples:
echo   bootstrap-windows.cmd foundation -Mode ensure -Profile_ work -Personal
echo   bootstrap-windows.cmd audit -Section tools
echo   bootstrap-windows.cmd personal -DryRun
echo   bootstrap-windows.cmd resign -DryRun
echo.
echo Notes:
echo   Use install.cmd for normal remote or first-run usage.
echo   Use foundation-windows.cmd, audit-windows.cmd,
echo   personal-bootstrap-windows.cmd, or resign-windows.cmd
echo   for single-purpose local entrypoints.
echo   Use Get-Help .\Other\scripts\foundation-windows.ps1 -Detailed
echo   for full PowerShell help on direct script entrypoints.
endlocal & exit /b 0
