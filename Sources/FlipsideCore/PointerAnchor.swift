import CoreGraphics

/// The pointer's position relative to the display it is on.
///
/// Rearranging displays shifts their global coordinates but leaves the pointer's global position
/// as it was. If the pointer was on the display that moved, it ends up over the other screen or
/// over no screen at all, and jumps the next time the mouse moves. Capturing this first lets the
/// pointer be put back on the same spot of the same display afterwards.
public struct PointerAnchor: Equatable, Sendable {
    public let display: CGDirectDisplayID
    /// Distance from the display's top-left corner, in points.
    public let offset: CGPoint

    public init(display: CGDirectDisplayID, offset: CGPoint) {
        self.display = display
        self.offset = offset
    }

    /// Nil when the pointer is not over any display.
    public static func capture() -> PointerAnchor? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(location, 1, &display, &count) == .success, count > 0 else { return nil }
        let bounds = CGDisplayBounds(display)
        return PointerAnchor(
            display: display,
            offset: CGPoint(x: location.x - bounds.minX, y: location.y - bounds.minY)
        )
    }

    /// Where the pointer belongs once its display occupies `bounds`.
    public func location(in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y)
    }

    /// Moves the pointer back to its spot if its display has moved out from under it.
    public func restore() {
        guard CGDisplayIsOnline(display) != 0 else { return }
        let target = location(in: CGDisplayBounds(display))
        guard CGEvent(source: nil)?.location != target else { return }
        CGWarpMouseCursorPosition(target)
        // A warp otherwise freezes pointer movement for a quarter of a second.
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
