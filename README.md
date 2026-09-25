# nix config

Personal Nix configuration for three machines:

| host      | OS                     | managed by                          | scope         |
| --------- | ---------------------- | ----------------------------------- | ------------- |
| `mahi`    | macOS (aarch64-darwin) | nix-darwin + home-manager module    | system + home |
| `maui`    | Debian 13 trixie (x86_64-linux) | standalone home-manager    | `$HOME` only  |
| `noble2`  | VPS (x86_64-linux), root account | standalone home-manager | `$HOME` only  |

Debian/Ubuntu aren't NixOS, so there is no system-level Nix config for `maui`/`noble2` — packages
like `zsh`, `curl` and `build-essential` stay apt's job.

## Layout

```
flake.nix                      hosts attrset + the two outputs
justfile                       task runner; recipes dispatch on host OS
configs/                       raw dotfiles, symlinked in via home.file
modules/
├── common/home.nix            cross-platform home config (both hosts)
├── darwin/
│   ├── configuration.nix      nix-darwin system config (homebrew, system.defaults, aerospace, ...)
│   ├── home-manager.nix       wires home-manager into nix-darwin
│   ├── home.nix               macOS-only home config
│   ├── steam.nix              DMG-wrapping derivation
│   └── protonvpn.nix          DMG-wrapping derivation (currently unused)
└── linux/
    ├── home.nix               Linux-only home config (maui + noble2)
    ├── tailscale.nix          tailscaled as a system unit
    ├── tls-cert.nix           self-signed cert for services that predate `tailscale serve`
    ├── claudebox.nix          `claudebox`: Claude Code under systemd sandboxing
    ├── services-maui.nix      imports everything below; maui only
    ├── vaultwarden.nix        password vault          :8222
    ├── blocky.nix             DNS sinkhole for the tailnet (system unit, :53)
    ├── ntfy.nix               push notifications      :8443
    ├── paperless.nix          document archive        :8444
    ├── couchdb.nix            Obsidian LiveSync       :8446
    ├── openclaw.nix           WhatsApp agent          :8447 (system unit, own user)
    ├── vault-sync.nix         vault git + inbox timers
    ├── digest.nix             07:00 digest to the phone
    └── lib/                   tailnet.nix, system-unit.nix, vault.nix
```

Adding a package: cross-platform → `modules/common/home.nix`; mac-only → `modules/darwin/home.nix`;
Debian-only → `modules/linux/home.nix`.

## just

`just` works the same on both hosts — every recipe picks `darwin-rebuild` or `home-manager`
based on `uname`, and derives the flake target from `hostname -s`.

```
just              # list recipes
just switch       # apply this host's config
just dry          # build + diff against what's live, without applying
just plan         # resolve the build plan; builds and downloads nothing
just build        # build only, leaves ./result
just check        # evaluate all hosts (catches module errors with no builder needed)
just dns-info     # the address to paste into Tailscale admin → DNS (maui)
just generations  # list generations
just rollback     # back to the previous generation
just update       # update all flake inputs
just update-input claude-code-nix
just gc           # drop old generations + collect garbage (destructive)
```

## mahi (macOS)

```bash
just switch
# equivalently:
sudo darwin-rebuild switch --flake ~/.config/nix-darwin-config#mahi
# or the shell alias:
rebuild
```

## maui (Debian 13)

One-time setup (Nix is assumed installed with flakes enabled — check with
`nix config show experimental-features`):

```bash
sudo apt install -y zsh git curl
chsh -s /usr/bin/zsh                     # zsh from apt, NOT nix: a /nix/store login shell
                                          # breaks the next time the GC runs
git clone git@github.com:saiputravu/nix-macos.git ~/.config/nix-config
cd ~/.config/nix-config
nix run nixpkgs#just -- bootstrap-linux     # or the raw command below
nix run home-manager/master -- switch -b backup --flake ~/.config/nix-config#sai@maui
```

After the first activation `just`, `home-manager` and `claude` are all on `$PATH`:

```bash
just switch
# equivalently:
home-manager switch -b backup --flake ~/.config/nix-config#sai@maui
# or the shell alias:
rebuild
```

`zsh4humans` bootstraps itself on first interactive shell via the managed `~/.zshenv`.

### Services on maui

maui is the always-on box, so it hosts everything in `modules/linux/services-maui.nix`. The rule:
a `systemd --user` service unless the thing genuinely needs root or a privileged port, in which
case `lib/system-unit.nix` installs a root-owned unit during activation (one sudo prompt per
switch). Nothing writes this host's tailnet IP or MagicDNS name into a module — `lib/tailnet.nix`
resolves both at start time, so the config replicates onto another box unedited.

| service | reachable at | notes |
| --- | --- | --- |
| vaultwarden | `:8222` | self-signed cert from `just tls-cert` |
| ntfy | `:8443` | `notify "..."` is the CLI every timer alerts through |
| paperless | `:8444` | archive of record for admin documents |
| couchdb | `:8446` | Obsidian LiveSync backend |
| openclaw | `:8447` | WhatsApp agent; own system user, `ProtectHome` |
| blocky | DNS `:53` | tailnet-wide sinkhole, DoH upstreams; API on `127.0.0.1:4000` |

Everything except vaultwarden is published with `tailscale serve`, so the ports above are on this
host's tailnet name over HTTPS with a cert that renews itself. Timers: `vault-git` (hourly commit
+ push), `vault-ingest` (06:30/18:30), `morning-digest` (07:00).

## Setting the services up

One-time steps, none of them expressible in Nix — they involve a browser, a phone, or a secret
that must not land in the store. `$FQDN` below is this host's tailnet name; `just dns-info` prints
it alongside the address blocky answers on.

**Prerequisite for every iOS step:** the Tailscale app installed, logged into the same tailnet,
and *connected*. Nothing here is exposed to the public internet, so an iPhone off the tailnet
reaches none of it — including over cellular, where Tailscale is exactly what makes it work.

### 0. blocky — tailnet-wide DNS

Nothing to do on maui; it is already answering. In the Tailscale admin console → **DNS**:

- **Nameservers** → add the address from `just dns-info`
- add `9.9.9.9` as a second nameserver — if maui reboots, this is what stops DNS going down for
  every device on the tailnet
- turn **Override local DNS** on

Verify from the iPhone on cellular, not just wifi: ads should be gone in Safari.

### 1. ntfy — notifications

On maui:

```bash
ntfy-admin user add --role=admin sai     # prompts for a password; remember it, iOS needs it
ntfy-admin token add sai                 # prints tk_...
install -m 600 /dev/null ~/.config/ntfy/token
printf 'tk_...\n' > ~/.config/ntfy/token
notify "hello from maui"                 # should arrive on the phone once the app is set up
```

An admin user has access to every topic, so no `ntfy-admin access` grant is needed. Use
`ntfy-admin`, not `ntfy`: the server-side subcommands look for `/etc/ntfy/server.yml`, which does
not exist here.

On iOS — the **ntfy** app:

1. Settings → **Default server** → `https://$FQDN:8443`
2. Settings → **Manage users** → add `sai` with the password above
3. Subscribe to the topic **`alerts`**

Every timer on maui reports failures through this, and the 07:00 digest arrives on it.

### 2. vaultwarden — passwords

Already configured on maui; nothing to run. On iOS — the **Bitwarden** app:

1. On the login screen, tap the region selector → **Self-hosted**
2. **Server URL** → `https://$FQDN:8222`
3. Create the account, then turn signups off in `~/.config/vaultwarden/env`
   (`SIGNUPS_ALLOWED=false`) and `systemctl --user restart vaultwarden`

The cert is a real Let's Encrypt one issued to the tailnet name, so the app accepts it without
any profile fiddling.

### 3. paperless — documents

On maui:

```bash
paperless-manage createsuperuser
```

Then open `https://$FQDN:8444`, log in, and drop a PDF into `/srv/storage/paperless/consume/` —
it should appear in the UI within a minute.

On iOS — **Swift Paperless**:

1. Add server `https://$FQDN:8444`
2. Log in with the superuser; the app exchanges that for an API token itself

Scope reminder: paperless is for admin documents — bills, letters, statements. Study capture stays
in the vault's `_inbox/`. A file lives in exactly one of the two.

### 4. couchdb + LiveSync — the Obsidian vault

On maui, create the database the plugin replicates into:

```bash
PW=$(cat ~/.config/couchdb/admin-password)
curl -X PUT -u "sai:$PW" http://127.0.0.1:5984/obsidian
```

Then in Obsidian **on maui**, install the **Self-hosted LiveSync** community plugin and point it at:

| field | value |
| --- | --- |
| URI | `https://$FQDN:8446` |
| Username | `sai` |
| Password | contents of `~/.config/couchdb/admin-password` |
| Database | `obsidian` |

Set the ignore list to derived state only — `.git/`, `.index/notes.db*`, `.uv-cache/`,
`.npm-tools/`, `.trash/`, `Plan/.mdbase/`, `__pycache__/`, `.obsidian/workspace*.json`,
`.obsidian/cache`. Do **not** reuse the vault's `.gitignore`: it excludes `_inbox/*`, which is
precisely the iPad capture live sync exists to move.

Then **Copy setup URI** from the plugin, and on each other device (iPhone, iPad, mahi) install the
same plugin and **Open setup URI**.

Finally, remove the **obsidian-git** plugin from every device. `vault-git.timer` on maui is the
only writer of git history now — that split is what prevents the stale-phone-reverts-desktop
failure the vault's `.gitignore` documents.

### 5. gcalcli — the morning digest's calendar half

In the Google Cloud Console: create a project, enable the **Google Calendar API**, then create an
OAuth client of type **Desktop app**. Keep the client ID and secret to hand. On maui:

```bash
gcalcli init      # paste the client ID and secret; a browser opens for consent
morning-digest    # the calendar sections should now fill in
```

maui has a desktop session, so the browser flow works locally. Until this is done the digest still
arrives — the calendar sections just say so in one line.

### 6. openclaw — the WhatsApp agent

Give it a model first. An API key is the most predictable option for an always-on daemon:

```bash
sudo sh -c 'printf "ANTHROPIC_API_KEY=sk-ant-...\n" >> /var/lib/openclaw/.env'
sudo systemctl restart openclaw
openclawctl models status
```

Or reuse a Claude Code login — note this logs *the openclaw user* in, not you:

```bash
openclaw-as claude auth login
openclawctl models auth login --provider anthropic --method cli --set-default
```

Then link WhatsApp. Use a spare number if you have one; this is an unofficial WhatsApp Web client
holding a real session:

```bash
openclawctl channels login --channel whatsapp     # prints a QR in the terminal
```

On iOS — **WhatsApp** → Settings → **Linked Devices** → **Link a Device** → scan that QR.

Finally allow your own number to talk to it. It starts with an empty allowlist, so until this is
done nobody can reach the agent at all:

```bash
sudo nano /var/lib/openclaw/openclaw.json     # channels.whatsapp.allowFrom: ["+44..."]
sudo systemctl restart openclaw
```

Message that number from your phone to test. The Control UI is at `https://$FQDN:8447`; the token
it asks for is in `/var/lib/openclaw/.env`.

Two boundaries worth remembering, both deliberate: the agent can read, edit and commit in
`/srv/storage/repos` but cannot push (the key is in your home directory, which `ProtectHome` hides
from it), and ntfy stays the alerting path precisely because it has no model in the loop.

**Clone path:** `~/.config/nix-config` is recommended over `~/.config/nix`, because
`$XDG_CONFIG_HOME/nix/` is where Nix itself looks for `nix.conf`. Either works — `cdconf`/`rebuild`
probe for `~/.config/nix-darwin-config`, `~/.config/nix-config` and `~/.config/nix` in that order.

### Sandboxed Claude Code

`claudebox` is a drop-in for `claude` (same flags) that runs it as a transient
`systemd --user` service with the filesystem read-only and privilege escalation disabled:

```bash
cd /srv/storage/repos/foo && claudebox      # interactive
claudebox -p "..."                           # headless works too
CLAUDEBOX_RW=/srv/data:/opt/x claudebox # extra writable dirs, this run only
```

Inside it:

- **Writable:** the launch directory, `~/.config/nix`, `/srv/storage/repos`, `~/.claude`, and a
  private `/tmp` that's discarded on exit. Everything else is read-only. Launching from `~`, `/`
  or `/srv/storage` does *not* make that directory writable (too broad), so `cd` into a project first.
- **No root:** `sudo`/`su`/`pkexec` fail even with the right password — run those yourself in a
  normal shell.
- **Blocked:** mount, ptrace, bpf, kernel modules, new namespaces. Claude's own `/sandbox` needs
  namespaces, so it doesn't work inside; this sandbox replaces it.
- **Open:** network, your environment and SSH agent (so `git push` works), and `nix` via the daemon.
  `just switch` won't work inside — it writes outside the allowlist.

Claude's global state moves from `~/.claude.json` to `~/.claude/.claude.json` (`CLAUDE_CONFIG_DIR`),
since `$HOME` is read-only in the sandbox. The first `claudebox` run copies it over, and from then
on `~/.zshenv` points plain `claude` (in new shells) at the same file, so both share trust settings,
MCP servers and login.

## noble2 (VPS, root)

`just` derives the flake target from `hostname -s`, so the box's hostname must actually be
`noble2` (`hostnamectl set-hostname noble2`) before `just switch`/`just bootstrap-linux` will
resolve. One-time setup, run as `root`:

```bash
apt install -y zsh git curl
chsh -s /usr/bin/zsh
git clone git@github.com:saiputravu/nix-macos.git ~/.config/nix-config
cd ~/.config/nix-config
nix run nixpkgs#just -- bootstrap-linux     # or the raw command below
nix run home-manager/master -- switch -b backup --flake ~/.config/nix-config#root@noble2
```

After the first activation:

```bash
just switch
# equivalently:
home-manager switch -b backup --flake ~/.config/nix-config#root@noble2
```

## Known sharp edges

- `home.file.".gitconfig"` and `programs.git` both exist. Git reads `~/.gitconfig` and ignores
  `~/.config/git/config` when it's present, so the `programs.git.settings` block
  (`init.defaultBranch`, `push.autoSetupRemote`, lfs) currently has no effect on any host.
- `configs/helix/languages.toml` references `lspmux`, `rustfmt`, `dprint` and `clangd`, none of
  which are installed on `maui`/`noble2` — helix will just report no LSP for those languages.
- `configs/tmux.conf` pipes copy-mode to `xclip`, which isn't installed on any host.
