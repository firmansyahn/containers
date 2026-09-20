# redis

Mirror of the Bitnami Redis container build. Built and pushed by
[`.github/workflows/redis.yml`](../../.github/workflows/redis.yml), which calls
the shared [`build.yml`](../../.github/workflows/build.yml), to
`ghcr.io/firmansyahn/containers/redis`:

| branch | upstream commit | published tags |
| ------ | --------------- | -------------- |
| 8.10 | [c62f41a](https://github.com/bitnami/containers/tree/c62f41af66f777c7d6bfe232bff806a41f330791/bitnami/redis/8.10) (2026-09-19, still on `main`) | `8.10.2-debian-12-r0`, `8.10.2`, `8.10`, `latest` |
| 8.6 | [833b33f](https://github.com/bitnami/containers/tree/833b33f51295ac207ccb8427f60cfd212c0a5c11/bitnami/redis/8.6) (2026-05-23, last commit before removal) | `8.6.3-debian-12-r3`, `8.6.3`, `8.6` |
| 8.2 | [e2bbf69](https://github.com/bitnami/containers/tree/e2bbf691c5625f086e44d3702e95ce1fb9d7d484/bitnami/redis/8.2) (2025-11-02, last commit before removal) | `8.2.3-debian-12-r0`, `8.2.3`, `8.2` |

8.6 and 8.2 are the branches pegasus actually runs. Upstream had already stripped
both directories, so they were recovered from git history — see the root
[README](../../README.md#adding-or-refreshing-a-version-branch).

The `8.6.2` tag rescued from the CRI-O caches has **no build context**: upstream
only ever keeps the newest patch of a branch, and 8.6.3 replaced it before the
directory was deleted. That tag stays in GHCR as the only copy in existence.

Images are multi-arch (`linux/amd64`, `linux/arm64`) and identical in layout to
the Bitnami originals — same `/opt/bitnami` tree, same entrypoint, same uid 1001
— so they drop into the Bitnami Helm charts by overriding `image.registry` and
`image.repository` only.

## Smoke test

[`ci-smoke.sh`](ci-smoke.sh) starts the amd64 build with `ALLOW_EMPTY_PASSWORD`,
waits for `redis-cli ping` to answer `PONG`, and asserts the server's reported
`redis_version` matches `APP_VERSION` in the Dockerfile. Every build must pass it
before anything is pushed.
