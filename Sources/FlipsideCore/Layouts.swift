import CoreGraphics

/// Flipside keeps exactly two arrangements and flips between them.
public enum Slot: Int, CaseIterable, Codable, Identifiable, Sendable {
    case first, second

    public var id: Int { rawValue }
    public var other: Slot { self == .first ? .second : .first }
}

public struct Layouts: Codable, Equatable, Sendable {
    public var first: Placement
    public var second: Placement

    public init(first: Placement, second: Placement) {
        self.first = first
        self.second = second
    }

    /// The arrangements the app ships with: the built-in display to the lower left of the
    /// external one, and tucked underneath it a little right of centre.
    public static let standard = Layouts(
        first: Placement(edge: .left, align: 48.0 / 69.0),
        second: Placement(edge: .below, align: 86.0 / 157.0)
    )

    public subscript(slot: Slot) -> Placement {
        get { slot == .first ? first : second }
        set {
            if slot == .first { first = newValue } else { second = newValue }
        }
    }

    /// If `placement` is a near miss of a slot that still holds its shipped arrangement, makes
    /// that slot match it exactly and returns the slot.
    ///
    /// The shipped arrangements were measured off screenshots, so they can sit a few points away
    /// from the one the user really has. This closes that gap the first time their arrangement
    /// is seen, and never touches a slot they have saved themselves.
    public mutating func adopt(
        _ placement: Placement,
        anchor: CGSize,
        satellite: CGSize,
        within distance: CGFloat = 24
    ) -> Slot? {
        let actual = placement.offset(anchor: anchor, satellite: satellite)
        for slot in Slot.allCases where self[slot] == Self.standard[slot] && self[slot].edge == placement.edge {
            let shipped = self[slot].offset(anchor: anchor, satellite: satellite)
            if abs(shipped.x - actual.x) <= distance, abs(shipped.y - actual.y) <= distance {
                self[slot] = placement
                return slot
            }
        }
        return nil
    }

    /// The slot whose arrangement puts the satellite at `offset` from the anchor, if either does.
    /// macOS may nudge a requested origin by a point, hence the tolerance.
    public func slot(
        matching offset: CGPoint,
        anchor: CGSize,
        satellite: CGSize,
        tolerance: CGFloat = 2
    ) -> Slot? {
        Slot.allCases.first { slot in
            let wanted = self[slot].offset(anchor: anchor, satellite: satellite)
            return abs(wanted.x - offset.x) <= tolerance && abs(wanted.y - offset.y) <= tolerance
        }
    }
}
