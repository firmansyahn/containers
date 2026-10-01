# The Containers Library

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
- **A revision tag is pushed once.** Each image is labelled
  `io.github.firmansyahn.containers.build-files` with a hash of its build
  files, and [`ci-published.sh`](.github/scripts/ci-published.sh) checks the
  tag before every push: already published from the same files, nothing is
  built or pushed; from other files, the run fails until `IMAGE_REVISION` is
  raised. A digest therefore stays valid as long as its revision tag exists,
  and production can pin it.
- Each workflow runs only for changes under its own `containers/<app>/`, its
  own workflow file, `ci-published.sh` and, for a mirror, `build.yml`.

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
- on `main`, skips every branch whose revision tag is already published, so the
  moving tags only move when a new revision is pushed. The hash leaves out
  `docker-compose.yml`, which is not part of the image;
- otherwise builds amd64 first, runs `ci-smoke.sh` against it, and only then
  builds both arches and pushes all of the branch's tags. Pull requests build
  and smoke-test every branch, published or not;
- after publishing, deletes the untagged manifests that no tag reaches any more.
  A published image keeps its revision tag, so this only removes what is left
  untagged some other way, such as the images re-pushes orphaned before
  revision tags were pushed only once. Deleting needs the `GHCR_TOKEN`
  repository secret, a classic token with `write:packages` and
  `delete:packages`, because `GITHUB_TOKEN` cannot delete versions of a
  user-owned package; without it, the prune is skipped.

`workflow_dispatch` takes an optional single branch to build. Rebuilding a
published revision, for example to pick up a new `minideb`, means raising
`IMAGE_REVISION` in its Dockerfile.

Images pushed before the build-files label existed carry none. They count as
published, and are not compared, until their branch moves to a new revision.

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

A derived image has its own workflow instead of `build.yml`, because it is
built and tested differently:

- **One tag per build, `<upstream tag>-r<revision>`, and nothing else.** No
  moving tags, and nothing is ever pruned. The app's README keeps a table of
  what each revision holds.
- **The build that was tested is the build that is pushed**, as a file handed
  from one job to the next. The job that builds it holds no write token and no
  secret, so it can run code that is not ours, such as a plugin's test suite.
  The job that pushes runs nothing from the image and uses the workflow's own
  token.
- **One architecture per test job.** What is pushed is the very image the
  tests ran in, so a second architecture is a second build-and-test job, not a
  second platform on one build.

## License

Copyright © 2026 Firmansyah Nainggolan

Licensed under the Apache License, Version 2.0 (the "License"); see
[LICENSE.md](LICENSE.md). You may not use the files in this repository except
in compliance with the License. You may obtain a copy of the License at
<http://www.apache.org/licenses/LICENSE-2.0>.

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

A mirror's build files, and the parts of its README taken from upstream, are
Bitnami's: Copyright Broadcom, Inc., under the same license, as their file
headers say. The images themselves contain third-party software under its own
licenses.
