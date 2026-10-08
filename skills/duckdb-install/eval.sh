#!/usr/bin/env bash
# End-to-end evaluations for the duckdb-install skill.
# Runs the skill via `claude --print` and verifies extensions are actually loadable.
#
# Prerequisites: claude CLI in PATH (authenticated) and the duckdb Python package.
#
# Usage:
#   bash skills/duckdb-install/eval.sh
#   PLUGIN_DIR=/other/path bash skills/duckdb-install/eval.sh

PLUGIN_DIR="${PLUGIN_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
PASS=0
FAIL=0
TIMINGS=()

# ---------------------------------------------------------------------------
if ! command -v claude &>/dev/null; then
    echo "ERROR: 'claude' CLI not found. Install Claude Code to run evals."
    exit 1
fi
if ! python -c "import duckdb" &>/dev/null; then
    echo "ERROR: 'duckdb' Python package not found. Run: python -m pip install duckdb"
    exit 1
fi

# ---------------------------------------------------------------------------
# Run the skill and check that the listed extensions are loadable afterwards.
eval_case() {
    local desc="$1"; shift
    local args="$1"; shift
    local exts=("$@")   # extensions to verify via LOAD

    printf "  %-56s " "$desc"
    local t0 t1 elapsed result
    t0=$(date +%s)
    result=$(printf 'duckdb-install %s' "$args" \
        | claude --print --plugin-dir "$PLUGIN_DIR" 2>/dev/null)
    t1=$(date +%s)
    elapsed=$((t1 - t0))
    TIMINGS+=("$elapsed")

    # Verify each extension is loadable
    local ok=true
    for ext in "${exts[@]}"; do
        if ! python -c "import duckdb; duckdb.connect(':memory:').execute('LOAD ${ext};')" &>/dev/null; then
            ok=false
            echo "FAIL  (${elapsed}s) — LOAD ${ext} failed after install"
            echo "        skill output: ${result:0:300}"
            ((FAIL++))
            return
        fi
    done

    if $ok; then
        echo "PASS  (${elapsed}s)"
        ((PASS++))
    fi
}

# ---------------------------------------------------------------------------
echo "=== install-duckdb skill eval ==="
echo "Plugin dir: $PLUGIN_DIR"
echo ""

echo "--- Single extension (core) ---"
eval_case "Install httpfs"              "httpfs"                    httpfs
eval_case "Install json"               "json"                      json

echo ""
echo "--- Extension with @repo ---"
eval_case "Install magic@community"    "magic@community"           magic

echo ""
echo "--- Multiple extensions ---"
eval_case "Install spatial + httpfs"   "spatial httpfs"            spatial httpfs
eval_case "Install spatial + magic"    "spatial magic@community"   spatial magic

echo ""
echo "--- Update mode ---"
eval_case "Update all extensions"      "--update"                  # no LOAD check needed
eval_case "Update specific extension"  "--update httpfs"           # no LOAD check needed

echo ""
echo "--- Version check (included in --update output) ---"
# Just verify the skill runs and mentions a version number
printf "  %-56s " "Version info present in --update output"
t0=$(date +%s)
out=$(printf 'duckdb-install --update' \
    | claude --print --plugin-dir "$PLUGIN_DIR" 2>/dev/null)
t1=$(date +%s)
elapsed=$((t1 - t0))
TIMINGS+=("$elapsed")
if echo "$out" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "PASS  (${elapsed}s)"
    ((PASS++))
else
    echo "FAIL  (${elapsed}s) — no version number in output"
    echo "        got: ${out:0:300}"
    ((FAIL++))
fi

# ---------------------------------------------------------------------------
echo ""
total=0
for t in "${TIMINGS[@]}"; do total=$((total + t)); done
count=${#TIMINGS[@]}
avg=$(( count > 0 ? total / count : 0 ))

echo "=================================="
echo "Results : $PASS passed, $FAIL failed"
echo "Timing  : total ${total}s, avg ${avg}s per case"
[ "$FAIL" -eq 0 ]
