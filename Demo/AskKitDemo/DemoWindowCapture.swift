#if DEBUG && os(macOS)
import AppKit
import CoreGraphics
import Foundation

/// The Mac window as a PNG, imaged by the demo itself: what
/// `DemoLaunchArgument.captureWindow` does, for the README's images.
///
/// The window takes the content size asked for and comes to the front, and
/// once the screen has settled it is written as the window server composites
/// it: title bar, glass and the shadow the system draws around the window, so
/// the image is larger than the window by the shadow's reach on every side and
/// transparent beyond the shadow and the window's corners. Then the app quits,
/// however the capture went, since the script waits on the process rather
/// than on the file. A Debug build only: nothing that ships reads a path from
/// its launch.
///
/// **The app images its own window** because a process may do that without
/// the Screen Recording permission, through `CGWindowListCreateImage`.
/// ScreenCaptureKit, the function's replacement, and `screencapture -l` ask
/// for the permission even for a window of the process's own. The SDK marks
/// the function obsoleted, so it is looked up at run time, where the system
/// still has it; if a later macOS takes it away, the capture says so and
/// writes nothing.
///
/// **Written plainly, never atomically.** The script hands the PNG over as an
/// inherited descriptor, `/dev/fd/4`: signed, the demo runs in the App
/// Sandbox, which lets it write a descriptor it was given and no path outside
/// its container. An atomic write goes to a file beside the path and renames
/// it over the path, which a descriptor can't take.
enum DemoWindowCapture {
    /// The content size when `DemoLaunchArgument.captureSize` gives none.
    private static let defaultSize = CGSize(width: 1280, height: 800)
    /// The seconds to wait when `DemoLaunchArgument.captureAfter` gives none:
    /// long enough for the first screen to read the library and settle.
    private static let defaultSettle = 8.0

    /// Begin the capture, when the launch asks for one. Called once, as the
    /// app starts.
    static func startIfAsked() {
        guard let path = DemoLaunchArgument.value(after: DemoLaunchArgument.captureWindow) else { return }
        let url = URL(filePath: path)
        let settle = DemoLaunchArgument.value(after: DemoLaunchArgument.captureAfter)
            .flatMap(seconds(from:)) ?? defaultSettle
        let size = DemoLaunchArgument.value(after: DemoLaunchArgument.captureSize)
            .flatMap(contentSize(from:)) ?? defaultSize
        Task {
            defer { NSApplication.shared.terminate(nil) }
            guard let window = await firstWindow() else {
                report("no window appeared")
                return
            }
            // Key and in front, so the title bar draws as it does for a reader
            // using the app rather than dimmed. Activation is cooperative: the
            // app in front can keep it, and so does the lock screen.
            NSApplication.shared.activate()
            window.setContentSize(size)
            window.center()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(settle))
            if !NSApplication.shared.isActive {
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nothing"
                report("\(front) kept the front, so the window draws as inactive")
            }
            write(window, to: url)
        }
    }

    /// `8` or `2.5` as seconds, up to an hour, or nil for anything else.
    private static func seconds(from text: String) -> Double? {
        guard let seconds = Double(text), (0...3600).contains(seconds) else { return nil }
        return seconds
    }

    /// `1280x800` as a size, or nil for anything else.
    private static func contentSize(from text: String) -> CGSize? {
        let sides = text.split(separator: "x").compactMap { Int($0) }
        guard sides.count == 2, sides.allSatisfy({ $0 > 0 }) else { return nil }
        return CGSize(width: sides[0], height: sides[1])
    }

    /// The demo's window once it is on screen, within fifteen seconds.
    private static func firstWindow() async -> NSWindow? {
        for _ in 0..<150 {
            let window = NSApplication.shared.windows.first {
                $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel)
            }
            if let window { return window }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static func write(_ window: NSWindow, to url: URL) {
        guard let image = image(of: window),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            report("the window could not be imaged")
            return
        }
        do {
            try png.write(to: url)
            report("wrote \(image.width)x\(image.height) to \(url.path(percentEncoded: false))")
        } catch {
            report("could not write \(url.path(percentEncoded: false)): \(error.localizedDescription)")
        }
    }

    /// `CGWindowListCreateImage`, as it is looked up.
    private typealias CreateImage = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?

    /// The window and its shadow, at the display's resolution: without
    /// `.boundsIgnoreFraming`, the bounds take in the window's framing effects,
    /// its shadow. When the window server composites nothing, as with
    /// the display asleep, the image comes back wholly transparent: the script
    /// checks for that.
    private static func image(of window: NSWindow) -> CGImage? {
        guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "CGWindowListCreateImage") else {
            report("this macOS no longer has CGWindowListCreateImage")
            return nil
        }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        return create(
            .null,
            CGWindowListOption.optionIncludingWindow.rawValue,
            CGWindowID(window.windowNumber),
            CGWindowImageOption([.bestResolution]).rawValue
        )?.takeRetainedValue()
    }

    /// A line for the script's log: nobody is watching the window.
    private static func report(_ line: String) {
        print("DemoWindowCapture: \(line)")
    }
}
#endif
