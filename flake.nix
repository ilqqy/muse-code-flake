{
  description = "Nix flake for Meta's Muse Code CLI (muse)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # Only the systems Meta publishes a Linux binary for.
      systems = builtins.attrNames (lib.importJSON ./sources.json).platforms;

      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfreePredicate = pkg: lib.getName pkg == "muse-code";
            }
          )
        );
    in
    {
      overlays.default = final: _prev: {
        muse-code = final.callPackage ./package.nix { };
      };

      packages = forAllSystems (pkgs: rec {
        muse-code = pkgs.callPackage ./package.nix { };
        default = muse-code;
      });

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.default;
          meta.description = "Run Meta's Muse Code CLI";
        };
      });

      checks = forAllSystems (pkgs: {
        muse-code = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
