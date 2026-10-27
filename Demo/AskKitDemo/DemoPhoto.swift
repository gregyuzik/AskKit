import CoreGraphics

/// The one photo the demo attaches: a record sleeve it draws.
///
/// The demo has no photo library to pick from, and a picture it draws is one
/// the UI tests can attach without a picker in the way. A host's `onAttach`
/// presents its picker and hands the store what the reader chose; this hands
/// the store the sleeve.
nonisolated enum DemoPhoto {
    static let label = "Blue record sleeve"
    /// Where a host would keep the photo. The demo keeps it nowhere, and draws
    /// it again for a thread read back from disk.
    static let reference = "demo.sleeve"

    /// Drawn off the main actor, the way `AskDomain.photoThumbnail(for:)` asks
    /// a host to read a photo back.
    @concurrent static func drawn() async -> CGImage? {
        draw()
    }

    static func draw() -> CGImage? {
        let side = 480
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGBitmapInfo(alpha: .premultipliedLast)
              ) else { return nil }
        // The sleeve.
        context.setFillColor(red: 0.16, green: 0.29, blue: 0.55, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        // The record, out of it by a third, and its label.
        context.setFillColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        context.fillEllipse(in: CGRect(x: 170, y: 90, width: 300, height: 300))
        context.setFillColor(red: 0.85, green: 0.72, blue: 0.30, alpha: 1)
        context.fillEllipse(in: CGRect(x: 290, y: 210, width: 60, height: 60))
        return context.makeImage()
    }
}
