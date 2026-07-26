#!/usr/bin/env bash
#
# Start / stop / reset a MiniStack container for Terraform integration tests.
#
# MiniStack is an MIT-licensed local AWS emulator that exposes every service on
# a single endpoint (default :4566). It is free with no sign-up, no API key and
# no license token, and it covers the services this project needs — EC2, IAM,
# STS, EKS, EFS, Route53, Cognito, SecretsManager and CloudWatch Logs.
#
# This is the only emulator the Terraform suites run against.
#
# Usage:
#   ./ministack.sh up      # start and block until healthy
#   ./ministack.sh down    # stop and remove
#   ./ministack.sh reset   # wipe all emulated state, keep the container
#   ./ministack.sh env     # print the env vars to export for Terraform
#
set -euo pipefail

CONTAINER_NAME="${MINISTACK_CONTAINER_NAME:-ministack-tf-tests}"
IMAGE="${MINISTACK_IMAGE:-ministackorg/ministack:latest}"
PORT="${MINISTACK_PORT:-4566}"
ENDPOINT="http://localhost:${PORT}"
HEALTH_TIMEOUT_SECONDS="${MINISTACK_HEALTH_TIMEOUT:-90}"

log() { printf '[ministack] %s\n' "$*" >&2; }

wait_for_health() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS))
  log "waiting for ${ENDPOINT}/_ministack/health"
  while ((SECONDS < deadline)); do
    if curl -fsS "${ENDPOINT}/_ministack/health" >/dev/null 2>&1; then
      log "healthy after $((SECONDS))s"
      return 0
    fi
    sleep 2
  done
  log "did not become healthy within ${HEALTH_TIMEOUT_SECONDS}s"
  docker logs "${CONTAINER_NAME}" 2>&1 | tail -50 >&2 || true
  return 1
}

cmd_up() {
  if docker inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
    log "container ${CONTAINER_NAME} already exists, reusing it"
    docker start "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  else
    log "starting ${IMAGE} on port ${PORT}"
    # The docker socket is mounted because MiniStack backs some services with
    # real containers — notably EKS, which brings up a k3s cluster.
    docker run -d \
      --name "${CONTAINER_NAME}" \
      -p "${PORT}:4566" \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -e MINISTACK_REGION=us-east-1 \
      -e LOG_LEVEL="${MINISTACK_LOG_LEVEL:-INFO}" \
      "${IMAGE}" >/dev/null
  fi
  wait_for_health
}

cmd_down() {
  log "removing ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}

cmd_reset() {
  log "resetting emulated state"
  curl -fsS -X POST "${ENDPOINT}/_ministack/reset" >/dev/null
}

cmd_env() {
  cat <<EOF
export AWS_ENDPOINT_URL=${ENDPOINT}
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1
EOF
}

case "${1:-}" in
  up) cmd_up ;;
  down) cmd_down ;;
  reset) cmd_reset ;;
  env) cmd_env ;;
  *)
    echo "usage: $0 {up|down|reset|env}" >&2
    exit 64
    ;;
esac
