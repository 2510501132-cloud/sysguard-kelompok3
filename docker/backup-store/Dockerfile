# Backup store: server SSH/SFTP minimal. Hanya user 'backup', hanya login dengan key.
FROM alpine:3.20
RUN apk add --no-cache openssh-server \
 && addgroup -g 1001 backup \
 && adduser -D -u 1001 -G backup -s /bin/ash backup \
 && echo "backup:$(head -c 32 /dev/urandom | base64)" | chpasswd \
 && mkdir -p /backups /etc/ssh/hostkeys \
 && chown backup:backup /backups && chmod 700 /backups
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh
EXPOSE 22
VOLUME ["/backups", "/etc/ssh/hostkeys"]
ENTRYPOINT ["/entrypoint.sh"]
