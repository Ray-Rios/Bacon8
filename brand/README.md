# Brand masters

Every logo, icon and splash the hub and the game use is generated from the few
master files here, so new artwork is a drop-in: replace a master, run the build
script, commit what it writes.

| Master | Size | Used for |
|---|---|---|
| `bacon8-mark.png` | 1024x1024 PNG, square, transparent corners allowed | favicon.ico, app icons, web manifest icons |
| `bacon8-mark.svg` | square SVG, no external fonts (outlines only) | browser tab icon (modern browsers), desktop Start button |
| `og-image.png` | 1200x630 PNG | preview card when a bacon8.net link is shared |
| `brand.json` | | site name, one-line description, colours |
| `../RaysSpaceSim/Brand/game-icon.png` | 1024x1024 PNG | game exe icon, launcher icon (in the game repository) |
| `../RaysSpaceSim/Brand/splash.png` | 720x370 PNG (keep the bottom 70 px plain) | game startup splash, editor splash |

Build (in a throwaway container, from the repository root):

```sh
docker run --rm -v "$(pwd -W):/work" -w /work python:3.12-slim \
  sh -c "pip install -q pillow && python scripts/brand/build_brand_assets.py"
```

The Bacon8 logo is the "B8" monogram set in Inter Display Black (SIL Open Font
License): cream `#E7F1FD` on blue `#247DF1`, shown on near-black `#14100F`
(decided 2026-10-20). The game's icon is an "RSS" mark over a ringed planet.
