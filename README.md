# 🏠 Home Lab IaC

**WireGuard VPN + NFS + Docker Compose** 로 묶은 멀티노드 홈 인프라를 한 번에 굴리는 Ansible 워크스페이스.

---

## 한눈에 보기

| 구분 | 노드 | 역할 |
|------|------|------|
| **OCI** | `arm` | 컴퓨팅 (Authentik, Code-Server, Jellyfin, NPM…) |
| **Home** | `n4000` | **Hub** — NFS 서버, WireGuard 허브, 데이터(Nextcloud, Immich, Syncthing…) |
| **Home** | `n4200` | 엣지 (Ghost, Homepage, Home Assistant) |

→ **site.yml**를 통해 VPN·NFS·서비스 배포까지 가능합니다.

---

## 요구사항

- **Ansible** 2.14+ (컬렉션: `community.docker`)
- 대상 호스트: **Ubuntu** (apt), SSH 접근 가능
- Vault 비밀번호 파일: `.vault_pass` (로컬에만 두고 `.gitignore` 유지)

```bash
# 컬렉션 설치 (Docker Compose V2 사용 시)
ansible-galaxy collection install community.docker
```

---

## Quick Start

```bash
# 전체 실행 (host_specific 로드 → wireguard → nfs → deploy)
ansible-playbook site.yml

# 태그로 나눠서 실행
ansible-playbook site.yml --tags wireguard
ansible-playbook site.yml --tags nfs
ansible-playbook site.yml --tags deploy

# 특정 노드만
ansible-playbook site.yml --limit n4000,n4200
```

**최초 1회:** `group_vars/secrets.yml` 이 Vault 암호화되어 있으므로, `ansible.cfg`에 설정한 `vault_password_file`(예: `.vault_pass`)이 있어야 합니다.

---

## 프로젝트 구조

```
.
├── ansible.cfg          # inventory, vault_password_file, SSH
├── inventory.ini        # oci_nodes, home_nodes, tmp_nodes
├── site.yml             # 메인 플레이북 (wireguard → nfs → deploy)
├── group_vars/
│   ├── all.yml          # 공통 변수 (경로, VPN 대역, NFS 서버 IP)
│   └── secrets.yml      # 🔐 Vault 암호화 (비밀/키/호스트별 설정)
├── playbooks/           # cleanup, docker_stop_all, docker_start_all
├── roles/
│   ├── wireguard/       # VPN 구축 (키 생성, wg0.conf, resolv)
│   ├── nfs_setup/       # NFS 서버(n4000) / 클라이언트
│   ├── common/          # base, docker, security + wg0.conf.j2
│   ├── deploy_services/ # NFS 동기화(rsync) + docker_compose_v2
│   └── cron_cli_to_hub/ # cron 관련
└── docs/
    └── WORKSPACE_OVERVIEW.md   # 역할 트리, 기술 스택, Vault 상세
```

---

## Roles 한 줄 요약

| Role | 하는 일 |
|------|----------|
| **wireguard** | WireGuard 설치·키 생성·설정, Docker 잠시 중지 후 적용 |
| **nfs_setup** | n4000 = NFS 서버(exports), 나머지 = NFS 클라이언트(mount/fstab) |
| **deploy_services** | N4000에서 rsync로 볼륨 동기화 → `docker compose` 로 서비스 기동 |
| **common** | timezone, ip_forward, rsync, resolv, Docker 등 (site.yml에서 선택 사용) |
| **cron_cli_to_hub** | NFS/동기화용 cron |

---

## 🔐 보안 (Vault)

- **`group_vars/secrets.yml`** → **전체 파일**이 `Ansible Vault`(AES256)로 암호화되어 있습니다.
- 안에 들어가는 것: SSH 키 경로, `hub_info`, `all_peers`, **host_specific**(endpoint, public_key, private_key, address, public_interface).
- 복호화는 `ansible.cfg`의 `vault_password_file`(예: `.vault_pass`)로 자동적용됩니다.
- **`.vault_pass`는 반드시 `.gitignore`에 두고 저장소에 올리지 말 것.**

---

## 기술 스택

**인프라·자동화**  
Ansible · Ansible Vault · Inventory(INI) · Tags · group_vars / host_specific

**네트워크·VPN**  
WireGuard · iptables(MASQUERADE) · resolvectl

**스토리지**  
NFS · rsync · Jinja2(wg0.conf, exports)

**컨테이너**  
Docker · Docker Compose V2 (`community.docker.docker_compose_v2`)

**시스템**  
systemd · apt · sysctl(ip_forward) · timezone(Asia/Seoul) · mount/fstab

자세한 역할 트리·모듈·플로우는 **[docs/WORKSPACE_OVERVIEW.md](docs/WORKSPACE_OVERVIEW.md)** 참고.

---

## 라이선스 / 기타

- 이 레포는 홈랩 자동화용 템플릿/참고용으로 두었습니다.
- 실제 IP·호스트명·비밀값은 `inventory.ini`와 Vault로 관리하며, 공개 시 민감 정보 제외 여부를 꼭 확인하세요.
