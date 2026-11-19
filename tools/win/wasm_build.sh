#!/bin/sh
# box3d.wasm in the wasi-sdk image (the same flags as plugins/bacon_world/native/box3d/build.sh).
set -e
echo "CC=$CC"; ls /opt 2>/dev/null
CLANG=/opt/wasi-sdk/bin/clang
[ -x "$CLANG" ] || CLANG=clang
$CLANG --version | head -1
mkdir -p /o
for f in /box3d/Private/box3d_src/*.c /src/bw_box3d.c; do
  $CLANG --target=wasm32-wasip1 -O3 -std=c17 -DNDEBUG -msimd128 -I/box3d/Public -I/box3d/Private/box3d_src -c "$f" -o "/o/$(basename "$f" .c).o"
done
$CLANG --target=wasm32-wasip1 -mexec-model=reactor -O3 /o/*.o -o /out/box3d.wasm \
  -Wl,--strip-all -Wl,-z,stack-size=1048576 -Wl,--initial-memory=16777216
ls -l /out/box3d.wasm
