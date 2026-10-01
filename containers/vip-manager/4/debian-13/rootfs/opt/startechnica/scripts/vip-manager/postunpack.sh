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
. /opt/startechnica/scripts/libfs.sh

ensure_dir_exists "$(dirname "$VIPMANAGER_SETPRIV")"

# The image's only file capability, on a private copy of setpriv rather than on
# vip-manager or `ip`. Debian's `ip` cancels a capability of its own for any
# non-root caller, by dropping everything unless NET_ADMIN is in its inheritable
# set. And a capability on vip-manager would never reach the `ip` it runs.
# run.sh has setpriv raise both capabilities into the inheritable and ambient
# sets instead.
#
# Permitted only: setpriv raises what it needs itself.
#
# This must stay last. A later chown of the file would clear it.
install -m 0755 /usr/bin/setpriv "$VIPMANAGER_SETPRIV"
setcap cap_net_admin,cap_net_raw+p "$VIPMANAGER_SETPRIV"
getcap "$VIPMANAGER_SETPRIV" | grep -qE 'cap_net_admin,cap_net_raw[+=]p$' \
    || { error "setcap left ${VIPMANAGER_SETPRIV} without its capabilities"; exit 1; }
