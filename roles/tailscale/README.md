# tailscale role (backup management path)

WireGuard is still the primary management network in this repository.
This role only adds Tailscale as a backup/secondary management path for emergency access.
For Debian/Ubuntu/Raspbian hosts, it also configures the official Tailscale apt repository automatically.

Required secret variable (Vault recommended):

```yaml
vault_ts_auth_key: "tskey-..."
```

Optional variables:

```yaml
ts_tags:
  - "tag:homelab"
  - "tag:mgmt-backup"
ts_accept_dns_by_host:
  arm: true
  n4000: true
  n4200: true
ts_advertise_exit_node_by_host:
  n4000: true
ts_force_reauth: false
ts_reapply_on_each_run: true
ts_apt_lock_timeout_seconds: 180
```

Run only this pass:

```bash
ansible-playbook playbooks/tailscale_backup_management.yml
```
