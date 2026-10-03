# Image frontend: đóng gói trang tĩnh của từng môi trường vào nginx
# Build: docker build -f docker/frontend/Dockerfile --build-arg APP_ENV=staging .
FROM nginx:alpine

ARG APP_ENV=staging
COPY compose/${APP_ENV}/html/ /usr/share/nginx/html/
