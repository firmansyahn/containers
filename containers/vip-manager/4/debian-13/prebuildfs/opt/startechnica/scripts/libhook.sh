#!/bin/bash
# Copyright Startechnica. All Rights Reserved.
# Copyright Broadcom, Inc. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Modified by Startechnica from the shared library of the Bitnami containers:
# paths, switches and branding renamed to startechnica.
#
# Library to use for scripts expected to be used as Kubernetes lifecycle hooks

# shellcheck disable=SC1091

# Load generic libraries
. /opt/startechnica/scripts/liblog.sh
. /opt/startechnica/scripts/libos.sh

# Override functions that log to stdout/stderr of the current process, so they print to process 1
for function_to_override in stderr_print debug_execute; do
    # Output is sent to output of process 1 and thus end up in the container log
    # The hook output in general isn't saved
    eval "$(declare -f "$function_to_override") >/proc/1/fd/1 2>/proc/1/fd/2"
done
