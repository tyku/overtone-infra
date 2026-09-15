#!/bin/sh
set -u

check_once() {
  failures=""
  details=""

  non_ready_nodes="$(docker node ls --format '{{.Hostname}} {{.Status}} {{.Availability}}' 2>/dev/null | awk '$2 != "Ready" || $3 != "Active" {print $1 ":" $2 "/" $3}' | paste -sd, -)"
  if [ -n "$non_ready_nodes" ]; then
    failures="${failures} nodes=${non_ready_nodes}"
  fi

  for expected in ${EXPECTED_SERVICES:-}; do
    service="${expected%%=*}"
    wanted="${expected#*=}"
    replicas="$(docker service ls --filter "name=${STACK_NAME}_${service}" --format '{{.Replicas}}' 2>/dev/null | head -n 1)"
    replicas="${replicas%% *}"
    running="${replicas%%/*}"
    desired="${replicas#*/}"
    if [ -z "$replicas" ] || [ "$running" != "$wanted" ] || [ "$desired" != "$wanted" ]; then
      failures="${failures} ${service}=${replicas:-missing}(want:${wanted}/${wanted})"
    fi
    details="${details} ${service}=${replicas:-missing}"
  done

  failed_tasks="$(docker service ps --filter desired-state=shutdown --format '{{.CurrentState}}|{{.Error}}' \
    "${STACK_NAME}_api" "${STACK_NAME}_worker" "${STACK_NAME}_gateway" 2>/dev/null | \
    awk -F'|' '$1 ~ /(second|minute)/ && $2 != "" {count++} END {print count+0}')"
  if [ "${failed_tasks:-0}" -gt 0 ]; then
    failures="${failures} failed_tasks=${failed_tasks}"
  fi

  disk_percent="$(df -P /var/run/docker.sock 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
  if [ -z "$disk_percent" ]; then
    disk_percent="$(df -P / 2>/dev/null | awk 'NR==2 {gsub(/%/, "", $5); print $5}')"
  fi
  if [ "${disk_percent:-100}" -ge "${DISK_WARN_PERCENT:-85}" ]; then
    failures="${failures} manager_disk=${disk_percent:-unknown}%"
  fi

  push_url=""
  if [ -s /run/secrets/uptime_push_url ]; then
    push_url="$(tr -d '\r\n' < /run/secrets/uptime_push_url)"
  fi

  if [ -n "$failures" ]; then
    echo "FAIL${failures};${details}; manager_disk=${disk_percent:-unknown}%" >&2
    if [ -n "$push_url" ]; then
      curl --fail --silent --show-error --get --data-urlencode status=down \
        --data-urlencode "msg=${failures}" --data-urlencode ping= "$push_url" >/dev/null || true
    fi
    return 1
  fi

  echo "OK${details}; manager_disk=${disk_percent}%"
  if [ -n "$push_url" ]; then
    curl --fail --silent --show-error --get --data-urlencode status=up \
      --data-urlencode "msg=swarm healthy${details}" --data-urlencode ping= "$push_url" >/dev/null || true
  fi
}

if [ "${1:-}" = "--loop" ]; then
  while :; do
    check_once || true
    sleep "${CHECK_INTERVAL_SECONDS:-60}"
  done
fi

check_once
