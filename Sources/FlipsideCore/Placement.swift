import CoreGraphics

/// The side of the anchor display that the satellite display sits on.
public enum Edge: String, Codable, CaseIterable, Sendable {
    case left, right, above, below

    public var isHorizontal: Bool { self == .left || self == .right }
}

/// Where one display (the satellite) sits relative to another (the anchor).
///
/// `align` is the satellite's position along the shared edge, as a fraction of the room it has
/// to slide: 0 is flush with the anchor's top (or left), 0.5 is centred, 1 is flush with the
/// bottom (or right). Storing a fraction rather than points keeps "centred" centred if either
/// display later changes resolution.
public struct Placement: Codable, Equatable, Sendable {
    public var edge: Edge
    public var align: Double

    public init(edge: Edge, align: Double) {
        self.edge = edge
        self.align = align
    }

    /// Describes how `satellite` currently sits against `anchor`, in global display coordinates.
    /// Returns nil when the two overlap, which only happens while mirroring.
    ///
    /// Two displays of equal length along the shared edge have no room to slide, so any offset
    /// between them is recorded as centred.
    public init?(anchor: CGRect, satellite: CGRect) {
        let edge: Edge
        if satellite.maxX <= anchor.minX {
            edge = .left
        } else if satellite.minX >= anchor.maxX {
            edge = .right
        } else if satellite.maxY <= anchor.minY {
            edge = .above
        } else if satellite.minY >= anchor.maxY {
            edge = .below
        } else {
            return nil
        }
        let room = edge.isHorizontal ? anchor.height - satellite.height : anchor.width - satellite.width
        let moved = edge.isHorizontal ? satellite.minY - anchor.minY : satellite.minX - anchor.minX
        self.init(edge: edge, align: room == 0 ? 0.5 : Double(moved / room))
    }

    /// The satellite's origin relative to the anchor's origin, in points with y pointing down.
    public func offset(anchor: CGSize, satellite: CGSize) -> CGPoint {
        switch edge {
        case .left:
            CGPoint(x: -satellite.width, y: slide(anchor.height - satellite.height))
        case .right:
            CGPoint(x: anchor.width, y: slide(anchor.height - satellite.height))
        case .above:
            CGPoint(x: slide(anchor.width - satellite.width), y: -satellite.height)
        case .below:
            CGPoint(x: slide(anchor.width - satellite.width), y: anchor.height)
        }
    }

    private func slide(_ room: CGFloat) -> CGFloat {
        (room * align).rounded()
    }
}
