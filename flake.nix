{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, utils }@inputs:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        name = "os-installer-snowflake-config";
      in
      rec
      {
        packages.${name} = pkgs.callPackage ./default.nix {
          inherit (inputs);
        };

        # `nix build`
        defaultPackage = packages.${name};

        # `nix run`
        apps.${name} = utils.lib.mkApp {
          inherit name;
          drv = packages.${name};
        };
        defaultApp = packages.${name};
      });
}
