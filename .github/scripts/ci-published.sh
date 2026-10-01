#!/usr/bin/env bash
# Says whether a revision tag is already on GHCR, and if so whether it was built
# from the same files. Called by .github/workflows/netbox.yml and build.yml with
# IMAGE, TAG and BUILD_HASH set.
#
# A published revision tag is never pushed again: production pins images by
# digest, and a second push of the same tag would leave that digest with no tag
# pointing at it. So the answer is one of
#
#   state=absent      nothing under that tag (or nothing we are allowed to see)
#   state=same        published, from these build files: there is nothing to do
#   state=unlabelled  published before images carried the build-files label, so
#                     it cannot be compared; only with ACCEPT_UNLABELLED=1,
#                     which the mirrors set for the images they pushed before
#                     the label existed. Treated as published.
#   (exit 1)          published, from other build files: IMAGE_REVISION in the
#                     Dockerfile was not raised
#
# written to stdout as key=value lines, with digest= and config= when the tag
# exists, so the caller can append them to $GITHUB_OUTPUT. Everything else goes
# to stderr.
#
# GHCR_USER and GHCR_TOKEN are optional. Without them the question is asked
# anonymously, which only a public package answers; a private one reads as
# absent. The job that pushes asks again with its token, and that answer is the
# one that counts.
set -euo pipefail

: "${IMAGE:?IMAGE not set}"
: "${TAG:?TAG not set}"
: "${BUILD_HASH:?BUILD_HASH not set}"

registry=${IMAGE%%/*}
path=${IMAGE#*/}
label='io.github.firmansyahn.containers.build-files'
accept='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

auth=()
if [ -n "${GHCR_TOKEN:-}" ]; then
  auth=(-u "${GHCR_USER:?GHCR_USER not set}:${GHCR_TOKEN}")
fi

# A registry that will not hand out a pull token is saying the same thing as a
# 404 on the manifest: not there, or not for us.
tok=$(curl -sS "${auth[@]}" "https://$registry/token?scope=repository:$path:pull&service=$registry" \
  | jq -r '.token // empty' 2>/dev/null) || tok=''
if [ -z "$tok" ]; then
  echo "no pull token for $IMAGE — reading it as absent" >&2
  echo "state=absent"
  exit 0
fi

# $1 = manifest reference (tag or digest); body to $work/manifest, headers to
# $work/headers, HTTP status on stdout.
manifest() {
  curl -sS -o "$work/manifest" -D "$work/headers" -w '%{http_code}' \
    -H "Authorization: Bearer $tok" -H "Accept: $accept" \
    "https://$registry/v2/$path/manifests/$1"
}

code=$(manifest "$TAG")
case "$code" in
  200) ;;
  401|403|404)
    echo "$IMAGE:$TAG answered $code — absent" >&2
    echo "state=absent"
    exit 0
    ;;
  *)
    # Anything else is the registry having a bad day. Guessing "absent" here
    # is how a tag gets pushed twice.
    echo "::error::$registry answered $code for $IMAGE:$TAG" >&2
    exit 1
    ;;
esac

digest=$(tr -d '\r' < "$work/headers" | awk 'tolower($1)=="docker-content-digest:"{print $2}')

# A multi-arch tag is an index. Every image under it was built from the same
# files, so any one of them carries the label; attestation entries do not.
if jq -e 'has("manifests")' "$work/manifest" >/dev/null; then
  child=$(jq -r '[.manifests[] | select(.platform.os != "unknown")][0].digest // empty' "$work/manifest")
  [ -n "$child" ] || { echo "::error::$IMAGE:$TAG is an index with no image in it" >&2; exit 1; }
  code=$(manifest "$child")
  [ "$code" = 200 ] || { echo "::error::$registry answered $code for $IMAGE@$child" >&2; exit 1; }
fi

config=$(jq -r '.config.digest // empty' "$work/manifest")
[ -n "$config" ] || { echo "::error::$IMAGE:$TAG has no config digest" >&2; exit 1; }

# -L: GHCR answers a blob request with a redirect to its storage.
curl -fsSL -o "$work/config" -H "Authorization: Bearer $tok" "https://$registry/v2/$path/blobs/$config"
published=$(jq -r --arg l "$label" '.config.Labels[$l] // empty' "$work/config")

echo "digest=$digest"
echo "config=$config"

if [ "$published" = "$BUILD_HASH" ]; then
  echo "$IMAGE:$TAG is published from these build files, as $digest" >&2
  echo "state=same"
  exit 0
fi

if [ -z "$published" ] && [ "${ACCEPT_UNLABELLED:-}" = 1 ]; then
  echo "::warning::$IMAGE:$TAG is published as $digest without label $label, so its build files cannot be compared; counting it as published. Raise IMAGE_REVISION if they changed." >&2
  echo "state=unlabelled"
  exit 0
fi

echo "::error::$IMAGE:$TAG is already published from other build files (label $label is '${published:-unset}', these hash to $BUILD_HASH). A published tag is never pushed again: raise IMAGE_REVISION in the Dockerfile." >&2
exit 1
