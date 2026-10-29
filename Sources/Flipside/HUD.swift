import AppKit
import FlipsideCore
import SwiftUI

/// A brief on-screen confirmation of a change of arrangement. Rearranging displays moves nothing
/// you can see, so without this a shortcut press would feel like it did nothing.
///
/// `display` is the screen to show it on: the one the pointer was on before the change, since
/// that is where the user is looking. Nil falls back to the main display.
@MainActor
final class HUDController {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?

    func show(from old: Placement?, to new: Placement, geometry: PreviewGeometry, on display: CGDirectDisplayID?) {
        present(HUDView(start: old ?? new, end: new, geometry: geometry), on: display)
    }

    func show(message: String, symbol: String, on display: CGDirectDisplayID?) {
        present(HUDMessage(message: message, symbol: symbol), on: display)
    }

    private func present(_ content: some View, on display: CGDirectDisplayID?) {
        dismissal?.cancel()

        // The material alone is nearly clear over busy windows; the tint keeps it readable.
        let host = NSHostingView(rootView: content.background(Color.black.opacity(0.45)))
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let effect = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        // The layer's corner radius clips the content but not the blur, which the window server
        // draws behind the window as a plain rectangle. Only a mask image rounds that too.
        effect.maskImage = Self.mask(size: size, cornerRadius: 22)
        host.frame = effect.bounds
        host.autoresizingMask = [.width, .height]
        effect.addSubview(host)
        panel.contentView = effect

        panel.setFrame(frame(for: size, on: display), display: true)
        // The shadow follows the window's opaque pixels, so it has to be redone for the new mask.
        panel.invalidateShadow()
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }

        let dismissal = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.3
                    panel.animator().alphaValue = 0
                },
                completionHandler: {
                    MainActor.assumeIsolated {
                        if panel.alphaValue == 0 { panel.orderOut(nil) }
                    }
                }
            )
        }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3, execute: dismissal)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }

    /// Opaque inside a continuous-cornered rounded rectangle, to match the layer's own corners.
    private static func mask(size: CGSize, cornerRadius: CGFloat) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(shape.cgPath)
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
    }

    /// Lower middle of `display`. Worked out from CoreGraphics rather than NSScreen, which can
    /// still describe the old arrangement for a moment after a change.
    private func frame(for size: CGSize, on display: CGDirectDisplayID?) -> CGRect {
        let main = CGDisplayBounds(CGMainDisplayID())
        let bounds = display.flatMap { CGDisplayIsOnline($0) != 0 ? CGDisplayBounds($0) : nil } ?? main
        let center = CGPoint(x: bounds.midX, y: bounds.minY + bounds.height * 0.78)
        // CoreGraphics measures down from the main display's top; AppKit up from its bottom.
        return CGRect(
            x: (center.x - size.width / 2).rounded(),
            y: (main.height - center.y - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
    }
}

private struct HUDView: View {
    var start: Placement
    var end: Placement
    var geometry: PreviewGeometry

    @State private var shown: Placement?

    var body: some View {
        VStack(spacing: 12) {
            ArrangementDiagram(
                placement: shown ?? start,
                geometry: geometry,
                palette: .hud,
                scaleWith: [start, end],
                cornerRadius: 5,
                motion: motion
            )
            .frame(width: 148, height: 84)

            Text(end.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .environment(\.colorScheme, .dark)
        .onAppear {
            // Show the old arrangement for a beat, then move into the new one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { shown = end }
        }
    }

    /// The displays first separate along one axis, then close in along the other, so they
    /// swing around each other's corner rather than cutting straight across it.
    private var motion: DiagramMotion {
        let lead = Animation.spring(response: 0.36, dampingFraction: 0.86)
        let follow = lead.delay(0.14)
        return end.edge.isHorizontal ? DiagramMotion(x: lead, y: follow) : DiagramMotion(x: follow, y: lead)
    }
}

private struct HUDMessage: View {
    var message: String
    var symbol: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
            Text(message)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .environment(\.colorScheme, .dark)
    }
}

extension HUDController {
    /// The HUD's content on its own, for rendering previews.
    static func previewContent(showing placement: Placement, geometry: PreviewGeometry) -> some View {
        HUDView(start: placement, end: placement, geometry: geometry)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(white: 0.16)))
    }
}
