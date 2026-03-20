{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      lib = nixpkgs.lib;
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      linkFarmAll =
        system: flake:
        lib.pipe flake [
          (lib.filterAttrs (
            name: output:
            !lib.elem name [ "checks" ]
            && output ? ${system}
            && builtins.isAttrs output.${system}
            && !(output.${system} ? type)
          ))
          (lib.mapAttrsToList (
            outputName: output:
            lib.mapAttrsToList (name: drv: {
              name = "${outputName}-${name}";
              path = drv;
            }) output.${system}
          ))
          lib.concatLists
          (pkgs.linkFarm "all")
        ];

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        programs.deadnix.enable = true;
        programs.nixfmt.enable = true;
      };

      tests = import ./tests.nix { inherit pkgs self; };

      packages = {
        formatting = treefmtEval.config.build.check self;
        test-nginx = tests.nginx;
        test-caddy = tests.caddy;
        generate-cert = pkgs.writeShellApplication {
          name = "generate-cert";
          runtimeInputs = [ pkgs.openssl ];
          text = ''
            domain="$1"
            outfile="$2"
            openssl req -x509 -newkey rsa:2048 -keyout "''${outfile%.pem}.key.pem" -out "$outfile" -days 365 -nodes -subj "/CN=$domain"
          '';
        };
      };

    in
    {
      nixosModules.default = import ./module.nix;
      packages.x86_64-linux = packages;
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;
      checks.x86_64-linux.all = linkFarmAll "x86_64-linux" self;
    };
}
