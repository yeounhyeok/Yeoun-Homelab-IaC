# Yeoun Homelab IaC architecture

## Entry points

| Entry point | Purpose | Side effects |
|---|---|---|
| `site.yml` | Shared host baseline | Packages, Docker, SSH policy, zram, Tailscale |
| `playbooks/n4000_rebuild.yml` | Fresh n4000 host after OS install | Baseline + verified HDD mount, never formats/restores/starts apps |
| `playbooks/n4000_restore_services.yml` | Restore selected n4000 compose projects | Starts only explicit `compose_restore_services` |
| `playbooks/tailscale_enroll.yml` | Enroll/reconcile management path | Requires Vault auth key only when state must change |
| `playbooks/docker_stop_all.yml` | Emergency Docker stop | Requires `docker_stop_confirm=true` |
| `playbooks/docker_start_all.yml` | Emergency Docker start | Starts Docker only |

## Supported topology

- `arm`: primary automation/Vault and Tailnet DNS control-plane.
- `n4000`: stateful Docker host, rebuilt from a clean eMMC OS when required.
- `n4200`: headless edge/application node.
- External HDD: user/application data mounted only after UUID/model verification.

The repository does not configure n4000 as an NFS server, WireGuard hub, or
Tailnet exit-node by default. Those old roles were removed because they no
longer describe the live architecture and made a full `site.yml` run unsafe.
Their implementation remains available through Git history if forensic recovery
is ever needed.

## Variable boundaries

- `group_vars/all.yml`: non-secret topology and policy.
- `group_vars/secrets.yml`: encrypted credentials loaded by Ansible's normal
  group-vars mechanism; no playbook-relative manual include.
- `host_vars/n4000.yml`: ignored local override for the verified external HDD
  UUID and bootstrap choice; start from the `.example` file.
- `roles/*/defaults/main.yml`: safe defaults that do not depend on a specific
  host's current runtime state.

## Restore boundary

IaC creates the host and empty project roots. It does not copy `/var/lib/docker`
or `/var/lib/tailscale/tailscaled.state`. Application state must arrive through
verified encrypted config archives and native database exports, as described in
`docs/n4000-preservation-manifest.yml`.
