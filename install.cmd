@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "DEFAULT_DOTFILES_REPO=https://github.com/benjaminwestern/dotfiles.git"
set "DEFAULT_ARCHIVE_URL=https://github.com/benjaminwestern/dotfiles/archive/refs/heads/main.zip"
set "ENTRY_TARGET=foundation"
set "ENTRY_MODE="
set "FORWARD_ARGS="
set "ARCHIVE_RUN_ROOT="

if defined DOTFILES_REPO (
  set "DOTFILES_REPO=%DOTFILES_REPO%"
) else (
  set "DOTFILES_REPO=%DEFAULT_DOTFILES_REPO%"
)
if not "%DOTFILES_DIR%"=="" (
  set "TARGET_DOTFILES_DIR=%DOTFILES_DIR%"
) else (
  set "TARGET_DOTFILES_DIR=%USERPROFILE%\.dotfiles"
)

for %%I in ("%~dp0.") do set "LOCAL_ROOT=%%~fI"
if exist "%LOCAL_ROOT%\Other\scripts\bootstrap-windows.cmd" (
  set "RUN_ROOT=%LOCAL_ROOT%"
) else (
  set "RUN_ROOT="
)

:parse_args
if "%~1"=="" goto after_parse

if /I "%~1"=="setup" (
  if defined ENTRY_MODE set "FAIL_MESSAGE=Mode already set to %ENTRY_MODE%" & goto fatal
  set "ENTRY_MODE=setup"
  shift
  goto parse_args
)

if /I "%~1"=="ensure" (
  if defined ENTRY_MODE set "FAIL_MESSAGE=Mode already set to %ENTRY_MODE%" & goto fatal
  set "ENTRY_MODE=ensure"
  shift
  goto parse_args
)

if /I "%~1"=="update" (
  if defined ENTRY_MODE set "FAIL_MESSAGE=Mode already set to %ENTRY_MODE%" & goto fatal
  set "ENTRY_MODE=update"
  shift
  goto parse_args
)

if /I "%~1"=="personal" (
  if defined ENTRY_MODE set "FAIL_MESSAGE=Mode already set to %ENTRY_MODE%" & goto fatal
  set "ENTRY_TARGET=personal"
  set "ENTRY_MODE=personal"
  shift
  goto parse_args
)

if /I "%~1"=="audit" (
  if defined ENTRY_MODE set "FAIL_MESSAGE=Mode already set to %ENTRY_MODE%" & goto fatal
  set "ENTRY_TARGET=audit"
  set "ENTRY_MODE=audit"
  shift
  goto parse_args
)

if /I "%~1"=="--shell" (
  if "%~2"=="" set "FAIL_MESSAGE=--shell requires a value" & goto fatal
  set "FORWARD_ARGS=%FORWARD_ARGS% -Shell ""%~2"""
  shift
  shift
  goto parse_args
)

if /I "%~1"=="--profile" (
  if "%~2"=="" set "FAIL_MESSAGE=--profile requires a value" & goto fatal
  set "FORWARD_ARGS=%FORWARD_ARGS% -Profile_ ""%~2"""
  shift
  shift
  goto parse_args
)

if /I "%~1"=="--personal" (
  if /I not "%ENTRY_TARGET%"=="personal" set "FORWARD_ARGS=%FORWARD_ARGS% -Personal"
  shift
  goto parse_args
)

if /I "%~1"=="--non-interactive" (
  set "FORWARD_ARGS=%FORWARD_ARGS% -NonInteractive"
  shift
  goto parse_args
)

if /I "%~1"=="--dry-run" (
  set "FORWARD_ARGS=%FORWARD_ARGS% -DryRun"
  shift
  goto parse_args
)

if /I "%~1"=="--dotfiles-repo" (
  if "%~2"=="" set "FAIL_MESSAGE=--dotfiles-repo requires a value" & goto fatal
  set "DOTFILES_REPO=%~2"
  set "FORWARD_ARGS=%FORWARD_ARGS% -DotfilesRepo ""%~2"""
  shift
  shift
  goto parse_args
)

if /I "%~1"=="--dotfiles-dir" (
  if "%~2"=="" set "FAIL_MESSAGE=--dotfiles-dir requires a value" & goto fatal
  set "TARGET_DOTFILES_DIR=%~2"
  shift
  shift
  goto parse_args
)

if /I "%~1"=="--personal-script" (
  if "%~2"=="" set "FAIL_MESSAGE=--personal-script requires a value" & goto fatal
  set "FORWARD_ARGS=%FORWARD_ARGS% -PersonalScript ""%~2"""
  shift
  shift
  goto parse_args
)

if /I "%~1"=="--section" (
  if "%~2"=="" set "FAIL_MESSAGE=--section requires a value" & goto fatal
  set "FORWARD_ARGS=%FORWARD_ARGS% -Section ""%~2"""
  shift
  shift
  goto parse_args
)

if /I "%~1"=="--json" (
  set "FORWARD_ARGS=%FORWARD_ARGS% -Json"
  shift
  goto parse_args
)

if /I "%~1"=="--populate-state" (
  set "FORWARD_ARGS=%FORWARD_ARGS% -PopulateState"
  shift
  goto parse_args
)

if /I "%~1"=="-h" goto usage
if /I "%~1"=="--help" goto usage

set "PREFIX=%~1"
if /I "!PREFIX:~0,9!"=="--enable-" (
  set "FLAG_NAME=!PREFIX:~9!"
  set "FLAG_NAME=!FLAG_NAME:-=_!"
  call set "ENABLE_!FLAG_NAME!=true"
  shift
  goto parse_args
)

if /I "!PREFIX:~0,10!"=="--disable-" (
  set "FLAG_NAME=!PREFIX:~10!"
  set "FLAG_NAME=!FLAG_NAME:-=_!"
  call set "ENABLE_!FLAG_NAME!=false"
  shift
  goto parse_args
)

set "FAIL_MESSAGE=Unknown argument: %~1"
goto fatal

:after_parse
if not defined ENTRY_MODE set "ENTRY_MODE=setup"

if not defined RUN_ROOT call :ensure_run_root

set "DOTFILES_DIR=%TARGET_DOTFILES_DIR%"
set "BOOTSTRAP_ROOT=%RUN_ROOT%"

echo.
echo ^>^>^> Install Entry ^<^<^<
echo.
echo ^>^>^> OS: windows ^| Mode: %ENTRY_MODE% ^<^<^<
echo.
echo %FORWARD_ARGS% | findstr /I /C:"-DryRun" >nul
if not errorlevel 1 (
  echo ^>^>^> DRY RUN - no changes will be made ^<^<^<
  echo.
)

if /I "%ENTRY_TARGET%"=="audit" (
  call "%RUN_ROOT%\Other\scripts\bootstrap-windows.cmd" audit %FORWARD_ARGS%
) else if /I "%ENTRY_TARGET%"=="personal" (
  call "%RUN_ROOT%\Other\scripts\bootstrap-windows.cmd" personal %FORWARD_ARGS%
) else (
  call "%RUN_ROOT%\Other\scripts\bootstrap-windows.cmd" foundation -Mode %ENTRY_MODE% %FORWARD_ARGS%
)
set "EXITCODE=%ERRORLEVEL%"

call :maybe_persist_repo_after_archive_run

endlocal & exit /b %EXITCODE%

:usage
echo Usage:
echo   install.cmd ^<setup^|ensure^|update^|personal^|audit^> [options]
echo.
echo Options:
echo   --shell ^<pwsh^>            Set preferred shell ^(persisted to state file^)
echo   --profile ^<work^|home^|minimal^>  Set device profile preset
echo   --enable-^<flag^>           Enable a feature flag
echo   --disable-^<flag^>          Disable a feature flag
echo   --personal                  Run the personal layer after foundation
echo   --non-interactive           Disable all interactive prompts
echo   --dry-run                   Show what would happen without making changes
echo   --dotfiles-repo ^<url^>     Override dotfiles repository URL
echo   --dotfiles-dir ^<path^>     Override the local dotfiles checkout path
echo   --personal-script ^<path^>  Override personal bootstrap script path
echo   --section ^<name^>          Audit section ^(audit mode only^)
echo   --json                      JSON audit output ^(audit mode only^)
echo   --populate-state            Populate audit state ^(audit mode only^)
echo.
echo Examples:
echo   install.cmd setup --profile work --personal
echo   install.cmd ensure
echo   install.cmd audit --section tools
echo   install.cmd audit --json
endlocal & exit /b 0

:fatal
echo.
echo ^>^>^> ERROR: %FAIL_MESSAGE% ^<^<^<
echo.
endlocal & exit /b 1

:have_git
where git >nul 2>nul
exit /b %ERRORLEVEL%

:clone_repo_with_git
echo.
echo ^>^>^> Cloning dotfiles repo to %TARGET_DOTFILES_DIR% ^<^<^<
echo.
git clone "%DOTFILES_REPO%" "%TARGET_DOTFILES_DIR%"
exit /b %ERRORLEVEL%

:download_repo_archive
if /I not "%DOTFILES_REPO%"=="%DEFAULT_DOTFILES_REPO%" (
  set "FAIL_MESSAGE=git is required when --dotfiles-repo is not the default repository"
  goto fatal
)

set "ARCHIVE_TEMP_ROOT=%TEMP%\dotfiles-install"
set "ARCHIVE_PATH=%TEMP%\dotfiles-main.zip"

echo.
echo ^>^>^> Downloading temporary dotfiles archive ^<^<^<
echo.

powershell -NoLogo -NoProfile -Command "& { $ErrorActionPreference = 'Stop'; $archivePath = [System.IO.Path]::GetFullPath('%ARCHIVE_PATH%'); $archiveRoot = [System.IO.Path]::GetFullPath('%ARCHIVE_TEMP_ROOT%'); if (Test-Path $archivePath) { Remove-Item $archivePath -Force }; if (Test-Path $archiveRoot) { Remove-Item $archiveRoot -Recurse -Force }; Invoke-WebRequest -UseBasicParsing -Uri '%DEFAULT_ARCHIVE_URL%' -OutFile $archivePath; Expand-Archive -Path $archivePath -DestinationPath $archiveRoot -Force }"
if errorlevel 1 exit /b %ERRORLEVEL%

set "ARCHIVE_RUN_ROOT=%ARCHIVE_TEMP_ROOT%\dotfiles-main"
set "RUN_ROOT=%ARCHIVE_RUN_ROOT%"
exit /b 0

:ensure_run_root
if exist "%TARGET_DOTFILES_DIR%\Other\scripts\bootstrap-windows.cmd" (
  set "RUN_ROOT=%TARGET_DOTFILES_DIR%"
  exit /b 0
)

if exist "%TARGET_DOTFILES_DIR%" (
  set "FAIL_MESSAGE=Path exists but does not contain the dotfiles bootstrap: %TARGET_DOTFILES_DIR%"
  goto fatal
)

call :have_git
if not errorlevel 1 (
  call :clone_repo_with_git
  if errorlevel 1 exit /b %ERRORLEVEL%
  set "RUN_ROOT=%TARGET_DOTFILES_DIR%"
  exit /b 0
)

call :download_repo_archive
exit /b %ERRORLEVEL%

:maybe_persist_repo_after_archive_run
if not defined ARCHIVE_RUN_ROOT exit /b 0
if exist "%TARGET_DOTFILES_DIR%" exit /b 0

call :have_git
if not errorlevel 1 (
  echo.
  echo ^>^>^> Cloning persistent dotfiles repo to %TARGET_DOTFILES_DIR% ^<^<^<
  echo.
  git clone "%DOTFILES_REPO%" "%TARGET_DOTFILES_DIR%" >nul 2>nul
  exit /b 0
)

echo.
echo ^>^>^> WARNING: bootstrap ran from a temporary archive because git is unavailable; dotfiles repo was not persisted ^<^<^<
echo.
exit /b 0
