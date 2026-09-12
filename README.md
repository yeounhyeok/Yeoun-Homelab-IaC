# Yeoun Homelab IaC

Ansible repository for the current homelab architecture. The repository has a
strict boundary between **host convergence** and **application-state restore**.

## Architecture

- `arm`: primary automation/Vault host and active Tailnet DNS control-plane.
- `n4000`: stateful Docker host, rebuilt from clean eMMC when required.
- `n4200`: headless edge/application node.
- External HDD: user/application data; mount only after model and UUID are
  verified on the fresh OS.

The default architecture does **not** make n4000 an NFS server, WireGuard hub,
DNS dependency, or exit node. Those old roles were removed from the active tree;
see `docs/legacy-removal.md`.

## Repository contract

### IaC manages

- Ubuntu baseline and timezone
- Docker Engine, Compose V2, bounded container logs
- SSH policy with config validation and PAM kept available for MFA extensions
- zram policy
- Tailscale enrollment/reconciliation
- verified external-disk mount and empty service roots on n4000

### IaC does not manage

- disk formatting or partitioning
- `/var/lib/docker` copying
- Docker overlay/container metadata
- Tailscale identity state
- plaintext `.env`, private keys, tunnel tokens, or database passwords
- automatic discovery and startup of every directory found on disk

Application data is restored from encrypted config archives and native database
exports according to `docs/n4000-preservation-manifest.yml`.

## Entry points

```text
site.yml                              shared host baseline
playbooks/n4000_rebuild.yml           clean n4000 host bootstrap
playbooks/n4000_restore_services.yml  explicit compose restore allow-list
playbooks/tailscale_enroll.yml        enrollment/reconciliation
playbooks/docker_stop_all.yml         emergency stop, confirmation required
playbooks/docker_start_all.yml        emergency start
```

The old Tailscale backup-named entrypoint was removed; call
`playbooks/tailscale_enroll.yml` directly.

## Fresh n4000 workflow

```bash
ansible-galaxy collection install -r collections/requirements.yml

# 1. Reinstall Ubuntu. Identify disks by model and UUID.
#    Never infer the eMMC from mmcblk0/mmcblk1 numbering.
#    Do not format or mount the 931.5GiB HDD until verified.

# 2. Copy the bootstrap inventory example and set only the temporary LAN IP.
cp inventory/bootstrap.ini.example inventory/bootstrap.ini

# 3. Put n4000_data_disk_uuid and enrollment secrets in ignored/encrypted vars.
#    First run intentionally leaves the HDD unmounted.
ansible-playbook -i inventory/bootstrap.ini playbooks/n4000_rebuild.yml \
  --limit n4000

# 4. After checking the HDD model and UUID on the fresh OS, opt in to mount.
ansible-playbook -i inventory/bootstrap.ini playbooks/n4000_rebuild.yml \
  --limit n4000 -e n4000_mount_data_disk=true

# 5. Restore selected config and native DB exports, then start only an allow-list.
ansible-playbook playbooks/n4000_restore_services.yml --limit n4000 \
  -e '{"compose_restore_services":["adguardhome","nginx-proxy-manager"]}'
```

## Validation

Use a local Ansible installation and install the pinned collections:

```bash
ansible-galaxy collection install -r collections/requirements.yml
ansible-playbook --syntax-check site.yml
ansible-playbook --syntax-check playbooks/n4000_rebuild.yml
ansible-playbook --syntax-check playbooks/n4000_restore_services.yml
```

The repository deliberately does not require a vault password to be committed.
Provide `.vault_pass` through the local ignored path or another approved
Ansible secret mechanism at execution time.
