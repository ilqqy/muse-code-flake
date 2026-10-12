# muse-code-flake

Nix flake packaging Meta's [Muse Code](https://dev.meta.ai/docs/muse-code) CLI
(`muse`) for NixOS, for `x86_64-linux` and `aarch64-linux`.

> **Unofficial.** Not affiliated with or endorsed by Meta. This repository
> contains no Meta code: the proprietary `muse` binary is downloaded from Meta's
> servers at build time, pinned by hash in [`sources.json`](sources.json).

## Try it

```sh
nix run github:ilqqy/muse-code-flake -- --version
```

## Use as a flake input

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    muse-code = {
      url = "github:ilqqy/muse-code-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, muse-code, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        ({ pkgs, ... }: {
          environment.systemPackages = [
            muse-code.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
        })
      ];
    };
  };
}
```

## Use the overlay

The overlay adds `pkgs.muse-code`. In the `modules` list above:

```nix
({ lib, pkgs, ... }: {
  nixpkgs.overlays = [ muse-code.overlays.default ];
  nixpkgs.config.allowUnfreePredicate =
    pkg: builtins.elem (lib.getName pkg) [ "muse-code" ];

  environment.systemPackages = [ pkgs.muse-code ];
})
```

## Unfree license

`muse` is proprietary (`meta.license = lib.licenses.unfree`). The overlay builds
with your nixpkgs, so you must allow it there (`allowUnfree = true`, or the
predicate above). The flake's own `packages`, `apps` and `checks` allow just
this package, so `nix run`, `nix build` and `packages.<system>.default` work
without changing your configuration.

## Differences from Meta's installer

- The official `install.sh` installs a bash launcher that downloads the binary
  into `~/.local/bin` and silently updates it in the background. That launcher
  is not used here. The native binary has no updater of its own and runs from
  the read-only store. New releases arrive through this repository: a daily
  workflow bumps `sources.json` once the new version builds and runs on both
  architectures. To bump it yourself, run `scripts/update.sh`.
- `muse` sandboxes tool commands with Bubblewrap and refuses to run them
  without a working `bwrap` on `PATH`. The wrapper puts nixpkgs' `bubblewrap`
  first on `PATH`, and adds `git` as a fallback when you don't have one.
  The sandbox needs unprivileged user namespaces, which NixOS enables by default.
