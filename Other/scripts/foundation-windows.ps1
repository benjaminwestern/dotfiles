# =============================================================================
# foundation-windows.ps1 -- Windows foundation bootstrap
#
# Installs and configures the core tooling layer that every Windows machine
# needs regardless of personal preferences: Scoop, CLI utilities, signed
# PowerShell profile, mise language runtime seeding, and optional Zscaler TLS
# trust.
#
# Architecture:
#   Dot-sources lib/common.ps1 for all shared utilities (status output, state
#   file, flag resolution, managed block writer).
#   Dot-sources windows-signing-helpers.ps1 for code signing functions.
#
# Design principles:
#   - Absolute idempotency: check before act, never destructive
#   - Feature-flag gating: every function respects RESOLVED_* flags
#   - Status output: every ensure/check emits Write-Status* calls
#   - AllSigned safe: all .ps1 files are signed after creation/modification
# =============================================================================

param(
  [ValidateSet('setup', 'ensure', 'update', 'personal')]
  [string]$Mode,
  [string]$Shell,
  [string]$Profile_,   # "Profile" conflicts with PS auto-var
  [switch]$NonInteractive,
  [switch]$Personal,
  [switch]$DryRun,
  [string]$DotfilesRepo,
  [string]$PersonalScript,
  [hashtable]$EnableFlags = @{},
  [hashtable]$DisableFlags = @{}
)

$ErrorActionPreference = 'Stop'


# =============================================================================
# SECTION 1: HEADER & CONSTANTS
# =============================================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'lib\common.ps1')
. (Join-Path $ScriptDir 'windows-signing-helpers.ps1')

# -- Dry-run flag -------------------------------------------------------------
# Honour both the -DryRun switch and the DRY_RUN env var (set by bootstrap.sh).
if ($DryRun -or $env:DRY_RUN -eq '1') { $global:DRY_RUN = $true }

# -- Foundation Scoop packages ------------------------------------------------
# NOTE: mise is NOT in this list. Like macOS, mise can be installed via Scoop
# or the shell installer (irm https://mise.run | iex). The Ensure-Mise function
# handles both paths. On AllSigned systems with Zscaler, Scoop is required so
# that mise's .ps1 shims can be signed with the local code-signing cert.
$FoundationPackages = @(
  'git', 'gh', 'jq', 'jid', 'yq', 'fzf', 'fd', 'ripgrep', 'zoxide',
  'lazygit', 'charm-gum', 'vscode', 'openssl'
)

# -- Signing detection --------------------------------------------------------
# Detect whether the current execution policy requires script signing.
# This determines whether we need to sign Scoop/mise scripts after install.
$RequiresSigning = (Get-ExecutionPolicy -Scope CurrentUser) -eq 'AllSigned' -or
                   (Get-ExecutionPolicy -Scope Process) -eq 'AllSigned' -or
                   (Get-ExecutionPolicy) -eq 'AllSigned'

# -- Mise paths ---------------------------------------------------------------
$MiseConfigDir  = Join-Path $HOME '.config\mise'
$MiseConfigPath = Join-Path $MiseConfigDir 'config.toml'
$MiseEnvPath    = Join-Path $MiseConfigDir '.env'

# -- Certificate / Zscaler paths ---------------------------------------------
$CertsDir          = Join-Path $HOME 'certs'
$ZscalerCaDir      = Join-Path $CertsDir 'zscaler-ca'
$ZscalerBundlePath = Join-Path $CertsDir 'zscaler_ca_bundle.pem'
$GoldenBundlePath  = Join-Path $CertsDir 'golden_pem.pem'

# -- Bootstrap root -----------------------------------------------------------
$BootstrapRoot = if ($env:BOOTSTRAP_ROOT) {
  $env:BOOTSTRAP_ROOT
} else {
  Split-Path -Parent (Split-Path -Parent $ScriptDir)
}

# -- DotfilesRepo default -----------------------------------------------------
if (-not $DotfilesRepo) {
  $DotfilesRepo = if ($env:DOTFILES_REPO) {
    $env:DOTFILES_REPO
  } else {
    'https://github.com/benjaminwestern/dotfiles.git'
  }
}


# =============================================================================
# SECTION 2: SCOOP
# =============================================================================

function Ensure-Scoop {
  <#
  .SYNOPSIS
      Install Scoop, with AllSigned signing support when required.
  .DESCRIPTION
      Checks for an existing Scoop installation. If absent, downloads and
      runs the Scoop installer. When the execution policy is AllSigned, the
      installer is patched, a local code-signing certificate is created, the
      installer is signed, and all Scoop .ps1 files are signed after install.
      Under non-AllSigned policies, Scoop is installed without signing.
  .NOTES
      Checks: Get-Command scoop, execution policy, cert store
      Gates: None (always runs)
      Side effects: May create certificate, install Scoop, sign scripts
      Idempotency: No-op if Scoop is already installed.
  #>
  if (Test-CommandExists 'scoop') {
    Write-StatusPass 'Scoop' -Detail 'already installed'
    return
  }

  # -- Dry-run: report what would happen and return ---------------------------
  if (Test-DryRun) {
    if ($RequiresSigning) {
      Write-DryRunLog 'download Scoop installer, create signing cert, patch + sign installer, install Scoop, sign all .ps1 files'
    } else {
      Write-DryRunLog 'download and run Scoop installer'
    }
    Write-DryRunLog 'scoop bucket add extras'
    Write-StatusFix 'Scoop' -Action 'would install'
    return
  }

  # -- Step 1: Download the Scoop installer -----------------------------------
  $installerPath = Join-Path $env:TEMP 'install-scoop.ps1'
  Write-Host '  Downloading Scoop installer...' -ForegroundColor Cyan
  Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1' `
    -OutFile $installerPath

  if ($RequiresSigning) {
    # -- AllSigned path: cert + patch + sign ----------------------------------

    # Ensure code-signing certificate
    $cert = Get-LocalCodeSigningCert
    if (-not $cert) {
      Write-Host '  Creating local code-signing certificate (CN=LocalScoopSigner)...' -ForegroundColor Cyan

      $cert = New-SelfSignedCertificate `
        -Type CodeSigningCert `
        -Subject 'CN=LocalScoopSigner' `
        -CertStoreLocation 'Cert:\CurrentUser\My'

      # Export and import into Root + TrustedPublisher for trust
      $cerPath = Join-Path $env:TEMP 'LocalScoopSigner.cer'
      Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null
      certutil -user -addstore Root $cerPath -f | Out-Null
      certutil -user -addstore TrustedPublisher $cerPath -f | Out-Null
      Remove-Item $cerPath -ErrorAction SilentlyContinue
    }

    # Patch the installer to accept AllSigned
    $content = Get-Content $installerPath -Raw
    $content = $content -replace `
      "@\('Unrestricted', 'RemoteSigned', 'ByPass'\)", `
      "@('Unrestricted', 'RemoteSigned', 'ByPass', 'AllSigned')"
    Set-Content -Path $installerPath -Value $content -Encoding Ascii

    # Sign the installer
    Set-AuthenticodeSignature -FilePath $installerPath -Certificate $cert | Out-Null

    # Run the installer
    Write-Host '  Running Scoop installer (AllSigned)...' -ForegroundColor Cyan
    & $installerPath -RunAsAdmin:$false

    # Sign all Scoop .ps1 files
    Sign-ScoopScripts

    Write-StatusFix 'Scoop' -Action 'installed with signed certificate (AllSigned)'
  } else {
    # -- Non-AllSigned path: standard install ---------------------------------

    # Set execution policy if it's too restrictive for the installer
    $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($currentPolicy -eq 'Restricted') {
      Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    }

    Write-Host '  Running Scoop installer...' -ForegroundColor Cyan
    & $installerPath -RunAsAdmin:$false

    Write-StatusFix 'Scoop' -Action 'installed'
  }

  # Add the extras bucket (both paths)
  scoop bucket add extras 2>$null
}


# =============================================================================
# SECTION 3: FOUNDATION PACKAGES
# =============================================================================

function Ensure-FoundationPackages {
  <#
  .SYNOPSIS
      Install missing Scoop packages from the foundation list.
  .DESCRIPTION
      Ensures the extras bucket is present, then iterates the package list
      and installs any that are missing. Re-signs all Scoop scripts after
      installation ONLY when the execution policy requires it (AllSigned).
  .NOTES
      Checks: scoop bucket list, scoop list per package
      Gates: None (always runs)
      Side effects: Installs Scoop packages, conditionally signs scripts
      Idempotency: Skips packages that are already installed.
  #>

  # Ensure extras bucket (read-only check, then add if missing)
  $buckets = scoop bucket list 2>$null
  if ($buckets -notmatch 'extras') {
    Invoke-OrDry -Label 'scoop bucket add extras' -Command { scoop bucket add extras 2>$null }
  }

  $present = 0
  $missing = 0
  $total   = $FoundationPackages.Count

  foreach ($pkg in $FoundationPackages) {
    $installed = scoop list $pkg 2>$null
    if ($installed -match $pkg) {
      $present++
    } else {
      Invoke-OrDry -Label "scoop install $pkg" -Command ([scriptblock]::Create("scoop install $pkg 2>`$null"))
      $missing++
    }
  }

  # Re-sign after all installs only if AllSigned policy requires it
  if ($RequiresSigning) {
    Invoke-OrDry -Label 'Sign-ScoopScripts' -Command { Sign-ScoopScripts }
  }

  if ($missing -eq 0) {
    Write-StatusPass 'Foundation packages' -Detail "${present}/${total} present"
  } else {
    if (Test-DryRun) {
      Write-StatusFix 'Foundation packages' -Action "would install ${missing} missing"
    } else {
      Write-StatusFix 'Foundation packages' -Action "installed ${missing} missing"
    }
  }
}


# =============================================================================
# SECTION 3b: MISE INSTALLATION
# =============================================================================

function Ensure-Mise {
  <#
  .SYNOPSIS
      Install mise if not present (Scoop OR shell installer).
  .DESCRIPTION
      Checks whether mise is already available on PATH. If not, the install
      strategy depends on the execution policy:

      - AllSigned policy → MUST use Scoop so the mise .ps1 shims can be signed
        with the local code-signing certificate. This is required when Zscaler
        or corporate policy enforces AllSigned.
      - Other policies → Try Scoop first (preferred for consistency with other
        foundation packages), fall back to the shell installer
        (irm https://mise.run | iex).

      After installation via Scoop under AllSigned, Sign-ScoopScripts AND
      Sign-MiseScripts are called to ensure all .ps1 files are trusted.

  .NOTES
      Checks: Test-CommandExists mise, execution policy
      Gates: None — always runs. mise is required for language runtimes.
      Side effects: Installs mise binary, may sign scripts
      Idempotency: No-op if mise is already on PATH.

      Install priority:
        1. Already installed (any method) → pass
        2. AllSigned policy → scoop install mise → sign
        3. Scoop available → scoop install mise
        4. Fallback → irm https://mise.run | iex
  #>

  if (Test-CommandExists 'mise') {
    $ver = mise --version 2>$null
    $method = 'unknown'
    $scoopMise = scoop list mise 2>$null
    if ($scoopMise -match 'mise') {
      $method = 'scoop'
    } elseif (Test-Path (Join-Path $HOME '.local\bin\mise.exe')) {
      $method = 'shell installer'
    }
    Write-StatusPass 'Mise' -Detail "$ver ($method)"
    return
  }

  if (Test-DryRun) {
    if ($RequiresSigning) {
      Write-DryRunLog 'scoop install mise + Sign-ScoopScripts + Sign-MiseScripts (AllSigned)'
    } else {
      Write-DryRunLog 'scoop install mise (or shell installer fallback)'
    }
    Write-StatusFix 'Mise' -Action 'would install'
    return
  }

  if ($RequiresSigning) {
    # AllSigned: MUST use Scoop so we can sign the mise .ps1 shims
    Write-Host '  AllSigned policy detected — installing mise via Scoop...' -ForegroundColor Cyan
    scoop install mise 2>$null
    Sign-ScoopScripts
    Sign-MiseScripts
    Write-StatusFix 'Mise' -Action 'installed via Scoop (signed for AllSigned)'
    return
  }

  # Non-AllSigned: try Scoop first, fall back to shell installer
  if (Test-CommandExists 'scoop') {
    scoop install mise 2>$null
    if (Test-CommandExists 'mise') {
      Write-StatusFix 'Mise' -Action 'installed via Scoop'
      return
    }
  }

  # Fallback: shell installer
  Write-Host '  Installing mise via shell installer...' -ForegroundColor Cyan
  irm https://mise.run | iex
  $env:PATH = "$HOME\.local\bin;$env:PATH"

  if (Test-CommandExists 'mise') {
    Write-StatusFix 'Mise' -Action 'installed via shell installer'
  } else {
    Write-StatusFail 'Mise' -Detail 'installation failed — neither Scoop nor shell installer succeeded'
  }
}


# =============================================================================
# SECTION 4: ZSCALER
# =============================================================================

function Detect-Zscaler {
  <#
  .SYNOPSIS
      Check Windows certificate stores for Zscaler CA certificates.
  .DESCRIPTION
      Searches LocalMachine\Root for certificates with Zscaler in the Issuer
      field. Returns $true if any are found.
  .NOTES
      Checks: Certificate stores
      Gates: None
      Side effects: None (read-only)
      Idempotency: Pure detection -- safe to call repeatedly.
  #>
  $zscalerCerts = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Issuer -match 'Zscaler' }
  return ($null -ne $zscalerCerts -and $zscalerCerts.Count -gt 0)
}

function Build-ZscalerBundle {
  <#
  .SYNOPSIS
      Export Zscaler CA certs and build a PEM bundle.
  .DESCRIPTION
      Finds all Zscaler CA certificates across Root and CA stores for both
      CurrentUser and LocalMachine, exports them to individual .cer files,
      converts them to PEM format, and concatenates into a bundle.
  .NOTES
      Checks: Certificate stores for Zscaler certs
      Gates: None
      Side effects: Creates files in ~/certs/zscaler-ca/
      Idempotency: Overwrites existing files with the same content.
  #>
  if (Test-DryRun) {
    Write-DryRunLog "export Zscaler CA certs to $CertsDir and build PEM bundle"
    return
  }

  New-Item -ItemType Directory -Force $CertsDir | Out-Null
  New-Item -ItemType Directory -Force $ZscalerCaDir | Out-Null

  $zscalerCaCerts = Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root,
    Cert:\CurrentUser\CA, Cert:\LocalMachine\CA -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Subject -like '*Zscaler*' -and
      $_.Subject -notlike '*CN=www.google.com*'
    }

  if (-not $zscalerCaCerts -or $zscalerCaCerts.Count -eq 0) {
    Write-StatusFail 'Zscaler CA certs' -Detail 'no Zscaler CA certificates found in stores'
  }

  # Export each cert to .cer
  $i = 0
  foreach ($c in $zscalerCaCerts) {
    $i++
    Export-Certificate -Cert $c -FilePath (Join-Path $ZscalerCaDir "zscaler-ca-$i.cer") -Force | Out-Null
  }

  # Build PEM bundle from the .cer files
  $pem = ''
  Get-ChildItem (Join-Path $ZscalerCaDir '*.cer') | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    $pem += "-----BEGIN CERTIFICATE-----`n"
    $pem += [Convert]::ToBase64String($bytes, 'InsertLineBreaks')
    $pem += "`n-----END CERTIFICATE-----`n"
  }
  Set-Content -Path $ZscalerBundlePath -Value $pem.Trim() -Encoding Ascii
}

function Build-GoldenBundle {
  <#
  .SYNOPSIS
      Concatenate Python certifi + Zscaler chain into golden PEM bundle.
  .DESCRIPTION
      Bootstraps Python via mise if needed, obtains the certifi CA bundle
      path, and concatenates it with the Zscaler CA bundle to create a
      complete trust store.
  .NOTES
      Checks: python command availability, certifi bundle existence
      Gates: None
      Side effects: Creates golden_pem.pem, may install Python via mise
      Idempotency: Overwrites golden bundle with the same content.
  #>
  if (Test-DryRun) {
    Write-DryRunLog "build golden CA bundle (certifi + Zscaler) at $GoldenBundlePath"
    return
  }

  # Ensure Python is available
  if (-not (Test-CommandExists 'python')) {
    mise install python@latest 2>$null
  }

  # Get certifi path
  $certifiPath = python -c "import pip._vendor.certifi as c; print(c.where())" 2>$null
  if (-not $certifiPath -or -not (Test-Path $certifiPath)) {
    python -m ensurepip --upgrade 2>$null
    $certifiPath = python -c "import pip._vendor.certifi as c; print(c.where())" 2>$null
  }

  if (-not $certifiPath -or -not (Test-Path $certifiPath)) {
    Write-StatusFail 'Golden bundle' -Detail 'unable to locate Python certifi bundle'
  }

  # Merge certifi + Zscaler
  $certifiContent = Get-Content $certifiPath -Raw
  $zscalerContent = Get-Content $ZscalerBundlePath -Raw
  $merged = $certifiContent.TrimEnd() + "`n" + $zscalerContent.Trim() + "`n"
  Set-Content -Path $GoldenBundlePath -Value $merged -Encoding Ascii
}

function Write-ZscalerMiseEnv {
  <#
  .SYNOPSIS
      Write TLS environment variables into mise .env file.
  .DESCRIPTION
      Generates a managed block with all TLS-related env vars pointing at the
      golden PEM bundle and writes it to the mise .env file using
      Write-ManagedBlock for idempotency.
  .NOTES
      Checks: Existing block content via Write-ManagedBlock
      Gates: None
      Side effects: Creates or modifies mise .env file
      Idempotency: No-op if block is already present and correct.
  #>
  Invoke-OrDry -Label "mkdir $MiseConfigDir" -Command { New-Item -ItemType Directory -Force $MiseConfigDir | Out-Null }

  # Use forward slashes for cross-tool compatibility
  $certFile = $GoldenBundlePath -replace '\\', '/'
  $certDir  = $CertsDir -replace '\\', '/'

  $block = @(
    $ZSCALER_ENV_BEGIN
    "SSL_CERT_FILE=`"$certFile`""
    "SSL_CERT_DIR=`"$certDir`""
    "CERT_PATH=`"$certFile`""
    "CERT_DIR=`"$certDir`""
    "REQUESTS_CA_BUNDLE=`"$certFile`""
    "CURL_CA_BUNDLE=`"$certFile`""
    "NODE_EXTRA_CA_CERTS=`"$certFile`""
    "GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=`"$certFile`""
    "GIT_SSL_CAINFO=`"$certFile`""
    "CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE=`"$certFile`""
    "PIP_CERT=`"$certFile`""
    "NPM_CONFIG_CAFILE=`"$certFile`""
    "npm_config_cafile=`"$certFile`""
    "AWS_CA_BUNDLE=`"$certFile`""
    $ZSCALER_ENV_END
  ) -join "`n"

  Write-ManagedBlock -FilePath $MiseEnvPath `
    -BeginMarker $ZSCALER_ENV_BEGIN `
    -EndMarker $ZSCALER_ENV_END `
    -BlockContent $block
}

function Set-ZscalerUserEnvVars {
  <#
  .SYNOPSIS
      Persist TLS env vars at user scope in the Windows registry.
  .DESCRIPTION
      Sets each TLS-related environment variable at the User scope so they
      survive reboots and are available in all new processes.
  .NOTES
      Checks: None
      Gates: None
      Side effects: Writes to user-scope environment variables
      Idempotency: Overwrites the same settings with the same values.
  #>
  if (Test-DryRun) {
    Write-DryRunLog 'set 14 TLS env vars at User scope (SSL_CERT_FILE, NODE_EXTRA_CA_CERTS, etc.)'
    return
  }

  $certFile = $GoldenBundlePath -replace '\\', '/'
  $certDir  = $CertsDir -replace '\\', '/'

  $vars = @{
    'SSL_CERT_FILE'                      = $certFile
    'SSL_CERT_DIR'                       = $certDir
    'CERT_PATH'                          = $certFile
    'CERT_DIR'                           = $certDir
    'REQUESTS_CA_BUNDLE'                 = $certFile
    'CURL_CA_BUNDLE'                     = $certFile
    'NODE_EXTRA_CA_CERTS'                = $certFile
    'GRPC_DEFAULT_SSL_ROOTS_FILE_PATH'   = $certFile
    'GIT_SSL_CAINFO'                     = $certFile
    'CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE' = $certFile
    'PIP_CERT'                           = $certFile
    'NPM_CONFIG_CAFILE'                  = $certFile
    'npm_config_cafile'                  = $certFile
    'AWS_CA_BUNDLE'                      = $certFile
  }

  foreach ($kv in $vars.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, 'User')
    # Also set in current process
    [Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, 'Process')
  }
}

function Configure-TlsClients {
  <#
  .SYNOPSIS
      Set CA paths in git, pip, and gcloud configs.
  .DESCRIPTION
      Configures git's global http.sslcainfo and pip's global cert setting
      to point at the golden PEM bundle.
  .NOTES
      Checks: command existence for python and gcloud
      Gates: None
      Side effects: Modifies git global config, pip config, gcloud config
      Idempotency: Overwrites the same settings with the same values.
  #>
  Invoke-OrDry -Label "git config --global http.sslcainfo $GoldenBundlePath" -Command {
    git config --global http.sslcainfo $GoldenBundlePath
  }

  if (Test-CommandExists 'python') {
    Invoke-OrDry -Label "pip config set global.cert $GoldenBundlePath" -Command {
      python -m pip config set global.cert $GoldenBundlePath 2>$null
    }
  }

  if (Test-CommandExists 'gcloud') {
    Invoke-OrDry -Label "gcloud config set core/custom_ca_certs_file $GoldenBundlePath" -Command {
      gcloud config set core/custom_ca_certs_file $GoldenBundlePath 2>$null
    }
  }
}

function Handle-Zscaler {
  <#
  .SYNOPSIS
      Orchestrator for all Zscaler TLS trust configuration on Windows.
  .DESCRIPTION
      Evaluates RESOLVED_ZSCALER to decide whether to configure Zscaler trust.
      When proceeding: searches cert stores, exports Zscaler CA certs, builds
      PEM bundle, merges with certifi, writes env vars to mise .env and user
      scope, and configures git/pip/gcloud.
  .NOTES
      Checks: RESOLVED_ZSCALER value, cert store search for auto mode
      Gates: RESOLVED_ZSCALER (false=skip, auto=detect, true=force)
      Side effects: May create cert files, modify configs, write env vars
      Idempotency: Re-running produces the same state.
  #>

  # Gate: disabled
  if ($global:RESOLVED_ZSCALER -eq 'false') {
    Write-StatusSkip 'Zscaler trust' -Reason 'disabled by flag'
    return
  }

  # Gate: auto-detect
  if ($global:RESOLVED_ZSCALER -eq 'auto') {
    if (Detect-Zscaler) {
      Write-Host '  Zscaler detected in certificate stores. Configuring TLS trust.' -ForegroundColor Cyan
      Set-StateValue -Key 'ENABLE_ZSCALER' -Value 'true'
    } else {
      Write-StatusSkip 'Zscaler trust' -Reason 'not detected in certificate stores'
      Set-StateValue -Key 'ENABLE_ZSCALER' -Value 'false'
      return
    }
  }

  # Check if already fully configured
  if ((Test-Path $GoldenBundlePath) -and (Test-Path $MiseEnvPath) -and
      ((git config --global --get http.sslcainfo 2>$null) -eq $GoldenBundlePath)) {
    Write-StatusPass 'Zscaler trust' -Detail 'already configured'
    return
  }

  # Proceed: build trust chain
  Build-ZscalerBundle
  Build-GoldenBundle
  Write-ZscalerMiseEnv
  Set-ZscalerUserEnvVars
  Configure-TlsClients

  if (Test-DryRun) {
    Write-StatusFix 'Zscaler trust' -Action 'would configure'
  } else {
    Write-StatusFix 'Zscaler trust' -Action 'configured'
  }
}


# =============================================================================
# SECTION 5: SHELL PROFILE
# =============================================================================

function Ensure-Profile {
  <#
  .SYNOPSIS
      Write the managed PowerShell profile block and sign it.
  .DESCRIPTION
      Uses Write-ManagedBlock with markers to idempotently write mise activation,
      zoxide init, and signing helpers dot-source into $PROFILE. Signs the
      profile after writing ONLY when AllSigned execution policy is active.
  .NOTES
      Checks: Existing profile content via Write-ManagedBlock
      Gates: None (always runs)
      Side effects: Creates or modifies $PROFILE, conditionally signs it
      Idempotency: No-op if the managed block is already present and correct.
  #>
  $profileDir = Split-Path -Parent $PROFILE
  if (-not (Test-Path $profileDir)) {
    Invoke-OrDry -Label "mkdir $profileDir" -Command { New-Item -ItemType Directory -Force $profileDir | Out-Null }
  }

  $signHelpersPath = Join-Path $BootstrapRoot 'Other\scripts\windows-signing-helpers.ps1'
  # Use ~ for portability in profile content
  $signHelpersRelative = '~/.dotfiles/Other/scripts/windows-signing-helpers.ps1'

  $blockContent = @(
    $PROFILE_BEGIN
    '$env:MISE_PWSH_CHPWD_WARNING=0'
    '(& mise activate pwsh) | Out-String | Invoke-Expression'
    '(& zoxide init powershell) | Out-String | Invoke-Expression'
    ''
    ". `"$signHelpersRelative`""
    $PROFILE_END
  ) -join "`n"

  # Check if block already matches
  if (Test-Path $PROFILE) {
    $currentContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($currentContent -and $currentContent.Contains($PROFILE_BEGIN)) {
      # Extract current block
      $lines = Get-Content $PROFILE
      $inBlock = $false
      $currentBlock = @()
      foreach ($line in $lines) {
        if ($line -like "*$PROFILE_BEGIN*") { $inBlock = $true }
        if ($inBlock) { $currentBlock += $line }
        if ($line -like "*$PROFILE_END*") { $inBlock = $false }
      }
      if (($currentBlock -join "`n") -eq $blockContent) {
        Write-StatusPass 'PowerShell profile' -Detail 'managed block up to date'
        return
      }
    }
  }

  Write-ManagedBlock -FilePath $PROFILE `
    -BeginMarker $PROFILE_BEGIN `
    -EndMarker $PROFILE_END `
    -BlockContent $blockContent

  # Sign the profile only if AllSigned policy requires it
  if ($RequiresSigning) {
    Invoke-OrDry -Label 'Sign-Profile' -Command { Sign-Profile }
    if (Test-DryRun) {
      Write-StatusFix 'PowerShell profile' -Action 'would write managed block and sign'
    } else {
      Write-StatusFix 'PowerShell profile' -Action 'wrote managed block and signed'
    }
  } else {
    if (Test-DryRun) {
      Write-StatusFix 'PowerShell profile' -Action 'would write managed block'
    } else {
      Write-StatusFix 'PowerShell profile' -Action 'wrote managed block'
    }
  }
}


# =============================================================================
# SECTION 6: MISE CONFIG
# =============================================================================

function Ensure-MiseConfig {
  <#
  .SYNOPSIS
      Create or update the mise seed configuration.
  .DESCRIPTION
      If no mise config exists, creates it with the seed block. If one exists
      with managed markers, updates the managed section. If one exists without
      markers, leaves it alone (user-managed config).
  .NOTES
      Checks: File existence, presence of managed markers
      Gates: None (always runs)
      Side effects: May create or modify ~/.config/mise/config.toml
      Idempotency: No-op if config is already in the desired state.
  #>
  Invoke-OrDry -Label "mkdir $MiseConfigDir" -Command { New-Item -ItemType Directory -Force $MiseConfigDir | Out-Null }

  $seedBlock = @(
    $MISE_BEGIN
    '[settings]'
    'experimental = true'
    ''
    '[env]'
    '_.file = "~/.config/mise/.env"'
    ''
    '[tools]'
    'go = "latest"'
    'node = "latest"'
    'bun = "latest"'
    'python = "latest"'
    'uv = "latest"'
    'terraform = "latest"'
    'gcloud = "latest"'
    'usage = "latest"'
    $MISE_END
  ) -join "`n"

  if (-not (Test-Path $MiseConfigPath)) {
    Invoke-OrDry -Label "create mise seed config at $MiseConfigPath" -Command {
      Set-Content -Path $MiseConfigPath -Value $seedBlock -Encoding Ascii
    }
    if (Test-DryRun) {
      Write-StatusFix 'Mise seed config' -Action "would create $MiseConfigPath"
    } else {
      Write-StatusFix 'Mise seed config' -Action "created $MiseConfigPath"
    }
    return
  }

  $content = Get-Content $MiseConfigPath -Raw
  if ($content -match [regex]::Escape($MISE_BEGIN)) {
    # Check if existing block matches
    $lines = Get-Content $MiseConfigPath
    $inBlock = $false
    $currentBlock = @()
    foreach ($line in $lines) {
      if ($line -like "*$MISE_BEGIN*") { $inBlock = $true }
      if ($inBlock) { $currentBlock += $line }
      if ($line -like "*$MISE_END*") { $inBlock = $false }
    }

    if (($currentBlock -join "`n") -eq $seedBlock) {
      Write-StatusPass 'Mise seed config' -Detail 'already up to date'
    } else {
      Write-ManagedBlock -FilePath $MiseConfigPath `
        -BeginMarker $MISE_BEGIN `
        -EndMarker $MISE_END `
        -BlockContent $seedBlock
      Write-StatusFix 'Mise seed config' -Action 'updated managed block'
    }
    return
  }

  # Config exists but has no managed markers -- user owns it
  Write-StatusSkip 'Mise seed config' -Reason "user config detected at $MiseConfigPath"
}

function Ensure-MiseTools {
  <#
  .SYNOPSIS
      Install all tools defined in mise config.
  .DESCRIPTION
      Runs `mise install` to ensure every tool in config.toml is present at
      the specified version. Signs mise scripts after installation ONLY when
      the execution policy requires AllSigned. New tool installations create
      .ps1 shims that must be signed to be executable under AllSigned.
  .NOTES
      Checks: None (mise install is inherently idempotent)
      Gates: RESOLVED_MISE_TOOLS (skipped if "false")
      Side effects: Downloads and installs language runtimes, conditionally signs scripts
      Idempotency: mise install skips tools already at the correct version.
  #>
  if ($global:RESOLVED_MISE_TOOLS -ne 'true') {
    Write-StatusSkip 'Mise tools install' -Reason 'disabled by flag'
    return
  }

  Invoke-OrDry -Label 'mise install' -Command { mise install 2>$null }

  # Sign mise .ps1 shims only if AllSigned policy requires it
  if ($RequiresSigning) {
    Invoke-OrDry -Label 'Sign-MiseScripts' -Command { Sign-MiseScripts }
  }

  if (Test-DryRun) {
    Write-StatusFix 'Mise tools install' -Action 'would install'
  } else {
    Write-StatusPass 'Mise tools install' -Detail 'complete'
  }
}


# =============================================================================
# SECTION 7: VALIDATION
# =============================================================================

function Invoke-FoundationValidation {
  <#
  .SYNOPSIS
      Run individual checks and emit status per check.
  .DESCRIPTION
      Verifies that every critical tool is installed and functional. Checks
      are conditional on feature flags where appropriate.
  .NOTES
      Checks: command existence and --version for each tool
      Gates: RESOLVED_MISE_TOOLS for runtime checks, Zscaler state for TLS
      Side effects: None (read-only validation)
      Idempotency: Pure validation -- safe to call any number of times.
  #>

  # Core tools (always checked)
  foreach ($tool in @('scoop', 'mise', 'git', 'openssl')) {
    if (Test-CommandExists $tool) {
      Write-StatusPass "Validate: $tool"
    } else {
      Write-StatusFail "Validate: $tool" -Detail 'not found'
    }
  }

  # Runtime checks (conditional on RESOLVED_MISE_TOOLS)
  if ($global:RESOLVED_MISE_TOOLS -eq 'true') {
    if ((Test-CommandExists 'node') -and (node --version 2>$null)) {
      $ver = node --version 2>$null
      Write-StatusPass 'Validate: node' -Detail $ver
    } else {
      Write-StatusSkip 'Validate: node' -Reason 'not yet installed'
    }

    if ((Test-CommandExists 'python') -and (python --version 2>$null)) {
      $ver = python --version 2>$null
      Write-StatusPass 'Validate: python' -Detail $ver
    } else {
      Write-StatusSkip 'Validate: python' -Reason 'not yet installed'
    }
  } else {
    Write-StatusSkip 'Validate: node' -Reason 'mise-tools disabled'
    Write-StatusSkip 'Validate: python' -Reason 'mise-tools disabled'
  }

  # Zscaler / TLS-sensitive checks
  $zscalerState = Get-StateValue -Key 'ENABLE_ZSCALER'
  if ($zscalerState -eq 'true' -or $global:RESOLVED_ZSCALER -eq 'true') {
    if (Test-Path $GoldenBundlePath) {
      Write-StatusPass 'Zscaler: golden bundle exists'
    } else {
      Write-StatusFail 'Zscaler: golden bundle exists' -Detail "file missing at $GoldenBundlePath"
    }

    if (Test-Path $MiseEnvPath) {
      Write-StatusPass 'Zscaler: mise .env exists'
    } else {
      Write-StatusFail 'Zscaler: mise .env exists' -Detail "file missing at $MiseEnvPath"
    }

    $gitCa = git config --global --get http.sslcainfo 2>$null
    if ($gitCa -eq $GoldenBundlePath) {
      Write-StatusPass 'Zscaler: git sslcainfo'
    } else {
      Write-StatusFail 'Zscaler: git sslcainfo' -Detail "expected $GoldenBundlePath, got $gitCa"
    }

    # Cert-sensitive tool validation (Phase 6 from runbook)
    if (Test-CommandExists 'node') {
      $nodeCA = node -p "process.env.NODE_EXTRA_CA_CERTS" 2>$null
      if ($nodeCA -and (Test-Path $nodeCA)) {
        Write-StatusPass 'Zscaler: NODE_EXTRA_CA_CERTS' -Detail $nodeCA
      } else {
        Write-StatusFail 'Zscaler: NODE_EXTRA_CA_CERTS' -Detail "not set or file missing"
      }
    }

    if (Test-CommandExists 'python') {
      $pipCert = python -m pip config get global.cert 2>$null
      if ($pipCert) {
        Write-StatusPass 'Zscaler: pip cert config' -Detail $pipCert
      } else {
        Write-StatusSkip 'Zscaler: pip cert config' -Reason 'not configured'
      }
    }
  }

  # Signing health checks (only under AllSigned)
  if ($RequiresSigning) {
    $unsignedScoop = Get-ChildItem "$env:USERPROFILE\scoop" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
      Get-AuthenticodeSignature -ErrorAction SilentlyContinue |
      Where-Object Status -ne 'Valid'
    if ($unsignedScoop -and $unsignedScoop.Count -gt 0) {
      Write-StatusFail 'Signing: Scoop scripts' -Detail "$($unsignedScoop.Count) unsigned .ps1 files"
    } else {
      Write-StatusPass 'Signing: Scoop scripts' -Detail 'all signed'
    }

    $unsignedMise = Get-ChildItem "$HOME\AppData\Local\mise" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
      Get-AuthenticodeSignature -ErrorAction SilentlyContinue |
      Where-Object Status -ne 'Valid'
    if ($unsignedMise -and $unsignedMise.Count -gt 0) {
      Write-StatusFail 'Signing: mise scripts' -Detail "$($unsignedMise.Count) unsigned .ps1 files"
    } else {
      Write-StatusPass 'Signing: mise scripts' -Detail 'all signed'
    }

    $profileSig = Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
    if ($profileSig -and $profileSig.Status -eq 'Valid') {
      Write-StatusPass 'Signing: PowerShell profile'
    } else {
      Write-StatusFail 'Signing: PowerShell profile' -Detail "status: $($profileSig.Status)"
    }
  }
}


# =============================================================================
# SECTION 8: PERSONAL HANDOFF
# =============================================================================

function Get-PersonalScriptPath {
  <#
  .SYNOPSIS
      Resolve the path to the personal bootstrap script.
  .DESCRIPTION
      Honors the PersonalScript parameter if set (supports both absolute and
      relative paths). Falls back to the default location in the dotfiles repo.
  .NOTES
      Checks: None
      Gates: None
      Side effects: None
      Idempotency: Pure path resolution.
  #>
  if ($PersonalScript) {
    if ([System.IO.Path]::IsPathRooted($PersonalScript)) {
      return $PersonalScript
    }
    return (Join-Path $BootstrapRoot $PersonalScript)
  }
  return (Join-Path $BootstrapRoot 'Other\scripts\personal-bootstrap-windows.ps1')
}

function Invoke-PersonalLayer {
  <#
  .SYNOPSIS
      Execute the personal bootstrap script.
  .DESCRIPTION
      Resolves the personal script path and invokes it, passing mode and
      dotfiles repo. Checks for the Personal switch before running.
  .NOTES
      Checks: Verifies the script file exists
      Gates: -Personal switch (caller is responsible for checking)
      Side effects: Spawns a child PowerShell process running the personal script
      Idempotency: Depends on the personal script's own idempotency.
  #>
  if (-not $Personal) {
    Write-StatusSkip 'Personal layer' -Reason 'not enabled (pass -Personal to enable)'
    return
  }

  $scriptPath = Get-PersonalScriptPath
  if (-not (Test-Path $scriptPath)) {
    Write-StatusFail 'Personal layer' -Detail "script not found at $scriptPath"
  }

  Write-Host "  Handing off to personal bootstrap: $scriptPath" -ForegroundColor Cyan
  $personalArgs = @{ Mode = $Mode; DotfilesRepo = $DotfilesRepo }
  if (Test-DryRun) { $personalArgs['DryRun'] = $true }
  & $scriptPath @personalArgs
  Write-StatusPass 'Personal layer' -Detail 'completed'
}


# =============================================================================
# SECTION 9: MODE ORCHESTRATORS
# =============================================================================

function Invoke-FoundationSetup {
  <#
  .SYNOPSIS
      Run all foundation steps in setup/ensure mode.
  .DESCRIPTION
      Sequential orchestrator for the full foundation provisioning flow:
      Scoop -> packages -> mise -> profile -> mise config -> Zscaler ->
      mise tools -> validate -> personal.
  .NOTES
      Checks: Delegates to individual functions
      Gates: Delegates to individual functions
      Side effects: Installs software, writes configs
      Idempotency: Every step is individually idempotent.
  #>
  Ensure-Scoop
  Ensure-FoundationPackages
  Ensure-Mise
  Ensure-Profile
  Ensure-MiseConfig
  Handle-Zscaler
  Ensure-MiseTools
  Invoke-FoundationValidation
  Invoke-PersonalLayer
}

function Invoke-FoundationUpdate {
  <#
  .SYNOPSIS
      Run all foundation steps in update mode.
  .DESCRIPTION
      Same as ensure but also runs scoop update/upgrade and mise upgrade
      before re-signing and validating.
  .NOTES
      Checks: Delegates to individual functions
      Gates: Delegates to individual functions
      Side effects: Upgrades software, writes configs
      Idempotency: Every step is individually idempotent.
  #>
  # Update Scoop and all packages
  Write-Host '  Updating Scoop packages...' -ForegroundColor Cyan
  Invoke-OrDry -Label 'scoop update *' -Command { scoop update * 2>$null }
  if ($RequiresSigning) { Invoke-OrDry -Label 'Sign-ScoopScripts' -Command { Sign-ScoopScripts } }
  if (Test-DryRun) {
    Write-StatusFix 'Scoop update' -Action 'would update'
  } else {
    Write-StatusPass 'Scoop update' -Detail 'update complete'
  }

  # Update mise
  if ($global:RESOLVED_MISE_TOOLS -eq 'true') {
    Invoke-OrDry -Label 'mise upgrade + mise install' -Command { mise upgrade 2>$null; mise install 2>$null }
    if ($RequiresSigning) { Invoke-OrDry -Label 'Sign-MiseScripts' -Command { Sign-MiseScripts } }
    if (Test-DryRun) {
      Write-StatusFix 'Mise update' -Action 'would upgrade'
    } else {
      Write-StatusPass 'Mise update' -Detail 'binary + tools upgraded'
    }
  } else {
    Write-StatusSkip 'Mise update' -Reason 'disabled by flag'
  }

  # Run remainder of foundation flow
  Ensure-FoundationPackages
  Ensure-Mise
  Ensure-Profile
  Ensure-MiseConfig
  Handle-Zscaler
  Invoke-FoundationValidation
  Invoke-PersonalLayer
}


# =============================================================================
# SECTION 10: MODE SELECTION
# =============================================================================

function Select-Mode {
  <#
  .SYNOPSIS
      Prompt the user to choose a mode if Mode is not set.
  .DESCRIPTION
      If Mode is empty and gum is available, presents an interactive chooser.
      If Mode is empty and non-interactive, fails with an error.
  .NOTES
      Checks: Mode emptiness, gum availability
      Gates: NonInteractive switch
      Side effects: Sets script-level Mode variable
      Idempotency: No-op if Mode is already set.
  #>
  if ($Mode) { return }

  if (-not $NonInteractive -and (Test-CommandExists 'gum')) {
    $script:Mode = gum choose --header 'Choose a Windows foundation mode' setup ensure update personal
    return
  }

  if (-not $NonInteractive) {
    Write-Host 'Select mode:' -ForegroundColor Cyan
    Write-Host '  1. setup   - Full first-time install'
    Write-Host '  2. ensure  - Idempotent re-run'
    Write-Host '  3. update  - Update all packages'
    Write-Host '  4. personal - Personal layer only'
    $choice = Read-Host 'Enter choice (1-4)'
    switch ($choice) {
      '1' { $script:Mode = 'setup' }
      '2' { $script:Mode = 'ensure' }
      '3' { $script:Mode = 'update' }
      '4' { $script:Mode = 'personal' }
      default { Write-Fatal 'Invalid choice' }
    }
    return
  }

  Write-Fatal 'MODE is not set and running non-interactively. Pass a mode: setup, ensure, update, or personal.'
}


# =============================================================================
# SECTION 11: MAIN
# =============================================================================

function Main {
  <#
  .SYNOPSIS
      Main entry point for the Windows foundation bootstrap.
  .DESCRIPTION
      Implements the 6-phase flow: bootstrap deps -> parse args -> resolve
      flags -> display panel -> dispatch -> summary. Parallel structure to
      the macOS foundation-macos.zsh main function.
  .NOTES
      Checks: Delegates to individual functions
      Gates: Mode parameter controls dispatch
      Side effects: Full system provisioning
      Idempotency: All phases are individually idempotent.
  #>

  # Phase 1: Bootstrap minimum deps
  # Scoop must be available before we can install gum or other tools.
  # On first run, Ensure-Scoop handles the full bootstrap.

  # Phase 2: Select mode
  Select-Mode

  # Phase 3: Resolve all flags
  Resolve-AllFlags `
    -CliShell $Shell `
    -CliProfile $Profile_ `
    -EnableFlags $EnableFlags `
    -DisableFlags $DisableFlags

  # Phase 4: Display config panel
  Write-Host ''
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host "  Windows foundation bootstrap" -ForegroundColor White
  Write-Host "  Mode:    $Mode" -ForegroundColor DarkGray
  Write-Host "  Shell:   $global:RESOLVED_SHELL" -ForegroundColor DarkGray
  Write-Host "  Profile: $global:RESOLVED_PROFILE" -ForegroundColor DarkGray
  Write-Host "  Zscaler: $global:RESOLVED_ZSCALER" -ForegroundColor DarkGray
  if (Test-DryRun) {
    Write-Host '  ** DRY RUN — no changes will be made **' -ForegroundColor Magenta
  }
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host ''

  # Phase 5: Dispatch
  switch ($Mode) {
    { $_ -in @('setup', 'ensure') } {
      Invoke-FoundationSetup
    }
    'update' {
      Invoke-FoundationUpdate
    }
    'personal' {
      Invoke-FoundationValidation
      Invoke-PersonalLayer
    }
    default {
      Write-Fatal "Unsupported mode: $Mode"
    }
  }

  # Phase 6: Summary
  Write-StatusSummary -Label 'Foundation'
  Write-Host 'Done.' -ForegroundColor Green
}

Main
