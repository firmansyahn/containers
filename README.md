# containers

Self-built mirrors of container images that upstream stopped publishing, chiefly
the Bitnami free catalog withdrawn in 2025-2026.

Images are published to `ghcr.io/firmansyahn/containers/<app>`.

| app | source | tags |
| --- | ------ | ---- |
| [redis](containers/redis) | [bitnami/containers](https://github.com/bitnami/containers/tree/main/bitnami/redis) | `8.10.2-debian-12-r0`, `8.10.2`, `8.10`, `latest` |
| keycloak | — | placeholder |

Layout mirrors upstream: `containers/<app>/<version branch>/<os flavour>/`, so a
build context can be copied in or refreshed without rewriting anything. Each app
has its own workflow under [`.github/workflows/`](.github/workflows) that builds
every version branch present for `linux/amd64` and `linux/arm64`, smoke-tests the
amd64 image, and pushes to GHCR.

See each app's README for provenance and for how to pull an older version branch
out of upstream git history.
