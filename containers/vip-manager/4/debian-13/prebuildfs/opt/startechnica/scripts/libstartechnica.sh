#!/bin/bash
# Copyright Startechnica. All Rights Reserved.
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Modified by Startechnica from the shared library of the Bitnami containers:
# paths, switches and branding renamed to startechnica.
#
# Startechnica custom library

# shellcheck disable=SC1091

# Load Generic Libraries
. /opt/startechnica/scripts/liblog.sh

# Constants
BOLD='\033[1m'

# Functions

########################
# Print the welcome page
# Globals:
#   DISABLE_WELCOME_MESSAGE
#   STARTECHNICA_APP_NAME
# Arguments:
#   None
# Returns:
#   None
#########################
print_welcome_page() {
    if [[ -z "${DISABLE_WELCOME_MESSAGE:-}" ]]; then
        if [[ -n "$STARTECHNICA_APP_NAME" ]]; then
            print_image_welcome_page
        fi
    fi
}

########################
# Print the welcome page for a Startechnica Docker image
# Globals:
#   STARTECHNICA_APP_NAME
# Arguments:
#   None
# Returns:
#   None
#########################
print_image_welcome_page() {
    local github_url="https://github.com/firmansyahn/containers"

    info ""
    info "${BOLD}Welcome to the Startechnica ${STARTECHNICA_APP_NAME} container${RESET}"
    info "Source and documentation: ${BOLD}${github_url}${RESET}"
    info ""
}

