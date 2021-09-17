{
  description = "Simon’s Improved Layout Engine";

  # To make user overrides of the nixpkgs flake not take effect
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  # https://nixos.wiki/wiki/Flakes#Using_flakes_project_from_a_legacy_Nix
  inputs.flake-compat = {
    url = "github:edolstra/flake-compat";
    flake = false;
  };

  outputs = { self
    , nixpkgs
    , flake-utils
    , flake-compat
  }:
  flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = import nixpkgs {
        inherit system;
      };
      # Use the expression from Nixpkgs instead of rewriting it here.
      sile = pkgs.sile.overrideAttrs(oldAttr: rec {
        version = "${(pkgs.lib.importJSON ./package.json).version}-flake";
        src = builtins.filterSource
          (path: type: type != "directory" || baseNameOf path != ".git")
        ./.;
        # Don't build the manual as it's time consuming, and it requires fonts
        # that are not available in the sandbox due to internet connection
        # missing in the sandbox.
        configureFlags = pkgs.lib.lists.remove "--with-manual" oldAttr.configureFlags;
        nativeBuildInputs = oldAttr.nativeBuildInputs ++ [
          pkgs.autoreconfHook
        ];
        # This switch between the hooks can be moved to Nixpkgs'
        postPatch = oldAttr.preConfigure;
        preConfigure = "";
        meta = oldAttr.meta // {
          changelog = "https://github.com/sile-typesetter/sile/raw/master/CHANGELOG.md";
        };
      });
    in rec {
      devShell = pkgs.mkShell {
        inherit (sile) checkInputs nativeBuildInputs buildInputs;
      };
      packages.sile = sile;
      defaultPackage = sile;
      apps.sile = {
        type = "app";
        program = "${sile}/bin/sile";
      };
      defaultApp = apps.sile;
    }
  );
}
