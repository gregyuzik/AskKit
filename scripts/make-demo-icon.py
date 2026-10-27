#!/usr/bin/env python3
"""Generate the demo's app icon, three plates of tinted glass in the silhouette of the speech bubble
from SF Symbols' `text.bubble.badge.sparkles`, the glyph its Ask tab wears, so the icon and the tab
can't drift apart.

The symbol's bubble is rendered through AppKit as a 4096 px mask and traced back to curves, and only
its outline is kept: the text lines go, and the notch the sparkles cut in its shoulder is filled with
its other top corner, mirrored. Three outputs:

- `Demo/AskKitDemo/AppIcon.icon/` — the Icon Composer document, `icon.json` included. The plates
  recede straight back, each smaller and higher than the one in front, so nothing slides sideways,
  each in Liquid Glass, from the most transparent at the back to the most saturated at the front, so
  the color deepens where they overlap. Each plate is an image of its own with its place and size
  drawn in, and a gradient through `AskSpectrum.aurora`'s five colors runs across the whole stack from
  bottom left to top right, not across each plate, so where plates overlap their colors agree. The
  images are Display P3 PNGs because Icon Composer clamps an SVG's gradients to sRGB and takes only
  two colors in a fill. Behind them lies a pastel field, peach-cream through pink to pale teal (deep
  plum through indigo to deep teal in dark), crossed by a soft beam. In the clear and tinted looks,
  which bring a field of their own, the field hides and the plates turn white.
- `Demo/AskKitDemo/Assets.xcassets/AppIcon.solidimagestack/` — visionOS's three layers: the field at
  the back, the two back plates in the middle and the front plate in front, so the plates part in
  parallax, scaled to sit inside the round mask.
- `docs/images/icon.png` and `icon-dark.png` — the icon atop the README, rendered by Icon Composer's
  `ictool` in light and dark.

Needs macOS with Xcode (the symbol is rendered through AppKit, the README's images by `ictool`) and
numpy, shapely, Pillow and potracer:

    python3 -m venv tmp/venv && tmp/venv/bin/pip install numpy shapely pillow potracer
    tmp/venv/bin/python scripts/make-demo-icon.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import potrace
from PIL import Image, ImageDraw
from shapely import affinity
from shapely.geometry import MultiPolygon, Polygon, box
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent.parent
DEMO = ROOT / "Demo/AskKitDemo"
ICON = DEMO / "AppIcon.icon"
STACK = DEMO / "Assets.xcassets/AppIcon.solidimagestack"
IMAGES = ROOT / "docs/images"

SYMBOL = "text.bubble.badge.sparkles.fill"
# The symbol's ink spans this much of the 1024 grid while it's traced.
INK_WIDTH = 700
MASK_SIDE = 4096
DISPLAY_P3 = Path("/System/Library/ColorSync/Profiles/Display P3.icc")

# `AskSpectrum.aurora` (Sources/AskUI/AskSpectrum.swift) in Display P3: cyan, blue, violet, magenta,
# coral, and where each sits on the stack's gradient, from its bottom left to its top right.
AURORA = ((0.30, 0.86, 1.00), (0.24, 0.48, 1.00), (0.56, 0.36, 1.00), (0.90, 0.32, 0.86), (1.00, 0.50, 0.44))
AURORA_STOPS = (0.0, 0.3, 0.55, 0.8, 1.0)

# The bubble's width on the 1024 grid at full size, the front plate's. Then the plates, back to
# front: each one's scale about the centre, its offset from the centre after that (y down) and its
# opacity. Each plate is a group of its own, and with the field that's Icon Composer's limit of four.
PLATE_WIDTH = 440
PLATE_SCALES = (0.72, 0.86, 1.0)
PLATE_OFFSETS = ((0, -128), (0, -60), (0, 36))
PLATE_OPACITY = (0.45, 0.7, 0.95)
TRANSLUCENCY = 0.5

# The field, sRGB, from its top right corner to its bottom left, and the beam across it: its colour
# in Display P3, its opacity, how far below the centre it runs before it turns, its width (both in
# grid units) and how far it turns, in degrees.
FIELD = {
    "light": (("#fcebd8", 0.0), ("#f7dfdf", 0.5), ("#a8d9e2", 1.0)),
    "dark": (("#2b1a35", 0.0), ("#15112a", 0.55), ("#0e2433", 1.0)),
}
BEAM = {"light": (AURORA[4], 0.24), "dark": (AURORA[1], 0.22)}
BEAM_OFFSET, BEAM_WIDTH, BEAM_TURN = 154, 307, 21.8

# visionOS draws the stack inside a round mask, so its art is scaled down about the centre, and this
# many plates sit in the middle layer, the rest in front.
STACK_SCALE = 0.86
STACK_BACK = 2

RENDER_SWIFT = r"""
import AppKit
// The symbol's bubble layer as an alpha mask, the whole symbol scaled so its ink is `width` of a
// 1024 grid wide and centred.
let name = CommandLine.arguments[1], width = CGFloat(Double(CommandLine.arguments[2])!)
let side = Int(CommandLine.arguments[3])!, out = CommandLine.arguments[4]
let scale = CGFloat(side) / 1024

func render(_ palette: [NSColor], in rect: NSRect?) -> (NSBitmapImageRep, NSRect) {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 1000, weight: .regular).applying(.init(paletteColors: palette)))!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let target = rect ?? NSRect(origin: .zero, size: image.size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: target)
    NSGraphicsContext.restoreGraphicsState()
    return (rep, target)
}

/// The inked pixels' bounds, bottom up, as drawing coordinates run.
func ink(_ rep: NSBitmapImageRep) -> NSRect {
    let data = rep.bitmapData!, stride = rep.bytesPerRow
    var minX = side, maxX = -1, minY = side, maxY = -1
    for y in 0..<side { for x in 0..<side where data[y * stride + x * 4 + 3] > 127 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    return NSRect(x: minX, y: side - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let (probe, natural) = render([.white, .white], in: nil)
let box = ink(probe)
let k = width * scale / box.width
let placed = NSRect(x: CGFloat(side) / 2 - (box.midX - natural.minX) * k, y: CGFloat(side) / 2 - (box.midY - natural.minY) * k,
                    width: natural.width * k, height: natural.height * k)
// The palette's first layer is the sparkles, its second the bubble.
let (rep, _) = render([.clear, .white], in: placed)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
"""


# MARK: - The bubble


def bezier(p0, p1, p2, p3, steps: int = 24) -> list[tuple[float, float]]:
    t = np.linspace(0, 1, steps + 1)[1:, None]
    p0, p1, p2, p3 = map(np.array, (p0, p1, p2, p3))
    return [tuple(p) for p in (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3]


def traced(png: Path):
    """The mask's shape on the 1024 grid, y down: every traced ring, filled even-odd."""
    # potracer traces the dark pixels, so the mask goes in inverted.
    dark = ~(np.asarray(Image.open(png).getchannel("A")) > 127)
    unit = 1024 / MASK_SIDE
    shape = None
    for curve in potrace.Bitmap(dark).trace(turdsize=4, alphamax=1.0, opticurve=True, opttolerance=0.2):
        points, last = [], curve.start_point
        for segment in curve.segments:
            end = (segment.end_point.x, segment.end_point.y)
            if segment.is_corner:
                points += [(segment.c.x, segment.c.y), end]
            else:
                points += bezier((last.x, last.y), (segment.c1.x, segment.c1.y), (segment.c2.x, segment.c2.y), end)
            last = segment.end_point
        ring = Polygon([(x * unit, y * unit) for x, y in points]).buffer(0)
        shape = ring if shape is None else shape.symmetric_difference(ring)
    return shape


def parts(geom) -> list[Polygon]:
    return list(geom.geoms) if isinstance(geom, MultiPolygon) else [geom]


def bubble() -> Polygon:
    """The bubble's outline, `PLATE_WIDTH` wide and centred on the grid, its notch filled."""
    with tempfile.TemporaryDirectory() as scratch:
        source, mask = Path(scratch) / "render.swift", Path(scratch) / "bubble.png"
        source.write_text(RENDER_SWIFT)
        subprocess.run(["xcrun", "swift", str(source), SYMBOL, str(INK_WIDTH), str(MASK_SIDE), str(mask)],
                       check=True, capture_output=True)
        layer = traced(mask)
    shapes = parts(layer)
    assert len(shapes) == 1 and len(shapes[0].interiors) == 2, \
        f"expected one bubble with two text lines, traced {len(shapes)} shapes"
    outline = Polygon(shapes[0].exterior)
    # The sparkles cut a notch in the top right corner. The body is a rounded rectangle, so its top
    # half mirrored left to right is the whole corner, and the tail sits low enough to stay out of it.
    x0, y0, x1, y1 = outline.bounds
    top = outline.intersection(box(x0, y0, x1, (y0 + y1) / 2))
    filled = unary_union([outline, affinity.scale(top, -1, 1, origin=((x0 + x1) / 2, 0))]).buffer(0.5).buffer(-0.5)
    assert isinstance(filled, Polygon) and filled.area > outline.area, "the notch didn't fill"
    x0, y0, x1, y1 = filled.bounds
    k = PLATE_WIDTH / (x1 - x0)
    return affinity.translate(affinity.scale(filled, k, k, origin=((x0 + x1) / 2, (y0 + y1) / 2)),
                              512 - (x0 + x1) / 2, 512 - (y0 + y1) / 2)


def plates(shape: Polygon, scale: float = 1.0) -> list[Polygon]:
    """The plates, back to front: the bubble scaled about the grid's centre and moved by its offset,
    then the whole stack scaled by `scale` about the centre."""
    return [affinity.scale(affinity.translate(affinity.scale(shape, k, k, origin=(512, 512)), dx, dy),
                           scale, scale, origin=(512, 512))
            for k, (dx, dy) in zip(PLATE_SCALES, PLATE_OFFSETS)]


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
    """The field and its beam, in sRGB values."""
    ys, xs = np.mgrid[0:1024, 0:1024] + 0.5
    colors, stops = zip(*FIELD[appearance])
    rgb = ramp(((1024 - xs) + ys) / 2048, [hex_rgb(c) for c in colors], stops)
    beam, opacity = BEAM[appearance]
    # Distance across the beam: turned by BEAM_TURN about the centre, it runs BEAM_OFFSET below it.
    turn = np.radians(BEAM_TURN)
    across = -(xs - 512) * np.sin(turn) + (ys - 512) * np.cos(turn) - BEAM_OFFSET
    strength = opacity * np.clip(1 - np.abs(across) / (BEAM_WIDTH / 2), 0, 1)[:, :, None]
    # The beam is P3; over an sRGB field at a quarter's opacity or less the gamut doesn't show.
    rgb = rgb * (1 - strength) + np.array(beam) * strength
    return Image.fromarray(np.round(rgb * 255).astype(np.uint8), "RGB").convert("RGBA")


def field_svg(appearance: str) -> str:
    """The field and its beam as Icon Composer draws them: the field's gradient across the square,
    and the beam a band whose gradient fades from clear to its colour and back."""
    def stop(offset, color, opacity=1.0):
        return f'<stop offset="{offset}" stop-color="{color}" stop-opacity="{opacity}"/>'
    beam, opacity = BEAM[appearance]
    beam_color = "color(display-p3 " + " ".join(f"{v:.2f}" for v in beam) + ")"
    top = 512 + BEAM_OFFSET - BEAM_WIDTH / 2
    # The beam's gradient is in user space: Icon Composer measures a bounding-box gradient on a
    # turned shape wrongly, and the beam comes out a flat band with hard edges.
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
            '<defs>\n'
            '<linearGradient id="field" x1="1" y1="0" x2="0" y2="1">'
            + "".join(stop(o, c) for c, o in FIELD[appearance]) + '</linearGradient>\n'
            f'<linearGradient id="beam" gradientUnits="userSpaceOnUse" x1="0" y1="{top:g}" x2="0" y2="{top + BEAM_WIDTH:g}">'
            + stop(0, beam_color, 0) + stop(0.5, beam_color, opacity) + stop(1, beam_color, 0) + '</linearGradient>\n'
            '</defs>\n'
            '<rect width="1024" height="1024" fill="url(#field)"/>\n'
            f'<rect x="-1024" y="{top:g}" width="3072" height="{BEAM_WIDTH}" fill="url(#beam)" '
            f'transform="rotate({BEAM_TURN} 512 512)"/>\n'
            '</svg>\n')


def save_p3(image: Image.Image, path: Path) -> None:
    image.save(path, optimize=True, icc_profile=DISPLAY_P3.read_bytes())


# MARK: - The icon


def srgb(code: str) -> str:
    return "srgb:" + ",".join(f"{v:.5f}" for v in (*hex_rgb(code), 1.0))


def write_icon(shape: Polygon) -> None:
    """The Icon Composer document, front to back: a group for each plate, then the field."""
    assets = ICON / "Assets"
    shutil.rmtree(assets, ignore_errors=True)
    assets.mkdir(parents=True)
    geoms = plates(shape)
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


def write_stack(shape: Polygon) -> None:
    """visionOS's layers: the field at the back, the back plates in the middle, the front plate in
    front."""
    layers = {"Middle": Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)), "Front": Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))}
    geoms = plates(shape, STACK_SCALE)
    rgb = spectrum(geoms)
    for i, geom in enumerate(geoms):
        name = "Middle" if i < STACK_BACK else "Front"
        layers[name] = Image.alpha_composite(layers[name], painted(geom, rgb, PLATE_OPACITY[i]))
    for name, image in layers.items():
        save_p3(image, STACK / f"{name}.solidimagestacklayer/Content.imageset/{name.lower()}.png")
    field("light").save(STACK / "Back.solidimagestacklayer/Content.imageset/back.png", optimize=True)


def main() -> None:
    shape = bubble()
    write_icon(shape)
    write_stack(shape)
    render_readme_icons()
    print(f"wrote {ICON.relative_to(ROOT)} (icon.json and {len(list((ICON / 'Assets').iterdir()))} assets)")
    print(f"wrote {STACK.relative_to(ROOT)} (back, middle, front)")
    print(f"wrote {(IMAGES / 'icon.png').relative_to(ROOT)} and {(IMAGES / 'icon-dark.png').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
