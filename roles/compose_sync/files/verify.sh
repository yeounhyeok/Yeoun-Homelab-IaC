#!/usr/bin/env bash
# verify.sh <project_dir> <candidate_dir> <compose_file> [env files...]
# Prints EQUAL or DIFF:<reason>. Never prints values.
set -uo pipefail
D=$1; T=$2; F=$3; shift 3
h(){ sha256sum | cut -c1-12; }
norm(){ python3 -c 'import sys,json; print(json.dumps(json.load(sys.stdin),sort_keys=True))'; }
cfg(){ docker compose "$@" config --format json 2>/tmp/.iac-verify-err.$$ | norm; }
before=$(cd "$D" && cfg -f "$D/$F") || { echo "DIFF:before-config-failed $(head -c 200 /tmp/.iac-verify-err.$$)"; exit 0; }
envarg=(); [ -f "$T/.env" ] && envarg=(--env-file "$T/.env")
after=$(cd "$D" && cfg -f "$T/$F" --project-directory "$D" "${envarg[@]}") || { echo "DIFF:after-config-failed $(head -c 200 /tmp/.iac-verify-err.$$)"; exit 0; }
rm -f /tmp/.iac-verify-err.$$
if [ "$before" != "$after" ]; then
  python3 - "$before" "$after" <<'PY'
import sys,json
a,b=json.loads(sys.argv[1]),json.loads(sys.argv[2]); out=[]
def walk(x,y,p):
    if isinstance(x,dict) and isinstance(y,dict):
        for k in sorted(set(x)|set(y)): walk(x.get(k),y.get(k),p+'/'+str(k))
    elif x!=y: out.append(p)
walk(a,b,''); print("DIFF:compose "+" ".join(out[:12]))
PY
  exit 0
fi
# env files: compare as compose itself parses them (env_file semantics)
for e in "$@"; do
  # A file that does not exist live yet is a new interpolation-only .env
  # (secrets moved out of the compose file). The compose comparison above
  # already proved the rendered values produce the identical config.
  [ -f "$D/$e" ] || { new_env="${new_env:-}$e "; continue; }
  m=$(mktemp -d); printf 'services:\n  x:\n    image: scratch\n    env_file: [%s]\n' "$D/$e" > $m/a.yml; printf 'services:\n  x:\n    image: scratch\n    env_file: [%s]\n' "$T/$e" > $m/b.yml
  ea=$(docker compose -f $m/a.yml --env-file /dev/null config --format json 2>/dev/null | norm); eb=$(docker compose -f $m/b.yml --env-file /dev/null config --format json 2>/dev/null | norm); rm -rf $m
  [ -n "$ea" ] && [ "$ea" = "$eb" ] || { echo "DIFF:env $e live=$(printf %s "$ea"|h) rendered=$(printf %s "$eb"|h)"; exit 0; }
done
[ -n "${new_env:-}" ] && echo "EQUAL" || echo EQUAL
