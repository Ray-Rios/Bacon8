#!/usr/bin/env python3
"""Build every derived brand file from a handful of master images.

    brand/bacon8-mark.png     1024x1024 PNG, the Bacon8 mark (transparent corners OK)
    brand/bacon8-mark.svg     the same mark as SVG (favicon for modern browsers, Start button)
    brand/og-image.png        1200x630 PNG, the card shown when a bacon8.net link is shared
    brand/brand.json          name, description and colours (web manifest, icon backgrounds)

and, when the game repository is checked out beside this one (./RaysSpaceSim):

    RaysSpaceSim/Brand/game-icon.png   1024x1024 PNG, the game's icon
    RaysSpaceSim/Brand/splash.png      the startup splash, 720x370 recommended

Writes:
    priv/static/favicon.ico, priv/static/site.webmanifest,
    priv/static/images/{logo-mark.svg, apple-touch-icon.png, icon-192.png, icon-512.png,
                        icon-maskable-512.png, og-image.png}
    RaysSpaceSim/Build/Windows/Application.ico   (game exe icon; picked up at build time)
    RaysSpaceSim/Launcher/app.ico                (launcher exe and window icon)
    RaysSpaceSim/Content/Splash/Splash.bmp       (packaged game's startup splash)
    RaysSpaceSim/Content/Splash/EdSplash.bmp     (editor splash; the editor draws its own
                                                  text over the bottom ~70 px)

Needs Pillow only. Nothing is built on the development PC, so run it in a
throwaway container from the repository root:

    docker run --rm -v "$(pwd -W):/work" -w /work python:3.12-slim \
      sh -c "pip install -q pillow && python scripts/brand/build_brand_assets.py"

Then commit the outputs (both repositories) and rebuild what uses them:
deploy-prod.sh for the site, the game and launcher build for the rest.
"""
import json
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / "brand"
STATIC = ROOT / "priv" / "static"
GAME = ROOT / "RaysSpaceSim"

WIN_ICON_SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]


def rgb(hex_colour):
    h = hex_colour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def load_square(path, minimum=512):
    im = Image.open(path).convert("RGBA")
    if im.width != im.height:
        sys.exit(f"{path}: must be square, is {im.width}x{im.height}")
    if im.width < minimum:
        sys.exit(f"{path}: needs at least {minimum}x{minimum}, is {im.width}x{im.height}")
    return im


def sized(im, px):
    return im.resize((px, px), Image.LANCZOS)


def on_background(im, px, colour, scale=1.0):
    """Opaque square: the image (scaled) centred on a solid colour."""
    canvas = Image.new("RGBA", (px, px), rgb(colour) + (255,))
    inner = sized(im, round(px * scale))
    off = (px - inner.width) // 2
    canvas.alpha_composite(inner, (off, off))
    return canvas


def write_ico(im, path, sizes):
    path.parent.mkdir(parents=True, exist_ok=True)
    # BMP entries: the Windows resource compiler and every Windows version read them.
    sized(im, max(sizes)).save(path, format="ICO", sizes=[(s, s) for s in sizes], bitmap_format="bmp")
    print("wrote", path.relative_to(ROOT))


def write_png(im, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, optimize=True)
    print("wrote", path.relative_to(ROOT))


def write_bmp24(im, path, background=(0, 0, 0)):
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = Image.new("RGB", im.size, background)
    flat.paste(im.convert("RGBA"), (0, 0), im.convert("RGBA"))
    flat.save(path, format="BMP")  # 24-bit, what the Windows splash loader expects
    print("wrote", path.relative_to(ROOT))


def build_hub():
    meta = json.loads((BRAND / "brand.json").read_text(encoding="utf-8"))
    mark = load_square(BRAND / "bacon8-mark.png")
    images = STATIC / "images"

    write_ico(mark, STATIC / "favicon.ico", [16, 32, 48])
    images.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(BRAND / "bacon8-mark.svg", images / "logo-mark.svg")
    print("wrote", (images / "logo-mark.svg").relative_to(ROOT))
    # Apple draws its own rounded corners and wants no transparency.
    write_png(on_background(mark, 180, meta["mark_color"]), images / "apple-touch-icon.png")
    write_png(sized(mark, 192), images / "icon-192.png")
    write_png(sized(mark, 512), images / "icon-512.png")
    # Maskable: the platform crops to its own shape, so keep the mark inside the 80% safe zone.
    write_png(on_background(mark, 512, meta["mark_color"], scale=0.8), images / "icon-maskable-512.png")

    og = Image.open(BRAND / "og-image.png").convert("RGB")
    if og.size != (1200, 630):
        sys.exit(f"brand/og-image.png must be 1200x630, is {og.width}x{og.height}")
    write_png(og, images / "og-image.png")

    manifest = {
        "name": meta["name"],
        "short_name": meta.get("short_name", meta["name"]),
        "description": meta.get("description", ""),
        "start_url": "/",
        "display": "standalone",
        "background_color": meta["background_color"],
        "theme_color": meta["theme_color"],
        "icons": [
            {"src": "/images/icon-192.png", "sizes": "192x192", "type": "image/png"},
            {"src": "/images/icon-512.png", "sizes": "512x512", "type": "image/png"},
            {"src": "/images/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
        ],
    }
    (STATIC / "site.webmanifest").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("wrote", (STATIC / "site.webmanifest").relative_to(ROOT))


def build_game():
    src = GAME / "Brand"
    if not (src / "game-icon.png").exists():
        print("no RaysSpaceSim/Brand/game-icon.png - skipping the game")
        return
    icon = load_square(src / "game-icon.png", minimum=256)
    write_ico(icon, GAME / "Build" / "Windows" / "Application.ico", WIN_ICON_SIZES)
    write_ico(icon, GAME / "Launcher" / "app.ico", WIN_ICON_SIZES)
    splash_src = src / "splash.png"
    if splash_src.exists():
        splash = Image.open(splash_src)
        write_bmp24(splash, GAME / "Content" / "Splash" / "Splash.bmp")
        write_bmp24(splash, GAME / "Content" / "Splash" / "EdSplash.bmp")


if __name__ == "__main__":
    build_hub()
    build_game()
