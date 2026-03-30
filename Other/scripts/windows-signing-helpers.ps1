<#
.SYNOPSIS
Exports Windows code signing helper functions into the current session.

.DESCRIPTION
This script defines and exports the code signing helper functions for
managing local code signing on a Windows engineering foundation. These
functions locate the local Scoop signer certificate and apply it to
Scoop scripts, mise scripts, and the user's PowerShell profile.
#>

function global:Get-LocalCodeSigningCert {
  Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
    Where-Object Subject -eq 'CN=LocalScoopSigner' |
    Select-Object -First 1
}

function global:Ensure-LocalCodeSigningCert {
  $cert = Get-LocalCodeSigningCert
  if ($cert) {
    return $cert
  }

  $cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject 'CN=LocalScoopSigner' `
    -CertStoreLocation 'Cert:\CurrentUser\My'

  $cerPath = Join-Path $env:TEMP 'LocalScoopSigner.cer'
  Export-Certificate -Cert $cert -FilePath $cerPath -Force | Out-Null

  foreach ($store in @('Root', 'TrustedPublisher')) {
    certutil -user -addstore $store $cerPath -f | Out-Null
  }

  Remove-Item $cerPath -ErrorAction SilentlyContinue
  return $cert
}

function global:Sign-ScoopScripts {
  $cert = Get-LocalCodeSigningCert
  if (-not $cert) { return }
  $scoopRoot = Join-Path $env:USERPROFILE 'scoop'
  if (-not (Test-Path $scoopRoot)) { return }
  Get-ChildItem $scoopRoot -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge 4 } |
    ForEach-Object {
      Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
    }
}

function global:Sign-MiseScripts {
  $cert = Get-LocalCodeSigningCert
  if (-not $cert) { return }
  $miseRoot = Join-Path $HOME 'AppData\Local\mise'
  if (-not (Test-Path $miseRoot)) { return }
  Get-ChildItem $miseRoot -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge 4 } |
    ForEach-Object {
      Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
    }
}

function global:Sign-DotfilesWindowsScripts {
  $cert = Get-LocalCodeSigningCert
  if (-not $cert) { return }
  $scriptsRoot = Join-Path $HOME '.dotfiles\Other\scripts'
  if (-not (Test-Path $scriptsRoot)) { return }
  Get-ChildItem $scriptsRoot -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue |
    Where-Object { $_.Length -ge 4 } |
    ForEach-Object {
      Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
    }
}

function global:Sign-Profile {
  $cert = Get-LocalCodeSigningCert
  if (-not $cert) { return }
  if (-not (Test-Path $PROFILE)) { return }
  $profileFile = Get-Item $PROFILE -ErrorAction SilentlyContinue
  if (-not $profileFile -or $profileFile.Length -lt 4) { return }
  Set-AuthenticodeSignature -FilePath $PROFILE -Certificate $cert | Out-Null
}
