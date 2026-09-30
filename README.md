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
| [keycloak](containers/keycloak) | 26 (26.7.4), 26.6 (26.6.4), 26.6.1 | [bitnami/containers](https://github.com/bitnami/containers/tree/main/bitnami/keycloak) |

## Layout

```
containers/<app>/ci-smoke.sh              # per-app test, run against every build
containers/<app>/description.txt          # GHCR package-page description
containers/<app>/<branch>/<os flavour>/   # build context, copied from upstream
```

`description.txt` is the only per-package text GHCR will show: the README it
renders underneath is always this root one, for every package, because
`org.opencontainers.image.source` takes a repo URL and not a subdirectory. So
each file spends part of its 512-character budget linking to that app's own
README. It is written as an index **annotation** rather than only a label —
GHCR reads the description of a multi-arch image from the index, and ignores
the per-architecture labels.

Nothing about an app is configured in the workflow. Each app has a thin caller
workflow (`.github/workflows/<app>.yml`) that owns the path filters and hands
over to the shared [`build.yml`](.github/workflows/build.yml), which:

- discovers every `containers/<app>/*/debian-12` directory at run time, so a new
  branch builds with no workflow edit;
- reads `APP_VERSION` and `IMAGE_REVISION` out of each Dockerfile, so tags can
  never drift from the tarball the build actually pulls;
- tags `<version>-debian-12-r<revision>`, `<version>` and `<branch>` (the last
  two are one tag when a branch is named after its exact version), plus
  `latest` for the branch with the **highest `APP_VERSION`** (not the highest
  directory name — keycloak keeps 26.7.4 in a directory called `26` and older
  builds in `26.6` and `26.6.1`);
- builds amd64 first, runs `containers/<app>/ci-smoke.sh` against it, and only
  then builds both arches and pushes;
- after publishing, deletes the untagged manifests that no tag reaches any more
  — every re-push of a moving tag like `latest` orphans the old image. This
  needs the `GHCR_TOKEN` secret and is skipped without it; see
  [GHCR notes](#ghcr-notes).

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
  These packages were first pushed by hand, so every push failed with
  `denied: permission_denied: write_package` until this repo was given Write
  under each package's **Manage Actions access** setting. There is no API for
  that — not REST, not GraphQL, and the `org.opencontainers.image.source` label
  does not do it retroactively — so it is a click on each package's settings
  page, once.

  Pushing works with plain `GITHUB_TOKEN` now that the access is granted.
  Pruning does not: **`GITHUB_TOKEN` cannot delete versions of a user-owned
  package**, only an org-owned one. That is what the `GHCR_TOKEN` secret is
  for. When it is set, both the push login and the prune job use it; when it
  is absent, pushes fall back to `GITHUB_TOKEN` and prune is skipped with a
  notice.

### `GHCR_TOKEN`

A **classic** personal access token. GitHub Packages does not accept
fine-grained tokens, and classic tokens are the ones that offer
**No expiration**. It needs exactly two scopes:

| scope | used for |
| ----- | -------- |
| `write:packages` (includes `read:packages`) | pushing, and reading tags and package versions for prune |
| `delete:packages` | prune's version deletes |

Do not add `repo`: container packages have their own permissions, so nothing
here needs it. The token page ticks `repo` automatically as soon as
`write:packages` is ticked, so create the token from this link instead, which
pre-selects just the two scopes:

<https://github.com/settings/tokens/new?scopes=write:packages,delete:packages&description=containers%20GHCR_TOKEN>

Store it as a repository secret. `gh` prompts for the value, so it stays out
of shell history:

```bash
gh secret set GHCR_TOKEN -R firmansyahn/containers
```

A classic token covers every package on the account, not just this repo's,
and anyone who can edit workflows on `main` can use it. Fork pull requests
never receive secrets. Revoke it at <https://github.com/settings/tokens> if it
is ever in doubt.
