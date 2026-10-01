#!/usr/bin/env bash
# Copyright Startechnica. All Rights Reserved.
# SPDX-License-Identifier: APACHE-2.0
#
# Copies the mirrors' shared shell library and apt helpers into every
# vip-manager branch, rebranded for startechnica. Run it again whenever the
# mirrors' library changes, review the diff, and raise IMAGE_REVISION in each
# branch whose files changed.
#
# The rebranding is mechanical, so it is repeated rather than hand-edited:
#   /opt/bitnami      -> /opt/startechnica
#   libbitnami.sh     -> libstartechnica.sh
#   BITNAMI_*         -> STARTECHNICA_*
#   bitnami.<unit>    -> startechnica.<unit>   (systemd units in libservice.sh)
#   Bitnami, bitnami  -> Startechnica, startechnica (comments, banner, licenses.txt)
# plus a banner line linking to this repo, and on every script a Startechnica
# copyright line and a modification notice above Broadcom's, which stays.
#
# Needs GNU sed. Reads the library from HEAD, not the working tree, so a
# Windows checkout's CRLF line endings never reach the image.
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
cd "$repo"

# redis and keycloak carry byte-identical copies; take redis's newest branch.
# They stay on debian-12; the library is the same on the vip-manager branches'
# debian-13.
src_branch=$(find containers/redis -mindepth 2 -maxdepth 2 -type d -name debian-12 \
  | cut -d/ -f3 | sort -V | tail -1)
src="containers/redis/${src_branch}/debian-12/prebuildfs"
echo "shared library from $src at $(git rev-parse --short HEAD)"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git archive HEAD "$src/opt/bitnami/scripts" "$src/opt/bitnami/licenses" "$src/usr/sbin" \
  | tar -x -C "$work"

out="$work/out"
mkdir -p "$out/opt/startechnica" "$out/usr"
cp -a "$work/$src/opt/bitnami/scripts" "$work/$src/opt/bitnami/licenses" "$out/opt/startechnica/"
cp -a "$work/$src/usr/sbin" "$out/usr/"
mv "$out/opt/startechnica/scripts/libbitnami.sh" "$out/opt/startechnica/scripts/libstartechnica.sh"

notice='#\n# Modified by Startechnica from the shared library of the Bitnami containers:\n# paths, switches and branding renamed to startechnica.'

find "$out" -type f | while read -r f; do
  sed -E -i \
    -e 's#/opt/bitnami#/opt/startechnica#g' \
    -e 's#libbitnami\.sh#libstartechnica.sh#g' \
    -e 's#\bBITNAMI_#STARTECHNICA_#g' \
    -e 's#\bbitnami\.([a-z$"])#startechnica.\1#g' \
    -e 's#https://github\.com/bitnami/containers#https://github.com/firmansyahn/containers#g' \
    -e 's#\bBitnami\b#Startechnica#g' \
    -e 's#\bbitnami\b#startechnica#g' \
    "$f"
  if grep -q '^# Copyright Broadcom, Inc\. All Rights Reserved\.$' "$f"; then
    sed -i \
      -e '0,/^# Copyright Broadcom, Inc\. All Rights Reserved\.$/s//# Copyright Startechnica. All Rights Reserved.\n&/' \
      -e "0,/^# SPDX-License-Identifier: APACHE-2.0\$/s//&\n${notice}/" \
      "$f"
  fi
done

# The banner names startechnica (above) and links to this repo. Upstream's
# print_image_welcome_page sets github_url but prints nothing with it.
banner="$out/opt/startechnica/scripts/libstartechnica.sh"
grep -q 'Welcome to the Startechnica \${STARTECHNICA_APP_NAME} container' "$banner" \
  || { echo "banner line not found in $banner; upstream changed it, update this script" >&2; exit 1; }
sed -i '/Welcome to the Startechnica \${STARTECHNICA_APP_NAME} container/a\    info "Source and documentation: ${BOLD}${github_url}${RESET}"' "$banner"

# Nothing may still point at the Bitnami layout (R6, AE6).
if leftover=$(grep -rIn -e '/opt/bitnami' -e 'libbitnami' -e 'BITNAMI_' "$out"); then
  echo "rebranding missed:" >&2
  echo "$leftover" >&2
  exit 1
fi

for dir in containers/vip-manager/*/debian-*; do
  pre="$dir/prebuildfs"
  # Each branch keeps its own checksums; everything else is replaced.
  rm -rf "$pre/opt/startechnica/scripts" "$pre/opt/startechnica/licenses" "$pre/usr/sbin"
  mkdir -p "$pre/opt/startechnica" "$pre/usr"
  cp -a "$out/opt/startechnica/scripts" "$out/opt/startechnica/licenses" "$pre/opt/startechnica/"
  cp -a "$out/usr/sbin" "$pre/usr/"
  echo "  $pre"
done
