# Self-Hosted Platform

Hệ thống hạ tầng tự quản (self-hosted) trên nền tảng Ubuntu Server, cung cấp môi trường vận hành độc lập cho **Production** và **Staging**, tích hợp sẵn hệ thống giám sát tập trung và các tiêu chuẩn bảo mật mức hệ điều hành.

---

## 1. Giới thiệu tổng quan

Dự án thiết lập một máy chủ duy nhất phục vụ toàn bộ vòng đời ứng dụng web:
- **Production & Staging:** Chạy song song nhưng hoàn toàn tách biệt về dữ liệu, network và cấu hình container.
- **Tập trung hóa định tuyến & SSL:** Nginx reverse proxy trên host xử lý cấp phát chứng chỉ tự động (Let's Encrypt) và phân phối traffic an toàn.
- **Giám sát toàn diện:** Thu thập metrics hạ tầng, container, database và uptime tự động với cảnh báo đa kênh.
- **An toàn & Bảo mật:** Quản trị từ xa khép kín qua mạng riêng ảo Tailscale (không mở cổng SSH public), tuân thủ tiêu chuẩn CIS Benchmark và giám sát an ninh máy chủ với Wazuh.

---

## 2. Mô hình kiến trúc

```
[ Người dùng Internet ]
         │
     (HTTP/S)
         ▼
[ Nginx Reverse Proxy (Host) ]
    ├── Production Stack (prod-net) ──► Frontend · API · Backend · MySQL
    ├── Staging Stack    (stg-net)  ──► Nginx · Frontend · API · Backend · MySQL
    └── Grafana Dashboard

[ Mạng quản trị nội bộ (Tailscale VPN) ]
    ├── SSH Server (Cổng 22 chỉ mở trong Tailnet)
    └── Wazuh SIEM Manager (Kết nối agent qua Tailnet)

[ Monitoring Stack (monitor-net) ]
    Node / MySQL / Blackbox Exporter + cAdvisor
         │
         ▼
    Prometheus ──► Alertmanager ──► Telegram / Email
         │
         ▼
      Grafana
```

---

## 3. Các thành phần chính

| Phân hệ | Công nghệ / Dịch vụ | Chức năng chính |
|---|---|---|
| **Hệ điều hành** | Ubuntu 24.04 LTS | Nền tảng máy chủ, tinh chỉnh kernel và cấu hình theo chuẩn CIS |
| **Mạng & Định tuyến** | Nginx, Tailscale, UFW | Reverse proxy, quản lý TLS, định tuyến domain và VPN quản trị khép kín |
| **Ứng dụng** | Docker, Docker Compose | Đóng gói và cô lập các service của Production và Staging |
| **Cơ sở dữ liệu** | MySQL 8.0 | Lưu trữ dữ liệu riêng biệt cho từng môi trường qua Docker volume |
| **Giám sát & Cảnh báo** | Prometheus, Grafana, Alertmanager | Thu thập số liệu hiệu năng, trực quan hóa dashboard và gửi thông báo sự cố |
| **Sao lưu dữ liệu** | Restic, S3 / Backblaze B2 | Sao lưu tự động hằng ngày ra bộ nhớ ngoài với chính sách xoay vòng snapshot |
| **An ninh máy chủ** | Wazuh Agent, AIDE, Fail2ban | Phát hiện xâm nhập, kiểm tra tính toàn vẹn file và chống brute-force |

---

## 4. Cấu trúc thư mục dự án

```
.
├── compose/
│   ├── production/         # Cấu hình Docker Compose cho môi trường Production
│   ├── staging/            # Cấu hình Docker Compose cho môi trường Staging
│   └── monitoring/         # Stack giám sát: Prometheus, Grafana, Alertmanager, Exporters
├── nginx/                  # File cấu hình virtual host cho từng domain
├── ansible/                # Playbook tự động hóa hardening hệ điều hành theo chuẩn CIS
├── scripts/                # Các script tự động hóa: deploy, backup, restore
├── docs/                   # Tài liệu vận hành, runbook ứng cứu sự cố và baseline kiểm toán
├── README.md               # Mô tả tổng quan hệ thống
└── project.md              # Kế hoạch kỹ thuật và đặc tả chi tiết dự án
```

---

## 5. Khởi động nhanh (Quick Start)

### Yêu cầu tiên quyết
- Máy chủ Ubuntu đã cài đặt Docker và Docker Compose plugin.
- Đã cấu hình domain trỏ về địa chỉ IP của server.

### Các bước vận hành cơ bản

1. **Khởi tạo file cấu hình môi trường:**
   Tạo file `.env` từ mẫu có sẵn cho từng môi trường:
   ```bash
   cp compose/production/.env.example compose/production/.env
   cp compose/staging/.env.example compose/staging/.env
   ```

2. **Khởi chạy hệ thống giám sát:**
   ```bash
   docker compose -f monitoring/docker-compose.yml up -d
   ```

3. **Khởi chạy môi trường ứng dụng:**
   - Dành cho Staging:
     ```bash
     ./scripts/deploy.sh staging
     ```
   - Dành cho Production:
     ```bash
     ./scripts/deploy.sh production
     ```

---

## 6. Tài liệu chi tiết

Để tìm hiểu sâu hơn về quy trình triển khai, kịch bản bảo trì và xử lý sự cố, vui lòng tham khảo các tài liệu liên quan:
- **Kế hoạch triển khai & chi tiết kỹ thuật:** [project.md](file:///d:/selfhosted-platform/project.md)
- **Quy trình phục hồi dữ liệu:** [docs/runbook-restore.md](file:///d:/selfhosted-platform/docs/runbook-restore.md)
- **Quy trình xử lý sự cố:** [docs/runbook-incident.md](file:///d:/selfhosted-platform/docs/runbook-incident.md)