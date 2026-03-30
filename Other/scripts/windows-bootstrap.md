# Windows bootstrap

This runbook describes the current Windows bootstrap architecture as it exists
in this repository. It covers the public entrypoint, the repo-local first-run
wrapper, the PowerShell 5 to PowerShell 7 bridge, signing behaviour, staged
Zscaler trust, and the local repair commands used after the machine is online.

The goal is a repeatable Windows foundation that works on fresh machines,
including machines that start in Windows PowerShell 5.x or under an effective
`AllSigned` policy.

## Quick start

Use the public loader for normal setup, ensure, update, and audit runs. It
reuses `~\.dotfiles` when present, clones it when missing, and can fall back to
a temporary GitHub archive when `git` is unavailable.

```powershell
# Remote bootstrap
curl.exe -fsSL -o "$env:TEMP\install.cmd" "https://raw.githubusercontent.com/benjaminwestern/dotfiles/main/install.cmd"
& "$env:TEMP\install.cmd" setup --profile work --personal

# Local checkout bootstrap
git clone https://github.com/benjaminwestern/dotfiles $HOME\.dotfiles
& "$HOME\.dotfiles\install.cmd" setup --profile work --personal

# Read-only audit plus state discovery
& "$HOME\.dotfiles\install.cmd" audit --populate-state

# Local signing repair
& "$HOME\.dotfiles\Other\scripts\resign-windows.cmd"
```

<!-- prettier-ignore -->
> [!IMPORTANT]
> For a first run, use `install.cmd` or
> `Other\scripts\bootstrap-windows.cmd`. Do not start with
> `pwsh -File foundation-windows.ps1` on a fresh machine if the local `.ps1`
> files may still be unsigned.

## Entry points

The Windows bootstrap has four user-facing entrypoints, each with a different
responsibility.

- `install.cmd` is the public loader. It resolves the repo checkout, parses the
  public flags, and delegates into the repo-local bootstrap.
- `Other\scripts\bootstrap-windows.cmd` is the first repo-local entrypoint. It
  makes first-run local PowerShell execution safe by creating
  `LocalScoopSigner`, signing the local Windows bootstrap tree, and then
  launching the selected `.ps1` target with `powershell.exe -File`.
- `Other\scripts\foundation-windows.ps1` is the Windows foundation
  orchestrator. It owns Scoop, the Windows baseline package set, `mise`,
  managed PowerShell profile repair, Windows Terminal default profile repair,
  Zscaler trust, and validation.
- `Other\scripts\audit-windows.ps1` is the read-only machine audit. It reports
  the Windows foundation, shell, config, signing, and Zscaler state. Use
  `-PopulateState` when you want it to write the detected baseline into
  `~/.config/dotfiles/state.env`.

`Other\scripts\resign-windows.cmd` is the local repair entrypoint for signing
drift. It is not a public remote loader. It assumes the repo is already on
disk.

## First-run execution flow

The Windows first-run chain deliberately separates responsibilities so the
operator does not have to solve PowerShell policy and versioning problems by
hand.

1. `install.cmd` finds or downloads a working checkout and delegates to
   `Other\scripts\bootstrap-windows.cmd`.
2. `bootstrap-windows.cmd` normalises the repo-local script path, ensures the
   `LocalScoopSigner` certificate exists, signs the local Windows `.ps1`
   bootstrap files, and launches the selected target with `powershell.exe`.
3. `foundation-windows.ps1` and `audit-windows.ps1` immediately load
   `lib/windows-precursor.ps1`.
4. If the current host is already PowerShell 7 or later, the precursor returns
   immediately.
5. If the current host is still Windows PowerShell 5.x, the precursor ensures
   Scoop exists, ensures `pwsh` exists, signs the local script tree, and
   re-runs the same target under `pwsh -NoLogo -NoProfile -File ...`.
6. The real foundation or audit logic then continues in PowerShell 7.

That architecture is what makes the Windows path usable on fresh machines. The
public loader resolves the repo, the CMD wrapper handles unsigned local
scripts, and the precursor handles the PowerShell 5 bootstrap gap.

## Foundation behaviour

Once the target is running in `pwsh`, the Windows foundation proceeds in a
fixed order:

1. Ensure Scoop exists and the required buckets are available.
2. Ensure the Windows foundation package set is present.
3. Ensure `mise` is installed.
4. Write or repair the managed PowerShell profile block.
5. Activate `mise` in the current shell with `mise activate pwsh --shims`.
6. Remove stale `AppData\Local\mise\installs\...` PATH entries from the
   current session before activation.
7. Set Windows Terminal's default profile to `pwsh`.
8. Create or update the managed `mise` seed config.
9. Configure stage-1 Zscaler trust before `mise install`.
10. Run `mise install`.
11. Refresh TLS trust after `mise install`, using Python `certifi` when Python
    is now available.
12. Validate the resulting machine state.
13. Optionally hand off to the personal layer when `--personal` is set.

The current Windows foundation package list is:

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
- `charm-gum`
- `vscode`
- `openssl`
- `pwsh`

`mise` is managed separately on purpose. Under `AllSigned`, it must be
installed via Scoop so its PowerShell wrappers can be signed. Under
`RemoteSigned`, the foundation still prefers Scoop but can fall back to the
shell installer.

## Signing behaviour

The Windows scripts support both `AllSigned` and `RemoteSigned`.

- Under `AllSigned`, signing is required. The bootstrap ensures
  `LocalScoopSigner` exists and signs the local Windows bootstrap scripts, Scoop
  scripts, `mise` scripts, repo-local dotfiles scripts, and the managed
  PowerShell profile where required.
- Under `RemoteSigned`, unsigned local scripts are acceptable. The bootstrap
  still prepares the local script tree for first-run safety, but the steady
  state does not require every local `.ps1` file to stay signed. The audit
  reports unsigned dotfiles scripts or an unsigned profile as informational
  under `RemoteSigned`.

For manual repair after updates or local edits, use:

```powershell
.\Other\scripts\resign-windows.cmd
.\Other\scripts\resign-windows.cmd -DryRun
```

That repair flow re-signs Scoop scripts, `mise` scripts, repo-local Windows
bootstrap scripts, and the current PowerShell profile.

## Zscaler and TLS trust

The Windows foundation performs staged Zscaler trust repair because `mise
install` and the tools it installs may need working TLS before Python is
available.

**Stage 1 runs before `mise install`**

- Detect active Zscaler using live TLS probes and Windows certificate store
  evidence.
- Build `~/certs/zscaler_ca_bundle.pem`.
- Build `~/certs/golden_pem.pem` from the base OpenSSL CA bundle plus the
  detected Zscaler chain.
- Write `~/.config/mise/.env`.
- Export the relevant user and process TLS environment variables.
- Configure Git, `pip`, and `gcloud` when those clients are available.

**Stage 2 runs after `mise install`**

- Rebuild `golden_pem.pem` using Python `certifi` when Python is now available.
- Re-run TLS client configuration so newly installed tools, including `gcloud`,
  pick up the final trust bundle on the first bootstrap run.

The audit reports both the raw stored Zscaler state and the effective resolved
value. If live TLS detection proves active interception, the audit and the
resolution engine can override stale non-explicit `false` state.

## Managed outputs

The Windows foundation writes and maintains a small set of managed files and
settings.

- `~/.config/dotfiles/state.env` stores resolved preferences and discovered
  state for later runs.
- The PowerShell profile receives a managed activation block that loads
  `lib/common.ps1`, strips stale `mise` install paths, activates `mise` via
  `pwsh --shims`, activates `zoxide`, and dot-sources the signing helpers.
- `~/.config/mise/config.toml` receives the managed `mise` seed block unless
  the file is user-owned and takeover was not requested.
- `~/.config/mise/.env` receives the managed Zscaler environment block.
- `~/certs/zscaler_ca_bundle.pem` and `~/certs/golden_pem.pem` hold the
  generated trust bundles.
- Windows Terminal `settings.json` is updated so the default profile resolves
  to `pwsh`.

When you need to replace an existing user-owned `~/.config/mise/config.toml`
with the managed seed, run the foundation directly with
`-TakeoverMiseConfig`. That advanced option is intentionally repo-local and is
not currently exposed through `install.cmd`.

## Audit and validation

The Windows audit can be entered through the public loader or the repo-local
wrapper.

```powershell
& "$HOME\.dotfiles\install.cmd" audit
.\Other\scripts\bootstrap-windows.cmd audit -Section signing
.\Other\scripts\bootstrap-windows.cmd audit -Json
.\Other\scripts\bootstrap-windows.cmd audit -PopulateState
```

The audit covers:

- foundation package coverage
- `mise` install method and activation state
- PowerShell version and effective execution policy
- managed profile block presence and signature state
- Windows Terminal default profile state
- Scoop, `mise`, dotfiles, and profile signing posture
- live Zscaler detection, cert-store evidence, CA bundles, `mise` `.env`, and
  TLS client configuration

On a healthy machine, you should expect the foundation package count to be
`14/14`, `pwsh` to be available, Windows Terminal to default to `pwsh`, and
Zscaler trust to validate when your network requires it.

## Advanced direct commands

Use the public loaders for standard operations. Use these direct commands only
when you need explicit control of the repo-local scripts.

```powershell
# First-run-safe repo-local flows
.\Other\scripts\bootstrap-windows.cmd foundation -Mode ensure -DryRun
.\Other\scripts\bootstrap-windows.cmd personal
.\Other\scripts\bootstrap-windows.cmd resign

# Advanced foundation recovery
pwsh -NoLogo -NoProfile -File .\Other\scripts\foundation-windows.ps1 -Mode ensure -TakeoverMiseConfig
```

The repo-local wrapper remains the safer option whenever unsigned local scripts
or Windows PowerShell 5 are still part of the problem.
