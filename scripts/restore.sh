#!/usr/bin/env bash
set -euo pipefail

# Script phục hồi database hoặc toàn bộ dữ liệu từ backup Restic
# Sử dụng: ./restore.sh <snapshot-id hoặc latest> <target-env: staging|production>

SNAPSHOT="${1:-latest}"
TARGET_ENV="${2:-staging}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/root/.restic_password}"
RESTORE_DIR="/tmp/restore_${SNAPSHOT}"

echo "=========================================="
echo "Khôi phục dữ liệu từ Snapshot: ${SNAPSHOT}"
echo "Môi trường đích: ${TARGET_ENV}"
echo "=========================================="

mkdir -p "${RESTORE_DIR}"
export RESTIC_PASSWORD_FILE

echo "-> Tải snapshot từ repository..."
restic restore "${SNAPSHOT}" --target "${RESTORE_DIR}"

# Xác định file dump database
DUMP_FILE=$(find "${RESTORE_DIR}" -name "*.sql.gz" | head -n 1)

if [[ -z "$DUMP_FILE" ]]; then
    echo "Lỗi: Không tìm thấy file SQL dump trong bản restore!"
    exit 1
fi

echo "-> Đã tìm thấy SQL dump: ${DUMP_FILE}"

CONTAINER="${TARGET_ENV}-mysql-1"
DB_NAME="app_${TARGET_ENV}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo "Lỗi: Container ${CONTAINER} không chạy. Khởi động môi trường trước."
    exit 1
fi

read -p "CẢNH BÁO: Thao tác này sẽ ghi đè database ${DB_NAME} trên ${TARGET_ENV}. Tiếp tục? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Huỷ thao tác restore."
    rm -rf "${RESTORE_DIR}"
    exit 0
fi

echo "-> Đang import dữ liệu vào container ${CONTAINER}..."
zcat "${DUMP_FILE}" | docker exec -i "${CONTAINER}" mysql -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}"

echo "-> Dọn dẹp file tạm..."
rm -rf "${RESTORE_DIR}"

echo "=========================================="
echo "Khôi phục thành công vào ${TARGET_ENV}!"
echo "=========================================="
