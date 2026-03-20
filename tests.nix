{
  pkgs,
  self,
}:
{
  nginx =
    let
      serverIp = "192.168.1.2";
    in
    pkgs.testers.runNixOSTest {
      name = "subdomain-blackhole-nginx";
      nodes.server =
        { ... }:
        {
          imports = [ self.nixosModules.default ];
          networking.interfaces.eth1.ipv4.addresses = [
            { address = serverIp; prefixLength = 24; }
          ];
          services.nginx.enable = true;
          services.nginx.virtualHosts."server.com" = {
            onlySSL = true;
            sslCertificate = ./test/cert.pem;
            sslCertificateKey = ./test/key.pem;
            locations."/".return = "200 'Hello from server.com'";
          };
          services.subdomain-blackhole.enable = true;
          networking.firewall.allowedTCPPorts = [ 443 ];
        };
      nodes.attacker = {
        networking.hosts.${serverIp} = [ "server.com" "unknown.server.com" ];
      };
      testScript = builtins.readFile ./test/nginx.py;
    };

  caddy = pkgs.testers.runNixOSTest {
    name = "subdomain-blackhole-caddy";
    nodes.server =
      { ... }:
      {
        imports = [ self.nixosModules.default ];
        services.caddy.enable = true;
        services.caddy.virtualHosts."example.com" = {
          extraConfig = ''
            tls ${./test/cert.pem} ${./test/key.pem}
            respond "Hello from example.com"
          '';
        };
        services.subdomain-blackhole.enable = true;
        networking.firewall.allowedTCPPorts = [ 443 ];
      };
    nodes.attacker = { };
    testScript = builtins.readFile ./test/caddy.py;
  };
}
