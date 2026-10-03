#!/usr/bin/env bash
set -euo pipefail

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/platform/${TIMESTAMP}"
PROD_DB_CONTAINER="prod-mysql"
DB_NAME="app_production"
RESTIC_REPO="${RESTIC_REPO:-/var/backups/restic-repo}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/root/.restic_password}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-8707225772:AAFXAd6ogKi6RWI2UehFiCfoc3RarJCsIWo}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-7961049003}"

notify() {
    local msg="$1"
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${msg}" >/dev/null || true
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg"
}

mkdir -p "${BACKUP_DIR}"

notify "Starting daily backup: ${TIMESTAMP}"

# 1. Dump MySQL database
DUMP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"
if docker ps --format '{{.Names}}' | grep -q "^${PROD_DB_CONTAINER}$"; then
    # Lấy mật khẩu từ environment nếu có, hoặc dùng mật khẩu mặc định
    MYSQL_PWD="${MYSQL_ROOT_PASSWORD:-prod_root_pass_ultra_secure_2026}"
    docker exec "${PROD_DB_CONTAINER}" mysqldump --single-transaction --quick -u root -p"${MYSQL_PWD}" "${DB_NAME}" | gzip > "${DUMP_FILE}"
    notify "Database dump completed: ${DUMP_FILE}"
else
    notify "WARNING: Database container ${PROD_DB_CONTAINER} not running, skipping DB dump."
fi

# 2. Backup volumes and configurations via restic
export RESTIC_PASSWORD_FILE
export RESTIC_REPOSITORY="${RESTIC_REPO}"
restic backup \
    "${BACKUP_DIR}" \
    /var/lib/docker/volumes/prod-mysql-data \
    /etc/nginx \
    /etc/ssh \
    /opt/selfhosted-platform \
    --tag "daily-${TIMESTAMP}"

# 3. Apply retention policy
restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune

# Cleanup local dump directory
rm -rf "${BACKUP_DIR}"

notify "Daily backup successfully completed and pruned."
