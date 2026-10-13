import FlipsideCore
import SwiftUI

/// The panel that drops down from the menu bar icon.
struct PanelView: View {
    let model: AppModel
    var pick: (Slot) -> Void
    var setRecording: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            cards
            note
            Divider()
                .padding(.vertical, 12)
            settings
            Divider()
                .padding(.top, 12)
                .padding(.bottom, 8)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(width: 316)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Arrangement")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 12)
            Text(statusLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusLine: String {
        switch model.setup {
        case .single: "No second display"
        case let .pair(anchor, _): anchor.name
        case .mirrored: "Mirroring"
        case let .unsupported(count): "\(count) displays"
        }
    }

    private var cards: some View {
        let placements = Slot.allCases.map { model.layouts[$0] }
        return HStack(spacing: 10) {
            ForEach(Slot.allCases) { slot in
                LayoutCard(
                    placement: model.layouts[slot],
                    geometry: model.geometry,
                    scaleWith: placements,
                    isActive: model.activeSlot == slot,
                    action: { pick(slot) }
                )
                .keyboardShortcut(KeyEquivalent(Character("\(slot.rawValue + 1)")), modifiers: [])
                .contextMenu {
                    Button("Use Current Arrangement") { model.capture(into: slot) }
                        .disabled(model.currentPlacement == nil || model.activeSlot == slot)
                    Button("Reset to Default") { model.reset(slot) }
                        .disabled(model.layouts[slot] == Layouts.standard[slot])
                }
            }
        }
        .disabled(model.setup.pair == nil)
    }

    @ViewBuilder private var note: some View {
        if let error = model.errorMessage {
            caption(error, symbol: "exclamationmark.triangle.fill", tint: .orange)
        } else {
            switch model.setup {
            case .single:
                caption("Connect a second display to switch arrangements.", symbol: "display")
            case .mirrored:
                caption("Your displays are mirrored. Turn mirroring off to arrange them.", symbol: "rectangle.on.rectangle")
            case .unsupported:
                caption("Flipside arranges two displays at a time.", symbol: "display.2")
            case .pair:
                if model.activeSlot == nil { saveBanner }
            }
        }
    }

    private func caption(_ text: String, symbol: String, tint: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
        .padding(.top, 10)
    }

    /// Shown when the arrangement on screen is neither saved layout, which is the moment
    /// someone who just dragged displays around in System Settings wants to keep it.
    private var saveBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.dashed")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("Custom arrangement")
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                ForEach(Slot.allCases) { slot in
                    Button("Replace “\(model.layouts[slot].title)”") { model.capture(into: slot) }
                }
            } label: {
                Text("Save as").font(.system(size: 11.5, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 11))
        .padding(.top, 10)
    }

    private var settings: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Flip shortcut")
                    Text("or right-click the menu bar icon")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ShortcutRecorder(
                    shortcut: model.shortcut,
                    isPanelOpen: model.isPanelOpen,
                    set: model.setShortcut,
                    setRecording: setRecording
                )
            }
            HStack {
                Text("Launch at login")
                Spacer()
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .font(.system(size: 12.5))
    }

    private var footer: some View {
        HStack {
            Button("Display Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(QuietButtonStyle())
        // Let the button labels, not their hover backgrounds, line up with the content above.
        .padding(.horizontal, -7)
    }
}

private struct LayoutCard: View {
    var placement: Placement
    var geometry: PreviewGeometry
    var scaleWith: [Placement]
    var isActive: Bool
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ArrangementDiagram(
                    placement: placement,
                    geometry: geometry,
                    palette: isActive ? .active : .idle,
                    scaleWith: scaleWith
                )
                .frame(height: 70)

                VStack(alignment: .leading, spacing: 1) {
                    Text(placement.title)
                        .font(.system(size: 12.5, weight: .medium))
                    Text(placement.detail(for: geometry.satelliteLabel))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(background))
            .overlay(shape.strokeBorder(Color.accentColor.opacity(isActive ? 0.9 : 0), lineWidth: 1.5))
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(7)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(PressableCardStyle())
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .accessibilityLabel("\(placement.title), \(placement.detail(for: geometry.satelliteLabel))")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var background: Color {
        if isActive { return .accentColor.opacity(0.14) }
        return .primary.opacity(isHovering && isEnabled ? 0.1 : 0.055)
    }
}

private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : isHovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

/// Shows the flip shortcut as keycaps; click it and press a new combination to change it.
private struct ShortcutRecorder: View {
    var shortcut: Shortcut?
    var isPanelOpen: Bool
    var set: (Shortcut?) -> Void
    var setRecording: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { isRecording ? stop() : start() }) {
            HStack(spacing: 3) {
                if isRecording {
                    Text("Type shortcut")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 4)
                } else if let shortcut {
                    ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in
                        Text(cap)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, cap.count > 1 ? 4 : 0)
                            .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(Color.primary.opacity(0.1)))
                    }
                } else {
                    Text("Record")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .frame(minHeight: 24)
            .padding(.horizontal, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isRecording ? 0.9 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press a shortcut. Esc cancels, Delete removes it." : "Click to change the shortcut")
        .onChange(of: isPanelOpen) { _, open in
            if !open { stop() }
        }
    }

    private func start() {
        isRecording = true
        setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        setRecording(false)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        switch Int(event.keyCode) {
        case 53 where flags.isEmpty:  // Esc
            stop()
        case 51 where flags.isEmpty, 117 where flags.isEmpty:  // Delete, Forward Delete
            set(nil)
            stop()
        default:
            // A global shortcut on a bare or shifted key would swallow ordinary typing.
            guard !flags.intersection([.control, .option, .command]).isEmpty else {
                NSSound.beep()
                return
            }
            set(Shortcut(keyCode: UInt32(event.keyCode), flags: flags))
            stop()
        }
    }
}
