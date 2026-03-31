<#
.SYNOPSIS
Runs the read-only Windows machine audit for this dotfiles repository.

.DESCRIPTION
Use this script to inspect the current Windows bootstrap state without making
changes. It reports foundation package coverage, outdated Scoop foundation
packages, outdated mise tools, shell and profile state, signing posture,
configuration files, and Zscaler trust state. The only optional write is
PopulateState, which records discovered values into the shared state file.

.PARAMETER Section
Limits the audit to one section. Supported values are tools, shell, configs,
signing, zscaler, and all.

.PARAMETER Json
Outputs machine-readable JSON instead of the formatted terminal report.

.PARAMETER PopulateState
Writes discovered baseline values into ~/.config/dotfiles/state.env after the
audit completes.

.EXAMPLE
pwsh -NoLogo -NoProfile -File .\Other\scripts\audit-windows.ps1

.EXAMPLE
pwsh -NoLogo -NoProfile -File .\Other\scripts\audit-windows.ps1 -Section signing

.EXAMPLE
pwsh -NoLogo -NoProfile -File .\Other\scripts\audit-windows.ps1 -Json

.NOTES
Use install.cmd audit, audit-windows.cmd, or bootstrap-windows.cmd audit on a
fresh machine so the PowerShell 5 precursor path and repo-local signing
protections stay in place.
#>
param(
  [ValidateSet('tools', 'shell', 'configs', 'signing', 'zscaler', 'all')]
  [string]$Section = 'all',
  [switch]$Json,
  [switch]$PopulateState
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $ScriptDir 'lib\windows-precursor.ps1')

$PrecursorArgs = @()
if ($PSBoundParameters.ContainsKey('Section')) { $PrecursorArgs += @('-Section', $Section) }
if ($Json) { $PrecursorArgs += '-Json' }
if ($PopulateState) { $PrecursorArgs += '-PopulateState' }
Invoke-PwshPrecursor -ScriptPath $MyInvocation.MyCommand.Path -ArgumentList $PrecursorArgs

. (Join-Path $ScriptDir 'lib\common.ps1')
. (Join-Path $ScriptDir 'lib\signing-helpers-windows.ps1')

$FoundationPackages = @(
  'git', 'gh', 'jq', 'jid', 'yq', 'fzf', 'fd', 'ripgrep', 'zoxide',
  'lazygit', 'charm-gum', 'vscode', 'openssl', 'pwsh'
)

$DotfilesDir        = Join-Path $HOME '.dotfiles'
$MiseConfigDir      = Join-Path $HOME '.config\mise'
$MiseConfigPath     = Join-Path $MiseConfigDir 'config.toml'
$MiseEnvPath        = Join-Path $MiseConfigDir '.env'
$CertsDir           = Join-Path $HOME 'certs'
$GoldenBundlePath   = Join-Path $CertsDir 'golden_pem.pem'
$ZscalerBundlePath  = Join-Path $CertsDir 'zscaler_ca_bundle.pem'
$EffectivePolicy    = Get-ExecutionPolicy
$RequiresSigning    = $EffectivePolicy -eq 'AllSigned'
$script:Detection   = Get-ZscalerDetection


function Write-AuditLine {
  param(
    [string]$Label,
    [string]$Value
  )

  $renderedValue = if ($null -eq $Value -or $Value -eq '') { '(empty)' } else { [string]$Value }
  Write-Host ("  {0,-35} {1}" -f $Label, $renderedValue)
}

function Write-SectionHeader {
  param([Parameter(Mandatory)][string]$Title)
  Write-Host ''
  Write-Host "** $Title **" -ForegroundColor Cyan
}

function Get-PropertyValue {
  param(
    $Object,
    [string[]]$Names
  )

  if (-not $Object) { return $null }

  foreach ($name in $Names) {
    if ($Object.PSObject.Properties.Name -contains $name) {
      return $Object.$name
    }
  }

  return $null
}

function Get-MiseShellName {
  param($Doctor)

  $doctorShell = Get-PropertyValue -Object $Doctor -Names @('shell', 'mise_shell')
  if (-not $doctorShell) {
    return $null
  }

  if ($doctorShell -is [string]) {
    return $doctorShell
  }

  if ($doctorShell.PSObject.Properties.Name -contains 'name' -and $doctorShell.name) {
    return [string]$doctorShell.name
  }

  return [string]$doctorShell
}

function Get-SignableScriptAudit {
  param([Parameter(Mandatory)][string]$RootPath)

  if (-not (Test-Path $RootPath)) {
    return [pscustomobject]@{
      total          = 0
      unsigned_count = 0
      unsigned_paths = @()
    }
  }

  $files = @(Get-ChildItem $RootPath -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge 4 })

  $unsignedPaths = @()
  foreach ($file in $files) {
    $signature = Get-AuthenticodeSignature $file.FullName -ErrorAction SilentlyContinue
    if (-not $signature -or $signature.Status -ne 'Valid') {
      $unsignedPaths += $file.FullName
    }
  }

  return [pscustomobject]@{
    total          = $files.Count
    unsigned_count = $unsignedPaths.Count
    unsigned_paths = $unsignedPaths
  }
}

function Test-PathContainsMiseShims {
  param([string]$PathValue)

  if (-not $PathValue) { return $false }
  $normalized = $PathValue -replace '/', '\'
  return [bool]($normalized -match '(?i)(^|;)[^;]*\\AppData\\Local\\mise\\shims($|;)')
}

function Get-MiseActivationBlockType {
  if (-not (Test-Path $PROFILE)) {
    return 'absent'
  }

  $content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
  if (-not $content) {
    return 'absent'
  }

  if ($content -match 'mise activate pwsh --shims') {
    return 'pwsh --shims'
  }

  if ($content -match 'mise activate pwsh') {
    return 'pwsh'
  }

  return 'absent'
}

function Get-MiseAuditState {
  $state = [ordered]@{
    doctor_json            = $null
    activation_block_type  = Get-MiseActivationBlockType
    mise_activated         = $false
    mise_shell             = 'unknown'
    mise_shims_on_path     = $false
  }

  $doctor = Get-InteractivePwshMiseDoctorJson
  if ($doctor) {
    $state.doctor_json = $doctor

    $doctorActivated = Get-PropertyValue -Object $doctor -Names @('activated', 'is_activated', 'active')
    if ($null -ne $doctorActivated) {
      $state.mise_activated = [bool]$doctorActivated
    }

    $doctorShell = Get-MiseShellName -Doctor $doctor
    if ($doctorShell) {
      $state.mise_shell = $doctorShell
    }

    $doctorShims = Get-PropertyValue -Object $doctor -Names @('shims_on_path', 'mise_shims_on_path')
    if ($null -ne $doctorShims) {
      $state.mise_shims_on_path = [bool]$doctorShims
    }
  }

  if ($state.activation_block_type -eq 'pwsh --shims') {
    $state.mise_activated = $true
    if ($state.mise_shell -eq 'unknown') {
      $state.mise_shell = 'pwsh --shims'
    }
  }

  if (Test-CommandExists 'pwsh') {
    $interactivePath = pwsh -NoLogo -Command '$env:PATH' 2>$null
    if (Test-PathContainsMiseShims -PathValue $interactivePath) {
      $state.mise_shims_on_path = $true
    }
  }

  return [pscustomobject]$state
}

function Get-ZscalerEffectiveValue {
  $profile = Get-StateValue -Key 'DEVICE_PROFILE'
  if (-not $profile) {
    $profile = 'minimal'
  }

  return Resolve-ZscalerSetting `
    -EnvVal $env:ENABLE_ZSCALER `
    -StateVal (Get-StateValue -Key 'ENABLE_ZSCALER') `
    -ProfileDefault (Get-ProfileDefault -Profile_ $profile -FlagKey 'ENABLE_ZSCALER') `
    -HardDefault 'false' `
    -Detection $script:Detection
}

function Get-WindowsTerminalAudit {
  $settingsPath = Get-WindowsTerminalSettingsPath
  $settings = Get-WindowsTerminalSettingsObject

  $result = [ordered]@{
    settings_path        = $settingsPath
    default_profile_guid = ''
    default_profile_name = ''
    default_pwsh         = $false
  }

  if (-not $settings) {
    return [pscustomobject]$result
  }

  $result.default_profile_guid = [string](Get-PropertyValue -Object $settings -Names @('defaultProfile'))
  if ($result.default_profile_guid) {
    $defaultProfile = Get-WindowsTerminalProfileByGuid -SettingsObject $settings -Guid $result.default_profile_guid
    if ($defaultProfile) {
      $result.default_profile_name = [string](Get-PropertyValue -Object $defaultProfile -Names @('name'))

      $commandLine = ''
      if ($defaultProfile.PSObject.Properties.Name -contains 'commandline') {
        $commandLine = $defaultProfile.commandline
      } elseif ($defaultProfile.PSObject.Properties.Name -contains 'commandLine') {
        $commandLine = $defaultProfile.commandLine
      }

      if ($defaultProfile.source -eq 'Windows.Terminal.PowershellCore' -or
        ($commandLine -and $commandLine -match '(^|[\\/])pwsh(\.exe)?(\s|$)')) {
        $result.default_pwsh = $true
      }
    }
  }

  return [pscustomobject]$result
}

function Get-ToolVersion {
  param(
    [Parameter(Mandatory)][string]$CommandName,
    [string[]]$Arguments = @('--version')
  )

  if (-not (Test-CommandExists $CommandName)) {
    return 'not installed'
  }

  try {
    $output = & $CommandName @Arguments 2>$null | Select-Object -First 1
    if ($output) { return [string]$output }
  } catch {
  }

  return 'installed'
}

function Get-ScoopOutdatedPackages {
  $result = [ordered]@{
    checked             = $false
    uses_local_metadata = $true
    packages            = @()
    foundation_packages = @()
    note                = ''
  }

  if (-not (Test-CommandExists 'scoop')) {
    return [pscustomobject]$result
  }

  try {
    $statusItems = @(scoop status --local 2>$null)
  } catch {
    $result.note = 'status check failed'
    return [pscustomobject]$result
  }
  $statusExitCode = $LASTEXITCODE
  if ($statusExitCode -ne 0) {
    $result.note = "status check failed (exit $statusExitCode)"
    return [pscustomobject]$result
  }

  $packages = @()
  foreach ($item in $statusItems) {
    if (-not $item) { continue }
    if (-not ($item.PSObject.Properties.Name -contains 'Name')) { continue }

    $name = [string](Get-PropertyValue -Object $item -Names @('Name'))
    if (-not $name) { continue }

    $installed = [string](Get-PropertyValue -Object $item -Names @('Installed Version', 'InstalledVersion'))
    $latest = [string](Get-PropertyValue -Object $item -Names @('Latest Version', 'LatestVersion'))
    $missingDeps = [string](Get-PropertyValue -Object $item -Names @('Missing Dependencies', 'MissingDependencies'))
    $info = [string](Get-PropertyValue -Object $item -Names @('Info'))

    $normalizedName = $name
    if ($normalizedName.Contains('/')) {
      $normalizedName = ($normalizedName -split '/')[(-1)]
    }

    $packages += [pscustomobject]@{
      name                 = $name
      normalized_name      = $normalizedName
      current              = $installed
      latest               = $latest
      missing_dependencies = $missingDeps
      info                 = $info
      outdated             = -not [string]::IsNullOrWhiteSpace($latest)
    }
  }

  $outdatedPackages = @($packages | Where-Object { $_.outdated })
  $foundationOutdated = @($outdatedPackages | Where-Object { $FoundationPackages -contains $_.normalized_name })

  $result.checked = $true
  $result.packages = $outdatedPackages
  $result.foundation_packages = $foundationOutdated
  return [pscustomobject]$result
}

function Get-MiseOutdatedTools {
  $result = [ordered]@{
    checked = $false
    tools   = @()
    note    = ''
  }

  if (-not (Test-CommandExists 'mise')) {
    return [pscustomobject]$result
  }

  try {
    $json = @((mise outdated --json 2>$null)) -join "`n"
  } catch {
    $result.note = 'outdated check failed'
    return [pscustomobject]$result
  }
  $outdatedExitCode = $LASTEXITCODE
  if ($outdatedExitCode -ne 0) {
    $result.note = "outdated check failed (exit $outdatedExitCode)"
    return [pscustomobject]$result
  }

  $result.checked = $true
  if (-not $json) {
    return [pscustomobject]$result
  }

  try {
    $parsed = $json | ConvertFrom-Json
  } catch {
    $result.note = 'invalid JSON from mise outdated'
    return [pscustomobject]$result
  }

  $tools = @()
  foreach ($property in $parsed.PSObject.Properties) {
    if (-not $property) { continue }

    $tool = $property.Value
    if (-not $tool) { continue }

    $source = Get-PropertyValue -Object $tool -Names @('source')
    $sourcePath = if ($source) {
      [string](Get-PropertyValue -Object $source -Names @('path'))
    } else {
      ''
    }

    $tools += [pscustomobject]@{
      name        = if ((Get-PropertyValue -Object $tool -Names @('name'))) {
        [string](Get-PropertyValue -Object $tool -Names @('name'))
      } else {
        [string]$property.Name
      }
      requested   = [string](Get-PropertyValue -Object $tool -Names @('requested'))
      current     = [string](Get-PropertyValue -Object $tool -Names @('current'))
      latest      = [string](Get-PropertyValue -Object $tool -Names @('latest'))
      bump        = [string](Get-PropertyValue -Object $tool -Names @('bump'))
      source_path = $sourcePath
    }
  }

  $result.tools = $tools
  return [pscustomobject]$result
}

function Format-OutdatedEntries {
  param(
    [object[]]$Entries,
    [int]$Limit = 5
  )

  if (-not $Entries -or $Entries.Count -eq 0) {
    return 'none'
  }

  $rendered = @()
  foreach ($entry in ($Entries | Select-Object -First $Limit)) {
    $name = [string](Get-PropertyValue -Object $entry -Names @('name'))
    $current = [string](Get-PropertyValue -Object $entry -Names @('current'))
    $latest = [string](Get-PropertyValue -Object $entry -Names @('latest'))

    if ($current -and $latest) {
      $rendered += "$name ($current -> $latest)"
    } elseif ($latest) {
      $rendered += "$name (latest $latest)"
    } else {
      $rendered += $name
    }
  }

  if ($Entries.Count -gt $Limit) {
    $rendered += "+$($Entries.Count - $Limit) more"
  }

  return ($rendered -join ', ')
}

function Invoke-AuditTools {
  Write-SectionHeader 'Tooling'

  $scoopOutdated = Get-ScoopOutdatedPackages
  $miseOutdated = Get-MiseOutdatedTools

  if (Test-CommandExists 'scoop') {
    Write-AuditLine 'Scoop:' (Get-ToolVersion -CommandName 'scoop')
  } else {
    Write-AuditLine 'Scoop:' 'not installed'
  }

  if (Test-CommandExists 'scoop') {
    $missing = @()
    foreach ($package in $FoundationPackages) {
      if (-not (Test-ScoopPackageInstalled -Name $package)) {
        $missing += $package
      }
    }

    $present = $FoundationPackages.Count - $missing.Count
    Write-AuditLine 'Foundation packages:' "$present/$($FoundationPackages.Count) present"
    if ($missing.Count -gt 0) {
      Write-AuditLine 'Missing packages:' ($missing -join ', ')
    }
  } else {
    Write-AuditLine 'Foundation packages:' 'cannot audit without Scoop'
  }

  if (Test-CommandExists 'scoop') {
    if (-not $scoopOutdated.checked) {
      $detail = if ($scoopOutdated.note) { $scoopOutdated.note } else { 'not checked' }
      Write-AuditLine 'Scoop outdated:' $detail
    } else {
      $detail = "$($scoopOutdated.foundation_packages.Count) outdated foundation package(s)"
      if ($scoopOutdated.packages.Count -gt $scoopOutdated.foundation_packages.Count) {
        $detail += ", $($scoopOutdated.packages.Count) outdated Scoop app(s) total"
      }
      $detail += ' (local bucket metadata)'
      Write-AuditLine 'Scoop outdated:' $detail
      if ($scoopOutdated.foundation_packages.Count -gt 0) {
        Write-AuditLine 'Outdated Scoop packages:' (Format-OutdatedEntries -Entries $scoopOutdated.foundation_packages)
      }
    }
  }

  if (Test-CommandExists 'mise') {
    Write-AuditLine 'Mise:' "$(Get-ToolVersion -CommandName 'mise') ($(Get-MiseInstallMethod))"
  } else {
    Write-AuditLine 'Mise:' 'not installed'
  }

  if (Test-CommandExists 'mise') {
    if (-not $miseOutdated.checked) {
      $detail = if ($miseOutdated.note) { $miseOutdated.note } else { 'not checked' }
      Write-AuditLine 'Mise outdated:' $detail
    } else {
      Write-AuditLine 'Mise outdated:' "$($miseOutdated.tools.Count) outdated tool(s)"
      if ($miseOutdated.tools.Count -gt 0) {
        Write-AuditLine 'Outdated mise tools:' (Format-OutdatedEntries -Entries $miseOutdated.tools)
      }
    }
  }

  foreach ($tool in @(
    @{ Name = 'pwsh'; Arguments = @('--version') },
    @{ Name = 'gum'; Arguments = @('--version') },
    @{ Name = 'lazygit'; Arguments = @('--version') },
    @{ Name = 'git'; Arguments = @('--version') },
    @{ Name = 'gh'; Arguments = @('--version') },
    @{ Name = 'openssl'; Arguments = @('version') }
  )) {
    Write-AuditLine "$($tool.Name):" (Get-ToolVersion -CommandName $tool.Name -Arguments $tool.Arguments)
  }

  foreach ($runtime in @(
    @{ Name = 'node'; Arguments = @('--version') },
    @{ Name = 'python'; Arguments = @('--version') },
    @{ Name = 'go'; Arguments = @('version') },
    @{ Name = 'terraform'; Arguments = @('version') }
  )) {
    Write-AuditLine "$($runtime.Name):" (Get-ToolVersion -CommandName $runtime.Name -Arguments $runtime.Arguments)
  }
}

function Invoke-AuditShell {
  Write-SectionHeader 'Shell Configuration'

  $miseAudit = Get-MiseAuditState
  $terminalAudit = Get-WindowsTerminalAudit

  Write-AuditLine 'PowerShell version:' $PSVersionTable.PSVersion.ToString()
  Write-AuditLine 'Execution policy (User):' (Get-ExecutionPolicy -Scope CurrentUser).ToString()
  Write-AuditLine 'Execution policy (Effective):' $EffectivePolicy.ToString()
  Write-AuditLine 'Profile path:' $PROFILE

  if (Test-Path $PROFILE) {
    Write-AuditLine 'Profile exists:' 'yes'
    $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    Write-AuditLine 'Managed block present:' $(if ($profileContent -and $profileContent.Contains($PROFILE_BEGIN)) { 'yes' } else { 'no' })

    $profileSignature = Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
    if ($profileSignature) {
      Write-AuditLine 'Profile signature:' $profileSignature.Status.ToString()
    } else {
      Write-AuditLine 'Profile signature:' 'unknown'
    }
  } else {
    Write-AuditLine 'Profile exists:' 'no'
  }

  Write-AuditLine 'Mise activation block:' $miseAudit.activation_block_type
  Write-AuditLine 'Mise doctor JSON:' $(if ($miseAudit.doctor_json) { 'captured from fresh pwsh' } else { 'unavailable' })
  Write-AuditLine 'Mise activated:' $(if ($miseAudit.mise_activated) { 'yes' } else { 'no' })
  Write-AuditLine 'Mise shell:' $miseAudit.mise_shell
  Write-AuditLine 'Mise shims on PATH:' $(if ($miseAudit.mise_shims_on_path) { 'yes' } else { 'no' })
  Write-AuditLine 'Windows Terminal settings:' $(if ($terminalAudit.settings_path) { $terminalAudit.settings_path } else { 'not found' })
  Write-AuditLine 'Windows Terminal default:' $(if ($terminalAudit.default_profile_name) { $terminalAudit.default_profile_name } else { 'unknown' })
  Write-AuditLine 'Windows Terminal default pwsh:' $(if ($terminalAudit.default_pwsh) { 'yes' } else { 'no' })
}

function Invoke-AuditConfigs {
  Write-SectionHeader 'Configuration'

  if (Test-Path (Join-Path $DotfilesDir '.git')) {
    Write-AuditLine 'Dotfiles repo:' $DotfilesDir
    $branch = git -C $DotfilesDir branch --show-current 2>$null
    Write-AuditLine 'Dotfiles branch:' $(if ($branch) { $branch } else { 'unknown' })
    $statusCount = (git -C $DotfilesDir status --porcelain 2>$null | Measure-Object -Line).Lines
    Write-AuditLine 'Dotfiles working tree:' $(if ($statusCount -eq 0) { 'clean' } else { "$statusCount change(s)" })
  } else {
    Write-AuditLine 'Dotfiles repo:' "not found at $DotfilesDir"
  }

  if (Test-Path $STATE_FILE_PATH) {
    Write-AuditLine 'State file:' $STATE_FILE_PATH
    foreach ($line in (Get-Content $STATE_FILE_PATH)) {
      if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $parts = $line.Split('=', 2)
        Write-AuditLine ("State $($parts[0]):") $parts[1]
      }
    }
  } else {
    Write-AuditLine 'State file:' 'absent'
  }

  if (Test-Path $MiseConfigPath) {
    Write-AuditLine 'Mise config:' $MiseConfigPath
    $configContent = Get-Content $MiseConfigPath -Raw -ErrorAction SilentlyContinue
    if ($configContent -and $configContent.Contains($MISE_BEGIN)) {
      Write-AuditLine 'Mise config ownership:' 'managed seed present'
    } else {
      Write-AuditLine 'Mise config ownership:' 'user-owned'
    }
  } else {
    Write-AuditLine 'Mise config:' 'absent'
  }

  if (Test-Path $MiseEnvPath) {
    Write-AuditLine 'Mise .env:' $MiseEnvPath
    $miseEnvContent = Get-Content $MiseEnvPath -Raw -ErrorAction SilentlyContinue
    Write-AuditLine 'Mise .env Zscaler block:' $(if ($miseEnvContent -and $miseEnvContent.Contains($ZSCALER_ENV_BEGIN)) { 'present' } else { 'absent' })
  } else {
    Write-AuditLine 'Mise .env:' 'absent'
  }

  if (Test-Path $GoldenBundlePath) {
    Write-AuditLine 'Golden CA bundle:' $GoldenBundlePath
  } else {
    Write-AuditLine 'Golden CA bundle:' 'absent'
  }

  Write-AuditLine 'Windows version:' ([System.Environment]::OSVersion.Version.ToString())
  Write-AuditLine 'Architecture:' $env:PROCESSOR_ARCHITECTURE
  Write-AuditLine 'Username:' $env:USERNAME
  Write-AuditLine 'Home:' $HOME
}

function Invoke-AuditSigning {
  Write-SectionHeader 'Signing'

  $cert = Get-LocalCodeSigningCert
  $scoopAudit = Get-SignableScriptAudit -RootPath (Join-Path $env:USERPROFILE 'scoop')
  $miseAudit = Get-SignableScriptAudit -RootPath (Join-Path $HOME 'AppData\Local\mise')
  $dotfilesAudit = Get-SignableScriptAudit -RootPath (Join-Path $HOME '.dotfiles\Other\scripts')
  $profileSignature = if (Test-Path $PROFILE) {
    Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
  } else {
    $null
  }
  $profileState = if ($profileSignature) { $profileSignature.Status.ToString() } else { 'profile missing' }
  $policyContext = $EffectivePolicy.ToString()
  $scoopDetail = "$($scoopAudit.total) total, $($scoopAudit.unsigned_count) unsigned"
  $miseDetail = "$($miseAudit.total) total, $($miseAudit.unsigned_count) unsigned"
  $dotfilesDetail = "$($dotfilesAudit.total) total, $($dotfilesAudit.unsigned_count) unsigned"
  if (-not $RequiresSigning) {
    if ($scoopAudit.unsigned_count -gt 0) { $scoopDetail += " (informational under $policyContext)" }
    if ($miseAudit.unsigned_count -gt 0) { $miseDetail += " (informational under $policyContext)" }
    if ($dotfilesAudit.unsigned_count -gt 0) { $dotfilesDetail += " (informational under $policyContext)" }
  }
  $profileDisplay = switch ($profileState) {
    'NotSigned' {
      if ($RequiresSigning) {
        'NotSigned'
      } else {
        "NotSigned (informational under $policyContext)"
      }
    }
    default { $profileState }
  }

  Write-AuditLine 'Effective policy:' $EffectivePolicy.ToString()
  Write-AuditLine 'Signing required:' $(if ($RequiresSigning) { 'yes' } else { 'no' })
  Write-AuditLine 'Local signing cert:' $(if ($cert) { "present (expires $($cert.NotAfter.ToString('yyyy-MM-dd')))" } else { 'absent' })
  Write-AuditLine 'Scoop .ps1 files:' $scoopDetail
  Write-AuditLine 'mise .ps1 files:' $miseDetail
  Write-AuditLine 'Dotfiles .ps1 files:' $dotfilesDetail
  Write-AuditLine 'Profile signature:' $profileDisplay

  if ($RequiresSigning) {
    $overall = if ($scoopAudit.unsigned_count -eq 0 -and $miseAudit.unsigned_count -eq 0 -and $dotfilesAudit.unsigned_count -eq 0 -and $profileState -eq 'Valid') {
      'all signable Scoop, mise, dotfiles scripts, and pwsh profile are signed'
    } else {
      "signing remediation needed; pwsh profile status is $profileState"
    }
    Write-AuditLine 'Overall:' $overall
  } else {
    $unsignedCounts = $scoopAudit.unsigned_count + $miseAudit.unsigned_count + $dotfilesAudit.unsigned_count
    if ($unsignedCounts -eq 0 -and $profileState -eq 'Valid') {
      Write-AuditLine 'Overall:' "signing is optional under $policyContext; all signable scripts and the pwsh profile are signed"
    } else {
      Write-AuditLine 'Overall:' "signing is optional under $policyContext; unsigned script counts and pwsh profile status are reported for visibility only"
    }
  }
}

function Invoke-AuditZscaler {
  Write-SectionHeader 'Zscaler'

  $rawState = Get-StateValue -Key 'ENABLE_ZSCALER'
  $effective = Get-ZscalerEffectiveValue
  $envContent = if (Test-Path $MiseEnvPath) { Get-Content $MiseEnvPath -Raw -ErrorAction SilentlyContinue } else { '' }

  Write-AuditLine 'State ENABLE_ZSCALER:' $(if ($rawState) { $rawState } else { 'unset' })
  Write-AuditLine 'Effective ENABLE_ZSCALER:' $effective
  Write-AuditLine 'Live TLS checked:' $(if ($script:Detection.live_tls_checked) { 'yes' } else { 'no' })
  Write-AuditLine 'Live TLS detected:' $(if ($script:Detection.live_tls_detected) { 'yes' } else { 'no' })
  Write-AuditLine 'Live TLS host:' $(if ($script:Detection.live_tls_host) { $script:Detection.live_tls_host } else { 'n/a' })
  Write-AuditLine 'Live TLS subject:' $(if ($script:Detection.live_tls_subject) { $script:Detection.live_tls_subject } else { 'n/a' })
  Write-AuditLine 'Live TLS issuer:' $(if ($script:Detection.live_tls_issuer) { $script:Detection.live_tls_issuer } else { 'n/a' })
  Write-AuditLine 'Cert store detected:' $(if ($script:Detection.store_detected) { 'yes' } else { 'no' })
  Write-AuditLine 'Cert store count:' $script:Detection.store_cert_count
  Write-AuditLine 'Detection sources:' $(if ($script:Detection.detection_sources) { ($script:Detection.detection_sources -join ', ') } else { 'none' })
  Write-AuditLine 'Zscaler bundle:' $(if (Test-Path $ZscalerBundlePath) { $ZscalerBundlePath } else { 'absent' })
  Write-AuditLine 'Golden bundle:' $(if (Test-Path $GoldenBundlePath) { $GoldenBundlePath } else { 'absent' })
  Write-AuditLine 'Mise .env block:' $(if ($envContent -and $envContent.Contains($ZSCALER_ENV_BEGIN)) { 'present' } else { 'absent' })

  foreach ($storeCert in ($script:Detection.store_certs | Select-Object -First 5)) {
    Write-AuditLine 'Store cert:' "$($storeCert.store) :: $($storeCert.subject)"
  }

  foreach ($name in @(
    'SSL_CERT_FILE',
    'NODE_EXTRA_CA_CERTS',
    'REQUESTS_CA_BUNDLE',
    'CURL_CA_BUNDLE',
    'GIT_SSL_CAINFO',
    'PIP_CERT',
    'NPM_CONFIG_CAFILE',
    'npm_config_cafile'
  )) {
    Write-AuditLine "User env ${name}:" ([Environment]::GetEnvironmentVariable($name, 'User'))
  }

  if (Test-CommandExists 'git') {
    Write-AuditLine 'Git http.sslcainfo:' (git config --global --get http.sslcainfo 2>$null)
  }

  if (Test-CommandExists 'node') {
    Write-AuditLine 'Node CA env:' ([Environment]::GetEnvironmentVariable('NODE_EXTRA_CA_CERTS', 'User'))
  }

  if (Test-CommandExists 'npm.cmd') {
    Write-AuditLine 'npm cafile:' (npm.cmd config get cafile 2>$null)
  } elseif (Test-CommandExists 'npm') {
    Write-AuditLine 'npm cafile:' (npm config get cafile 2>$null)
  }

  if ($rawState -eq 'false' -and $script:Detection.live_tls_detected -and $effective -eq 'true') {
    Write-AuditLine 'Override:' 'live TLS interception forced effective=true while state=false'
  }
}

function Invoke-PopulateState {
  Write-SectionHeader 'State Population'

  Set-StateValue -Key 'PREFERRED_SHELL' -Value 'pwsh'
  Write-AuditLine 'PREFERRED_SHELL:' 'pwsh'

  $existingProfile = Get-StateValue -Key 'DEVICE_PROFILE'
  if (-not $existingProfile) {
    $existingProfile = 'minimal'
  }
  Set-StateValue -Key 'DEVICE_PROFILE' -Value $existingProfile
  Write-AuditLine 'DEVICE_PROFILE:' $existingProfile

  $zscalerValue = if ($script:Detection.detected) { 'true' } else { 'false' }
  Set-StateValue -Key 'ENABLE_ZSCALER' -Value $zscalerValue
  Write-AuditLine 'ENABLE_ZSCALER:' $zscalerValue

  $miseToolsValue = if (Test-CommandExists 'mise') { 'true' } else { 'false' }
  Set-StateValue -Key 'ENABLE_MISE_TOOLS' -Value $miseToolsValue
  Write-AuditLine 'ENABLE_MISE_TOOLS:' $miseToolsValue

  Write-AuditLine 'State file:' $STATE_FILE_PATH
}

function Invoke-AuditJson {
  $scoopOutdated = Get-ScoopOutdatedPackages
  $miseOutdated = Get-MiseOutdatedTools
  $miseAudit = Get-MiseAuditState
  $terminalAudit = Get-WindowsTerminalAudit
  $profileSignature = if (Test-Path $PROFILE) {
    Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
  } else {
    $null
  }

  $result = [ordered]@{
    timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    shell = @{
      powershell_version            = $PSVersionTable.PSVersion.ToString()
      execution_policy              = $EffectivePolicy.ToString()
      profile_path                  = $PROFILE
      profile_exists                = (Test-Path $PROFILE)
      profile_signature             = if ($profileSignature) { $profileSignature.Status.ToString() } else { 'profile_missing' }
      mise_activation_block_type    = $miseAudit.activation_block_type
      mise_activated                = $miseAudit.mise_activated
      mise_shell                    = $miseAudit.mise_shell
      mise_shims_on_path            = $miseAudit.mise_shims_on_path
      windows_terminal_default_pwsh = $terminalAudit.default_pwsh
    }
    tools = @{
      scoop = (Test-CommandExists 'scoop')
      scoop_outdated = @{
        checked = $scoopOutdated.checked
        uses_local_metadata = $scoopOutdated.uses_local_metadata
        packages = $scoopOutdated.packages
        foundation_packages = $scoopOutdated.foundation_packages
        note = $scoopOutdated.note
      }
      mise = (Test-CommandExists 'mise')
      mise_outdated = @{
        checked = $miseOutdated.checked
        tools = $miseOutdated.tools
        note = $miseOutdated.note
      }
      foundation_packages = @{}
      mise_method = Get-MiseInstallMethod
    }
    configs = @{
      dotfiles_repo = (Test-Path (Join-Path $DotfilesDir '.git'))
      state_file = (Test-Path $STATE_FILE_PATH)
      mise_config = (Test-Path $MiseConfigPath)
      mise_env = (Test-Path $MiseEnvPath)
      golden_bundle = (Test-Path $GoldenBundlePath)
    }
    signing = @{
      requires_signing = $RequiresSigning
      cert_present = ($null -ne (Get-LocalCodeSigningCert))
    }
    zscaler = @{
      detected = $script:Detection.detected
      detection_sources = $script:Detection.detection_sources
      live_tls_checked = $script:Detection.live_tls_checked
      live_tls_detected = $script:Detection.live_tls_detected
      live_tls_host = $script:Detection.live_tls_host
      live_tls_subject = $script:Detection.live_tls_subject
      live_tls_issuer = $script:Detection.live_tls_issuer
      store_detected = $script:Detection.store_detected
      store_cert_count = $script:Detection.store_cert_count
      store_certs = $script:Detection.store_certs
      state_value = Get-StateValue -Key 'ENABLE_ZSCALER'
      effective_value = Get-ZscalerEffectiveValue
      zscaler_bundle = (Test-Path $ZscalerBundlePath)
      golden_bundle = (Test-Path $GoldenBundlePath)
      mise_env_present = (Test-Path $MiseEnvPath)
    }
  }

  if (Test-CommandExists 'scoop') {
    foreach ($package in $FoundationPackages) {
      $result.tools.foundation_packages[$package] = Test-ScoopPackageInstalled -Name $package
    }
  }

  $result | ConvertTo-Json -Depth 8
}


if ($Json) {
  Invoke-AuditJson
  return
}

Write-Host ''
Write-Host '=============================================================' -ForegroundColor DarkGray
Write-Host '  Windows Machine Audit' -ForegroundColor White
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host '  Read-only audit' -ForegroundColor DarkGray
Write-Host '=============================================================' -ForegroundColor DarkGray

switch ($Section) {
  'tools'   { Invoke-AuditTools }
  'shell'   { Invoke-AuditShell }
  'configs' { Invoke-AuditConfigs }
  'signing' { Invoke-AuditSigning }
  'zscaler' { Invoke-AuditZscaler }
  'all' {
    Invoke-AuditTools
    Invoke-AuditShell
    Invoke-AuditConfigs
    Invoke-AuditSigning
    Invoke-AuditZscaler
  }
}

if ($PopulateState) {
  Invoke-PopulateState
}

Write-Host ''
Write-Host 'Audit complete.' -ForegroundColor Green
