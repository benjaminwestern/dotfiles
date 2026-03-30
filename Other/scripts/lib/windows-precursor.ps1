if ($global:_WINDOWS_PRECURSOR_PS1_LOADED) { return }
$global:_WINDOWS_PRECURSOR_PS1_LOADED = $true

function global:Test-PrecursorCommandExists {
  param([Parameter(Mandatory)][string]$Name)
  [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function global:Get-PrecursorCodeSigningCert {
  Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object Subject -eq 'CN=LocalScoopSigner' |
    Select-Object -First 1
}

function global:Ensure-PrecursorCodeSigningCert {
  $cert = Get-PrecursorCodeSigningCert
  if ($cert) {
    return $cert
  }

  $cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=LocalScoopSigner' `
    -CertStoreLocation 'Cert:\CurrentUser\My'

  $cerPath = Join-Path $env:TEMP 'LocalScoopSigner.cer'
  Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null
  certutil -user -addstore Root $cerPath -f | Out-Null
  certutil -user -addstore TrustedPublisher $cerPath -f | Out-Null
  Remove-Item $cerPath -ErrorAction SilentlyContinue

  return $cert
}

function global:Update-PrecursorPath {
  $prepend = @(
    (Join-Path $HOME 'scoop\shims'),
    (Join-Path $HOME 'scoop\apps\pwsh\current')
  )

  for ($index = $prepend.Count - 1; $index -ge 0; $index--) {
    $candidate = $prepend[$index]
    if (-not $candidate -or -not (Test-Path $candidate)) {
      continue
    }

    $segments = @()
    if ($env:PATH) {
      $segments = $env:PATH -split ';'
    }

    $alreadyPresent = $false
    foreach ($segment in $segments) {
      if ([string]::Equals($segment, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
        $alreadyPresent = $true
        break
      }
    }

    if (-not $alreadyPresent) {
      $env:PATH = "$candidate;$env:PATH"
    }
  }
}

function global:Sign-PrecursorScripts {
  param(
    [string]$ScriptsRoot = (Join-Path $HOME '.dotfiles\Other\scripts')
  )

  $cert = Get-PrecursorCodeSigningCert
  if (-not $cert) { return }
  if (-not $ScriptsRoot -or -not (Test-Path $ScriptsRoot)) { return }

  Get-ChildItem $ScriptsRoot -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge 4 } |
    ForEach-Object {
      Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
    }
}

function global:Install-PrecursorScoop {
  if (Test-PrecursorCommandExists 'scoop') {
    Update-PrecursorPath
    $extrasBucket = Join-Path $HOME 'scoop\buckets\extras'
    if (-not (Test-Path $extrasBucket)) {
      scoop bucket add extras 2>$null
    }
    return
  }

  $installerPath = Join-Path $env:TEMP 'install-scoop.ps1'
  Invoke-WebRequest `
    -Uri 'https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1' `
    -OutFile $installerPath

  $requiresSigning = (Get-ExecutionPolicy) -eq 'AllSigned'
  if ($requiresSigning) {
    $cert = Ensure-PrecursorCodeSigningCert
    $content = Get-Content $installerPath -Raw
    $content = $content -replace `
      "@\('Unrestricted', 'RemoteSigned', 'ByPass'\)", `
      "@('Unrestricted', 'RemoteSigned', 'ByPass', 'AllSigned')"
    Set-Content -Path $installerPath -Value $content -Encoding Ascii

    Set-AuthenticodeSignature -FilePath $installerPath -Certificate $cert | Out-Null
  } else {
    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($currentUserPolicy -eq 'Restricted') {
      Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    }
  }

  & $installerPath -RunAsAdmin:$false
  Update-PrecursorPath

  $extrasBucket = Join-Path $HOME 'scoop\buckets\extras'
  if (-not (Test-Path $extrasBucket)) {
    scoop bucket add extras 2>$null
  }

  $cert = Get-PrecursorCodeSigningCert
  if ($cert) {
    Get-ChildItem (Join-Path $HOME 'scoop') -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
      Where-Object { $_.Length -ge 4 } |
      ForEach-Object {
        Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
      }
  }
}

function global:Install-PrecursorPwsh {
  Update-PrecursorPath
  if (Test-PrecursorCommandExists 'pwsh') {
    return
  }

  if (-not (Test-PrecursorCommandExists 'scoop')) {
    Install-PrecursorScoop
  }

  if (-not (Test-PrecursorCommandExists 'scoop')) {
    throw 'Scoop was not available after precursor bootstrap.'
  }

  scoop install pwsh 2>$null
  Update-PrecursorPath

  $cert = if ((Get-ExecutionPolicy) -eq 'AllSigned') {
    Ensure-PrecursorCodeSigningCert
  } else {
    Get-PrecursorCodeSigningCert
  }
  if ($cert) {
    Get-ChildItem (Join-Path $HOME 'scoop') -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
      Where-Object { $_.Length -ge 4 } |
      ForEach-Object {
        Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
      }
  }
}

function global:Invoke-PwshPrecursor {
  param(
    [Parameter(Mandatory)][string]$ScriptPath,
    [string[]]$ArgumentList = @()
  )

  if ($PSVersionTable.PSVersion.Major -ge 7) {
    return
  }

  Install-PrecursorScoop
  Install-PrecursorPwsh
  Update-PrecursorPath
  Sign-PrecursorScripts -ScriptsRoot (Split-Path -Parent $ScriptPath)

  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not $pwsh) {
    throw 'pwsh was not found after precursor installation.'
  }

  & $pwsh -NoLogo -NoProfile -File $ScriptPath @ArgumentList
  $exitCode = $LASTEXITCODE
  if ($null -eq $exitCode) {
    $exitCode = 0
  }
  exit $exitCode
}
