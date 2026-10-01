# Copyright Startechnica. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

FROM docker.io/bitnami/minideb:trixie

ARG TARGETARCH

LABEL org.opencontainers.image.base.name="docker.io/bitnami/minideb:trixie" \
      org.opencontainers.image.created="2026-10-01T00:00:00Z" \
      org.opencontainers.image.description="vip-manager, packaged by Startechnica." \
      org.opencontainers.image.documentation="https://github.com/firmansyahn/containers/tree/main/containers/vip-manager/README.md" \
      org.opencontainers.image.source="https://github.com/firmansyahn/containers/tree/main/containers/vip-manager" \
      org.opencontainers.image.title="vip-manager" \
      org.opencontainers.image.vendor="Startechnica" \
      org.opencontainers.image.version="4.2.0"

ENV HOME="/" \
    OS_ARCH="${TARGETARCH:-amd64}" \
    OS_FLAVOUR="debian-13" \
    OS_NAME="linux"

COPY prebuildfs /
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]
# Upstream publishes arm64 too, but this image is built for amd64 only.
RUN [[ "$OS_ARCH" == "amd64" ]] || { echo "vip-manager is built for amd64 only, not ${OS_ARCH}" >&2; exit 1; }
# iproute2: the `ip` vip-manager runs. curl: for an etcd healthcheck, and for
# hetzner mode. libcap2-bin: setcap for postunpack.sh. In trixie, iproute2
# depends on libcap2-bin, so it stays in the image.
RUN install_packages ca-certificates curl iproute2 libcap2-bin
RUN mkdir -p /tmp/startechnica/pkg/cache/ ; cd /tmp/startechnica/pkg/cache/ || exit 1 ; \
    COMPONENT="vip-manager_4.2.0_Linux_x86_64" ; \
    curl -SsLf "https://github.com/cybertec-postgresql/vip-manager/releases/download/v4.2.0/${COMPONENT}.tar.gz" -O ; \
    sha256sum -c "/opt/startechnica/checksums/${COMPONENT}.tar.gz.sha256" ; \
    tar -zxf "${COMPONENT}.tar.gz" --no-same-owner ; \
    install -D -m 0755 "${COMPONENT}/vip-manager" /opt/startechnica/vip-manager/bin/vip-manager ; \
    install -D -m 0644 "${COMPONENT}/LICENSE" /opt/startechnica/vip-manager/licenses/vip-manager-4.2.0.txt ; \
    cd / ; rm -rf /tmp/startechnica /opt/startechnica/checksums
RUN apt-get update && apt-get upgrade -y && \
    apt-get clean && rm -rf /var/lib/apt/lists /var/cache/apt/archives
RUN chmod g+rwX /opt/startechnica
RUN find / -perm /6000 -type f -exec chmod a-s {} \; || true
RUN ln -s /opt/startechnica/scripts/vip-manager/entrypoint.sh /entrypoint.sh
RUN ln -s /opt/startechnica/scripts/vip-manager/run.sh /run.sh

COPY rootfs /
RUN /opt/startechnica/scripts/vip-manager/postunpack.sh
ENV APP_VERSION="4.2.0" \
    STARTECHNICA_APP_NAME="vip-manager" \
    IMAGE_REVISION="0" \
    PATH="/opt/startechnica/vip-manager/bin:$PATH"

USER 1001
ENTRYPOINT [ "/opt/startechnica/scripts/vip-manager/entrypoint.sh" ]
CMD [ "/opt/startechnica/scripts/vip-manager/run.sh" ]
