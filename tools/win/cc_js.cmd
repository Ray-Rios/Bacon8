@echo off
call "%~dp0paths.cmd"
set LOG=C:\Bacon8\tmp\cc_js.log
cd /d C:\Bacon8
echo start %time% > %LOG%
docker run --rm -v "C:\Bacon8:/app:ro" -v bacon8_js_nm:/nm -w /nm node:20 sh -c "cp /app/assets/package.json /app/assets/package-lock.json /nm/ 2>/dev/null; (npm ci --no-audit --no-fund >/dev/null 2>&1 || npm install --no-audit --no-fund >/dev/null 2>&1); mkdir -p /node_modules && cp -r /nm/node_modules/. /node_modules/ && out=$(mktemp -d) && for t in /app/plugins/bacon_world/assets/js/__tests__/%1*.test.ts; do /node_modules/.bin/esbuild $t --bundle --platform=node --format=esm --log-level=warning --outfile=$out/$(basename $t .ts).mjs || exit 3; done && cd /app && node --test $out/*.mjs" >> %LOG% 2>&1
echo EXIT %errorlevel% >> %LOG%
echo ALLDONE %time% >> %LOG%
