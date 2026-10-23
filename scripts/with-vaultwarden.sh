#!/usr/bin/env bash
# Export BW_SESSION for the vaultwarden_fields lookup, then run the command.
# Session source: $BW_SESSION, else Hermes' session file on arm.
set -euo pipefail
if [ -z "${BW_SESSION:-}" ]; then
  f="${BW_SESSION_FILE:-$HOME/.hermes/secrets/bw_session_raw}"
  BW_SESSION=$(python3 -c 'import json,sys; s=open(sys.argv[1]).read().strip()
try: s=json.loads(s)["session_key"]
except Exception: pass
print(s)' "$f")
  export BW_SESSION
fi
bw sync >/dev/null 2>&1 || true
exec "$@"
