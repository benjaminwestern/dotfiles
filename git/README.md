# Machine-Local Git Configuration

The tracked `config.shared` includes `~/.config/git/local.inc` when it exists.
Keep employer, organization, and repository-specific identities out of this
repository by declaring them in that machine-local file.

For a directory-scoped identity, create `~/.config/git/local.inc` with an
include whose `gitdir` ends in `/` so it applies recursively:

```gitconfig
[includeIf "gitdir:~/code/example-repos/"]
	path = ~/.config/git/example.inc
```

Then create the referenced file:

```gitconfig
[user]
	email = developer@example.com
[credential]
	helper = /usr/lib/git-core/git-credential-libsecret
```

On Linux, the declared `gnome-keyring` package, greetd PAM hooks, and Hyprland
autostart provide encrypted Secret Service storage for `git-credential-libsecret`.
Run an HTTPS `git fetch` or `git push` once and enter the account username and a
personal access token. Git stores the credential in GNOME Keyring, not in either
configuration file, and reuses it for repositories on the same host.

Automatic keyring unlock requires a password-based greetd login and a login
keyring using the same password. Fingerprint-only or automatic login sessions
may still require an explicit keyring unlock.

Verify the effective settings from a repository in the scoped directory:

```bash
git config --show-origin --get user.email
git config --show-origin --get-all credential.helper
GIT_TERMINAL_PROMPT=0 git ls-remote origin HEAD
```
