import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, limited to ⌃⌥⇧⌘.
    var modifiers: UInt

    static let standard = Shortcut(keyCode: UInt32(kVK_ANSI_D), flags: [.control, .option, .command])

    init(keyCode: UInt32, flags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        modifiers = flags.intersection([.control, .option, .shift, .command]).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result = 0
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.shift) { result |= shiftKey }
        if flags.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    /// The keys in the order macOS menus show them, e.g. ["⌃", "⌥", "⌘", "D"].
    var keycaps: [String] {
        var caps: [String] = []
        if flags.contains(.control) { caps.append("⌃") }
        if flags.contains(.option) { caps.append("⌥") }
        if flags.contains(.shift) { caps.append("⇧") }
        if flags.contains(.command) { caps.append("⌘") }
        caps.append(Self.keyName(keyCode))
        return caps
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// The character printed on the key in the current keyboard layout.
    private static func keyName(_ keyCode: UInt32) -> String {
        if let name = namedKeys[Int(keyCode)] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "?" }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = layoutData.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

/// A single system-wide hot key, via Carbon — the one hot key API that needs no
/// Accessibility or Input Monitoring permission.
@MainActor
final class HotKey {
    static let shared = HotKey()

    var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register(_ shortcut: Shortcut?) {
        unregister()
        guard let shortcut else { return }
        installEventHandler()
        let id = EventHotKeyID(signature: OSType(0x464C_5053), id: 1)  // 'FLPS'
        RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { HotKey.shared.handler?() }
                }
                return noErr
            },
            1, &spec, nil, &eventHandler
        )
    }
}
