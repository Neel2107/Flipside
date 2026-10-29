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

    func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    func rgb(_ hex: UInt32) -> CGColor {
        CGColor(
            red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
    /// Fills `path` with a gradient running from `start` to `end`.
    func fill(_ path: CGPath, _ colors: [UInt32], from start: CGPoint, to end: CGPoint) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map(rgb) as CFArray, locations: nil)!
        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        cg.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    // A keycap, as on the website (website/src/components/Logo.astro): on the standard 824 pt
    // icon shape, a darker base for the key's sides and a lighter, smaller face on top.
    let base = rounded(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 32 * scale, color: CGColor(gray: 0, alpha: 0.28))
    cg.addPath(base)
    cg.setFillColor(rgb(0xBCB8AF))
    cg.fillPath()
    cg.restoreGState()
    fill(base, [0xCBC7BE, 0xACA79D], from: CGPoint(x: 512, y: 100), to: CGPoint(x: 512, y: 924))

    let face = CGRect(x: 128, y: 112, width: 768, height: 744)
    fill(rounded(face, 160), [0xFFFFFF, 0xE9E7E1], from: CGPoint(x: 512, y: face.minY), to: CGPoint(x: 512, y: face.maxY))
    cg.addPath(rounded(face.insetBy(dx: 1.5, dy: 1.5), 158.5))
    cg.setStrokeColor(CGColor(gray: 1, alpha: 0.7))
    cg.setLineWidth(3)
    cg.strokePath()

    // The legend: a monitor with the MacBook in orange to its lower left, in the proportions of a
    // 16-inch MacBook Pro beside a 27-inch display. Inset like a printed key's.
    cg.saveGState()
    cg.translateBy(x: 512, y: 482)
    cg.scaleBy(x: 0.84, y: 0.84)
    cg.translateBy(x: -512, y: -482)
    let macbook = CGRect(x: 183, y: 420, width: 236, height: 153)
    fill(rounded(macbook, 28), [0xFF8A55, 0xFF5B1F], from: macbook.origin, to: CGPoint(x: macbook.minX + 0.3 * macbook.width, y: macbook.maxY))
    cg.addPath(rounded(CGRect(x: 441, y: 370, width: 400, height: 224), 34))
    cg.setFillColor(rgb(0x232323))
    cg.fillPath()
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
