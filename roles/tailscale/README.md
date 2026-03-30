# tailscale role (backup management path)

WireGuard is still the primary management network in this repository.
This role only adds Tailscale as a backup/secondary management path for emergency access.
For Debian/Ubuntu/Raspbian hosts, it also configures the official Tailscale apt repository automatically.

Required secret variable (Vault recommended):

```yaml
vault_tailscale_auth_key: "tskey-..."
```

Optional variables:

```yaml
tailscale_tags:
  - "tag:homelab"
  - "tag:mgmt-backup"
tailscale_force_reauth: false
tailscale_reapply_on_each_run: true
tailscale_accept_dns: false
```

Run only this pass:

```bash
ansible-playbook playbooks/tailscale_backup_management.yml
```
