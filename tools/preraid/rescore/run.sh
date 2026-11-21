#!/usr/bin/env bash
# Pre-raid re-score: one command. Usage (from anywhere):
#   bash tools/preraid/rescore/run.sh                 # model from this repo (HunterGearAdvisor)
#   HGA_ADDON=/c/Users/Admin/WowProjects/HunterGearAdvisor-wowsims bash tools/preraid/rescore/run.sh   # another checkout
# Rebuilds out/cands_all.json + out/items.lua only when an input in ../data or a script is newer; then runs both
# scorings in parallel (~30 min in raid mode): out/out.txt (addon conventions) and out/out_nocreature.txt (+AP vs creature
# = 0; in raid mode the same, the untyped AP counts 0 against the dragonkin boss).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LUA="${LUA:-C:/Users/Admin/AppData/Local/Programs/Lua/bin/lua}"
cd "$HERE"; mkdir -p out
if [ ! -f out/items.lua ] || [ -n "$(find ../data avail.py convert.py -newer out/items.lua -type f | head -1)" ]; then
  echo "rebuilding candidates + items"; python avail.py && python convert.py
else
  echo "candidates + items up to date (out/items.lua)"
fi
"$LUA" rescore.lua > out/out.txt 2>&1 & a=$!
"$LUA" rescore.lua nocreature > out/out_nocreature.txt 2>&1 & b=$!
wait $a; ea=$?; wait $b; eb=$?
echo "out/out.txt exit $ea, out/out_nocreature.txt exit $eb"; exit $(( ea | eb ))
