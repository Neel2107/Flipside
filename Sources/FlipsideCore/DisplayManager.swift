import AppKit
import CoreGraphics

public struct Display: Equatable, Identifiable, Sendable {
    public let id: CGDirectDisplayID
    public var name: String
    public var isBuiltin: Bool
    /// The main display carries the menu bar and sits at the origin of global coordinates.
    public var isMain: Bool
    /// Bounds in global display coordinates: points, origin at the main display's top left, y down.
    public var frame: CGRect

    public init(id: CGDirectDisplayID, name: String, isBuiltin: Bool, isMain: Bool, frame: CGRect) {
        self.id = id
        self.name = name
        self.isBuiltin = isBuiltin
        self.isMain = isMain
        self.frame = frame
    }
}

public enum DisplaySetup: Equatable, Sendable {
    case single(Display)
    /// Two extended displays. The satellite is the one Flipside moves around the anchor: the
    /// built-in display when there is one, otherwise whichever display isn't main.
    case pair(anchor: Display, satellite: Display)
    case mirrored
    case unsupported(count: Int)

    public var pair: (anchor: Display, satellite: Display)? {
        if case let .pair(anchor, satellite) = self { return (anchor, satellite) }
        return nil
    }

    /// How the satellite currently sits against the anchor.
    public var placement: Placement? {
        pair.flatMap { Placement(anchor: $0.anchor.frame, satellite: $0.satellite.frame) }
    }
}

public struct DisplayError: Error, Equatable {
    public let code: CGError
}

public enum DisplayManager {
    public static func currentSetup() -> DisplaySetup {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        ids = Array(ids.prefix(Int(count)))

        let names = screenNames()
        let main = CGMainDisplayID()
        let displays = ids.map { id in
            let builtin = CGDisplayIsBuiltin(id) != 0
            return Display(
                id: id,
                name: names[id] ?? (builtin ? "Built-in Display" : "External Display"),
                isBuiltin: builtin,
                isMain: id == main,
                frame: CGDisplayBounds(id)
            )
        }
        return setup(from: displays, mirrored: ids.contains { CGDisplayIsInMirrorSet($0) != 0 })
    }

    public static func setup(from displays: [Display], mirrored: Bool) -> DisplaySetup {
        switch displays.count {
        case 1:
            return .single(displays[0])
        case 2:
            if mirrored { return .mirrored }
            let builtins = displays.filter(\.isBuiltin)
            let satellite = builtins.count == 1 ? builtins[0] : (displays.first { !$0.isMain } ?? displays[1])
            let anchor = displays.first { $0.id != satellite.id } ?? displays[0]
            return .pair(anchor: anchor, satellite: satellite)
        default:
            return .unsupported(count: displays.count)
        }
    }

    /// The global origins that realise `placement` while leaving the main display where it is,
    /// so the menu bar and Dock don't jump to the other screen.
    public static func origins(
        for placement: Placement,
        anchor: Display,
        satellite: Display
    ) -> [(id: CGDirectDisplayID, origin: CGPoint)] {
        let offset = placement.offset(anchor: anchor.frame.size, satellite: satellite.frame.size)
        if satellite.isMain {
            return [(satellite.id, .zero), (anchor.id, CGPoint(x: -offset.x, y: -offset.y))]
        }
        return [(anchor.id, .zero), (satellite.id, offset)]
    }

    /// Rearranges the two displays. `.permanently` is what System Settings uses: the arrangement
    /// is remembered for this pair of displays across restarts and reconnects.
    public static func apply(
        _ placement: Placement,
        anchor: Display,
        satellite: Display,
        option: CGConfigureOption = .permanently
    ) throws {
        var config: CGDisplayConfigRef?
        var status = CGBeginDisplayConfiguration(&config)
        guard status == .success, let config else { throw DisplayError(code: status) }

        for (id, origin) in origins(for: placement, anchor: anchor, satellite: satellite) {
            status = CGConfigureDisplayOrigin(config, id, Int32(origin.x), Int32(origin.y))
            guard status == .success else {
                CGCancelDisplayConfiguration(config)
                throw DisplayError(code: status)
            }
        }

        status = CGCompleteDisplayConfiguration(config, option)
        guard status == .success else { throw DisplayError(code: status) }
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? NSNumber {
                names[number.uint32Value] = screen.localizedName
            }
        }
        return names
    }
}
