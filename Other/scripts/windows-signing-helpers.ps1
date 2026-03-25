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
  Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object Subject -eq 'CN=LocalScoopSigner' |
    Select-Object -First 1
}

function global:Sign-ScoopScripts {
  $cert = Get-LocalCodeSigningCert
  if (-not $cert) { return }
  Get-ChildItem "$env:USERPROFILE\scoop" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
  }
}

function global:Sign-MiseScripts {
  $cert = Get-LocalCodeSigningCert
  if (-not $cert) { return }
  Get-ChildItem "$HOME\AppData\Local\mise" -Recurse -Filter *.ps1 -ErrorAction SilentlyContinue | ForEach-Object {
    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
  }
}

function global:Sign-Profile {
  $cert = Get-LocalCodeSigningCert
  if (-not $cert) { return }
  Set-AuthenticodeSignature -FilePath $PROFILE -Certificate $cert | Out-Null
}
