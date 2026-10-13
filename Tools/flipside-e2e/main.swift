import AppKit
import CVirtualDisplay
import FlipsideCore

// Exercises the real arrangement code against a temporary virtual display standing in for an
// external monitor.
//
//   flipside-e2e                    run the checks
//   flipside-e2e --stand-in <secs>  just provide the stand-in display, to try the app by hand
//   flipside-e2e --stand-in <secs> --at <x>,<y>
//                                   ...with the built-in display at that offset from it
//
// The virtual display disappears when this process exits. The checks apply arrangements for
// the session only, so they write nothing to the system's saved display preferences.

func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func waitFor(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(6)
    while Date() < deadline {
        if condition() { return true }
        pump(0.1)
    }
    return condition()
}

func describe(_ setup: DisplaySetup) -> String {
    switch setup {
    case let .single(display): "single: \(display.name) \(display.frame)"
    case let .pair(anchor, satellite):
        "pair: anchor \(anchor.name) \(anchor.frame)\(anchor.isMain ? " [main]" : ""), "
            + "satellite \(satellite.name) \(satellite.frame)\(satellite.isMain ? " [main]" : "")"
    case .mirrored: "mirrored"
    case let .unsupported(count): "unsupported (\(count) displays)"
    }
}

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "  ok    \(what)" : "  FAIL  \(what)")
    if !ok { failures += 1 }
}

let arguments = CommandLine.arguments
let standIn = arguments.firstIndex(of: "--stand-in").flatMap {
    arguments.indices.contains($0 + 1) ? TimeInterval(arguments[$0 + 1]) : nil
}

let before = DisplayManager.currentSetup()
print("before:  \(describe(before))")
guard case .single = before else {
    print("This check expects exactly one display to start with. Nothing was changed.")
    exit(2)
}

var virtualID: CGDirectDisplayID = 0
let virtualDisplay = FSCreateVirtualDisplay("Flipside Test Display", 2560, 1440, &virtualID)
guard virtualDisplay != nil else {
    print("Couldn't create a virtual display on this macOS version. Nothing was changed.")
    exit(3)
}

guard waitFor({ DisplayManager.currentSetup().pair != nil }) else {
    print("The virtual display never came online: \(describe(DisplayManager.currentSetup()))")
    exit(4)
}
pump(0.5)
print("with virtual display: \(describe(DisplayManager.currentSetup()))")

if let standIn {
    if let flag = arguments.firstIndex(of: "--at"), arguments.indices.contains(flag + 1),
       let pair = DisplayManager.currentSetup().pair {
        let parts = arguments[flag + 1].split(separator: ",").compactMap { Double($0) }
        let satellite = CGRect(origin: CGPoint(x: parts[0], y: parts[1]), size: pair.satellite.frame.size)
        if parts.count == 2, let placement = Placement(anchor: CGRect(origin: .zero, size: pair.anchor.frame.size), satellite: satellite) {
            try DisplayManager.apply(placement, anchor: pair.anchor, satellite: pair.satellite, option: .forSession)
        }
    }
    print("stand-in display is up for \(Int(standIn))s…")
    pump(standIn)
    exit(0)
}

let sequence: [(String, Placement)] = [
    ("side by side (default)", Layouts.standard.first),
    ("stacked (default)", Layouts.standard.second),
    ("side by side again", Layouts.standard.first),
    ("right, bottom-aligned", Placement(edge: .right, align: 1)),
    ("above, centred", Placement(edge: .above, align: 0.5)),
    ("stacked again", Layouts.standard.second),
]

for (name, placement) in sequence {
    guard let pair = DisplayManager.currentSetup().pair else {
        check(false, "\(name): lost the display pair")
        break
    }
    let mainBefore = pair.anchor.isMain ? pair.anchor.id : pair.satellite.id
    let wanted = placement.offset(anchor: pair.anchor.frame.size, satellite: pair.satellite.frame.size)
    do {
        try DisplayManager.apply(placement, anchor: pair.anchor, satellite: pair.satellite, option: .forSession)
    } catch {
        check(false, "\(name): apply threw \(error)")
        continue
    }
    // The app reads the result back straight away, so that has to work without waiting.
    let immediate = DisplayManager.currentSetup().pair.map {
        CGPoint(x: $0.satellite.frame.minX - $0.anchor.frame.minX, y: $0.satellite.frame.minY - $0.anchor.frame.minY)
    }
    check(immediate == wanted, "\(name): in place as soon as apply returns")
    pump(0.4)

    guard let after = DisplayManager.currentSetup().pair else {
        check(false, "\(name): no pair after applying")
        continue
    }
    let got = CGPoint(
        x: after.satellite.frame.minX - after.anchor.frame.minX,
        y: after.satellite.frame.minY - after.anchor.frame.minY
    )
    check(got == wanted, "\(name): satellite at \(got) relative to anchor, wanted \(wanted)")
    check(CGMainDisplayID() == mainBefore, "\(name): main display unchanged")
    check(Layouts(first: placement, second: placement).slot(
        matching: got, anchor: after.anchor.frame.size, satellite: after.satellite.frame.size) != nil,
        "\(name): recognised as the active layout")
    check(DisplayManager.currentSetup().placement == Placement(anchor: after.anchor.frame, satellite: after.satellite.frame),
        "\(name): captured placement reproduces \(placement.edge)")
}

print(failures == 0 ? "PASS" : "FAILED (\(failures))")
// Exiting is what removes the virtual display.
exit(failures == 0 ? 0 : 1)
