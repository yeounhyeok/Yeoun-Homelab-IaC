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
playbooks/npm_advanced_config.yml     NPM proxy-host Advanced config (e.g. jellyfin web HEVC->H.264)
playbooks/lab_gpu_jobs.yml            on-demand GPU job tools on lab (gpu-run / gpu-status)
playbooks/lab_media.yml               lab media path (n4000 NFS -> Windows portproxy -> WSL) + lab Windows ports
```

The old Tailscale backup-named entrypoint was removed; call
`playbooks/tailscale_enroll.yml` directly.

## lab media path (Jellyfin on lab, 2026-10-26)

lab is one PC with two inventory hosts: `lab` (WSL2 Ubuntu, Docker) and
`lab-win` (the Windows host itself, OpenSSH with cmd shell, `ansible.windows`).

```text
n4000:/mnt/usb ──Tailscale──▶ lab Windows portproxy <WSL vEthernet IP>:2049
                                  ▲ (roles/lab_windows_net, PortproxyGuard 1 min)
WSL  /mnt/n4000 (nfs4 ro) ────────┘ (roles/wsl_nfs_mount, timer 5 min)
     └─ jellyfin container /media (GTX 1050 NVENC, compose/lab/jellyfin)
NPM proxy host 18 ──▶ lab.soay-quail.ts.net:8096 ──portproxy──▶ 127.0.0.1:8096 (WSL)
```

Why the portproxy: WSL's own NAT path to n4000 runs at ~5 MB/s (both through
the Windows Tailscale and with a Tailscale node inside WSL), while Windows gets
~10-12 MB/s. WSL only talks to the Windows side of the vSwitch; Windows makes
the n4000 connection (measured 9.7-9.9 MB/s vs host 11.3-11.5 MB/s). The n4000
export for lab needs `insecure` because the connection comes from Windows with
a source port above 1023. n4200's Jellyfin is kept stopped as a fallback
(`profiles: ["disabled"]`); rollback = start it and point NPM 18 back.

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
