server.wait_for_unit("nginx.service")
server.wait_for_unit("fail2ban.service")
server.wait_for_open_port(443)

attacker.wait_for_unit("multi-user.target")

# Request to the legitimate virtualHost should work
result = attacker.succeed("curl -sk https://server.com/")
assert "Hello from server.com" in result, f"Expected greeting, got: {result}"

# Make a request with unmatched SNI
attacker.succeed("curl -sk https://unknown.server.com/ || true")

# Wait for fail2ban to ban the IP and verify exact output
server.wait_until_succeeds("fail2ban-client status subdomain-blackhole | grep -q '192.168.1.1'", timeout=10)
output = server.succeed("fail2ban-client status subdomain-blackhole")
expected = """Status for the jail: subdomain-blackhole
|- Filter
|  |- Currently failed:\t0
|  |- Total failed:\t1
|  `- Journal matches:\t_SYSTEMD_UNIT=nginx.service
`- Actions
   |- Currently banned:\t1
   |- Total banned:\t1
   `- Banned IP list:\t192.168.1.1"""
assert output.strip() == expected, f"Expected:\n{expected}\n\nGot:\n{output}"
