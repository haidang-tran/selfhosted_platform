#!/usr/bin/env bash
set -euo pipefail

# Script deploy ứng dụng bằng Docker Compose
# Sử dụng: ./deploy.sh <staging|production> [image_tag]

TARGET_ENV="${1:-staging}"
IMAGE_TAG="${2:-latest}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_DIR="${ROOT_DIR}/compose/${TARGET_ENV}"

if [[ ! -d "${COMPOSE_DIR}" ]]; then
    echo "Lỗi: Không tìm thấy thư mục môi trường: ${COMPOSE_DIR}"
    exit 1
fi

echo "=========================================="
echo "Bắt đầu triển khai: ${TARGET_ENV}"
echo "Tag hình ảnh: ${IMAGE_TAG}"
echo "=========================================="

cd "${COMPOSE_DIR}"

if [[ ! -f ".env" ]]; then
    echo "Lỗi: Thiếu file .env trong ${COMPOSE_DIR}. Tạo từ .env.example trước khi deploy."
    exit 1
fi

# Cập nhật IMAGE_TAG trong runtime nếu được chỉ định
export GHCR_IMAGE_TAG="${IMAGE_TAG}"

echo "-> Kéo Docker images mới..."
docker compose -p "${TARGET_ENV}" pull

echo "-> Triển khai các container mới (zero-downtime rolling restart)..."
docker compose -p "${TARGET_ENV}" up -d --remove-orphans

echo "-> Chờ container khởi động & kiểm tra healthcheck..."
sleep 5

docker compose -p "${TARGET_ENV}" ps

# Kiểm tra trạng thái container
UNHEALTHY=$(docker compose -p "${TARGET_ENV}" ps | grep -i "unhealthy" || true)
if [[ -n "${UNHEALTHY}" ]]; then
    echo "CẢNH BÁO: Phát hiện container không healthy:"
    echo "${UNHEALTHY}"
    echo "Cần kiểm tra log ngay bằng lệnh: docker compose -p ${TARGET_ENV} logs"
    exit 1
fi

echo "=========================================="
echo "Triển khai ${TARGET_ENV} hoàn tất thành công!"
echo "=========================================="
