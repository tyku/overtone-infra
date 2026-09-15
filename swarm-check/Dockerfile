FROM docker:29.0.0-cli-alpine3.22
ARG APP_VERSION
LABEL org.opencontainers.image.revision=$APP_VERSION
RUN apk add --no-cache curl coreutils
COPY scripts/swarm-check.sh /usr/local/bin/swarm-check
RUN chmod 0555 /usr/local/bin/swarm-check
ENTRYPOINT ["/usr/local/bin/swarm-check", "--loop"]
