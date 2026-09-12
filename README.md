# 🏠 Yeoun Homelab IaC

Ansible workspace for a **clean, reproducible host baseline**. It separates:

1. **IaC-managed baseline** — Ubuntu settings, Docker, Tailscale, disk mount, service directory layout, diagnostics.
2. **Encrypted restore artifacts** — compose manifests, `.env` files, certificates, service configuration, and native database dumps.
3. **Disposable runtime state** — Docker overlay layers, images, containers, caches, anonymous volumes, and logs.

The immediate use case is a clean n4000 rebuild after root-eMMC filesystem instability.

## Safety model

- This repository **never stores plaintext credentials**, tunnel tokens, private keys, or application `.env` files.
- `playbooks/n4000_rebuild.yml` does **not** format disks, restore user data, or start application containers.
- `playbooks/n4000_restore_services.yml` starts only an explicit allow-list of already-restored projects.
- Do not copy `/var/lib/docker` to a fresh OS. Use native database exports and compose-level restoration.
- Do not restore `/var/lib/tailscale/tailscaled.state`; enroll the rebuilt host as a deliberate Tailnet node.

## Current architecture decision

- `arm`: primary Vault/automation and active Tailnet DNS control-plane.
- `n4000`: stateful Docker host after rebuild; **not** a default NFS, WireGuard, DNS, or exit-node control-plane dependency.
- `n4200`: headless edge/application node.
- NFS and WireGuard roles remain available only as explicit `nfs_legacy`/legacy workflows; they do not run in the default `site.yml` path.

## Bootstrap a fresh n4000

```bash
ansible-galaxy collection install -r collections/requirements.yml

# 1) Reinstall Ubuntu and identify disks by model/UUID.
#    Never assume mmcblk0: controller numbering has changed across boots.
#    Do not touch the 931.5GiB external HDD.

# 2) Use inventory/bootstrap.ini (copied from inventory/bootstrap.ini.example)
#    until Tailnet enrollment is complete. Put n4000_data_disk_uuid and Vault
#    secrets in encrypted variables; first run leaves the HDD unmounted.
ansible-playbook -i inventory/bootstrap.ini playbooks/n4000_rebuild.yml --limit n4000

# 3) After verifying the HDD UUID in the fresh OS, opt in to the mount.
ansible-playbook -i inventory/bootstrap.ini playbooks/n4000_rebuild.yml --limit n4000 \\
  -e n4000_mount_data_disk=true

# 4) Restore encrypted compose/config artifacts and native DB dumps.
#    Start only reviewed services, in dependency order.
ansible-playbook playbooks/n4000_restore_services.yml --limit n4000 \\
  -e '{"n4000_restore_services":["adguardhome","nginx-proxy-manager"]}'
```

## Required preservation review

Read [`docs/n4000-preservation-manifest.yml`](docs/n4000-preservation-manifest.yml) before any wipe. It classifies current n4000 state as:

- **critical restore:** NPM/certificates, Vaultwarden, AdGuard, Cloudflared, Immich, Nextcloud, Syncthing, Navidrome;
- **preserve or selectively restore:** Jellyfin and monitoring configuration/history;
- **triage with owner confirmation:** legacy Ghost, Postgres, Uptime Kuma, Portainer, chatbot, documentserver, and vocal-coach volumes;
- **recreate:** Docker runtime state and Tailscale identity.

## Default baseline

```bash
ansible-playbook site.yml
```

This applies only `common`, RAM optimization, and Tailscale. It does not deploy services or make n4000 an NFS hub.
