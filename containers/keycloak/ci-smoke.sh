#!/usr/bin/env bash
# Smoke test for a freshly built keycloak image.
# Called by .github/workflows/build.yml with IMAGE and WANT set.
#
# Keycloak cannot be started without a database: the Bitnami entrypoint defaults
# KEYCLOAK_DATABASE_HOST to "postgresql" and blocks on wait-for-port until it
# answers. So the test stands up a throwaway PostgreSQL on its own network and
# lets Keycloak run its real schema migration against it.
set -euo pipefail

: "${IMAGE:?IMAGE not set}"
: "${WANT:?WANT not set}"

net="keycloak-smoke-net-$$"
pg="keycloak-smoke-pg-$$"
name="keycloak-smoke-$$"

db_name=bitnami_keycloak
db_user=bn_keycloak
db_pass=smoketest

cleanup() {
  docker logs "$name" 2>&1 | tail -30 || true
  docker rm -f "$name" "$pg" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$net" >/dev/null

# The network alias has to be "postgresql" — that is the host the entrypoint
# waits for when KEYCLOAK_DATABASE_HOST is left at its default.
docker run -d --name "$pg" --network "$net" --network-alias postgresql \
  -e POSTGRES_DB="$db_name" \
  -e POSTGRES_USER="$db_user" \
  -e POSTGRES_PASSWORD="$db_pass" \
  docker.io/library/postgres:16-alpine >/dev/null

for _ in $(seq 30); do
  if docker exec "$pg" pg_isready -q -U "$db_user" -d "$db_name"; then break; fi
  sleep 2
done
docker exec "$pg" pg_isready -U "$db_user" -d "$db_name"

docker run -d --name "$name" --network "$net" \
  -e KEYCLOAK_DATABASE_NAME="$db_name" \
  -e KEYCLOAK_DATABASE_USER="$db_user" \
  -e KEYCLOAK_DATABASE_PASSWORD="$db_pass" \
  "$IMAGE" >/dev/null

for _ in $(seq 90); do
  if line=$(docker logs "$name" 2>&1 | grep -m1 -E 'Keycloak [0-9.]+ .* started in'); then
    got=$(echo "$line" | grep -oP 'Keycloak \K[0-9.]+')
    if [ "$got" != "$WANT" ]; then
      echo "::error::image reports keycloak $got, Dockerfile says $WANT"
      exit 1
    fi
    echo "keycloak $got booted against PostgreSQL as uid $(docker exec "$name" id -u)"
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
