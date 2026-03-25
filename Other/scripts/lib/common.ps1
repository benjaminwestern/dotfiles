# =============================================================================
# common.ps1 -- Shared library for Windows bootstrap scripts
#
# Dot-sourced by foundation-windows.ps1 and personal-bootstrap-windows.ps1.
# PowerShell parallel of common.zsh. Same state file format
# (~/.config/dotfiles/state.env), same resolution logic.
#
# Sections:
#   1. Constants
#   2. Dry-Run
#   3. Core Utilities
#   4. Status Output
#   5. State File
#   6. Resolution
#   7. Managed Block Writer
# =============================================================================

# Guard against double-sourcing.
if ($global:_COMMON_PS1_LOADED) { return }
$global:_COMMON_PS1_LOADED = $true


# =============================================================================
# SECTION 1: CONSTANTS
# =============================================================================

# -- State file path ----------------------------------------------------------
# The state file is a simple KEY=VALUE env file that persists resolved settings
# across bootstrap runs. Lives outside the dotfiles repo so it is specific to
# the current machine.
$global:STATE_FILE_PATH = Join-Path $HOME '.config\dotfiles\state.env'

# -- Status symbols -----------------------------------------------------------
# Unicode glyphs used by the Write-Status* functions.
$global:STATUS_SYM_PASS = [char]0x2713   # check mark
$global:STATUS_SYM_FAIL = [char]0x2717   # ballot x
$global:STATUS_SYM_SKIP = [char]0x25CB   # white circle

# -- Managed block markers ----------------------------------------------------
# Delimiters injected into config files by Write-ManagedBlock. Each pair fences
# a block of content that the bootstrap owns and may overwrite.
$global:PROFILE_BEGIN = '# >>> foundation-bootstrap >>>'
$global:PROFILE_END   = '# <<< foundation-bootstrap <<<'
$global:MISE_BEGIN     = '# >>> foundation-seed >>>'
$global:MISE_END       = '# <<< foundation-seed <<<'
$global:ZSCALER_ENV_BEGIN = '# >>> zscaler-bootstrap >>>'
$global:ZSCALER_ENV_END   = '# <<< zscaler-bootstrap <<<'


# =============================================================================
# SECTION 2: DRY-RUN
# =============================================================================

# When set to $true, the bootstrap runs the entire resolution, pre-flight, and
# validation pipeline but NEVER executes any destructive command. Instead it
# prints what WOULD happen.
#
# The following STILL run during dry-run:
#   - Pre-flight inventory (read-only machine state snapshot)
#   - Flag resolution and display
#   - Validation checks (Test-CommandExists, file existence, version queries)
#   - Status output (shows what would pass/fix/skip/fail)
#   - State file writes (so subsequent dry-runs remember the resolved flags)
$global:DRY_RUN = $false

function global:Test-DryRun {
  <#
  .SYNOPSIS
      Check whether dry-run mode is enabled.
  .NOTES
      Checks: DRY_RUN global variable.
      Gates: None.
      Side effects: None.
      Idempotency: Pure query.
  #>
  [bool]$global:DRY_RUN
}

function global:Write-DryRunLog {
  <#
  .SYNOPSIS
      Print a dry-run notice for a command that would be skipped.
  .NOTES
      Checks: None -- always prints.
      Gates: Should only be called when Test-DryRun is true.
      Side effects: Writes to stdout.
      Idempotency: Pure output.
  #>
  param([Parameter(Mandatory)][string]$Action)
  Write-Host "  [dry-run] would run: $Action" -ForegroundColor Magenta
}

function global:Invoke-OrDry {
  <#
  .SYNOPSIS
      Execute a scriptblock, or log it if dry-run is active.
  .DESCRIPTION
      The core dry-run gate. Every destructive command should be routed through
      this function. If DRY_RUN is true, the command is logged but not executed.
      If DRY_RUN is false, the command runs normally.
  .NOTES
      Checks: DRY_RUN flag.
      Gates: None -- delegates to the caller's judgement about what is destructive.
      Side effects: Either executes the command or prints what would have run.
      Idempotency: Depends on the underlying command.
  #>
  param(
    [Parameter(Mandatory)][string]$Label,
    [Parameter(Mandatory)][scriptblock]$Command
  )
  if (Test-DryRun) {
    Write-DryRunLog $Label
    return
  }
  & $Command
}


# =============================================================================
# SECTION 3: CORE UTILITIES
# =============================================================================

function global:Test-CommandExists {
  <#
  .SYNOPSIS
      Check whether a command is available on PATH.
  .DESCRIPTION
      Uses Get-Command to test availability without running the command.
  .NOTES
      Checks: Get-Command lookup
      Gates: None
      Side effects: None
      Idempotency: Pure query -- always safe to call.
  #>
  param([Parameter(Mandatory)][string]$Name)
  [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function global:Write-Fatal {
  <#
  .SYNOPSIS
      Print an error message to stderr and terminate.
  .DESCRIPTION
      Writes a red ERROR prefix followed by the message, then throws a
      terminating error so the script stops.
  .NOTES
      Checks: None
      Gates: None
      Side effects: Terminates the running script.
      Idempotency: N/A -- the process ends.
  #>
  param([Parameter(Mandatory)][string]$Message)
  Write-Host "ERROR: $Message" -ForegroundColor Red
  throw $Message
}


# =============================================================================
# SECTION 4: STATUS OUTPUT
# =============================================================================

# Global counters that track how many steps fell into each outcome.
$global:_STATUS_PASSED  = 0
$global:_STATUS_FIXED   = 0
$global:_STATUS_SKIPPED = 0
$global:_STATUS_FAILED  = 0

function global:Write-StatusPass {
  <#
  .SYNOPSIS
      Record and display a passing (already-correct) step.
  .DESCRIPTION
      Increments the passed counter and prints a green check line.
  .NOTES
      Checks: Nothing -- the caller has already verified the condition.
      Gates: None
      Side effects: Increments _STATUS_PASSED. Writes to stdout.
      Idempotency: Safe to call multiple times; counter increments each time.
  #>
  param(
    [Parameter(Mandatory)][string]$Description,
    [string]$Detail = ''
  )
  $global:_STATUS_PASSED++
  $detailPart = if ($Detail) { "($Detail)" } else { '' }
  $line = "  $STATUS_SYM_PASS {0,-45} {1}" -f $Description, $detailPart
  Write-Host $line -ForegroundColor Green
}

function global:Write-StatusFix {
  <#
  .SYNOPSIS
      Record and display a step that required remediation.
  .DESCRIPTION
      Increments the fixed counter and prints a yellow line with the action taken.
  .NOTES
      Checks: Nothing -- the caller performed the fix before calling this.
      Gates: None
      Side effects: Increments _STATUS_FIXED. Writes to stdout.
      Idempotency: Safe to call multiple times; counter increments each time.
  #>
  param(
    [Parameter(Mandatory)][string]$Description,
    [string]$Action = ''
  )
  $global:_STATUS_FIXED++
  $actionPart = if ($Action) { "-- $Action" } else { '' }
  $line = "  $STATUS_SYM_FAIL {0,-45} {1}" -f $Description, $actionPart
  Write-Host $line -ForegroundColor Yellow
}

function global:Write-StatusSkip {
  <#
  .SYNOPSIS
      Record and display a step that was intentionally skipped.
  .DESCRIPTION
      Increments the skipped counter and prints a gray line with the reason.
  .NOTES
      Checks: Nothing -- the caller determined the skip condition.
      Gates: None
      Side effects: Increments _STATUS_SKIPPED. Writes to stdout.
      Idempotency: Safe to call multiple times; counter increments each time.
  #>
  param(
    [Parameter(Mandatory)][string]$Description,
    [string]$Reason = ''
  )
  $global:_STATUS_SKIPPED++
  $reasonPart = if ($Reason) { "-- $Reason" } else { '' }
  $line = "  $STATUS_SYM_SKIP {0,-45} {1}" -f $Description, $reasonPart
  Write-Host $line -ForegroundColor DarkGray
}

function global:Write-StatusFail {
  <#
  .SYNOPSIS
      Record and display a fatal failure, then exit.
  .DESCRIPTION
      Increments the failed counter, prints a red error line, then calls
      Write-Fatal to terminate the script.
  .NOTES
      Checks: Nothing -- the caller detected the failure.
      Gates: None
      Side effects: Increments _STATUS_FAILED. Writes to stdout. Calls Write-Fatal.
      Idempotency: N/A -- the process exits.
  #>
  param(
    [Parameter(Mandatory)][string]$Description,
    [string]$Detail = ''
  )
  $global:_STATUS_FAILED++
  $detailPart = if ($Detail) { "($Detail)" } else { '' }
  $line = "  $STATUS_SYM_FAIL {0,-45} {1}" -f $Description, $detailPart
  Write-Host $line -ForegroundColor Red
  Write-Fatal "$Description$(if ($Detail) { ": $Detail" })"
}

function global:Write-StatusSummary {
  <#
  .SYNOPSIS
      Print a one-line summary of all status counters.
  .DESCRIPTION
      Reads the four global counters and formats them into a summary line.
  .NOTES
      Checks: Reads the four global counters.
      Gates: None
      Side effects: Writes to stdout.
      Idempotency: Always safe; reads counters without modifying them.
  #>
  param([Parameter(Mandatory)][string]$Label)
  $line = '{0}: {1} passed, {2} fixed, {3} skipped, {4} failed' -f `
    $Label, $global:_STATUS_PASSED, $global:_STATUS_FIXED, `
    $global:_STATUS_SKIPPED, $global:_STATUS_FAILED
  Write-Host $line -ForegroundColor White
}


# =============================================================================
# SECTION 5: STATE FILE
# =============================================================================

function global:Read-State {
  <#
  .SYNOPSIS
      Source the state file and return its contents as a hashtable.
  .DESCRIPTION
      Reads the KEY=VALUE state file and returns a hashtable of all settings.
      Blank lines and comment lines (starting with #) are ignored.
  .NOTES
      Checks: Whether the state file exists.
      Gates: None
      Side effects: None (read-only).
      Idempotency: Pure query -- always safe to call.
  #>
  $state = @{}
  if (Test-Path $STATE_FILE_PATH) {
    Get-Content $STATE_FILE_PATH | ForEach-Object {
      $line = $_.Trim()
      if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
        $eqIndex = $line.IndexOf('=')
        $key = $line.Substring(0, $eqIndex)
        $val = $line.Substring($eqIndex + 1)
        $state[$key] = $val
      }
    }
  }
  return $state
}

function global:Get-StateValue {
  <#
  .SYNOPSIS
      Retrieve a single value from the state file by key.
  .DESCRIPTION
      Reads the state file and returns the value for the given key. Returns
      an empty string if the key is absent.
  .NOTES
      Checks: Whether the state file exists and contains the key.
      Gates: None
      Side effects: None (read-only).
      Idempotency: Pure query.
  #>
  param([Parameter(Mandatory)][string]$Key)
  if (-not (Test-Path $STATE_FILE_PATH)) { return '' }
  $match = Get-Content $STATE_FILE_PATH | Where-Object {
    $_ -match "^${Key}="
  } | Select-Object -First 1
  if ($match) {
    $eqIndex = $match.IndexOf('=')
    return $match.Substring($eqIndex + 1)
  }
  return ''
}

function global:Set-StateValue {
  <#
  .SYNOPSIS
      Set a single key-value pair in the state file (idempotent).
  .DESCRIPTION
      If the key exists, replaces its value. If not, appends it. Uses a
      temp file and atomic move for safety.
  .NOTES
      Checks: Whether the key already exists in the file.
      Gates: None
      Side effects: Rewrites the state file via atomic temp-file swap.
      Idempotency: If the key already has the given value, file content is
                   unchanged (though it is still rewritten atomically).
  #>
  param(
    [Parameter(Mandatory)][string]$Key,
    [Parameter(Mandatory)][string]$Value
  )

  $dir = Split-Path -Parent $STATE_FILE_PATH
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force $dir | Out-Null
  }

  $found = $false
  $lines = @()

  if (Test-Path $STATE_FILE_PATH) {
    foreach ($line in (Get-Content $STATE_FILE_PATH)) {
      if ($line -match "^${Key}=") {
        $lines += "${Key}=${Value}"
        $found = $true
      } else {
        $lines += $line
      }
    }
  }

  if (-not $found) {
    $lines += "${Key}=${Value}"
  }

  $tmpFile = "${STATE_FILE_PATH}.$([System.IO.Path]::GetRandomFileName())"
  $lines | Set-Content $tmpFile -Encoding Ascii
  Move-Item -Force $tmpFile $STATE_FILE_PATH
}

function global:Write-AllState {
  <#
  .SYNOPSIS
      Persist all RESOLVED_* globals to the state file.
  .DESCRIPTION
      Overwrites STATE_FILE_PATH with a complete snapshot of all resolved
      settings. Called after resolve_all_flags to persist choices.
  .NOTES
      Checks: None -- blindly writes whatever is in the RESOLVED_* variables.
      Gates: None
      Side effects: Overwrites STATE_FILE_PATH with a complete snapshot.
      Idempotency: Produces the same file given the same RESOLVED_* values.
  #>
  $dir = Split-Path -Parent $STATE_FILE_PATH
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force $dir | Out-Null
  }

  $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
  $content = @(
    "# dotfiles state file -- auto-generated by common.ps1"
    "# last written: $timestamp"
    "# Do not edit manually; values are overwritten on each bootstrap run."
    "PREFERRED_SHELL=$global:RESOLVED_SHELL"
    "DEVICE_PROFILE=$global:RESOLVED_PROFILE"
    "ENABLE_ZSCALER=$global:RESOLVED_ZSCALER"
    "ENABLE_MISE_TOOLS=$global:RESOLVED_MISE_TOOLS"
  )

  $tmpFile = "${STATE_FILE_PATH}.$([System.IO.Path]::GetRandomFileName())"
  $content | Set-Content $tmpFile -Encoding Ascii
  Move-Item -Force $tmpFile $STATE_FILE_PATH
}


# =============================================================================
# SECTION 6: RESOLUTION
# =============================================================================

function global:Resolve-Setting {
  <#
  .SYNOPSIS
      Walk the resolution chain for a single setting.
  .DESCRIPTION
      Checks each source in precedence order until a non-empty value is found:
      1. CLI flag value
      2. Environment variable
      3. State file value
      4. Device profile preset
      5. Hard-coded default
      Returns empty string if no value could be resolved.
  .NOTES
      Checks: Each source in precedence order until a non-empty value is found.
      Gates: None
      Side effects: None
      Idempotency: Deterministic given the same inputs.
  #>
  param(
    [string]$CliVal       = '',
    [string]$EnvVal       = '',
    [string]$StateVal     = '',
    [string]$ProfileDefault = '',
    [string]$HardDefault  = ''
  )

  if ($CliVal)        { return $CliVal }
  if ($EnvVal)        { return $EnvVal }
  if ($StateVal)      { return $StateVal }
  if ($ProfileDefault) { return $ProfileDefault }
  if ($HardDefault)   { return $HardDefault }
  return ''
}

function global:Resolve-ShellPreference {
  <#
  .SYNOPSIS
      Resolve PREFERRED_SHELL with constrained choices.
  .DESCRIPTION
      Walks CLI -> env -> state and returns "pwsh" as the only valid Windows
      shell. Falls back to "pwsh" since that is the only supported shell on
      Windows.
  .NOTES
      Checks: Walks the resolution chain.
      Gates: None
      Side effects: None
      Idempotency: Deterministic given the same inputs.
  #>
  param([string]$CliVal = '')

  $envVal   = $env:PREFERRED_SHELL
  $stateVal = Get-StateValue -Key 'PREFERRED_SHELL'

  if ($CliVal)   { return $CliVal }
  if ($envVal)   { return $envVal }
  if ($stateVal) { return $stateVal }

  # Windows default
  return 'pwsh'
}

function global:Resolve-DeviceProfile {
  <#
  .SYNOPSIS
      Resolve DEVICE_PROFILE with constrained choices.
  .DESCRIPTION
      Walks CLI -> env -> state and returns one of "work", "home", or "minimal".
      Falls back to "minimal" as the hard default.
  .NOTES
      Checks: Walks the resolution chain with "work", "home", "minimal" as
              the only valid options.
      Gates: None
      Side effects: None
      Idempotency: Deterministic given the same inputs.
  #>
  param([string]$CliVal = '')

  $envVal   = $env:DEVICE_PROFILE
  $stateVal = Get-StateValue -Key 'DEVICE_PROFILE'

  $resolved = ''
  if ($CliVal)   { $resolved = $CliVal }
  elseif ($envVal)   { $resolved = $envVal }
  elseif ($stateVal) { $resolved = $stateVal }

  if (-not $resolved) { $resolved = 'minimal' }

  if ($resolved -notin @('work', 'home', 'minimal')) {
    Write-Fatal "DEVICE_PROFILE must be 'work', 'home', or 'minimal', got: $resolved"
  }

  return $resolved
}

function global:Get-ProfileDefault {
  <#
  .SYNOPSIS
      Look up a preset value for a given profile and flag.
  .DESCRIPTION
      Returns the default value for a feature flag based on the device profile.
      Profile presets encode the default boolean flags for each device role.
  .NOTES
      Checks: None
      Gates: None
      Side effects: None
      Idempotency: Pure lookup function.
  #>
  param(
    [Parameter(Mandatory)][string]$Profile_,
    [Parameter(Mandatory)][string]$FlagKey
  )

  $defaults = @{
    'work:ENABLE_ZSCALER'     = 'auto'
    'work:ENABLE_MISE_TOOLS'  = 'true'
    'home:ENABLE_ZSCALER'     = 'false'
    'home:ENABLE_MISE_TOOLS'  = 'true'
    'minimal:ENABLE_ZSCALER'     = 'false'
    'minimal:ENABLE_MISE_TOOLS'  = 'true'
  }

  $key = "${Profile_}:${FlagKey}"
  if ($defaults.ContainsKey($key)) {
    return $defaults[$key]
  }
  return ''
}

function global:Resolve-AllFlags {
  <#
  .SYNOPSIS
      Resolve every configurable flag using the full precedence chain.
  .DESCRIPTION
      Resolves PREFERRED_SHELL, DEVICE_PROFILE, and all ENABLE_* flags by
      walking CLI -> env -> state -> profile -> default for each setting.
      Populates RESOLVED_* global variables and persists to state file.
  .NOTES
      Checks: Resolves all flags through the full chain.
      Gates: None directly, delegates to resolution functions.
      Side effects: Populates RESOLVED_* globals. Calls Write-AllState.
      Idempotency: Safe to call multiple times; overwrites globals and state.
  #>
  param(
    [string]$CliShell   = '',
    [string]$CliProfile = '',
    [hashtable]$EnableFlags  = @{},
    [hashtable]$DisableFlags = @{}
  )

  # Read current state file
  $state = Read-State

  # Resolve profile first (other flags depend on it)
  $global:RESOLVED_PROFILE = Resolve-DeviceProfile -CliVal $CliProfile

  # Resolve shell preference
  $global:RESOLVED_SHELL = Resolve-ShellPreference -CliVal $CliShell

  # Build CLI values from enable/disable flags
  $cliZscaler = ''
  if ($EnableFlags.ContainsKey('ZSCALER'))  { $cliZscaler = 'true' }
  if ($DisableFlags.ContainsKey('ZSCALER')) { $cliZscaler = 'false' }

  $cliMiseTools = ''
  if ($EnableFlags.ContainsKey('MISE_TOOLS'))  { $cliMiseTools = 'true' }
  if ($DisableFlags.ContainsKey('MISE_TOOLS')) { $cliMiseTools = 'false' }

  # Resolve feature flags
  $global:RESOLVED_ZSCALER = Resolve-Setting `
    -CliVal $cliZscaler `
    -EnvVal ($env:ENABLE_ZSCALER) `
    -StateVal ($state['ENABLE_ZSCALER']) `
    -ProfileDefault (Get-ProfileDefault -Profile_ $global:RESOLVED_PROFILE -FlagKey 'ENABLE_ZSCALER') `
    -HardDefault 'false'

  $global:RESOLVED_MISE_TOOLS = Resolve-Setting `
    -CliVal $cliMiseTools `
    -EnvVal ($env:ENABLE_MISE_TOOLS) `
    -StateVal ($state['ENABLE_MISE_TOOLS']) `
    -ProfileDefault (Get-ProfileDefault -Profile_ $global:RESOLVED_PROFILE -FlagKey 'ENABLE_MISE_TOOLS') `
    -HardDefault 'true'

  # Persist all resolved values
  Write-AllState
}

function global:Export-BrewEnvVars {
  <#
  .SYNOPSIS
      No-op on Windows -- included for API parity with common.zsh.
  .DESCRIPTION
      On macOS this maps resolved flags to Homebrew env vars. Windows uses
      Scoop and does not need equivalent env vars, so this is a no-op stub.
  .NOTES
      Checks: None
      Gates: None
      Side effects: None
      Idempotency: Always safe.
  #>
}


# =============================================================================
# SECTION 7: MANAGED BLOCK WRITER
# =============================================================================

function global:Write-ManagedBlock {
  <#
  .SYNOPSIS
      Idempotent marker-delimited block writer.
  .DESCRIPTION
      Writes a block of content between begin/end markers into a target file.
      If the markers are absent, the block is appended. If the markers are
      present, the content between them (inclusive) is replaced. Creates parent
      directories if they do not exist.
  .NOTES
      Checks: Whether the target file already contains the begin marker.
      Gates: None
      Side effects: Creates or modifies the target file. Creates parent dirs
                   if they do not exist.
      Idempotency: If the block content is identical, the file is rewritten
                   with the same content. If markers are absent, the block
                   is appended.
  #>
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string]$BeginMarker,
    [Parameter(Mandatory)][string]$EndMarker,
    [Parameter(Mandatory)][string]$BlockContent
  )

  # Dry-run gate: log what would happen without writing
  if (Test-DryRun) {
    if (-not (Test-Path $FilePath)) {
      Write-DryRunLog "create file and write managed block to $FilePath"
    } elseif (Get-Content $FilePath -ErrorAction SilentlyContinue | Where-Object { $_ -like "*$BeginMarker*" }) {
      Write-DryRunLog "replace managed block in $FilePath"
    } else {
      Write-DryRunLog "append managed block to $FilePath"
    }
    return
  }

  # Ensure parent directory and file exist
  $dir = Split-Path -Parent $FilePath
  if (-not (Test-Path $dir)) {
    New-Item -ItemType Directory -Force $dir | Out-Null
  }
  if (-not (Test-Path $FilePath)) {
    New-Item -ItemType File -Force $FilePath | Out-Null
  }

  $currentContent = Get-Content $FilePath -ErrorAction SilentlyContinue

  # Fast path: markers not present -- just append
  if (-not ($currentContent | Where-Object { $_ -like "*$BeginMarker*" })) {
    Add-Content -Path $FilePath -Value "`n$BlockContent" -Encoding Ascii
    return
  }

  # Slow path: replace the existing block
  $newLines = @()
  $insideBlock = $false

  foreach ($line in $currentContent) {
    if ($line -like "*$BeginMarker*") {
      # Write the new block content (which includes markers)
      $newLines += $BlockContent -split "`n"
      $insideBlock = $true
      continue
    }

    if ($insideBlock) {
      if ($line -like "*$EndMarker*") {
        $insideBlock = $false
      }
      continue
    }

    $newLines += $line
  }

  $newLines | Set-Content $FilePath -Encoding Ascii
}
