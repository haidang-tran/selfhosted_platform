# Kế hoạch CI/CD (triển khai sau)

> Trạng thái: **chưa triển khai**. Code dưới đây đã được viết thử rồi gỡ khỏi repo, giữ lại làm bản thiết kế cho Giai đoạn 7 trong `project.md`.
> Lưu ý: bản nháp này chưa từng chạy thật trên GitHub Actions.

## 1. Luồng tổng quan

```
Pull Request ──► CI: lint → build → smoke test → Trivy scan

push develop ──► CI ──► build & push GHCR ──► deploy staging (tự động)
push main    ──► CI ──► build & push GHCR ──► ⏸ chờ approve ──► deploy production
Chạy tay     ──► deploy một image_tag cũ (rollback)
```

- **CI** (`ci.yml`): ShellCheck các script, `docker compose config` cho staging/production, build image frontend, smoke test HTTP 200, quét Trivy (fail khi có CVE HIGH/CRITICAL đã có bản vá).
- **CD** (`cd.yml`): gọi lại CI → build và push image tag `<env>-<sha7>` + `<env>` lên GHCR → vào server qua Tailscale + SSH → rsync compose và `deploy.sh` → chạy `deploy.sh <env> <tag>`.
- **Rollback tự động**: `deploy.sh` dùng `up --wait`. Nếu healthcheck fail thì quay về tag đã lưu trong `.deployed_tag`.
- **Rollback thủ công**: Actions → CD → *Run workflow* → chọn môi trường + tag cũ, ví dụ `production-a7a3e45`. Tag phải cùng môi trường vì mỗi image chứa HTML riêng của môi trường đó.

## 2. Checklist khi triển khai

### Thay đổi trong repo
- [ ] Tạo `.github/workflows/ci.yml` (mục 4.1)
- [ ] Tạo `.github/workflows/cd.yml` (mục 4.2)
- [ ] Tạo `docker/frontend/Dockerfile` (mục 4.3)
- [ ] Tạo `.dockerignore` ở thư mục gốc (mục 4.4)
- [ ] Sửa `compose/staging/docker-compose.yml` và `compose/production/docker-compose.yml` (mục 4.5)
- [ ] Sửa `scripts/deploy.sh`: thêm `--wait` + rollback (mục 4.6)
- [ ] `compose/production/.env.example`: `GHCR_IMAGE_TAG=latest` → `GHCR_IMAGE_TAG=production`
- [ ] `.gitignore`: thêm dòng `.deployed_tag`

### GitHub
- [ ] Tạo nhánh `develop`
- [ ] Settings → Environments: tạo `staging` và `production`. Với `production`, bật *Required reviewers*
- [ ] Secrets: `TS_AUTHKEY` (Tailscale, nên ephemeral), `SSH_KEY`, `DEPLOY_HOST` (IP/hostname Tailscale), `DEPLOY_USER`
- [ ] (Tuỳ chọn) Variable `DEPLOY_PATH`, mặc định `/opt/selfhosted-platform`
- [ ] Không cần `GHCR_TOKEN`: workflow dùng `GITHUB_TOKEN`

### Server
- [ ] User deploy thuộc group `docker`
- [ ] Có `rsync`
- [ ] Đã tạo network `stg-net`, `prod-net`
- [ ] Có sẵn `$DEPLOY_PATH/compose/<env>/.env` (pipeline không đụng tới file này)

## 3. Hạn chế và điểm cần cải thiện
- Chỉ `frontend` được build thành image. `api` vẫn là mock (`nginx:alpine` + `api-mock`) vì chưa có code backend.
- Trivy đang pin `0.58.1`: nên cập nhật bản mới và pin theo digest.
- CD dùng `ssh-keyscan` mỗi lần deploy. Chấp nhận được vì đi trong tailnet, nhưng chặt hơn thì nên lưu host key vào secret `known_hosts`.

## 4. Code tham khảo

### 4.1 `.github/workflows/ci.yml`

```yaml
name: CI

# Kiểm tra mọi Pull Request; CD cũng gọi lại workflow này trước khi deploy
on:
  pull_request:
  workflow_call:

permissions:
  contents: read

jobs:
  lint:
    name: Lint scripts & compose
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: ShellCheck scripts
        run: shellcheck --severity=error scripts/*.sh

      - name: Validate docker-compose files
        run: |
          for env in staging production; do
            cp "compose/${env}/.env.example" "compose/${env}/.env"
            docker compose -f "compose/${env}/docker-compose.yml" config --quiet
            echo "compose/${env}: OK"
          done

  build-test:
    name: Build & test image (${{ matrix.env }})
    runs-on: ubuntu-latest
    needs: lint
    strategy:
      matrix:
        env: [staging, production]
    steps:
      - uses: actions/checkout@v4

      - name: Build image
        run: |
          docker build -f docker/frontend/Dockerfile \
            --build-arg APP_ENV=${{ matrix.env }} \
            -t frontend:ci .

      - name: Smoke test (container phải trả về HTTP 200)
        run: |
          docker run -d --name fe -p 8080:80 frontend:ci
          for i in $(seq 1 10); do
            curl -fsS http://localhost:8080/ > /dev/null && break
            sleep 1
          done
          curl -fsS http://localhost:8080/ | grep -qi "<title>"
          docker rm -f fe

      - name: Trivy scan (fail nếu có CVE HIGH/CRITICAL đã có bản vá)
        run: |
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
            aquasec/trivy:0.58.1 image \
            --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
            frontend:ci
```

### 4.2 `.github/workflows/cd.yml`

```yaml
name: CD

# develop -> staging (tự động) | main -> production (cần approve)
# Chạy tay (workflow_dispatch) với image_tag cũ để rollback
on:
  push:
    branches: [develop, main]
  workflow_dispatch:
    inputs:
      environment:
        description: Môi trường deploy
        type: choice
        options: [staging, production]
      image_tag:
        description: Tag image cần deploy, cùng môi trường (vd production-abc1234)
        required: true

concurrency:
  group: deploy-${{ github.ref_name }}
  cancel-in-progress: false

env:
  IMAGE: ghcr.io/${{ github.repository }}/frontend
  TARGET_ENV: ${{ github.event_name == 'workflow_dispatch' && inputs.environment || (github.ref_name == 'main' && 'production' || 'staging') }}

jobs:
  ci:
    if: github.event_name == 'push'
    uses: ./.github/workflows/ci.yml

  build:
    name: Build & push image
    if: github.event_name == 'push'
    needs: ci
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      tag: ${{ steps.vars.outputs.tag }}
    steps:
      - uses: actions/checkout@v4

      - id: vars
        run: echo "tag=${TARGET_ENV}-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build & push
        run: |
          docker build -f docker/frontend/Dockerfile \
            --build-arg APP_ENV=${TARGET_ENV} \
            -t ${IMAGE}:${{ steps.vars.outputs.tag }} \
            -t ${IMAGE}:${TARGET_ENV} .
          docker push --all-tags ${IMAGE}

  deploy:
    name: Deploy ${{ github.event_name == 'workflow_dispatch' && inputs.environment || (github.ref_name == 'main' && 'production' || 'staging') }}
    needs: build
    # Chạy cả khi build bị skip (trường hợp rollback bằng workflow_dispatch)
    if: ${{ !failure() && !cancelled() }}
    runs-on: ubuntu-latest
    # Environment "production" cấu hình Required reviewers -> bước approve thủ công
    environment: ${{ github.event_name == 'workflow_dispatch' && inputs.environment || (github.ref_name == 'main' && 'production' || 'staging') }}
    permissions:
      contents: read
      packages: read
    env:
      IMAGE_TAG: ${{ inputs.image_tag || needs.build.outputs.tag }}
      DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
      DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
      DEPLOY_PATH: ${{ vars.DEPLOY_PATH || '/opt/selfhosted-platform' }}
    steps:
      - uses: actions/checkout@v4

      - name: Kết nối Tailscale
        uses: tailscale/github-action@v3
        with:
          authkey: ${{ secrets.TS_AUTHKEY }}

      - name: Cấu hình SSH
        env:
          SSH_KEY: ${{ secrets.SSH_KEY }}
        run: |
          install -m 700 -d ~/.ssh
          echo "$SSH_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          # Kết nối đi qua tailnet (WireGuard đã xác thực peer) nên keyscan chấp nhận được
          ssh-keyscan -H "$DEPLOY_HOST" >> ~/.ssh/known_hosts

      - name: Đồng bộ file compose & script lên server
        run: |
          ssh "$DEPLOY_USER@$DEPLOY_HOST" "mkdir -p $DEPLOY_PATH/compose/$TARGET_ENV $DEPLOY_PATH/scripts"
          # Không dùng --delete để giữ nguyên .env & .deployed_tag trên server
          rsync -az --exclude '.env' "compose/$TARGET_ENV/" "$DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH/compose/$TARGET_ENV/"
          rsync -az scripts/deploy.sh "$DEPLOY_USER@$DEPLOY_HOST:$DEPLOY_PATH/scripts/"

      - name: Deploy (tự rollback nếu healthcheck fail)
        env:
          GHCR_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo "$GHCR_TOKEN" | ssh "$DEPLOY_USER@$DEPLOY_HOST" \
            "docker login ghcr.io -u ${{ github.actor }} --password-stdin"
          ssh "$DEPLOY_USER@$DEPLOY_HOST" "bash $DEPLOY_PATH/scripts/deploy.sh $TARGET_ENV $IMAGE_TAG"

      - name: Đăng xuất GHCR trên server
        if: always()
        run: ssh "$DEPLOY_USER@$DEPLOY_HOST" "docker logout ghcr.io" || true
```

### 4.3 `docker/frontend/Dockerfile`

```dockerfile
# Image frontend: đóng gói trang tĩnh của từng môi trường vào nginx
# Build: docker build -f docker/frontend/Dockerfile --build-arg APP_ENV=staging .
FROM nginx:alpine

ARG APP_ENV=staging
COPY compose/${APP_ENV}/html/ /usr/share/nginx/html/
```

### 4.4 `.dockerignore`

```
.git
.github
**/.env
docs
monitoring
ansible
*.drawio
```

### 4.5 Thay đổi service `frontend` trong compose

Dùng image từ GHCR thay cho mount `./html` (production đổi default tag thành `production`):

```diff
   frontend:
-    image: nginx:alpine
+    image: ghcr.io/haidang-tran/selfhosted-platform/frontend:${GHCR_IMAGE_TAG:-staging}
     container_name: stg-frontend
     restart: unless-stopped
     ports:
       - "127.0.0.1:${FRONTEND_PORT:-9080}:80"
-    volumes:
-      - ./html:/usr/share/nginx/html:ro
     networks:
       - stg-net
```

### 4.6 Thay đổi `scripts/deploy.sh`

```diff
@@ -29,26 +29,29 @@ fi
 # Cập nhật IMAGE_TAG trong runtime nếu được chỉ định
 export GHCR_IMAGE_TAG="${IMAGE_TAG}"
 
+# Tag đang chạy ổn định gần nhất, dùng để rollback khi deploy lỗi
+TAG_FILE=".deployed_tag"
+PREVIOUS_TAG="$(cat "${TAG_FILE}" 2>/dev/null || true)"
+
 echo "-> Kéo Docker images mới..."
 docker compose -p "${TARGET_ENV}" pull
 
-echo "-> Triển khai các container mới (zero-downtime rolling restart)..."
-docker compose -p "${TARGET_ENV}" up -d --remove-orphans
-
-echo "-> Chờ container khởi động & kiểm tra healthcheck..."
-sleep 5
-
-docker compose -p "${TARGET_ENV}" ps
-
-# Kiểm tra trạng thái container
-UNHEALTHY=$(docker compose -p "${TARGET_ENV}" ps | grep -i "unhealthy" || true)
-if [[ -n "${UNHEALTHY}" ]]; then
-    echo "CẢNH BÁO: Phát hiện container không healthy:"
-    echo "${UNHEALTHY}"
+echo "-> Triển khai các container mới & chờ healthcheck (tối đa 120s)..."
+if ! docker compose -p "${TARGET_ENV}" up -d --remove-orphans --wait --wait-timeout 120; then
+    echo "CẢNH BÁO: Container không healthy sau khi deploy tag ${IMAGE_TAG}"
+    docker compose -p "${TARGET_ENV}" ps
+    if [[ -n "${PREVIOUS_TAG}" && "${PREVIOUS_TAG}" != "${IMAGE_TAG}" ]]; then
+        echo "-> Rollback về tag trước: ${PREVIOUS_TAG}"
+        export GHCR_IMAGE_TAG="${PREVIOUS_TAG}"
+        docker compose -p "${TARGET_ENV}" up -d --remove-orphans --wait --wait-timeout 120
+    fi
     echo "Cần kiểm tra log ngay bằng lệnh: docker compose -p ${TARGET_ENV} logs"
     exit 1
 fi
 
+docker compose -p "${TARGET_ENV}" ps
+echo "${IMAGE_TAG}" > "${TAG_FILE}"
+
 echo "=========================================="
 echo "Triển khai ${TARGET_ENV} hoàn tất thành công!"
 echo "=========================================="
```
