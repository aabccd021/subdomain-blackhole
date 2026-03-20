{
  config,
  lib,
  ...
}:
let
  cfg = config.services.subdomain-blackhole;
  webserver =
    if config.services.nginx.enable then
      "nginx"
    else if config.services.caddy.enable then
      "caddy"
    else
      null;
  filterName = "subdomain-blackhole";

  # Check for nginx virtualHosts with default = true (excluding our catch-all "_")
  defaultNginxHosts = lib.filterAttrs (name: vhost: name != "_" && (vhost.default or false)) (
    config.services.nginx.virtualHosts or { }
  );

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

  config = lib.mkIf (cfg.enable && webserver != null) {
    assertions = [
      {
        assertion = webserver != "nginx" || defaultNginxHosts == { };
        message = "subdomain-blackhole: cannot have nginx virtualHosts with 'default = true'. Conflicting hosts: ${lib.concatStringsSep ", " (lib.attrNames defaultNginxHosts)}";
      }
      {
        assertion = webserver != "caddy" || caddyCatchAllHosts == { };
        message = "subdomain-blackhole: cannot have Caddy catch-all virtualHosts (like ':443'). Conflicting hosts: ${lib.concatStringsSep ", " (lib.attrNames caddyCatchAllHosts)}";
      }
    ];

    # Fail2ban filter
    environment.etc."fail2ban/filter.d/${filterName}.conf".text =
      if webserver == "nginx" then
        ''
          [Definition]
          failregex = ^.*handshake rejected.*client: <HOST>,.*$
          ignoreregex =
        ''
      else if webserver == "caddy" then
        ''
          [Definition]
          failregex = ^.*TLS handshake error from <HOST>:\d+:.*$
          ignoreregex =
          datepattern = "ts":{EPOCH}
          journalmatch = _SYSTEMD_UNIT=caddy.service
        ''
      else
        throw "subdomain-blackhole: unsupported webserver";

    # Fail2ban jail
    services.fail2ban = {
      enable = true;
      jails.${cfg.jailName}.settings =
        if webserver == "nginx" then
          {
            enabled = true;
            filter = filterName;
            backend = "auto";
            logpath = "/var/log/nginx/subdomain-blackhole.log";
            maxretry = lib.mkDefault 1;
          }
        else if webserver == "caddy" then
          {
            enabled = true;
            filter = filterName;
            backend = "systemd";
            maxretry = lib.mkDefault 1;
          }
        else
          throw "subdomain-blackhole: unsupported webserver";
    };

    # Nginx catch-all to reject unmatched SNI.
    # Without this, nginx uses the first matching certificate for unknown domains.
    # Example: if only "example.com" is configured, a request to "unknown.example.com"
    # would be served using example.com's certificate instead of being rejected.
    # rejectSSL uses ssl_reject_handshake to close the connection and log the attempt.
    services.nginx.virtualHosts."_" = lib.mkIf (webserver == "nginx") {
      default = true;
      rejectSSL = true;
      extraConfig = ''
        error_log /var/log/nginx/subdomain-blackhole.log info;
      '';
    };

    # Caddy log level to capture TLS handshake errors
    services.caddy.logFormat = lib.mkIf (webserver == "caddy") "level DEBUG";

  };
}
