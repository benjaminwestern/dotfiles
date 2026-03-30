# =============================================================================
# personal-bootstrap-windows.ps1 -- Windows personal layer bootstrap
#
# Runs AFTER foundation-windows.ps1 has completed successfully. Sources the
# shared library (lib/common.ps1) and reads the state file that foundation
# already populated with all resolved feature flags.
#
# Targets:
#   - Dotfiles repo clone/pull
#   - Git config (copy .gitconfig to $HOME)
#   - SSH config (copy .ssh/config to $HOME\.ssh)
#   - Mise config (copy config.toml, .env, scripts to $HOME\.config\mise)
#   - Opencode config (copy opencode.json and plugins to $HOME\.config\opencode)
#   - PowerShell profile extras (managed block with personal aliases/functions)
#
# Usage:
#   .\personal-bootstrap-windows.ps1
#   .\personal-bootstrap-windows.ps1 -Mode personal -DotfilesRepo <url>
#
# Prerequisites:
#   - foundation-windows.ps1 has been run at least once (state file exists)
#   - Scoop is installed and on PATH
# =============================================================================

param(
  [string]$Mode = 'personal',
  [string]$DotfilesRepo = 'https://github.com/benjaminwestern/dotfiles.git',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'lib\common.ps1')

# Honour both the -DryRun switch and the DRY_RUN env var (set by install.cmd).
if ($DryRun -or $env:DRY_RUN -eq '1') { $global:DRY_RUN = $true }

$DotfilesDir = if ($env:DOTFILES_DIR) { $env:DOTFILES_DIR } else { Join-Path $HOME '.dotfiles' }
$ConfigsDir  = Join-Path $DotfilesDir 'Configs'

# Read the state file to consume RESOLVED_* variables from foundation.
$State = Read-State


# =============================================================================
# SECTION 1: DOTFILES REPO
# =============================================================================

function Ensure-Repo {
  <#
  .SYNOPSIS
      Clone the dotfiles repo if absent, or pull latest changes.
  .DESCRIPTION
      Checks whether $DotfilesDir\.git exists. If present, fetches and pulls
      (ff-only). If absent, clones from DotfilesRepo.
  .NOTES
      Checks: Whether $DotfilesDir\.git exists.
      Gates: None -- always runs because the repo is needed for everything else.
      Side effects: Clones or fetches+pulls the dotfiles repository.
      Idempotency: Safe. Uses --ff-only so it will never force-merge.
  #>
  if (Test-Path (Join-Path $DotfilesDir '.git')) {
    Invoke-OrDry -Label 'git fetch --all --prune' -Command { git -C $DotfilesDir fetch --all --prune 2>$null }
    Invoke-OrDry -Label 'git pull --ff-only' -Command { git -C $DotfilesDir pull --ff-only 2>$null }

    if (Test-DryRun) {
      Write-StatusFix 'Dotfiles repo' -Action 'would pull latest'
    } else {
      Write-StatusPass 'Dotfiles repo' -Detail 'up to date'
    }
    return
  }

  Invoke-OrDry -Label "git clone $DotfilesRepo $DotfilesDir" -Command { git clone $DotfilesRepo $DotfilesDir }
  if (Test-DryRun) {
    Write-StatusFix 'Dotfiles repo' -Action "would clone from $DotfilesRepo"
  } else {
    Write-StatusFix 'Dotfiles repo' -Action "cloned from $DotfilesRepo"
  }
}


# =============================================================================
# SECTION 2: GIT CONFIG
# =============================================================================

function Apply-GitConfig {
  <#
  .SYNOPSIS
      Copy .gitconfig from dotfiles to $HOME.
  .DESCRIPTION
      Copies the managed .gitconfig into the user's home directory. If the
      destination already exists and matches, reports pass. If it differs or
      is absent, copies and reports fix.
  .NOTES
      Checks: Whether source .gitconfig exists; whether destination matches.
      Gates: ENABLE_GIT_CONFIG env var (default: true).
      Side effects: Copies .gitconfig to $HOME.
      Idempotency: Compares content before copying; no-ops if identical.
  #>
  $enabled = if ($env:ENABLE_GIT_CONFIG) { $env:ENABLE_GIT_CONFIG } else { 'true' }
  if ($enabled -ne 'true') {
    Write-StatusSkip 'Git config' -Reason 'disabled by flag'
    return
  }

  $src = Join-Path $ConfigsDir 'git\.gitconfig'
  $dst = Join-Path $HOME '.gitconfig'

  if (-not (Test-Path $src)) {
    Write-StatusSkip 'Git config' -Reason 'source not found in dotfiles'
    return
  }

  if (Test-Path $dst) {
    $srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash $dst -Algorithm SHA256).Hash
    if ($srcHash -eq $dstHash) {
      Write-StatusPass 'Git config' -Detail 'up to date'
      return
    }
  }

  Invoke-OrDry -Label "copy .gitconfig to $dst" -Command { Copy-Item -Path $src -Destination $dst -Force }
  if (Test-DryRun) {
    Write-StatusFix 'Git config' -Action 'would copy to home directory'
  } else {
    Write-StatusFix 'Git config' -Action 'copied to home directory'
  }
}


# =============================================================================
# SECTION 3: SSH CONFIG
# =============================================================================

function Apply-SshConfig {
  <#
  .SYNOPSIS
      Copy SSH config from dotfiles to $HOME\.ssh.
  .DESCRIPTION
      Ensures $HOME\.ssh exists, then copies the managed SSH config into it.
      Compares content before overwriting.
  .NOTES
      Checks: Whether source config exists; whether destination matches.
      Gates: ENABLE_SSH_CONFIG env var (default: true).
      Side effects: Creates .ssh directory if absent; copies config.
      Idempotency: Compares content before copying; no-ops if identical.
  #>
  $enabled = if ($env:ENABLE_SSH_CONFIG) { $env:ENABLE_SSH_CONFIG } else { 'true' }
  if ($enabled -ne 'true') {
    Write-StatusSkip 'SSH config' -Reason 'disabled by flag'
    return
  }

  $src = Join-Path $ConfigsDir 'ssh\.ssh\config'
  $dst = Join-Path $HOME '.ssh\config'
  $sshDir = Join-Path $HOME '.ssh'

  if (-not (Test-Path $src)) {
    Write-StatusSkip 'SSH config' -Reason 'source not found in dotfiles'
    return
  }

  # Ensure .ssh directory exists
  if (-not (Test-Path $sshDir)) {
    Invoke-OrDry -Label "mkdir $sshDir" -Command { New-Item -ItemType Directory -Force $sshDir | Out-Null }
  }

  if (Test-Path $dst) {
    $srcHash = (Get-FileHash $src -Algorithm SHA256).Hash
    $dstHash = (Get-FileHash $dst -Algorithm SHA256).Hash
    if ($srcHash -eq $dstHash) {
      Write-StatusPass 'SSH config' -Detail 'up to date'
      return
    }
  }

  Invoke-OrDry -Label "copy ssh config to $dst" -Command { Copy-Item -Path $src -Destination $dst -Force }
  if (Test-DryRun) {
    Write-StatusFix 'SSH config' -Action 'would copy to .ssh directory'
  } else {
    Write-StatusFix 'SSH config' -Action 'copied to .ssh directory'
  }
}


# =============================================================================
# SECTION 4: MISE CONFIG
# =============================================================================

function Apply-MiseConfig {
  <#
  .SYNOPSIS
      Copy mise config.toml, .env, and scripts from dotfiles to $HOME\.config\mise.
  .DESCRIPTION
      Mirrors the dotfiles mise config tree into the user's .config\mise directory.
      Copies config.toml, .env (if present), and the scripts directory. Compares
      each file before overwriting.
  .NOTES
      Checks: Whether source mise config directory exists.
      Gates: ENABLE_MISE_CONFIG env var (default: true).
      Side effects: Creates .config\mise directory tree; copies config files.
      Idempotency: Compares content before copying; no-ops if identical.
  #>
  $enabled = if ($env:ENABLE_MISE_CONFIG) { $env:ENABLE_MISE_CONFIG } else { 'true' }
  if ($enabled -ne 'true') {
    Write-StatusSkip 'Mise config' -Reason 'disabled by flag'
    return
  }

  $srcDir = Join-Path $ConfigsDir 'mise\.config\mise'
  $dstDir = Join-Path $HOME '.config\mise'

  if (-not (Test-Path $srcDir)) {
    Write-StatusSkip 'Mise config' -Reason 'source not found in dotfiles'
    return
  }

  # Count files that need updating (used for both dry-run and real mode)
  $pending = 0
  $srcConfig = Join-Path $srcDir 'config.toml'
  $dstConfig = Join-Path $dstDir 'config.toml'
  if ((Test-Path $srcConfig) -and ((-not (Test-Path $dstConfig)) -or
      (Get-FileHash $srcConfig -Algorithm SHA256).Hash -ne (Get-FileHash $dstConfig -Algorithm SHA256).Hash)) {
    $pending++
  }
  $srcEnv = Join-Path $srcDir '.env'
  $dstEnv = Join-Path $dstDir '.env'
  if ((Test-Path $srcEnv) -and ((-not (Test-Path $dstEnv)) -or
      (Get-FileHash $srcEnv -Algorithm SHA256).Hash -ne (Get-FileHash $dstEnv -Algorithm SHA256).Hash)) {
    $pending++
  }
  $srcScripts = Join-Path $srcDir 'scripts'
  $dstScripts = Join-Path $dstDir 'scripts'
  if (Test-Path $srcScripts) {
    foreach ($file in (Get-ChildItem -Path $srcScripts -File -Recurse)) {
      $relativePath = $file.FullName.Substring($srcScripts.Length)
      $dstFile = Join-Path $dstScripts $relativePath
      if ((-not (Test-Path $dstFile)) -or
          (Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $dstFile -Algorithm SHA256).Hash) {
        $pending++
      }
    }
  }

  if ($pending -eq 0) {
    Write-StatusPass 'Mise config' -Detail 'up to date'
    return
  }

  if (Test-DryRun) {
    Write-DryRunLog "copy $pending mise config file(s) to $dstDir"
    Write-StatusFix 'Mise config' -Action "would copy $pending file(s)"
    return
  }

  # Ensure destination directory exists
  if (-not (Test-Path $dstDir)) {
    New-Item -ItemType Directory -Force $dstDir | Out-Null
  }

  $copied = 0

  # Copy config.toml
  if ((Test-Path $srcConfig) -and ((-not (Test-Path $dstConfig)) -or
      (Get-FileHash $srcConfig -Algorithm SHA256).Hash -ne (Get-FileHash $dstConfig -Algorithm SHA256).Hash)) {
    Copy-Item -Path $srcConfig -Destination $dstConfig -Force
    $copied++
  }

  # Copy .env (if present)
  if ((Test-Path $srcEnv) -and ((-not (Test-Path $dstEnv)) -or
      (Get-FileHash $srcEnv -Algorithm SHA256).Hash -ne (Get-FileHash $dstEnv -Algorithm SHA256).Hash)) {
    Copy-Item -Path $srcEnv -Destination $dstEnv -Force
    $copied++
  }

  # Copy scripts directory (recursive)
  if (Test-Path $srcScripts) {
    if (-not (Test-Path $dstScripts)) {
      New-Item -ItemType Directory -Force $dstScripts | Out-Null
    }
    foreach ($file in (Get-ChildItem -Path $srcScripts -File -Recurse)) {
      $relativePath = $file.FullName.Substring($srcScripts.Length)
      $dstFile = Join-Path $dstScripts $relativePath
      $dstFileDir = Split-Path -Parent $dstFile
      if (-not (Test-Path $dstFileDir)) {
        New-Item -ItemType Directory -Force $dstFileDir | Out-Null
      }
      if ((-not (Test-Path $dstFile)) -or
          (Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $dstFile -Algorithm SHA256).Hash) {
        Copy-Item -Path $file.FullName -Destination $dstFile -Force
        $copied++
      }
    }
  }

  Write-StatusFix 'Mise config' -Action "$copied file(s) copied"
}


# =============================================================================
# SECTION 5: OPENCODE CONFIG
# =============================================================================

function Apply-OpencodeConfig {
  <#
  .SYNOPSIS
      Copy opencode config and plugins from dotfiles to $HOME\.config\opencode.
  .DESCRIPTION
      Copies opencode.json and the plugins directory into the user's
      .config\opencode directory. Compares each file before overwriting.
  .NOTES
      Checks: Whether source opencode config directory exists.
      Gates: ENABLE_OPENCODE_CONFIG env var (default: true).
      Side effects: Creates .config\opencode directory tree; copies config files.
      Idempotency: Compares content before copying; no-ops if identical.
  #>
  $enabled = if ($env:ENABLE_OPENCODE_CONFIG) { $env:ENABLE_OPENCODE_CONFIG } else { 'true' }
  if ($enabled -ne 'true') {
    Write-StatusSkip 'Opencode config' -Reason 'disabled by flag'
    return
  }

  $srcDir = Join-Path $ConfigsDir 'opencode\.config\opencode'
  $dstDir = Join-Path $HOME '.config\opencode'

  if (-not (Test-Path $srcDir)) {
    Write-StatusSkip 'Opencode config' -Reason 'source not found in dotfiles'
    return
  }

  # Count files that need updating
  $pending = 0
  $srcJson = Join-Path $srcDir 'opencode.json'
  $dstJson = Join-Path $dstDir 'opencode.json'
  if ((Test-Path $srcJson) -and ((-not (Test-Path $dstJson)) -or
      (Get-FileHash $srcJson -Algorithm SHA256).Hash -ne (Get-FileHash $dstJson -Algorithm SHA256).Hash)) {
    $pending++
  }
  $srcPlugins = Join-Path $srcDir 'plugins'
  $dstPlugins = Join-Path $dstDir 'plugins'
  if (Test-Path $srcPlugins) {
    foreach ($file in (Get-ChildItem -Path $srcPlugins -File -Recurse)) {
      $relativePath = $file.FullName.Substring($srcPlugins.Length)
      $dstFile = Join-Path $dstPlugins $relativePath
      if ((-not (Test-Path $dstFile)) -or
          (Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $dstFile -Algorithm SHA256).Hash) {
        $pending++
      }
    }
  }

  if ($pending -eq 0) {
    Write-StatusPass 'Opencode config' -Detail 'up to date'
    return
  }

  if (Test-DryRun) {
    Write-DryRunLog "copy $pending opencode config file(s) to $dstDir"
    Write-StatusFix 'Opencode config' -Action "would copy $pending file(s)"
    return
  }

  if (-not (Test-Path $dstDir)) {
    New-Item -ItemType Directory -Force $dstDir | Out-Null
  }

  $copied = 0

  # Copy opencode.json
  if ((Test-Path $srcJson) -and ((-not (Test-Path $dstJson)) -or
      (Get-FileHash $srcJson -Algorithm SHA256).Hash -ne (Get-FileHash $dstJson -Algorithm SHA256).Hash)) {
    Copy-Item -Path $srcJson -Destination $dstJson -Force
    $copied++
  }

  # Copy plugins directory (recursive)
  if (Test-Path $srcPlugins) {
    if (-not (Test-Path $dstPlugins)) {
      New-Item -ItemType Directory -Force $dstPlugins | Out-Null
    }
    foreach ($file in (Get-ChildItem -Path $srcPlugins -File -Recurse)) {
      $relativePath = $file.FullName.Substring($srcPlugins.Length)
      $dstFile = Join-Path $dstPlugins $relativePath
      $dstFileDir = Split-Path -Parent $dstFile
      if (-not (Test-Path $dstFileDir)) {
        New-Item -ItemType Directory -Force $dstFileDir | Out-Null
      }
      if ((-not (Test-Path $dstFile)) -or
          (Get-FileHash $file.FullName -Algorithm SHA256).Hash -ne (Get-FileHash $dstFile -Algorithm SHA256).Hash) {
        Copy-Item -Path $file.FullName -Destination $dstFile -Force
        $copied++
      }
    }
  }

  Write-StatusFix 'Opencode config' -Action "$copied file(s) copied"
}


# =============================================================================
# SECTION 6: POWERSHELL PROFILE EXTRAS
# =============================================================================

function Apply-ProfileExtras {
  <#
  .SYNOPSIS
      Inject personal aliases and functions into the PowerShell profile.
  .DESCRIPTION
      Uses Write-ManagedBlock to maintain a fenced block of personal additions
      in the PowerShell $PROFILE. Content includes common aliases, directory
      shortcuts, and tool integrations (zoxide, fzf, starship) that go beyond
      the foundation-managed PATH setup.
  .NOTES
      Checks: Whether $PROFILE path is set.
      Gates: ENABLE_PROFILE_EXTRAS env var (default: true).
      Side effects: Appends or updates a managed block in $PROFILE.
      Idempotency: Write-ManagedBlock replaces existing block content.
  #>
  $enabled = if ($env:ENABLE_PROFILE_EXTRAS) { $env:ENABLE_PROFILE_EXTRAS } else { 'true' }
  if ($enabled -ne 'true') {
    Write-StatusSkip 'Profile extras' -Reason 'disabled by flag'
    return
  }

  if (-not $PROFILE) {
    Write-StatusSkip 'Profile extras' -Reason '$PROFILE not set'
    return
  }

  $beginMarker = '# >>> personal-bootstrap >>>'
  $endMarker   = '# <<< personal-bootstrap <<<'

  # Build the managed block content -- personal shell customisations
  $blockContent = @"
$beginMarker
# Personal aliases and functions managed by personal-bootstrap-windows.ps1
# Do not edit this block manually; it will be overwritten on next run.

# -- Navigation aliases -------------------------------------------------------
Set-Alias -Name ll -Value Get-ChildItem
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# -- Git aliases --------------------------------------------------------------
function gs { git status @args }
function gd { git diff @args }
function gl { git log --oneline -20 @args }
function gp { git pull @args }
function gc { git commit @args }

# -- Tool integrations --------------------------------------------------------
# Zoxide (smarter cd) -- only if installed
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# Fzf integration -- only if installed
if (Get-Command fzf -ErrorAction SilentlyContinue) {
  `$env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border'
}

# Starship prompt -- only if installed
if (Get-Command starship -ErrorAction SilentlyContinue) {
  Invoke-Expression (& starship init powershell)
}

$endMarker
"@

  Write-ManagedBlock `
    -FilePath $PROFILE `
    -BeginMarker $beginMarker `
    -EndMarker $endMarker `
    -BlockContent $blockContent

  if (Test-DryRun) {
    Write-StatusFix 'Profile extras' -Action 'would update managed block'
  } else {
    Write-StatusFix 'Profile extras' -Action 'managed block updated'
  }
}


# =============================================================================
# SECTION 7: MAIN
# =============================================================================

function Main {
  <#
  .SYNOPSIS
      Main entry point for the Windows personal bootstrap.
  .DESCRIPTION
      Sequential orchestrator that runs each personal target in order.
      Mirrors the macOS personal-bootstrap-macos.zsh main function structure.
  .NOTES
      Checks: Delegates to individual functions.
      Gates: Delegates to individual functions.
      Side effects: Copies config files, updates profile.
      Idempotency: Every step is individually idempotent.
  #>

  Write-Host ''
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host '  Windows personal bootstrap' -ForegroundColor White
  Write-Host "  Mode: $Mode" -ForegroundColor DarkGray
  Write-Host "  Repo: $DotfilesRepo" -ForegroundColor DarkGray
  Write-Host "  Path: $DotfilesDir" -ForegroundColor DarkGray
  if (Test-DryRun) {
    Write-Host '  ** DRY RUN — no changes will be made **' -ForegroundColor Magenta
  }
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host ''

  # Step 1: Ensure repo is up to date
  Ensure-Repo

  # Step 2: Git config
  Apply-GitConfig

  # Step 3: SSH config
  Apply-SshConfig

  # Step 4: Mise config (config.toml, .env, scripts)
  Apply-MiseConfig

  # Step 5: Opencode config (opencode.json, plugins)
  Apply-OpencodeConfig

  # Step 6: PowerShell profile extras (aliases, tool integrations)
  Apply-ProfileExtras

  # Summary
  Write-StatusSummary -Label 'Personal'
  Write-Host 'Personal bootstrap completed.' -ForegroundColor Green
}

Main
