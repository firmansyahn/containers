# netbox

NetBox with plugins baked in. Built and pushed by
[`.github/workflows/netbox.yml`](../../.github/workflows/netbox.yml) to
`ghcr.io/firmansyahn/containers/netbox`.

Unlike everything else in this repo it is **derived, not mirrored**: the
[netbox-docker](https://github.com/netbox-community/netbox-docker) image, named
by digest, plus one layer that installs the packages pinned in
[`4.7/plugin_requirements.txt`](4.7/plugin_requirements.txt) and collects their
static files. A chart can turn a plugin on but cannot install one, and
installing at pod start would make every start depend on PyPI — so the packages
have to be in the image.

**No plugin is on as shipped.** The image behaves exactly like its base until
the deployment lists a plugin in `PLUGINS`. Moving to this image and turning a
plugin on are two separate changes.

## Tags

`<netbox-docker tag>-r<revision>`, for example `v4.7.1-5.1.1-r0`. The revision
is `IMAGE_REVISION` in the Dockerfile: it goes up by one whenever anything in
the version directory changes on the same base, and a new base starts again at
`r0`. The [revision table](../../README.md#netbox-revisions) in the root README
says what each one holds.

- **A published tag is never pushed again, and nothing is pruned.** Production
  pins the image by digest. A rebuild under the same tag would leave that
  digest with no tag pointing at it, and the prune job the mirrors use deletes
  exactly that. So when the tag already exists the workflow compares a hash of
  the build files with the published image's label: the same, and it ends green
  without pushing; different, and it fails and says the revision was not
  raised. That check also runs on pull requests.
- **There are no moving tags**: no `latest`, no `4.7`.
- **`linux/amd64` only.** What is pushed is the very image the tests ran in,
  and one runner tests one architecture. A second architecture is a second
  build-and-test job and an index, not a second platform on one build.

## What is in an image

The tag names a revision, not a plugin list, so the image says it itself:

```bash
# from outside
docker buildx imagetools inspect ghcr.io/firmansyahn/containers/netbox:v4.7.1-5.1.1-r0 \
  --format '{{json .Image.Config.Labels}}'

# from inside a pod
cat /opt/netbox/plugin_requirements.txt
```

| label | holds |
| ----- | ----- |
| `io.github.firmansyahn.containers.packages` | every `name==version` the image adds |
| `io.github.firmansyahn.containers.build-files` | sha256 over the build context, what "the same image" means above |
| `org.opencontainers.image.version` | the tag |
| `org.opencontainers.image.base.name`, `.base.digest` | the netbox-docker image it was built on |
| `org.opencontainers.image.source`, `.revision` | this repo, and the commit it was built from |

## Changing it

One version directory at a time. Everything below is one commit.

**Add a plugin, or move one to another version**

1. Edit [`4.7/plugin_requirements.txt`](4.7/plugin_requirements.txt): exact
   version, and the sha256 of its **wheel** from
   `https://pypi.org/pypi/<name>/<version>/json`. A dependency the base image
   lacks gets a line of its own; the build fails on one that is missing.
2. Raise `IMAGE_REVISION` in the [Dockerfile](4.7/Dockerfile).
3. In [`ci-plugin-tests.sh`](ci-plugin-tests.sh), give the package a line in
   `SUITES` (version, and the commit of that release in the plugin's repo) or
   in `NO_SUITE` (why not). The script refuses a package that is in neither.
4. If the plugin ships static files, add it to the `PLUGINS` line the
   Dockerfile writes for `collectstatic`. The smoke test fails until it is.
5. Add a row to the [revision table](../../README.md#netbox-revisions).

**Move to a new NetBox**

1. Check that every plugin has a release that supports it. None of the three
   sets a `max_version`, so NetBox will not refuse one for you.
2. Put the new netbox-docker tag **and its index digest** in `FROM` and set
   `IMAGE_REVISION` back to `0`. A new minor version also renames the
   directory and updates `CONTEXT` in the workflow; a patch release stays in
   its directory (4.7.2 replaced 4.7.1 in `4.7`). Go through the list above
   for whatever plugin versions change, and add a row to the revision table
   either way.

The tag built before stays on GHCR, as every tag does, but the directory now
builds the new one only. Its build files are in git history.

## What CI does

Two jobs, because the plugins' test suites are other people's code.

**`build`** can read this repo and nothing else: no write token, no secret, no
registry login. It builds the image once and runs everything against it.

- [`ci-smoke.sh`](ci-smoke.sh) compares the image with its base. No database:
  - the base image's packages are all still at their versions, and the added
    ones are exactly the requirements file's;
  - NetBox's release file still reads the base tag's version;
  - `/etc/netbox/config` is the base image's, file for file. netbox-docker
    reads every file there and the last one wins, so a `PLUGINS` line left by
    the build would override the chart and turn plugins on in every pod;
  - with that configuration NetBox loads no plugin; each installed plugin's
    `min_version`/`max_version` admits this NetBox (NetBox itself only warns
    and starts without the plugin); and all of them load together;
  - every file a plugin ships under `static/` is in `/opt/netbox/netbox/static`;
  - the labels say what the build files say.
- [`ci-plugin-tests.sh`](ci-plugin-tests.sh) runs `netbox-routing`'s and
  `netbox-security`'s own suites in the image, against PostgreSQL 18 and Redis
  on a network with no way out. Upstream runs them on NetBox `main` only.
  - The `tests` directory comes from the plugin's repo at the commit of the
    pinned release and is copied in beside the *installed* package, after every
    installed `.py` file has been compared with that commit.
  - One plugin on at a time, one test at a time, with
    [`testing_configuration.py`](testing_configuration.py) mounted for the run.
  - Query counts are recorded, not compared: the baselines are for NetBox
    `main`. The ones that differ are printed.
  - A test that cannot pass here for a reason that is not the plugin's is
    skipped **by name, with the reason, in `SKIPS`**. A skip that matches no
    test fails the run.
  - The job summary ends with the tests run, each skipped test and the counts
    that differ. `netbox-topology-views` has no tests at all; CI proves only
    that it installs, loads and has its static files.

**`push`** runs on `main` only. It checks out one script, builds nothing and
runs nothing from a plugin: it loads the image `build` saved, checks its ID and
labels, pushes it with the workflow's own token, and reads it back. `GHCR_TOKEN`,
which can delete packages, is not used.

A pull request builds and tests, and pushes nothing.

## After the first push

GHCR creates the package **private**, and no API changes that (see the
[GHCR notes](../../README.md#ghcr-notes)). A cluster with no pull secret gets
`ImagePullBackOff`. Make it public on the package's settings page; the `push`
job warns on every run until a pull without a credential works.

## Who decides what runs

Whoever can push to `main` here decides what code runs inside NetBox, next to
its database and its SSO secrets. The image rests on this account's two-factor
login and on who may push.
