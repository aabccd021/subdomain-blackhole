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

      packages = {
        formatting = treefmtEval.config.build.check self;
        test = pkgs.testers.runNixOSTest {
          name = "subdomain-blackhole";
          nodes.machine = {
            imports = [ self.nixosModules.default ];
            services.subdomain-blackhole.enable = true;
          };
          testScript = ''
            machine.wait_for_unit("multi-user.target")
            machine.succeed("cat /etc/hello | grep 'Hello, World!'")
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
