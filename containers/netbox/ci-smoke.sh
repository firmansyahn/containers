#!/usr/bin/env bash
# Smoke test for a freshly built netbox image.
# Called by .github/workflows/netbox.yml with IMAGE and CONTEXT set.
#
# The image is the netbox-docker image plus one layer, so this is a comparison
# with its base rather than a boot: what the layer was meant to add is there,
# and nothing else moved. No database is started. The plugins first meet one
# in ci-plugin-tests.sh, and all together on the rehearsal copy.
#
# Every check runs even after one has failed, so one CI run shows all of them.
set -euo pipefail

: "${IMAGE:?IMAGE not set}"
: "${CONTEXT:?CONTEXT not set}"

dockerfile="$CONTEXT/Dockerfile"
requirements="$CONTEXT/plugin_requirements.txt"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failed=0
ok()   { echo "ok    $*"; }
fail() { echo "::error::$*"; failed=1; }

# The Dockerfile's own FROM line, digest included: the image this one has to
# be compared with is the one it was built on, not whatever the tag says today.
base=$(grep -m1 -oP '^FROM\s+\K\S+' "$dockerfile")
base_tag=$(echo "$base" | grep -oP ':\K[^:@]+(?=@sha256:)')
revision=$(grep -oP '^ARG IMAGE_REVISION="\K[0-9]+(?=")' "$dockerfile")
want_tag="${base_tag}-r${revision}"
# v4.7.1-5.1.1 is <netbox version>-<netbox-docker version>.
want_netbox=$(echo "$base_tag" | sed -E 's/^v([^-]+)-.*$/\1/')
grep -oP '^[A-Za-z0-9][A-Za-z0-9._-]*==[^\s\\]+' "$requirements" | LC_ALL=C sort > "$work/pins"
[ -s "$work/pins" ] || { echo "::error::no pinned package found in $requirements"; exit 1; }

# netbox-docker's entrypoint is `tini --`, so a command given here replaces
# the launch script and nothing waits for a database. The key and DEBUG are
# what netbox-docker's own build passes to load the settings without one.
run() {
  docker run --rm -i \
    -e SECRET_KEY='dummyKeyWithMinimumLength-------------------------' -e DEBUG=true \
    "$@"
}

echo "image  $IMAGE"
echo "base   $base"

# --- packages ---------------------------------------------------------------
# Compared as whole lists: a plugin dependency that moved Django would show up
# as one line gone and one line new, not just as something added.
run "$base"  uv pip freeze | LC_ALL=C sort > "$work/base.freeze"
run "$IMAGE" uv pip freeze | LC_ALL=C sort > "$work/image.freeze"
[ -s "$work/base.freeze" ] || { echo "::error::could not list the base image's packages"; exit 1; }

LC_ALL=C comm -23 "$work/base.freeze" "$work/image.freeze" > "$work/moved"
LC_ALL=C comm -13 "$work/base.freeze" "$work/image.freeze" > "$work/added"
if [ -s "$work/moved" ]; then
  fail "packages of the base image changed or went missing: $(paste -sd' ' "$work/moved")"
else
  ok "all $(wc -l < "$work/base.freeze") packages of the base image are at the base image's versions"
fi
if diff -u "$work/pins" "$work/added" > "$work/added.diff"; then
  ok "added packages are exactly the requirements file's: $(paste -sd' ' "$work/added")"
else
  cat "$work/added.diff"
  fail "added packages differ from $requirements (- pinned, + in the image)"
fi

# --- the requirements file, read back from the image --------------------------
if run "$IMAGE" cat /opt/netbox/plugin_requirements.txt | diff -u "$requirements" - > "$work/req.diff"; then
  ok "/opt/netbox/plugin_requirements.txt in the image is the repo's"
else
  cat "$work/req.diff"
  fail "/opt/netbox/plugin_requirements.txt in the image is not the repo's"
fi

# --- NetBox itself ----------------------------------------------------------
got_netbox=$(run "$IMAGE" cat /opt/netbox/netbox/release.yaml | grep -oP '^version:\s*"?\K[0-9][^"\s]*' || true)
if [ "$got_netbox" = "$want_netbox" ]; then
  ok "NetBox's release file reads $got_netbox"
else
  fail "NetBox's release file reads '${got_netbox}', the base tag says $want_netbox"
fi

# --- configuration ----------------------------------------------------------
# netbox-docker reads every .py in this directory and the last one read wins,
# so a PLUGINS line left behind by the build would override the chart's values
# and turn plugins on in every pod. The directory has to be the base image's,
# file for file. __pycache__ is left out: bytecode is not configuration.
config_files='cd /etc/netbox/config && find . -type f -not -path "*/__pycache__/*" -exec sha256sum {} + | LC_ALL=C sort -k2'
run "$base"  sh -c "$config_files" > "$work/base.config"
run "$IMAGE" sh -c "$config_files" > "$work/image.config"
if [ -s "$work/base.config" ] && diff -u "$work/base.config" "$work/image.config" > "$work/config.diff"; then
  ok "/etc/netbox/config is the base image's, $(wc -l < "$work/base.config") files"
else
  cat "$work/config.diff" 2>/dev/null || true
  fail "/etc/netbox/config differs from the base image's (- base, + image)"
fi

# --- plugins: off as shipped, loadable, in range --------------------------------
# With the image's own configuration NetBox must load no plugin at all. The
# same process then imports what the requirements file added and picks out the
# NetBox plugins — a module with a `config` that is a PluginConfig — and holds
# each against this NetBox's version. NetBox itself only warns about a plugin
# outside its min_version/max_version and starts without it; here that fails.
cat > "$work/probe_off.py" <<'EOF'
import importlib
import re
import sys
from importlib.metadata import packages_distributions

import django

django.setup()

from django.conf import settings
from netbox.plugins import PluginConfig

if settings.PLUGINS:
    sys.exit(f'the image turns plugins on by itself: PLUGINS = {settings.PLUGINS}')

def norm(name):
    return re.sub(r'[-_.]+', '-', name).lower()

added = {norm(a.split('==')[0]) for a in sys.argv[1:]}
modules = sorted(
    module for module, dists in packages_distributions().items()
    if added & {norm(d) for d in dists}
)
for module in modules:
    config = getattr(importlib.import_module(module), 'config', None)
    if isinstance(config, type) and issubclass(config, PluginConfig):
        # Raises for a NetBox outside the plugin's version range.
        config.validate({}, settings.RELEASE.version)
        print(f'plugin {module}')
EOF
mapfile -t pins < "$work/pins"
if run -e DJANGO_SETTINGS_MODULE=netbox.settings "$IMAGE" python - "${pins[@]}" \
     < "$work/probe_off.py" > "$work/plugins" 2> "$work/probe_off.err"; then
  # netbox-docker's configuration loader prints to stdout too, hence the prefix.
  mapfile -t plugins < <(sed -n 's/^plugin //p' "$work/plugins")
  ok "no plugin is on as shipped; ${#plugins[@]} installed and in range for NetBox $want_netbox: ${plugins[*]}"
else
  cat "$work/probe_off.err"
  fail "the image's own configuration, or a plugin's version range, is wrong (see above)"
  plugins=()
fi
[ "${#plugins[@]}" -gt 0 ] || fail "no NetBox plugin found among the added packages"

# All of them on at once, still without a database: every plugin's models,
# navigation, template extensions and search indexes are imported and its
# ready() runs. A plugin NetBox skipped is missing from the app registry.
if [ "${#plugins[@]}" -gt 0 ]; then
  printf 'PLUGINS = [%s]\n' "$(printf '"%s", ' "${plugins[@]}")" > "$work/zz_smoke_plugins.py"
  cat > "$work/probe_on.py" <<'EOF'
import sys

import django

django.setup()

from django.apps import apps
from django.conf import settings

for name in sys.argv[1:]:
    if name not in settings.PLUGINS or not apps.is_installed(name):
        sys.exit(f'{name} did not load')
    print(f'loaded {name} {apps.get_app_config(name).version}')
EOF
  if run -e DJANGO_SETTINGS_MODULE=netbox.settings \
       -v "$work/zz_smoke_plugins.py:/etc/netbox/config/zz_smoke_plugins.py:ro" \
       "$IMAGE" python - "${plugins[@]}" < "$work/probe_on.py" > "$work/loaded" 2> "$work/probe_on.err"; then
    ok "all plugins load together without a database: $(sed -n 's/^loaded //p' "$work/loaded" | paste -sd, | sed 's/,/, /g')"
  else
    cat "$work/probe_on.err"
    fail "the plugins do not all load together (see above)"
  fi
fi

# --- static files -----------------------------------------------------------
# NetBox serves /static from this directory in the image and the chart mounts
# nothing over it: a file a plugin ships under <module>/static/ and the build
# did not collect is a page without its stylesheet. Checked for every plugin,
# so a later one with static files fails here until the Dockerfile's
# collectstatic turns it on as well. Plugins only: django-polymorphic ships
# two files for Django's admin, but it is never an installed app in NetBox, so
# nothing would collect or serve them.
cat > "$work/static.py" <<'EOF'
import filecmp
import sys
from importlib.util import find_spec
from pathlib import Path

root = Path('/opt/netbox/netbox/static')
shipped = missing = 0
for module in sys.argv[1:]:
    # find_spec on a top-level name does not import it, so no settings are needed.
    static = Path(find_spec(module).submodule_search_locations[0]) / 'static'
    for f in static.rglob('*'):
        if f.is_file():
            shipped += 1
            collected = root / f.relative_to(static)
            if not collected.is_file() or not filecmp.cmp(f, collected, shallow=False):
                missing += 1
                print(f'not collected: {collected}', file=sys.stderr)
for named in ('netbox_topology_views/css/app.css', 'netbox_topology_views/img/role-unknown.svg'):
    if not (root / named).is_file():
        missing += 1
        print(f'not collected: {root / named}', file=sys.stderr)
print(f'{shipped} shipped, {missing} not collected')
sys.exit(1 if missing or not shipped else 0)
EOF
if [ "${#plugins[@]}" -gt 0 ]; then
  if static=$(run "$IMAGE" python - "${plugins[@]}" < "$work/static.py"); then
    ok "the plugins' static files are in /opt/netbox/netbox/static: $static"
  else
    fail "the plugins' static files are not all collected: ${static:-none found}"
  fi
fi

# --- labels -----------------------------------------------------------------
# The tag names a revision, not what is inside, so the labels have to.
label() { docker image inspect --format "{{ index .Config.Labels \"$1\" }}" "$IMAGE"; }
want_label() {
  local got
  got=$(label "$1")
  if [ "$got" = "$2" ]; then ok "label $1 = $got"; else fail "label $1 is '$got', expected '$2'"; fi
}
want_label io.github.firmansyahn.containers.packages "$(grep -oP '^[A-Za-z0-9][A-Za-z0-9._-]*==[^\s\\]+' "$requirements" | paste -sd' ')"
want_label org.opencontainers.image.version "$want_tag"
want_label org.opencontainers.image.base.name "${base%@*}"
want_label org.opencontainers.image.base.digest "${base#*@}"
if [ -n "${GITHUB_SHA:-}" ]; then
  want_label org.opencontainers.image.source "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
  want_label org.opencontainers.image.revision "$GITHUB_SHA"
fi
if [ -n "${BUILD_HASH:-}" ]; then
  want_label io.github.firmansyahn.containers.build-files "$BUILD_HASH"
fi

if [ "$failed" -ne 0 ]; then
  echo "::error::smoke test failed for $IMAGE"
  exit 1
fi
echo "netbox $got_netbox with $(paste -sd' ' "$work/pins") passed"
