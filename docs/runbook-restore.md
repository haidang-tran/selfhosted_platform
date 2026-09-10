# Runbook: Quy trình Phục hồi Dữ liệu (Disaster Recovery & Restore)

## 1. Mục tiêu
Tài liệu hướng dẫn khôi phục toàn diện dữ liệu hệ thống từ backup lưu trữ trên S3 / Backblaze B2 bằng công cụ `restic`.

---

## 2. Chuẩn bị trước khi khôi phục

1. Đảm bảo server đã cài đặt `restic` và `docker`.
2. Khai báo thông tin xác thực repo backup:
   ```bash
   export AWS_ACCESS_KEY_ID="<your-access-key>"
   export AWS_SECRET_ACCESS_KEY="<your-secret-key>"
   export RESTIC_REPOSITORY="s3:s3.amazonaws.com/my-platform-backups"
   export RESTIC_PASSWORD_FILE="/root/.restic_password"
   ```

3. Kiểm tra danh sách các bản snapshot hiện có:
   ```bash
   restic snapshots
   ```

---

## 3. Khôi phục thử nghiệm trên môi trường Staging (Định kỳ hàng tháng)

Luôn ưu tiên restore thử trên môi trường Staging trước để tránh ảnh hưởng hệ thống thật:

1. Chạy script khôi phục tự động:
   ```bash
   ./scripts/restore.sh latest staging
   ```
2. Kiểm tra log của container MySQL:
   ```bash
   docker compose -p staging logs -f mysql
   ```
3. Đăng nhập kiểm tra dữ liệu qua API hoặc Frontend Staging:
   `https://staging.example.com`

---

## 4. Khôi phục khẩn cấp môi trường Production

> **Lưu ý:** Thao tác này sẽ ghi đè toàn bộ dữ liệu hiện tại của Production. Cần thông báo bảo trì trước khi thực hiện.

1. Tạm dừng traffic đến Production qua Nginx:
   ```bash
   # Chuyển hướng sang trang bảo trì nếu cần
   systemctl reload nginx
   ```

2. Tạm dừng các service backend ghi dữ liệu:
   ```bash
   docker compose -p production stop backend api
   ```

3. Thực hiện restore bản snapshot cụ thể (thay `<snapshot_id>` bằng mã snapshot mong muốn):
   ```bash
   ./scripts/restore.sh <snapshot_id> production
   ```

4. Khởi động lại toàn bộ stack Production:
   ```bash
   docker compose -p production up -d
   ```

5. Kiểm tra tính toàn vẹn dữ liệu và smoke test các tính năng cốt lõi.

---

## 5. Xử lý sự cố khi Restore thất bại

- **Lỗi repo lock:**
  ```bash
  restic unlock
  ```
- **Lỗi checksum hoặc repo hỏng:**
  ```bash
  restic check --read-data-subset=10%
  ```
- **Không tìm thấy SQL dump:** Kiểm tra đường dẫn backup trong snapshot:
  ```bash
  restic ls <snapshot_id>
  ```
