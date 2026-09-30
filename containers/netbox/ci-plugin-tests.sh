#!/usr/bin/env bash
# Runs the plugins' own test suites inside a freshly built netbox image.
# Called by .github/workflows/netbox.yml with IMAGE and CONTEXT set, after the
# smoke test and before anything is pushed.
#
# Upstream runs these suites against NetBox `main` only, so nobody else runs
# them on the NetBox this image ships. The packages on PyPI leave the tests out
# (netbox-routing ships a few of its test directories, but not the base classes
# they import), so each plugin's `tests` directory is taken from its repository
# at the commit of the pinned release and copied into a container of the built
# image, beside the installed package. The suite then tests the package
# production will run, not a checkout.
#
# Each suite runs with its own plugin on, alone, one test at a time, against a
# throwaway PostgreSQL and Redis on a network with no way out. The suites are
# other people's code: the job that runs this holds no token that can write.
#
# The log ends with, for each suite, the tests run, every skipped test with its
# reason, and the query counts that differ from the baseline the release ships.
set -euo pipefail

: "${IMAGE:?IMAGE not set}"
: "${CONTEXT:?CONTEXT not set}"

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
requirements="$CONTEXT/plugin_requirements.txt"

# package | version | repository | commit of that release | module
#
# The version has to be the one plugin_requirements.txt pins, and the commit
# has to be that release: the run fails if the file pins another version, if
# the repository at that commit declares another, or if a .py file of the
# installed package is not byte for byte the one at that commit.
SUITES=(
  'netbox-routing|0.5.0|DanSheps/netbox-routing|d5aeb997f3d74ffc314a6f5967129d3455f683bb|netbox_routing'
  'netbox-security|1.6.8|andy-shady-org/netbox-security|fa9510f56d883904c410607725507eab3ac464c2|netbox_security'
)

# package | why no suite runs for it
#
# Every line of plugin_requirements.txt is in one list or the other, so a
# package cannot be added to the image without deciding which.
NO_SUITE=(
  'netbox-topology-views|its repository has no tests at v4.7.0; the rehearsal on the copy is its only evidence'
  'django-polymorphic|a library netbox-routing requires, not a plugin'
)

# module | full test id | reason (no "|" in it)
#
# For a test that cannot pass in this setting for a reason that is not the
# plugin's. Each entry is approved by name before the image goes anywhere, and
# an entry that matches no test fails the run. A suite that needs many of
# these is not evidence.
SKIPS=(
)

# pg-pegasus runs PostgreSQL 18.
postgres_image=docker.io/library/postgres:18-alpine
redis_image=docker.io/library/redis:8-alpine

net="netbox-tests-net-$$"
pg="netbox-tests-pg-$$"
redis="netbox-tests-redis-$$"
work=$(mktemp -d)
summary="$work/summary.md"
containers=()

cleanup() {
  docker rm -f "$pg" "$redis" "${containers[@]}" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

failed=0
fail() { echo "::error::$*"; failed=1; }

# --- the three lists have to agree before anything is started ---------------
declare -A pinned=() accounted=()
while IFS='=' read -r name _ version; do
  pinned[$name]=$version
done < <(grep -oP '^[A-Za-z0-9][A-Za-z0-9._-]*==[^\s\\]+' "$requirements")
[ "${#pinned[@]}" -gt 0 ] || { echo "::error::no pinned package found in $requirements"; exit 1; }

for suite in "${SUITES[@]}"; do
  IFS='|' read -r package version _ _ _ <<< "$suite"
  accounted[$package]=1
  if [ -z "${pinned[$package]:-}" ]; then
    fail "SUITES names $package, which $requirements does not pin"
  elif [ "${pinned[$package]}" != "$version" ]; then
    fail "SUITES has $package at $version with that release's commit, but $requirements pins ${pinned[$package]}"
  fi
done
for entry in "${NO_SUITE[@]}"; do
  package=${entry%%|*}
  accounted[$package]=1
  [ -n "${pinned[$package]:-}" ] || fail "NO_SUITE names $package, which $requirements does not pin"
done
for package in "${!pinned[@]}"; do
  [ -n "${accounted[$package]:-}" ] || fail "$package is pinned in $requirements but is in neither SUITES nor NO_SUITE"
done
[ "$failed" -eq 0 ] || exit 1

# --- PostgreSQL and Redis ---------------------------------------------------
# --internal: the containers reach each other and nothing else.
docker network create --internal "$net" >/dev/null

docker run -d --name "$pg" --network "$net" --network-alias postgres \
  -e POSTGRES_DB=netbox -e POSTGRES_USER=netbox -e POSTGRES_PASSWORD=netbox \
  "$postgres_image" >/dev/null
docker run -d --name "$redis" --network "$net" --network-alias redis \
  "$redis_image" >/dev/null

# Over TCP on purpose: while the image initialises the database it runs a
# temporary server that answers on the socket only, then restarts.
for _ in $(seq 60); do
  if docker exec "$pg" pg_isready -q -h 127.0.0.1 -U netbox -d netbox \
     && docker exec "$redis" redis-cli ping 2>/dev/null | grep -q PONG; then
    break
  fi
  sleep 2
done
docker exec "$pg" pg_isready -h 127.0.0.1 -U netbox -d netbox
docker exec "$redis" redis-cli ping

{
  echo "### Plugin test suites"
  echo
  echo "Image \`$(docker image inspect --format '{{.Id}}' "$IMAGE")\`, $(docker exec "$pg" postgres --version), one plugin on at a time, tests run serially."
  echo
} > "$summary"

# --- one suite ----------------------------------------------------------------
run_suite() {
  local package=$1 version=$2 repo=$3 commit=$4 module=$5
  local src="$work/$module-src" installed="$work/$module-installed" log="$work/$module.log"
  local declared pkgdir cid skip_lines='' entry s_module s_id s_reason rc line counts
  local suite_failed=0

  echo "::group::$package $version: tests from $repo@${commit:0:12}"

  mkdir -p "$src"
  curl -fsSL --retry 3 --retry-all-errors "https://github.com/$repo/archive/$commit.tar.gz" \
    | tar -xz -C "$src" --strip-components=1

  declared=$(grep -m1 -oP '^version\s*=\s*"\K[^"]+' "$src/pyproject.toml" || true)
  if [ "$declared" != "$version" ]; then
    fail "$repo@$commit declares version '${declared}', not $version: that commit is not the pinned release"
    suite_failed=1
  fi

  # find_spec on a top-level name does not import it, so this needs no settings.
  pkgdir=$(docker run --rm "$IMAGE" python -c \
    "import importlib.util; print(importlib.util.find_spec('$module').submodule_search_locations[0])")

  for entry in "${SKIPS[@]}"; do
    IFS='|' read -r s_module s_id s_reason <<< "$entry"
    if [ "$s_module" = "$module" ]; then
      skip_lines+="${s_id}|${s_reason}"$'\n'
    fi
  done

  # UPDATE_QUERY_COUNTS: NetBox's test helpers compare the number of queries
  # per page with a baseline recorded on NetBox main, and on another NetBox
  # some differ for reasons that are not the plugin's. Recorded instead of
  # compared, as netbox-security's own workflow does; the differences are
  # printed below. That mode refuses --parallel, hence one test at a time.
  cid=$(docker create --network "$net" \
    -e NETBOX_CONFIGURATION=netbox.configuration_testing \
    -e DB_HOST=postgres -e REDIS_HOST=redis \
    -e PLUGIN_UNDER_TEST="$module" \
    -e UPDATE_QUERY_COUNTS=1 \
    -e SKIP_TESTS="$skip_lines" \
    -v "$here/testing_configuration.py:/opt/netbox/netbox/netbox/configuration_testing.py:ro" \
    "$IMAGE" \
    python manage.py test "$module.tests" --no-input --verbosity 2 \
      --testrunner netbox.configuration_testing.SkippingRunner)
  containers+=("$cid")

  # The installed package against the checkout, before the tests are added.
  docker cp "$cid:$pkgdir" "$installed" >/dev/null
  local n=0 differ=0 f rel
  while IFS= read -r -d '' f; do
    rel=${f#"$installed/"}
    n=$((n + 1))
    if ! cmp -s "$f" "$src/$module/$rel"; then
      echo "  installed $module/$rel is not the file at $commit"
      differ=$((differ + 1))
    fi
  done < <(find "$installed" -type f -name '*.py' -print0)
  if [ "$n" -eq 0 ] || [ "$differ" -ne 0 ]; then
    fail "$package $version as installed is not $repo@$commit: $differ of $n .py files differ"
    suite_failed=1
  else
    echo "installed $package $version is $repo@${commit:0:12}: all $n .py files identical"
  fi

  # Only the tests directory goes in. The query-count file starts empty, so
  # what comes back out is exactly what this run recorded.
  docker cp "$src/$module/tests" "$cid:$pkgdir/" >/dev/null
  echo '{}' > "$work/empty.json"
  docker cp "$work/empty.json" "$cid:$pkgdir/tests/query_counts.json" >/dev/null

  docker exec "$redis" redis-cli flushall >/dev/null

  set +e
  docker start -a "$cid" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e
  echo "::endgroup::"

  line=$(grep -m1 '^ci: ran=' "$log" || true)
  if [ -z "$line" ]; then
    fail "$package: the suite did not get as far as a result (exit $rc)"
    suite_failed=1
  elif [ "$rc" -ne 0 ]; then
    fail "$package: suite failed (exit $rc): ${line#ci: }"
    suite_failed=1
  fi

  [ -f "$src/$module/tests/query_counts.json" ] || echo '{}' > "$src/$module/tests/query_counts.json"
  docker cp "$cid:$pkgdir/tests/query_counts.json" "$work/$module-recorded.json" >/dev/null 2>&1 \
    || echo '{}' > "$work/$module-recorded.json"
  counts=$(jq -rn \
    --slurpfile base "$src/$module/tests/query_counts.json" \
    --slurpfile here "$work/$module-recorded.json" '
      $base[0] as $b | $here[0] as $h
      | [$h | to_entries[] | select($b[.key] != null and $b[.key] != .value)
           | "- `\(.key)`: \($b[.key]) at the release, \(.value) here"] as $changed
      | [$h | keys[] | select($b[.] == null) | "- `\(.)`: recorded here, no baseline at the release"] as $new
      | [$b | keys[] | select($h[.] == null) | "- `\(.)`: in the baseline, not recorded by this run"] as $unrun
      | "Query counts recorded: \($h | length). Different from the baseline shipped with the release: \($changed | length). Without a baseline: \($new | length). In the baseline, not recorded: \($unrun | length).",
        $changed[], $new[], $unrun[]')

  {
    echo "#### $package $version"
    echo
    echo "Tests from [$repo@${commit:0:12}](https://github.com/$repo/tree/$commit), $n installed .py files compared with that commit, $differ different."
    echo
    if [ "$suite_failed" -eq 0 ]; then echo "**Passed.** ${line#ci: }"; else echo "**FAILED.** ${line:+${line#ci: }}"; fi
    echo
    # shellcheck disable=SC2016  # the backticks are markdown, not a command
    grep -E '^ci: (failed|error) ' "$log" | sed -E 's/^ci: (failed|error) (.*)$/- \1: `\2`/' || true
    if grep -q '^ci: skipped ' "$log"; then
      echo
      echo "Skipped:"
      echo
      # Ours are marked: they are the ones that need approving by name.
      grep '^ci: skipped ' "$log" | while IFS= read -r line; do
        s_id=${line#ci: skipped }; s_reason=${s_id#*: }; s_id=${s_id%%: *}
        if printf '%s' "$skip_lines" | grep -qF "${s_id}|"; then
          echo "- \`$s_id\`: $s_reason — **skipped by ci-plugin-tests.sh**"
        else
          echo "- \`$s_id\`: $s_reason — skipped by the suite itself"
        fi
      done
    else
      echo "No test was skipped."
    fi
    echo
    echo "$counts"
    echo
  } >> "$summary"

  [ "$suite_failed" -eq 0 ] || failed=1
}

for suite in "${SUITES[@]}"; do
  IFS='|' read -r package version repo commit module <<< "$suite"
  run_suite "$package" "$version" "$repo" "$commit" "$module"
done

{
  echo "#### No suite"
  echo
  for entry in "${NO_SUITE[@]}"; do
    echo "- ${entry%%|*} ${pinned[${entry%%|*}]}: ${entry#*|}"
  done
} >> "$summary"

cat "$summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$summary" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$failed" -ne 0 ]; then
  echo "::error::plugin test suites failed in $IMAGE — nothing may be pushed"
  exit 1
fi
echo "plugin test suites passed in $IMAGE"
