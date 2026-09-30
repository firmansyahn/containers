# NetBox with plugins: the netbox-docker image plus one layer of pinned
# packages. Derived, not mirrored — see ../README.md.
#
# The published tag is <tag of FROM>-r<IMAGE_REVISION>. The workflow reads both
# out of this file, so the base is named by tag *and* digest: the tag is for
# the reader and for our own tag, the digest is what gets pulled.
FROM docker.io/netboxcommunity/netbox:v4.7.1-5.1.1@sha256:59e3e5954d0243d8648f2fa7ba82cf7c7770aaeef392026cca8b21cd67411e74

# Goes up by one whenever anything in this directory changes on the same base;
# a new base starts again at 0. A published tag is never pushed twice, so a
# change here without a new revision fails the workflow.
ARG IMAGE_REVISION="0"

# Kept in the image, as netbox-docker keeps its own requirements files there:
# a pod can say what it was built from.
COPY plugin_requirements.txt /opt/netbox/plugin_requirements.txt

# One layer, so nothing the build turned on for itself can outlive it.
#
# Install: uv will not check hashes and resolve dependencies in one go — it
# wants a hash for Django too — so nothing is resolved. --no-deps installs
# exactly the lines of the file, --require-hashes refuses any of them whose
# wheel is not the one pinned, and --only-binary keeps a withdrawn wheel from
# being quietly replaced by a build of the sdist. The base image's own package
# list rides along as constraints: a line that names something the base
# already ships at another version is a conflict, not an upgrade. `uv pip
# check` then does what the resolver would have: a plugin whose dependency is
# neither in the base nor in the file fails the build here.
#
# Static files: NetBox serves /static from a directory in the image and the
# chart mounts nothing over it, so they are collected now. netbox-docker reads
# every file in /etc/netbox/config, the last one winning; the plugin is turned
# on by a file of our own that is deleted again, and plugins.py is never
# touched. A PLUGINS line left behind would win over the chart's values and
# turn the plugin on in every pod. PYTHONDONTWRITEBYTECODE keeps that file's
# .pyc out of the layer too. Same dummy key as netbox-docker's own build; no
# database is involved.
RUN set -eux; \
    uv pip freeze > /tmp/base-packages.txt; \
    uv pip install \
      --require-hashes --no-deps --only-binary :all: \
      --constraints /tmp/base-packages.txt \
      --requirements /opt/netbox/plugin_requirements.txt; \
    uv pip check; \
    rm /tmp/base-packages.txt; \
    echo 'PLUGINS = ["netbox_topology_views"]' > /etc/netbox/config/zz_build_static.py; \
    DEBUG="true" SECRET_KEY="dummyKeyWithMinimumLength-------------------------" PYTHONDONTWRITEBYTECODE=1 \
      /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py collectstatic --no-input; \
    rm /etc/netbox/config/zz_build_static.py
