FROM alpine:3.21

RUN apk add --no-cache \
    git \
    restic \
    inotify-tools \
    busybox-extras \
    jq \
    bash \
    tzdata \
    curl

WORKDIR /app

COPY scripts/ /app/

RUN chmod +x /app/*.sh

USER root

ENV DEBOUNCE_SECONDS=300
ENV HEALTH_PORT=8080
ENV GIT_USER_NAME="Obsidian Backup"
ENV GIT_USER_EMAIL="backup@local"
ENV VAULT_PATH=/vault

EXPOSE 8080/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q --spider http://127.0.0.1:${HEALTH_PORT}/health || exit 1

ENTRYPOINT ["/app/entrypoint.sh"]
