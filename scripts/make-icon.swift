// Draws the app icon and packs it into an .icns. Usage: swift scripts/make-icon.swift <out.icns>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Flipside-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Renders the icon at `pixels` square. All coordinates are on a 1024 grid, y down.
func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let scale = CGFloat(pixels) / 1024
    cg.translateBy(x: 0, y: CGFloat(pixels))
    cg.scaleBy(x: scale, y: -scale)

    // The standard macOS icon shape: an 824 pt rounded square with a soft shadow beneath.
    let plate = CGPath(
        roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
        cornerWidth: 185, cornerHeight: 185, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: CGColor(gray: 0, alpha: 0.3))
    cg.addPath(plate)
    cg.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.95, alpha: 1))
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(plate)
    cg.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.42, green: 0.68, blue: 1.0, alpha: 1),
            CGColor(red: 0.13, green: 0.33, blue: 0.92, alpha: 1),
        ] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    cg.restoreGState()

    func tile(_ rect: CGRect, radius: CGFloat, alpha: CGFloat) {
        cg.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        cg.setFillColor(CGColor(gray: 1, alpha: alpha))
        cg.fillPath()
    }
    // A laptop to the lower left of a monitor, in the proportions of a 16-inch MacBook Pro
    // beside a 27-inch display.
    let monitor = CGRect(x: 436, y: 393, width: 424, height: 238)
    tile(CGRect(x: 164, y: 446, width: 250, height: 162), radius: 30, alpha: 0.55)
    tile(monitor, radius: 36, alpha: 1)

    // The menu bar, to say which display is the main one.
    cg.saveGState()
    cg.addPath(CGPath(roundedRect: monitor, cornerWidth: 36, cornerHeight: 36, transform: nil))
    cg.clip()
    cg.setFillColor(CGColor(red: 0.13, green: 0.33, blue: 0.92, alpha: 0.22))
    cg.fill(CGRect(x: monitor.minX, y: monitor.minY, width: monitor.width, height: 30))
    cg.restoreGState()

    context.flushGraphics()
    NSGraphicsContext.current = nil
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
