#!/bin/bash
# Copyright Startechnica. All Rights Reserved.
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Modified by Startechnica from the redis entrypoint of the Bitnami containers:
# rewritten for vip-manager.

# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load vip-manager environment variables
. /opt/startechnica/scripts/vip-manager-env.sh

# Load libraries
. /opt/startechnica/scripts/libstartechnica.sh
. /opt/startechnica/scripts/libvipmanager.sh

print_welcome_page

debug "Running as uid $(id -u), capabilities: bounding $(vip_manager_status_field CapBnd), effective $(vip_manager_status_field CapEff)"

if [[ "$*" = *"/opt/startechnica/scripts/vip-manager/run.sh"* || "$*" = *"/run.sh"* ]]; then
    info "** Starting vip-manager setup **"
    /opt/startechnica/scripts/vip-manager/setup.sh
    info "** vip-manager setup finished! **"
fi

echo ""
exec "$@"
