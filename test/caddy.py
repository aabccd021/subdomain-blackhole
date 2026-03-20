server.wait_for_unit("caddy.service")
server.wait_for_unit("fail2ban.service")
server.wait_for_open_port(443)

attacker.wait_for_unit("multi-user.target")

# Request to the legitimate virtualHost should work (use SNI for example.com)
result = attacker.succeed("curl -sk --resolve example.com:443:$(getent hosts server | awk '{print $1}') https://example.com/")
assert "Hello from example.com" in result, f"Expected greeting, got: {result}"

# Make a request with unmatched SNI - should hit catch-all
print("=== curl unmatched SNI ===")
result = attacker.succeed("curl -svk --resolve unknown.example.com:443:$(getent hosts server | awk '{print $1}') https://unknown.example.com/ 2>&1 || true")
print(result)

# Wait for fail2ban to process the log
server.sleep(2)

# Debug: show caddy logs
print("=== caddy log file ===")
print(server.succeed("cat /var/log/caddy/subdomain-blackhole.log || echo 'file empty or missing'"))
print("=== journalctl caddy ===")
print(server.succeed("journalctl -u caddy --no-pager"))
print("=== caddy config ===")
print(server.succeed("find /nix/store -name 'Caddyfile' -exec cat {} \\; 2>/dev/null | head -50 || echo 'not found'"))
print("=== caddy systemd ===")
print(server.succeed("systemctl cat caddy | head -30"))

# Check log was written
server.succeed("test -s /var/log/caddy/subdomain-blackhole.log")

# Verify fail2ban banned an IP
output = server.succeed("fail2ban-client status subdomain-blackhole")
assert "Banned IP list:" in output and output.split("Banned IP list:")[1].strip(), f"No IP was banned: {output}"
