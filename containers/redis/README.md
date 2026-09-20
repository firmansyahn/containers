# redis

Mirror of the Bitnami Redis container build, kept because Bitnami withdrew its
free catalog: `public.ecr.aws/bitnami/*` was deleted outright, `docker.io/bitnami/*`
keeps only `latest`-style development tags, `bitnamilegacy/*` is frozen at the
August 2025 cutoff, and `bitnamisecure/*` needs a paid subscription.

Built and pushed by [`.github/workflows/redis.yml`](../../.github/workflows/redis.yml)
to:

```
ghcr.io/firmansyahn/containers/redis:<version>-debian-12-r<revision>
ghcr.io/firmansyahn/containers/redis:<version>
ghcr.io/firmansyahn/containers/redis:<branch>        # e.g. 8.10
ghcr.io/firmansyahn/containers/redis:latest          # highest branch in this repo
```

Images are multi-arch (`linux/amd64`, `linux/arm64`) and identical in layout to
the Bitnami originals — same `/opt/bitnami` tree, same entrypoint, same uid 1001
— so they drop into the Bitnami Helm charts by overriding `image.registry` and
`image.repository` only.

## Provenance

| branch | source |
| ------ | ------ |
| 8.10   | [bitnami/containers@c62f41a](https://github.com/bitnami/containers/tree/c62f41af66f777c7d6bfe232bff806a41f330791/bitnami/redis/8.10) (redis 8.10.2, 2026-09-19) |

The Dockerfile does not compile Redis. It unpacks a prebuilt tarball from
`https://downloads.bitnami.com/files/stacksmith/` and verifies it against the
sha256 in `prebuildfs/opt/bitnami/checksums/`. That download host still serves
old versions even though the image tags are gone — it is the single external
dependency this mirror rests on, along with `docker.io/bitnami/minideb:bookworm`
as the base image.

## Adding another version branch

Upstream keeps build files only for the *current* branch; when a new one is
promoted the old directory is stripped to a README. Older versions survive in
git history:

```bash
git clone --filter=blob:none --sparse https://github.com/bitnami/containers /tmp/bitnami
cd /tmp/bitnami && git sparse-checkout set bitnami/redis
git log --oneline -- bitnami/redis/8.6/debian-12/Dockerfile   # last release commit
git checkout 833b33f -- bitnami/redis/8.6                      # 8.6.3-debian-12-r3
cp -a bitnami/redis/8.6 "$OLDPWD/containers/redis/"
```

Known-good commits: `833b33f` = 8.6.3-debian-12-r3, `e2bbf69` = 8.2.3-debian-12-r0.

The workflow discovers `containers/redis/*/debian-12` at run time, so a new
directory builds with no workflow edit. `:latest` follows the highest branch
present, so adding an *older* branch never moves it.

## Updating a branch in place

Copy the newer `Dockerfile`, `prebuildfs/` and `rootfs/` over the existing
directory. The workflow reads `APP_VERSION` and `IMAGE_REVISION` out of the
Dockerfile, so the published tags follow automatically.

## First push

GHCR packages are **private by default, even under a public repo**, and there is
no API to change that — it is the Danger Zone on the package settings page in the
web UI. After the first successful run, flip
`ghcr.io/firmansyahn/containers/redis` to public there, or every consumer needs a
pull secret.
