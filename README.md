# containers

Container images built in this repo and published to
`ghcr.io/firmansyahn/containers/<app>`.

GHCR shows this README under every package, so it holds only what applies to
all of them. What an image is, which versions it has and how it is tested are
in that app's own README, which its package description links to.

| app | kind |
| --- | ---- |
| [redis](containers/redis/README.md) | mirror |
| [keycloak](containers/keycloak/README.md) | mirror |
| [netbox](containers/netbox/README.md) | derived |

- A **[mirror](#mirrors)** rebuilds an upstream image that is no longer
  published, from upstream's own build files copied into this repo.
- A **[derived](#derived-images)** image is an upstream image, named by digest,
  plus a layer of our own.

## Layout

```
containers/<app>/README.md         # what the image is, its versions, its tests
containers/<app>/description.txt   # GHCR package-page description
containers/<app>/ci-smoke.sh       # test run against every build
containers/<app>/<branch>/         # build context (a mirror's is <branch>/<os flavour>/)
.github/workflows/<app>.yml        # path filters, then the build
```

`description.txt` is the only per-package text GHCR will show: the README it
renders underneath is always this root one, for every package, because
`org.opencontainers.image.source` takes a repo URL and not a subdirectory. So
each file spends part of its 512-character budget linking to that app's own
README. A multi-arch image carries it as an index **annotation** as well as a
label, because GHCR reads the description of a multi-arch image from the index
and ignores the per-architecture labels.

## What every image goes through

- Pull requests build and test, and push nothing. A push to `main` publishes.
- Every build passes the app's `ci-smoke.sh` before anything is pushed.
- Each workflow runs only for changes under its own `containers/<app>/`, its
  own workflow file and, for a mirror, `build.yml`. A change to `build.yml`
  therefore rebuilds and republishes every mirror.

## Mirrors

The mirrors here all come from the Bitnami free catalog, withdrawn in
2025-2026: `public.ecr.aws/bitnami/*` was deleted outright,
`docker.io/bitnami/*` keeps only `latest`-style development tags,
`bitnamilegacy/*` is frozen at the August 2025 cutoff, and `bitnamisecure/*`
needs a paid subscription. They are multi-arch for `linux/amd64` and
`linux/arm64`, and keep upstream's layout, so they drop into upstream's charts
by changing the image registry and repository only.

Nothing about a mirror is configured in the workflow. Each one has a thin caller
workflow that owns the path filters and hands over to the shared
[`build.yml`](.github/workflows/build.yml), which:

- discovers every `containers/<app>/*/debian-12` directory at run time, so a new
  branch builds with no workflow edit;
- reads `APP_VERSION` and `IMAGE_REVISION` out of each Dockerfile, so tags can
  never drift from the tarball the build actually pulls;
- tags `<version>-debian-12-r<revision>`, `<version>` and `<branch>` (the last
  two are one tag when a branch is named after its exact version), plus
  `latest` for the branch with the **highest `APP_VERSION`**, not the highest
  directory name: upstream may keep its newest release in a directory named
  for the major version and older ones in directories named for a minor;
- builds amd64 first, runs `ci-smoke.sh` against it, and only then builds both
  arches and pushes;
- after publishing, deletes the untagged manifests that no tag reaches any more
  — every re-push of a moving tag like `latest` orphans the old image. This
  needs the `GHCR_TOKEN` secret and is skipped without it; see
  [GHCR notes](#ghcr-notes).

`workflow_dispatch` takes an optional single branch to build.

### Adding or refreshing a version branch

Upstream keeps build files only for the *current* branch — when a new one is
promoted, the old directory is stripped down to a README. Older versions survive
in git history:

```bash
git clone --filter=blob:none --sparse https://github.com/bitnami/containers /tmp/bitnami
cd /tmp/bitnami && git sparse-checkout set bitnami/<app>
git log --oneline -- bitnami/<app>/<branch>/debian-12/Dockerfile   # newest one still has content
git checkout <commit> -- bitnami/<app>/<branch>
cp -a bitnami/<app>/<branch> ~/containers/containers/<app>/
```

Refreshing a branch is the same copy over the existing directory; the tags
follow the Dockerfile. The app's README records which upstream commit each
branch came from.

The Dockerfiles do not compile anything. They unpack prebuilt tarballs from
`https://downloads.bitnami.com/files/stacksmith/` and verify them against the
sha256 files in `prebuildfs/opt/bitnami/checksums/`. That host still serves old
versions even though the matching image tags are gone — it and
`docker.io/bitnami/minideb:bookworm` are the only external dependencies of a
mirror, so check both before assuming an old version can still be rebuilt.

## Derived images

A derived image has its own workflow instead of `build.yml`, because production
pins it by digest:

- **One tag per build, `<upstream tag>-r<revision>`, never pushed twice and
  never pruned.** `build.yml` pushes moving tags again and then deletes the
  manifests that orphans — which, for an image pinned by digest, deletes the
  one in use. The app's README keeps a table of what each revision holds.
- **The build that was tested is the build that is pushed**, as a file handed
  from one job to the next. The job that builds it holds no write token and no
  secret, so it can run code that is not ours, such as a plugin's test suite.
  The job that pushes runs nothing from the image and uses the workflow's own
  token, not `GHCR_TOKEN`.
- **One architecture per test job.** What is pushed is the very image the
  tests ran in, so a second architecture is a second build-and-test job, not a
  second platform on one build.

## GHCR notes

Two things that are settings, not code, and cost an afternoon each if unknown:

- **Packages are private by default, even under a public repo**, and no API
  changes it — it is the Danger Zone on the package settings page in the web UI.
  A new package has to be made public by hand after its first push.
- **`GITHUB_TOKEN` cannot push to a package that was not created by Actions.**
  The first packages here were pushed by hand, so every push failed with
  `denied: permission_denied: write_package` until this repo was given Write
  under each package's **Manage Actions access** setting. There is no API for
  that — not REST, not GraphQL, and the `org.opencontainers.image.source` label
  does not do it retroactively — so it is a click on each package's settings
  page, once. A package that Actions created has that access already.

  Pushing works with plain `GITHUB_TOKEN` now that the access is granted.
  Pruning does not: **`GITHUB_TOKEN` cannot delete versions of a user-owned
  package**, only an org-owned one. That is what the `GHCR_TOKEN` secret is
  for. When it is set, `build.yml` uses it for both the push login and the
  prune job; when it is absent, pushes fall back to `GITHUB_TOKEN` and prune is
  skipped with a notice. Derived images never use it.

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
