# -*- coding: utf-8 -*-
"""Return the custom fields of exactly one Vaultwarden item as a dict.

    lookup('vaultwarden_fields', 'homelab/n4000/immich-app')

Uses the `bw` CLI with BW_SESSION from the controller environment.
Why not community.general.bitwarden: our bw build aborts at exit (rc=134)
after printing valid JSON, which that plugin treats as failure. Here a
non-zero rc is tolerated only when stdout parses as JSON, and the item
name must match exactly (search is substring-based).
"""
from __future__ import annotations
import json
import subprocess
from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        out = []
        for name in terms:
            proc = subprocess.run(["bw", "list", "items", "--search", name],
                                  capture_output=True, text=True, timeout=120)
            try:
                items = json.loads(proc.stdout or "")
            except ValueError:
                raise AnsibleError("vaultwarden_fields: bw returned no JSON for %r (rc=%s). "
                                   "Is BW_SESSION exported and the vault unlocked?" % (name, proc.returncode))
            exact = [i for i in items if i.get("name") == name]
            if len(exact) != 1:
                raise AnsibleError("vaultwarden_fields: expected exactly 1 item named %r, found %d" % (name, len(exact)))
            out.append({f["name"]: f.get("value") or "" for f in exact[0].get("fields") or []})
        return out
