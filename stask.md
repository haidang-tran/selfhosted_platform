internal
exxternal / -> docker
yaml
tìm hiểu sâu về dockercompose

bỏ port ở trong dockercpmpose , chỉ hiển thị tên -> phải config

TLS -> 1 giao thức của wed 
Domain
nameserver A
DNS 
port fowarding
api gateway
những công dụng của nginx


domain/grafana
Vd: haidang.com/grafana

Hiểu từ cái luồng từ user đi tới DNS đi tới server, tới nginx rồi tới bên tron  g grafana
Phải show cho đc record, nameserver A, TLS cert , nginx config




┌──────────┬──────────────────────────────────────────────────────┐
│  Loại    │  Ý nghĩa                                             │
├──────────┼──────────────────────────────────────────────────────┤
│ A        │  Tên miền → IPv4                                     │
│          │  haidang.com → 103.56.12.34                          │
├──────────┼──────────────────────────────────────────────────────┤
│ AAAA     │  Tên miền → IPv6                                     │
│          │  haidang.com → 2001:db8::1                           │
├──────────┼──────────────────────────────────────────────────────┤
│ CNAME    │  Tên miền → Tên miền khác (bí danh)                 │
│          │  www.haidang.com → haidang.com                       │
├──────────┼──────────────────────────────────────────────────────┤
│ NS       │  Ai là Nameserver có thẩm quyền cho domain này?      │
│          │  haidang.com → ns1.cloudflare.com                    │
├──────────┼──────────────────────────────────────────────────────┤
│ MX       │  Email của domain này gửi về máy chủ nào?            │
│          │  haidang.com → mail.haidang.com                      │
├──────────┼──────────────────────────────────────────────────────┤
│ TXT      │  Lưu văn bản tùy ý (xác minh, SPF, DKIM...)         │
│          │  haidang.com → "v=spf1 include:..."                  │

└──────────┴──────────────────────────────────────────────────────┘






[Người dùng gõ: https://haidang.com/grafana]
         │
         ▼  TẦNG 1: DNS
    DNS Resolver → Root NS → TLD NS → Cloudflare NS
    Kết quả: haidang.com = 103.56.12.34
         │
         ▼  TẦNG 2: Network
    TCP Handshake tới 103.56.12.34:443
    UFW: port 443 ALLOW ✓
         │
         ▼  TẦNG 3: TLS
    TLS Handshake (fullchain.pem + privkey.pem)
    Đường hầm mã hóa AES-256 thiết lập
         │
         ▼  TẦNG 4: Nginx
    Nginx giải mã → đọc Host + Path
    server_name: haidang.com ✓
    location: /grafana/ ✓
    Rate limit: OK ✓
    proxy_pass → http://grafana:3000/
         │
         ▼  TẦNG 5: Docker Network
    Docker DNS: "grafana" = 172.25.0.5
    Kết nối nội bộ tới container grafana:3000
         │
         ▼  TẦNG 6: Grafana Container
    Xác thực session
    Query Prometheus lấy data
    Render HTML dashboard
         │
         ▼  Response ngược lại (qua các tầng)
[Người dùng thấy Grafana Dashboard]






Internet
    │
    │  (1) PORT FORWARDING — Tầng Router/Mạng
    │      Nhiệm vụ: Đưa gói tin từ Internet VÀO được server
    │
    ▼
[Router]  103.56.12.34:443  ──────►  192.168.1.40:443
    │      (IP Public)                 (IP nội bộ server)
    │
    ▼
[Ubuntu Server - Nginx]
    │
    │  (2) NGINX REVERSE PROXY — Tầng Application
    │      Nhiệm vụ: Phân nhánh request vào ĐÚNG container
    │
    ├── /           ──► container frontend :8080
    ├── /api/       ──► container backend  :8081
    └── /grafana/   ──► container grafana  :3000
    │
    ▼
[Bên trong Backend Container :8081]
    │
    │  (3) API GATEWAY — Tầng Microservice
    │      Nhiệm vụ: Phân nhánh request vào ĐÚNG microservice
    │
    ├── /api/users/    ──► user-service    :8001
    ├── /api/products/ ──► product-service :8002
    └── /api/orders/   ──► order-service   :8003



bên trong 1 domain 
        https://  staging.haidang.com /grafana
                  ─────────────────── ────────
                         │               │
                      Domain           Path
                  ─────┬───────────────
                       │
            ┌──────────┼──────────────┐
            │          │              │
         staging    haidang          com
            │          │              │
        Subdomain   Second-level    Top-level
                    Domain (SLD)    Domain (TLD)

quy trình đăng ký 1 domain 
1. Đăng ký      Mua haidang.com trên Namecheap/Cloudflare (~$10-15/năm)
       │
       ▼
2. Trỏ DNS      Cấu hình A Record: haidang.com → 103.56.12.34
       │
       ▼
3. Cấp TLS      certbot --nginx -d haidang.com (Let's Encrypt)
       │
       ▼
4. Nginx config  server_name haidang.com;
       │
       ▼
5. Người dùng   Gõ haidang.com → vào được server của bạn qua HTTPS





luồn hỏi DNS Resolver

Máy bạn                                           Internet
   │
   │  "haidang.com là IP gì?"
   │
   ▼
[DNS Resolver]  ← Bạn chỉ nói chuyện với nó
   │
   │  Tự đi hỏi:
   ├──► Root Name Server
   ├──► TLD Name Server (.com)
   └──► Cloudflare (Authoritative NS)
   │
   │  Nhận được: 103.56.12.34
   │  Cache lại theo TTL
   │
   ▼
Trả về cho máy bạn: "103.56.12.34"



xem domain của docker













