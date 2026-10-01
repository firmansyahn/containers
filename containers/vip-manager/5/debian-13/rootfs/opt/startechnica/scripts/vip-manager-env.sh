#!/bin/bash
# Copyright Startechnica. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Environment configuration for vip-manager
#
# vip-manager reads its own settings from VIP_* variables and from its config
# file, and nothing here renames or wraps them. The variables below only locate
# the image's own files. They are named VIPMANAGER_*, not VIP_MANAGER_*, so
# that none of them falls under vip-manager's VIP_ prefix: VIP_MANAGER_TYPE,
# for one, is a vip-manager setting.

# Load logging library
# shellcheck disable=SC1090,SC1091
. /opt/startechnica/scripts/liblog.sh

export STARTECHNICA_ROOT_DIR="/opt/startechnica"

# Logging configuration
export MODULE="${MODULE:-vip-manager}"
export STARTECHNICA_DEBUG="${STARTECHNICA_DEBUG:-false}"

# Paths
export VIPMANAGER_BASE_DIR="${STARTECHNICA_ROOT_DIR}/vip-manager"
export VIPMANAGER_BIN_DIR="${VIPMANAGER_BASE_DIR}/bin"
export VIPMANAGER_SETPRIV="${VIPMANAGER_BASE_DIR}/libexec/setpriv"
# Where upstream's .deb and .rpm packages install the config file.
export VIPMANAGER_CONF_FILE="/etc/default/vip-manager.yml"

export PATH="${VIPMANAGER_BIN_DIR}:${PATH}"
