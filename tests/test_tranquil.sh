#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/tranquil-test.XXXXXXXX")
test_dir=$(cd "$test_dir" && pwd -P)
trap 'rm -rf "$test_dir"' EXIT

base_bin="$test_dir/base-bin"
module_bin="$test_dir/module-bin"
mkdir -p "$base_bin" "$module_bin"

for cmd in awk basename bash cat date dirname find grep groups head ls mkdir mv readlink sed sort tee tr uniq wc whoami; do
  ln -s "$(command -v "$cmd")" "$base_bin/$cmd"
done

cat > "$base_bin/dos2unix" <<'EOF'
#!/usr/bin/env bash
cat
EOF
cat > "$base_bin/pinky" <<'EOF'
#!/usr/bin/env bash
echo "In real life: Test User"
EOF
cat > "$base_bin/sbatch" <<'EOF'
#!/usr/bin/env bash
echo "sbatch:$*" >> "$TEST_EVENTS"
EOF
cat > "$base_bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl:$*" >> "$TEST_EVENTS"
if [ "${STUB_CURL_FAIL:-0}" = "1" ]; then
  echo "Simulated download failure" >&2
  exit 22
fi
if [ "${STUB_CURL_EMPTY:-0}" = "1" ]; then
  exit 0
fi
cat <<'SCRIPT'
echo "stats:$1" >> "$TEST_EVENTS"
echo "stub cluster summary"
exit "${STUB_STATS_STATUS:-0}"
SCRIPT
EOF
cat > "$module_bin/snakemake" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" --dry-run "*) mode=dryrun; status=${STUB_DRYRUN_STATUS:-0} ;;
  *" --unlock "*) mode=unlock; status=0 ;;
  *" --report "*) mode=report; status=${STUB_REPORT_STATUS:-0} ;;
  *) mode=run; status=${STUB_RUN_STATUS:-0} ;;
esac
echo "snakemake:$mode" >> "$TEST_EVENTS"
echo "stub snakemake $mode"
exit "$status"
EOF
chmod +x "$base_bin/dos2unix" "$base_bin/pinky" "$base_bin/sbatch" "$base_bin/curl" "$module_bin/snakemake"

export TEST_EVENTS="$test_dir/events"
export TEST_BASE_PATH="$base_bin"
export TEST_MODULE_BIN="$module_bin"

module() {
  echo "module:$*" >> "$TEST_EVENTS"
  case "${1:-} ${2:-}" in
    "purge ")
      if [ "${STUB_PURGE_KEEPS_SNAKEMAKE:-0}" = "1" ]; then
        export PATH="$TEST_MODULE_BIN:$TEST_BASE_PATH"
      else
        export PATH="$TEST_BASE_PATH"
      fi
      ;;
    "load snakemake/5.24.1")
      if [ "${STUB_MODULE_FAIL:-0}" = "1" ]; then
        return 1
      fi
      if [ "${STUB_MODULE_MISSING:-0}" != "1" ]; then
        export PATH="$TEST_MODULE_BIN:$PATH"
      fi
      ;;
  esac
}
export -f module

make_workdir() {
  local workdir="$test_dir/$1"
  mkdir -p "$workdir/logs" "$workdir/stats" "$workdir/resources"
  printf 'workdir: "%s"\n' "$workdir" > "$workdir/config.yaml"
  printf 'sampleName\treplicateNumber\tpath_to_R1_fastq\n' > "$workdir/samples.tsv"
  printf 'group1\tgroup2\n' > "$workdir/contrasts.tsv"
  echo "$workdir"
}

assert_contains() {
  if ! grep -Fq -- "$2" "$1"; then
    echo "Expected '$2' in $1" >&2
    cat "$1" >&2
    exit 1
  fi
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    echo "Unexpected '$2' in $1" >&2
    cat "$1" >&2
    exit 1
  fi
}

assert_status() {
  local expected=$1
  local actual=0
  shift
  "$@" > "$test_dir/output" 2>&1 || actual=$?
  if [ "$actual" -ne "$expected" ]; then
    echo "Expected exit $expected, got $actual: $*" >&2
    cat "$test_dir/output" >&2
    exit 1
  fi
}

cd "$repo_dir"
workdir=$(make_workdir dryrun)
: > "$TEST_EVENTS"
assert_status 0 env HOSTNAME=fsitgl-head01p.ncifcrf.gov PATH="$TEST_BASE_PATH" \
  bash ./tranquil -m=dryrun -w="$workdir"
assert_contains "$TEST_EVENTS" "module:load snakemake/5.24.1"
assert_contains "$TEST_EVENTS" "snakemake:dryrun"
assert_contains "$workdir/dryrun.log" "stub snakemake dryrun"

workdir=$(make_workdir unlock)
: > "$TEST_EVENTS"
assert_status 0 env HOSTNAME=fsitgl-head01p.ncifcrf.gov PATH="$TEST_BASE_PATH" \
  bash ./tranquil -m=unlock -w="$workdir"
assert_contains "$TEST_EVENTS" "module:load snakemake/5.24.1"
assert_contains "$TEST_EVENTS" "snakemake:unlock"

workdir=$(make_workdir biowulf-dryrun)
: > "$TEST_EVENTS"
assert_status 0 env HOSTNAME=biowulf.nih.gov PATH="$TEST_BASE_PATH" \
  bash ./tranquil -m=dryrun -w="$workdir"
assert_contains "$TEST_EVENTS" "module:load python/3.7"
assert_contains "$TEST_EVENTS" "module:load snakemake/5.24.1"
assert_contains "$TEST_EVENTS" "snakemake:dryrun"

workdir=$(make_workdir module-failure)
: > "$TEST_EVENTS"
assert_status 1 env HOSTNAME=fsitgl-head01p.ncifcrf.gov PATH="$TEST_BASE_PATH" \
  STUB_MODULE_FAIL=1 STUB_PURGE_KEEPS_SNAKEMAKE=1 bash ./tranquil -m=dryrun -w="$workdir"
assert_contains "$test_dir/output" "Failed to load snakemake/5.24.1"
assert_not_contains "$TEST_EVENTS" "snakemake:dryrun"

workdir=$(make_workdir executable-missing)
: > "$TEST_EVENTS"
assert_status 1 env HOSTNAME=fsitgl-head01p.ncifcrf.gov PATH="$TEST_BASE_PATH" \
  STUB_MODULE_MISSING=1 bash ./tranquil -m=dryrun -w="$workdir"
assert_contains "$test_dir/output" "Executable 'snakemake' not found in PATH"
assert_not_contains "$TEST_EVENTS" "snakemake:dryrun"

workdir=$(make_workdir dryrun-failure)
: > "$TEST_EVENTS"
assert_status 23 env HOSTNAME=fsitgl-head01p.ncifcrf.gov PATH="$TEST_BASE_PATH" \
  STUB_DRYRUN_STATUS=23 bash ./tranquil -m=dryrun -w="$workdir"
assert_contains "$test_dir/output" "stub snakemake dryrun"

workdir=$(make_workdir runlocal)
: > "$TEST_EVENTS"
assert_status 0 env HOSTNAME=fsitgl-head01p.ncifcrf.gov PATH="$TEST_BASE_PATH" \
  SLURM_JOB_ID=123 bash ./tranquil -m=runlocal -w="$workdir"
assert_contains "$TEST_EVENTS" "module:load snakemake/5.24.1"
assert_contains "$TEST_EVENTS" "snakemake:run"
assert_contains "$TEST_EVENTS" "snakemake:report"

workdir=$(make_workdir slurm)
: > "$TEST_EVENTS"
assert_status 0 env HOSTNAME=fsitgl-head01p.ncifcrf.gov PATH="$TEST_BASE_PATH" \
  bash ./tranquil -m=run -w="$workdir"
assert_contains "$TEST_EVENTS" "sbatch:"
job_script="$workdir/submit_script.sbatch"
bash -n "$job_script"

: > "$TEST_EVENTS"
assert_status 0 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" bash "$job_script"
assert_contains "$TEST_EVENTS" "module:load snakemake/5.24.1"
assert_contains "$TEST_EVENTS" "snakemake:run"
assert_contains "$TEST_EVENTS" "snakemake:report"
assert_contains "$TEST_EVENTS" "CCBR/Tools/34bd72aaaf7e2c4881c4d46fa6e0bd0a11b1a3fd/scripts/gather_cluster_stats.sh"
assert_contains "$TEST_EVENTS" "stats:$workdir/snakemake.log"
assert_contains "$workdir/snakemake.log.HPC_summary.txt" "stub cluster summary"

: > "$TEST_EVENTS"
assert_status 1 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  STUB_MODULE_FAIL=1 bash "$job_script"
assert_contains "$test_dir/output" "Failed to load snakemake/5.24.1"
assert_not_contains "$TEST_EVENTS" "snakemake:"

: > "$TEST_EVENTS"
assert_status 1 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  STUB_MODULE_MISSING=1 bash "$job_script"
assert_contains "$test_dir/output" "snakemake not found in PATH"
assert_not_contains "$TEST_EVENTS" "snakemake:"

: > "$TEST_EVENTS"
assert_status 23 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  STUB_RUN_STATUS=23 bash "$job_script"
assert_contains "$TEST_EVENTS" "snakemake:run"
assert_not_contains "$TEST_EVENTS" "snakemake:report"
assert_contains "$TEST_EVENTS" "stats:$workdir/snakemake.log"

: > "$TEST_EVENTS"
assert_status 24 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  STUB_REPORT_STATUS=24 bash "$job_script"
assert_contains "$TEST_EVENTS" "snakemake:report"
assert_contains "$TEST_EVENTS" "stats:$workdir/snakemake.log"

: > "$TEST_EVENTS"
assert_status 0 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  STUB_CURL_FAIL=1 bash "$job_script"
assert_contains "$test_dir/output" "WARNING: Failed to download cluster statistics helper"
assert_not_contains "$TEST_EVENTS" "stats:"

: > "$TEST_EVENTS"
assert_status 0 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  STUB_CURL_EMPTY=1 bash "$job_script"
assert_contains "$test_dir/output" "WARNING: Failed to generate cluster statistics"
assert_not_contains "$TEST_EVENTS" "stats:"

: > "$TEST_EVENTS"
assert_status 23 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  STUB_RUN_STATUS=23 STUB_STATS_STATUS=1 bash "$job_script"
assert_contains "$test_dir/output" "WARNING: Failed to generate cluster statistics"
assert_contains "$TEST_EVENTS" "stats:$workdir/snakemake.log"

workdir=$(make_workdir biowulf-slurm)
: > "$TEST_EVENTS"
assert_status 0 env HOSTNAME=biowulf.nih.gov PATH="$TEST_BASE_PATH" \
  bash ./tranquil -m=run -w="$workdir"
: > "$TEST_EVENTS"
assert_status 0 env PATH="$TEST_BASE_PATH" SLURM_SUBMIT_DIR="$workdir" \
  bash "$workdir/submit_script.sbatch"
assert_contains "$TEST_EVENTS" "module:load python/3.7"
assert_contains "$TEST_EVENTS" "module:load snakemake/5.24.1"
assert_contains "$TEST_EVENTS" "snakemake:run"

echo "TRANQUIL wrapper regression tests passed"
