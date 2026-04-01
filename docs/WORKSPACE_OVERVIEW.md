# Ansible 워크스페이스 개요

## Role 기반 디렉터리 트리

```
ansibleWorkspace/
├── ansible.cfg                    # inventory, vault_password_file, SSH 옵션
├── inventory.ini                  # 호스트 그룹 (oci_nodes, home_nodes, tmp_nodes)
├── site.yml                       # 메인 플레이북 (태그: wireguard, nfs, deploy)
│
├── group_vars/
│   ├── all.yml                   # 공통 변수 (WG 기반 NFS 경로/대역/서버 IP)
│   └── secrets.yml               # 🔐 Ansible Vault 암호화 (아래 참조)
│
├── playbooks/
│   ├── cleanup.yml               # tmp_nodes 정리 (불필요 서비스 디렉터리 삭제)
│   ├── docker_stop_all.yml
│   └── docker_start_all.yml
│
└── roles/
    │
    ├── wireguard/                # VPN (WireGuard) 설치·설정
    │   ├── tasks/
    │   │   ├── main.yml          # → docker_stop → wireguard_setup → docker_start
    │   │   ├── wireguard_setup.yml   # apt, 키 생성, slurp, template(wg0.conf), resolv.conf
    │   │   ├── docker_stop_all.yml
    │   │   └── docker_start_all.yml
    │   └── templates/            # (wg0.conf.j2는 common과 공유 또는 동일 내용)
    │
    ├── nfs_setup/                # NFS 서버(n4000) / 클라이언트(나머지) 설정
    │   ├── tasks/
    │   │   ├── main.yml
    │   │   └── nfs_setup.yml     # apt, mount, template(exports.j2), service, fstab
    │   └── templates/
    │       └── exports.j2        # wg_nfs_export_path + wg_vpn_network_cidr(rw,sync,...)
    │
    ├── common/                   # 공통 시스템·Docker·보안 (site.yml에서 주석 처리됨)
    │   ├── tasks/
    │   │   ├── main.yml          # base → docker → security (wireguard.yml 참조는 별도 역할로 이전됨)
    │   │   ├── base.yml          # timezone, sysctl(ip_forward), rsync, resolv.conf
    │   │   ├── docker.yml
    │   │   └── security.yml
    │   ├── templates/
    │   │   └── wg0.conf.j2       # WireGuard [Interface]/[Peer] Jinja2 템플릿
    │   └── handlers/
    │       └── main.yml
    │
    ├── deploy_services/          # NFS 기반 Docker Compose 배포
    │   └── tasks/
    │       ├── main.yml          # sync_volumes_from_hub → (deploy_services 주석)
    │       ├── sync_volumes_from_hub.yml   # rsync N4000 → 로컬
    │       └── deploy_services.yml         # stat, file, community.docker.docker_compose_v2
    │
    └── cron_cli_to_hub/         # NFS/동기화 관련 cron (import_tasks: cron_cli_to_hub.yml)
        └── tasks/
            └── main.yml
```

---

## 🔐 Ansible Vault로 암호화된 항목

| 파일 | 용도 |
|------|------|
| **group_vars/secrets.yml** | 전체 파일이 `$ANSIBLE_VAULT;1.1;AES256` 로 암호화됨 |

**암호화된 내용 (복호화 시 포함되는 것):**
- `ansible_ssh_private_key_file` — SSH 개인키 경로
- `hub_info` — Hub 이름, public_key, endpoint
- `all_peers` — WireGuard Peer 목록 (name, ip, pub)
- `host_specific` — 호스트별 `endpoint`, `public_key`, `private_key`, `address`, `public_interface` (arm, n4000, n4200)
  - NOTE: vps 노드는 성능/회선 이슈로 현재 구성에서 제거됨

**복호화:** `ansible-playbook ...` 실행 시 `ansible.cfg`의 `vault_password_file = .vault_pass` 로 자동 사용 (`.vault_pass`는 `.gitignore`로 저장소 제외).

---

## 핵심 기술 나열

### 인프라·자동화
- **Ansible** — 설정 자동화, 플레이북·역할 기반 구조
- **Ansible Vault** — secrets.yml 전체 암호화 (AES256)
- **Inventory** — INI 형식, 그룹(oci_nodes, home_nodes, tmp_nodes), 호스트 변수

### 네트워크·VPN
- **WireGuard** — 메시 VPN, Hub(n4000) / Worker(arm, n4200) 토폴로지
  - NOTE: vps 노드는 성능/회선 이슈로 현재 구성에서 제거됨
- **iptables** — Hub에서 FORWARD/NAT (MASQUERADE)
- **resolvectl** — Worker 노드 DNS (wg 인터페이스용)

### 스토리지·파일
- **NFS** — n4000이 서버, 나머지는 클라이언트 (wg_nfs_export_path 공유)
- **rsync** — N4000 → 각 노드 서비스 디렉터리 동기화 (sync_volumes_from_hub)
- **Jinja2** — wg0.conf.j2, exports.j2 템플릿

### 컨테이너·배포
- **Docker** — 컨테이너 런타임
- **Docker Compose V2** — `community.docker.docker_compose_v2` (project_src, pull, remove_orphans)
- **역할별 서비스:** nextcloud, immich-app, syncthing, vaultwarden, adguardhome, authentik, code-server, onlyoffice, uptimekuma, nginx-proxy-manager, jellyfin, ghost, homepage, home-assistant 등

### 시스템
- **systemd** — service 모듈 (nfs-kernel-server, docker, systemd-resolved)
- **apt** — 패키지 설치 (wireguard, nfs-kernel-server, nfs-common, rsync, resolvconf 등)
- **sysctl** — net.ipv4.ip_forward
- **timezone** — Asia/Seoul
- **mount** — NFS 마운트/언마운트, fstab 관리
- **file** — 디렉터리/심볼릭링크 생성·삭제

### Ansible 모듈·기능
- **template** — wg0.conf, exports
- **slurp** — WireGuard 키 파일 읽기 (base64 디코딩 후 fact)
- **set_fact** / **host_specific** — 플레이북 초반에 호스트별 변수를 fact로 주입
- **stat** — 디렉터리 존재·mtime 검사 (안전 검사, rsync 조건)
- **copy** — resolv.conf 등 정적 파일
- **command** — wg genkey, rsync 호출
- **fail** — NFS 서비스 디렉터리 없을 때 배포 중단
- **tags** — wireguard, nfs, deploy 등 선택 실행
- **loop / loop_control** — 다중 서비스·다중 호스트 처리

### 보안·접근
- **SSH** — ControlMaster, ForwardAgent, pipelining (ansible.cfg)
- **become** — 권한 상승
- **host_key_checking = False** — SSH 호스트키 검사 비활성

### 기타
- **group_vars / host_specific** — 호스트별 변수를 한 파일(secrets)에 모아 fact로 적용
- **.gitignore** — .ansible, .stfolder, .legacy, .vault_pass, .DS_Store

---

## 플레이북 실행 흐름 (site.yml)

1. **모든 호스트** — `host_specific` 변수를 각 호스트 fact로 적용 (태그 없음, 항상 실행)
2. **모든 호스트** — `wireguard` 역할 (태그: wireguard)
3. **모든 호스트** — `nfs_setup` 역할 (태그: nfs)
4. **n4000** — deploy_services (nextcloud, immich-app, syncthing, vaultwarden, adguardhome 등)
5. **arm** — deploy_services (authentik, code-server, onlyoffice, uptimekuma, nginx-proxy-manager, jellyfin 등)
6. **n4200** — deploy_services (ghost, homepage, home-assistant)
7. ~~vps~~ — (제거됨) gateway 용도(legacy). 성능/회선 이슈로 현재 구성에서 제외

이 문서는 워크스페이스 구조와 핵심 기술을 한눈에 보기 위해 작성되었습니다.
