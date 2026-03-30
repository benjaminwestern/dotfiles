# =============================================================================
# foundation-windows.ps1 -- Windows foundation bootstrap
# =============================================================================

param(
  [ValidateSet('setup', 'ensure', 'update', 'personal')]
  [string]$Mode,
  [string]$Shell,
  [string]$Profile_,   # "Profile" conflicts with PS auto-var
  [switch]$NonInteractive,
  [switch]$Personal,
  [switch]$TakeoverMiseConfig,
  [switch]$DryRun,
  [string]$DotfilesRepo,
  [string]$PersonalScript,
  [hashtable]$EnableFlags = @{},
  [hashtable]$DisableFlags = @{}
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $ScriptDir 'lib\windows-precursor.ps1')

$PrecursorArgs = @()
if ($PSBoundParameters.ContainsKey('Mode')) { $PrecursorArgs += @('-Mode', $Mode) }
if ($PSBoundParameters.ContainsKey('Shell')) { $PrecursorArgs += @('-Shell', $Shell) }
if ($PSBoundParameters.ContainsKey('Profile_')) { $PrecursorArgs += @('-Profile_', $Profile_) }
if ($NonInteractive) { $PrecursorArgs += '-NonInteractive' }
if ($Personal) { $PrecursorArgs += '-Personal' }
if ($TakeoverMiseConfig) { $PrecursorArgs += '-TakeoverMiseConfig' }
if ($DryRun) { $PrecursorArgs += '-DryRun' }
if ($PSBoundParameters.ContainsKey('DotfilesRepo')) { $PrecursorArgs += @('-DotfilesRepo', $DotfilesRepo) }
if ($PSBoundParameters.ContainsKey('PersonalScript')) { $PrecursorArgs += @('-PersonalScript', $PersonalScript) }
Invoke-PwshPrecursor -ScriptPath $MyInvocation.MyCommand.Path -ArgumentList $PrecursorArgs

. (Join-Path $ScriptDir 'lib\common.ps1')
. (Join-Path $ScriptDir 'windows-signing-helpers.ps1')

if ($DryRun -or $env:DRY_RUN -eq '1') { $global:DRY_RUN = $true }

$FoundationPackages = @(
  'git', 'gh', 'jq', 'jid', 'yq', 'fzf', 'fd', 'ripgrep', 'zoxide',
  'lazygit', 'charm-gum', 'vscode', 'openssl', 'pwsh'
)

$EffectiveExecutionPolicy = Get-ExecutionPolicy
$RequiresSigning = @(
  (Get-ExecutionPolicy -Scope CurrentUser),
  (Get-ExecutionPolicy -Scope Process),
  $EffectiveExecutionPolicy
) -contains 'AllSigned'

$MiseConfigDir  = Join-Path $HOME '.config\mise'
$MiseConfigPath = Join-Path $MiseConfigDir 'config.toml'
$MiseEnvPath    = Join-Path $MiseConfigDir '.env'

$CertsDir          = Join-Path $HOME 'certs'
$ZscalerCaDir      = Join-Path $CertsDir 'zscaler-ca'
$ZscalerBundlePath = Join-Path $CertsDir 'zscaler_ca_bundle.pem'
$GoldenBundlePath  = Join-Path $CertsDir 'golden_pem.pem'

$BootstrapRoot = if ($env:BOOTSTRAP_ROOT) {
  $env:BOOTSTRAP_ROOT
} else {
  Split-Path -Parent (Split-Path -Parent $ScriptDir)
}

if (-not $DotfilesRepo) {
  $DotfilesRepo = if ($env:DOTFILES_REPO) {
    $env:DOTFILES_REPO
  } else {
    'https://github.com/benjaminwestern/dotfiles.git'
  }
}

$script:ZscalerDetection = $null


function Test-ScoopBucketInstalled {
  param([Parameter(Mandatory)][string]$Name)
  Test-Path (Join-Path $HOME "scoop\buckets\$Name")
}

function Ensure-ScoopBucket {
  param([Parameter(Mandatory)][string]$Name)

  if (Test-ScoopBucketInstalled -Name $Name) {
    return
  }

  Invoke-OrDry -Label "scoop bucket add $Name" -Command {
    scoop bucket add $Name 2>$null
  }
}

function Get-MiseInstallMethod {
  if (Test-CommandExists 'scoop') {
    $scoopMise = scoop list mise 2>$null
    if ($scoopMise -match '(^|\s)mise(\s|$)') {
      return 'scoop'
    }
  }

  foreach ($candidate in @(
    (Join-Path $HOME '.local\bin\mise.exe'),
    (Join-Path $HOME 'AppData\Local\mise\bin\mise.exe')
  )) {
    if (Test-Path $candidate) {
      return 'shell installer'
    }
  }

  return 'unknown'
}

function Get-SignableScriptStatus {
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

function Convert-CertificateToPemText {
  param([Parameter(Mandatory)]$Certificate)

  $base64 = [System.Convert]::ToBase64String($Certificate.RawData, 'InsertLineBreaks')
  return "-----BEGIN CERTIFICATE-----`n$base64`n-----END CERTIFICATE-----`n"
}

function Ensure-Scoop {
  if (Test-CommandExists 'scoop') {
    Update-PrecursorPath
    Ensure-ScoopBucket -Name 'extras'
    Write-StatusPass 'Scoop' -Detail 'already installed'
    return
  }

  if (Test-DryRun) {
    if ($RequiresSigning) {
      Write-DryRunLog 'download Scoop installer, patch allowlist, sign installer, install Scoop, sign Scoop scripts'
    } else {
      Write-DryRunLog 'download and run Scoop installer'
    }
    Write-DryRunLog 'scoop bucket add extras'
    Write-StatusFix 'Scoop' -Action 'would install'
    return
  }

  if ($RequiresSigning) {
    Ensure-LocalCodeSigningCert | Out-Null
  }

  $installerPath = Join-Path $env:TEMP 'install-scoop.ps1'
  Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1' `
    -OutFile $installerPath

  if ($RequiresSigning) {
    $content = Get-Content $installerPath -Raw
    $content = $content -replace `
      "@\('Unrestricted', 'RemoteSigned', 'ByPass'\)", `
      "@('Unrestricted', 'RemoteSigned', 'ByPass', 'AllSigned')"
    Set-Content -Path $installerPath -Value $content -Encoding Ascii

    $cert = Ensure-LocalCodeSigningCert
    Set-AuthenticodeSignature -FilePath $installerPath -Certificate $cert | Out-Null
  } else {
    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($currentUserPolicy -eq 'Restricted') {
      Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    }
  }

  & $installerPath -RunAsAdmin:$false
  Update-PrecursorPath

  if ($RequiresSigning) {
    Sign-ScoopScripts
  }

  Ensure-ScoopBucket -Name 'extras'
  Write-StatusFix 'Scoop' -Action 'installed'
}

function Ensure-FoundationPackages {
  if ($RequiresSigning) {
    Ensure-LocalCodeSigningCert | Out-Null
  }

  Ensure-ScoopBucket -Name 'extras'

  $present = 0
  $missing = 0
  $total = $FoundationPackages.Count

  foreach ($package in $FoundationPackages) {
    $installed = scoop list $package 2>$null
    if ($installed -match ("(^|\s)" + [regex]::Escape($package) + "(\s|$)")) {
      $present++
      continue
    }

    Invoke-OrDry -Label "scoop install $package" -Command {
      scoop install $package 2>$null
    }
    $missing++
  }

  Update-PrecursorPath

  if ($RequiresSigning) {
    Invoke-OrDry -Label 'Sign-ScoopScripts' -Command { Sign-ScoopScripts }
  }

  if ($missing -eq 0) {
    Write-StatusPass 'Foundation packages' -Detail "${present}/${total} present"
  } else {
    $action = if (Test-DryRun) { "would install ${missing} missing" } else { "installed ${missing} missing" }
    Write-StatusFix 'Foundation packages' -Action $action
  }
}

function Ensure-Mise {
  if (Test-CommandExists 'mise') {
    $version = mise --version 2>$null
    Write-StatusPass 'Mise' -Detail "$version ($(Get-MiseInstallMethod))"
    return
  }

  if ($RequiresSigning) {
    Ensure-LocalCodeSigningCert | Out-Null
  }

  if (Test-DryRun) {
    if ($RequiresSigning) {
      Write-DryRunLog 'scoop install mise, sign Scoop scripts, sign mise scripts'
    } else {
      Write-DryRunLog 'prefer scoop install mise, fall back to shell installer'
    }
    Write-StatusFix 'Mise' -Action 'would install'
    return
  }

  if ($RequiresSigning) {
    if (-not (Test-CommandExists 'scoop')) {
      Ensure-Scoop
    }

    scoop install mise 2>$null
    Update-PrecursorPath
    Sign-ScoopScripts
    Sign-MiseScripts

    if (-not (Test-CommandExists 'mise')) {
      Write-StatusFail 'Mise' -Detail 'install via Scoop failed under AllSigned'
    }

    Write-StatusFix 'Mise' -Action 'installed via Scoop (signed for AllSigned)'
    return
  }

  if (Test-CommandExists 'scoop') {
    scoop install mise 2>$null
    Update-PrecursorPath
    if (Test-CommandExists 'mise') {
      Write-StatusFix 'Mise' -Action 'installed via Scoop'
      return
    }
  }

  irm https://mise.run | iex
  $env:PATH = "$(Join-Path $HOME '.local\bin');$(Join-Path $HOME 'AppData\Local\mise\bin');$env:PATH"

  if (Test-CommandExists 'mise') {
    Write-StatusFix 'Mise' -Action 'installed via shell installer'
  } else {
    Write-StatusFail 'Mise' -Detail 'installation failed'
  }
}

function Get-BaseCaBundlePath {
  $candidates = @()

  if ($env:SSL_CERT_FILE) {
    $candidates += $env:SSL_CERT_FILE
  }

  $opensslCommand = Get-Command openssl -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($opensslCommand) {
    $opensslBinDir = Split-Path -Parent $opensslCommand.Source
    $opensslRoot = Split-Path -Parent $opensslBinDir
    $candidates += @(
      (Join-Path $opensslRoot 'cert.pem'),
      (Join-Path $opensslRoot 'cacert.pem'),
      (Join-Path $opensslRoot 'ssl\cert.pem'),
      (Join-Path $opensslRoot 'certs\ca-bundle.crt'),
      (Join-Path $opensslRoot 'certs\ca-certificates.crt'),
      (Join-Path $opensslBinDir 'curl-ca-bundle.crt'),
      (Join-Path $opensslBinDir 'cacert.pem'),
      (Join-Path $opensslBinDir 'cert.pem'),
      (Join-Path $HOME 'scoop\apps\openssl\current\cert.pem'),
      (Join-Path $HOME 'scoop\apps\openssl\current\bin\curl-ca-bundle.crt'),
      (Join-Path $HOME 'scoop\apps\openssl\current\bin\cacert.pem')
    )

    $opensslDirOutput = openssl version -d 2>$null
    if ($opensslDirOutput -match '"([^"]+)"') {
      $opensslDir = $matches[1]
      $candidates += @(
        (Join-Path $opensslDir 'cert.pem'),
        (Join-Path $opensslDir 'certs\ca-certificates.crt'),
        (Join-Path $opensslDir 'certs\ca-bundle.crt')
      )
    }
  }

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path $candidate)) {
      return $candidate
    }
  }

  return $null
}

function Get-PythonCertifiBundlePath {
  if (-not (Test-CommandExists 'python')) {
    return $null
  }

  foreach ($command in @(
    'import certifi; print(certifi.where())',
    'import pip._vendor.certifi as c; print(c.where())'
  )) {
    try {
      $result = python -c $command 2>$null
      if ($result -and (Test-Path $result.Trim())) {
        return $result.Trim()
      }
    } catch {
      continue
    }
  }

  return $null
}

function Build-ZscalerBundle {
  if (Test-DryRun) {
    Write-DryRunLog "build Zscaler CA bundle at $ZscalerBundlePath"
    return
  }

  New-Item -ItemType Directory -Force $CertsDir | Out-Null
  New-Item -ItemType Directory -Force $ZscalerCaDir | Out-Null

  $zscalerCerts = @(Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root,
    Cert:\CurrentUser\CA, Cert:\LocalMachine\CA -ErrorAction SilentlyContinue |
    Where-Object { ($_.Subject -match 'Zscaler') -or ($_.Issuer -match 'Zscaler') } |
    Sort-Object Thumbprint -Unique)

  if ($zscalerCerts.Count -eq 0) {
    Write-StatusFail 'Zscaler trust' -Detail 'no Zscaler certificates found in Windows stores'
  }

  $pemBlocks = @()
  foreach ($certificate in $zscalerCerts) {
    $pemBlocks += Convert-CertificateToPemText -Certificate $certificate
  }

  Set-Content -Path $ZscalerBundlePath -Value (($pemBlocks -join '').Trim() + "`n") -Encoding Ascii
}

function Build-GoldenBundle {
  $baseBundlePath = Get-BaseCaBundlePath
  if (-not $baseBundlePath) {
    Write-StatusFail 'Zscaler trust' -Detail 'OpenSSL CA bundle not found'
  }

  if (Test-DryRun) {
    Write-DryRunLog "build golden CA bundle from $baseBundlePath and $ZscalerBundlePath"
    return
  }

  $baseContent = Get-Content $baseBundlePath -Raw
  $zscalerContent = Get-Content $ZscalerBundlePath -Raw
  $merged = $baseContent.TrimEnd() + "`n" + $zscalerContent.Trim() + "`n"
  Set-Content -Path $GoldenBundlePath -Value $merged -Encoding Ascii
}

function Refresh-GoldenBundleWithPythonCertifi {
  $pythonBundlePath = Get-PythonCertifiBundlePath
  if (-not $pythonBundlePath) {
    return $false
  }

  if (Test-DryRun) {
    Write-DryRunLog "refresh golden CA bundle from Python certifi bundle at $pythonBundlePath"
    return $true
  }

  $pythonContent = Get-Content $pythonBundlePath -Raw
  $zscalerContent = Get-Content $ZscalerBundlePath -Raw
  $merged = $pythonContent.TrimEnd() + "`n" + $zscalerContent.Trim() + "`n"
  Set-Content -Path $GoldenBundlePath -Value $merged -Encoding Ascii
  return $true
}

function Write-ZscalerMiseEnv {
  Invoke-OrDry -Label "mkdir $MiseConfigDir" -Command {
    New-Item -ItemType Directory -Force $MiseConfigDir | Out-Null
  }

  $certFile = $GoldenBundlePath -replace '\\', '/'
  $certDir = $CertsDir -replace '\\', '/'

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
  if (Test-DryRun) {
    Write-DryRunLog 'set Zscaler TLS environment variables at user and process scope'
    return
  }

  $certFile = $GoldenBundlePath -replace '\\', '/'
  $certDir = $CertsDir -replace '\\', '/'

  $pairs = @(
    [pscustomobject]@{ Name = 'SSL_CERT_FILE'; Value = $certFile },
    [pscustomobject]@{ Name = 'SSL_CERT_DIR'; Value = $certDir },
    [pscustomobject]@{ Name = 'CERT_PATH'; Value = $certFile },
    [pscustomobject]@{ Name = 'CERT_DIR'; Value = $certDir },
    [pscustomobject]@{ Name = 'REQUESTS_CA_BUNDLE'; Value = $certFile },
    [pscustomobject]@{ Name = 'CURL_CA_BUNDLE'; Value = $certFile },
    [pscustomobject]@{ Name = 'NODE_EXTRA_CA_CERTS'; Value = $certFile },
    [pscustomobject]@{ Name = 'GRPC_DEFAULT_SSL_ROOTS_FILE_PATH'; Value = $certFile },
    [pscustomobject]@{ Name = 'GIT_SSL_CAINFO'; Value = $certFile },
    [pscustomobject]@{ Name = 'CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE'; Value = $certFile },
    [pscustomobject]@{ Name = 'PIP_CERT'; Value = $certFile },
    [pscustomobject]@{ Name = 'NPM_CONFIG_CAFILE'; Value = $certFile },
    [pscustomobject]@{ Name = 'npm_config_cafile'; Value = $certFile },
    [pscustomobject]@{ Name = 'AWS_CA_BUNDLE'; Value = $certFile }
  )

  foreach ($pair in $pairs) {
    [Environment]::SetEnvironmentVariable($pair.Name, $pair.Value, 'User')
    [Environment]::SetEnvironmentVariable($pair.Name, $pair.Value, 'Process')
  }
}

function Configure-TlsClients {
  Invoke-OrDry -Label "git config --global http.sslcainfo $GoldenBundlePath" -Command {
    git config --global http.sslcainfo $GoldenBundlePath
  }

  if (Test-CommandExists 'python') {
    Invoke-OrDry -Label "python -m pip config set global.cert $GoldenBundlePath" -Command {
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
  $script:ZscalerDetection = Get-ZscalerDetection

  if ($global:RESOLVED_ZSCALER -ne 'true') {
    Write-StatusSkip 'Zscaler trust' -Reason 'disabled or not detected'
    return
  }

  if ($script:ZscalerDetection.detected -and (Get-StateValue -Key 'ENABLE_ZSCALER') -ne 'true') {
    Set-StateValue -Key 'ENABLE_ZSCALER' -Value 'true'
  }

  $alreadyConfigured = (Test-Path $ZscalerBundlePath) -and
    (Test-Path $GoldenBundlePath) -and
    (Test-Path $MiseEnvPath) -and
    ((git config --global --get http.sslcainfo 2>$null) -eq $GoldenBundlePath)

  if ($alreadyConfigured) {
    Write-StatusPass 'Zscaler trust' -Detail 'stage 1 already configured'
    return
  }

  Build-ZscalerBundle
  Build-GoldenBundle
  Write-ZscalerMiseEnv
  Set-ZscalerUserEnvVars
  Configure-TlsClients

  $action = if (Test-DryRun) { 'would configure stage 1 trust' } else { 'configured stage 1 trust' }
  Write-StatusFix 'Zscaler trust' -Action $action
}

function Refresh-ZscalerTlsClientsAfterMiseTools {
  if ($global:RESOLVED_ZSCALER -ne 'true') {
    Write-StatusSkip 'Zscaler trust refresh' -Reason 'disabled or not detected'
    return
  }

  if (-not (Test-Path $ZscalerBundlePath)) {
    Write-StatusSkip 'Zscaler trust refresh' -Reason 'Zscaler bundle not present yet'
    return
  }

  if (-not (Test-CommandExists 'python')) {
    Write-StatusSkip 'Zscaler trust refresh' -Reason 'python not installed yet'
    return
  }

  $refreshed = Refresh-GoldenBundleWithPythonCertifi
  if (-not $refreshed) {
    Write-StatusSkip 'Zscaler trust refresh' -Reason 'python certifi bundle not available'
    return
  }

  Configure-TlsClients
  $action = if (Test-DryRun) { 'would refresh stage 2 trust' } else { 'refreshed stage 2 trust' }
  Write-StatusFix 'Zscaler trust refresh' -Action $action
}

function Ensure-Profile {
  $profileDir = Split-Path -Parent $PROFILE
  if (-not (Test-Path $profileDir)) {
    Invoke-OrDry -Label "mkdir $profileDir" -Command {
      New-Item -ItemType Directory -Force $profileDir | Out-Null
    }
  }

  $blockContent = @(
    $PROFILE_BEGIN
    '$env:MISE_PWSH_CHPWD_WARNING=0'
    '. "~/.dotfiles/Other/scripts/lib/common.ps1"'
    'Remove-MiseInstallPathsFromSessionPath'
    '(& mise activate pwsh --shims) | Out-String | Invoke-Expression'
    '(& zoxide init powershell) | Out-String | Invoke-Expression'
    ''
    '. "~/.dotfiles/Other/scripts/windows-signing-helpers.ps1"'
    $PROFILE_END
  ) -join "`n"

  $changed = $true
  if (Test-Path $PROFILE) {
    $currentContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($currentContent -and $currentContent.Contains($PROFILE_BEGIN) -and $currentContent.Contains($PROFILE_END)) {
      $currentBlock = ($currentContent.Substring(
        $currentContent.IndexOf($PROFILE_BEGIN),
        ($currentContent.IndexOf($PROFILE_END) + $PROFILE_END.Length) - $currentContent.IndexOf($PROFILE_BEGIN)
      ))
      $changed = $currentBlock -ne $blockContent
    }
  }

  Write-ManagedBlock -FilePath $PROFILE `
    -BeginMarker $PROFILE_BEGIN `
    -EndMarker $PROFILE_END `
    -BlockContent $blockContent

  if ($RequiresSigning) {
    Invoke-OrDry -Label 'Sign-DotfilesWindowsScripts' -Command { Sign-DotfilesWindowsScripts }
    Invoke-OrDry -Label 'Sign-Profile' -Command { Sign-Profile }
  }

  if ($changed) {
    $action = if ($RequiresSigning) {
      if (Test-DryRun) { 'would write managed block and sign' } else { 'wrote managed block and signed' }
    } else {
      if (Test-DryRun) { 'would write managed block' } else { 'wrote managed block' }
    }
    Write-StatusFix 'PowerShell profile' -Action $action
  } else {
    $detail = if ($RequiresSigning) { 'managed block up to date and signed' } else { 'managed block up to date' }
    Write-StatusPass 'PowerShell profile' -Detail $detail
  }
}

function Ensure-CurrentPwshActivation {
  if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-StatusSkip 'Current pwsh activation' -Reason 'not running in pwsh'
    return
  }

  Remove-MiseInstallPathsFromSessionPath
  (& mise activate pwsh --shims) | Out-String | Invoke-Expression
  $zoxideActivated = $false
  if (Test-CommandExists 'zoxide') {
    (& zoxide init powershell) | Out-String | Invoke-Expression
    $zoxideActivated = $true
  }

  $doctor = Get-MiseDoctorJson
  if (-not $doctor) {
    Write-StatusFail 'Current pwsh activation' -Detail 'mise doctor --json failed after activation'
  }

  if ($env:MISE_SHELL -and $env:MISE_SHELL -ne 'pwsh') {
    Write-StatusFail 'Current pwsh activation' -Detail "MISE_SHELL was '$($env:MISE_SHELL)'"
  }

  $detail = if ($zoxideActivated) {
    'mise doctor returned JSON; MISE_SHELL resolved; zoxide activated'
  } else {
    'mise doctor returned JSON; MISE_SHELL resolved'
  }
  Write-StatusPass 'Current pwsh activation' -Detail $detail
}

function Ensure-WindowsTerminalPwshDefault {
  $deterministicPwshGuid = '{e267f5ba-0552-4202-9426-d4f81d00e17f}'
  $settingsPath = Get-WindowsTerminalSettingsPath
  if (-not $settingsPath) {
    Write-StatusSkip 'Windows Terminal default profile' -Reason 'settings.json not found'
    return
  }

  $settings = Get-WindowsTerminalSettingsObject
  if (-not $settings) {
    Write-StatusSkip 'Windows Terminal default profile' -Reason 'unable to parse settings.json'
    return
  }

  if (-not $settings.profiles) {
    $settings | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{ list = @() })
  }
  if (-not $settings.profiles.list) {
    $settings.profiles.list = @()
  }

  $pwshCommand = (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not $pwshCommand) {
    $pwshCommand = 'pwsh.exe'
  }

  $pwshProfile = Get-WindowsTerminalPwshProfile -SettingsObject $settings
  if (-not $pwshProfile) {
    $pwshProfile = Get-WindowsTerminalProfileByGuid -SettingsObject $settings -Guid $deterministicPwshGuid
  }
  $createdProfile = $false
  if (-not $pwshProfile) {
    $pwshProfile = [pscustomobject]@{
      guid        = $deterministicPwshGuid
      name        = 'PowerShell 7'
      commandLine = "`"$pwshCommand`""
      hidden      = $false
    }
    $settings.profiles.list = @($settings.profiles.list) + $pwshProfile
    $createdProfile = $true
  } else {
    if ($pwshProfile.PSObject.Properties.Name -contains 'commandLine') {
      $pwshProfile.commandLine = "`"$pwshCommand`""
    } elseif ($pwshProfile.PSObject.Properties.Name -contains 'commandline') {
      $pwshProfile.commandline = "`"$pwshCommand`""
    } else {
      $pwshProfile | Add-Member -NotePropertyName commandLine -NotePropertyValue "`"$pwshCommand`""
    }
  }

  $alreadyDefault = $settings.defaultProfile -and
    [string]::Equals($settings.defaultProfile, $pwshProfile.guid, [System.StringComparison]::OrdinalIgnoreCase)

  if ($alreadyDefault -and -not $createdProfile) {
    Write-StatusPass 'Windows Terminal default profile' -Detail 'already set to pwsh'
    return
  }

  if ($settings.PSObject.Properties.Name -contains 'defaultProfile') {
    $settings.defaultProfile = $pwshProfile.guid
  } else {
    $settings | Add-Member -NotePropertyName defaultProfile -NotePropertyValue $pwshProfile.guid
  }

  if (Test-DryRun) {
    Write-DryRunLog "set Windows Terminal defaultProfile to $($pwshProfile.guid)"
    Write-StatusFix 'Windows Terminal default profile' -Action 'would set to pwsh'
    return
  }

  $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $settingsPath -Encoding utf8
  Write-StatusFix 'Windows Terminal default profile' -Action 'set to pwsh'
}

function Get-MiseSeedBlock {
  return (@(
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
    'zig = "latest"'
    'terraform = "latest"'
    'gcloud = "latest"'
    'usage = "latest"'
    'pkl = "latest"'
    'hk = "latest"'
    'fnox = "latest"'
    '"go:oss.terrastruct.com/d2" = { version = "latest" }'
    '"go:github.com/charmbracelet/glow" = { version = "latest" }'
    '"go:github.com/charmbracelet/freeze" = { version = "latest" }'
    '"go:github.com/charmbracelet/vhs" = { version = "latest" }'
    '"npm:opencode-ai" = "latest"'
    '"npm:@playwright/cli" = "latest"'
    $MISE_END
  ) -join "`n")
}

function Ensure-MiseConfig {
  Invoke-OrDry -Label "mkdir $MiseConfigDir" -Command {
    New-Item -ItemType Directory -Force $MiseConfigDir | Out-Null
  }

  $seedBlock = Get-MiseSeedBlock

  if (-not (Test-Path $MiseConfigPath)) {
    Invoke-OrDry -Label "create $MiseConfigPath" -Command {
      Set-Content -Path $MiseConfigPath -Value $seedBlock -Encoding Ascii
    }
    $action = if (Test-DryRun) { "would create $MiseConfigPath" } else { "created $MiseConfigPath" }
    Write-StatusFix 'Mise seed config' -Action $action
    return
  }

  $content = Get-Content $MiseConfigPath -Raw -ErrorAction SilentlyContinue
  if ($content -and $content.Contains($MISE_BEGIN) -and $content.Contains($MISE_END)) {
    $currentBlock = $content.Substring(
      $content.IndexOf($MISE_BEGIN),
      ($content.IndexOf($MISE_END) + $MISE_END.Length) - $content.IndexOf($MISE_BEGIN)
    )

    if ($currentBlock -eq $seedBlock) {
      Write-StatusPass 'Mise seed config' -Detail 'managed block up to date'
    } else {
      Write-ManagedBlock -FilePath $MiseConfigPath `
        -BeginMarker $MISE_BEGIN `
        -EndMarker $MISE_END `
        -BlockContent $seedBlock
      Write-StatusFix 'Mise seed config' -Action 'updated managed block'
    }
    return
  }

  if (-not $TakeoverMiseConfig) {
    Write-StatusSkip 'Mise seed config' -Reason "user config detected at $MiseConfigPath"
    return
  }

  $backupPath = Join-Path $MiseConfigDir 'config.toml.pre-foundation.bak'
  Invoke-OrDry -Label "backup $MiseConfigPath to $backupPath" -Command {
    Copy-Item -Path $MiseConfigPath -Destination $backupPath -Force
  }
  Invoke-OrDry -Label "replace $MiseConfigPath with managed seed" -Command {
    Set-Content -Path $MiseConfigPath -Value $seedBlock -Encoding Ascii
  }

  $action = if (Test-DryRun) {
    "would back up existing config and replace with managed seed"
  } else {
    "backed up existing config and replaced with managed seed"
  }
  Write-StatusFix 'Mise seed config' -Action $action
}

function Ensure-MiseTools {
  if ($global:RESOLVED_MISE_TOOLS -ne 'true') {
    Write-StatusSkip 'Mise tools install' -Reason 'disabled by flag'
    return
  }

  Write-Host '  Running mise install...' -ForegroundColor Cyan
  Invoke-OrDry -Label 'mise install' -Command {
    mise install 2>$null
  }

  if ($RequiresSigning) {
    Invoke-OrDry -Label 'Sign-MiseScripts' -Command { Sign-MiseScripts }
  }

  if (Test-DryRun) {
    Write-StatusFix 'Mise tools install' -Action 'would install'
  } else {
    Write-StatusPass 'Mise tools install' -Detail 'complete'
  }
}

function Invoke-FoundationValidation {
  foreach ($tool in @('scoop', 'mise', 'git', 'openssl')) {
    if (Test-CommandExists $tool) {
      Write-StatusPass "Validate: $tool"
    } else {
      Write-StatusFail "Validate: $tool" -Detail 'not found'
    }
  }

  if ($global:RESOLVED_MISE_TOOLS -eq 'true') {
    foreach ($runtime in @('node', 'python')) {
      if (Test-CommandExists $runtime) {
        $version = & $runtime --version 2>$null | Select-Object -First 1
        Write-StatusPass "Validate: $runtime" -Detail $version
      } else {
        Write-StatusFail "Validate: $runtime" -Detail 'not found'
      }
    }
  } else {
    Write-StatusSkip 'Validate: node' -Reason 'mise-tools disabled'
    Write-StatusSkip 'Validate: python' -Reason 'mise-tools disabled'
  }

  if ($global:RESOLVED_ZSCALER -eq 'true') {
    if (Test-Path $GoldenBundlePath) {
      Write-StatusPass 'Zscaler: golden bundle exists'
    } else {
      Write-StatusFail 'Zscaler: golden bundle exists' -Detail $GoldenBundlePath
    }

    if (Test-Path $MiseEnvPath) {
      Write-StatusPass 'Zscaler: mise .env exists'
    } else {
      Write-StatusFail 'Zscaler: mise .env exists' -Detail $MiseEnvPath
    }

    $gitCa = git config --global --get http.sslcainfo 2>$null
    if ($gitCa -eq $GoldenBundlePath) {
      Write-StatusPass 'Zscaler: git sslcainfo'
    } else {
      Write-StatusFail 'Zscaler: git sslcainfo' -Detail "expected $GoldenBundlePath"
    }

    $nodeCa = [Environment]::GetEnvironmentVariable('NODE_EXTRA_CA_CERTS', 'User')
    if ($nodeCa -eq ($GoldenBundlePath -replace '\\', '/')) {
      Write-StatusPass 'Zscaler: NODE_EXTRA_CA_CERTS'
    } else {
      Write-StatusFail 'Zscaler: NODE_EXTRA_CA_CERTS' -Detail 'user env var not set to golden bundle'
    }

    if (Test-CommandExists 'python') {
      $pipCert = python -m pip config get global.cert 2>$null
      if ($pipCert) {
        Write-StatusPass 'Zscaler: pip cert config' -Detail $pipCert
      } else {
        Write-StatusFail 'Zscaler: pip cert config' -Detail 'not configured'
      }
    }
  }

  $scoopSigning = Get-SignableScriptStatus -RootPath (Join-Path $env:USERPROFILE 'scoop')
  $miseSigning = Get-SignableScriptStatus -RootPath (Join-Path $HOME 'AppData\Local\mise')
  $dotfilesSigning = Get-SignableScriptStatus -RootPath (Join-Path $HOME '.dotfiles\Other\scripts')
  $profileSignature = if (Test-Path $PROFILE) {
    Get-AuthenticodeSignature $PROFILE -ErrorAction SilentlyContinue
  } else {
    $null
  }

  if ($RequiresSigning) {
    if ($scoopSigning.unsigned_count -eq 0) {
      Write-StatusPass 'Signing: Scoop scripts' -Detail 'all signed'
    } else {
      Write-StatusFail 'Signing: Scoop scripts' -Detail "$($scoopSigning.unsigned_count) unsigned"
    }

    if ($miseSigning.unsigned_count -eq 0) {
      Write-StatusPass 'Signing: mise scripts' -Detail 'all signed'
    } else {
      Write-StatusFail 'Signing: mise scripts' -Detail "$($miseSigning.unsigned_count) unsigned"
    }

    if ($dotfilesSigning.unsigned_count -eq 0) {
      Write-StatusPass 'Signing: dotfiles scripts' -Detail 'all signed'
    } else {
      Write-StatusFail 'Signing: dotfiles scripts' -Detail "$($dotfilesSigning.unsigned_count) unsigned"
    }

    if ($profileSignature -and $profileSignature.Status -eq 'Valid') {
      Write-StatusPass 'Signing: PowerShell profile'
    } else {
      $status = if ($profileSignature) { $profileSignature.Status } else { 'missing' }
      Write-StatusFail 'Signing: PowerShell profile' -Detail "status: $status"
    }

    Write-StatusPass 'Signing posture' -Detail 'AllSigned requirements satisfied'
  } else {
    if ($profileSignature -and $profileSignature.Status -eq 'NotSigned' -and $EffectiveExecutionPolicy -eq 'RemoteSigned') {
      Write-StatusPass 'Signing: PowerShell profile' -Detail 'NotSigned is acceptable under RemoteSigned'
    } elseif ($profileSignature) {
      Write-StatusPass 'Signing: PowerShell profile' -Detail "status: $($profileSignature.Status)"
    } else {
      Write-StatusSkip 'Signing: PowerShell profile' -Reason 'profile not present'
    }

    $unsignedCounts = $scoopSigning.unsigned_count + $miseSigning.unsigned_count + $dotfilesSigning.unsigned_count
    if ($unsignedCounts -eq 0) {
      Write-StatusPass 'Signing posture' -Detail "all signable Scoop, mise, and dotfiles scripts are signed; policy is $EffectiveExecutionPolicy"
    } else {
      Write-StatusPass 'Signing posture' -Detail "$unsignedCounts unsigned script(s) found; policy is $EffectiveExecutionPolicy"
    }
  }
}

function Get-PersonalScriptPath {
  if ($PersonalScript) {
    if ([System.IO.Path]::IsPathRooted($PersonalScript)) {
      return $PersonalScript
    }
    return (Join-Path $BootstrapRoot $PersonalScript)
  }

  return (Join-Path $BootstrapRoot 'Other\scripts\personal-bootstrap-windows.ps1')
}

function Invoke-PersonalLayer {
  if (-not $Personal) {
    Write-Host '  Personal layer: not requested' -ForegroundColor DarkGray
    return
  }

  $scriptPath = Get-PersonalScriptPath
  if (-not (Test-Path $scriptPath)) {
    Write-StatusFail 'Personal layer' -Detail "script not found at $scriptPath"
  }

  $personalArgs = @{ Mode = $Mode; DotfilesRepo = $DotfilesRepo }
  if (Test-DryRun) { $personalArgs['DryRun'] = $true }

  & $scriptPath @personalArgs
  Write-StatusPass 'Personal layer' -Detail 'completed'
}

function Invoke-FoundationEnsureFlow {
  Ensure-Scoop
  Ensure-FoundationPackages
  Ensure-Mise
  Ensure-Profile
  Ensure-CurrentPwshActivation
  Ensure-WindowsTerminalPwshDefault
  Ensure-MiseConfig
  Handle-Zscaler
  Ensure-MiseTools
  Refresh-ZscalerTlsClientsAfterMiseTools
  Invoke-FoundationValidation
  Invoke-PersonalLayer
}

function Invoke-FoundationUpdate {
  Ensure-Scoop

  Write-Host '  Updating Scoop packages...' -ForegroundColor Cyan
  Invoke-OrDry -Label 'scoop update *' -Command { scoop update * 2>$null }
  if ($RequiresSigning) {
    Invoke-OrDry -Label 'Sign-ScoopScripts' -Command { Sign-ScoopScripts }
  }
  if (Test-DryRun) {
    Write-StatusFix 'Scoop update' -Action 'would update'
  } else {
    Write-StatusPass 'Scoop update' -Detail 'update complete'
  }

  if ($global:RESOLVED_MISE_TOOLS -eq 'true' -and (Test-CommandExists 'mise')) {
    Invoke-OrDry -Label 'mise upgrade' -Command { mise upgrade 2>$null }
    if ($RequiresSigning) {
      Invoke-OrDry -Label 'Sign-MiseScripts' -Command { Sign-MiseScripts }
    }
    if (Test-DryRun) {
      Write-StatusFix 'Mise update' -Action 'would upgrade'
    } else {
      Write-StatusPass 'Mise update' -Detail 'upgrade complete'
    }
  } else {
    Write-StatusSkip 'Mise update' -Reason 'mise-tools disabled or mise missing'
  }

  Invoke-FoundationEnsureFlow
}

function Select-Mode {
  if ($Mode) { return }

  if (-not $NonInteractive -and (Test-CommandExists 'gum')) {
    $script:Mode = gum choose --header 'Choose a Windows foundation mode' setup ensure update personal
    return
  }

  if (-not $NonInteractive) {
    Write-Host 'Select mode:' -ForegroundColor Cyan
    Write-Host '  1. setup   - Full first-time install'
    Write-Host '  2. ensure  - Idempotent re-run'
    Write-Host '  3. update  - Update packages and runtimes'
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

  Write-Fatal 'MODE is not set and running non-interactively. Pass setup, ensure, update, or personal.'
}

function Main {
  Select-Mode

  $script:ZscalerDetection = Get-ZscalerDetection

  Resolve-AllFlags `
    -CliShell $Shell `
    -CliProfile $Profile_ `
    -EnableFlags $EnableFlags `
    -DisableFlags $DisableFlags `
    -ZscalerDetection $script:ZscalerDetection

  Write-Host ''
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host '  Windows foundation bootstrap' -ForegroundColor White
  Write-Host "  Mode:    $Mode" -ForegroundColor DarkGray
  Write-Host "  Shell:   $global:RESOLVED_SHELL" -ForegroundColor DarkGray
  Write-Host "  Profile: $global:RESOLVED_PROFILE" -ForegroundColor DarkGray
  Write-Host "  Zscaler: $global:RESOLVED_ZSCALER" -ForegroundColor DarkGray
  Write-Host "  Policy:  $EffectiveExecutionPolicy" -ForegroundColor DarkGray
  if (Test-DryRun) {
    Write-Host '  ** DRY RUN — no changes will be made **' -ForegroundColor Magenta
  }
  Write-Host '---' -ForegroundColor DarkGray
  Write-Host ''

  switch ($Mode) {
    { $_ -in @('setup', 'ensure') } {
      Invoke-FoundationEnsureFlow
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

  Write-StatusSummary -Label 'Foundation'
  Write-Host 'Done.' -ForegroundColor Green
}

Main
