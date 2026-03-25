# macOS foundation bootstrap

This runbook gets a bare macOS machine to a stable engineering foundation using
Homebrew, `mise`, `zsh`, and Google Chrome-driven Zscaler detection. The result
is a machine that can install packages, activate shell tooling, resolve runtime
shims, trust corporate TLS interception when present, and be safely maintained
later by the same bootstrap flow.

The approach is deliberately conservative for customer environments. It avoids
personal dotfiles, keeps Fish in the personal layer, and treats the foundation
bootstrap as a reusable base rather than a full workstation customisation.

It assumes:
- macOS with Terminal or another shell-capable terminal emulator
- `zsh` is the foundation shell target
- the target is a reusable foundation, not personal dotfiles yet

## Quick start

Use this document in order. The high-level flow is:

1. Install Homebrew.
2. Install the minimum foundation packages.
3. Create or repair the managed `zsh` profile block.
4. Create the seed `mise` configuration.
5. Detect active Zscaler trust in Chrome and repair TLS trust before full
   `mise` reconciliation.
6. Install and validate the full foundation toolset.

If you are behind Zscaler, do not skip the trust phase. `mise install`, npm,
and Python package operations can fail until the CA bundle is in place.

## What this bootstrap delivers

By the end of the runbook, the machine should have:
- Homebrew installed and healthy
- a managed `zsh` bootstrap block for `brew`, `mise`, and `zoxide`
- `mise` installed, activated, and able to resolve foundation runtimes
- a reusable CA bundle for npm, Python, Git, curl, and related tools when
  Zscaler is active
- practical validation proving the machine is usable, not just partially
  installed

## Foundation package list

Install with Homebrew:
- `gum`
- `git`
- `gh`
- `jq`
- `yq`
- `fzf`
- `fd`
- `ripgrep`
- `zoxide`
- `lazygit`
- `mise`
- `openssl`

Optional macOS foundation packages:
- `neovim`
- `gnupg`

## Phase 1: install Homebrew

If Homebrew is missing, install it:

```zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Load the environment into the current shell:

```zsh
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
```

Verify:

```zsh
brew --version
```

## Phase 2: install foundation packages

Install the minimum package-manager-managed toolset:

```zsh
brew install gum git gh jq yq fzf fd ripgrep zoxide lazygit mise openssl
```

Verify:

```zsh
git --version
mise --version
gum --version
openssl version
```

## Phase 3: create the managed `zsh` bootstrap block

Ensure `~/.zshrc` exists:

```zsh
touch ~/.zshrc
```

Write or update the managed bootstrap block:

```zsh
cat <<'EOF' > /tmp/foundation-zsh-block
# >>> foundation-bootstrap >>>
if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv)"
fi
export MISE_ZSH_AUTO_START=1
eval "$(mise activate zsh)"
eval "$(zoxide init zsh)"
# <<< foundation-bootstrap <<<
EOF
```

Then merge that block into `~/.zshrc` using your preferred editing approach or
the script implementation.

Reload the shell:

```zsh
source ~/.zshrc
```

Verify:

```zsh
command -v mise
command -v zoxide
```

## Phase 4: create the seed `mise` config

Create the directory:

```zsh
mkdir -p ~/.config/mise
```

Write the seed config:

```zsh
cat <<'EOF' > ~/.config/mise/config.toml
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
EOF
```

Verify:

```zsh
cat ~/.config/mise/config.toml
```

## Phase 5: detect Zscaler and bootstrap trust

Use Google Chrome as the decision point:

1. Open Chrome.
2. Browse to `https://registry.npmjs.org`.
3. Inspect the certificate chain.
4. If the chain shows Zscaler, continue with this section.
5. If not, skip to Phase 6.

Create the directory:

```zsh
mkdir -p ~/certs
mkdir -p ~/.config/mise
```

Fetch the active certificate chain:

```zsh
openssl s_client -showcerts -connect registry.npmjs.org:443 -servername registry.npmjs.org < /dev/null 2>/dev/null \
  | awk '/-----BEGIN CERTIFICATE-----/{p=1}; p; /-----END CERTIFICATE-----/{p=0}' \
  > ~/certs/zscaler_chain.pem
```

Validate the issuer:

```zsh
openssl x509 -in ~/certs/zscaler_chain.pem -noout -issuer
```

The issuer must show Zscaler. If it does not, stop and inspect the network
path before continuing.

Bootstrap Python just enough to locate a certifi bundle:

```zsh
mise install python@latest
source ~/.zshrc
python3 -m ensurepip --upgrade
CERTIFI_PATH=$(python3 -c 'import pip._vendor.certifi as c; print(c.where())')
```

Build the merged CA bundle:

```zsh
cat "$CERTIFI_PATH" ~/certs/zscaler_chain.pem > ~/certs/golden_pem.pem
```

Write the `mise` environment file:

```zsh
cat <<EOF > ~/.config/mise/.env
SSL_CERT_FILE="$HOME/certs/golden_pem.pem"
SSL_CERT_DIR="$HOME/certs"
CERT_PATH="$HOME/certs/golden_pem.pem"
CERT_DIR="$HOME/certs"
REQUESTS_CA_BUNDLE="$HOME/certs/golden_pem.pem"
CURL_CA_BUNDLE="$HOME/certs/golden_pem.pem"
NODE_EXTRA_CA_CERTS="$HOME/certs/golden_pem.pem"
GRPC_DEFAULT_SSL_ROOTS_FILE_PATH="$HOME/certs/golden_pem.pem"
GIT_SSL_CAINFO="$HOME/certs/golden_pem.pem"
CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE="$HOME/certs/golden_pem.pem"
PIP_CERT="$HOME/certs/golden_pem.pem"
NPM_CONFIG_CAFILE="$HOME/certs/golden_pem.pem"
npm_config_cafile="$HOME/certs/golden_pem.pem"
AWS_CA_BUNDLE="$HOME/certs/golden_pem.pem"
EOF
```

Reload the shell:

```zsh
source ~/.zshrc
```

Configure Git and Python explicitly:

```zsh
git config --global http.sslcainfo "$HOME/certs/golden_pem.pem"
python3 -m pip config set global.cert "$HOME/certs/golden_pem.pem"
```

If you use gcloud:

```zsh
gcloud config set core/custom_ca_certs_file "$HOME/certs/golden_pem.pem"
```

## Phase 6: validate cert-sensitive tooling before full `mise install`

Run:

```zsh
node -p 'process.env.NODE_EXTRA_CA_CERTS'
npm ping
python3 -m pip --version
git config --global --get http.sslcainfo
```

If these fail:
- confirm Chrome still shows Zscaler
- confirm `~/certs/golden_pem.pem` exists
- confirm the fetched issuer is Zscaler
- confirm the shell reloaded the `.env`-driven variables

## Phase 7: run full `mise` reconciliation

Install the full foundation toolset:

```zsh
mise install
```

Verify:

```zsh
mise current
node --version
python3 --version
python3 -m pip --version
go version
terraform version
gcloud version
```

## Phase 8: final validation

Package manager and shell:

```zsh
brew --version
echo $SHELL
command -v brew
command -v mise
command -v zoxide
```

Foundation tools:

```zsh
git --version
gh --version
jq --version
yq --version
fzf --version
fd --version
rg --version
zoxide --version
lazygit --version
mise --version
gum --version
openssl version
```

`mise` and runtimes:

```zsh
mise env
mise current
node --version
python3 --version
python3 -m pip --version
go version
terraform version
```

TLS-sensitive checks:

```zsh
node -p 'process.env.NODE_EXTRA_CA_CERTS'
npm ping
git config --global --get http.sslcainfo
```

If Zscaler is active, also verify:

```zsh
ls -l ~/certs/golden_pem.pem
cat ~/.config/mise/.env
```

## Important lessons

- Homebrew should install without issue in most environments, but Zscaler trust
  must be repaired before network-heavy `mise` reconciliation if Chrome shows an
  active Zscaler chain.
- The foundation layer owns a managed `zsh` bootstrap block only. Fish remains a
  personal-layer concern.
- The seed `mise` config should remain minimal and customer-safe.
- The TLS bundle must be reusable across npm, Python, Git, curl, and optionally
  `gcloud`.
