# wg_phone_gateway

Plain-WireGuard entry point (arm, UDP 51820) so a phone can reach tailnet hosts
without the Tailscale app. Split tunnel: clients route only `100.64.0.0/10`
(+ the gateway address) through it; DNS = MagicDNS `100.100.100.100`.

- Opt-in: `wg_phone_enabled: true` + `wg_phone_peers` in `host_vars/<host>.yml`.
- Server private key: generated once on the host (`/etc/wireguard/wg-phone.key`,
  0600), never in Git. Rebuild = new key => re-issue client configs.
- Prerequisites outside this role: host firewall allows UDP 51820 (ufw) and the
  OCI Security List has an ingress rule UDP 51820 (see vault note).
- Client private keys exist only on the clients / in the config handed to them.
- Revoke a client: remove it from `wg_phone_peers`, run the role.
