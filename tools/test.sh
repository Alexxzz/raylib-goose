#!/bin/sh
# Runs every check this repository has: the rl bindings and the honk engine.
# Needs a goose compiler, a C compiler,
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
for f in examples/*.goose examples/honk/*.goose; do
    "$GOOSE" check "$f"
done

echo "== smoke test"
"$GOOSE" run test/smoke.goose

echo "== honk engine test"
"$GOOSE" run test/honk_test.goose

echo "== goose_grove, played by the computer through every scene"
repo=$(pwd)
tmp=$(mktemp -d)
(cd "$tmp" && "$GOOSE" run "$repo/examples/honk/goose_grove.goose" -- --autoplay --fast --frames 6000 > game.log 2>&1) \
    || { tail -20 "$tmp/game.log"; exit 1; }
test -f "$tmp/goose_grove_scores.bin" || { echo "the game never reached game over"; exit 1; }
rm -rf "$tmp"
echo "played to game over and saved the score"
