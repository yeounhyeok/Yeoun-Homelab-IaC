# n4000 clean rebuild and service restoration

This role starts **only** projects that were explicitly restored and supplied in
`compose_restore_services`. It does not copy Docker runtime state, create
containers implicitly, or infer a service list from directories on disk.

Required sequence:

1. Restore the selected config and native database backup.
2. Verify the project directory and its secrets source.
3. Run `playbooks/n4000_restore_services.yml` with an explicit allow-list.
4. Verify service health and public ingress separately.
