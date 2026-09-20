#!/usr/bin/env bash
# Smoke test for a freshly built redis image.
# Called by .github/workflows/build.yml with IMAGE and WANT set.
set -euo pipefail

: "${IMAGE:?IMAGE not set}"
: "${WANT:?WANT not set}"

name="redis-smoke-$$"
cleanup() {
  docker logs "$name" 2>&1 | tail -20 || true
  docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$name" -e ALLOW_EMPTY_PASSWORD=yes "$IMAGE"

for _ in $(seq 60); do
  if docker exec "$name" redis-cli ping 2>/dev/null | grep -q PONG; then
    got=$(docker exec "$name" redis-cli INFO server | grep -oP 'redis_version:\K[0-9.]+' | tr -d '\r')
    if [ "$got" != "$WANT" ]; then
      echo "::error::image reports redis $got, Dockerfile says $WANT"
      exit 1
    fi
    echo "redis $got answered PONG as uid $(docker exec "$name" id -u)"
    exit 0
  fi
  sleep 2
done

echo "::error::redis never answered PING"
exit 1
