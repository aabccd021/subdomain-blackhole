server.wait_for_unit("nginx.service")
server.wait_for_unit("fail2ban.service")
server.wait_for_open_port(443)

attacker.wait_for_unit("multi-user.target")

# Request to the legitimate virtualHost should work
result = attacker.succeed("curl -s --cacert /etc/ssl/server.pem https://example.com/")
assert "Hello from example.com" in result, f"Expected greeting, got: {result}"

# Make a request with unmatched SNI (TLS fails, but IP gets logged)
attacker.fail("curl -sk https://unknown.example.com/")

# Verify fail2ban filter matches the log (failregex and datepattern work)
server.succeed("fail2ban-regex /var/log/nginx/subdomain-blackhole.log /etc/fail2ban/filter.d/subdomain-blackhole.conf")

# Wait for fail2ban to ban the IP and verify exact output
server.wait_until_succeeds("fail2ban-client status subdomain-blackhole | grep -q '192.168.1.1'", timeout=10)
output = server.succeed("fail2ban-client status subdomain-blackhole")
expected = """Status for the jail: subdomain-blackhole
|- Filter
|  |- Currently failed:\t0
|  |- Total failed:\t1
|  `- File list:\t/var/log/nginx/subdomain-blackhole.log
`- Actions
   |- Currently banned:\t1
   |- Total banned:\t1
   `- Banned IP list:\t192.168.1.1"""
assert output.strip() == expected, f"Expected:\n{expected}\n\nGot:\n{output}"

# 1. Verify banned IP is actually blocked from accessing legitimate domain
attacker.fail("curl -s --connect-timeout 5 --cacert /etc/ssl/server.pem https://example.com/")

# 2. Verify banned IP can't make more probing attempts (blocked at firewall)
# -k skips SSL verification so we test firewall block, not SSL rejection
attacker.fail("curl -sk --connect-timeout 5 https://unknown.example.com/")

# 3. Verify other IPs are unaffected - user can still access the server
user.wait_for_unit("multi-user.target")
result = user.succeed("curl -s --cacert /etc/ssl/server.pem https://example.com/")
assert "Hello from example.com" in result, f"Expected greeting from user, got: {result}"
