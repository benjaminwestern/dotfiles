<#
.SYNOPSIS
Installs and converges an optional WSL Linux environment.

.DESCRIPTION
WSL is deliberately separate from the native Windows foundation. This script
enables WSL, installs an Ubuntu distribution by default, creates a Linux user
matching the Windows account, and then invokes the repository's normal Linux
bootstrap with the same home, work, or minimal profile. Native Windows remains
fully usable when this layer is never selected.

.PARAMETER Mode
Use ensure to install or repair the WSL layer, or audit for a read-only Linux
profile audit inside an existing distribution.

.PARAMETER Profile_
The Linux bootstrap profile: home, work, or minimal.

.PARAMETER Distribution
The WSL distribution name. Defaults to Ubuntu.

.PARAMETER WslVersion
Use auto to preserve an installed distribution version and otherwise prefer
WSL 2. Explicitly select 1 for a nested VM without virtualization support.

.PARAMETER WslUser
The Linux user to create/use. Defaults to the current Windows user name.

.PARAMETER WslShell
The Linux login shell. Home/work default to Fish; minimal defaults to Bash.

.PARAMETER DownloadsTarget
An optional absolute Linux path for the WSL Downloads symlink.

.PARAMETER DryRun
Reports required changes without enabling Windows features, installing a
distribution, creating a user, or changing Linux state.
#>
param(
  [ValidateSet('ensure', 'audit')]
  [string]$Mode = 'ensure',
  [ValidateSet('work', 'home', 'minimal')]
  [string]$Profile_,
  [string]$Distribution = 'Ubuntu',
  [ValidateSet('auto', '1', '2')]
  [string]$WslVersion = 'auto',
  [string]$WslUser,
  [ValidateSet('bash', 'zsh', 'fish')]
  [string]$WslShell,
  [string]$DeviceName,
  [string]$DownloadsTarget,
  [string]$GitName,
  [string]$GitEmail,
  [string]$DotfilesRepo,
  [switch]$NonInteractive,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'lib\windows-precursor.ps1')

$PrecursorArgs = @('-Mode', $Mode)
foreach ($parameter in @('Profile_', 'Distribution', 'WslVersion', 'WslUser', 'WslShell', 'DeviceName', 'DownloadsTarget', 'GitName', 'GitEmail', 'DotfilesRepo')) {
  if ($PSBoundParameters.ContainsKey($parameter)) {
    $PrecursorArgs += @("-$parameter", [string]$PSBoundParameters[$parameter])
  }
}
if ($NonInteractive) { $PrecursorArgs += '-NonInteractive' }
if ($DryRun) { $PrecursorArgs += '-DryRun' }
Invoke-PwshPrecursor -ScriptPath $MyInvocation.MyCommand.Path -ArgumentList $PrecursorArgs

. (Join-Path $ScriptDir 'lib\common.ps1')
if ($DryRun -or $env:DRY_RUN -eq '1') { $global:DRY_RUN = $true }

$state = Read-State
if (-not $Profile_) {
  $Profile_ = if ($env:DEVICE_PROFILE) { $env:DEVICE_PROFILE } elseif ($state['DEVICE_PROFILE']) { $state['DEVICE_PROFILE'] } else { 'minimal' }
}
if ($Profile_ -notin @('work', 'home', 'minimal')) {
  Write-Fatal "WSL profile must be work, home, or minimal; got: $Profile_"
}

if (-not $WslUser) { $WslUser = $env:USERNAME.ToLowerInvariant() }
if ($WslUser -notmatch '^[a-z_][a-z0-9_-]{0,31}$') {
  Write-Fatal "WSL user must be a portable lowercase Linux account name; got: $WslUser"
}
if ($Distribution -notmatch '^[A-Za-z0-9._-]+$') {
  Write-Fatal "WSL distribution contains unsupported characters: $Distribution"
}
if (-not $WslShell) { $WslShell = if ($Profile_ -eq 'minimal') { 'bash' } else { 'fish' } }
if ($DownloadsTarget -and -not $DownloadsTarget.StartsWith('/')) {
  Write-Fatal "WSL Downloads target must be an absolute Linux path; got: $DownloadsTarget"
}
if (-not $DeviceName) {
  $baseName = if ($state['DEVICE_NAME']) { $state['DEVICE_NAME'] } elseif ($env:COMPUTERNAME) { $env:COMPUTERNAME.ToLowerInvariant() } else { 'windows-pc' }
  $DeviceName = "$baseName-wsl"
}
if ($DeviceName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,62}$') {
  Write-Fatal "WSL device name must be a portable hostname; got: $DeviceName"
}
if (-not $GitName) { $GitName = $state['GIT_USER_NAME'] }
if (-not $GitEmail) { $GitEmail = $state['GIT_USER_EMAIL'] }
if (-not $DotfilesRepo) {
  $DotfilesRepo = if ($env:DOTFILES_REPO) { $env:DOTFILES_REPO } else { 'https://github.com/benjaminwestern/dotfiles.git' }
}
$ManageWslLoginShell = [Environment]::GetEnvironmentVariable('ENABLE_SHELL_DEFAULT') -ne 'false'

function ConvertTo-BashSingleQuoted {
  param([AllowEmptyString()][string]$Value)
  $singleQuote = [string][char]39
  $doubleQuote = [string][char]34
  $embeddedQuote = "$singleQuote$doubleQuote$singleQuote$doubleQuote$singleQuote"
  return "$singleQuote$($Value.Replace($singleQuote, $embeddedQuote))$singleQuote"
}

function Test-IsAdministrator {
  $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WindowsFeatureState {
  param([Parameter(Mandatory)][string]$Name)
  $feature = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction SilentlyContinue
  if ($feature) { return [string]$feature.State }
  return 'Unavailable'
}

function Test-WindowsRestartPending {
  return (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
}

function Get-WslDistributions {
  # Do not call `wsl --list` until the optional feature is enabled: current
  # Windows builds turn that read into an interactive installation prompt.
  if ((Get-WindowsFeatureState 'Microsoft-Windows-Subsystem-Linux') -ne 'Enabled') {
    return @()
  }
  $raw = & wsl.exe --list --quiet 2>$null
  if ($LASTEXITCODE -ne 0) { return @() }
  return @($raw | ForEach-Object { ([string]$_).Replace([string][char]0, '').Trim() } | Where-Object { $_ })
}

function Test-WslDistributionInstalled {
  $installed = Get-WslDistributions
  return @($installed | Where-Object { $_.Equals($Distribution, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
}

function Get-WslDistributionVersion {
  if (-not (Test-WslDistributionInstalled)) { return '' }
  $lines = & wsl.exe --list --verbose 2>$null
  if ($LASTEXITCODE -ne 0) { return '' }
  $escapedDistribution = [regex]::Escape($Distribution)
  foreach ($line in $lines) {
    $clean = ([string]$line).Replace([string][char]0, '').Trim()
    if ($clean -match "^\*?\s*$escapedDistribution\s+\S+\s+([12])\s*$") {
      return $Matches[1]
    }
  }
  return ''
}

function Invoke-WslRoot {
  param([Parameter(Mandatory)][string]$Command)
  & wsl.exe --distribution $Distribution --user root --cd '~' -- bash --noprofile --norc -lc $Command
  if ($LASTEXITCODE -ne 0) { throw "WSL root command failed with exit code $LASTEXITCODE" }
}

function Invoke-WslUser {
  param([Parameter(Mandatory)][string]$Command)
  # Bootstrap orchestration must not depend on, or accidentally load, either
  # the Windows or Linux user's interactive shell configuration.
  & wsl.exe --distribution $Distribution --user $WslUser --cd '~' -- bash --noprofile --norc -lc $Command
  if ($LASTEXITCODE -ne 0) { throw "WSL user command failed with exit code $LASTEXITCODE" }
}

function Write-WslHeader {
  Write-Host ''
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host '  Optional WSL bootstrap' -ForegroundColor White
  Write-Host "  Mode:         $Mode" -ForegroundColor DarkGray
  Write-Host "  Distribution: $Distribution" -ForegroundColor DarkGray
  Write-Host "  WSL version:  $WslVersion" -ForegroundColor DarkGray
  Write-Host "  Linux user:   $WslUser" -ForegroundColor DarkGray
  Write-Host "  Linux shell:  $WslShell" -ForegroundColor DarkGray
  Write-Host "  Profile:      $Profile_" -ForegroundColor DarkGray
  if (Test-DryRun) { Write-Host '  ** DRY RUN — no changes will be made **' -ForegroundColor Magenta }
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host ''
}

function Invoke-WslAudit {
  $featureState = Get-WindowsFeatureState 'Microsoft-Windows-Subsystem-Linux'
  $vmState = Get-WindowsFeatureState 'VirtualMachinePlatform'
  if ($featureState -ne 'Enabled') {
    Write-StatusSkip 'WSL' -Reason "Linux feature is $featureState"
    Write-StatusSummary -Label 'WSL'
    return
  }
  if (-not (Test-WslDistributionInstalled)) {
    Write-StatusSkip 'WSL distribution' -Reason "$Distribution is not installed"
    Write-StatusSummary -Label 'WSL'
    return
  }

  $installedVersion = Get-WslDistributionVersion
  if ($installedVersion -eq '2' -and $vmState -ne 'Enabled') {
    Write-StatusSkip 'WSL 2' -Reason "Virtual Machine Platform is $vmState"
    Write-StatusSummary -Label 'WSL'
    return
  }
  Write-StatusPass 'WSL feature' -Detail 'enabled'
  Write-StatusPass 'WSL distribution' -Detail "$Distribution (version $installedVersion)"
  $auditCommand = "BOOTSTRAP_WSL_VERSION=$(ConvertTo-BashSingleQuoted $installedVersion) `"`$HOME/.dotfiles/install.sh`" audit --profile $(ConvertTo-BashSingleQuoted $Profile_)"
  Invoke-WslUser -Command $auditCommand
  Write-StatusPass 'WSL profile audit' -Detail "$Profile_ completed"
  Write-StatusSummary -Label 'WSL'
}

function Ensure-WslPlatform {
  $featureState = Get-WindowsFeatureState 'Microsoft-Windows-Subsystem-Linux'
  $vmState = Get-WindowsFeatureState 'VirtualMachinePlatform'
  $installedVersion = Get-WslDistributionVersion
  $effectiveVersion = if ($WslVersion -eq 'auto' -and $installedVersion) { $installedVersion } elseif ($WslVersion -eq 'auto') { '2' } else { $WslVersion }
  $script:EffectiveWslVersion = $effectiveVersion
  $featuresReady = $featureState -eq 'Enabled' -and ($effectiveVersion -eq '1' -or $vmState -eq 'Enabled')
  if ($featuresReady -and (Test-WindowsRestartPending)) {
    Write-StatusSkip 'WSL platform' -Reason 'Windows restart is required before the distribution can be initialized'
    return $false
  }
  $distroReady = $featuresReady -and (Test-WslDistributionInstalled)

  if (-not $featuresReady -or -not $distroReady) {
    if (Test-DryRun) {
      Write-DryRunLog "wsl --set-default-version $effectiveVersion"
      Write-DryRunLog "wsl --install --distribution $Distribution --no-launch --web-download"
      Write-StatusFix 'WSL platform' -Action "would enable WSL $effectiveVersion and install the distribution; restart may be required"
      return $false
    }
    if (-not (Test-IsAdministrator)) {
      Write-Fatal 'WSL installation requires an elevated Windows terminal.'
    }

    & wsl.exe --set-default-version $effectiveVersion | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wsl --set-default-version $effectiveVersion failed with exit code $LASTEXITCODE" }

    # Keep native command output visible without allowing it to become part of
    # this function's Boolean return stream.
    & wsl.exe --install --distribution $Distribution --no-launch --web-download | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wsl --install failed with exit code $LASTEXITCODE" }

    if (Test-WindowsRestartPending) {
      Write-StatusFix 'WSL platform' -Action 'installed; restart Windows, then rerun install.cmd wsl'
      return $false
    }

    $featuresReady = (Get-WindowsFeatureState 'Microsoft-Windows-Subsystem-Linux') -eq 'Enabled' -and
      ($effectiveVersion -eq '1' -or (Get-WindowsFeatureState 'VirtualMachinePlatform') -eq 'Enabled')
    $distroReady = $featuresReady -and (Test-WslDistributionInstalled)
    if (-not $featuresReady -or -not $distroReady) {
      Write-StatusFix 'WSL platform' -Action 'installed; restart Windows, then rerun install.cmd wsl'
      return $false
    }
  }

  & wsl.exe --set-default-version $effectiveVersion | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "wsl --set-default-version $effectiveVersion failed with exit code $LASTEXITCODE" }
  $installedVersion = Get-WslDistributionVersion
  if ($installedVersion -and $installedVersion -ne $effectiveVersion) {
    & wsl.exe --set-version $Distribution $effectiveVersion | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "wsl --set-version $Distribution $effectiveVersion failed with exit code $LASTEXITCODE" }
  }
  Write-StatusPass 'WSL platform' -Detail "WSL $effectiveVersion enabled"
  Write-StatusPass 'WSL distribution' -Detail "$Distribution installed (version $effectiveVersion)"
  return $true
}

function Ensure-WslLinuxUser {
  $quotedUser = ConvertTo-BashSingleQuoted $WslUser
  $quotedDeviceName = ConvertTo-BashSingleQuoted $DeviceName
  $rootCommand = @"
set -eu
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl sudo
elif command -v pacman >/dev/null 2>&1; then
  pacman -Sy --needed --noconfirm ca-certificates curl sudo
else
  printf 'unsupported WSL distribution: apt-get or pacman is required\n' >&2
  exit 2
fi
if ! id $quotedUser >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash $quotedUser
fi
usermod -aG sudo $quotedUser
printf '%s ALL=(ALL) NOPASSWD:ALL\n' $quotedUser > /etc/sudoers.d/dotfiles-bootstrap
chmod 0440 /etc/sudoers.d/dotfiles-bootstrap
$(if ($script:EffectiveWslVersion -eq '2') { "printf '[boot]\\nsystemd=true\\n\\n[user]\\ndefault=%s\\n\\n[network]\\nhostname=%s\\n' $quotedUser $quotedDeviceName > /etc/wsl.conf" } else { "printf '[user]\\ndefault=%s\\n\\n[network]\\nhostname=%s\\n' $quotedUser $quotedDeviceName > /etc/wsl.conf" })
"@
  Invoke-WslRoot -Command $rootCommand
  Write-StatusPass 'WSL Linux user' -Detail $WslUser
}

function Ensure-WslLinuxBootstrap {
  $arguments = @(
    'setup',
    '--profile', (ConvertTo-BashSingleQuoted $Profile_),
    '--shell', (ConvertTo-BashSingleQuoted $WslShell),
    '--device-name', (ConvertTo-BashSingleQuoted $DeviceName),
    '--dotfiles-repo', (ConvertTo-BashSingleQuoted $DotfilesRepo),
    '--non-interactive'
  )
  if ($GitName) { $arguments += @('--git-name', (ConvertTo-BashSingleQuoted $GitName)) }
  if ($GitEmail) { $arguments += @('--git-email', (ConvertTo-BashSingleQuoted $GitEmail)) }
  if ($DownloadsTarget) {
    $arguments += @('--downloads-target', (ConvertTo-BashSingleQuoted $DownloadsTarget))
  }
  if ($Profile_ -in @('home', 'work')) { $arguments += '--personal' }
  # install.cmd records --enable/--disable switches in its child environment.
  # Translate the Linux-relevant subset back to the public install.sh flags so
  # WSL profiles remain just as editable as native macOS/Linux profiles.
  $linuxFlagMap = [ordered]@{
    'ENABLE_PACKAGES'           = 'packages'
    'ENABLE_APPLICATIONS'       = 'applications'
    'ENABLE_MISE_TOOLS'         = 'mise-tools'
    'ENABLE_DOTFILES'           = 'dotfiles'
    'ENABLE_CODE_DIRECTORY'     = 'code-directory'
    'ENABLE_DOWNLOADS_LINK'     = 'downloads-link'
    'ENABLE_GIT_IDENTITY'       = 'git-identity'
    'ENABLE_LINUX_DEFAULTS'     = 'linux-defaults'
    'ENABLE_LINUX_HOSTNAME'     = 'linux-hostname'
    'ENABLE_LINUX_DEFAULT_APPS' = 'linux-default-apps'
    'ENABLE_REMOTE_ACCESS'      = 'remote-access'
    'ENABLE_SHELL_DEFAULT'      = 'shell-default'
    'ENABLE_ZSCALER'            = 'zscaler'
  }
  foreach ($entry in $linuxFlagMap.GetEnumerator()) {
    $value = [Environment]::GetEnvironmentVariable($entry.Key)
    if ($value -eq 'true') { $arguments += "--enable-$($entry.Value)" }
    elseif ($value -eq 'false') { $arguments += "--disable-$($entry.Value)" }
  }
  # The Linux user bootstrap must never invoke interactive chsh under WSL.
  # The elevated Windows orchestrator applies the same selected shell after
  # packages are present, unless the operator explicitly disabled that stage.
  # Keep this last so it wins over the translated profile override.
  $arguments += '--disable-shell-default'
  if ($script:EffectiveWslVersion -eq '1') {
    # WSL 1 cannot run systemd-backed SSH, Flatpak applications, or desktop
    # MIME handlers. Preserve the portable CLI, Mise, Fish, Git, and dotfiles
    # layers while WSL 2 retains the complete Linux profile.
    $arguments += @('--disable-applications', '--disable-remote-access', '--disable-linux-default-apps')
  }
  if (Test-DryRun) { $arguments += '--dry-run' }

  $installUrl = 'https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.sh'
  $command = "export BOOTSTRAP_WSL_VERSION=$(ConvertTo-BashSingleQuoted $script:EffectiveWslVersion); curl -fsSL $(ConvertTo-BashSingleQuoted $installUrl) | bash -s -- $($arguments -join ' ')"
  Invoke-WslUser -Command $command
  Write-StatusPass 'WSL Linux bootstrap' -Detail "$Profile_ profile converged"
}

function Ensure-WslLoginShell {
  if (-not $ManageWslLoginShell) {
    Write-StatusSkip 'WSL login shell' -Reason 'disabled by flag'
    return
  }
  $quotedUser = ConvertTo-BashSingleQuoted $WslUser
  $shellPath = switch ($WslShell) {
    'bash' { '/bin/bash' }
    'zsh'  { '/usr/bin/zsh' }
    'fish' { '/usr/bin/fish' }
  }
  $quotedShellPath = ConvertTo-BashSingleQuoted $shellPath
  $command = "set -eu; test -x $quotedShellPath; usermod --shell $quotedShellPath $quotedUser"
  Invoke-WslRoot -Command $command
  Write-StatusPass 'WSL login shell' -Detail "$WslShell ($shellPath)"
}

function Remove-TransientWslSudo {
  Invoke-WslRoot -Command 'rm -f /etc/sudoers.d/dotfiles-bootstrap'
  Write-StatusPass 'WSL bootstrap elevation' -Detail 'temporary sudo rule removed'
}

Write-WslHeader
if ($Mode -eq 'audit') {
  Invoke-WslAudit
  exit 0
}

if (-not (Ensure-WslPlatform)) {
  Write-StatusSummary -Label 'WSL'
  exit 0
}

if (Test-DryRun) {
  Write-DryRunLog "create or validate Linux user $WslUser"
  Write-DryRunLog "run Linux $Profile_ bootstrap in $Distribution"
  Write-StatusFix 'WSL Linux bootstrap' -Action 'would converge after WSL is available'
  Write-StatusSummary -Label 'WSL'
  exit 0
}

try {
  Ensure-WslLinuxUser
  Ensure-WslLinuxBootstrap
  Ensure-WslLoginShell
} finally {
  Remove-TransientWslSudo
}

& wsl.exe --set-default $Distribution | Out-Null
if ($LASTEXITCODE -ne 0) { throw "wsl --set-default failed with exit code $LASTEXITCODE" }
Write-StatusPass 'WSL default distribution' -Detail $Distribution
Write-StatusSummary -Label 'WSL'
