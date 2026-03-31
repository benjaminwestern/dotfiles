<#
.SYNOPSIS
Compatibility shim for the Windows signing helper library.

.DESCRIPTION
The signing helper implementation now lives at
Other/scripts/lib/signing-helpers-windows.ps1. This top-level shim exists so
older PowerShell profiles or local references do not break after the file was
moved under lib/.
#>

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'lib\signing-helpers-windows.ps1')
