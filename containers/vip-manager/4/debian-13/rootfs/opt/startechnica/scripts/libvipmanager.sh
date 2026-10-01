#!/bin/bash
# Copyright Startechnica. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Startechnica vip-manager library

# shellcheck disable=SC1091

# Load generic libraries
. /opt/startechnica/scripts/liblog.sh
. /opt/startechnica/scripts/libos.sh

# What vip-manager needs, as name:bit in the /proc/<pid>/status masks
# (linux/capability.h). NET_ADMIN is for the `ip addr` it runs to add and
# remove the VIP, NET_RAW for the gratuitous ARP it sends over a raw socket.
VIPMANAGER_CAPABILITIES=(NET_ADMIN:12 NET_RAW:13)

########################
# Read a field of this shell's /proc/<pid>/status
# Arguments:
#   $1 - field name, e.g. CapAmb or NoNewPrivs
# Returns:
#   The field's value
#########################
vip_manager_status_field() {
    local -r field="${1:?missing field}"
    local key value
    # $$ is this shell even inside $(...), so this reads the process that will
    # exec vip-manager, not a subshell or a child such as awk.
    while read -r key value; do
        if [[ "$key" == "${field}:" ]]; then
            echo "$value"
            return 0
        fi
    done < "/proc/$$/status"
    return 1
}

########################
# List the capabilities vip-manager needs that one capability set of this shell lacks
# Arguments:
#   $1 - set: CapInh, CapPrm, CapEff, CapBnd or CapAmb
# Returns:
#   The missing capability names, space-separated; nothing when none is missing
#########################
vip_manager_missing_caps() {
    local -r set="${1:?missing set}"
    local hex cap
    local missing=()
    hex="$(vip_manager_status_field "$set")"
    for cap in "${VIPMANAGER_CAPABILITIES[@]}"; do
        (( (16#$hex >> ${cap##*:}) & 1 )) || missing+=("${cap%%:*}")
    done
    echo "${missing[*]}"
}

########################
# Check that the runtime gave the container what vip-manager needs
# Reads the bounding set, which is what the runtime granted; nothing has been
# raised yet at this point.
# Returns:
#   0 if it did, 1 after logging what is missing
#########################
vip_manager_validate_runtime() {
    local missing
    missing="$(vip_manager_missing_caps CapBnd)"
    if [[ -n "$missing" ]]; then
        error "The container was started without ${missing// /, }, which vip-manager needs to move the VIP. Grant NET_ADMIN and NET_RAW (docker run --cap-add, cap_add in compose, AddCapability= in a Quadlet), with host networking."
        return 1
    fi
    if ! am_i_root && [[ "$(vip_manager_status_field NoNewPrivs)" == 1 ]]; then
        error "no-new-privileges is set. As uid $(id -u), vip-manager gets NET_ADMIN and NET_RAW through a file capability, and no-new-privileges cancels file capabilities. Remove it for this container, or run the container as root."
        return 1
    fi
}

########################
# Check that vip-manager, and every `ip` it runs, will hold the capabilities it needs
# Call it in the shell that execs vip-manager, once they have been raised.
# Returns:
#   0 if they will, 1 after logging which set lacks which capability
#########################
vip_manager_validate_capabilities() {
    local set missing failed=0
    local sets=(CapEff)
    # Run as root, `ip` keeps the capabilities it starts with. Run as anyone
    # else, Debian's `ip` drops them all at start unless NET_ADMIN is in its
    # inheritable set, and only the ambient set carries capabilities across the
    # exec of a file that has none of its own: vip-manager, then `ip`.
    am_i_root || sets+=(CapInh CapAmb)
    for set in "${sets[@]}"; do
        missing="$(vip_manager_missing_caps "$set")"
        if [[ -n "$missing" ]]; then
            error "vip-manager would run without ${missing// /, } in its ${set#Cap} capability set (${set} $(vip_manager_status_field "$set")), and could not move the VIP."
            failed=1
        fi
    done
    return "$failed"
}
