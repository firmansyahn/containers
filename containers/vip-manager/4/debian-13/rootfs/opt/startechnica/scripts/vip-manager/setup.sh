#!/bin/bash
# Copyright Startechnica. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0

# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load vip-manager environment variables
. /opt/startechnica/scripts/vip-manager-env.sh

# Load libraries
. /opt/startechnica/scripts/libvipmanager.sh

# Fail now, naming what is missing, rather than run without moving the VIP
vip_manager_validate_runtime

if [[ -n "${VIP_CONFIG:-}" ]]; then
    info "Configuration: VIP_* variables, then the file VIP_CONFIG names (${VIP_CONFIG})"
elif [[ -f "$VIPMANAGER_CONF_FILE" ]]; then
    info "Configuration: VIP_* variables, then ${VIPMANAGER_CONF_FILE}"
else
    info "Configuration: VIP_* variables only, as nothing is mounted at ${VIPMANAGER_CONF_FILE}"
fi
