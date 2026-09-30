# keycloak

Mirror of the Bitnami Keycloak container build. Built and pushed by
[`.github/workflows/keycloak.yml`](../../.github/workflows/keycloak.yml), which
calls the shared [`build.yml`](../../.github/workflows/build.yml), to
`ghcr.io/firmansyahn/containers/keycloak`:

| branch | upstream commit | published tags |
| ------ | --------------- | -------------- |
| 26 | [b0d8c5e](https://github.com/bitnami/containers/tree/b0d8c5e131de56611a01342058814ed838984a80/bitnami/keycloak/26) (2026-09-29, still on `main`) | `26.7.4-debian-12-r1`, `26.7.4`, `26`, `latest` |
| 26.6 | [602de88](https://github.com/bitnami/containers/tree/602de887cbfcfcf18d5b5c11f9ac92107bb5b2a5/bitnami/keycloak/26) (2026-07-06, last 26.6 release) | `26.6.4-debian-12-r3`, `26.6.4`, `26.6` |
| 26.6.1 | [c35c493](https://github.com/bitnami/containers/tree/c35c493ebfbf4ec9b84189c226aa88bde38e2d84/bitnami/keycloak/26) (2026-04-29) | `26.6.1-debian-12-r1`, `26.6.1` |

Upstream keeps a single `26` directory and rolls it forward in place, so the
26.6 builds are the same directory taken from older commits and stored here
under `26.6` and `26.6.1`. That makes directory names an unreliable ordering,
which is why the workflow picks the `:latest` branch by comparing `APP_VERSION`
rather than directory name.

26.6.1-r1 is the build behind the `keycloak:26.6.1` image still in production —
the one that survived only in a few nodes' CRI-O caches. It is now reproducible
from source, and pinned in its own `26.6.1` branch so it stays buildable after
`26.6` moved on to 26.6.4.

26.6.4 is the last 26.6 patch that exists as a release: Bitnami moved to 26.7.0
three days later. Keycloak's repo does carry `26.6.5` and `26.6.6` tags, but
neither was ever published — no GitHub release, no distribution on Maven
Central, no `quay.io/keycloak/keycloak` image, no Bitnami tarball — so there is
nothing to build them from.

Images are multi-arch (`linux/amd64`, `linux/arm64`) and identical in layout to
the Bitnami originals — same `/opt/bitnami` tree, same bundled JRE, same
entrypoint, same uid 1001 — so they drop into the Bitnami Helm charts by
overriding `image.registry` and `image.repository` only.

## Smoke test

[`ci-smoke.sh`](ci-smoke.sh) stands up a throwaway PostgreSQL on its own docker
network, aliased `postgresql`, then starts the amd64 build against it, waits for
the `Keycloak <version> ... started in` log line, and asserts that version
matches `APP_VERSION` in the Dockerfile.

The database is not optional. `KEYCLOAK_DATABASE_HOST` defaults to `postgresql`
and the entrypoint blocks on `wait-for-port` until it answers, then exits — so
the test also covers the real schema migration, not just process startup.
