#!/bin/bash
# Homelab weekly DB + config backup -> n4000 HDD /mnt/usb/homelab-backup/weekly/<date>/ (keep 4)
# stdout: exactly "OK" on success (deterministic, for cron monitor gating); failure lines otherwise. Full log in ~/.hermes/cache/backup-logs/.
# Source of truth: Yeoun-Homelab-IaC backup/ -> deployed to arm ~/.hermes/scripts/ by playbooks/backup_job.yml. Do not edit on arm.
# rev 2026-10-23: + non-DB config/user-file tarballs (arm-config, arm-work, arm-hermes(+state), n4000-config, n4200-config).
# rev 2026-10-18: pipefail on remote pipelines (rc was masked), nextcloud-db SKIP when stopped,
#   + geometrikks-db, + SQLite app DBs (kuma config-only, NPM x2, beszel, navidrome, filebrowser, jellyfin, open-webui, vikunja)
set -o pipefail
TS=$(date +%Y%m%d-%H%M)
LOGD=/home/ubuntu/.hermes/cache/backup-logs; mkdir -p $LOGD; LOG=$LOGD/weekly-$TS.log
W=/mnt/usb/homelab-backup/weekly; D=$W/$TS
SNAP=/home/ubuntu/.hermes/scripts/_sqlite_snap.py
S="ssh -o ConnectTimeout=10 -o ServerAliveInterval=30 -o BatchMode=yes"
n4(){ timeout 3600 $S n4000 "$@"; }
# n4b: run a pipeline on n4000 under bash -o pipefail so a failing docker exec is not masked by gzip/cat
n4b(){ n4 "bash -o pipefail -c $(printf '%q' "$1")"; }
put(){ n4 "sudo -n sh -c 'cat > \"$1\"'"; }
FAIL=()
step(){ local name=$1; shift; echo "== [$name] $(date +%T)" >>$LOG; "$@" >>$LOG 2>&1; local rc=$?; echo "== [$name] rc=$rc" >>$LOG; [ $rc -eq 0 ] || FAIL+=("$name rc=$rc"); }

n4 "mountpoint -q /mnt/usb && sudo -n mkdir -p $D && sudo -n chown root:root /mnt/usb/homelab-backup $W && sudo -n chmod 700 /mnt/usb/homelab-backup $W $D" >>$LOG 2>&1 || { echo "FAIL: n4000 HDD not mounted/reachable (see $LOG)"; exit 0; }

# ---- arm-hosted DBs
pg_main(){ docker exec postgres-main sh -c 'pg_dumpall -U "$POSTGRES_USER"' | gzip -6 | put "$D/arm-postgres-main.sql.gz"; }
mysql_school(){ docker exec mysql-school sh -c 'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases --single-transaction --routines --events --triggers 2>/dev/null' | gzip -6 | put "$D/arm-mysql-school.sql.gz"; }
vaultwarden(){ local T=$(mktemp -d); sudo -n python3 -c "import sqlite3,sys; s=sqlite3.connect('/home/ubuntu/docker_volumes/vaultwarden/data/db.sqlite3'); d=sqlite3.connect('$T/db.sqlite3'); s.backup(d); d.close(); c=sqlite3.connect('$T/db.sqlite3'); r=c.execute('pragma integrity_check').fetchone()[0]; print('vw integrity',r); sys.exit(0 if r=='ok' else 3)" || { sudo -n rm -rf $T; return 3; }
  sudo -n tar -C /home/ubuntu/docker_volumes/vaultwarden --exclude='data/db.sqlite3*' --exclude='data/icon_cache' -czf - data docker-compose.yml -C $T db.sqlite3 | put "$D/arm-vaultwarden.tar.gz"; local r=$?; sudo -n rm -rf $T; return $r; }
sqlite_arm(){ sudo -n python3 $SNAP \
  'kuma=/home/ubuntu/docker_volumes/uptimekuma/data/kuma.db|heartbeat' \
  'npm-arm=/home/ubuntu/docker_volumes/nginx-proxy-manager/data/database.sqlite' \
  'beszel=/home/ubuntu/docker_volumes/monitoring/beszel_data/data.db' | put "$D/arm-sqlite-apps.tar.gz"; }
step postgres-main pg_main
step mysql-school mysql_school
step vaultwarden vaultwarden
step sqlite-arm sqlite_arm

# ---- n4000-local DBs (dumped on n4000, written straight to its HDD)
IMMICH_CMD="docker exec immich_postgres pg_dumpall --clean --if-exists -U postgres | gzip -6 | sudo -n sh -c 'cat > $D/n4000-immich.sql.gz'"
GEO_CMD="docker exec geometrikks-db sh -c 'pg_dump -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" --clean --if-exists' | gzip -6 | sudo -n sh -c 'cat > $D/n4000-geometrikks.sql.gz'"
NC_CMD="docker exec nextcloud-db sh -c 'mariadb-dump -uroot -p\"\$MARIADB_ROOT_PASSWORD\" --single-transaction --default-character-set=utf8mb4 --routines --triggers --events nextcloud' | gzip -6 | sudo -n sh -c 'cat > $D/n4000-nextcloud.sql.gz'"
nextcloud_db(){ # intentionally-stopped stack => SKIP (logged), not FAIL. A running-but-broken dump still FAILs via pipefail+verify.
  if [ "$(n4 "docker inspect -f '{{.State.Running}}' nextcloud-db 2>/dev/null")" != "true" ]; then echo "SKIP nextcloud-db: container not running"; return 0; fi
  n4b "$NC_CMD"; }
sqlite_n4000(){ n4b "sudo -n python3 - 'navidrome=/home/yeoun/docker_volumes/navidrome/navidrome_data/navidrome.db' 'npm-n4000=/home/yeoun/docker_volumes/nginx-proxy-manager/data/database.sqlite' 'filebrowser=/home/yeoun/docker_volumes/filebrowser-quantum/data/filebrowser.sqlite' | sudo -n sh -c 'cat > $D/n4000-sqlite-apps.tar.gz'" < $SNAP; }
step immich-db n4b "$IMMICH_CMD"
step geometrikks-db n4b "$GEO_CMD"
step nextcloud-db nextcloud_db
step sqlite-n4000 sqlite_n4000

# ---- n4200 SQLite apps (snapshotted on n4200, streamed to n4000 HDD)
sqlite_n4200(){ timeout 900 ssh -o ConnectTimeout=10 -o BatchMode=yes n4200 "sudo -n python3 - 'jellyfin=/home/yeoun/docker_volumes/jellyfin/jellyfin/config/data/jellyfin.db' 'open-webui=/home/yeoun/docker_volumes/open-webui/data/webui.db' 'open-webui-chroma=/home/yeoun/docker_volumes/open-webui/data/vector_db/chroma.sqlite3' 'vikunja=/home/yeoun/docker_volumes/vikunja/db/vikunja.db'" < $SNAP | put "$D/n4200-sqlite-apps.tar.gz"; }
step sqlite-n4200 sqlite_n4200

# ---- non-DB config + user files (rev 2026-10-23). DB files are excluded here because the steps above
# snapshot them consistently. GNU tar rc 1 = "file changed while reading" on live dirs -> warning, not failure.
tarok(){ "$@"; local r=$?; [ $r -le 1 ]; }
# Unquoted globs in CX must not be expanded by a shell: arm uses the CXA array; remote shells run with noglob (set -f / bash -f).
CX="--warning=no-file-changed --exclude=*.sqlite* --exclude=*.sqlite3* --exclude=*.db --exclude=*.db-wal --exclude=*.db-shm --exclude=logs --exclude=log --exclude=*.log --exclude=cache --exclude=node_modules --exclude=__pycache__ --exclude=.iac-backup"
read -r -a CXA <<< "$CX"   # word-split only; read does not glob
arm_config(){ tarok sudo -n tar -C /home/ubuntu "${CXA[@]}" -czf - \
  docker_volumes/adguardhome-secondary/conf docker_volumes/authentik/media docker_volumes/authentik/certs docker_volumes/authentik/custom-templates \
  docker_volumes/monitoring/tapmap-data docker_volumes/nginx-proxy-manager docker_volumes/syncthing_arm/config docker_volumes/transmission/config \
  docker_volumes/rhwp-studio docker_volumes/BOJWorkspace/workspace docker_volumes/mc-forward scripts \
  -C / path/to/code-server/config | put "$D/arm-config.tar.gz"; }
arm_work(){ tarok tar -C /home/ubuntu --warning=no-file-changed --exclude=node_modules --exclude=.venv --exclude=venv --exclude=__pycache__ \
  --exclude=ansible_collections --exclude='*.ckpt' --exclude='*.pt' --exclude='*.pth' --exclude='*.safetensors' --exclude='*.onnx' -czf - work | put "$D/arm-work.tar.gz"; }
arm_hermes(){ local T=$(mktemp -d); local H=/home/ubuntu/.hermes
  git -C $H/hermes-agent rev-parse HEAD > $T/hermes-agent.HEAD 2>&1; git -C $H/hermes-agent status --porcelain > $T/hermes-agent.status 2>&1
  git -C $H/hermes-agent diff HEAD > $T/hermes-agent-local.patch 2>&1
  tarok tar -C $H --warning=no-file-changed --exclude=./hermes-agent --exclude=./tools --exclude=./installs --exclude=./checkpoints --exclude=./lsp \
    --exclude=./bin --exclude=./cache --exclude=./audio_cache --exclude=./logs --exclude='./state.db*' --exclude=node_modules --exclude=__pycache__ \
    --exclude=venv --exclude=.venv -czf - . -C $T hermes-agent.HEAD hermes-agent.status hermes-agent-local.patch | put "$D/arm-hermes.tar.gz"; local r=$?; rm -rf $T; return $r; }
arm_hermes_state(){ python3 $SNAP 'hermes-state=/home/ubuntu/.hermes/state.db' | put "$D/arm-hermes-state.tar.gz"; }
N4CFG="set -f; { sudo -n tar -C /home/yeoun $CX -czf - docker_volumes/adguardhome/conf docker_volumes/nginx-proxy-manager docker_volumes/navidrome/navidrome_data docker_volumes/syncthing/config docker_volumes/moa-monitoring docker_volumes/cloudflared docs work scripts ysvpn-test mc-offload-prune.sh; r=\$?; [ \$r -le 1 ]; } | sudo -n sh -c 'cat > $D/n4000-config.tar.gz'"
n4200_config(){ timeout 1800 ssh -o ConnectTimeout=10 -o BatchMode=yes n4200 "bash -f -o pipefail -c '{ sudo -n tar -C /home/yeoun $CX --exclude=docker_volumes/jellyfin/jellyfin/config/metadata --exclude=dist --exclude=.astro -czf - docker_volumes/home-assistant/config docker_volumes/home-assistant/matter-data docker_volumes/homepage/config docker_volumes/jellyfin/jellyfin/config docker_volumes/open-webui/data docker_volumes/vikunja/files docker_volumes/vikunja/config.yml docker_volumes/syncthing_n4200/config services/astro-blog; r=\$?; [ \$r -le 1 ]; }'" | put "$D/n4200-config.tar.gz"; }
step arm-config arm_config
step arm-work arm_work
step arm-hermes arm_hermes
step arm-hermes-state arm_hermes_state
step n4000-config n4b "$N4CFG"
step n4200-config n4200_config

# ---- verify + checksums + retention (keep newest 4)
VERIFY=$(cat <<'EOS'
D=$1; W=$2
cd $D || exit 1; bad=0
for f in *.gz; do gzip -t $f || { echo BAD_GZIP $f; bad=1; }; done
for f in *.tar.gz; do tar -tzf $f >/dev/null || { echo BAD_TAR $f; bad=1; }; done
for f in *postgres*.sql.gz *immich*.sql.gz; do [ -e "$f" ] || continue; zcat $f | tail -c 400 | grep -q "cluster dump complete" || { echo NO_END $f; bad=1; }; done
for f in *geometrikks*.sql.gz; do [ -e "$f" ] || continue; zcat $f | tail -c 400 | grep -q "database dump complete" || { echo NO_END $f; bad=1; }; done
for f in *mysql*.sql.gz *nextcloud*.sql.gz; do [ -e "$f" ] || continue; zcat $f | tail -c 300 | grep -q "Dump completed" || { echo NO_END $f; bad=1; }; done
# every expected artifact must exist (nextcloud optional: SKIP when stack stopped)
for f in arm-postgres-main.sql.gz arm-mysql-school.sql.gz arm-vaultwarden.tar.gz arm-sqlite-apps.tar.gz n4000-immich.sql.gz n4000-geometrikks.sql.gz n4000-sqlite-apps.tar.gz n4200-sqlite-apps.tar.gz arm-config.tar.gz arm-work.tar.gz arm-hermes.tar.gz arm-hermes-state.tar.gz n4000-config.tar.gz n4200-config.tar.gz; do [ -e "$f" ] || { echo MISSING $f; bad=1; }; done
for f in *.gz; do s=$(stat -c %s $f); [ $s -gt 1000 ] || { echo TOO_SMALL $f $s; bad=1; }; done
sha256sum * > SHA256SUMS
ls -1d $W/2* | sort | head -n -4 | xargs -r rm -rf
du -sh $D $W >&2; exit $bad
EOS
)
V=$(echo "$VERIFY" | n4 "sudo -n bash -s -- $D $W" 2>>$LOG); rc=$?
echo "$V" >>$LOG
[ $rc -eq 0 ] || FAIL+=("verify: $(echo $V | tr '\n' ' ')")
if [ ${#FAIL[@]} -eq 0 ]; then echo OK; else printf 'FAIL: %s\n' "${FAIL[@]}"; echo "log: $LOG"; fi
