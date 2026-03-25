# Windows foundation bootstrap

This runbook gets a bare Windows machine to a stable engineering foundation
using native PowerShell, Scoop, `mise`, and Google Chrome-driven Zscaler
detection. The result is a machine that can install packages, activate shell
tooling, resolve runtime shims, trust corporate TLS interception when present,
and be safely maintained later by the same bootstrap flow.

The approach is deliberately conservative for customer environments. It avoids
personal dotfiles, assumes user-space only, and treats `AllSigned` as a real
constraint rather than something to work around unsafely.

It assumes:

- user-space only
- effective PowerShell execution policy is `AllSigned`
- the target is a reusable foundation, not personal dotfiles yet

## Quick start

Use this document in order. The high-level flow is:

1. Create a local code-signing certificate.
2. Install Scoop from a patched, signed local installer copy.
3. Install the minimum bootstrap packages.
4. Create and sign the managed PowerShell profile.
5. Detect active Zscaler trust in Chrome and repair TLS trust before full
   `mise` reconciliation.
6. Install and validate the full foundation toolset.

If you are behind Zscaler, do not skip the trust phase. `mise install`, npm,
and Python package operations can fail until the CA bundle is in place.

## What this bootstrap delivers

By the end of the runbook, the machine should have:

- Scoop working under `AllSigned`
- a managed and signed PowerShell profile
- `mise` installed, activated, and able to resolve foundation runtimes
- a reusable CA bundle for npm, Python, Git, curl, and related tools when
  Zscaler is active
- a clean `opencode` foundation directory structure
- validation commands that prove the machine is usable rather than merely
  partially installed

## Foundation package list

Install with Scoop:

- `git`
- `gh`
- `jq`
- `jid`
- `yq`
- `fzf`
- `fd`
- `ripgrep`
- `zoxide`
- `lazygit`
- `mise`
- `charm-gum`
- `vscode`
- `openssl`

## Phase 1: create a local signing certificate

Run:

```powershell
$cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=LocalScoopSigner" -CertStoreLocation "Cert:\CurrentUser\My"
Export-Certificate -Cert $cert -FilePath "$env:TEMP\LocalScoopSigner.cer" -Force
certutil -user -addstore Root "$env:TEMP\LocalScoopSigner.cer" -f
certutil -user -addstore TrustedPublisher "$env:TEMP\LocalScoopSigner.cer" -f
```

Verify:

```powershell
Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject,Thumbprint,NotAfter
```

## Phase 2: install Scoop under `AllSigned`

Download the installer locally:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1" -OutFile "$env:TEMP\install-scoop.ps1"
```

Patch the execution policy allowlist to include `AllSigned`:

```powershell
$path = "$env:TEMP\install-scoop.ps1"
$content = Get-Content $path -Raw
$content = $content -replace "@\('Unrestricted', 'RemoteSigned', 'ByPass'\)", "@('Unrestricted', 'RemoteSigned', 'ByPass', 'AllSigned')"
Set-Content -Path $path -Value $content -Encoding Ascii
```

Sign the installer:

```powershell
Set-AuthenticodeSignature -FilePath "$env:TEMP\install-scoop.ps1" -Certificate $cert
Get-AuthenticodeSignature -FilePath "$env:TEMP\install-scoop.ps1" | Format-List Status,StatusMessage,Path
```

Run it:

```powershell
& "$env:TEMP\install-scoop.ps1" -RunAsAdmin:$false
```

Sign Scoop-managed PowerShell files:

```powershell
Get-ChildItem "$env:USERPROFILE\scoop" -Recurse -Filter *.ps1 | ForEach-Object {
    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
}
```

Verify:

```powershell
scoop --version
```

## Phase 3: install minimal bootstrap packages

Add `extras`:

```powershell
scoop bucket add extras
```

Install the minimum packages needed before runtime reconciliation:

```powershell
scoop install git mise charm-gum openssl gh jq jid yq fzf fd ripgrep zoxide lazygit vscode
```

Re-sign Scoop PowerShell files again:

```powershell
Get-ChildItem "$env:USERPROFILE\scoop" -Recurse -Filter *.ps1 | ForEach-Object {
    Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert | Out-Null
}
```

Verify:

```powershell
git --version
mise --version
gum --version
openssl version
```

## Phase 4: create the PowerShell profile and activate `mise`

Create the profile path if needed:

```powershell
New-Item -ItemType Directory -Force (Split-Path -Parent $PROFILE)
New-Item -ItemType File -Force $PROFILE
```

Write the managed foundation block, sourcing the standalone `windows-signing-helpers.ps1` script to load the signing functions directly rather than copying them from this README:

```powershell
@'
$env:MISE_PWSH_CHPWD_WARNING=0
(& mise activate pwsh) | Out-String | Invoke-Expression
(& zoxide init powershell) | Out-String | Invoke-Expression

. ~/.dotfiles/Other/scripts/windows-signing-helpers.ps1
'@ | Set-Content $PROFILE -Encoding Ascii
```

Sign the profile:

```powershell
Set-AuthenticodeSignature -FilePath $PROFILE -Certificate $cert
Get-AuthenticodeSignature $PROFILE | Format-List Status,StatusMessage,Path
```

Reload it:

```powershell
. $PROFILE
```

Verify:

```powershell
mise --version
zoxide --version
Get-Command z
```

## Phase 5: detect Zscaler and bootstrap trust

Use Google Chrome as the decision point:

1. Open Chrome.
2. Browse to `https://registry.npmjs.org`.
3. Inspect the certificate chain.
4. If the chain shows Zscaler, continue with this section.
5. If not, skip to Phase 6.

Create the directories:

```powershell
New-Item -ItemType Directory -Force "$HOME\certs"
New-Item -ItemType Directory -Force "$HOME\certs\zscaler-ca"
New-Item -ItemType Directory -Force "$HOME\.config\mise"
```

Find Zscaler CA certs in the Windows stores:

```powershell
$zscalerCaCerts = Get-ChildItem Cert:\CurrentUser\Root, Cert:\LocalMachine\Root, Cert:\CurrentUser\CA, Cert:\LocalMachine\CA |
  Where-Object {
    $_.Subject -like "*Zscaler*" -and
    $_.Subject -notlike "*CN=www.google.com*"
  }

$zscalerCaCerts | Format-List Subject,Issuer,Thumbprint,PSParentPath
```

If nothing useful is returned, export the Zscaler root or intermediate CA from
Chrome's certificate viewer and import it:

```powershell
Import-Certificate -FilePath "$HOME\Downloads\zscaler-root.cer" -CertStoreLocation Cert:\CurrentUser\Root
Import-Certificate -FilePath "$HOME\Downloads\zscaler-intermediate.cer" -CertStoreLocation Cert:\CurrentUser\CA
```

Then re-run the `Get-ChildItem ... Zscaler` query.

Export the discovered CA certs:

```powershell
$i = 0
foreach ($c in $zscalerCaCerts) {
  $i++
  Export-Certificate -Cert $c -FilePath "$HOME\certs\zscaler-ca\zscaler-ca-$i.cer" -Force | Out-Null
}
```

Build the Zscaler CA PEM bundle:

```powershell
$pem = ""
Get-ChildItem "$HOME\certs\zscaler-ca\*.cer" | ForEach-Object {
  $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
  $pem += "-----BEGIN CERTIFICATE-----`n"
  $pem += [Convert]::ToBase64String($bytes, 'InsertLineBreaks')
  $pem += "`n-----END CERTIFICATE-----`n"
}
Set-Content -Path "$HOME\certs\zscaler_ca_bundle.pem" -Value $pem.Trim() -Encoding Ascii
```

Bootstrap Python just enough to obtain a base CA bundle:

```powershell
mise install python@latest
. $PROFILE
python -m ensurepip --upgrade
$certifiPath = python -c "import pip._vendor.certifi as c; print(c.where())"
```

Build the merged PEM bundle:

```powershell
$certifiContent = Get-Content $certifiPath -Raw
$zscalerContent = Get-Content "$HOME\certs\zscaler_ca_bundle.pem" -Raw
Set-Content -Path "$HOME\certs\golden_pem.pem" -Value ($certifiContent.TrimEnd() + "`n" + $zscalerContent.Trim() + "`n") -Encoding Ascii
```

Write a minimal `mise` config first so cert-aware tool installs do not fail:

```powershell
@'
[settings]
experimental = true

[env]
_.file = "~/.config/mise/.env"

[tools]
go = "latest"
node = "latest"
bun = "latest"
python = "latest"
uv = "latest"
terraform = "latest"
gcloud = "latest"
usage = "latest"
'@ | Set-Content "$HOME\.config\mise\config.toml" -Encoding Ascii
```

Append the certificate environment block into `mise` config:

```powershell
$certFile = "C:/Users/$env:USERNAME/certs/golden_pem.pem"
$certDir = "C:/Users/$env:USERNAME/certs"

Add-Content "$HOME\.config\mise\config.toml" @"

SSL_CERT_FILE = "$certFile"
SSL_CERT_DIR = "$certDir"
CERT_PATH = "$certFile"
CERT_DIR = "$certDir"
REQUESTS_CA_BUNDLE = "$certFile"
CURL_CA_BUNDLE = "$certFile"
NODE_EXTRA_CA_CERTS = "$certFile"
GRPC_DEFAULT_SSL_ROOTS_FILE_PATH = "$certFile"
GIT_SSL_CAINFO = "$certFile"
CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE = "$certFile"
PIP_CERT = "$certFile"
NPM_CONFIG_CAFILE = "$certFile"
npm_config_cafile = "$certFile"
AWS_CA_BUNDLE = "$certFile"
"@
```

Persist the same values at user scope:

```powershell
[Environment]::SetEnvironmentVariable("SSL_CERT_FILE", $certFile, "User")
[Environment]::SetEnvironmentVariable("SSL_CERT_DIR", $certDir, "User")
[Environment]::SetEnvironmentVariable("CERT_PATH", $certFile, "User")
[Environment]::SetEnvironmentVariable("CERT_DIR", $certDir, "User")
[Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $certFile, "User")
[Environment]::SetEnvironmentVariable("CURL_CA_BUNDLE", $certFile, "User")
[Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $certFile, "User")
[Environment]::SetEnvironmentVariable("GRPC_DEFAULT_SSL_ROOTS_FILE_PATH", $certFile, "User")
[Environment]::SetEnvironmentVariable("GIT_SSL_CAINFO", $certFile, "User")
[Environment]::SetEnvironmentVariable("CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE", $certFile, "User")
[Environment]::SetEnvironmentVariable("PIP_CERT", $certFile, "User")
[Environment]::SetEnvironmentVariable("NPM_CONFIG_CAFILE", $certFile, "User")
[Environment]::SetEnvironmentVariable("npm_config_cafile", $certFile, "User")
[Environment]::SetEnvironmentVariable("AWS_CA_BUNDLE", $certFile, "User")
```

Reload the profile:

```powershell
. $PROFILE
```

Configure Git and pip explicitly:

```powershell
git config --global http.sslcainfo "$HOME\certs\golden_pem.pem"
python -m pip config set global.cert "$HOME\certs\golden_pem.pem"
```

If you use gcloud:

```powershell
gcloud config set core/custom_ca_certs_file "$HOME\certs\golden_pem.pem"
```

## Phase 6: validate cert-sensitive tooling before full `mise install`

Run:

```powershell
node -p "process.env.NODE_EXTRA_CA_CERTS"
npm.cmd config get cafile
npm.cmd ping --loglevel verbose
python -m pip --version
git config --global --get http.sslcainfo
```

If these fail:

- confirm Chrome still shows Zscaler
- confirm `golden_pem.pem` exists
- confirm the bundle was built from real Zscaler CA certs, not a leaf cert
- confirm `npm.cmd` works even if `npm.ps1` is unsigned

## Phase 7: run full `mise` reconciliation

Now that trust is in place, install the full foundation `mise` toolset:

```powershell
mise install
```

Sign `mise` PowerShell wrappers:

```powershell
Sign-MiseScripts
```

Verify:

```powershell
mise current
node --version
python --version
python -m pip --version
go version
terraform version
gcloud version
```

## Phase 8: create `opencode` foundation directories

Create the directories:

```powershell
New-Item -ItemType Directory -Force "$HOME\.config\opencode"
New-Item -ItemType Directory -Force "$HOME\.config\opencode\plugins"
```

Optionally create a minimal placeholder config:

```powershell
@'
{
  "plugins": []
}
'@ | Set-Content "$HOME\.config\opencode\opencode.json" -Encoding Ascii
```

Verify:

```powershell
Get-Content "$HOME\.config\opencode\opencode.json"
```

## Phase 9: final validation

Package manager and shell:

```powershell
scoop --version
$PROFILE
Test-Path $PROFILE
Get-AuthenticodeSignature $PROFILE | Format-List Status,StatusMessage,Path
```

Foundation tools:

```powershell
git --version
gh --version
jq --version
jid --help
yq --version
fzf --version
fd --version
rg --version
zoxide --version
lazygit --version
mise --version
gum --version
code --version
openssl version
```

`mise` and runtimes:

```powershell
mise env
mise current
node --version
python --version
python -m pip --version
go version
terraform version
```

TLS-sensitive checks:

```powershell
node -p "process.env.NODE_EXTRA_CA_CERTS"
npm.cmd config get cafile
npm.cmd ping --loglevel verbose
git config --global --get http.sslcainfo
```

Windows signing health:

```powershell
Get-ChildItem "$env:USERPROFILE\scoop" -Recurse -Filter *.ps1 | Get-AuthenticodeSignature | Where-Object Status -ne 'Valid' | Select-Object Path,Status
Get-ChildItem "$HOME\AppData\Local\mise" -Recurse -Filter *.ps1 | Get-AuthenticodeSignature | Where-Object Status -ne 'Valid' | Select-Object Path,Status
```

If both return nothing, signing is healthy.

## Recovery helpers

If you end up in a broken shell where your profile won't load (e.g., due to an unsigned script or HashMismatch), you can source the standalone `windows-signing-helpers.ps1` script to load the signing functions directly, rather than just copying from this README:

```powershell
. ~/.dotfiles/Other/scripts/windows-signing-helpers.ps1
```

Re-sign Scoop scripts:

```powershell
Sign-ScoopScripts
```

Re-sign `mise` scripts:

```powershell
Sign-MiseScripts
```

Re-sign the profile:

```powershell
Sign-Profile
. $PROFILE
```

If `$PROFILE` shows `HashMismatch` or gets corrupted, you can rewrite it and sign it again using the standalone script rather than copying the functions manually:

```powershell
@'
$env:MISE_PWSH_CHPWD_WARNING=0
(& mise activate pwsh) | Out-String | Invoke-Expression
(& zoxide init powershell) | Out-String | Invoke-Expression

. ~/.dotfiles/Other/scripts/windows-signing-helpers.ps1
'@ | Set-Content $PROFILE -Encoding Ascii

. ~/.dotfiles/Other/scripts/windows-signing-helpers.ps1
Sign-Profile
. $PROFILE
```

## Important lessons

- Scoop installer must be downloaded locally, patched, signed, then run under
  `AllSigned`
- Scoop and `mise` both create `.ps1` wrappers that must be re-signed over time
- `$PROFILE` itself must be signed after every edit
- `npm.cmd` is the correct debug path when `npm.ps1` is blocked
- Zscaler trust must be built from real Zscaler CA certs, not intercepted leaf
  certs like `CN=www.google.com`
- use Chrome to decide whether Zscaler is active, but use exported CA certs for
  trust material
