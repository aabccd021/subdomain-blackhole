{
  pkgs,
  self,
}:
let
  attacker = {
    networking.interfaces.eth1.ipv4.addresses = [
      {
        address = "192.168.1.1";
        prefixLength = 24;
      }
    ];
    networking.hosts."192.168.1.2" = [
      "example.com"
      "unknown.example.com"
    ];
    environment.etc."ssl/server.pem".source = ./test/cert.pem;
  };

  user = {
    networking.interfaces.eth1.ipv4.addresses = [
      {
        address = "192.168.1.3";
        prefixLength = 24;
      }
    ];
    networking.hosts."192.168.1.2" = [
      "example.com"
      "unknown.example.com"
    ];
    environment.etc."ssl/server.pem".source = ./test/cert.pem;
  };

  serverBase = {
    imports = [ self.nixosModules.default ];
    networking.interfaces.eth1.ipv4.addresses = [
      {
        address = "192.168.1.2";
        prefixLength = 24;
      }
    ];
    services.subdomain-blackhole.enable = true;
    networking.firewall.allowedTCPPorts = [ 443 ];
  };
in
{
  nginx = pkgs.testers.runNixOSTest {
    name = "subdomain-blackhole-nginx";
    nodes.server =
      { ... }:
      {
        imports = [ serverBase ];
        services.nginx.enable = true;
        services.nginx.virtualHosts."example.com" = {
          onlySSL = true;
          sslCertificate = ./test/cert.pem;
          sslCertificateKey = ./test/key.pem;
          locations."/".return = "200 'Hello from example.com'";
        };
      };
    nodes.attacker = attacker;
    nodes.user = user;
    testScript = builtins.readFile ./test/nginx.py;
  };

  caddy = pkgs.testers.runNixOSTest {
    name = "subdomain-blackhole-caddy";
    nodes.server =
      { ... }:
      {
        imports = [ serverBase ];
        services.caddy.enable = true;
        services.caddy.virtualHosts."example.com" = {
          extraConfig = ''
            tls ${./test/cert.pem} ${./test/key.pem}
            respond "Hello from example.com"
          '';
        };
      };
    nodes.attacker = attacker;
    nodes.user = user;
    testScript = builtins.readFile ./test/caddy.py;
  };
}
