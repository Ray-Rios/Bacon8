#!/bin/sh
# Bacon World's JS unit tests: bundle each *.test.ts with the hub's esbuild and
# run it with `node --test`. The hub has no JS test runner. Run inside a
# throwaway node:20 container where assets/node_modules exists, e.g. the
# image's assets-builder stage:
#
#   docker run --rm -v "$PWD/plugins:/app/plugins:ro" -w /app/assets <assets image> \
#     sh /app/plugins/bacon_world/assets/js/__tests__/run.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d)
for t in "$here"/*.test.ts; do
  npx --no-install esbuild "$t" --bundle --platform=node --format=esm --log-level=warning \
    --outfile="$out/$(basename "$t" .ts).mjs"
done
node --test "$out"/*.mjs
