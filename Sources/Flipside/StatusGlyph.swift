import AppKit
import FlipsideCore

/// The menu bar icon: a solid monitor and an outlined laptop, drawn in the current arrangement.
enum StatusGlyph {
    static let canvas = CGSize(width: 23, height: 16)
    private static let monitor = CGSize(width: 13, height: 8)
    private static let laptop = CGSize(width: 7.5, height: 5)
    private static let gap: CGFloat = 1.5

    struct Frames: Equatable {
        var monitor: CGRect
        var laptop: CGRect

        func mixed(with other: Frames, by t: CGFloat) -> Frames {
            Frames(monitor: Self.mix(monitor, other.monitor, t), laptop: Self.mix(laptop, other.laptop, t))
        }

        private static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
            CGRect(
                x: a.minX + (b.minX - a.minX) * t,
                y: a.minY + (b.minY - a.minY) * t,
                width: a.width + (b.width - a.width) * t,
                height: a.height + (b.height - a.height) * t
            )
        }
    }

    static func frames(for placement: Placement) -> Frames {
        // Keep the laptop within the monitor's extent so an unusual arrangement still fits.
        let clamped = Placement(edge: placement.edge, align: min(max(placement.align, 0), 1))
        var offset = clamped.offset(anchor: monitor, satellite: laptop)
        switch placement.edge {
        case .left: offset.x -= gap
        case .right: offset.x += gap
        case .above: offset.y -= gap
        case .below: offset.y += gap
        }

        let monitorFrame = CGRect(origin: .zero, size: monitor)
        let laptopFrame = CGRect(origin: offset, size: laptop)
        let union = monitorFrame.union(laptopFrame)
        // Snap to half points so edges stay crisp on Retina displays.
        let dx = (((canvas.width - union.width) / 2 - union.minX) * 2).rounded() / 2
        let dy = (((canvas.height - union.height) / 2 - union.minY) * 2).rounded() / 2
        return Frames(monitor: monitorFrame.offsetBy(dx: dx, dy: dy), laptop: laptopFrame.offsetBy(dx: dx, dy: dy))
    }

    static func image(_ frames: Frames) -> NSImage {
        let image = NSImage(size: canvas, flipped: true) { _ in
            NSColor.black.set()
            let outline = NSBezierPath(roundedRect: frames.laptop.insetBy(dx: 0.6, dy: 0.6), xRadius: 1.25, yRadius: 1.25)
            outline.lineWidth = 1.2
            outline.stroke()

            // Mid-morph the laptop passes behind the monitor's corner; clear a gap around the
            // monitor so the two shapes never merge into a blob.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: frames.monitor.insetBy(dx: -gap, dy: -gap), xRadius: 3, yRadius: 3).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver

            NSBezierPath(roundedRect: frames.monitor, xRadius: 1.75, yRadius: 1.75).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
