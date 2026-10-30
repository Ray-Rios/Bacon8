# Brand masters

Every logo, icon and splash the hub and the game use is generated from the few
master files here, so new artwork is a drop-in: replace a master, run the build
script, commit what it writes.

| Master | Size | Used for |
|---|---|---|
| `bacon8-mark.png` | 1024x1024 PNG, square, transparent corners allowed | favicon.ico, app icons, web manifest icons |
| `bacon8-mark.svg` | square SVG, no external fonts (outlines only, or an embedded PNG) | browser tab icon (modern browsers) |

Since 2026-10-26 the mark is **two strips of bacon** (BACON8.md, decisions log). Both masters are written
by `library/pipeline/scripts/bacon_sheets.py` from the Blender render (`bacon_strips.py`), along with the
animated icon's sprite sheets; the desktop's Start button and the navbar's Games link use the animated
`<b8-bacon>`, not these files. To change the bacon, re-render and rerun `bacon_sheets.py`, then this build.
| `og-image.png` | 1200x630 PNG | preview card when a link to the site is shared |
| `brand.json` | | site name, one-line description, colours |
| `../plugins/rays_space_sim/unreal/Brand/game-icon.png` | 1024x1024 PNG | game exe icon, launcher icon (in the game repository) |
| `../plugins/rays_space_sim/unreal/Brand/splash.png` | 720x370 PNG (keep the bottom 70 px plain) | game startup splash, editor splash |

Build (in a throwaway container, from the repository root):

```sh
docker run --rm -v "$(pwd -W):/work" -w /work python:3.12-slim \
  sh -c "pip install -q pillow && python scripts/brand/build_brand_assets.py"
```

The Bacon8 logo is the "B8" monogram set in Inter Display Black (SIL Open Font
License): cream `#E7F1FD` on blue `#247DF1`, shown on near-black `#14100F`
(decided 2026-10-20). The game's icon is an "RSS" mark over a ringed planet.
