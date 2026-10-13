import AppKit
import FlipsideCore
import SwiftUI

/// Development aid: `Flipside --render-previews <dir>` writes PNGs of the panel, HUD and menu
/// bar glyph in each state, so the design can be checked without the hardware for every case.
@MainActor
enum Previews {
    static func render(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let dell = CGSize(width: 2560, height: 1440)
        let macbook = CGSize(width: 1512, height: 982)
        let external = Display(id: 2, name: "DELL S2725QC", isBuiltin: false, isMain: true, frame: CGRect(origin: .zero, size: dell))
        func builtin(at origin: CGPoint, isMain: Bool) -> Display {
            Display(id: 1, name: "Built-in Display", isBuiltin: true, isMain: isMain, frame: CGRect(origin: origin, size: macbook))
        }
        func pair(_ placement: Placement) -> DisplaySetup {
            let offset = placement.offset(anchor: dell, satellite: macbook)
            return .pair(anchor: external, satellite: builtin(at: offset, isMain: false))
        }
        let laptop = builtin(at: .zero, isMain: true)

        let states: [(String, AppModel)] = [
            ("side", AppModel(preview: pair(Layouts.standard.first))),
            ("stacked", AppModel(preview: pair(Layouts.standard.second))),
            ("custom", AppModel(preview: pair(Placement(edge: .right, align: 0)))),
            ("single", AppModel(preview: .single(laptop))),
            ("error", AppModel(preview: pair(Layouts.standard.first), error: "macOS wouldn't change the arrangement (error 1001).")),
        ]
        for (name, model) in states {
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = appearance == .aqua ? "light" : "dark"
                let panel = PanelView(model: model, pick: { _ in })
                    .background(Color(nsColor: .windowBackgroundColor))
                write(panel, appearance: appearance, to: directory.appendingPathComponent("panel-\(name)-\(suffix).png"))
            }
        }

        let hud = HUDController.previewContent(
            showing: Layouts.standard.second,
            geometry: PreviewGeometry(anchor: external, satellite: laptop)
        )
        write(hud.padding(24).background(Color(white: 0.55)), appearance: .darkAqua, to: directory.appendingPathComponent("hud.png"))

        write(glyphSheet, appearance: .aqua, to: directory.appendingPathComponent("glyphs.png"))
    }

    /// The menu bar glyph at rest in both arrangements and mid-morph, at actual size and enlarged.
    private static var glyphSheet: some View {
        let side = StatusGlyph.frames(for: Layouts.standard.first)
        let stacked = StatusGlyph.frames(for: Layouts.standard.second)
        let steps = [side, side.mixed(with: stacked, by: 0.5), stacked, StatusGlyph.frames(for: Placement(edge: .right, align: 0.5))]
        return VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                HStack(spacing: 24) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, frames in
                        let image = Image(nsImage: StatusGlyph.image(frames)).renderingMode(.template)
                        image.frame(width: 22, height: 16)
                        image.resizable().interpolation(.high).frame(width: 110, height: 80)
                    }
                }
                .padding(20)
                .foregroundStyle(dark ? Color.white : Color.black)
                .background(dark ? Color(white: 0.18) : Color(white: 0.9))
            }
        }
    }

    private static func write(_ view: some View, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)

        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}
