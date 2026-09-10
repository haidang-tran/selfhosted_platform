> Dự án: máy chủ Ubuntu tự quản (self-hosted) chạy đồng thời **môi trường Staging** và **Production** cho ứng dụng web (frontend + api + backend + MySQL), kèm **stack giám sát** (Prometheus / Grafana / exporters) và **lớp bảo mật** (Tailscale, hardening theo CIS, Wazuh).
> 

> 
> 

> Tài liệu này đi kèm bản vẽ `Ubuntu_server.drawio` — **Page-1** là bản gốc, **Page-2** là kiến trúc triển khai đã chuẩn hoá. Tham chiếu bổ sung: trang *Hướng dẫn Hardening Linux*.
> 

---

## 1. Mục tiêu & phạm vi

| Mục tiêu | Tiêu chí hoàn thành |
| --- | --- |
| Chạy Production web app ổn định | Truy cập qua `https://prod.example.com`, uptime ≥ 99.5% |
| Có Staging tách biệt để test trước khi lên prod | `https://staging.example.com`, dữ liệu/DB riêng, deploy tự động từ nhánh `develop` |
| Giám sát đầy đủ hạ tầng + ứng dụng | Grafana có dashboard host / container / MySQL / blackbox; có cảnh báo |
| Bảo mật ở mức "hardened" (CIS Level 1 + MAC + HIDS) | Lynis score ≥ 70; SSH chỉ qua Tailscale; Wazuh agent báo về manager |
| Sao lưu & phục hồi được | Backup DB + volume hằng ngày, off-site; đã test restore |
| Triển khai lặp lại được | Toàn bộ bằng `docker compose`  • script/Ansible, có tài liệu |

**Ngoài phạm vi (giai đoạn 1):** Kubernetes, multi-node HA, auto-scaling.

---

## 2. Kiến trúc tổng quan (xem Page-2 của file draw.io)

```
Admin ──(Tailscale VPN)──┐
                         ▼
Internet ──(80/443)──►  UFW/nftables ──►  Nginx reverse proxy (host, TLS Let's Encrypt)
                                             ├─► Production stack   (docker compose, prod-net)
                                             │      frontend · api · backend · MySQL
                                             ├─► Staging stack      (docker compose, stg-net)
                                             │      nginx · frontend · api · backend · MySQL
                                             └─► Grafana

Monitoring stack (monitor-net):
   node_exporter · mysqld_exporter · blackbox_exporter · cAdvisor ──► Prometheus ──► Grafana
                                                                           └──► Alertmanager ──► Telegram/Email

Security:
   Wazuh agent ──(tailnet)──► Wazuh Manager/SIEM (VM riêng)
   auditd · AIDE · fail2ban · AppArmor enforce · unattended-upgrades

CI/CD:
   GitHub Actions ─► build image ─► push Registry (GHCR) ─► SSH (qua Tailscale) ─► compose pull & up

Backup:
   restic (DB dump + volumes) ─► S3 / Backblaze B2, cron hằng ngày
```

### Nguyên tắc thiết kế

- **Một máy chủ, nhiều môi trường tách biệt bằng Docker network + compose project riêng.** Staging và Production không dùng chung DB, volume, network.
- **Reverse proxy Nginx chạy trên host** (không trong container) để quản lý TLS tập trung và định tuyến theo domain.
- **Quản trị chỉ qua Tailscale** — cổng 22 không mở ra Internet.
- **Mọi thứ khai báo bằng code** (compose files, `.env` mẫu, Ansible playbook / script bash), lưu trong git repo hạ tầng.

---

## 3. Yêu cầu hạ tầng

| Hạng mục | Khuyến nghị tối thiểu | Ghi chú |
| --- | --- | --- |
| CPU | 4 vCPU | Staging + Prod + monitoring |
| RAM | 8 GB (khuyến nghị 16 GB) | Prometheus + 2 MySQL khá ngốn RAM |
| Disk | 100 GB SSD (tách `/var`, `/var/log`, `/var/log/audit` nếu được) | Prometheus retention 15–30 ngày |
| OS | Ubuntu Server 24.04 LTS (hoặc 22.04 LTS) | Minimal install, không GUI |
| Mạng | IPv4 public tĩnh, DNS trỏ `prod`, `staging`, `grafana` về IP |  |
| Out-of-band | Console/VNC của nhà cung cấp | Tránh tự khoá mình khi siết firewall |

**Tài khoản/dịch vụ cần chuẩn bị trước:** tài khoản Tailscale (+ auth key), domain + quyền quản lý DNS, GitHub repo + GHCR token, tài khoản S3/B2 cho backup, (tuỳ chọn) VM cho Wazuh Manager, bot Telegram cho cảnh báo.

---

## 4. Kế hoạch triển khai theo giai đoạn

### Giai đoạn 0 — Chuẩn bị (0.5 ngày)

- [ ]  Tạo repo git `infra/` chứa: `compose/`, `nginx/`, `ansible/` (hoặc `scripts/`), `docs/`.
- [ ]  Provision server, ghi lại IP, tạo user thường `deploy` (không dùng root), thêm SSH key.
- [ ]  Trỏ DNS: `prod.example.com`, `staging.example.com`, `grafana.example.com` → IP server.
- [ ]  Snapshot ban đầu của VPS.

### Giai đoạn 1 — Cài đặt nền & hardening OS (1 ngày)

Thứ tự an toàn: **cài Tailscale trước → xác minh SSH qua tailnet hoạt động → mới siết firewall.**

1. `apt update && apt full-upgrade`, đặt hostname, timezone, NTP (`systemd-timesyncd`/`chrony`).
2. Cài Tailscale: `curl -fsSL https://tailscale.com/install.sh | sh` → `tailscale up --ssh` (hoặc auth key). Ghi lại IP tailnet.
3. Hardening SSH (`/etc/ssh/sshd_config.d/99-hardening.conf`): `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`, `MaxAuthTries 3`, `AllowUsers deploy`, `X11Forwarding no`, `AllowTcpForwarding no`, `ClientAliveInterval 300`, `ClientAliveCountMax 2`.
4. Firewall UFW: `ufw default deny incoming`; `ufw default allow outgoing`; `ufw allow in on tailscale0 to any port 22 proto tcp`; `ufw allow 80/tcp`; `ufw allow 443/tcp`; `ufw enable`.
5. `fail2ban` (jail cho sshd, nginx-http-auth, nginx-limit-req).
6. `unattended-upgrades` bật auto security update.
7. Kernel/sysctl hardening (`/etc/sysctl.d/60-hardening.conf`) — theo mục 3.4 của trang Hardening.
8. `auditd` + ruleset CIS; `AIDE` init baseline + cron kiểm tra hằng ngày.
9. AppArmor: đảm bảo `enforcing`, không disable.
10. `umask 027`, chính sách mật khẩu (`pam_pwquality`, `pam_faillock`).
11. Chạy **Lynis** (`lynis audit system`) → lưu báo cáo baseline vào `docs/`.

**Nghiệm thu GĐ1:** SSH chỉ vào được qua Tailscale; `ufw status` đúng; Lynis score ghi nhận; reboot vẫn truy cập được.

### Giai đoạn 2 — Docker & reverse proxy (0.5 ngày)

1. Cài Docker Engine + compose plugin (repo chính thức của Docker).
2. Thêm user `deploy` vào group `docker` (hoặc dùng rootless — cân nhắc).
3. Cấu hình `daemon.json`: `log-driver: json-file` + `max-size`, `live-restore: true`, địa chỉ pool mạng.
4. Tạo Docker networks: `prod-net`, `stg-net`, `monitor-net`.
5. Cài Nginx trên host + `certbot` (plugin nginx).
6. Lấy chứng chỉ: `certbot --nginx -d prod.example.com -d staging.example.com -d grafana.example.com`.
7. Cấu hình vhost Nginx (trong `infra/nginx/`): prod → `proxy_pass http://127.0.0.1:8080` và `/api` → `127.0.0.1:8081`; staging → `127.0.0.1:9080`; grafana → `127.0.0.1:3000` (auth cơ bản hoặc chỉ tailnet). Header bảo mật: HSTS, `X-Content-Type-Options`, `X-Frame-Options`, CSP cơ bản; bật `limit_req`.

**Nghiệm thu GĐ2:** `curl -I https://prod.example.com` trả 502 (chưa có app) nhưng TLS hợp lệ; auto-renew certbot đã bật (`systemctl list-timers`).

### Giai đoạn 3 — Triển khai ứng dụng Staging (1 ngày)

1. `infra/compose/staging/docker-compose.yml`: services `nginx`, `frontend`, `api`, `backend`, `mysql`. `mysql`: image `mysql:8.0`, volume `stg-mysql-data`, `env_file`, healthcheck, **không** publish port ra ngoài. `frontend`/`api`: publish `127.0.0.1:9080`/`127.0.0.1:9081`. Đặt `restart: unless-stopped`, `mem_limit`, `logging` giới hạn.
2. Quản lý secret: `.env` không commit; commit `.env.example`. Cân nhắc `sops`/`age` hoặc Docker secrets.
3. Khởi tạo schema DB + seed dữ liệu test.
4. `docker compose -p staging up -d` → kiểm tra healthcheck.
5. Test end-to-end qua `https://staging.example.com`.

**Nghiệm thu GĐ3:** luồng người dùng chính chạy được trên staging; log sạch; `docker compose ps` all healthy.

### Giai đoạn 4 — Triển khai Production (0.5–1 ngày)

1. `infra/compose/production/docker-compose.yml` — tương tự staging, project `-p production`, network `prod-net`, volume `prod-mysql-data`, port `127.0.0.1:8080/8081`.
2. Import dữ liệu thật (nếu có) — có kế hoạch migration & rollback.
3. `docker compose -p production up -d`.
4. Kiểm tra qua `https://prod.example.com`; smoke test.
5. Bật backup (GĐ6) ngay sau khi prod có dữ liệu.

**Nghiệm thu GĐ4:** prod phục vụ traffic thật; TLS A trên SSL Labs; không có port DB/exporter lộ ra Internet (`ss -tlnp`, quét từ ngoài).

### Giai đoạn 5 — Monitoring stack (1 ngày)

1. `infra/compose/monitoring/docker-compose.yml`: `prometheus`, `alertmanager`, `grafana`, `node_exporter`, `cadvisor`, `blackbox_exporter`. `mysqld_exporter` chạy 2 instance (prod + staging) hoặc multi-target.
2. `prometheus.yml`: scrape jobs cho từng exporter; `blackbox` probe `https://prod.example.com`, `https://staging.example.com`.
3. `node_exporter`: chạy trên host (systemd) hoặc container với `--path.rootfs=/host`. Chỉ nghe trên `monitor-net`/localhost.
4. `mysqld_exporter`: user `exporter` trong MySQL với quyền tối thiểu (`PROCESS`, `REPLICATION CLIENT`, `SELECT`).
5. Grafana: provisioning datasource Prometheus + dashboard (Node Exporter Full `1860`, MySQL `7362`, cAdvisor `14282`, Blackbox `7587`). Đổi mật khẩu admin, tắt sign-up.
6. Alertmanager: route → Telegram bot / email. Alert rules: host down, disk > 85%, RAM > 90%, CPU load cao kéo dài, MySQL down, cert sắp hết hạn, blackbox probe fail, container restart loop.

**Nghiệm thu GĐ5:** Grafana truy cập qua `https://grafana.example.com`; tất cả target `UP` trong Prometheus; thử tắt 1 container → nhận alert.

### Giai đoạn 6 — Backup & khôi phục (0.5 ngày)

1. Script `infra/scripts/backup.sh`: `mysqldump --single-transaction` cho DB prod (và staging nếu cần) → file nén; `restic` backup thư mục dump + Docker volumes + `/etc` + `infra/` → repo S3/B2; giữ chính sách `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`.
2. `cron`/systemd timer: chạy 02:00 hằng ngày; gửi kết quả về Telegram.
3. **Test restore** trên staging: dựng lại DB từ bản backup mới nhất, đối chiếu.
4. Ghi `docs/runbook-restore.md`.

**Nghiệm thu GĐ6:** có ít nhất 1 lần restore thành công được ghi nhận; `restic snapshots` hiển thị bản mới mỗi ngày.

### Giai đoạn 7 — CI/CD (0.5–1 ngày)

1. GitHub Actions: `on: push` nhánh `develop` → build image → push GHCR tag `staging` → SSH vào server (qua Tailscale GitHub Action hoặc self-hosted runner trong tailnet) → `docker compose -p staging pull && up -d`. `on: push` tag `v*` hoặc nhánh `main` → tag `prod` → deploy production (có bước approval thủ công / environment protection).
2. Secret trong GitHub: `TS_AUTHKEY`, `GHCR_TOKEN`, `SSH_KEY`, `DEPLOY_HOST`.
3. Healthcheck sau deploy; nếu fail → tự `rollback` về image tag trước.

**Nghiệm thu GĐ7:** push `develop` tự lên staging < 5 phút; deploy prod cần approve; có đường rollback.

### Giai đoạn 8 — Bảo mật nâng cao & nghiệm thu (0.5 ngày)

- [ ]  Cài **Wazuh agent**, đăng ký với Wazuh Manager (VM riêng, kết nối qua tailnet). Bật FIM cho `/etc`, `/root`, `infra/`; module SCA (CIS Ubuntu).
- [ ]  Quét lại **Lynis** + **OpenSCAP (SSG, profile CIS L1)** → xử lý phần fail hợp lý, ghi lại exception.
- [ ]  Quét image bằng **Trivy** trong CI (fail nếu có CVE HIGH/CRITICAL chưa fix).
- [ ]  Rà soát: không port thừa (`ss -tlnp`), không container chạy `--privileged`, MySQL không lộ ra ngoài, secret không nằm trong image.
- [ ]  Diễn tập sự cố: mất 1 container, đầy disk, lộ SSH key.

---

## 5. Bảng phân rã container

| Môi trường | Container | Image gợi ý | Cổng (chỉ localhost) | Volume |
| --- | --- | --- | --- | --- |
| Production | nginx (proxy trên host) | nginx (apt) | 80/443 public | — |
| Production | frontend | app frontend | 127.0.0.1:8080 | — |
| Production | api | app api | 127.0.0.1:8081 | — |
| Production | backend/worker | app backend | — | — |
| Production | mysql | mysql:8.0 | (prod-net) | prod-mysql-data |
| Staging | nginx | nginx:alpine | 127.0.0.1:9080 | — |
| Staging | frontend / api / backend | như prod, tag staging | 127.0.0.1:9081 | — |
| Staging | mysql | mysql:8.0 | (stg-net) | stg-mysql-data |
| Monitoring | prometheus | prom/prometheus | 127.0.0.1:9090 | prom-data |
| Monitoring | alertmanager | prom/alertmanager | 127.0.0.1:9093 | am-data |
| Monitoring | grafana | grafana/grafana | 127.0.0.1:3000 | grafana-data |
| Monitoring | node_exporter | prom/node-exporter | 127.0.0.1:9100 | — |
| Monitoring | cadvisor | gcr.io/cadvisor | 127.0.0.1:8085 | — |
| Monitoring | blackbox_exporter | prom/blackbox-exporter | 127.0.0.1:9115 | — |
| Monitoring | mysqld_exporter (x2) | prom/mysqld-exporter | 127.0.0.1:9104/9105 | — |
| Security | wazuh-agent | wazuh/wazuh-agent (hoặc apt) | — | — |

---

## 6. Cấu trúc repo hạ tầng đề xuất

```
infra/
├── ansible/                 # hoặc scripts/ nếu làm bằng bash
│   ├── playbook-hardening.yml
│   └── inventory.ini
├── compose/
│   ├── production/docker-compose.yml   + .env.example
│   ├── staging/docker-compose.yml      + .env.example
│   └── monitoring/
│       ├── docker-compose.yml
│       ├── prometheus/prometheus.yml + rules/
│       ├── alertmanager/config.yml
│       ├── blackbox/config.yml
│       └── grafana/provisioning/
├── nginx/
│   ├── prod.example.com.conf
│   ├── staging.example.com.conf
│   └── grafana.example.com.conf
├── scripts/
│   ├── backup.sh
│   ├── restore.sh
│   └── deploy.sh
└── docs/
    ├── runbook-restore.md
    ├── runbook-incident.md
    └── lynis-baseline.txt
```

---

## 7. Lịch triển khai (ước lượng ~7–8 ngày công)

| GĐ | Nội dung | Thời lượng | Phụ thuộc |
| --- | --- | --- | --- |
| 0 | Chuẩn bị | 0.5 ngày | — |
| 1 | Nền tảng OS + hardening | 1 ngày | 0 |
| 2 | Docker + Nginx + TLS | 0.5 ngày | 1 |
| 3 | Staging | 1 ngày | 2 |
| 4 | Production | 1 ngày | 3 |
| 5 | Monitoring | 1 ngày | 2 (song song được với 3–4) |
| 6 | Backup & restore | 0.5 ngày | 4 |
| 7 | CI/CD | 1 ngày | 3, 4 |
| 8 | Bảo mật nâng cao + nghiệm thu | 0.5 ngày | tất cả |

---

## 8. Rủi ro & giảm thiểu

| Rủi ro | Ảnh hưởng | Giảm thiểu |
| --- | --- | --- |
| Tự khoá mình khỏi SSH khi siết firewall | Cao | Cài Tailscale trước, giữ console out-of-band, test trước reboot |
| Một máy chủ = SPOF | Cao | Backup off-site + IaC → dựng lại nhanh; giai đoạn 2 cân nhắc node thứ 2 |
| Rò rỉ secret trong image/git | Cao | `.env` không commit, `sops/age`, Trivy + git-secrets, xoay khoá định kỳ |
| Prometheus/MySQL ngốn RAM gây OOM | Trung bình | `mem_limit`, giới hạn retention, cảnh báo RAM, nâng RAM |
| Container image có CVE | Trung bình | Trivy trong CI, `unattended-upgrades`, rebuild định kỳ |
| Backup không restore được | Cao | Bắt buộc test restore định kỳ (hằng tháng) |
| Chứng chỉ TLS hết hạn | Trung bình | certbot timer + alert "cert < 20 ngày" từ blackbox/prometheus |

---

## 9. Vận hành sau triển khai (Day-2)

- **Hằng ngày:** kiểm tra Grafana + báo cáo backup + alert Telegram.
- **Hằng tuần:** review log Wazuh/auditd; `apt` update host; cập nhật image staging.
- **Hằng tháng:** test restore; quét Lynis/OpenSCAP/Trivy; review exception hardening; dọn dữ liệu Prometheus/log.
- **Hằng quý:** xoay SSH key & secret; diễn tập sự cố; rà soát dung lượng đĩa & capacity.

---

## 10. Checklist nghiệm thu cuối

- [ ]  SSH chỉ truy cập được qua Tailscale; 22 không mở public
- [ ]  `https://prod.example.com` và `https://staging.example.com` hoạt động, TLS hợp lệ (A trên SSL Labs)
- [ ]  Không có cổng DB/exporter nào lộ ra Internet (quét ngoài xác nhận)
- [ ]  Grafana có dashboard host/container/MySQL/blackbox; toàn bộ target `UP`
- [ ]  Thử gây lỗi → nhận alert qua Telegram/email
- [ ]  Backup chạy tự động hằng ngày + đã test restore thành công
- [ ]  CI/CD: push `develop` → staging tự động; prod cần approval; có rollback
- [ ]  Wazuh agent báo về manager; SCA CIS chạy
- [ ]  Lynis score ≥ 70; OpenSCAP CIS L1 pass phần lớn, exception có ghi lý do
- [ ]  Tài liệu runbook (restore, incident) hoàn chỉnh trong repo