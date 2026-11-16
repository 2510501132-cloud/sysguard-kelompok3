# Layanan yang dimonitor: nginx non-root (port 8080), konten dari bind mount read-only.
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY default.conf /etc/nginx/conf.d/default.conf
# Berjalan sebagai user 'nginx' (non-root) -- bawaan image.
EXPOSE 8080
