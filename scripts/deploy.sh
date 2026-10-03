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

# Tag đang chạy ổn định gần nhất, dùng để rollback khi deploy lỗi
TAG_FILE=".deployed_tag"
PREVIOUS_TAG="$(cat "${TAG_FILE}" 2>/dev/null || true)"

echo "-> Kéo Docker images mới..."
docker compose -p "${TARGET_ENV}" pull

echo "-> Triển khai các container mới & chờ healthcheck (tối đa 120s)..."
if ! docker compose -p "${TARGET_ENV}" up -d --remove-orphans --wait --wait-timeout 120; then
    echo "CẢNH BÁO: Container không healthy sau khi deploy tag ${IMAGE_TAG}"
    docker compose -p "${TARGET_ENV}" ps
    if [[ -n "${PREVIOUS_TAG}" && "${PREVIOUS_TAG}" != "${IMAGE_TAG}" ]]; then
        echo "-> Rollback về tag trước: ${PREVIOUS_TAG}"
        export GHCR_IMAGE_TAG="${PREVIOUS_TAG}"
        docker compose -p "${TARGET_ENV}" up -d --remove-orphans --wait --wait-timeout 120
    fi
    echo "Cần kiểm tra log ngay bằng lệnh: docker compose -p ${TARGET_ENV} logs"
    exit 1
fi

docker compose -p "${TARGET_ENV}" ps
echo "${IMAGE_TAG}" > "${TAG_FILE}"

echo "=========================================="
echo "Triển khai ${TARGET_ENV} hoàn tất thành công!"
echo "=========================================="
