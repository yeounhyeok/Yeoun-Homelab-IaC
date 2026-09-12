# Legacy removal record

The following code was removed from the active repository in the full IaC
refactor on 2026-09-12:

- `roles/wireguard`: replaced by the supported Tailscale management path.
- `roles/nfs_setup`: n4000 is no longer the storage/control-plane hub.
- `roles/deploy_services`: combined NFS sync and compose deployment; replaced by
  the explicit `roles/compose_restore` allow-list role.
- `roles/cron_cli_to_hub`: empty wrapper with no active caller.
- `playbooks/cleanup.yml`: unguarded deletion of service directories was not a
  safe operational workflow.

These files are recoverable from Git history, but are intentionally not part of
`site.yml` or the current rebuild path. Do not resurrect them by adding a role
to the default playbook without revalidating the current host map and storage
model.
