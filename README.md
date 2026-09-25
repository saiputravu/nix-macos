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

Manual steps, all one-time and none of them expressible in Nix:

1. **blocky** — Tailscale admin → DNS: global nameserver from `just dns-info`, `9.9.9.9` as a
   second resolver, *Override local DNS* on.
2. **ntfy** — `ntfy user add --role=admin sai`, `ntfy token add sai` → `~/.config/ntfy/token`,
   then subscribe to the `alerts` topic in the iOS app pointed at the `:8443` URL.
3. **paperless** — `paperless-manage createsuperuser`, then an API token in the web UI for the
   iOS app.
4. **couchdb** — set the admin password in the seeded ini, create the LiveSync database, generate
   the Setup URI in the plugin here and paste it on the other devices. Remove the `obsidian-git`
   *plugin* everywhere: `vault-git.timer` is the only writer of git history now.
5. **gcalcli** — OAuth *desktop app* client in Google Cloud Console, Calendar API enabled, client
   JSON in `~/.config/gcalcli/`, then `gcalcli init` once.
6. **openclaw** — `openclawctl models auth login --provider anthropic --method cli`, then
   `openclawctl channels login --channel whatsapp` and scan the QR. Add the sending number to
   `channels.whatsapp.allowFrom` in `/var/lib/openclaw/openclaw.json`. Use `openclawctl`, not
   `openclaw`: the daemon's state lives under its own user.

**Clone path:** `~/.config/nix-config` is recommended over `~/.config/nix`, because
`$XDG_CONFIG_HOME/nix/` is where Nix itself looks for `nix.conf`. Either works — `cdconf`/`rebuild`
probe for `~/.config/nix-darwin-config`, `~/.config/nix-config` and `~/.config/nix` in that order.

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
