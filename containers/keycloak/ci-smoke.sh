#!/usr/bin/env bash
# Smoke test for a freshly built keycloak image.
# Called by .github/workflows/build.yml with IMAGE and WANT set.
#
# No database is configured on purpose: with KC_DB unset the entrypoint runs
# kc.sh start-dev, which falls back to the embedded dev-file store. That is
# enough to prove the bundled JRE, the Quarkus augmentation and the Bitnami
# entrypoint all work — a real deployment still needs PostgreSQL.
set -euo pipefail

: "${IMAGE:?IMAGE not set}"
: "${WANT:?WANT not set}"

name="keycloak-smoke-$$"
cleanup() {
  docker logs "$name" 2>&1 | tail -30 || true
  docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$name" "$IMAGE"

for _ in $(seq 90); do
  if line=$(docker logs "$name" 2>&1 | grep -m1 -E 'Keycloak [0-9.]+ .* started in'); then
    got=$(echo "$line" | grep -oP 'Keycloak \K[0-9.]+')
    if [ "$got" != "$WANT" ]; then
      echo "::error::image reports keycloak $got, Dockerfile says $WANT"
      exit 1
    fi
    echo "keycloak $got booted as uid $(docker exec "$name" id -u)"
    echo "$line"
    exit 0
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$name")" != "true" ]; then
    echo "::error::container exited before keycloak finished starting"
    exit 1
  fi
  sleep 2
done

echo "::error::keycloak never finished starting"
exit 1
