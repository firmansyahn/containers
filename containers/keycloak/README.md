# Keycloak, rebuilt from Bitnami's build files

> Keycloak is a high performance Java-based identity and access management solution. It lets developers add an authentication layer to their applications with minimum effort.

[Overview of Keycloak](https://www.keycloak.org/)

Trademarks: Keycloak and Bitnami are trademarks of their respective owners. Both names are used here for reference only: this image is built in this repository, not by the Keycloak project or Bitnami, and neither of them sponsors, endorses or supports it.

## About this image

A rebuild of the Bitnami Keycloak container, from Bitnami's own build files, after Bitnami stopped publishing it (see the [root README](../../README.md#mirrors)). Built and pushed by [`.github/workflows/keycloak.yml`](../../.github/workflows/keycloak.yml), which calls the shared [`build.yml`](../../.github/workflows/build.yml), to `ghcr.io/firmansyahn/containers/keycloak`:

| branch | upstream commit | published tags |
| ------ | --------------- | -------------- |
| 26 | [b0d8c5e](https://github.com/bitnami/containers/tree/b0d8c5e131de56611a01342058814ed838984a80/bitnami/keycloak/26) (2026-09-29, still on `main`) | `26.7.4-debian-12-r1`, `26.7.4`, `26`, `latest` |
| 26.6 | [602de88](https://github.com/bitnami/containers/tree/602de887cbfcfcf18d5b5c11f9ac92107bb5b2a5/bitnami/keycloak/26) (2026-07-06, last 26.6 release) | `26.6.4-debian-12-r3`, `26.6.4`, `26.6` |
| 26.6.1 | [c35c493](https://github.com/bitnami/containers/tree/c35c493ebfbf4ec9b84189c226aa88bde38e2d84/bitnami/keycloak/26) (2026-04-29) | `26.6.1-debian-12-r1`, `26.6.1` |

Upstream keeps a single `26` directory and rolls it forward in place, so the 26.6 builds are the same directory taken from older commits and stored here under `26.6` and `26.6.1`. That makes directory names an unreliable ordering, which is why the workflow picks the `:latest` branch by comparing `APP_VERSION` rather than directory name.

26.6.1-r1 is the build behind the `keycloak:26.6.1` image still in production — the one that survived only in a few nodes' CRI-O caches. It is now reproducible from source, and pinned in its own `26.6.1` branch so it stays buildable after `26.6` moved on to 26.6.4.

26.6.4 is the last 26.6 patch that exists as a release: Bitnami moved to 26.7.0 three days later. Keycloak's repo does carry `26.6.5` and `26.6.6` tags, but neither was ever published — no GitHub release, no distribution on Maven Central, no `quay.io/keycloak/keycloak` image, no Bitnami tarball — so there is nothing to build them from.

Images are multi-arch (`linux/amd64`, `linux/arm64`) and identical in layout to the Bitnami originals: same `/opt/bitnami` tree, same bundled JRE, same entrypoint, same UID 1001. Everything below that Bitnami documented for its own image applies to this one.

## TL;DR

Keycloak needs a PostgreSQL database. The container looks for one at `postgresql:5432`, waits for it, and exits if none answers:

```console
docker network create keycloak
docker run -d --name postgresql --network keycloak \
  -e POSTGRES_USER=bn_keycloak -e POSTGRES_PASSWORD=change-me -e POSTGRES_DB=bitnami_keycloak \
  postgres:16-alpine
docker run --name keycloak --network keycloak -p 8080:8080 \
  -e KC_DB_PASSWORD=change-me -e KC_BOOTSTRAP_ADMIN_PASSWORD=change-me \
  ghcr.io/firmansyahn/containers/keycloak:latest
```

## Using `docker-compose.yml`

Each branch keeps upstream's compose file, which starts Keycloak with its own PostgreSQL: [26](26/debian-12/docker-compose.yml), [26.6](26.6/debian-12/docker-compose.yml), [26.6.1](26.6.1/debian-12/docker-compose.yml). They still name `docker.io/bitnami/keycloak:26`, which Bitnami no longer publishes, so change the `keycloak` service's `image:` to `ghcr.io/firmansyahn/containers/keycloak:<branch>` first. The PostgreSQL image they name is Bitnami's own and is not rebuilt here.

The compose files are not tested here. Use them for development and testing only; for production, use the Helm chart below.

## How to deploy Keycloak in Kubernetes

The [Bitnami Keycloak chart](https://github.com/bitnami/charts/tree/main/bitnami/keycloak) runs this image unchanged. Point it here, and allow the substitution, which the chart otherwise refuses:

```yaml
global:
  security:
    allowInsecureImages: true
image:
  registry: ghcr.io
  repository: firmansyahn/containers/keycloak
  tag: "26"
```

The PostgreSQL subchart and the other images the chart can turn on still point at `docker.io/bitnami` and are not rebuilt here.

## Why use a non-root container?

Non-root container images add an extra layer of security and are generally recommended for production environments. However, because they run as a non-root user, privileged tasks are typically off-limits. Learn more about non-root containers [in Bitnami's docs](https://techdocs.broadcom.com/us/en/vmware-tanzu/application-catalog/tanzu-application-catalog/services/tac-doc/apps-tutorials-work-with-non-root-containers-index.html).

## Tags

Each branch is published as `<version>-debian-12-r<revision>`, `<version>` and `<branch>`, and the branch with the highest version also as `latest`; the table above lists them.

A `-r<revision>` tag is pushed once and never again, so its digest stays valid: **pin that tag, or its digest**. `<version>`, `<branch>` and `latest` move to the new image when a branch gets a new revision; the image they leave keeps its `-r<revision>` tag.

## Get this image

```console
docker pull ghcr.io/firmansyahn/containers/keycloak:latest
docker pull ghcr.io/firmansyahn/containers/keycloak:26.6.1
```

## Configuration

The following sections describe environment variables and related settings.

### Environment variables

The following tables list the main variables you can set.

#### Customizable environment variables

| Name                            | Description                                                                                        | Default Value                 |
|---------------------------------|----------------------------------------------------------------------------------------------------|-------------------------------|
| `KEYCLOAK_MOUNTED_CONF_DIR`     | Directory for including custom configuration files (that override the default generated ones)      | `${KEYCLOAK_VOLUME_DIR}/conf` |
| `KC_RUN_IN_CONTAINER`           | Keycloak kc.sh context                                                                             | `true`                        |
| `KEYCLOAK_PRODUCTION`           | Run in production mode.                                                                            | `false`                       |
| `KEYCLOAK_EXTRA_ARGS`           | Append extra arguments to Keycloak start command.                                                  | `nil`                         |
| `KEYCLOAK_EXTRA_ARGS_PREPENDED` | Prepend extra arguments to Keycloak start command.                                                 | `nil`                         |
| `KC_HTTP_MANAGEMENT_PORT`       | Management interface port.                                                                         | `9000`                        |
| `KEYCLOAK_ENABLE_HTTPS`         | Enable SSL certificates                                                                            | `false`                       |
| `KEYCLOAK_HTTPS_USE_PEM`        | Set to true to configure HTTPS using PEM certificates                                              | `false`                       |
| `KC_BOOTSTRAP_ADMIN_USERNAME`   | Bootstrap admin username                                                                           | `user`                        |
| `KC_BOOTSTRAP_ADMIN_PASSWORD`   | Bootstrap admin password                                                                           | `nil`                         |
| `KC_HTTP_PORT`                  | HTTP port                                                                                          | `8080`                        |
| `KC_HTTPS_PORT`                 | HTTPS port                                                                                         | `8443`                        |
| `KC_HTTP_RELATIVE_PATH`         | Set the path relative to "/" for serving resources.                                                | `/`                           |
| `KC_LOG_LEVEL`                  | Keycloak log level                                                                                 | `info`                        |
| `KC_LOG_CONSOLE_OUTPUT`         | Keycloak log output                                                                                | `default`                     |
| `KC_METRICS_ENABLED`            | Enable metrics.                                                                                    | `false`                       |
| `KC_HEALTH_ENABLED`             | Enable health check endpoints.                                                                     | `false`                       |
| `KC_CACHE`                      | Cache mechanism for high-availability.                                                             | `ispn`                        |
| `KC_CACHE_STACK`                | Default stack to use for cluster communication and node discovery.                                 | `nil`                         |
| `KC_CACHE_CONFIG_FILE`          | Path to the file from which cache configuration should be loaded from.                             | `cache-ispn.xml`              |
| `KC_HOSTNAME`                   | Keycloak hostname                                                                                  | `nil`                         |
| `KC_HOSTNAME_ADMIN`             | Keycloak admin hostname                                                                            | `nil`                         |
| `KC_HOSTNAME_STRICT`            | Disables dynamically resolving the hostname from request headers                                   | `false`                       |
| `KC_HTTPS_TRUST_STORE_FILE`     | Path to the SSL truststore file                                                                    | `nil`                         |
| `KC_HTTPS_TRUST_STORE_PASSWORD` | Password for decrypting the truststore file                                                        | `nil`                         |
| `KC_HTTPS_KEY_STORE_FILE`       | Path to the SSL keystore file                                                                      | `nil`                         |
| `KC_HTTPS_KEY_STORE_PASSWORD`   | Password for decrypting the keystore file                                                          | `nil`                         |
| `KC_HTTPS_CERTIFICATE_FILE`     | Path to the PEM certificate file                                                                   | `nil`                         |
| `KC_HTTPS_CERTIFICATE_KEY_FILE` | Path to the PEM key file                                                                           | `nil`                         |
| `KC_DB`                         | Database vendor                                                                                    | `postgres`                    |
| `KEYCLOAK_DATABASE_HOST`        | Database hostname                                                                                  | `postgresql`                  |
| `KEYCLOAK_DATABASE_PORT`        | Database port                                                                                      | `5432`                        |
| `KEYCLOAK_DATABASE_NAME`        | Database name                                                                                      | `bitnami_keycloak`            |
| `KEYCLOAK_JDBC_PARAMS`          | Extra JDBC connection parameters for the database (e.g.: sslmode=verify-full&connectTimeout=30000) | `nil`                         |
| `KEYCLOAK_JDBC_DRIVER`          | JDBC driver to set in the connection string for the database                                       | `postgresql`                  |
| `KC_DB_USERNAME`                | Database username                                                                                  | `bn_keycloak`                 |
| `KC_DB_PASSWORD`                | Database password                                                                                  | `nil`                         |
| `KC_DB_SCHEMA`                  | PostgreSQL database schema                                                                         | `public`                      |
| `KEYCLOAK_INIT_MAX_RETRIES`     | Maximum retries for checking that the database works                                               | `10`                          |
| `KEYCLOAK_DAEMON_USER`          | Keycloak daemon user when running as root                                                          | `keycloak`                    |
| `KEYCLOAK_DAEMON_GROUP`         | Keycloak daemon group when running as root                                                         | `keycloak`                    |

#### Read-only environment variables

| Name                        | Description                                             | Value                             |
|-----------------------------|---------------------------------------------------------|-----------------------------------|
| `BITNAMI_VOLUME_DIR`        | Directory where to mount volumes.                       | `/bitnami`                        |
| `JAVA_HOME`                 | Java installation directory                             | `/opt/bitnami/java`               |
| `KEYCLOAK_BASE_DIR`         | Keycloak base directory                                 | `/opt/bitnami/keycloak`           |
| `KEYCLOAK_BIN_DIR`          | Keycloak bin directory                                  | `$KEYCLOAK_BASE_DIR/bin`          |
| `KEYCLOAK_PROVIDERS_DIR`    | Keycloak providers (extensions) directory               | `$KEYCLOAK_BASE_DIR/providers`    |
| `KEYCLOAK_LOG_DIR`          | Keycloak log directory                                  | `$KEYCLOAK_PROVIDERS_DIR/log`     |
| `KEYCLOAK_TMP_DIR`          | Keycloak tmp directory                                  | `$KEYCLOAK_PROVIDERS_DIR/tmp`     |
| `KEYCLOAK_DOMAIN_TMP_DIR`   | Keycloak tmp directory                                  | `$KEYCLOAK_BASE_DIR/domain/tmp`   |
| `KEYCLOAK_VOLUME_DIR`       | Path to keycloak mount directory                        | `/bitnami/keycloak`               |
| `KEYCLOAK_CONF_DIR`         | Keycloak configuration directory                        | `$KEYCLOAK_BASE_DIR/conf`         |
| `KEYCLOAK_DEFAULT_CONF_DIR` | Keycloak default configuration directory                | `$KEYCLOAK_BASE_DIR/conf.default` |
| `KEYCLOAK_INITSCRIPTS_DIR`  | Path to keycloak init scripts directory                 | `/docker-entrypoint-initdb.d`     |
| `KEYCLOAK_CONF_FILE`        | Name of the keycloak configuration file (relative path) | `keycloak.conf`                   |

### Extra arguments to Keycloak startup

In case you want to add extra flags to Keycloak use the `KEYCLOAK_EXTRA_ARGS` variable. Example:

```console
docker run --name keycloak \
  -e KEYCLOAK_EXTRA_ARGS="-Dkeycloak.profile.feature.scripts=enabled" \
  ghcr.io/firmansyahn/containers/keycloak:latest
```

Or, if you need flags which are applied directly to keycloak executable, you can use `KEYCLOAK_EXTRA_ARGS_PREPENDED` variable. Example:

```console
docker run --name keycloak \
  -e KEYCLOAK_EXTRA_ARGS_PREPENDED="--spi-login-protocol-openid-connect-legacy-logout-redirect-uri=true" \
  ghcr.io/firmansyahn/containers/keycloak:latest
```

### Initializing a new instance

When the container is launched, it will execute the files with extension `.sh` located at `/docker-entrypoint-initdb.d`.

In order to have your custom files inside the docker image you can mount them as a volume.

```console
docker run --name keycloak \
  -v /path/to/init-scripts:/docker-entrypoint-initdb.d \
  ghcr.io/firmansyahn/containers/keycloak:latest
```

### TLS encryption

The image allows configuring HTTPS/TLS encryption. This is done by mounting in `/opt/bitnami/keycloak/certs` two files:

- `keystore`: File with the server `keystore`
- `truststore`: File with the server `truststore`

> **NOTE** Find more information about how to create these files at the [Keycloak documentation](https://www.keycloak.org/server/keycloak-truststore).

Apart from that, the following environment variables must be set:

- `KEYCLOAK_ENABLE_HTTPS`: Enable TLS encryption using the `keystore`. Default: **false**.
- `KC_HTTPS_KEY_STORE_FILE`: Path to the `keystore` file (e.g. `/opt/bitnami/keycloak/certs/keystore.jks`). No defaults.
- `KC_HTTPS_TRUST_STORE_FILE`: Path to the `truststore` file (e.g. `/opt/bitnami/keycloak/certs/truststore.jks`). No defaults.
- `KC_HTTPS_KEY_STORE_PASSWORD`: Password for accessing the `keystore`. No defaults.
- `KC_HTTPS_TRUST_STORE_PASSWORD`: Password for accessing the `truststore`. No defaults.
- `KEYCLOAK_HTTPS_USE_PEM`: Set to true to configure HTTPS using PEM certificates. Default: **false**.
- `KC_HTTPS_CERTIFICATE_FILE`: Path to the PEM certificate file (e.g. `/opt/bitnami/keycloak/certs/tls.crt`). No defaults.
- `KC_HTTPS_CERTIFICATE_KEY_FILE`: Path to the PEM key file (e.g. `/opt/bitnami/keycloak/certs/tls.key`). No defaults.

The older `KEYCLOAK_HTTPS_*` names of these `KC_HTTPS_*` variables are still read when the `KC_` one is not set.

### Adding custom themes

In order to add new themes to Keycloak, you can mount them to the `/opt/bitnami/keycloak/themes` folder. The example below mounts a new theme.

```yaml
services:
  postgresql:
    image: docker.io/bitnami/postgresql:latest
    environment:
      - ALLOW_EMPTY_PASSWORD=yes
      - POSTGRESQL_USERNAME=bn_keycloak
      - POSTGRESQL_DATABASE=bitnami_keycloak
    volumes:
      - postgresql_data:/bitnami/postgresql
  keycloak:
    image: ghcr.io/firmansyahn/containers/keycloak:latest
    ports:
      - 80:8080
    environment:
      - KC_BOOTSTRAP_ADMIN_PASSWORD=change-me
    depends_on:
      - postgresql
    volumes:
      - ./mynewtheme:/opt/bitnami/keycloak/themes/mynewtheme
volumes:
  postgresql_data:
    driver: local
```

### Enabling metrics

The container can activate different set of metrics (database, `jgroups` and HTTP) by setting the environment variable `KC_METRICS_ENABLED=true`. See [the official documentation](https://www.keycloak.org/observability/configuration-metrics) for more information about these metrics.

### Enabling health endpoints

The container can activate several endpoints providing information about the health of Keycloak by setting the environment variable `KC_HEALTH_ENABLED=true`. See [the official documentation](https://www.keycloak.org/observability/health) for more information about these endpoints.

### Full configuration

The image looks for configuration files in the `/bitnami/keycloak/conf/` directory. This directory can be changed by setting the `KEYCLOAK_MOUNTED_CONF_DIR` environment variable.

```console
docker run --name keycloak \
    -v /path/to/keycloak.conf:/bitnami/keycloak/conf/keycloak.conf \
    ghcr.io/firmansyahn/containers/keycloak:latest
```

After that, your changes will be taken into account in the server's behaviour.

## Smoke test

[`ci-smoke.sh`](ci-smoke.sh) stands up a throwaway PostgreSQL on its own docker network, aliased `postgresql`, then starts the amd64 build against it, waits for the `Keycloak <version> ... started in` log line, and asserts that version matches `APP_VERSION` in the Dockerfile.

The database is not optional. `KEYCLOAK_DATABASE_HOST` defaults to `postgresql` and the entrypoint blocks on `wait-for-port` until it answers, then exits — so the test also covers the real schema migration, not just process startup.

## Notable changes

These are Bitnami's, from before this repository existed; the tags they name are Bitnami's own.

### 26.3.2-debian-12-r1

The following environment variables have been deprecated. Instead rely on the native `KC_*` equivalent environment variables:

- `KEYCLOAK_CACHE_TYPE`, `KEYCLOAK_CACHE_STACK` and `KEYCLOAK_CACHE_CONFIG_FILE`
- `KEYCLOAK_ENABLE_STATISTICS` and `KEYCLOAK_ENABLE_HEALTH_ENDPOINTS`
- `KEYCLOAK_LOG_LEVEL` and `KEYCLOAK_LOG_OUTPUT`
- `KEYCLOAK_HOSTNAME`, `KEYCLOAK_HOSTNAME_ADMIN` and `KEYCLOAK_HOSTNAME_STRICT`
- `KEYCLOAK_PROXY_HEADERS`
- `KEYCLOAK_ADMIN_USER` and `KEYCLOAK_BOOTSTRAP_ADMIN_PASSWORD`

The [keycloak-metrics-spi](https://github.com/aerogear/keycloak-metrics-spi) provider is no longer shipped by default in the container image.
Also, support for deprecated SPI `truststore` was removed.

### 19-debian-11-r4

- TLS environment variables have been renamed to match upstream.
  - `KEYCLOAK_ENABLE_TLS` was renamed as `KEYCLOAK_ENABLE_HTTPS`.
  - `KEYCLOAK_TLS_KEYSTORE_FILE` was renamed as `KEYCLOAK_TLS_KEY_STORE_FILE`.
  - `KEYCLOAK_TLS_TRUSTSTORE_FILE` was renamed as `KEYCLOAK_TLS_TRUST_STORE_FILE`.
  - `KEYCLOAK_TLS_KEYSTORE_PASSWORD` was renamed as `KEYCLOAK_TLS_KEY_STORE_PASSWORD`.
  - `KEYCLOAK_TLS_TRUSTSTORE_PASSWORD` was renamed as `KEYCLOAK_TLS_TRUST_STORE_PASSWORD`.
- HTTPS/TLS can now be configured using PEM certificates.
- Added support to add SPI `truststore` file.

### 17-debian-10

Keycloak 17 is powered by Quarkus and to deploy it in production mode it is necessary to set up TLS.
To do this you need to set `KEYCLOAK_PRODUCTION` to **true** and configure TLS.

## License

This README is adapted from Bitnami's README for its Keycloak image, and the build files under `<branch>/debian-12/` are copied from [bitnami/containers](https://github.com/bitnami/containers/tree/main/bitnami/keycloak).

Copyright &copy; 2026 Broadcom. The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

Changes made in this repository are under the same license; see [LICENSE.md](../../LICENSE.md).
