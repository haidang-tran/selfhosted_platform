# Tài Liệu Học: Hạ Tầng Web Từ A → Z

> **Mục tiêu:** Hiểu trọn vẹn hành trình của một gói tin từ lúc người dùng gõ `haidang.com/grafana`  
> cho đến khi nhận được giao diện Grafana trả về — và biết cách tự cấu hình được từng bước đó.

---

## Mục Lục

1. [DNS — Hệ thống phân giải tên miền](#1-dns)
2. [TLS/HTTPS — Lớp mã hóa đường truyền](#2-tls)
3. [Port Forwarding — Cánh cổng mạng](#3-port-forwarding)
4. [Nginx — Người lính gác và người điều phối](#4-nginx)
5. [API Gateway — Cổng tổng hợp dịch vụ](#5-api-gateway)
6. [Docker Networking — Mạng nội bộ Docker](#6-docker-networking)
7. [Docker Compose Nâng Cao — Bỏ port, dùng tên](#7-docker-compose)
8. [YAML — Ngôn ngữ cấu hình](#8-yaml)
9. [Luồng Hoàn Chỉnh: User → DNS → Nginx → Grafana](#9-luong-hoan-chinh)
10. [Lab Thực Hành: Show toàn bộ cấu hình thật](#10-lab)

---

## 1. DNS — Hệ Thống Phân Giải Tên Miền

> **Nguồn tham chiếu:** RFC 1034/1035 — Cloudflare Learning: https://www.cloudflare.com/learning/dns/what-is-dns/

### DNS là gì?

**DNS (Domain Name System)** là hệ thống phân giải tên miền — giống như một **cuốn danh bạ khổng lồ toàn cầu** cho Internet.

- **Người dùng nhớ:** `haidang.com` (tên dễ nhớ)
- **Máy tính hiểu:** `103.56.12.34` (địa chỉ IP — địa chỉ nhà thật)
- **DNS làm:** Dịch từ tên miền → địa chỉ IP

### Các loại DNS Record quan trọng

| Loại Record | Viết tắt | Mục đích | Ví dụ |
|:---|:---|:---|:---|
| **A Record** | Address | Trỏ tên miền → IPv4 | `haidang.com` → `103.56.12.34` |
| **AAAA Record** | IPv6 Address | Trỏ tên miền → IPv6 | `haidang.com` → `2001:db8::1` |
| **CNAME Record** | Canonical Name | Bí danh cho tên miền khác | `www.haidang.com` → `haidang.com` |
| **MX Record** | Mail Exchange | Máy chủ nhận email | `haidang.com` → `mail.haidang.com` |
| **TXT Record** | Text | Xác minh quyền sở hữu, SPF, DKIM | `"v=spf1 include:..."` |
| **NS Record** | Name Server | Máy chủ DNS có thẩm quyền cho domain | `ns1.cloudflare.com` |

### Cách DNS hoạt động — 8 bước thực tế

```
Bước 1: Trình duyệt hỏi: "IP của haidang.com là gì?"
         |
         v (Hỏi DNS Resolver của ISP / 8.8.8.8)
Bước 2: DNS Resolver kiểm tra cache → Không có
         |
         v (Hỏi Root Name Server — 13 cái trên thế giới)
Bước 3: Root NS trả lời: "Hỏi Name Server của .com"
         |
         v (Hỏi TLD Name Server của .com)
Bước 4: TLD NS trả lời: "Hỏi Name Server của haidang.com"
         | (Đây là Nameserver của Cloudflare/Namecheap mà bạn đăng ký)
         v
Bước 5: Authoritative NS của haidang.com tra bảng → Tìm thấy A Record
Bước 6: Trả về IP: 103.56.12.34
Bước 7: DNS Resolver cache kết quả theo TTL (thời gian sống)
Bước 8: Trình duyệt nhận IP → Bắt đầu kết nối tới server
```

### Cấu hình DNS thực tế (trên Cloudflare)

```
Zone: haidang.com
Nameservers: ns1.cloudflare.com, ns2.cloudflare.com

┌─────────────────────────────────────────────────────────────┐
│  Type │  Name     │  Value          │ TTL  │ Proxy   │ Tác dụng
├───────┼───────────┼─────────────────┼──────┼─────────┤
│  A    │  @        │  103.56.12.34   │ Auto │   CF    │  haidang.com
│  A    │  grafana  │  103.56.12.34   │ Auto │   CF    │  grafana.haidang.com
│  A    │  staging  │  103.56.12.34   │ Auto │   CF    │  staging.haidang.com
│ CNAME │  www      │  haidang.com    │ Auto │   CF    │  www.haidang.com
└─────────────────────────────────────────────────────────────┘
```

### Kiểm tra DNS trên terminal

```bash
# Tra cứu IP của tên miền
nslookup haidang.com

# Tra cứu chi tiết hơn với dig
dig haidang.com A

# Xem toàn bộ các loại record
dig haidang.com ANY

# Kiểm tra nameserver đang dùng
dig haidang.com NS

# Tra cứu trực tiếp qua DNS cụ thể (1.1.1.1 của Cloudflare)
dig haidang.com @1.1.1.1
```

---

## 2. TLS/HTTPS — Lớp Mã Hóa Đường Truyền
HTTPS = HTTP + TLS 

> **Nguồn tham chiếu:** RFC 8446 — TLS 1.3: https://www.rfc-editor.org/rfc/rfc8446  
> Mozilla SSL Config Generator: https://ssl-config.mozilla.org/

### Vấn đề: Tại sao HTTP nguy hiểm?

**HTTP** gửi dữ liệu dưới dạng **văn bản thô, không mã hóa**:

```
HTTP Request (nguy hiểm!):
GET /login HTTP/1.1
Host: haidang.com
Body: username=dangtran&password=MySecret123   <- Ai cũng đọc được!
```

Nếu bạn ngồi ở quán cà phê bắt chung Wi-Fi, người bên cạnh có thể dùng **Wireshark** để đọc trộm mật khẩu của bạn.

### Giải pháp: TLS (Transport Layer Security)

**TLS** tạo ra một "đường hầm bí mật" (encrypted tunnel) giữa trình duyệt và server:

```
Trình duyệt --(mã hóa AES-256)-- Đường hầm TLS --(giải mã)--> Server
                Không ai ở giữa đọc được gì cả
```

> **Lưu ý tên gọi:**
> - **SSL** là phiên bản cũ, đã lỗi thời và có nhiều lỗ hổng bảo mật.
> - **TLS** là phiên bản mới, chuẩn hiện tại là **TLS 1.3** (2018).
> - Dân trong nghề vẫn hay gọi tắt là "SSL" vì thói quen.

### Cơ chế hoạt động của TLS Handshake

```
Trình duyệt                                    Server
    |                                              |
    |---- 1. "Hello, tôi hỗ trợ TLS 1.3" ------->|
    |                                              |
    |<--- 2. "OK, đây là chứng chỉ số của tôi" ---|
    |      (Certificate có Public Key)             |
    |                                              |
    |--- 3. Kiểm tra chứng chỉ với CA (Let's Encrypt)
    |      OK Hợp lệ, do Let's Encrypt ký         |
    |                                              |
    |---- 4. Tạo Session Key chung, mã hóa bằng   |
    |        Public Key của server --------------->|
    |                                              |
    |      Server dùng Private Key để giải mã      |
    |      Cả hai bên đều có Session Key           |
    |                                              |
    |<======= 5. Bắt đầu trao đổi mã hóa ========>|
               (Dữ liệu thật sự được mã hóa)
```

### Chứng chỉ TLS gồm những file gì?

Sau khi chạy `certbot`, bạn sẽ có các file trong `/etc/letsencrypt/live/haidang.com/`:

```
/etc/letsencrypt/live/haidang.com/
├── fullchain.pem   <- Chứng chỉ công khai (gửi cho trình duyệt để kiểm tra)
├── privkey.pem     <- Khóa bí mật (TUYỆT ĐỐI KHÔNG ĐƯỢC LỘ RA NGOÀI!)
├── cert.pem        <- Chứng chỉ của domain (không bao gồm chain)
└── chain.pem       <- Chứng chỉ trung gian của Let's Encrypt
```

| File | Ai dùng | Mục đích |
|:---|:---|:---|
| `fullchain.pem` | Nginx dùng, gửi cho trình duyệt | Chứng minh `haidang.com` là thật |
| `privkey.pem` | Nginx giữ bí mật | Giải mã dữ liệu từ trình duyệt |

### Cấp chứng chỉ Let's Encrypt

```bash
# Cài certbot
sudo apt install certbot python3-certbot-nginx

# Cấp chứng chỉ cho domain chính và subdomain
sudo certbot --nginx \
  -d haidang.com \
  -d www.haidang.com \
  -d grafana.haidang.com \
  -d staging.haidang.com

# Kiểm tra tự động gia hạn
sudo certbot renew --dry-run

# Xem thông tin chứng chỉ
sudo certbot certificates
```

### Kiểm tra TLS trên terminal

```bash
# Xem ngày hết hạn chứng chỉ
echo | openssl s_client -connect haidang.com:443 -servername haidang.com 2>/dev/null \
  | openssl x509 -noout -dates

# Kiểm tra điểm bảo mật TLS
# Truy cập: https://www.ssllabs.com/ssltest/analyze.html?d=haidang.com
```

---

## 3. Port Forwarding — Cánh Cổng Mạng

> **Nguồn tham chiếu:** IANA Port Numbers: https://www.iana.org/assignments/service-names-port-numbers/

### Port là gì?

Server có **1 địa chỉ IP** nhưng có thể cùng lúc chạy **hàng chục dịch vụ**. Port là **số phòng** để phân biệt từng dịch vụ:

```
Server: 103.56.12.34
    |
    |-- Port 22   --> SSH (quản trị từ xa)
    |-- Port 80   --> HTTP (Web không mã hóa)
    |-- Port 443  --> HTTPS (Web có mã hóa TLS)
    |-- Port 3306 --> MySQL Database
    |-- Port 3000 --> Grafana
    |-- Port 9090 --> Prometheus
    └-- Port 8080 --> Ứng dụng web tùy chỉnh
```

### Port Forwarding là gì?

Khi server nằm sau một **cục Router/NAT** (phổ biến ở server tại nhà):

```
Internet
    |
    | 103.56.12.34:443 (IP Public)
    v
[Router / Cục modem]  <-- Port Forwarding: 443 --> 192.168.1.40:443
    |
    | 192.168.1.40 (IP Nội bộ)
    v
[Server Ubuntu]
```

> **Quan trọng:** Với VPS thuê của nhà cung cấp (DigitalOcean, Vultr, AWS) — server có IP Public trực tiếp,
> **không cần Port Forwarding**. Chỉ cần mở UFW là xong!

### Danh sách Port quan trọng cần nhớ

| Port | Dịch vụ | Trạng thái mở ra ngoài |
|:---|:---|:---|
| **22** | SSH | KHÔNG — CHỈ mở cho Tailscale (`tailscale0`) |
| **80** | HTTP | CÓ — để redirect sang 443 |
| **443** | HTTPS | CÓ — mở cho mọi người |
| **3306** | MySQL | KHÔNG — đóng hoàn toàn |
| **3000** | Grafana | KHÔNG — truy cập qua Nginx |
| **9090** | Prometheus | KHÔNG — chỉ `127.0.0.1` |

---

## 4. Nginx — Người Lính Gác Và Người Điều Phối

> **Nguồn tham chiếu:** Nginx Official Docs: https://nginx.org/en/docs/

### Nginx là gì?

**Nginx** (đọc là "engine-x") là phần mềm chạy trên server đảm nhận nhiều vai trò:

```
Internet
    |
    v
[Nginx — Người gác cổng]
    |
    |---> Web Server:      Trả về file HTML/CSS/JS tĩnh
    |---> Reverse Proxy:   Chuyển tiếp request vào backend
    |---> TLS Termination: Xử lý mã hóa HTTPS
    |---> Load Balancer:   Chia tải cho nhiều server
    |---> Rate Limiter:    Chống spam, DDoS
    └---> API Gateway:     Điều phối nhiều microservice
```

### Cấu trúc file cấu hình Nginx

```
/etc/nginx/
├── nginx.conf              <- Cấu hình toàn cục (ít khi cần sửa)
├── sites-available/        <- Nơi chứa các vhost (chưa kích hoạt)
│   ├── haidang.com.conf
│   └── grafana.haidang.com.conf
└── sites-enabled/          <- Symlink tới sites-available (đã kích hoạt)
    └── haidang.com.conf    -> ../sites-available/haidang.com.conf
```

### Giải thích một file cấu hình hoàn chỉnh

```nginx
# ============================================================
# FILE: /etc/nginx/sites-available/haidang.com.conf
# ============================================================

# BLOCK 1: Redirect HTTP → HTTPS
# Mọi request vào cổng 80 (HTTP) đều bị chuyển sang 443 (HTTPS)
server {
    listen 80;
    server_name haidang.com www.haidang.com;

    # 301 = Redirect vĩnh viễn (trình duyệt + Google sẽ nhớ)
    return 301 https://$host$request_uri;
}

# BLOCK 2: HTTPS Server chính
server {
    listen 443 ssl http2;
    server_name haidang.com www.haidang.com;

    # --- TLS Certificate ---
    ssl_certificate     /etc/letsencrypt/live/haidang.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/haidang.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # --- Security Headers ---
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options    "nosniff" always;
    add_header X-Frame-Options           "SAMEORIGIN" always;

    # --- Rate Limiting (chống spam 30 req/giây/IP) ---
    limit_req_zone $binary_remote_addr zone=main:10m rate=30r/s;
    limit_req zone=main burst=60 nodelay;

    # Đường dẫn "/" → Frontend App
    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # Đường dẫn "/api/" → Backend API
    location /api/ {
        proxy_pass         http://127.0.0.1:8081;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # --- Logs ---
    access_log  /var/log/nginx/haidang.access.log;
    error_log   /var/log/nginx/haidang.error.log;
}
```

### Giải thích dòng proxy_set_header

Khi Nginx chuyển tiếp request vào container backend, request sẽ xuất phát từ `127.0.0.1`.
Các header này đính kèm thông tin gốc để backend biết ai thực sự gọi:

| Header | Ý nghĩa |
|:---|:---|
| `Host` | Tên miền người dùng đã gõ (`haidang.com`) |
| `X-Real-IP` | IP thật của người dùng |
| `X-Forwarded-For` | Chuỗi IP nếu qua nhiều proxy |
| `X-Forwarded-Proto` | Người dùng vào bằng `http` hay `https` |

### Lệnh Nginx hay dùng

```bash
# Kiểm tra file cấu hình có lỗi cú pháp không
sudo nginx -t

# Reload cấu hình (không restart, không mất kết nối đang có)
sudo systemctl reload nginx

# Restart hoàn toàn
sudo systemctl restart nginx

# Xem log truy cập realtime
sudo tail -f /var/log/nginx/haidang.access.log

# Kích hoạt một vhost
sudo ln -s /etc/nginx/sites-available/haidang.com.conf /etc/nginx/sites-enabled/
```

---

## 5. API Gateway — Cổng Tổng Hợp Dịch Vụ

> **Nguồn tham chiếu:** https://www.nginx.com/blog/deploying-nginx-plus-as-an-api-gateway-part-1/

### Vấn đề với Microservice

Khi ứng dụng lớn dần, người ta tách ra thành nhiều **Microservice** nhỏ:

```
Ứng dụng thương mại điện tử:
├── Service User:    /api/users     → Port 8001
├── Service Product: /api/products  → Port 8002
├── Service Order:   /api/orders    → Port 8003
└── Service Payment: /api/payments  → Port 8004
```

**Vấn đề:** Frontend phải gọi 4 cổng khác nhau, phức tạp, khó bảo mật.

**Giải pháp: API Gateway** — Một điểm vào duy nhất:

```
                    ┌──────────────────────────────────┐
Frontend --> :443  -->     API Gateway (Nginx)          |
                    |  /api/users    --> :8001           |
                    |  /api/products --> :8002           |
                    |  /api/orders   --> :8003           |
                    |  /api/payments --> :8004           |
                    └──────────────────────────────────┘
```

### Nginx làm API Gateway

```nginx
server {
    listen 443 ssl;
    server_name api.haidang.com;

    upstream user_service {
        server 127.0.0.1:8001;
    }
    upstream product_service {
        server 127.0.0.1:8002;
    }

    location /api/users/ {
        proxy_pass http://user_service;
    }
    location /api/products/ {
        proxy_pass http://product_service;
    }
}
```

---

## 6. Docker Networking — Mạng Nội Bộ Docker

> **Nguồn tham chiếu:** https://docs.docker.com/network/

### Tại sao Docker cần Network?

Các container Docker mặc định **bị cách ly hoàn toàn**. Muốn chúng nói chuyện được với nhau,
phải đặt chúng vào cùng một **Docker Network**.

### 4 loại Docker Network

#### 1. bridge — Mạng cầu nối (Mặc định)

```
Host OS
|
|-- Docker Bridge (172.17.0.0/16)
|       |-- Container A: 172.17.0.2
|       └-- Container B: 172.17.0.3
|
└-- eth0 (Interface mạng thật)
```

- Containers trong cùng bridge network nói chuyện được với nhau qua IP.
- **Dùng khi:** Development, test đơn giản.

#### 2. host — Chia sẻ mạng với Host OS

- Container dùng trực tiếp mạng của Host.
- **Dùng khi:** node_exporter cần đọc thông số host.

#### 3. Custom Bridge Network — Mạng tùy chỉnh (Khuyến nghị)

```bash
# Tạo mạng tùy chỉnh
docker network create prod-net
docker network create stg-net
docker network create monitor-net
```

**Điểm khác biệt quan trọng:**
- Có **Docker Internal DNS** — gọi container bằng **tên service**, không cần nhớ IP!
- Cách ly tốt hơn — container ở `prod-net` không thấy container ở `stg-net`.

```
prod-net (172.20.0.0/16):
    prod-frontend: 172.20.0.2  <-- Nginx biết tên "prod-frontend"
    prod-api:      172.20.0.3  <-- Nginx biết tên "prod-api"
    prod-mysql:    172.20.0.4  <-- api biết tên "prod-mysql"

stg-net (172.21.0.0/16):
    stg-frontend:  172.21.0.2  <-- Hoàn toàn tách biệt với prod-net!
    stg-api:       172.21.0.3
    stg-mysql:     172.21.0.4
```

#### 4. none — Không có mạng

- Container hoàn toàn bị cô lập.
- **Dùng khi:** Chạy task tính toán không cần mạng.

### internal vs external trong Docker Compose

```yaml
networks:
  # external: true --> Mạng đã tồn tại ngoài compose, dùng docker network create trước
  prod-net:
    external: true   # Không tạo mới, kết nối vào mạng đã có

  # external: false (mặc định) --> Compose tự tạo mạng này khi chạy
  app-internal:
    driver: bridge

  # internal: true --> Container trong mạng này KHÔNG ra được Internet!
  db-secret-net:
    internal: true   # Database cực kỳ bí mật, không ping ra ngoài được
```

**Khi nào dùng `external: true`?**
Khi có nhiều file `docker-compose.yml` riêng biệt (prod, staging, monitoring) muốn kết nối qua mạng chung.

**Khi nào dùng `internal: true`?**
Database chứa dữ liệu nhạy cảm — không bao giờ nên tự mình gọi ra Internet.

### Docker DNS hoạt động thế nào?

```
Container prod-api cần kết nối MySQL:

Code: mysql.connect("prod-mysql", 3306)
         |
         v
Docker DNS Server (127.0.0.11) bên trong prod-net
         |  Tra cứu: "prod-mysql" là ai trong prod-net?
         v
Trả về: 172.20.0.4
         |
         v
prod-api kết nối tới 172.20.0.4:3306 thành công!
```

Bạn không bao giờ phải hardcode IP vào code. Chỉ cần dùng **tên service** là Docker lo phần còn lại!

---

## 7. Docker Compose Nâng Cao — Bỏ Port, Dùng Tên

> **Nguồn tham chiếu:** https://docs.docker.com/compose/compose-file/

### Bài toán: Grafana đang mở port 3000 ra ngoài

```yaml
# CÁCH NGUY HIỂM
services:
  grafana:
    image: grafana/grafana:10.0.0
    ports:
      - "3000:3000"    # Bất kỳ ai cũng vào được http://103.56.12.34:3000 !!!
```

**Hậu quả:** Grafana bị lộ ra Internet không qua TLS, không qua xác thực của Nginx.

### Giải pháp: Bỏ ports, dùng expose + Docker Network chung

```yaml
# CÁCH CHUẨN CHO PRODUCTION
services:
  grafana:
    image: grafana/grafana:10.0.0
    container_name: grafana
    restart: unless-stopped

    # KHÔNG có `ports:` nữa — Grafana hoàn toàn tàng hình với bên ngoài!
    expose:
      - "3000"     # Chỉ cho container trong cùng network nhìn thấy

    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=my_secure_password
      - GF_USERS_ALLOW_SIGN_UP=false
      # Bắt buộc khai báo khi truy cập qua subpath /grafana
      - GF_SERVER_ROOT_URL=https://haidang.com/grafana/
      - GF_SERVER_SERVE_FROM_SUB_PATH=true

    volumes:
      - grafana-data:/var/lib/grafana
    networks:
      - monitor-net    # Cùng mạng với Prometheus
      - shared-proxy   # Cùng mạng với Nginx để Nginx gọi được vào!

networks:
  monitor-net:
    external: true
  shared-proxy:
    external: true   # Nginx và Grafana cùng cắm vào mạng này
```

Cấu hình Nginx tương ứng:

```nginx
# Nginx gọi Grafana bằng TÊN SERVICE, không phải IP!
location /grafana/ {
    proxy_pass         http://grafana:3000/;   # "grafana" là tên container!
    proxy_set_header   Host              $host;
    proxy_set_header   X-Real-IP         $remote_addr;
    proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto $scheme;

    # Cần thiết cho WebSocket (biểu đồ Grafana realtime)
    proxy_http_version 1.1;
    proxy_set_header   Upgrade    $http_upgrade;
    proxy_set_header   Connection "upgrade";
}
```

### Sự khác biệt: ports vs expose

| Thuộc tính | `ports` | `expose` |
|:---|:---|:---|
| **Ai thấy được?** | Host OS + Mọi container + Internet | Chỉ container cùng network |
| **Tác dụng bảo mật** | Mở cổng ra ngoài (nguy hiểm!) | Khai báo nội bộ (an toàn) |
| **Khi nào dùng?** | Dev/debug | Production |
| **Ví dụ** | `- "3000:3000"` | `- "3000"` |

---

## 8. YAML — Ngôn Ngữ Cấu Hình

> **Nguồn tham chiếu:** YAML Specification: https://yaml.org/spec/1.2-old/spec.html

YAML (YAML Ain't Markup Language) là định dạng file cấu hình rất phổ biến trong DevOps.

### Cú pháp cơ bản

```yaml
# 1. Key-Value (cặp khóa-giá trị)
ten: Đặng Trần
tuoi: 25
la_admin: true


# 2. Nested Object (Đối tượng lồng nhau) → Dùng indent 2 space
database:
  host: localhost
  port: 3306
  ten_db: app_production


# 3. List / Array (Danh sách) → Dùng dấu "-"
ports:
  - 80
  - 443
  - 3306


# 4. Multi-line String
# "|" giữ nguyên dòng mới (literal block)
script: |
  #!/bin/bash
  echo "Hello"
  echo "World"

# ">" gộp dòng mới thành khoảng trắng (folded block)
description: >
  Đây là một đoạn văn bản
  rất dài nhưng sẽ được gộp
  thành một dòng.


# 5. Environment Variable với giá trị mặc định
environment:
  - DB_HOST=${DB_HOST:-localhost}    # Nếu không set → dùng "localhost"
  - DB_PORT=${DB_PORT:-3306}


# 6. Anchor & Alias — Tái sử dụng cấu hình (tránh lặp)
x-logging-config: &logging
  driver: json-file
  options:
    max-size: "20m"
    max-file: "3"

services:
  nginx:
    image: nginx:alpine
    logging: *logging    # Dùng lại cấu hình logging ở trên

  grafana:
    image: grafana/grafana:10.0.0
    logging: *logging    # Dùng lại, không cần viết lại!
```

### Những lỗi hay gặp trong YAML

```yaml
# SAI: Dùng tab thay vì space
services:
	nginx:          # Tab character → LỖI!

# ĐÚNG: Luôn dùng 2 spaces
services:
  nginx:

# SAI: Thiếu dấu cách sau ":"
port:3306         # Không có space → LỖI!

# ĐÚNG
port: 3306

# SAI: String có ký tự đặc biệt nhưng không có dấu nháy
message: Hello: World   # Dấu ":" bên trong string → LỖI!

# ĐÚNG
message: "Hello: World"
```

---

## 9. Luồng Hoàn Chỉnh: User → DNS → Nginx → Grafana

### Kịch bản: Người dùng gõ `https://haidang.com/grafana`

```
┌─────────────────────────────────────────────────────────────────────┐
│  BƯỚC 1: DNS Resolution                                             │
│                                                                     │
│  Browser gõ: haidang.com/grafana                                    │
│       |                                                             │
│       v   Hỏi DNS Resolver (8.8.8.8)                               │
│  Tra cứu A Record của haidang.com                                   │
│       |                                                             │
│       v   TTL: 300s                                                 │
│  Kết quả: 103.56.12.34                                              │
└─────────────────────────────────────────────────────────────────────┘
                              |
                              v
┌─────────────────────────────────────────────────────────────────────┐
│  BƯỚC 2: Kết nối TCP + TLS Handshake                                │
│                                                                     │
│  Browser --> 103.56.12.34:443 (HTTPS)                               │
│  UFW kiểm tra: cổng 443 --> ALLOW OK                                │
│  TLS Handshake:                                                     │
│    - Server gửi fullchain.pem (Let's Encrypt)                       │
│    - Browser xác minh OK                                            │
│    - Thỏa thuận Session Key                                         │
│    - Bắt đầu mã hóa AES-256                                         │
└─────────────────────────────────────────────────────────────────────┘
                              |
                              v
┌─────────────────────────────────────────────────────────────────────┐
│  BƯỚC 3: Nginx nhận và xử lý Request                                │
│                                                                     │
│  Nginx giải mã TLS bằng privkey.pem                                 │
│  Nginx đọc:                                                         │
│    - Host: haidang.com                                              │
│    - Path: /grafana/                                                │
│                                                                     │
│  Nginx tra config → Tìm thấy luật:                                  │
│    location /grafana/ {                                             │
│        proxy_pass http://grafana:3000/;                             │
│    }                                                                │
└─────────────────────────────────────────────────────────────────────┘
                              |
                              v
┌─────────────────────────────────────────────────────────────────────┐
│  BƯỚC 4: Docker DNS Resolution (Nội bộ)                             │
│                                                                     │
│  Nginx gọi: http://grafana:3000/                                    │
│       |                                                             │
│       v   Hỏi Docker DNS Server (127.0.0.11)                        │
│  "grafana" trong shared-proxy network là ai?                        │
│       |                                                             │
│       v                                                             │
│  Trả về: 172.25.0.5 (IP nội bộ của container grafana)              │
└─────────────────────────────────────────────────────────────────────┘
                              |
                              v
┌─────────────────────────────────────────────────────────────────────┐
│  BƯỚC 5: Grafana Container xử lý                                    │
│                                                                     │
│  Grafana nhận request ở cổng 3000                                   │
│  Truy vấn Prometheus để lấy data                                    │
│  Render giao diện dashboard                                         │
│  Trả về HTML/JSON cho Nginx                                         │
└─────────────────────────────────────────────────────────────────────┘
                              |
                              v
┌─────────────────────────────────────────────────────────────────────┐
│  BƯỚC 6: Response ngược trở lại                                     │
│                                                                     │
│  Grafana --> Nginx (qua Docker network)                             │
│  Nginx mã hóa TLS response                                          │
│  Nginx --> Browser (qua Internet, đã mã hóa)                        │
│  Browser giải mã và hiển thị Grafana Dashboard!                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 10. Lab Thực Hành: Show Toàn Bộ Cấu Hình Thật

### Lab 1: Kiểm tra DNS Record

```bash
# Xem A Record của domain
dig haidang.com A +short
# Output: 103.56.12.34

# Xem NS (Nameserver) đang dùng
dig haidang.com NS +short
# Output: ns1.cloudflare.com, ns2.cloudflare.com

# Tra DNS từ Cloudflare (kiểm tra đã propagate chưa)
dig haidang.com A @1.1.1.1 +short

# Xem toàn bộ record
dig haidang.com ANY
```

### Lab 2: Kiểm tra TLS Certificate

```bash
# Xem chứng chỉ đang dùng
sudo certbot certificates

# Xem thông tin chi tiết chứng chỉ
echo | openssl s_client -connect haidang.com:443 -servername haidang.com 2>/dev/null \
  | openssl x509 -noout -text | grep -E "(Subject|Not Before|Not After)"

# Kiểm tra ngày hết hạn
echo | openssl s_client -connect haidang.com:443 -servername haidang.com 2>/dev/null \
  | openssl x509 -noout -dates
```

### Lab 3: Kiểm tra Nginx config

```bash
# Xem file config đang dùng
sudo cat /etc/nginx/sites-enabled/haidang.com.conf

# Test cú pháp file config
sudo nginx -t

# Xem Nginx đang lắng nghe ở port nào
sudo ss -tlnp | grep nginx

# Xem log truy cập realtime
sudo tail -f /var/log/nginx/haidang.access.log
```

### Lab 4: Kiểm tra Docker Network

```bash
# Xem danh sách các network Docker đang có
sudo docker network ls

# Xem chi tiết một network (xem container nào đang trong đó)
sudo docker network inspect monitor-net

# Xem container đang kết nối vào network nào
sudo docker inspect grafana | grep -A 20 '"Networks"'

# Test kết nối từ container Nginx sang container Grafana bằng tên
# (Chứng minh Docker DNS hoạt động)
sudo docker exec -it nginx curl -s http://grafana:3000/api/health
```

### Lab 5: Trace toàn bộ luồng từ bên ngoài

```bash
# Gửi HTTPS request và xem phản hồi đầy đủ (headers)
curl -I https://haidang.com/grafana/

# Xem chứng chỉ TLS trong response
curl --verbose https://haidang.com 2>&1 | grep -E "(SSL|certificate|TLS)"

# Test kết nối TCP đến server
nc -zv 103.56.12.34 443

# Xem Security headers đã được Nginx thêm vào
curl -I https://haidang.com | grep -E "(Strict|X-Content|X-Frame)"
```

---

## Tài Liệu Tham Khảo Chính Thống

| Chủ đề | Tài liệu |
|:---|:---|
| **DNS** | https://www.cloudflare.com/learning/dns/what-is-dns/ |
| **TLS/SSL** | https://wiki.mozilla.org/Security/Server_Side_TLS |
| **Nginx** | https://nginx.org/en/docs/ |
| **Docker Networking** | https://docs.docker.com/network/ |
| **Docker Compose** | https://docs.docker.com/compose/compose-file/ |
| **Let's Encrypt** | https://certbot.eff.org/docs/ |
| **YAML** | https://yaml.org/spec/1.2-old/spec.html |

---

> **Checklist tự kiểm tra — bạn đã hiểu đủ khi có thể tự trả lời:**
>
> - [ ] DNS A Record là gì? Tôi cấu hình nó ở đâu? -> là record A chứa ip và domain từ ip đó , cấu hình nó ở khi cấu hình DNS khi mua domain về hoặc cloudfare free
> - [ ] TLS `fullchain.pem` và `privkey.pem` khác nhau thế nào? đơn giản là cắp khóa public key nằm ở server tượng trưng cho ổ khóa , còn private key do user giữ không bị lộ , giao thức là https nhưng chính nó không đọc được do được cơ chế TLS mã hóa trong quá trình handshake và được giải mã khi đã được xác thực đúng 
> - [ ] Tại sao nên bỏ `ports:` trong Grafana compose? vì nginx đã proxy cho nó rồi nên sẽ không cần port ra ngoài
> - [ ] Nginx gọi Grafana bằng `http://grafana:3000` hoạt động như thế nào? -> thông qua docker network dns resolve 
> - [ ] `external: true` trong Docker network nghĩa là gì? 
> - [ ] Trace được đường đi của request `haidang.com/grafana` qua 6 bước.
