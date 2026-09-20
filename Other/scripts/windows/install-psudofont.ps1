<#
.SYNOPSIS
Installs psudoFont Liga Mono for the current Windows user.
#>
param([switch]$Force)

$ErrorActionPreference = 'Stop'

$version = 'v.2.2.0'
$archiveVersion = $version -replace '^v', 'V'
$archiveName = "psudoFont_Liga_Mono_$archiveVersion.zip"
$archiveHash = 'd6f214cd8fe4e2bf2e5fd1799c7f6e0f48ace5501d780b3249f91bdffcf97f07'
$downloadUrl = "https://github.com/psudo-dev/psudofont-liga-mono/releases/download/$version/$archiveName"
$fontNames = @(
  'psudoFont_Liga_Mono_-_Regular.ttf',
  'psudoFont_Liga_Mono_-_Bold.ttf',
  'psudoFont_Liga_Mono_-_Italic.ttf',
  'psudoFont_Liga_Mono_-_BoldItalic.ttf'
)
$fontDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$registryPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'

if (-not $Force -and -not ($fontNames | Where-Object { -not (Test-Path (Join-Path $fontDirectory $_)) })) {
  Write-Host 'psudoFont Liga Mono is already installed.' -ForegroundColor Green
  return
}

$tempDirectory = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())
$archivePath = Join-Path $tempDirectory $archiveName

try {
  New-Item -ItemType Directory -Path $tempDirectory | Out-Null
  Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath -UseBasicParsing

  if ((Get-FileHash $archivePath -Algorithm SHA256).Hash -ne $archiveHash) {
    throw "Hash verification failed for $archiveName"
  }

  Expand-Archive -Path $archivePath -DestinationPath $tempDirectory -Force
  New-Item -ItemType Directory -Path $fontDirectory -Force | Out-Null
  New-Item -Path $registryPath -Force | Out-Null

  foreach ($fontName in $fontNames) {
    $source = Get-ChildItem -Path $tempDirectory -Recurse -File -Filter $fontName |
      Where-Object { $_.FullName -notmatch '[\\/]__MACOSX[\\/]' } |
      Select-Object -First 1
    if (-not $source) { throw "$fontName was not found in $archiveName" }

    $destination = Join-Path $fontDirectory $fontName
    Copy-Item -Path $source.FullName -Destination $destination -Force
    $registryName = "$([System.IO.Path]::GetFileNameWithoutExtension($fontName)) (TrueType)"
    New-ItemProperty -Path $registryPath -Name $registryName -Value $destination -PropertyType String -Force | Out-Null
  }
} finally {
  Remove-Item $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'psudoFont Liga Mono installed. Restart terminal applications to use it.' -ForegroundColor Green
