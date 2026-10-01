# vip-manager, packaged by Startechnica

> vip-manager keeps a virtual IP address on the node that holds a key in etcd, Consul or Patroni's REST API. Run next to Patroni, it keeps the cluster's primary reachable at one address across failovers.

[vip-manager on GitHub](https://github.com/cybertec-postgresql/vip-manager)

Disclaimer: vip-manager is developed by Cybertec PostgreSQL International GmbH. Bitnami is a trademark of Broadcom. Both names are used here for reference only: this image is built in this repository, and neither of them sponsors, endorses or supports it.

## About this image

Unlike the [mirrors](../../README.md#mirrors), this image has no upstream image to rebuild. Upstream publishes release tarballs and packages only, and Bitnami never packaged vip-manager. So it is our own image, built the way the mirrors are:

- the `docker.io/bitnami/minideb:trixie` base (Debian 13), with packages upgraded at build time. The mirrors stay on Debian 12, as Bitnami built them; this image is new, so it starts on the current Debian release rather than on one past its regular security support;
- Bitnami's shared shell library and conventions (entrypoint, `run.sh`, banner, log format), rebranded: everything lives under `/opt/startechnica`, the library is `libstartechnica.sh`, and the switches are `STARTECHNICA_*`;
- vip-manager from upstream's Linux `x86_64` release tarball, checked against the sha256 recorded in this repo. Nothing is compiled;
- uid 1001 by default.

It is built for `linux/amd64` only, and published to `ghcr.io/firmansyahn/containers/vip-manager`:

| branch | vip-manager | upstream release | published tags |
| ------ | ----------- | ---------------- | -------------- |
| 5 | 5.0.0 | [v5.0.0](https://github.com/cybertec-postgresql/vip-manager/releases/tag/v5.0.0) (2026-07-30) | not published yet |
| 4 | 4.2.0 | [v4.2.0](https://github.com/cybertec-postgresql/vip-manager/releases/tag/v4.2.0) (2026-04-29) | not published yet |

### Which branch

**Use 5.** vip-manager 4.2.0 can leave the VIP up on two nodes after an etcd watch is cancelled ([#394](https://github.com/cybertec-postgresql/vip-manager/issues/394)). The fix ([#399](https://github.com/cybertec-postgresql/vip-manager/pull/399)) shipped only in 5.0.0, and upstream keeps no 4.x branch, so the 4 branch will never get it.

5.0.0 also removes the VIP when the DCS is unreachable. Patroni without `failsafe_mode` already demotes its primary in that case, so the VIP takes no writable endpoint with it.

5.0.0 dropped the deprecated parameter names that 4.x still maps to current ones ([#376](https://github.com/cybertec-postgresql/vip-manager/pull/376)). On the 5 branch they are ignored: a missing mandatory setting fails at startup, and an optional one silently falls back to its default. The 4 branch still accepts them, in the config file or as `VIP_` plus the upper-cased name (`VIP_IFACE`, …):

| deprecated, 4.x only | current |
| -------------------- | ------- |
| `mask` | `netmask` |
| `iface` | `interface` |
| `key` | `trigger-key` |
| `nodename`, `host` | `trigger-value` |
| `type`, `endpoint_type` | `dcs-type` |
| `endpoint`, `endpoints` | `dcs-endpoints` |
| `etcd_user`, `etcd_password` | `etcd-user`, `etcd-password` |
| `consul_token` | `consul-token` |
| `hostingtype`, `hosting_type` | `manager-type` |
| `retry_num`, `retry_after` | `retry-num`, `retry-after` |

## TL;DR

```console
docker run --name vip-manager --network host --cap-add NET_ADMIN --cap-add NET_RAW \
    -e VIP_IP=192.0.2.10 -e VIP_NETMASK=24 -e VIP_INTERFACE=eth0 \
    -e VIP_TRIGGER_KEY=/service/pgcluster/leader -e VIP_TRIGGER_VALUE=pgcluster-member1 \
    -e VIP_DCS_ENDPOINTS=http://192.0.2.2:2379 \
    ghcr.io/firmansyahn/containers/vip-manager:5
```

Each branch has a [`docker-compose.yml`](5/debian-13/docker-compose.yml) doing the same. It is not tested here.

## Privileges

vip-manager adds and removes the VIP on the host's own interface with `ip addr`, and announces it with a gratuitous ARP over a raw socket. So the container needs:

- host networking;
- `NET_ADMIN`, for `ip addr`;
- `NET_RAW`, for the gratuitous ARP.

### Running as uid 1001

Granting the capabilities is not enough for a non-root process. Docker gives a non-root container no inheritable or ambient capabilities. And Debian's `ip`, built with libcap, drops all of its capabilities at start for a non-root caller unless `NET_ADMIN` is in its inheritable set, so a file capability on `ip` itself is cancelled.

The image therefore carries one file capability, `cap_net_admin,cap_net_raw=p`, on a private copy of `setpriv` at `/opt/startechnica/vip-manager/libexec/setpriv`. `run.sh` re-executes itself through it, raising both capabilities into the inheritable and ambient sets. vip-manager, and every `ip` it runs, inherit them from there.

The container fails at startup, naming what is missing, rather than run without being able to move the VIP:

- before anything is raised, if the runtime did not grant `NET_ADMIN` and `NET_RAW`;
- if `no-new-privileges` is set, because it cancels the file capability;
- after the raise, if the process about to become vip-manager does not hold both capabilities in its effective, inheritable and ambient sets.

vip-manager itself only logs a failed `ip` and keeps running, so these checks are the only thing that stops a VIP that could never move.

**Do not set `no-new-privileges`** (`--security-opt no-new-privileges`, `security_opt` in compose, `NoNewPrivileges=true` in a Quadlet) for this container while it runs as uid 1001.

### Running as root

Started with `--user 0` (or `User=0` in a Quadlet), the container keeps vip-manager running as root. Unlike the mirrors, it does not switch to uid 1001. Use this when the etcd client key is readable by root only. `no-new-privileges` does no harm then.

## Configuration

vip-manager reads its own settings, and the image adds no aliases or wrappers for them. It takes them from `VIP_*` environment variables, from a config file, or from both. When a setting appears in more than one place, command-line flags win over variables, and variables win over the file.

### Config file

Mount it at `/etc/default/vip-manager.yml`, where upstream's `.deb` and `.rpm` packages install it. The image passes that path to vip-manager only when a file is there; vip-manager would otherwise fail with "fatal error reading config file". To use another path, set `VIP_CONFIG`. The file must then exist.

### Settings

| file key | variable | default |
| -------- | -------- | ------- |
| `ip` | `VIP_IP` | required |
| `netmask` | `VIP_NETMASK` | required |
| `interface` | `VIP_INTERFACE` | required |
| `trigger-key` | `VIP_TRIGGER_KEY` | required, except with `dcs-type: patroni` (`/leader`) |
| `trigger-value` | `VIP_TRIGGER_VALUE` | the hostname (`200` with `dcs-type: patroni`) |
| `dcs-type` | `VIP_DCS_TYPE` | `etcd`; also `consul`, `patroni` |
| `dcs-endpoints` | `VIP_DCS_ENDPOINTS` | `http://127.0.0.1:2379`, or `:8500` for consul and `:8008/` for patroni. A list in the file, comma-separated in the variable |
| `etcd-user`, `etcd-password` | `VIP_ETCD_USER`, `VIP_ETCD_PASSWORD` | |
| `etcd-ca-file` | `VIP_ETCD_CA_FILE` | turns on TLS |
| `etcd-cert-file`, `etcd-key-file` | `VIP_ETCD_CERT_FILE`, `VIP_ETCD_KEY_FILE` | client certificate |
| `consul-token` | `VIP_CONSUL_TOKEN` | |
| `interval` | `VIP_INTERVAL` | `1000` ms |
| `manager-type` | `VIP_MANAGER_TYPE` | `basic`; also `hetzner` |
| `retry-after` | `VIP_RETRY_AFTER` | `250` ms |
| `retry-num` | `VIP_RETRY_NUM` | `3` |
| `verbose` | `VIP_VERBOSE` | `false` |

Without the required settings, vip-manager exits at startup naming each one that is missing. At startup it prints the settings it will use, with `etcd-password` and `consul-token` masked. See upstream's [README](https://github.com/cybertec-postgresql/vip-manager#configuration) for the details.

The keys and certificates you mount must be readable by the user vip-manager runs as: uid 1001 with group 0, by default. A key owned by `root:root` with mode `0440` is enough, since vip-manager reads it through group 0. With mode `0400`, only root can read it, and vip-manager exits at startup with "permission denied".

### Image switches

These change only the image's own scripts, not vip-manager:

| variable | default | effect |
| -------- | ------- | ------ |
| `STARTECHNICA_DEBUG` | `false` | debug output from the scripts |
| `STARTECHNICA_QUIET` | `false` | no output from the scripts |
| `STARTECHNICA_COLOR` | `true` | coloured output |
| `DISABLE_WELCOME_MESSAGE` | unset | no startup banner |

## Healthcheck

`curl` is in the image, for a healthcheck against the DCS, and for vip-manager's hetzner mode. For example, against etcd with the client certificate:

```console
curl -fsS --cacert /certs/ca.crt --cert /certs/client.crt --key /certs/client.key https://192.0.2.2:2379/health
```

## Switching from a locally built vip-manager

What a deployment that builds vip-manager on each node, such as the patroni role in [startechnica/ansible-collection-infra](https://github.com/startechnica/ansible-collection-infra), changes to use this image:

- On amd64 nodes, pull this image, pinned to a 5.x revision tag or digest, never `latest`. Stop building vip-manager locally. A config written with current parameter names reads unchanged on 5.x.
- The nodes pull without a registry credential, so the package must be public. After every push, the pipeline warns if a pull without a credential fails.
- arm64 nodes have no image and keep building locally, so the choice between pulling and building is made per architecture.
- Keep mounting the config at `/etc/default/vip-manager.yml`.
- Give the etcd client key mode `0440` instead of `0400`, still owned by `root:root`. The container runs as uid 1001 with group 0, so vip-manager reads the key through its group, and so does a `curl` healthcheck run in the container. With `0400`, neither can. The fallback is to run the container as root.
- Keep `NET_ADMIN`, `NET_RAW` and host networking. Do not enable `no-new-privileges` while running as uid 1001.
- A `curl` healthcheck against etcd `/health` keeps working.

## Tags

Each branch is published as `<version>-debian-13-r<revision>`, `<version>` and `<branch>`, and the branch with the highest version also as `latest`.

A `-r<revision>` tag is pushed once and never again, so its digest stays valid: **pin that tag, or its digest**. `<version>`, `<branch>` and `latest` move to the new image when a branch gets a new revision.

## Smoke test

[`ci-smoke.sh`](ci-smoke.sh) runs every build under Docker, the strict case for a non-root container's capabilities. It moves the VIP on a veth pair inside a network namespace of its own, so the runner's network is not touched, against a throwaway etcd with TLS and client certificates. Every build must pass all of these before anything is pushed:

- the version vip-manager reports matches `APP_VERSION`;
- the banner names startechnica, `STARTECHNICA_DEBUG` works, and nothing in the image still refers to the Bitnami layout;
- as uid 1001, with a client key owned by `root:root` with mode `0440`, vip-manager adds the VIP when the leader key names this node, a gratuitous ARP for it is seen on the interface, and the VIP is removed when the key moves to another node;
- as uid 1001, a key with mode `0400` owned by root cannot be read, and vip-manager exits;
- without `NET_ADMIN`, or under `no-new-privileges`, the container exits at startup and says why;
- with no configuration at all, vip-manager names the missing setting, not a missing config file;
- a mounted config file is read, and `VIP_INTERVAL` wins over its `interval`;
- started as root, vip-manager stays root, reads a client key with mode `0400` owned by root, and moves the VIP.

## Maintenance

### Adding or refreshing a version branch

1. Copy an existing branch to `<major>/debian-13/`.
2. In its Dockerfile, change the version in the tarball name and URL, in the license file name, in `APP_VERSION` and in the `org.opencontainers.image.version` label. Reset `IMAGE_REVISION` to `0`.
3. Replace the checksum file with the tarball's line from upstream's `checksums.txt`:

   ```bash
   v=5.0.0
   gh release download "v$v" -R cybertec-postgresql/vip-manager -p checksums.txt -O - \
     | grep " vip-manager_${v}_Linux_x86_64.tar.gz\$" \
     > "5/debian-13/prebuildfs/opt/startechnica/checksums/vip-manager_${v}_Linux_x86_64.tar.gz.sha256"
   ```

4. Update the branch table above.

### Refreshing the shared library

[`rebrand-shared-lib.sh`](rebrand-shared-lib.sh) copies the mirrors' shared library and apt helpers into every branch's `prebuildfs/`, rebranded the same way each time. Run it after the mirrors' library changes, review the diff, and raise `IMAGE_REVISION` in each branch whose files changed.

## License

The build files in this directory are Copyright Startechnica, under the Apache License, Version 2.0; see [LICENSE.md](../../LICENSE.md). The shared library and apt helpers under `prebuildfs/`, and `entrypoint.sh`, are derived from [bitnami/containers](https://github.com/bitnami/containers): Copyright Broadcom, Inc., under the same license, and modified by Startechnica, as each file's header says.

vip-manager is Copyright (c) 2017 Cybertec PostgreSQL International GmbH, under the BSD 2-Clause License. The image ships that license at `/opt/startechnica/vip-manager/licenses/vip-manager-<version>.txt`. The image also contains other third-party software, under its own licenses.
