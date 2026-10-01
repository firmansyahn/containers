#!/usr/bin/env bash
# Smoke test for a freshly built vip-manager image.
# Called by .github/workflows/build.yml with IMAGE and WANT set.
#
# Everything runs under Docker, which gives a non-root container no inheritable
# or ambient capabilities. That is the strict case: Podman hands them out, and
# would hide an image that only works there.
#
# The VIP moves on a veth pair inside a network namespace of its own, held by a
# throwaway container, so nothing touches the runner's network. etcd is a
# throwaway too, with TLS and client certificates. The client key is owned by
# root:root, as a deployment writes it: with mode 0440, which uid 1001 reads
# through group 0, and with mode 0400, which only root can read.
set -euo pipefail

: "${IMAGE:?IMAGE not set}"
: "${WANT:?WANT not set}"

etcd_image=quay.io/coreos/etcd:v3.5.17
tools_image=docker.io/bitnami/minideb:trixie

id="vipsmoke-$$"
subnet=198.51.100.0/24        # documentation range, for the etcd network
etcd_ip=198.51.100.2
vip=192.0.2.10                # documentation range, for the VIP
key=/service/smoke/leader
me=smoke-node-1               # this node's trigger value
other=smoke-node-2

work=$(mktemp -d)

cleanup() {
  local code=$?
  if [ "$code" -ne 0 ]; then
    for c in $(docker ps -aq --filter "label=$id"); do
      echo "--- $(docker inspect -f '{{.Name}}' "$c")"
      docker logs "$c" 2>&1 | tail -25 || true
    done
  fi
  docker ps -aq --filter "label=$id" | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker network rm "$id" >/dev/null 2>&1 || true
  docker volume rm "$id-certs" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() { echo "::error::$*"; exit 1; }
pass() { echo "ok: $*"; }

# --- version (R20) -----------------------------------------------------------

got=$(docker run --rm --label "$id" -e DISABLE_WELCOME_MESSAGE=1 "$IMAGE" vip-manager --version \
  | sed -n 's/^version: *//p')
[ "$got" = "$WANT" ] || fail "image reports vip-manager ${got:-nothing}, Dockerfile says $WANT"
pass "vip-manager $got"

# --- branding (AE6) ----------------------------------------------------------

out=$(docker run --rm --label "$id" -e STARTECHNICA_DEBUG=true -e STARTECHNICA_COLOR=false "$IMAGE" true 2>&1)
grep -q 'Welcome to the Startechnica vip-manager container' <<<"$out" || fail "the banner does not name startechnica"
# liblog prints a colour reset after the level even with STARTECHNICA_COLOR=false.
grep -qE 'DEBUG.* ==> Running as uid' <<<"$out" || fail "STARTECHNICA_DEBUG=true logged nothing at debug level"
docker run --rm --label "$id" --entrypoint /bin/bash "$IMAGE" -c '
  [ ! -e /opt/bitnami ] || { echo "/opt/bitnami exists"; exit 1; }
  if found=$(find /opt /usr/sbin /entrypoint.sh /run.sh -iname "*bitnami*"); [ -n "$found" ]; then
    echo "$found"; exit 1
  fi
  if grep -rIl -e /opt/bitnami -e libbitnami -e BITNAMI_ /opt/startechnica \
       /usr/sbin/install_packages /usr/sbin/uninstall_packages /usr/sbin/run-script; then
    exit 1
  fi
' || fail "the image still refers to the Bitnami layout"
if docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | grep '^BITNAMI_'; then
  fail "the image sets BITNAMI_* variables"
fi
pass "branded startechnica, nothing left of the Bitnami layout"

# --- etcd with TLS -----------------------------------------------------------

cd "$work"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=smoke-ca \
  -keyout ca.key -out ca.crt 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj /CN=etcd -keyout server.key -out server.csr 2>/dev/null
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 1 -out server.crt \
  -extfile <(printf 'subjectAltName=IP:%s,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n' "$etcd_ip") 2>/dev/null
openssl req -newkey rsa:2048 -nodes -subj /CN=vip-manager -keyout client.key -out client.csr 2>/dev/null
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 1 -out client.crt \
  -extfile <(printf 'extendedKeyUsage=clientAuth\n') 2>/dev/null

# Two copies of the client key, both root:root: client.key with mode 0440, which
# uid 1001 reads through group 0, and client-root.key with mode 0400.
docker volume create "$id-certs" >/dev/null
tar -c ca.crt server.crt server.key client.crt client.key \
  | docker run --rm -i --label "$id" --user 0 -v "$id-certs:/certs" --entrypoint /bin/bash "$tools_image" -c '
      set -e
      tar -x -C /certs
      cp /certs/client.key /certs/client-root.key
      chown 0:0 /certs/*
      chmod 0444 /certs/*.crt
      chmod 0440 /certs/client.key
      chmod 0400 /certs/server.key /certs/client-root.key
      chmod 0755 /certs'
cd - >/dev/null

docker network create --subnet "$subnet" "$id" >/dev/null
docker run -d --name "$id-etcd" --label "$id" --network "$id" --ip "$etcd_ip" \
  -v "$id-certs:/certs:ro" "$etcd_image" \
  etcd --name smoke --data-dir /etcd-data \
    --listen-client-urls https://0.0.0.0:2379 --advertise-client-urls "https://$etcd_ip:2379" \
    --cert-file /certs/server.crt --key-file /certs/server.key \
    --trusted-ca-file /certs/ca.crt --client-cert-auth >/dev/null

etcdctl() {
  docker exec "$id-etcd" etcdctl --endpoints https://127.0.0.1:2379 \
    --cacert /certs/ca.crt --cert /certs/client.crt --key /certs/client-root.key "$@"
}
for _ in $(seq 30); do etcdctl endpoint health >/dev/null 2>&1 && break; sleep 1; done
etcdctl endpoint health >/dev/null 2>&1 || fail "etcd never became healthy"
etcdctl put "$key" "$other" >/dev/null

# --- a network namespace to move the VIP in ----------------------------------

# A veth pair that never leaves the namespace, with tcpdump on the end that
# carries the VIP, to see the gratuitous ARP.
docker run -d --name "$id-ns" --label "$id" --network "$id" --cap-add NET_ADMIN --cap-add NET_RAW \
  --entrypoint /bin/bash "$tools_image" -c '
    install_packages iproute2 tcpdump >/dev/null 2>&1
    ip link add vip0 type veth peer name vip0-peer
    ip link set vip0 up
    ip link set vip0-peer up
    exec tcpdump -i vip0 -n -l arp 2>&1' >/dev/null
for _ in $(seq 120); do docker logs "$id-ns" 2>&1 | grep -q 'listening on vip0' && break; sleep 1; done
docker logs "$id-ns" 2>&1 | grep -q 'listening on vip0' || fail "the test namespace never came up"

has_vip() { docker exec "$id-ns" ip -o addr show dev vip0 | grep -q " $vip/32 "; }
wait_vip() {
  local want=$1
  for _ in $(seq 40); do
    if has_vip; then [ "$want" = present ] && return 0; else [ "$want" = absent ] && return 0; fi
    sleep 0.5
  done
  return 1
}
wait_running() {
  for _ in $(seq 60); do
    [ "$(docker exec "$1" cat /proc/1/comm 2>/dev/null)" = vip-manager ] && return 0
    sleep 0.5
  done
  return 1
}

in_ns=(--label "$id" --network "container:$id-ns" -v "$id-certs:/certs:ro")
caps=(--cap-add NET_ADMIN --cap-add NET_RAW)
env=(
  -e VIP_IP="$vip" -e VIP_NETMASK=32 -e VIP_INTERFACE=vip0
  -e VIP_TRIGGER_KEY="$key" -e VIP_TRIGGER_VALUE="$me"
  -e VIP_DCS_TYPE=etcd -e VIP_DCS_ENDPOINTS="https://$etcd_ip:2379"
  -e VIP_ETCD_CA_FILE=/certs/ca.crt -e VIP_ETCD_CERT_FILE=/certs/client.crt
  -e VIP_INTERVAL=500
)

# --- uid 1001 moves the VIP and announces it (R13, R19, AE2) -----------------

docker run -d --name "$id-vip" "${in_ns[@]}" "${caps[@]}" "${env[@]}" \
  -e VIP_ETCD_KEY_FILE=/certs/client.key "$IMAGE" >/dev/null
wait_running "$id-vip" || fail "vip-manager never started as uid 1001"
status=$(docker exec "$id-vip" cat /proc/1/status)
[ "$(awk '/^Uid:/ {print $2}' <<<"$status")" = 1001 ] || fail "vip-manager is not running as uid 1001"
echo "vip-manager as uid 1001: $(grep -E '^Cap(Inh|Eff|Amb):' <<<"$status" | tr '\n\t' '  ')"

etcdctl put "$key" "$me" >/dev/null
wait_vip present || fail "the VIP never appeared when $key named this node"
for _ in $(seq 20); do docker logs "$id-ns" 2>&1 | grep 'ARP' | grep -qF "$vip" && break; sleep 0.5; done
docker logs "$id-ns" 2>&1 | grep 'ARP' | grep -qF "$vip" || fail "no gratuitous ARP for $vip was seen on vip0"
etcdctl put "$key" "$other" >/dev/null
wait_vip absent || fail "the VIP stayed when $key moved to another node"
docker rm -f "$id-vip" >/dev/null
pass "as uid 1001 under Docker, with a 0440 root:root key, the VIP was added, announced and removed"

# --- uid 1001 cannot read a key only root can read ---------------------------

out=$(timeout 60 docker run --rm "${in_ns[@]}" "${caps[@]}" "${env[@]}" \
  -e VIP_ETCD_KEY_FILE=/certs/client-root.key "$IMAGE" 2>&1) \
  && fail "as uid 1001, vip-manager ran with a 0400 key owned by root"
grep -q 'permission denied' <<<"$out" \
  || fail "as uid 1001, vip-manager failed with a 0400 root key, but not for lack of permission"
pass "as uid 1001, a 0400 root key cannot be read: it needs mode 0440"

# --- missing capabilities fail at startup (R14, AE3) -------------------------

out=$(timeout 60 docker run --rm "${in_ns[@]}" --cap-add NET_RAW "${env[@]}" \
  -e VIP_ETCD_KEY_FILE=/certs/client.key "$IMAGE" 2>&1) \
  && fail "the container ran without NET_ADMIN"
grep -q 'NET_ADMIN' <<<"$out" || fail "the container failed without NET_ADMIN, but did not name it"
pass "without NET_ADMIN, the container exits at startup and names it"

out=$(timeout 60 docker run --rm "${in_ns[@]}" "${caps[@]}" --security-opt no-new-privileges "${env[@]}" \
  -e VIP_ETCD_KEY_FILE=/certs/client.key "$IMAGE" 2>&1) \
  && fail "the container ran as uid 1001 under no-new-privileges"
grep -q 'no-new-privileges' <<<"$out" || fail "the container failed under no-new-privileges, but did not say why"
pass "under no-new-privileges, the container exits at startup and says why"

# --- no configuration at all (R9, R11, AE5) ----------------------------------

out=$(timeout 60 docker run --rm "${in_ns[@]}" "${caps[@]}" "$IMAGE" 2>&1) \
  && fail "vip-manager ran with no configuration"
grep -q 'Setting ip is mandatory' <<<"$out" || fail "with no configuration, vip-manager did not name the missing setting"
grep -q 'error reading config file' <<<"$out" && fail "with no file mounted, vip-manager was still given a config path"
pass "with no configuration, vip-manager names the missing setting"

# --- the config file, and variables over it (R9, R10, AE1) -------------------

cat > "$work/vip-manager.yml" <<EOF
ip: $vip
netmask: 32
interface: vip0
trigger-key: $key
trigger-value: $me
dcs-type: etcd
dcs-endpoints:
  - https://$etcd_ip:2379
etcd-ca-file: /certs/ca.crt
etcd-cert-file: /certs/client.crt
etcd-key-file: /certs/client.key
interval: 3000
EOF
chmod 0644 "$work/vip-manager.yml"
docker run -d --name "$id-file" "${in_ns[@]}" "${caps[@]}" -e VIP_INTERVAL=2000 \
  -v "$work/vip-manager.yml:/etc/default/vip-manager.yml:ro" "$IMAGE" >/dev/null
for _ in $(seq 30); do docker logs "$id-file" 2>&1 | grep -q 'This is the config that will be used' && break; sleep 1; done
out=$(docker logs "$id-file" 2>&1)
grep -q 'Using config from file: /etc/default/vip-manager.yml' <<<"$out" || fail "vip-manager did not read /etc/default/vip-manager.yml"
grep -qE '^\s*interval : 2000\s*$' <<<"$out" || fail "VIP_INTERVAL=2000 did not take precedence over the file's interval: 3000"
docker rm -f "$id-file" >/dev/null
pass "the mounted file is read, and VIP_* variables take precedence over it"

# --- root stays root, and reads a key only root can read (R12, AE4) ----------

docker run -d --name "$id-root" --user 0 "${in_ns[@]}" "${caps[@]}" "${env[@]}" \
  -e VIP_ETCD_KEY_FILE=/certs/client-root.key "$IMAGE" >/dev/null
wait_running "$id-root" || fail "vip-manager never started as root"
[ "$(docker exec "$id-root" awk '/^Uid:/ {print $2}' /proc/1/status)" = 0 ] \
  || fail "started as root, vip-manager switched to another user"
etcdctl put "$key" "$me" >/dev/null
wait_vip present || fail "as root, the VIP never appeared"
etcdctl put "$key" "$other" >/dev/null
wait_vip absent || fail "as root, the VIP stayed when $key moved to another node"
pass "as root, vip-manager stays root, reads a 0400 root key and moves the VIP"
