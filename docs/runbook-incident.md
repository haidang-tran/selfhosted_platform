# Runbook: Xử lý Sự cố Vận hành (Incident Response)

## 1. Nguyên tắc chung khi ứng cứu sự cố
1. **Bảo tồn hiện trường:** Không xoá vội container/log trước khi thu thập thông tin chẩn đoán.
2. **Ưu tiên khôi phục dịch vụ:** Nếu cần thiết, rollback nhanh hoặc chuyển hướng trang tĩnh bảo trì.
3. **Ghi chép log:** Mọi hành động can thiệp cần được lưu lại để phục vụ Post-Mortem.

---

## 2. Các kịch bản sự cố thường gặp

### Kịch bản 1: Container bị Crash Loop / Restart liên tục
- **Dấu hiệu:** Alert Telegram `ContainerRestartLoop`, HTTP 502 Bad Gateway từ Nginx.
- **Các bước xử lý:**
  1. Xác định container bị lỗi:
     ```bash
     docker ps -a --filter "status=restarting"
     ```
  2. Kiểm tra log chi tiết:
     ```bash
     docker logs --tail 100 <container_name>
     ```
  3. Kiểm tra biến môi trường hoặc kết nối DB:
     ```bash
     docker compose -p production exec backend env
     ```
  4. Nếu do release mới lỗi, thực hiện rollback:
     ```bash
     ./scripts/deploy.sh production <previous_healthy_tag>
     ```

---

### Kịch bản 2: Server đầy bộ nhớ đĩa (Disk Full > 85% / 95%)
- **Dấu hiệu:** Alert Telegram `DiskSpaceLow`, MySQL từ chối ghi dữ liệu.
- **Các bước xử lý:**
  1. Kiểm tra phân vùng đĩa:
     ```bash
     df -h
     ```
  2. Dọn dẹp Docker images / builder cache không dùng:
     ```bash
     docker system prune -a --volumes=false -f
     ```
  3. Dọn dẹp log Docker quá lớn:
     ```bash
     truncate -s 0 /var/lib/docker/containers/*/*-json.log
     ```
  4. Dọn log hệ thống và journald:
     ```bash
     journalctl --vacuum-time=3d
     ```

---

### Kịch bản 3: Tải CPU hoặc RAM tăng vọt (OOM Risk)
- **Dấu hiệu:** Alert `HighCpuLoad` hoặc `HighMemoryUsage`.
- **Các bước xử lý:**
  1. Xem thống kê tiêu thụ tài nguyên của các container:
     ```bash
     docker stats --no-stream --sort mem_percent
     ```
  2. Xem các tiến trình trên host:
     ```bash
     htop  # hoặc top -o %MEM
     ```
  3. Nếu container chiếm dụng bất thường, khởi động lại container đó:
     ```bash
     docker restart <container_name>
     ```
  4. Xem xét điều chỉnh lại `mem_limit` trong `docker-compose.yml`.

---

### Kịch bản 4: Nghi ngờ lộ SSH Key hoặc Xâm nhập bất thường
- **Dấu hiệu:** Cảnh báo FIM từ Wazuh, có tiến trình lạ ngoài dự kiến.
- **Các bước xử lý:**
  1. Thu hồi ngay SSH key trong file `~deploy/.ssh/authorized_keys`.
  2. Kiểm tra các phiên đăng nhập đang hoạt động:
     ```bash
     w
     last -n 20
     ```
  3. Tạm thời siết toàn bộ firewall UFW chỉ cho phép IP quản trị cụ thể:
     ```bash
     ufw status numbered
     ```
  4. Chạy kiểm tra rootkit và tính toàn vẹn hệ thống:
     ```bash
     aide --check
     rkhunter -c --sk
     ```
