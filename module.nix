{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.subdomain-blackhole;
in
{
  options.services.subdomain-blackhole = {
    enable = lib.mkEnableOption "subdomain-blackhole";
    message = lib.mkOption {
      type = lib.types.str;
      default = "Hello, World!";
      description = "Message to write to the hello file";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."hello".text = cfg.message;
  };
}
