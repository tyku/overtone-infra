FROM nginx:1.28.0-alpine3.21
ARG APP_VERSION
LABEL org.opencontainers.image.revision=$APP_VERSION
ENV NGINX_ENVSUBST_FILTER='^(PUBLIC_SERVER_NAME|ADMIN_ALLOW_RULES)$'
COPY nginx/gateway.conf.template /etc/nginx/templates/default.conf.template
COPY nginx/proxy_params /etc/nginx/proxy_params
HEALTHCHECK --interval=15s --timeout=5s --retries=5 \
  CMD wget -qO- http://127.0.0.1/nginx-health >/dev/null || exit 1
