#!/usr/bin/env python3
"""Generate the demo's app icon, three plates of tinted glass in the shape of `askkit.bubbles`, the
symbol its Ask tab and its mark wear, so the icon and the tab can't drift apart.

`scripts/make-demo-symbol.swift --plates` gives the symbol's three bubbles at regular, each filled
out to its stroke's outer edge: one size, each up and to the right of the one in front. They are
scaled together to `STACK_WIDTH` of the 1024 grid and centred on `STACK_CENTRE`. Four outputs:

- `Demo/AskKitDemo/AppIcon.icon/` — the Icon Composer document, `icon.json` included. The plates are
  in Liquid Glass, from the most transparent at the back to the most saturated at the front, so the
  color deepens where they overlap. Each plate is an image of its own with its place and size drawn
  in, and a gradient through `AskSpectrum.aurora`'s five colors runs across the whole stack from
  bottom left to top right, not across each plate, so where plates overlap their colors agree. The
  images are Display P3 PNGs because Icon Composer clamps an SVG's gradients to sRGB and takes only
  two colors in a fill. Behind them lies a pastel field, peach-cream through pink to pale teal (deep
  plum through indigo to deep teal in dark). In the clear and tinted looks, which bring a field of
  their own, the field hides and the plates turn white.
- `Demo/AskKitDemo/Assets.xcassets/AppIcon.solidimagestack/` — visionOS's three layers: the field at
  the back, the two back plates in the middle and the front plate in front, so the plates part in
  parallax, scaled to sit inside the round mask.
- `docs/images/icon.png` and `icon-dark.png` — the icon atop the README, rendered by Icon Composer's
  `ictool` in light and dark.
- `docs/images/social-preview.png` — GitHub's card for the repository: the icon, rendered by
  `ictool`, laid over the tile the card holds, its field and its words left as they are. GitHub
  shows a new card only once it's uploaded in the repository's settings.

The three PNGs under `docs/images/` then go through `oxipng -o max --strip safe` when oxipng is
installed (`brew install oxipng`), which is lossless and keeps their color profile; without it they
stay as written, and the script says it skipped them.

Needs macOS with Xcode (`swift` runs make-demo-symbol.swift, and `ictool` renders the images) and
numpy, shapely and Pillow:

    python3 -m venv tmp/venv && tmp/venv/bin/pip install numpy shapely pillow
    tmp/venv/bin/python scripts/make-demo-icon.py
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from shapely import affinity
from shapely.geometry import MultiPolygon, Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
DEMO = ROOT / "Demo/AskKitDemo"
ICON = DEMO / "AppIcon.icon"
STACK = DEMO / "Assets.xcassets/AppIcon.solidimagestack"
IMAGES = ROOT / "docs/images"
DISPLAY_P3 = Path("/System/Library/ColorSync/Profiles/Display P3.icc")

# `AskSpectrum.aurora` (Sources/AskUI/AskSpectrum.swift) in Display P3: cyan, blue, violet, magenta,
# coral, and where each sits on the stack's gradient, from its bottom left to its top right.
AURORA = ((0.30, 0.86, 1.00), (0.24, 0.48, 1.00), (0.56, 0.36, 1.00), (0.90, 0.32, 0.86), (1.00, 0.50, 0.44))
AURORA_STOPS = (0.0, 0.3, 0.55, 0.8, 1.0)

# The stack's width on the 1024 grid, and where the centre of its bounds sits, a little low, as the
# tail hangs below. Then each plate's opacity, back to front. Each plate is a group of its own, and
# with the field that's Icon Composer's limit of four.
STACK_WIDTH = 760
STACK_CENTRE = (512, 520)
PLATE_OPACITY = (0.25, 0.55, 0.95)
TRANSLUCENCY = 0.5

# The field, sRGB, from its top right corner to its bottom left.
FIELD = {
    "light": (("#fcebd8", 0.0), ("#f7dfdf", 0.5), ("#a8d9e2", 1.0)),
    "dark": (("#2b1a35", 0.0), ("#15112a", 0.55), ("#0e2433", 1.0)),
}

# visionOS draws the stack inside a round mask, so its art is scaled down about the centre, and this
# many plates sit in the middle layer, the rest in front.
STACK_SCALE = 0.86
STACK_BACK = 2

# Where the icon's tile sits on GitHub's 1280 x 640 card: its left edge, top edge and side.
SOCIAL_TILE = (153, 150, 340)


# MARK: - The plates


def bezier(p0, p1, p2, p3, steps: int = 24) -> list[tuple[float, float]]:
    t = np.linspace(0, 1, steps + 1)[1:, None]
    p0, p1, p2, p3 = map(np.array, (p0, p1, p2, p3))
    return [tuple(p) for p in (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3]


def outline(data: str) -> Polygon:
    """One closed outline from make-demo-symbol.swift's path data, which is absolute M, L, Q, C and
    Z, its curves sampled."""
    points: list[tuple[float, float]] = []
    for command, args in re.findall(r"([MLQCZ])([^MLQCZ]*)", data):
        values = [float(v) for v in args.split()]
        pairs = list(zip(values[0::2], values[1::2]))
        if command == "M":
            assert not points, "expected one outline a plate"
            points.append(pairs[0])
        elif command == "L":
            points.append(pairs[0])
        elif command == "Q":
            start, control, end = map(np.array, (points[-1], *pairs))
            t = np.linspace(0, 1, 17)[1:, None]
            points += [tuple(p) for p in (1 - t) ** 2 * start + 2 * (1 - t) * t * control + t ** 2 * end]
        elif command == "C":
            points += bezier(points[-1], *pairs)
    return Polygon(points).buffer(0)


def parts(geom) -> list[Polygon]:
    return list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]


def bubbles() -> list[Polygon]:
    """askkit.bubbles' three bubbles, back to front, scaled together to `STACK_WIDTH` and centred on
    `STACK_CENTRE`."""
    result = subprocess.run(["xcrun", "swift", str(ROOT / "scripts/make-demo-symbol.swift"), "--plates"],
                            check=True, capture_output=True, text=True)
    shapes = [outline(data) for data in json.loads(result.stdout)["plates"]]
    x0, y0, x1, y1 = unary_union(shapes).bounds
    k = STACK_WIDTH / (x1 - x0)
    return [affinity.translate(affinity.scale(shape, k, k, origin=((x0 + x1) / 2, (y0 + y1) / 2)),
                               STACK_CENTRE[0] - (x0 + x1) / 2, STACK_CENTRE[1] - (y0 + y1) / 2)
            for shape in shapes]


def plates(shapes: list[Polygon], scale: float = 1.0) -> list[Polygon]:
    """The plates, back to front, the whole stack scaled by `scale` about the grid's centre."""
    return [affinity.scale(shape, scale, scale, origin=(512, 512)) for shape in shapes]


# MARK: - Drawing


def coverage(geom) -> Image.Image:
    """The geometry's coverage on the 1024 grid, drawn at 4x and averaged down."""
    mask = Image.new("L", (4096, 4096), 0)
    draw = ImageDraw.Draw(mask)
    for polygon in parts(geom):
        draw.polygon([(x * 4, y * 4) for x, y in polygon.exterior.coords], fill=255)
        for hole in polygon.interiors:
            draw.polygon([(x * 4, y * 4) for x, y in hole.coords], fill=0)
    return mask.reduce(4)


def ramp(t: np.ndarray, colors, stops) -> np.ndarray:
    """The colors at each `t`, interpolated between their stops."""
    return np.stack([np.interp(t, stops, [c[i] for c in colors]) for i in range(3)], axis=-1)


def spectrum(geoms: list[Polygon]) -> np.ndarray:
    """Aurora's gradient across the whole grid, in Display P3 values, for the plates together. It
    runs along the diagonal of their hull's bounds, bottom left to top right, and spans the hull
    itself, from its farthest point down and left to its farthest up and right, so the rounded corners
    don't hide the gradient's ends."""
    hull = unary_union(geoms).convex_hull
    x0, y0, x1, y1 = hull.bounds
    direction = np.array([x1 - x0, y0 - y1]) / np.hypot(x1 - x0, y1 - y0)
    along = np.array(hull.exterior.coords) @ direction
    ys, xs = np.mgrid[0:1024, 0:1024] + 0.5
    t = np.clip((xs * direction[0] + ys * direction[1] - along.min()) / (along.max() - along.min()), 0, 1)
    return ramp(t, AURORA, AURORA_STOPS)


def painted(geom, rgb: np.ndarray, alpha: float = 1.0) -> Image.Image:
    """The geometry cut from the colors `rgb`, at `alpha`."""
    image = Image.fromarray(np.round(rgb * 255).astype(np.uint8), "RGB").convert("RGBA")
    image.putalpha(coverage(geom).point(lambda v: round(v * alpha)))
    return image


def hex_rgb(code: str) -> tuple[float, float, float]:
    return tuple(int(code[i:i + 2], 16) / 255 for i in (1, 3, 5))


def field(appearance: str) -> Image.Image:
    """The field, in sRGB values."""
    ys, xs = np.mgrid[0:1024, 0:1024] + 0.5
    colors, stops = zip(*FIELD[appearance])
    rgb = ramp(((1024 - xs) + ys) / 2048, [hex_rgb(c) for c in colors], stops)
    return Image.fromarray(np.round(rgb * 255).astype(np.uint8), "RGB").convert("RGBA")


def field_svg(appearance: str) -> str:
    """The field as Icon Composer draws it, its gradient across the square."""
    def stop(offset, color):
        return f'<stop offset="{offset}" stop-color="{color}" stop-opacity="1.0"/>'
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            '<defs>\n'
            '<linearGradient id="field" x1="1" y1="0" x2="0" y2="1">'
            + "".join(stop(o, c) for c, o in FIELD[appearance]) + '</linearGradient>\n'
            '</defs>\n'
            '<rect width="1024" height="1024" fill="url(#field)"/>\n'
            '</svg>\n')


def save_p3(image: Image.Image, path: Path) -> None:
    image.save(path, optimize=True, icc_profile=DISPLAY_P3.read_bytes())


# MARK: - The icon


def srgb(code: str) -> str:
    return "srgb:" + ",".join(f"{v:.5f}" for v in (*hex_rgb(code), 1.0))


def write_icon(shapes: list[Polygon]) -> None:
    """The Icon Composer document, front to back: a group for each plate, then the field."""
    assets = ICON / "Assets"
    shutil.rmtree(assets, ignore_errors=True)
    assets.mkdir(parents=True)
    geoms = plates(shapes)
    rgb = spectrum(geoms)
    for i, geom in enumerate(geoms):
        save_p3(painted(geom, rgb), assets / f"plate-{i + 1}.png")
    for appearance in FIELD:
        (assets / f"field-{appearance}.svg").write_text(field_svg(appearance))

    def plate_group(i: int) -> dict:
        # The clear and tinted looks draw a layer by its luminance, and aurora's middling one comes out
        # dim, in tinted dark most of all, so there the plates are white. Icon Composer's "tinted"
        # appearance is the clear looks as well as the tinted ones.
        layer = {"fill-specializations": [{"value": "automatic"},
                                          {"appearance": "tinted", "value": {"solid": srgb("#ffffff")}}],
                 "glass": True, "image-name": f"plate-{i + 1}.png", "name": f"Plate {i + 1}",
                 "opacity": PLATE_OPACITY[i], "position": {"scale": 1, "translation-in-points": [0, 0]}}
        return {"layers": [layer], "lighting": "individual", "name": f"Plate {i + 1}",
                "shadow": {"kind": "neutral", "opacity": 0.5}, "specular": True,
                "translucency": {"enabled": True, "value": TRANSLUCENCY}}

    groups = [plate_group(i) for i in reversed(range(len(geoms)))]
    backdrop = {
        "layers": [{"glass": False, "hidden-specializations": [{"value": False}, {"appearance": "tinted", "value": True}],
                    "image-name-specializations": [{"value": "field-light.svg"},
                                                   {"appearance": "dark", "value": "field-dark.svg"}],
                    "name": "Field"}],
        "name": "Field", "shadow": {"kind": "none", "opacity": 0}, "specular": False,
        "translucency": {"enabled": False, "value": 0},
    }

    def ends(appearance: str) -> dict:
        (start, _), *_, (stop, _) = FIELD[appearance]
        return {"linear-gradient": [srgb(start), srgb(stop)],
                "orientation": {"start": {"x": 1, "y": 0}, "stop": {"x": 0, "y": 1}}}

    document = {
        # Under the field, which covers it, the same gradient without its middle stop.
        "fill-specializations": [{"value": ends("light")}, {"appearance": "dark", "value": ends("dark")}],
        "groups": [*groups, backdrop],
        "supported-platforms": {"squares": "shared"},
    }
    (ICON / "icon.json").write_text(json.dumps(document, indent=2) + "\n")


def ictool() -> Path:
    developer = subprocess.run(["xcode-select", "-p"], check=True, capture_output=True, text=True).stdout.strip()
    return Path(developer).parent / "Applications/Icon Composer.app/Contents/Executables/ictool"


def render_readme_icons() -> None:
    for rendition, name in (("Default", "icon.png"), ("Dark", "icon-dark.png")):
        subprocess.run([str(ictool()), str(ICON), "--export-image", "--output-file", str(IMAGES / name),
                        "--platform", "iOS", "--rendition", rendition, "--width", "256", "--height", "256",
                        "--scale", "1", "--design-generation", "27"], check=True, capture_output=True)


# MARK: - visionOS


def write_stack(shapes: list[Polygon]) -> None:
    """visionOS's layers: the field at the back, the back plates in the middle, the front plate in
    front."""
    layers = {"Middle": Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)), "Front": Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))}
    geoms = plates(shapes, STACK_SCALE)
    rgb = spectrum(geoms)
    for i, geom in enumerate(geoms):
        name = "Middle" if i < STACK_BACK else "Front"
        layers[name] = Image.alpha_composite(layers[name], painted(geom, rgb, PLATE_OPACITY[i]))
    for name, image in layers.items():
        save_p3(image, STACK / f"{name}.solidimagestacklayer/Content.imageset/{name.lower()}.png")
    field("light").save(STACK / "Back.solidimagestacklayer/Content.imageset/back.png", optimize=True)


def render_social_preview() -> None:
    """The icon laid over the tile on GitHub's card, at `SOCIAL_TILE`."""
    with tempfile.TemporaryDirectory() as scratch:
        tile = Path(scratch) / "tile.png"
        subprocess.run([str(ictool()), str(ICON), "--export-image", "--output-file", str(tile),
                        "--platform", "iOS", "--rendition", "Default", "--width", "1024", "--height", "1024",
                        "--scale", "1", "--design-generation", "27"], check=True, capture_output=True)
        left, top, side = SOCIAL_TILE
        card = Image.open(IMAGES / "social-preview.png").convert("RGBA")
        card.alpha_composite(Image.open(tile).convert("RGBA").resize((side, side), Image.LANCZOS), (left, top))
        card.convert("RGB").save(IMAGES / "social-preview.png", optimize=True)


def recompress(paths: list[Path]) -> None:
    """The PNGs recompressed by oxipng, when it's installed: lossless, and `--strip safe` keeps the
    chunks that change how an image draws, its color profile among them."""
    names = ", ".join(str(path.relative_to(ROOT)) for path in paths)
    oxipng = shutil.which("oxipng")
    if oxipng is None:
        print(f"skipped oxipng on {names}: it isn't installed (brew install oxipng)")
        return
    subprocess.run([oxipng, "-o", "max", "--strip", "safe", *map(str, paths)], check=True, capture_output=True)
    print(f"recompressed {names} with oxipng, losslessly")


def main() -> None:
    shapes = bubbles()
    write_icon(shapes)
    write_stack(shapes)
    render_readme_icons()
    render_social_preview()
    print(f"wrote {ICON.relative_to(ROOT)} (icon.json and {len(list((ICON / 'Assets').iterdir()))} assets)")
    print(f"wrote {STACK.relative_to(ROOT)} (back, middle, front)")
    print(f"wrote {(IMAGES / 'icon.png').relative_to(ROOT)} and {(IMAGES / 'icon-dark.png').relative_to(ROOT)}")
    print(f"wrote {(IMAGES / 'social-preview.png').relative_to(ROOT)}")
    recompress([IMAGES / "icon.png", IMAGES / "icon-dark.png", IMAGES / "social-preview.png"])


if __name__ == "__main__":
    main()
