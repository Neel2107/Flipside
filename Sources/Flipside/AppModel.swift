import AppKit
import FlipsideCore
import IOKit.ps
import Observation
import ServiceManagement

/// What the arrangement previews are drawn from. Remembered between launches so the cards keep
/// the right proportions while the external display is unplugged.
struct PreviewGeometry: Codable, Equatable {
    var anchorSize: CGSize
    var satelliteSize: CGSize
    var anchorIsMain: Bool
    var satelliteIsBuiltin: Bool
    var anchorName: String
    var satelliteName: String

    static let fallback = PreviewGeometry(
        anchorSize: CGSize(width: 2560, height: 1440),
        satelliteSize: CGSize(width: 1512, height: 982),
        anchorIsMain: true,
        satelliteIsBuiltin: true,
        anchorName: "External Display",
        satelliteName: "Built-in Display"
    )

    /// Short name for the display that moves, as in "MacBook on the left".
    var satelliteLabel: String {
        guard satelliteIsBuiltin else { return satelliteName }
        return Self.hasBattery ? "MacBook" : "Built-in display"
    }

    private static let hasBattery: Bool = {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        return sources.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
    }()
}

extension PreviewGeometry {
    init(anchor: Display, satellite: Display) {
        self.init(
            anchorSize: anchor.frame.size,
            satelliteSize: satellite.frame.size,
            anchorIsMain: anchor.isMain,
            satelliteIsBuiltin: satellite.isBuiltin,
            anchorName: anchor.name,
            satelliteName: satellite.name
        )
    }
}

extension Placement {
    var title: String { edge.isHorizontal ? "Side by side" : "Stacked" }

    func detail(for label: String) -> String {
        switch edge {
        case .left: "\(label) on the left"
        case .right: "\(label) on the right"
        case .above: "\(label) above"
        case .below: "\(label) below"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var setup: DisplaySetup
    private(set) var layouts: Layouts
    private(set) var geometry: PreviewGeometry
    private(set) var shortcut: Shortcut?
    private(set) var launchAtLogin = false
    private(set) var errorMessage: String?
    /// The arrangement last seen on screen, so the menu bar icon has something to show
    /// while only one display is connected.
    private(set) var lastPlacement: Placement
    var isPanelOpen = false

    /// Called whenever the arrangement on screen changes, whoever changed it.
    @ObservationIgnored var arrangementDidChange: (() -> Void)?
    @ObservationIgnored var shortcutDidChange: ((Shortcut?) -> Void)?

    @ObservationIgnored private let defaults: UserDefaults?

    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        layouts = Self.load("layouts", from: defaults) ?? .standard
        geometry = Self.load("geometry", from: defaults) ?? .fallback
        lastPlacement = Self.load("lastPlacement", from: defaults) ?? Layouts.standard.first
        shortcut = defaults.bool(forKey: "shortcutCleared") ? nil : Self.load("shortcut", from: defaults) ?? .standard
        setup = DisplayManager.currentSetup()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        remember()
    }

    /// A model over fixed data with no side effects, for rendering previews.
    init(preview setup: DisplaySetup, layouts: Layouts = .standard, error: String? = nil) {
        defaults = nil
        self.setup = setup
        self.layouts = layouts
        geometry = setup.pair.map { PreviewGeometry(anchor: $0.anchor, satellite: $0.satellite) } ?? .fallback
        lastPlacement = setup.placement ?? layouts.first
        shortcut = .standard
        errorMessage = error
    }

    var currentPlacement: Placement? { setup.placement }

    var activeSlot: Slot? {
        guard let pair = setup.pair else { return nil }
        let offset = CGPoint(
            x: pair.satellite.frame.minX - pair.anchor.frame.minX,
            y: pair.satellite.frame.minY - pair.anchor.frame.minY
        )
        return layouts.slot(matching: offset, anchor: pair.anchor.frame.size, satellite: pair.satellite.frame.size)
    }

    /// The slot a flip should go to: the other one, or the first when the arrangement is custom.
    var flipTarget: Slot { activeSlot?.other ?? .first }

    func refresh() {
        let fresh = DisplayManager.currentSetup()
        guard fresh != setup else { return }
        setup = fresh
        remember()
        arrangementDidChange?()
    }

    /// Switches to `slot`. Returns whether that arrangement is now on screen.
    @discardableResult
    func apply(_ slot: Slot) -> Bool {
        guard let pair = setup.pair else { return false }
        let pointer = PointerAnchor.capture()
        defer { pointer?.restore() }
        do {
            try DisplayManager.apply(layouts[slot], anchor: pair.anchor, satellite: pair.satellite)
            errorMessage = nil
        } catch let error as DisplayError {
            errorMessage = "macOS wouldn't change the arrangement (error \(error.code.rawValue))."
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
        if errorMessage == nil, activeSlot != slot {
            errorMessage = "macOS adjusted the arrangement, so it doesn't quite match this layout."
        }
        return activeSlot == slot
    }

    func capture(into slot: Slot) {
        guard let placement = currentPlacement else { return }
        layouts[slot] = placement
        errorMessage = nil
        save(layouts, as: "layouts")
    }

    func reset(_ slot: Slot) {
        layouts[slot] = Layouts.standard[slot]
        save(layouts, as: "layouts")
    }

    func setShortcut(_ new: Shortcut?) {
        shortcut = new
        defaults?.set(new == nil, forKey: "shortcutCleared")
        if let new { save(new, as: "shortcut") }
        shortcutDidChange?(new)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func remember() {
        if let pair = setup.pair {
            geometry = PreviewGeometry(anchor: pair.anchor, satellite: pair.satellite)
            save(geometry, as: "geometry")
        }
        if let placement = setup.placement {
            lastPlacement = placement
            save(placement, as: "lastPlacement")
        }
        if let pair = setup.pair, let placement = setup.placement, activeSlot == nil,
           layouts.adopt(placement, anchor: pair.anchor.frame.size, satellite: pair.satellite.frame.size) != nil {
            save(layouts, as: "layouts")
        }
    }

    private func save<Value: Encodable>(_ value: Value, as key: String) {
        guard let defaults, let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<Value: Decodable>(_ key: String, from defaults: UserDefaults) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}
