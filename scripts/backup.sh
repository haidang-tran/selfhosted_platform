#!/usr/bin/env bash
set -euo pipefail

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="/var/backups/platform/${TIMESTAMP}"
PROD_DB_CONTAINER="production-mysql-1"
DB_NAME="app_production"
RESTIC_REPO="${RESTIC_REPO:-s3:s3.amazonaws.com/my-platform-backups}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-/root/.restic_password}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

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
    docker exec "${PROD_DB_CONTAINER}" mysqldump --single-transaction --quick -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}" | gzip > "${DUMP_FILE}"
    notify "Database dump completed: ${DUMP_FILE}"
else
    notify "WARNING: Database container ${PROD_DB_CONTAINER} not running, skipping DB dump."
fi

# 2. Backup volumes and configurations via restic
export RESTIC_PASSWORD_FILE
restic backup \
    "${BACKUP_DIR}" \
    /var/lib/docker/volumes/production_prod-mysql-data \
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
