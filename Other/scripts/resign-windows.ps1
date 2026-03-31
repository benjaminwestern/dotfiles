<#
.SYNOPSIS
Re-signs local Windows PowerShell assets used by the bootstrap.

.DESCRIPTION
Use this repair script after Scoop or mise updates, or after local edits, when
PowerShell scripts need to be signed again under an AllSigned execution policy.
Normal operators should enter through resign-windows.cmd. This implementation
ensures the local signing certificate exists, then re-signs Scoop scripts,
mise scripts, repo-local Windows bootstrap scripts, and the current PowerShell
profile when present.

.PARAMETER DryRun
Prints what the script would sign without modifying any files.

.EXAMPLE
pwsh -NoLogo -NoProfile -File .\Other\scripts\resign-windows.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -File .\Other\scripts\resign-windows.ps1 -DryRun
#>
param(
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $ScriptDir 'lib\common.ps1')
. (Join-Path $ScriptDir 'lib\signing-helpers-windows.ps1')

if ($DryRun -or $env:DRY_RUN -eq '1') { $global:DRY_RUN = $true }

function Get-SignableScriptCount {
  param([Parameter(Mandatory)][string]$RootPath)

  if (-not (Test-Path $RootPath)) {
    return 0
  }

  return @(
    Get-ChildItem $RootPath -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
      Where-Object { $_.Length -ge 4 }
  ).Count
}

function Invoke-ReSignSet {
  param(
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][string]$RootPath,
    [Parameter(Mandatory)][scriptblock]$SignAction
  )

  $count = Get-SignableScriptCount -RootPath $RootPath
  if ($count -eq 0) {
    Write-StatusSkip $Label -Reason 'no signable .ps1 files found'
    return
  }

  Invoke-OrDry -Label $Label -Command $SignAction
  if (Test-DryRun) {
    Write-StatusFix $Label -Action "would sign $count file(s)"
  } else {
    Write-StatusFix $Label -Action "signed $count file(s)"
  }
}

function Invoke-ReSignProfile {
  if (-not (Test-Path $PROFILE)) {
    Write-StatusSkip 'PowerShell profile signature' -Reason 'profile does not exist'
    return
  }

  $profileFile = Get-Item $PROFILE -ErrorAction SilentlyContinue
  if (-not $profileFile -or $profileFile.Length -lt 4) {
    Write-StatusSkip 'PowerShell profile signature' -Reason 'profile is empty or too small to sign'
    return
  }

  Invoke-OrDry -Label 'Sign-Profile' -Command { Sign-Profile }
  if (Test-DryRun) {
    Write-StatusFix 'PowerShell profile signature' -Action 'would sign profile'
  } else {
    Write-StatusFix 'PowerShell profile signature' -Action 'signed profile'
  }
}

function Main {
  Write-Host ''
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host '  Windows signing repair' -ForegroundColor White
  if (Test-DryRun) {
    Write-Host '  DRY RUN' -ForegroundColor Magenta
  }
  Write-Host '---' -ForegroundColor DarkGray

  $cert = Get-LocalCodeSigningCert
  if ($cert) {
    Write-StatusPass 'Local signing cert' -Detail "present (expires $($cert.NotAfter.ToString('yyyy-MM-dd')))"
  } elseif (Test-DryRun) {
    Write-StatusFix 'Local signing cert' -Action 'would create LocalScoopSigner'
  } else {
    $cert = Ensure-LocalCodeSigningCert
    Write-StatusFix 'Local signing cert' -Action 'created LocalScoopSigner'
  }

  Invoke-ReSignSet `
    -Label 'Scoop scripts' `
    -RootPath (Join-Path $env:USERPROFILE 'scoop') `
    -SignAction { Sign-ScoopScripts }

  Invoke-ReSignSet `
    -Label 'mise scripts' `
    -RootPath (Join-Path $HOME 'AppData\Local\mise') `
    -SignAction { Sign-MiseScripts }

  Invoke-ReSignSet `
    -Label 'Dotfiles Windows scripts' `
    -RootPath (Join-Path $HOME '.dotfiles\Other\scripts') `
    -SignAction { Sign-DotfilesWindowsScripts }

  Invoke-ReSignProfile

  Write-Host ''
  Write-Host "Summary: $global:_STATUS_PASSED passed, $global:_STATUS_FIXED fixed, $global:_STATUS_SKIPPED skipped, $global:_STATUS_FAILED failed" -ForegroundColor DarkGray
}

Main
