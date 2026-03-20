{
  config,
  lib,
  ...
}:
let
  cfg = config.services.subdomain-blackhole;
  filterName = "subdomain-blackhole";
  nginxHostName = "subdomain-blackhole";

  # Hardcoded in NixOS nginx module (services.nginx.stateDir was removed)
  nginxLogPath = "/var/log/nginx/subdomain-blackhole.log";

  # Caddy log path for TLS handshake errors (uses services.caddy.logDir)
  caddyLogPath = "${config.services.caddy.logDir}/subdomain-blackhole.log";

  # Check for nginx virtualHosts with default = true (excluding our catch-all)
  defaultNginxHosts = lib.filterAttrs (
    name: vhost: name != nginxHostName && (vhost.default or false)
  ) (config.services.nginx.virtualHosts or { });

  # Check for Caddy catch-all virtualHosts (ports without domains)
  caddyCatchAllHosts = lib.filterAttrs (name: _: builtins.match "^:[0-9]+$" name != null) (
    config.services.caddy.virtualHosts or { }
  );
in
{
  options.services.subdomain-blackhole = {
    enable = lib.mkEnableOption "subdomain-blackhole";

    jailName = lib.mkOption {
      type = lib.types.str;
      default = "subdomain-blackhole";
      readOnly = true;
      description = "The fail2ban jail name used by this module (read-only)";
    };
  };

  config = lib.mkIf (cfg.enable && (config.services.nginx.enable || config.services.caddy.enable)) {
    assertions = [
      {
        assertion = !config.services.nginx.enable || defaultNginxHosts == { };
        message = "subdomain-blackhole: cannot have nginx virtualHosts with 'default = true'. Conflicting hosts: ${lib.concatStringsSep ", " (lib.attrNames defaultNginxHosts)}";
      }
      {
        assertion = !config.services.caddy.enable || caddyCatchAllHosts == { };
        message = "subdomain-blackhole: cannot have Caddy catch-all virtualHosts (like ':443'). Conflicting hosts: ${lib.concatStringsSep ", " (lib.attrNames caddyCatchAllHosts)}";
      }
    ];

    # Fail2ban filter
    environment.etc."fail2ban/filter.d/${filterName}.conf".text =
      if config.services.nginx.enable then
        ''
          [Definition]
          failregex = ^.*handshake rejected.*client: <HOST>,.*$
          ignoreregex =
        ''
      else
        ''
          [Definition]
          failregex = ^.*TLS handshake error from <HOST>:\d+:.*$
          ignoreregex =
          datepattern = "ts":{EPOCH}
        '';

    # Fail2ban jail
    services.fail2ban = {
      enable = true;
      jails.${cfg.jailName}.settings = {
        enabled = true;
        filter = filterName;
        backend = "auto";
        logpath = if config.services.nginx.enable then nginxLogPath else caddyLogPath;
        maxretry = lib.mkDefault 1;
      };
    };

    # Nginx catch-all to reject unmatched SNI.
    # Without this, nginx uses the first matching certificate for unknown domains.
    # Example: if only "example.com" is configured, a request to "unknown.example.com"
    # would be served using example.com's certificate instead of being rejected.
    # rejectSSL uses ssl_reject_handshake to close the connection and log the attempt.
    services.nginx.virtualHosts.${nginxHostName} = lib.mkIf config.services.nginx.enable {
      default = true;
      rejectSSL = true;
      extraConfig = ''
        error_log ${nginxLogPath} info;
      '';
    };

    # Ensure caddy log file exists before fail2ban starts
    systemd.tmpfiles.rules = lib.mkIf config.services.caddy.enable [
      "d ${builtins.dirOf caddyLogPath} 0755 ${config.services.caddy.user} ${config.services.caddy.group} -"
      "f ${caddyLogPath} 0644 ${config.services.caddy.user} ${config.services.caddy.group} -"
    ];

    # Caddy named logger for TLS handshake errors - doesn't touch default logger
    services.caddy.globalConfig = lib.mkIf config.services.caddy.enable ''
      log subdomain-blackhole {
        output file ${caddyLogPath}
        level DEBUG
      }
    '';

  };
}
