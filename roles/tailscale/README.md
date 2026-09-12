# Tailscale management role

This is the supported management path. WireGuard is not part of the default
architecture anymore.

The role is idempotent for already-enrolled nodes: an auth key is required only
when the node needs enrollment or `ts_force_reauth`/`ts_reapply_on_each_run` is
explicitly enabled.

Required only for enrollment/reconciliation:

```yaml
vault_ts_auth_key: "tskey-..."
```

Host policy belongs in inventory/group variables:

```yaml
ts_accept_dns_by_host:
  n4000: false

ts_advertise_exit_node_by_host:
  n4000: false
```
