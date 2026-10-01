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
. /opt/startechnica/scripts/libos.sh
. /opt/startechnica/scripts/libvipmanager.sh

if ! am_i_root && [[ -z "${VIPMANAGER_CAPS_RAISED:-}" ]]; then
    # As uid 1001 this shell holds no capability, whatever the runtime granted.
    # So run this script again through the image's copy of setpriv. Its file
    # capability gives it NET_ADMIN and NET_RAW, and it raises both into the
    # inheritable and ambient sets. Those carry them across the exec of this
    # script, of vip-manager, and of every `ip` vip-manager runs.
    vip_manager_validate_runtime || exit 1
    export VIPMANAGER_CAPS_RAISED=yes
    exec "$VIPMANAGER_SETPRIV" --inh-caps=+net_admin,+net_raw --ambient-caps=+net_admin,+net_raw \
        -- "${BASH_SOURCE[0]}" "$@"
fi
unset VIPMANAGER_CAPS_RAISED

# setpriv ignores a failed ambient raise, and vip-manager only logs a failed
# `ip`. This is the last point at which a VIP that could never move is caught.
vip_manager_validate_capabilities || exit 1

args=()
# vip-manager exits with "fatal error reading config file" when it is given a
# config path with no file behind it. So the path is passed only when a file is
# mounted there, and configuration through VIP_* variables alone still works. A
# VIP_CONFIG set by the user is left to vip-manager.
if [[ -z "${VIP_CONFIG:-}" && -f "$VIPMANAGER_CONF_FILE" ]]; then
    args+=("--config=${VIPMANAGER_CONF_FILE}")
fi
args+=("$@")

info "** Starting vip-manager **"
# Unlike the mirrors' run.sh, there is no switch to a daemon user when started
# as root: root is the fallback when the etcd client key is readable by root only.
exec vip-manager "${args[@]}"
