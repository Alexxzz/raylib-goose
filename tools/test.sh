#!/bin/sh
# Runs every check this repository has. Needs a goose compiler, a C compiler,
# raylib's source (for raylib.h and raymath.h) and its shared library.
#
#   RAYLIB_SRC=~/raylib/src GOOSE=goose tools/test.sh
#
# The smoke test opens a window: on a machine without a display, run this
# under xvfb-run. Put the directory holding libraylib.so on LD_LIBRARY_PATH
# (DYLD_LIBRARY_PATH on macOS) if it is not installed system-wide.
set -e
cd "$(dirname "$0")/.."
GOOSE=${GOOSE:-goose}
CC=${CC:-cc}
: "${RAYLIB_SRC:?set RAYLIB_SRC to raylib's src directory}"

echo "== rl.goose is up to date with tools/gen_bindings.py"
python3 tools/gen_bindings.py tools/raylib_api.json /tmp/rl_goose_check.$$ > /dev/null
cmp rl.goose /tmp/rl_goose_check.$$ || { echo "rl.goose is stale: run python3 tools/gen_bindings.py"; exit 1; }
rm -f /tmp/rl_goose_check.$$

echo "== struct layouts against raylib.h"
python3 tools/check_layout.py "$RAYLIB_SRC" "$CC"

echo "== raymath.goose against raymath.h"
python3 tools/raymath_check.py "$RAYLIB_SRC" "$GOOSE" "$CC"

echo "== examples typecheck"
for f in examples/*.goose; do
    "$GOOSE" check -q "$f"
done

echo "== smoke test"
"$GOOSE" run -q test/smoke.goose
