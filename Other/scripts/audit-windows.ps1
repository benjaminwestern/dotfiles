# =============================================================================
# audit-windows.ps1 -- Standalone Windows machine state audit
#
# Performs a comprehensive, read-only audit of the current machine state. Use it
# to see what's installed before running the bootstrap, verify the bootstrap
# completed correctly, or diagnose drift between expected and actual state.
#
# This is the Windows parallel of audit-macos.zsh. It covers Scoop, mise, shell
# configuration, code signing health, Zscaler trust, and config file state.
#
# Usage:
#   .\audit-windows.ps1                      # Full audit
#   .\audit-windows.ps1 -Section tools       # Audit only tools
#   .\audit-windows.ps1 -Section signing     # Audit signing health
#   .\audit-windows.ps1 -Json                # Machine-readable JSON output
#   .\audit-windows.ps1 -PopulateState       # Full audit + populate state file
#
# Exit codes:
#   0 -- audit completed (does not mean everything is installed)
#   1 -- audit script itself failed to run
#
# This script is read-only by default. The -PopulateState switch writes
# discovered machine state into the state file (~/.config/dotfiles/state.env)
# so a subsequent bootstrap run can use it as a baseline.
# =============================================================================

param(
  [ValidateSet('tools', 'shell', 'configs', 'signing', 'zscaler', 'all')]
  [string]$Section = 'all',
  [switch]$Json,
  [switch]$PopulateState
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'lib\common.ps1')
. (Join-Path $ScriptDir 'windows-signing-helpers.ps1')


# =============================================================================
# CONSTANTS
# =============================================================================

# Foundation Scoop packages (must match foundation-windows.ps1)
$FoundationPackages = @(
  'git', 'gh', 'jq', 'jid', 'yq', 'fzf', 'fd', 'ripgrep', 'zoxide',
  'lazygit', 'charm-gum', 'vscode', 'openssl'
)

$DotfilesDir      = Join-Path $HOME '.dotfiles'
$MiseConfigDir    = Join-Path $HOME '.config\mise'
$MiseConfigPath   = Join-Path $MiseConfigDir 'config.toml'
$MiseEnvPath      = Join-Path $MiseConfigDir '.env'
$CertsDir         = Join-Path $HOME 'certs'
$GoldenBundlePath = Join-Path $CertsDir 'golden_pem.pem'
$ZscalerBundlePath = Join-Path $CertsDir 'zscaler_ca_bundle.pem'


# =============================================================================
# HELPERS
# =============================================================================

function Write-AuditLine {
  <#
  .SYNOPSIS
      Print a single audit inventory row.
  .DESCRIPTION
      Formats a label-value pair for consistent audit output.
  #>
  param(
    [string]$Label,
    [string]$Value
  )
  "  {0,-35} {1}" -f $Label, $Value
}

function Write-SectionHeader {
  <#
  .SYNOPSIS
      Print a section divider.
  #>
  param([string]$Title)
  Write-Host ""
  Write-Host "── $Title ──" -ForegroundColor Cyan
  Write-Host ""
}


# =============================================================================
# SECTION: TOOLS
# =============================================================================

function Invoke-AuditTools {
  <#
  .SYNOPSIS
      Audit package managers, CLI tools, and runtimes.
  .DESCRIPTION
      Checks availability and versions of Scoop, foundation packages, mise,
      and mise-managed runtimes. All checks are read-only.
  #>
  Write-SectionHeader 'Tools & Package Managers'

  # Scoop
  if (Test-CommandExists 'scoop') {
    $scoopVer = scoop --version 2>$null
    Write-AuditLine 'Scoop:' $scoopVer
  } else {
    Write-AuditLine 'Scoop:' 'NOT INSTALLED'
  }

  # Foundation packages
  if (Test-CommandExists 'scoop') {
    $present = 0
    $missing = 0
    $missingList = @()
    foreach ($pkg in $FoundationPackages) {
      $installed = scoop list $pkg 2>$null
      if ($installed -match $pkg) {
        $present++
      } else {
        $missing++
        $missingList += $pkg
      }
    }
    Write-AuditLine 'Foundation packages:' "$present/$($FoundationPackages.Count) present"
    if ($missingList.Count -gt 0) {
      Write-AuditLine '  Missing:' ($missingList -join ', ')
    }
  } else {
    Write-AuditLine 'Foundation packages:' 'cannot check (Scoop not installed)'
  }

  # Mise (separate from foundation packages — can be Scoop or shell installer)
  if (Test-CommandExists 'mise') {
    $miseVer = mise --version 2>$null
    $method = 'unknown'
    $scoopMise = scoop list mise 2>$null
    if ($scoopMise -match 'mise') {
      $method = 'scoop'
    } elseif (Test-Path (Join-Path $HOME '.local\bin\mise.exe')) {
      $method = 'shell installer'
    }
    Write-AuditLine 'Mise:' "$miseVer ($method)"

    # Count installed tools
    $toolLines = mise list 2>$null
    if ($toolLines) {
      $toolCount = ($toolLines | Measure-Object -Line).Lines
      Write-AuditLine '  Installed tools:' $toolCount
    }
  } else {
    Write-AuditLine 'Mise:' 'NOT INSTALLED'
  }

  # Extra tools
  foreach ($tool in @('gum', 'lazygit', 'git', 'gh', 'openssl')) {
    if (Test-CommandExists $tool) {
      $ver = & $tool --version 2>$null | Select-Object -First 1
      Write-AuditLine "${tool}:" ($ver ?? 'installed')
    } else {
      Write-AuditLine "${tool}:" 'not installed'
    }
  }

  # Mise-managed runtimes
  foreach ($runtime in @('node', 'python', 'go', 'terraform')) {
    if (Test-CommandExists $runtime) {
      $ver = & $runtime --version 2>$null | Select-Object -First 1
      Write-AuditLine "${runtime}:" $ver
    } else {
      Write-AuditLine "${runtime}:" 'not installed'
    }
  }
}


# =============================================================================
# SECTION: SHELL
# =============================================================================

function Invoke-AuditShell {
  <#
  .SYNOPSIS
      Audit PowerShell configuration state.
  .DESCRIPTION
      Checks execution policy, profile existence, managed block presence,
      and shell activation (mise, zoxide).
  #>
  Write-SectionHeader 'Shell Configuration'

  Write-AuditLine 'PowerShell version:' $PSVersionTable.PSVersion.ToString()
  Write-AuditLine 'Execution policy (User):' (Get-ExecutionPolicy -Scope CurrentUser).ToString()
  Write-AuditLine 'Execution policy (Effective):' (Get-ExecutionPolicy).ToString()

  # Profile
  Write-AuditLine 'Profile path:' $PROFILE
  if (Test-Path $PROFILE) {
    Write-AuditLine 'Profile exists:' 'yes'
    $content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($PROFILE_BEGIN)) {
      Write-AuditLine '  Managed block:' 'present'
    } else {
      Write-AuditLine '  Managed block:' 'ABSENT'
    }

    # Profile signature
    $sig = Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
    if ($sig) {
      Write-AuditLine '  Signature:' $sig.Status.ToString()
    } else {
      Write-AuditLine '  Signature:' 'not checked'
    }
  } else {
    Write-AuditLine 'Profile exists:' 'NO'
  }

  # Shell activations
  if (Test-CommandExists 'mise') {
    Write-AuditLine 'Mise activation:' 'available'
  } else {
    Write-AuditLine 'Mise activation:' 'mise not found'
  }

  if (Test-CommandExists 'zoxide') {
    Write-AuditLine 'Zoxide activation:' 'available'
  } else {
    Write-AuditLine 'Zoxide activation:' 'zoxide not found'
  }
}


# =============================================================================
# SECTION: CONFIGS
# =============================================================================

function Invoke-AuditConfigs {
  <#
  .SYNOPSIS
      Audit configuration files and state.
  .DESCRIPTION
      Checks dotfiles repo, state file contents, mise config, certificates,
      and system information.
  #>
  Write-SectionHeader 'Configuration & State'

  # Dotfiles repo
  if (Test-Path (Join-Path $DotfilesDir '.git')) {
    Write-AuditLine 'Dotfiles repo:' "present at $DotfilesDir"
    $branch = git -C $DotfilesDir branch --show-current 2>$null
    Write-AuditLine '  Branch:' ($branch ?? 'unknown')
    $statusCount = (git -C $DotfilesDir status --porcelain 2>$null | Measure-Object -Line).Lines
    if ($statusCount -eq 0) {
      Write-AuditLine '  Working tree:' 'clean'
    } else {
      Write-AuditLine '  Working tree:' "$statusCount uncommitted changes"
    }
  } else {
    Write-AuditLine 'Dotfiles repo:' "NOT FOUND at $DotfilesDir"
  }

  # State file
  if (Test-Path $STATE_FILE_PATH) {
    Write-AuditLine 'State file:' "present at $STATE_FILE_PATH"
    Get-Content $STATE_FILE_PATH | ForEach-Object {
      if ($_ -and -not $_.StartsWith('#') -and $_.Contains('=')) {
        $parts = $_.Split('=', 2)
        Write-AuditLine "  $($parts[0]):" $parts[1]
      }
    }
  } else {
    Write-AuditLine 'State file:' 'absent (first run or deleted)'
  }

  # Mise config
  if (Test-Path $MiseConfigPath) {
    Write-AuditLine 'Mise config:' 'present'
    $content = Get-Content $MiseConfigPath -Raw -ErrorAction SilentlyContinue
    if ($content -and $content.Contains($MISE_BEGIN)) {
      Write-AuditLine '  Seed block:' 'present'
    } else {
      Write-AuditLine '  Seed block:' 'absent (user-owned config)'
    }
  } else {
    Write-AuditLine 'Mise config:' 'absent'
  }

  # Mise env
  if (Test-Path $MiseEnvPath) {
    Write-AuditLine 'Mise .env:' 'present'
    $envContent = Get-Content $MiseEnvPath -Raw -ErrorAction SilentlyContinue
    if ($envContent -and $envContent.Contains('ZSCALER')) {
      Write-AuditLine '  Zscaler vars:' 'present'
    }
  } else {
    Write-AuditLine 'Mise .env:' 'absent'
  }

  # Certificates
  if (Test-Path $GoldenBundlePath) {
    $certCount = (Get-Content $GoldenBundlePath | Select-String 'BEGIN CERTIFICATE').Count
    Write-AuditLine 'Golden CA bundle:' "present ($certCount certs)"
  } else {
    Write-AuditLine 'Golden CA bundle:' 'absent'
  }

  # System info
  Write-AuditLine 'Windows version:' [System.Environment]::OSVersion.Version.ToString()
  Write-AuditLine 'Architecture:' $env:PROCESSOR_ARCHITECTURE
  Write-AuditLine 'Username:' $env:USERNAME
  Write-AuditLine 'Home:' $HOME
}


# =============================================================================
# SECTION: SIGNING
# =============================================================================

function Invoke-AuditSigning {
  <#
  .SYNOPSIS
      Audit code signing health under AllSigned policy.
  .DESCRIPTION
      Checks for the local code-signing certificate, scans Scoop and mise
      directories for unsigned .ps1 files, and verifies the profile signature.
      Most useful on AllSigned machines; on others, reports signing is not
      required.
  #>
  Write-SectionHeader 'Code Signing Health'

  $policy = Get-ExecutionPolicy
  $requiresSigning = $policy -eq 'AllSigned'
  Write-AuditLine 'Effective policy:' $policy.ToString()
  Write-AuditLine 'Signing required:' $(if ($requiresSigning) { 'YES' } else { 'no' })

  # Code-signing certificate
  $cert = Get-LocalCodeSigningCert
  if ($cert) {
    Write-AuditLine 'Signing cert:' "CN=LocalScoopSigner (expires $($cert.NotAfter.ToString('yyyy-MM-dd')))"
  } else {
    if ($requiresSigning) {
      Write-AuditLine 'Signing cert:' 'NOT FOUND — required for AllSigned'
    } else {
      Write-AuditLine 'Signing cert:' 'not found (not required)'
    }
  }

  # Scoop scripts
  $scoopDir = Join-Path $env:USERPROFILE 'scoop'
  if (Test-Path $scoopDir) {
    $scoopScripts = Get-ChildItem $scoopDir -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue
    $scoopTotal = ($scoopScripts | Measure-Object).Count
    $unsignedScoop = $scoopScripts |
      Get-AuthenticodeSignature -ErrorAction SilentlyContinue |
      Where-Object Status -ne 'Valid'
    $unsignedScoopCount = ($unsignedScoop | Measure-Object).Count
    if ($unsignedScoopCount -eq 0) {
      Write-AuditLine 'Scoop .ps1 files:' "$scoopTotal total, all signed"
    } else {
      Write-AuditLine 'Scoop .ps1 files:' "$scoopTotal total, $unsignedScoopCount UNSIGNED"
      $unsignedScoop | Select-Object -First 5 | ForEach-Object {
        Write-AuditLine '  Unsigned:' $_.Path
      }
    }
  } else {
    Write-AuditLine 'Scoop .ps1 files:' 'Scoop directory not found'
  }

  # Mise scripts
  $miseDir = Join-Path $HOME 'AppData\Local\mise'
  if (Test-Path $miseDir) {
    $miseScripts = Get-ChildItem $miseDir -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue
    $miseTotal = ($miseScripts | Measure-Object).Count
    $unsignedMise = $miseScripts |
      Get-AuthenticodeSignature -ErrorAction SilentlyContinue |
      Where-Object Status -ne 'Valid'
    $unsignedMiseCount = ($unsignedMise | Measure-Object).Count
    if ($unsignedMiseCount -eq 0) {
      Write-AuditLine 'Mise .ps1 files:' "$miseTotal total, all signed"
    } else {
      Write-AuditLine 'Mise .ps1 files:' "$miseTotal total, $unsignedMiseCount UNSIGNED"
      $unsignedMise | Select-Object -First 5 | ForEach-Object {
        Write-AuditLine '  Unsigned:' $_.Path
      }
    }
  } else {
    Write-AuditLine 'Mise .ps1 files:' 'mise directory not found'
  }

  # Profile signature
  if (Test-Path $PROFILE) {
    $sig = Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
    Write-AuditLine 'Profile signature:' $sig.Status.ToString()
    if ($sig.Status -eq 'HashMismatch') {
      Write-AuditLine '  Recovery:' 'Run Sign-Profile to re-sign after edits'
    }
  } else {
    Write-AuditLine 'Profile signature:' 'profile does not exist'
  }
}


# =============================================================================
# SECTION: ZSCALER
# =============================================================================

function Invoke-AuditZscaler {
  <#
  .SYNOPSIS
      Audit Zscaler TLS trust configuration.
  .DESCRIPTION
      Checks certificate stores for Zscaler CA certs, verifies the CA bundle
      chain, checks mise .env and user-scope env vars, and validates
      cert-sensitive tools (git, node, npm, pip).
  #>
  Write-SectionHeader 'Zscaler TLS Trust'

  # Certificate store scan
  $zscalerCerts = Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Issuer -match 'Zscaler' }
  if ($zscalerCerts -and $zscalerCerts.Count -gt 0) {
    Write-AuditLine 'Zscaler in cert stores:' "YES ($($zscalerCerts.Count) certs found)"
    $zscalerCerts | ForEach-Object {
      Write-AuditLine '  Cert:' "$($_.Subject) (expires $($_.NotAfter.ToString('yyyy-MM-dd')))"
    }
  } else {
    Write-AuditLine 'Zscaler in cert stores:' 'not detected'
  }

  # Bundle files
  if (Test-Path $ZscalerBundlePath) {
    $zBundleCount = (Get-Content $ZscalerBundlePath | Select-String 'BEGIN CERTIFICATE').Count
    Write-AuditLine 'Zscaler CA bundle:' "present ($zBundleCount certs)"
  } else {
    Write-AuditLine 'Zscaler CA bundle:' 'absent'
  }

  if (Test-Path $GoldenBundlePath) {
    $gBundleCount = (Get-Content $GoldenBundlePath | Select-String 'BEGIN CERTIFICATE').Count
    Write-AuditLine 'Golden CA bundle:' "present ($gBundleCount certs)"
  } else {
    Write-AuditLine 'Golden CA bundle:' 'absent'
  }

  # Mise .env Zscaler block
  if (Test-Path $MiseEnvPath) {
    $envContent = Get-Content $MiseEnvPath -Raw -ErrorAction SilentlyContinue
    if ($envContent -and $envContent.Contains($ZSCALER_ENV_BEGIN)) {
      Write-AuditLine 'Mise .env Zscaler block:' 'present'
    } else {
      Write-AuditLine 'Mise .env Zscaler block:' 'absent'
    }
  } else {
    Write-AuditLine 'Mise .env:' 'file does not exist'
  }

  # User-scope env vars
  $envVarsToCheck = @(
    'SSL_CERT_FILE', 'NODE_EXTRA_CA_CERTS', 'REQUESTS_CA_BUNDLE',
    'CURL_CA_BUNDLE', 'GIT_SSL_CAINFO', 'PIP_CERT', 'NPM_CONFIG_CAFILE'
  )
  foreach ($var in $envVarsToCheck) {
    $val = [Environment]::GetEnvironmentVariable($var, 'User')
    if ($val) {
      $exists = if (Test-Path $val) { 'file exists' } else { 'FILE MISSING' }
      Write-AuditLine "  ${var}:" "$val ($exists)"
    } else {
      Write-AuditLine "  ${var}:" 'not set'
    }
  }

  # Git sslcainfo
  if (Test-CommandExists 'git') {
    $gitCa = git config --global --get http.sslcainfo 2>$null
    if ($gitCa) {
      Write-AuditLine 'Git http.sslcainfo:' $gitCa
    } else {
      Write-AuditLine 'Git http.sslcainfo:' 'not configured'
    }
  }

  # TLS-sensitive tool checks
  if (Test-CommandExists 'node') {
    $nodeCA = node -p "process.env.NODE_EXTRA_CA_CERTS" 2>$null
    Write-AuditLine 'Node CA env:' ($nodeCA ?? 'not set in process')
  }

  if (Test-CommandExists 'npm') {
    # Use npm.cmd to avoid .ps1 signing issues
    $npmCafile = npm.cmd config get cafile 2>$null
    Write-AuditLine 'npm cafile config:' ($npmCafile ?? 'not set')
  }
}


# =============================================================================
# STATE FILE POPULATION
# =============================================================================

function Invoke-PopulateState {
  <#
  .SYNOPSIS
      Write discovered machine state into the state file.
  .DESCRIPTION
      Uses the audit data already gathered to populate the state file with
      baseline values. This lets a subsequent bootstrap run pick up where
      the audit left off without re-prompting.

      Detects:
        PREFERRED_SHELL   -- always 'pwsh' on Windows
        DEVICE_PROFILE    -- preserved if already set, otherwise 'minimal'
        ENABLE_ZSCALER    -- true/false based on cert store scan
        ENABLE_MISE_TOOLS -- true if mise is installed and has tools
  .NOTES
      Checks: cert stores, command availability, existing state file
      Gates: None
      Side effects: Writes to state file via Set-StateValue
      Idempotency: Overwrites with the same detected values.
  #>

  # PREFERRED_SHELL: always pwsh on Windows
  Set-StateValue -Key 'PREFERRED_SHELL' -Value 'pwsh'
  Write-AuditLine '  PREFERRED_SHELL:' 'pwsh'

  # DEVICE_PROFILE: keep existing if set, otherwise 'minimal'
  $existingProfile = Get-StateValue -Key 'DEVICE_PROFILE'
  if (-not $existingProfile) { $existingProfile = 'minimal' }
  Set-StateValue -Key 'DEVICE_PROFILE' -Value $existingProfile
  Write-AuditLine '  DEVICE_PROFILE:' $existingProfile

  # ENABLE_ZSCALER: detect from cert stores
  $zscalerCerts = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Issuer -match 'Zscaler' }
  $zscalerDetected = ($null -ne $zscalerCerts -and $zscalerCerts.Count -gt 0)
  $zscalerValue = if ($zscalerDetected) { 'true' } else { 'false' }
  Set-StateValue -Key 'ENABLE_ZSCALER' -Value $zscalerValue
  Write-AuditLine '  ENABLE_ZSCALER:' "$zscalerValue (detected: $zscalerDetected)"

  # ENABLE_MISE_TOOLS: check if mise is installed
  $miseInstalled = Test-CommandExists 'mise'
  $miseToolsValue = if ($miseInstalled) { 'true' } else { 'true' }  # default true even if not yet installed
  Set-StateValue -Key 'ENABLE_MISE_TOOLS' -Value $miseToolsValue
  Write-AuditLine '  ENABLE_MISE_TOOLS:' $miseToolsValue

  Write-Host ''
  Write-Host "  State file written: $STATE_FILE_PATH" -ForegroundColor Green
}


# =============================================================================
# JSON OUTPUT
# =============================================================================

function Invoke-AuditJson {
  <#
  .SYNOPSIS
      Output the full audit as a JSON object.
  .DESCRIPTION
      Collects the same checks as the section functions but formats results
      as JSON for machine consumption. Useful for CI, logging, or diffing.
  #>
  $result = @{
    timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
    system = @{
      windows_version = [System.Environment]::OSVersion.Version.ToString()
      architecture    = $env:PROCESSOR_ARCHITECTURE
      username        = $env:USERNAME
    }
    shell = @{
      powershell_version = $PSVersionTable.PSVersion.ToString()
      execution_policy   = (Get-ExecutionPolicy).ToString()
      profile_exists     = (Test-Path $PROFILE)
      profile_signed     = $false
    }
    tools = @{
      scoop = (Test-CommandExists 'scoop')
      mise  = (Test-CommandExists 'mise')
      git   = (Test-CommandExists 'git')
      gum   = (Test-CommandExists 'gum')
    }
    configs = @{
      dotfiles_repo    = (Test-Path (Join-Path $DotfilesDir '.git'))
      state_file       = (Test-Path $STATE_FILE_PATH)
      mise_config      = (Test-Path $MiseConfigPath)
      golden_ca_bundle = (Test-Path $GoldenBundlePath)
    }
    signing = @{
      requires_signing = ((Get-ExecutionPolicy) -eq 'AllSigned')
      cert_present     = ($null -ne (Get-LocalCodeSigningCert))
    }
  }

  # Profile signature
  if (Test-Path $PROFILE) {
    $sig = Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
    $result.shell.profile_signed = ($sig -and $sig.Status -eq 'Valid')
  }

  # Foundation packages
  $pkgStatus = @{}
  if (Test-CommandExists 'scoop') {
    foreach ($pkg in $FoundationPackages) {
      $installed = scoop list $pkg 2>$null
      $pkgStatus[$pkg] = [bool]($installed -match $pkg)
    }
  }
  $result.tools['foundation_packages'] = $pkgStatus

  # Mise install method
  if (Test-CommandExists 'mise') {
    $scoopMise = scoop list mise 2>$null
    if ($scoopMise -match 'mise') {
      $result.tools['mise_method'] = 'scoop'
    } elseif (Test-Path (Join-Path $HOME '.local\bin\mise.exe')) {
      $result.tools['mise_method'] = 'shell_installer'
    } else {
      $result.tools['mise_method'] = 'unknown'
    }
  }

  # Zscaler
  $zscalerCerts = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Issuer -match 'Zscaler' }
  $result['zscaler'] = @{
    detected         = ($null -ne $zscalerCerts -and $zscalerCerts.Count -gt 0)
    zscaler_bundle   = (Test-Path $ZscalerBundlePath)
    golden_bundle    = (Test-Path $GoldenBundlePath)
    mise_env_present = (Test-Path $MiseEnvPath)
  }

  $result['state_populated'] = [bool]$PopulateState
  $result | ConvertTo-Json -Depth 4
}


# =============================================================================
# MAIN
# =============================================================================

if ($Json) {
  Invoke-AuditJson
  return
}

Write-Host ''
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor DarkGray
Write-Host '  Windows Machine Audit' -ForegroundColor White
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host '  Read-only — no changes will be made' -ForegroundColor DarkGray
Write-Host '═══════════════════════════════════════════════════════════════' -ForegroundColor DarkGray

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
  Write-SectionHeader 'State File Population'
  Invoke-PopulateState
}

Write-Host ''
Write-Host 'Audit complete.' -ForegroundColor Green
