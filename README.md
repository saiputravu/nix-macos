# nix config

Personal Nix configuration for two machines:

| host   | OS                     | managed by                          | scope         |
| ------ | ---------------------- | ----------------------------------- | ------------- |
| `mahi` | macOS (aarch64-darwin) | nix-darwin + home-manager module    | system + home |
| `maui` | Debian 13 trixie (x86_64-linux) | standalone home-manager    | `$HOME` only  |

Debian isn't NixOS, so there is no system-level Nix config for `maui` — packages like `zsh`,
`curl` and `build-essential` stay apt's job.

## Layout

```
flake.nix                      hosts attrset + the two outputs
configs/                       raw dotfiles, symlinked in via home.file
modules/
├── common/home.nix            cross-platform home config (both hosts)
├── darwin/
│   ├── configuration.nix      nix-darwin system config (homebrew, system.defaults, aerospace, ...)
│   ├── home-manager.nix       wires home-manager into nix-darwin
│   ├── home.nix               macOS-only home config
│   ├── steam.nix              DMG-wrapping derivation
│   └── protonvpn.nix          DMG-wrapping derivation (currently unused)
└── linux/home.nix             Linux-only home config
```

Adding a package: cross-platform → `modules/common/home.nix`; mac-only → `modules/darwin/home.nix`;
Debian-only → `modules/linux/home.nix`.

## mahi (macOS)

```bash
sudo darwin-rebuild switch --flake ~/.config/nix-darwin-config#mahi
# or just:
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
nix run home-manager/master -- switch -b backup --flake ~/.config/nix-config#sai@maui
```

After the first activation `home-manager` is on `$PATH`:

```bash
home-manager switch -b backup --flake ~/.config/nix-config#sai@maui
# or just:
rebuild
```

`zsh4humans` bootstraps itself on first interactive shell via the managed `~/.zshenv`.

**Clone path:** `~/.config/nix-config` is recommended over `~/.config/nix`, because
`$XDG_CONFIG_HOME/nix/` is where Nix itself looks for `nix.conf`. Either works — `cdconf`/`rebuild`
probe for `~/.config/nix-darwin-config`, `~/.config/nix-config` and `~/.config/nix` in that order.

## Known sharp edges

- `home.file.".gitconfig"` and `programs.git` both exist. Git reads `~/.gitconfig` and ignores
  `~/.config/git/config` when it's present, so the `programs.git.settings` block
  (`init.defaultBranch`, `push.autoSetupRemote`, lfs) currently has no effect on either host.
- `configs/helix/languages.toml` references `lspmux`, `rustfmt`, `dprint` and `clangd`, none of
  which are installed on `maui` — helix will just report no LSP for those languages.
- `configs/tmux.conf` pipes copy-mode to `xclip`, which isn't installed on either host.
