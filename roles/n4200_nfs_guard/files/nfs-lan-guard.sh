#!/bin/bash
# n4200 /mnt/nfs: n4000 LAN(n4000-lan) 우선, 실패 시 Tailscale(n4000)로 자동 폴백. 5분마다 cron(root).
# 재생 중(jellyfin이 /media 파일을 열고 있음)이면 멀쩡한 마운트는 바꾸지 않는다.
# 마운트를 바꾸면 jellyfin 컨테이너를 재시작한다(바인드가 옛 마운트를 붙잡기 때문).
MP=/mnt/nfs; LAN=n4000-lan; TS=n4000; OPT=soft,timeo=600,retrans=2,_netdev
LOG=/var/log/nfs-lan-guard.log
log(){ echo "$(date -Is) $*" >> $LOG; }
cur=$(findmnt -n -o SOURCE $MP 2>/dev/null)
healthy(){ timeout 15 stat -t $MP/media >/dev/null 2>&1; }
lan_up(){ timeout 3 bash -c "</dev/tcp/$LAN/2049" 2>/dev/null; }
busy(){ pgrep -f jellyfin-ffmpeg >/dev/null && return 0; p=$(docker inspect -f '{{.State.Pid}}' jellyfin 2>/dev/null); [ -n "$p" ] && [ "$p" != 0 ] && ls -l /proc/$p/fd 2>/dev/null | grep -q ' /media/'; }
onlan(){ ss -tn | awk '/:2049 /{print $5}' | grep -q "^$(getent hosts $LAN | cut -d" " -f1):2049$"; }
if onlan && healthy; then exit 0; fi
if [ -n "$cur" ] && healthy; then
  lan_up || exit 0          # Tailscale 마운트 정상 + LAN 불가 -> 유지
  busy && exit 0            # LAN 복귀 가능하지만 재생 중 -> 다음 주기
fi
# NFSv4.1+는 같은 서버면 기존 전송(TCP)을 재사용한다 -> 옛 마운트를 완전히 놓아야 새 경로로 붙는다
# 2026-10-26: Jellyfin은 lab으로 이전, n4200 컨테이너는 정지 보존 -> 원래 실행 중이었을 때만 다시 켠다
WAS=$(docker inspect -f "{{.State.Running}}" jellyfin 2>/dev/null || echo false)
docker stop -t 20 jellyfin >/dev/null 2>&1
if [ -n "$cur" ]; then umount $MP 2>>$LOG || umount -f $MP 2>>$LOG || umount -l $MP; fi
for i in 1 2 3 4 5 6 7 8 9 10; do ss -tn | grep -q ':2049 ' || break; sleep 2; done
if lan_up && mount -t nfs -o $OPT $LAN:/mnt/usb $MP 2>>$LOG && healthy; then new=$LAN
elif mount -t nfs -o $OPT $TS:/mnt/usb $MP 2>>$LOG && healthy; then new=$TS
else log "FAIL: no NFS (was ${cur:-none})"; [ "$WAS" = true ] && docker start jellyfin >/dev/null 2>&1; exit 1; fi
log "remount ${cur:-none} -> $new:/mnt/usb conn=$(ss -tn | awk '/:2049 /{print $5}' | head -1)"
[ "$WAS" = true ] && docker start jellyfin >/dev/null 2>&1 && log "jellyfin started"
