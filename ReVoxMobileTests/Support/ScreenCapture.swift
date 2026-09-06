import XCTest
import SwiftUI
import UIKit

/// Renders a screen to a PNG at each of the two sizes the project publishes, so `ScreenshotTests` and
/// `OnboardingScreenshotTests` share one implementation and every capture, present and future, gets both:
///
/// - `screenshots/<name>.png`, the README's: 393 × 852 points (iPhone 15/16 portrait) at @2x, 786 × 1704 px,
///   sharp in the README at half the bytes of @3x.
/// - `store-screenshots/<name>.png`, App Store Connect's 6.9-inch slot: 430 × 932 points (the 6.7-inch phones'
///   portrait) at @3x, 1290 × 2796 px exactly. `scripts/store/compose-screenshots.py` puts the captions round them.
///
/// One PNG per size, and a real one: the first version of the capture shipped five byte-identical white images,
/// because `drawHierarchy` renders nothing for a window with no scene and a size assertion cannot tell a blank page
/// from a busy one. The layer tree is rendered instead, the window is attached to the app's own scene so SwiftUI
/// lays out in a real trait environment, and the result is checked for actual content at each size.
@MainActor
enum ScreenCapture {
    struct Render {
        /// The folder under the host app's Documents; `scripts/ci/collect-screenshots.sh` copies it out by this name.
        let folder: String
        let size: CGSize            // points
        let scale: CGFloat
        /// The safe area the screen is laid out in, or nil for whatever the simulator gives the window. See `image`.
        let safeArea: UIEdgeInsets?
        /// Whether a window larger than the simulator's screen is scaled to fit it (see `makeWindow`). True for the
        /// store render only (review R1): the README render is captured exactly as the simulator lays it out, so
        /// its PNGs stay byte-identical from one simulator to the next, and a simulator too small for it fails
        /// `capture` visibly instead of changing the image.
        let fitsToScreen: Bool

        var pixelWidth: Int { Int(size.width * scale) }
        var pixelHeight: Int { Int(size.height * scale) }
    }

    static let readme = Render(folder: "screenshots", size: CGSize(width: 393, height: 852), scale: 2, safeArea: nil, fitsToScreen: false)
    /// The safe area is the 6.7-inch phones' own (59 points of status bar, 34 of home indicator) rather than the
    /// simulator's, which is a different phone.
    static let store = Render(folder: "store-screenshots", size: CGSize(width: 430, height: 932), scale: 3,
                              safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), fitsToScreen: true)
    static let renders = [readme, store]

    static func directory(for render: Render) throws -> URL {
        let documents = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let directory = documents.appendingPathComponent(render.folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes `<folder>/<name>.png` for every render, checking each for content and for its exact pixel size, and
    /// returns the README one.
    @discardableResult
    static func capture<V: View>(_ name: String, settle: TimeInterval = 0.25, _ view: V) throws -> URL {
        var readmeURL: URL?
        for render in renders {
            let image = image(of: view, at: render, settle: settle)
            let colors = distinctColors(in: image)
            XCTAssertGreaterThan(colors, blankThreshold, "\(name) rendered blank in \(render.folder) (\(colors) distinct colours)")
            let data = try XCTUnwrap(image.pngData(), "\(name) produced no PNG for \(render.folder)")
            let written = try XCTUnwrap(UIImage(data: data)?.cgImage, "\(name) for \(render.folder) is not a readable PNG")
            XCTAssertEqual(written.width, render.pixelWidth, "\(name) in \(render.folder): width")
            XCTAssertEqual(written.height, render.pixelHeight, "\(name) in \(render.folder): height")
            let url = try directory(for: render).appendingPathComponent("\(name).png")
            try data.write(to: url)
            if render.folder == readme.folder { readmeURL = url }
        }
        return try XCTUnwrap(readmeURL, "no README render is configured")
    }

    private static func image<V: View>(of view: V, at render: Render, settle: TimeInterval) -> UIImage {
        let controller = UIHostingController(rootView: view)
        controller.overrideUserInterfaceStyle = .light
        let window = makeWindow(size: render.size, fitsToScreen: render.fitsToScreen)
        if !render.fitsToScreen, let screen = screenSize(of: window), render.size.width > screen.width || render.size.height > screen.height {
            XCTFail("the \(render.folder) render (\(Int(render.size.width)) × \(Int(render.size.height)) points) does not fit this simulator's "
                    + "\(Int(screen.width)) × \(Int(screen.height)) screen and is never scaled to it; run the screenshots on an iPhone at least that size")
        }
        // A window attached to the app's scene is retained by that scene: without this, each capture leaves a
        // live SwiftUI hierarchy sitting over the app for the rest of the run, doing layout on the main actor —
        // which is what started timing out the main-actor polls in the LiveViewModel and keep-alive tests.
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        if let safeArea = render.safeArea {
            // UIKit gives a window the safe area of the simulator it runs on, so a 430 × 932 store render on an
            // iPhone 16 would lay out under that phone's insets. The difference to the wanted insets is added
            // (negative where the simulator's are larger), then the screen is laid out again.
            window.layoutIfNeeded()
            let given = controller.view.safeAreaInsets
            controller.additionalSafeAreaInsets = UIEdgeInsets(top: safeArea.top - given.top, left: safeArea.left - given.left,
                                                               bottom: safeArea.bottom - given.bottom, right: safeArea.right - given.right)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        }
        RunLoop.current.run(until: Date().addingTimeInterval(settle))   // one turn for async text and image work

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = render.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        var image = renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
        if distinctColors(in: image) <= blankThreshold {
            // A scene-attached window can draw its hierarchy, which catches anything the layer tree misses.
            image = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        return image
    }

    /// A screen with a navigation bar, a card and text has hundreds; a blank page has one.
    static let blankThreshold = 8

    static func makeWindow(size: CGSize, fitsToScreen: Bool = false) -> UIWindow {
        let scenes = UIApplication.shared.connectedScenes
        let scene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            ?? scenes.first as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(origin: .zero, size: size))
        window.frame = CGRect(origin: .zero, size: size)
        // A window larger than the simulator's screen (the store size on an iPhone 16) is scaled to fit it on
        // screen, bounds untouched, so the layout and the render are still the full 430 × 932 points. UIKit
        // derives a window's safe area from where the screen's status bar and home indicator fall on it: at full
        // size the 932-point window's bottom edge would sit 80 points past an 852-point screen and be given a
        // 114-point bottom inset. Only the render that asks for it is scaled (review R1): the README render is
        // left as the simulator lays it out, and `image` fails the capture if that simulator is too small.
        if fitsToScreen, let screen = screenSize(of: window), size.width > screen.width || size.height > screen.height {
            let fit = min(screen.width / size.width, screen.height / size.height)
            window.transform = CGAffineTransform(scaleX: fit, y: fit)
            window.center = CGPoint(x: size.width * fit / 2, y: size.height * fit / 2)
        }
        return window
    }

    /// The simulator's screen in points, or nil for a window with no scene (which no capture on CI has).
    static func screenSize(of window: UIWindow) -> CGSize? {
        window.windowScene?.coordinateSpace.bounds.size
    }

    /// Distinct colours across a coarse grid — enough to tell a rendered screen from an empty one without
    /// reading every pixel of a two-megapixel image. The image is composited over white first: CI run 117's
    /// `history-selecting` was a transparent page with a few half-transparent white pixels along its edges, and
    /// their alpha values alone counted as forty "colours", so the layer render passed and the fallback never ran.
    static func distinctColors(in image: UIImage, samples: Int = 48) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return 0 }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return 0 }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        var seen = Set<UInt32>()
        let stepX = max(1, width / samples), stepY = max(1, height / samples)
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = (y * width + x) * 4
                seen.insert(UInt32(pixels[offset]) << 16 | UInt32(pixels[offset + 1]) << 8 | UInt32(pixels[offset + 2]))
            }
        }
        return seen.count
    }
}
