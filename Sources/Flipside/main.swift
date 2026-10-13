import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would just put a duplicate icon in the menu bar.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSApp.terminate(nil)
            return
        }

        let model = AppModel()
        let controller = StatusItemController(model: model)
        self.model = model
        self.controller = controller

        HotKey.shared.handler = { [weak controller] in controller?.flip() }
        HotKey.shared.register(model.shortcut)
        model.shortcutDidChange = { HotKey.shared.register($0) }

        // Fires when a display is plugged in, unplugged, or rearranged by anything at all.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak model] _ in
            MainActor.assumeIsolated { model?.refresh() }
        }
    }
}

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--render-previews"), arguments.indices.contains(flag + 1) {
        Previews.render(into: URL(fileURLWithPath: arguments[flag + 1], isDirectory: true))
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // `run()` never returns, which keeps `delegate` alive for the app's lifetime.
    app.run()
}
