import AppKit
import FlipsideCore
import SwiftUI

/// Owns the menu bar icon: left-click opens the panel, right-click flips straight away.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let hud = HUDController()

    private var shownFrames: StatusGlyph.Frames
    private var iconTimer: Timer?
    private var popoverClosedAt = Date.distantPast

    init(model: AppModel) {
        self.model = model
        shownFrames = StatusGlyph.frames(for: model.lastPlacement)
        super.init()

        statusItem.autosaveName = "Flipside"
        if let button = statusItem.button {
            button.image = StatusGlyph.image(shownFrames)
            button.appearsDisabled = model.setup.pair == nil
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.toolTip = "Flipside — click to choose an arrangement, right-click to flip"
            button.setAccessibilityLabel("Flipside")
        }

        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(
            rootView: PanelView(
                model: model,
                pick: { [weak self] in self?.pick($0) },
                // Otherwise re-recording the current shortcut would fire it instead.
                setRecording: { recording in HotKey.shared.register(recording ? nil : model.shortcut) }
            )
        )
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        model.arrangementDidChange = { [weak self] in self?.updateIcon() }
    }

    /// Switches to the other arrangement without opening the panel.
    func flip() {
        popover.performClose(nil)
        model.refresh()
        // Read before the change: afterwards the pointer's coordinates may match no display.
        let screen = PointerAnchor.capture()?.display

        guard model.setup.pair != nil else {
            let message = model.setup == .mirrored ? "Displays are mirrored" : "No second display"
            hud.show(message: message, symbol: "display.trianglebadge.exclamationmark", on: screen)
            return
        }
        let before = model.currentPlacement
        let target = model.flipTarget
        if model.apply(target) {
            hud.show(from: before, to: model.layouts[target], geometry: model.geometry, on: screen)
        } else {
            hud.show(message: "Couldn't rearrange displays", symbol: "exclamationmark.triangle", on: screen)
        }
    }

    private func pick(_ slot: Slot) {
        let screen = PointerAnchor.capture()?.display
        let before = model.currentPlacement
        let isChange = model.activeSlot != slot
        // On failure the panel stays open to show why.
        guard model.apply(slot) else { return }
        if isChange {
            hud.show(from: before, to: model.layouts[slot], geometry: model.geometry, on: screen)
        }
        // Leave the panel up just long enough to see the selection land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.popover.performClose(nil)
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isAlternate = event?.type == .rightMouseDown
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true
        if isAlternate {
            flip()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // A click on the icon while the panel is open dismisses it (it's transient) and then
        // arrives here; without this the panel would close and immediately reopen.
        guard Date().timeIntervalSince(popoverClosedAt) > 0.25 else { return }

        model.refresh()
        model.isPanelOpen = true
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        popoverClosedAt = Date()
        model.isPanelOpen = false
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.appearsDisabled = model.setup.pair == nil

        let start = shownFrames
        let end = StatusGlyph.frames(for: model.lastPlacement)
        guard start != end else { return }

        // Morph the glyph from the old arrangement to the new one.
        iconTimer?.invalidate()
        let began = CACurrentMediaTime()
        let duration = 0.36
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                let t = min(1, (CACurrentMediaTime() - began) / duration)
                let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
                self.shownFrames = t < 1 ? start.mixed(with: end, by: eased) : end
                button.image = StatusGlyph.image(self.shownFrames)
                if t >= 1 { timer.invalidate() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        iconTimer = timer
    }
}
