// Generate the demo's Ask symbol, `askkit.bubbles`, and its `askkit.bubbles.fill` sibling: the app
// icon's three speech bubbles, each behind and up to the right of the one in front, drawn as SF
// Symbols draw a stack. The Ask tab wears it, and the bar swaps in the fill itself; the first
// screen's mark is the fill.
//
// Writes both `.symbolset`s into `Demo/AskKitDemo/Assets.xcassets`, or into the asset catalog given
// as the one argument:
//
//     swift scripts/make-demo-symbol.swift
//
// With `--plates` it writes nothing, and prints the three bubbles at regular as JSON instead, each
// filled out to its stroke's outer edge: the plates `scripts/make-demo-icon.py` makes the app icon of.
//
// Each is an SF Symbols template with all 27 variants, nine weights in three scales, in the layout
// Xcode's asset compiler takes: a cap-height guide for each row, Medium and Large blown up from Small
// about the cap box's centre (1.267 and 1.618 times, as Apple's own symbols measure), and the margins
// at the ink's edges. Every weight is drawn, because outlines that boolean operations make can't be
// interpolated: with only three, a weight between them, such as Bold Text's, takes the nearest one.
// Nothing is rendered: the outlines come from CoreGraphics' stroking and its boolean operations on
// rounded rectangles, so they are the drawing itself.
//
// Measured against Apple's symbols in pixels at 100 pt, medium scale:
// - `bubble`'s stroke and width at each weight, in `measured` below;
// - `square.stack` draws the layers behind at three quarters of the front's stroke, 6 against 8;
// - the clock beside Ask in a toolbar inks 109 across, and the front bubble inks 105, so the stack
//   reads as large as the symbols beside it.

import CoreGraphics
import Foundation

// MARK: - The drawing, in pixels at 100 pt, medium scale, y down

/// Where a bubble's tail leaves its bottom edge, and its tip.
struct Tail {
    let left: CGFloat
    let right: CGFloat
    let tip: CGPoint
}

/// A speech bubble: a rounded rectangle, with a tail on the front one.
struct Bubble {
    let rect: CGRect
    let radius: CGFloat
    let tail: Tail?

    /// The same body moved up and to the right, as the icon's plates sit behind each other.
    func behind(_ distance: CGFloat) -> Bubble {
        Bubble(rect: rect.offsetBy(dx: distance, dy: -distance), radius: radius, tail: nil)
    }

    /// The outline through the stroke's centre, clockwise from the top left corner.
    var path: CGPath {
        let path = CGMutablePath()
        let r = radius
        let (x0, x1, y0, y1) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        path.move(to: CGPoint(x: x0 + r, y: y0))
        path.addLine(to: CGPoint(x: x1 - r, y: y0))
        path.addArc(tangent1End: CGPoint(x: x1, y: y0), tangent2End: CGPoint(x: x1, y: y0 + r), radius: r)
        path.addLine(to: CGPoint(x: x1, y: y1 - r))
        path.addArc(tangent1End: CGPoint(x: x1, y: y1), tangent2End: CGPoint(x: x1 - r, y: y1), radius: r)
        if let tail {
            path.addLine(to: CGPoint(x: tail.right, y: y1))
            let mid = CGPoint(x: (tail.right + tail.tip.x) / 2, y: (y1 + tail.tip.y) / 2)
            path.addQuadCurve(to: tail.tip, control: CGPoint(x: mid.x - 1.5, y: mid.y - 2.5))
            path.addLine(to: CGPoint(x: tail.left, y: y1))
        }
        path.addLine(to: CGPoint(x: x0 + r, y: y1))
        path.addArc(tangent1End: CGPoint(x: x0, y: y1), tangent2End: CGPoint(x: x0, y: y1 - r), radius: r)
        path.addLine(to: CGPoint(x: x0, y: y0 + r))
        path.addArc(tangent1End: CGPoint(x: x0, y: y0), tangent2End: CGPoint(x: x0 + r, y: y0), radius: r)
        path.closeSubpath()
        return path
    }
}

/// One of the template's three weights.
struct Weight {
    let name: String
    /// The front bubble's stroke. The two behind take three quarters of it.
    let stroke: CGFloat
    /// The clear space between one layer and the next.
    let gap: CGFloat
    /// How wide the whole stack is, against regular's, as `bubble` widens with weight.
    let widen: CGFloat

    var backStroke: CGFloat { stroke * 0.75 }

    /// How far the stack reaches past the front bubble's centre line: its own stroke's outer half
    /// on the left, and on the right the two layers behind, their gaps and their strokes.
    var extra: CGFloat {
        stroke / 2 + (stroke / 2 + gap + backStroke / 2) + backStroke + gap + backStroke / 2
    }
}

/// `bubble`'s stroke and width at each weight, in pixels at 100 pt (measured at 400 pt).
let measured: [(name: String, stroke: CGFloat, width: CGFloat)] = [
    ("Ultralight", 2.38, 127.75),
    ("Thin", 3.62, 129),
    ("Light", 6.03, 131),
    ("Regular", 7.85, 132.75),
    ("Medium", 9.56, 134.5),
    ("Semibold", 10.87, 135.75),
    ("Bold", 12.59, 137.5),
    ("Heavy", 15.1, 140.25),
    ("Black", 17.34, 142.5)
]

/// Every weight drawn, so none is interpolated: the strokes follow `bubble`'s from a regular of 8,
/// the gaps open a little with them, and the stack widens as `bubble` does.
let regular = Weight(name: "Regular", stroke: 8, gap: 6.5, widen: 1)
let weights = measured.map { entry in
    guard entry.name != regular.name else { return regular }
    let stroke = 8 * entry.stroke / 7.85
    return Weight(name: entry.name, stroke: stroke, gap: 6.5 + (stroke - 8) * 0.12, widen: entry.width / 132.75)
}

/// The front bubble at regular, across its stroke's centre: its ink, 105 wide, about the clock's.
let regularFrontWidth: CGFloat = 97

/// The front bubble, `width` across its stroke's centre, in the proportions of the icon's.
func front(width w: CGFloat) -> Bubble {
    Bubble(
        rect: CGRect(x: 0, y: 0, width: w, height: w * 0.639),
        radius: w * 0.175,
        tail: Tail(left: w * 0.227, right: w * 0.402, tip: CGPoint(x: w * 0.2115, y: w * 0.639 + w * 0.247))
    )
}

func stroked(_ path: CGPath, _ width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).normalized()
}

/// The three bubbles at one weight, back to front, each with its stroke.
func bubbles(weight: Weight) -> [(bubble: Bubble, stroke: CGFloat)] {
    let frontWidth = (regularFrontWidth + regular.extra) * weight.widen - weight.extra
    let near = weight.stroke / 2 + weight.gap + weight.backStroke / 2
    let far = near + weight.backStroke + weight.gap
    let bubble = front(width: frontWidth)
    return [(bubble.behind(far), weight.backStroke), (bubble.behind(near), weight.backStroke), (bubble, weight.stroke)]
}

/// The stack at one weight, its outline or its fill. Each layer is cleared where a layer in front
/// of it lies, and for a gap around that layer, so the ones behind show as slivers.
func stack(weight: Weight, filled: Bool) -> CGPath {
    let layers = bubbles(weight: weight)
    var result = CGMutablePath() as CGPath
    for (index, (layer, width)) in layers.enumerated() {
        let path = layer.path
        var shape = stroked(path, width)
        if filled { shape = shape.union(path) }
        for (ahead, aheadWidth) in layers[(index + 1)...] {
            let aheadPath = ahead.path
            shape = shape.subtracting(aheadPath.union(stroked(aheadPath, aheadWidth + 2 * weight.gap)))
        }
        result = result.union(shape)
    }
    return result
}

// MARK: - The template

let mediumPerSmall: CGFloat = 1.267
let cap: CGFloat = 70.459
let capCentre = -cap / 2
let rows: [(tag: String, baseline: CGFloat, scale: CGFloat)] = [("S", 696, 1), ("M", 1126, 1.267), ("L", 1556, 1.618)]
/// The nine weight columns, Ultralight at 559.711 to Black at 2933.4, as SF Symbols lays them out.
let columns = Dictionary(uniqueKeysWithValues: measured.enumerated().map { ($1.name, 559.711 + CGFloat($0) * 296.711) })

/// A weight's drawing in the template's small-scale units, its ink starting at x 0 and centred on
/// the cap box, and its ink's width.
func glyph(weight: Weight, filled: Bool) -> (path: CGPath, width: CGFloat) {
    var toSmall = CGAffineTransform(scaleX: 1 / mediumPerSmall, y: 1 / mediumPerSmall)
    guard let small = stack(weight: weight, filled: filled).copy(using: &toSmall) else { fatalError("unscalable path") }
    let box = small.boundingBoxOfPath
    var place = CGAffineTransform(translationX: -box.minX, y: capCentre - box.midY)
    guard let placed = small.copy(using: &place) else { fatalError("unplaceable path") }
    return (placed, box.width)
}

func fmt(_ value: CGFloat) -> String {
    var text = String(format: "%.3f", Double(value))
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text == "-0" ? "0" : text
}

func svgData(_ path: CGPath) -> String {
    var data = ""
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
            data += "M\(fmt(points[0].x)) \(fmt(points[0].y))"
        case .addLineToPoint:
            data += "L\(fmt(points[0].x)) \(fmt(points[0].y))"
        case .addQuadCurveToPoint:
            data += "Q\(fmt(points[0].x)) \(fmt(points[0].y)) \(fmt(points[1].x)) \(fmt(points[1].y))"
        case .addCurveToPoint:
            data += "C\(fmt(points[0].x)) \(fmt(points[0].y)) \(fmt(points[1].x)) \(fmt(points[1].y)) "
                + "\(fmt(points[2].x)) \(fmt(points[2].y))"
        case .closeSubpath:
            data += "Z"
        @unknown default:
            fatalError("unknown path element")
        }
    }
    return data
}

let hReference = #"<path d="M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.2315-26.7285L12.4385-26.7285ZM55.1196 0L57.7637 0L30.6382-70.459L29.4326-70.459L29.4326-67.1323Z"/>"#

func template(filled: Bool) -> String {
    let order = measured.map(\.name)
    let glyphs = Dictionary(uniqueKeysWithValues: weights.map { ($0.name, glyph(weight: $0, filled: filled)) })
    var guides: [String] = []
    var symbols: [String] = []
    for row in rows {
        let base = fmt(row.baseline)
        guides.append(#"  <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 \#(base))">"# + "\n   \(hReference)\n  </g>")
        guides.append(#"  <line id="Baseline-\#(row.tag)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\#(base)" y2="\#(base)"/>"#)
        guides.append(#"  <line id="Capline-\#(row.tag)" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="\#(fmt(row.baseline - cap))" y2="\#(fmt(row.baseline - cap))"/>"#)
    }
    for row in rows {
        for name in order.reversed() {
            guard let centre = columns[name], let entry = glyphs[name] else { fatalError("no \(name)") }
            let (path, width) = entry
            let left = centre - width * row.scale / 2
            let right = centre + width * row.scale / 2
            for (side, x) in [("right", right), ("left", left)] {
                guides.append(#"  <line id="\#(side)-margin-\#(name)-\#(row.tag)" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" x1="\#(fmt(x))" x2="\#(fmt(x))" y1="\#(fmt(row.baseline - cap * 1.35))" y2="\#(fmt(row.baseline + cap * 0.34))"/>"#)
            }
            var drawing = #"<path d="\#(svgData(path))"/>"#
            if row.scale != 1 {
                drawing = #"<g transform="matrix(\#(fmt(row.scale)) 0 0 \#(fmt(row.scale)) 0 \#(fmt(capCentre * (1 - row.scale))))">\#(drawing)</g>"#
            }
            symbols.append(#"  <g id="\#(name)-\#(row.tag)" transform="matrix(1 0 0 1 \#(fmt(left)) \#(fmt(row.baseline)))">"# + "\n   \(drawing)\n  </g>")
        }
    }
    let labels = order.map { name in
        #"  <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:middle;" transform="matrix(1 0 0 1 \#(fmt(columns[name] ?? 0)) 322)">\#(name)</text>"#
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 3300 2200">
     <g id="Notes">
      <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
      <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" x2="3036" y1="292" y2="292"/>
      <text style="stroke:none;fill:black;font-family:sans-serif;font-size:13;font-weight:bold;" transform="matrix(1 0 0 1 263 322)">Weight/Scale Variations</text>
    \(labels.joined(separator: "\n"))
     </g>
     <g id="Guides">
    \(guides.joined(separator: "\n"))
     </g>
     <g id="Symbols">
    \(symbols.joined(separator: "\n"))
     </g>
    </svg>

    """
}

func contents(_ name: String) -> String {
    """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "symbols" : [
        {
          "filename" : "\(name).svg",
          "idiom" : "universal"
        }
      ]
    }

    """
}

// MARK: - Writing

let arguments = CommandLine.arguments.dropFirst()
if arguments.first == "--plates" {
    // The three bubbles at regular, back to front, each filled out to its stroke's outer edge, in
    // pixels at 100 pt with y down: the plates make-demo-icon.py builds the app icon from.
    let plates = bubbles(weight: regular).map { layer in svgData(layer.bubble.path.union(stroked(layer.bubble.path, layer.stroke))) }
    let json = try JSONSerialization.data(withJSONObject: ["plates": plates], options: [.prettyPrinted, .sortedKeys])
    print(String(bytes: json, encoding: .utf8) ?? "")
} else {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let catalog = arguments.first.map { URL(fileURLWithPath: $0) } ?? root.appendingPathComponent("Demo/AskKitDemo/Assets.xcassets")
    for (name, filled) in [("askkit.bubbles", false), ("askkit.bubbles.fill", true)] {
        let set = catalog.appendingPathComponent("\(name).symbolset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        try template(filled: filled).write(to: set.appendingPathComponent("\(name).svg"), atomically: true, encoding: .utf8)
        try contents(name).write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        print("wrote \(set.path)")
    }
}
