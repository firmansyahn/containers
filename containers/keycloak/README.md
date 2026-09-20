# keycloak

Mirror of the Bitnami Keycloak container build. Built and pushed by
[`.github/workflows/keycloak.yml`](../../.github/workflows/keycloak.yml), which
calls the shared [`build.yml`](../../.github/workflows/build.yml), to
`ghcr.io/firmansyahn/containers/keycloak`:

| branch | upstream commit | published tags |
| ------ | --------------- | -------------- |
| 26 | [c62f41a](https://github.com/bitnami/containers/tree/c62f41af66f777c7d6bfe232bff806a41f330791/bitnami/keycloak/26) (2026-09-19, still on `main`) | `26.7.4-debian-12-r0`, `26.7.4`, `26`, `latest` |
| 26.6 | [c35c493](https://github.com/bitnami/containers/tree/c35c493ebfbf4ec9b84189c226aa88bde38e2d84/bitnami/keycloak/26) (2026-04-29) | `26.6.1-debian-12-r1`, `26.6.1`, `26.6` |

Upstream keeps a single `26` directory and rolls it forward in place, so the
pinned 26.6.1 build is the same directory taken from an older commit and stored
here under `26.6`. That makes directory names an unreliable ordering, which is
why the workflow picks the `:latest` branch by comparing `APP_VERSION` rather
than directory name.

26.6.1-r1 is the build behind the `keycloak:26.6.1` image that pegasus runs — the
one that survived only in three nodes' CRI-O caches. It is now reproducible from
source.

Images are multi-arch (`linux/amd64`, `linux/arm64`) and identical in layout to
the Bitnami originals — same `/opt/bitnami` tree, same bundled JRE, same
entrypoint, same uid 1001 — so they drop into the Bitnami Helm charts by
overriding `image.registry` and `image.repository` only.

## Smoke test

[`ci-smoke.sh`](ci-smoke.sh) runs the amd64 build with **no database
configured**: `KC_DB` ends up empty, the entrypoint runs `kc.sh start-dev`, and
Keycloak falls back to its embedded dev-file store. The test waits for the
`Keycloak <version> ... started in` log line and asserts that version matches
`APP_VERSION` in the Dockerfile.

That exercises the bundled JRE, the Quarkus augmentation and the Bitnami
entrypoint end to end, but it is *not* a production configuration check — a real
deployment still needs PostgreSQL and the chart's own settings.
