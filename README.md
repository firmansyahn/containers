# containers

Self-built mirrors of container images that upstream stopped publishing, chiefly
the Bitnami free catalog withdrawn in 2025-2026: `public.ecr.aws/bitnami/*` was
deleted outright, `docker.io/bitnami/*` keeps only `latest`-style development
tags, `bitnamilegacy/*` is frozen at the August 2025 cutoff, and
`bitnamisecure/*` needs a paid subscription.

Images are published to `ghcr.io/firmansyahn/containers/<app>`, multi-arch for
`linux/amd64` and `linux/arm64`.

| app | branches | source |
| --- | -------- | ------ |
| [redis](containers/redis) | 8.10, 8.6, 8.2 | [bitnami/containers](https://github.com/bitnami/containers/tree/main/bitnami/redis) |
| [keycloak](containers/keycloak) | 26 (26.7.4), 26.6 (26.6.1) | [bitnami/containers](https://github.com/bitnami/containers/tree/main/bitnami/keycloak) |

## Layout

```
containers/<app>/ci-smoke.sh              # per-app test, run against every build
containers/<app>/<branch>/<os flavour>/   # build context, copied from upstream
```

Nothing about an app is configured in the workflow. Each app has a thin caller
workflow (`.github/workflows/<app>.yml`) that owns the path filters and hands
over to the shared [`build.yml`](.github/workflows/build.yml), which:

- discovers every `containers/<app>/*/debian-12` directory at run time, so a new
  branch builds with no workflow edit;
- reads `APP_VERSION` and `IMAGE_REVISION` out of each Dockerfile, so tags can
  never drift from the tarball the build actually pulls;
- tags `<version>-debian-12-r<revision>`, `<version>` and `<branch>`, plus
  `latest` for the branch with the **highest `APP_VERSION`** (not the highest
  directory name — keycloak keeps 26.7.4 in a directory called `26` and an older
  pinned build in `26.6`);
- builds amd64 first, runs `containers/<app>/ci-smoke.sh` against it, and only
  then builds both arches and pushes.

Pull requests build and smoke-test without pushing; pushes to `main` publish.
`workflow_dispatch` takes an optional single branch to build.

## Adding or refreshing a version branch

Upstream keeps build files only for the *current* branch — when a new one is
promoted, the old directory is stripped down to a README. Older versions survive
in git history:

```bash
git clone --filter=blob:none --sparse https://github.com/bitnami/containers /tmp/bitnami
cd /tmp/bitnami && git sparse-checkout set bitnami/redis
git log --oneline -- bitnami/redis/8.6/debian-12/Dockerfile   # newest one still has content
git checkout 833b33f -- bitnami/redis/8.6
cp -a bitnami/redis/8.6 ~/containers/containers/redis/
```

Refreshing a branch is the same copy over the existing directory; the tags
follow the Dockerfile.

The Dockerfiles do not compile anything. They unpack prebuilt tarballs from
`https://downloads.bitnami.com/files/stacksmith/` and verify them against the
sha256 files in `prebuildfs/opt/bitnami/checksums/`. That host still serves old
versions even though the matching image tags are gone — it and
`docker.io/bitnami/minideb:bookworm` are the only external dependencies here, so
check both before assuming an old version can still be rebuilt.

## GHCR notes

Two things that are settings, not code, and cost an afternoon each if unknown:

- **Packages are private by default, even under a public repo**, and no API
  changes it — it is the Danger Zone on the package settings page in the web UI.
- **`GITHUB_TOKEN` cannot push to a package that was not created by Actions.**
  These packages were first pushed by hand, so buildx fails with
  `denied: permission_denied: write_package`. The workflow authenticates with a
  `GHCR_TOKEN` secret (a classic PAT with `write:packages`) and falls back to
  `GITHUB_TOKEN` when that secret is absent — so linking a package to this repo
  under its Actions access settings lets the secret be deleted with no workflow
  change.
