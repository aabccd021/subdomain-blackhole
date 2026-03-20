{
  config,
  lib,
  ...
}:
let
  cfg = config.services.subdomain-blackhole;
  nginxEnabled = config.services.nginx.enable;
  caddyEnabled = config.services.caddy.enable;
  webserver = if nginxEnabled then "nginx" else "caddy";

  # Check for other nginx virtualHosts with default = true
  otherDefaultNginxHosts = lib.filterAttrs (name: vhost: name != "_" && (vhost.default or false)) (
    config.services.nginx.virtualHosts or { }
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

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !nginxEnabled || otherDefaultNginxHosts == { };
        message = "subdomain-blackhole: cannot have other nginx virtualHosts with 'default = true'. Conflicting hosts: ${lib.concatStringsSep ", " (lib.attrNames otherDefaultNginxHosts)}";
      }
    ];

    # Fail2ban filter
    environment.etc."fail2ban/filter.d/subdomain-blackhole.conf".text =
      if webserver == "nginx" then
        ''
          [Definition]
          failregex = ^.*nginx.*handshake rejected.*client: <HOST>,.*$
          ignoreregex =
          journalmatch = _SYSTEMD_UNIT=nginx.service
        ''
      else
        ''
          [Definition]
          failregex = ^.*"client_ip":"<HOST>".*$
          ignoreregex =
          datepattern = "ts":{EPOCH}
        '';

    # Fail2ban jail
    services.fail2ban = {
      enable = true;
      jails.${cfg.jailName}.settings = {
        enabled = lib.mkDefault true;
        filter = lib.mkDefault "subdomain-blackhole";
        backend = lib.mkDefault (if webserver == "nginx" then "systemd" else "polling");
        bantime = lib.mkDefault 3600;
        maxretry = lib.mkDefault 1;
        findtime = lib.mkDefault 600;
        logpath = lib.mkDefault (
          if webserver == "nginx" then
            "" # journald doesn't need logpath
          else
            "/var/log/caddy/subdomain-blackhole.log"
        );
      };
    };

    # Nginx log level to capture ssl_reject_handshake
    services.nginx.logError = lib.mkIf nginxEnabled "stderr info";

    # Nginx configuration - reject SSL for unmatched SNI
    services.nginx.virtualHosts."_" = lib.mkIf nginxEnabled {
      default = true;
      rejectSSL = true;
      listen = [
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "[::]";
          port = 443;
          ssl = true;
        }
      ];
    };

    # Caddy configuration - HTTPS catch-all
    services.caddy.virtualHosts.":443" = lib.mkIf caddyEnabled {
      logFormat = ''
        output file /var/log/caddy/subdomain-blackhole.log
        format json
      '';
      extraConfig = ''
        tls internal
        respond 444 {
          close
        }
      '';
    };

    # Ensure log directory and file exist for caddy
    systemd.tmpfiles.rules = lib.mkIf caddyEnabled [
      "d /var/log/caddy 0755 caddy caddy -"
      "f /var/log/caddy/subdomain-blackhole.log 0644 caddy caddy -"
    ];
  };
}
