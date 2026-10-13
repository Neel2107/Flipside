import CoreGraphics
import Foundation
import Testing

@testable import FlipsideCore

// The sizes in the screenshots this app was built from: a Dell S2725QC at "looks like
// 2560 x 1440" and a 16-inch MacBook Pro at its default 1512 x 982.
private let dell = CGSize(width: 2560, height: 1440)
private let macbook = CGSize(width: 1512, height: 982)

private func display(_ id: UInt32, _ frame: CGRect, builtin: Bool = false, main: Bool = false) -> Display {
    Display(id: id, name: "Display \(id)", isBuiltin: builtin, isMain: main, frame: frame)
}

@Suite struct PlacementTests {
    @Test func standardLayoutsLandWhereTheScreenshotsShow() {
        // Measured from the screenshots at 6.67 pt per pixel, so good to about 7 pt.
        let side = Layouts.standard.first.offset(anchor: dell, satellite: macbook)
        #expect(side.x == -1512)
        #expect(abs(side.y - 320) <= 7)

        let stacked = Layouts.standard.second.offset(anchor: dell, satellite: macbook)
        #expect(stacked.y == 1440)
        #expect(abs(stacked.x - 573) <= 7)
    }

    @Test(arguments: [
        CGPoint(x: -1512, y: 0), CGPoint(x: -1512, y: 321), CGPoint(x: -1512, y: 458),
        CGPoint(x: 2560, y: 137), CGPoint(x: 2560, y: -200),
        CGPoint(x: 0, y: -982), CGPoint(x: 573, y: -982),
        CGPoint(x: 524, y: 1440), CGPoint(x: 1048, y: 1440), CGPoint(x: 1900, y: 1440),
    ])
    func capturingThenApplyingReproducesTheArrangementExactly(origin: CGPoint) throws {
        let anchor = CGRect(origin: .zero, size: dell)
        let satellite = CGRect(origin: origin, size: macbook)
        let placement = try #require(Placement(anchor: anchor, satellite: satellite))
        #expect(placement.offset(anchor: dell, satellite: macbook) == origin)
    }

    @Test func captureIsIndependentOfWhichDisplayIsAtTheOrigin() throws {
        // Same physical arrangement, once with the Dell as main and once with the MacBook.
        let dellMain = Placement(
            anchor: CGRect(origin: .zero, size: dell),
            satellite: CGRect(origin: CGPoint(x: -1512, y: 320), size: macbook))
        let macbookMain = Placement(
            anchor: CGRect(origin: CGPoint(x: 1512, y: -320), size: dell),
            satellite: CGRect(origin: .zero, size: macbook))
        #expect(dellMain != nil)
        #expect(dellMain == macbookMain)
    }

    @Test func overlappingDisplaysHaveNoPlacement() {
        let anchor = CGRect(origin: .zero, size: dell)
        #expect(Placement(anchor: anchor, satellite: CGRect(origin: .zero, size: macbook)) == nil)
    }

    @Test func equalLengthDisplaysAreTreatedAsCentred() throws {
        let anchor = CGRect(origin: .zero, size: dell)
        let twin = CGRect(origin: CGPoint(x: 2560, y: 0), size: dell)
        let placement = try #require(Placement(anchor: anchor, satellite: twin))
        #expect(placement == Placement(edge: .right, align: 0.5))
        #expect(placement.offset(anchor: dell, satellite: dell) == CGPoint(x: 2560, y: 0))
    }

    @Test func alignmentSurvivesAResolutionChange() {
        // Centred below at one resolution stays centred at another.
        let centred = Placement(edge: .below, align: 0.5)
        let fullHD = CGSize(width: 1920, height: 1080)
        #expect(centred.offset(anchor: fullHD, satellite: macbook) == CGPoint(x: 204, y: 1080))
    }
}

@Suite struct LayoutsTests {
    @Test func recognisesWhichSlotIsActive() {
        let layouts = Layouts.standard
        let side = layouts.first.offset(anchor: dell, satellite: macbook)
        let stacked = layouts.second.offset(anchor: dell, satellite: macbook)

        #expect(layouts.slot(matching: side, anchor: dell, satellite: macbook) == .first)
        #expect(layouts.slot(matching: stacked, anchor: dell, satellite: macbook) == .second)
        // A point of drift from macOS still counts...
        #expect(layouts.slot(matching: CGPoint(x: side.x, y: side.y + 1), anchor: dell, satellite: macbook) == .first)
        // ...but a hand-dragged arrangement doesn't.
        #expect(layouts.slot(matching: CGPoint(x: -1512, y: 0), anchor: dell, satellite: macbook) == nil)
    }

    @Test func shippedSlotSnapsToANearbyRealArrangement() throws {
        // The user's real side-by-side, a few points off the screenshot measurement.
        let real = try #require(Placement(
            anchor: CGRect(origin: .zero, size: dell),
            satellite: CGRect(origin: CGPoint(x: -1512, y: 327), size: macbook)))
        var layouts = Layouts.standard

        #expect(layouts.adopt(real, anchor: dell, satellite: macbook) == .first)
        #expect(layouts.first == real)
        #expect(layouts.second == Layouts.standard.second)
        #expect(layouts.slot(matching: CGPoint(x: -1512, y: 327), anchor: dell, satellite: macbook) == .first)
    }

    @Test func adoptionLeavesDeliberateArrangementsAlone() throws {
        func placement(_ origin: CGPoint) throws -> Placement {
            try #require(Placement(
                anchor: CGRect(origin: .zero, size: dell), satellite: CGRect(origin: origin, size: macbook)))
        }
        var layouts = Layouts.standard

        // Same side but top-aligned, or a different side altogether: not a near miss.
        #expect(layouts.adopt(try placement(CGPoint(x: -1512, y: 0)), anchor: dell, satellite: macbook) == nil)
        #expect(layouts.adopt(try placement(CGPoint(x: 2560, y: 319)), anchor: dell, satellite: macbook) == nil)
        #expect(layouts == .standard)

        // A slot the user saved themselves is never overwritten, however close.
        layouts[.first] = try placement(CGPoint(x: -1512, y: 300))
        let saved = layouts
        #expect(layouts.adopt(try placement(CGPoint(x: -1512, y: 310)), anchor: dell, satellite: macbook) == nil)
        #expect(layouts == saved)
    }

    @Test func slotsRoundTripThroughJSON() throws {
        var layouts = Layouts.standard
        layouts[.second] = Placement(edge: .right, align: 1)
        let decoded = try JSONDecoder().decode(Layouts.self, from: JSONEncoder().encode(layouts))
        #expect(decoded == layouts)
        #expect(decoded[.second].edge == .right)
        #expect(Slot.first.other == .second)
    }
}

@Suite struct DisplayManagerTests {
    private let external = display(2, CGRect(origin: .zero, size: dell), main: true)
    private let laptop = display(1, CGRect(origin: CGPoint(x: -1512, y: 320), size: macbook), builtin: true)

    @Test func builtinDisplayIsTheSatellite() {
        let setup = DisplayManager.setup(from: [laptop, external], mirrored: false)
        #expect(setup == .pair(anchor: external, satellite: laptop))
        #expect(setup.placement?.edge == .left)
    }

    @Test func withoutABuiltinTheNonMainDisplayIsTheSatellite() {
        let second = display(3, CGRect(origin: CGPoint(x: 2560, y: 0), size: dell))
        let setup = DisplayManager.setup(from: [external, second], mirrored: false)
        #expect(setup == .pair(anchor: external, satellite: second))
    }

    @Test func otherSetupsAreReportedNotGuessedAt() {
        #expect(DisplayManager.setup(from: [laptop], mirrored: false) == .single(laptop))
        #expect(DisplayManager.setup(from: [laptop, external], mirrored: true) == .mirrored)
        let third = display(3, CGRect(origin: CGPoint(x: 2560, y: 0), size: dell))
        #expect(DisplayManager.setup(from: [laptop, external, third], mirrored: false) == .unsupported(count: 3))
        #expect(DisplayManager.setup(from: [], mirrored: false) == .unsupported(count: 0))
    }

    @Test func mainDisplayStaysAtTheOriginWhenTheExternalIsMain() {
        let origins = DisplayManager.origins(for: Layouts.standard.second, anchor: external, satellite: laptop)
        #expect(origins.count == 2)
        #expect(origins[0].id == external.id)
        #expect(origins[0].origin == .zero)
        #expect(origins[1].id == laptop.id)
        #expect(origins[1].origin == CGPoint(x: 574, y: 1440))
    }

    @Test func mainDisplayStaysAtTheOriginWhenTheLaptopIsMain() {
        var mainLaptop = laptop
        mainLaptop.isMain = true
        mainLaptop.frame.origin = .zero
        var secondary = external
        secondary.isMain = false

        let origins = DisplayManager.origins(for: Layouts.standard.second, anchor: secondary, satellite: mainLaptop)
        #expect(origins[0].id == mainLaptop.id)
        #expect(origins[0].origin == .zero)
        // The Dell goes up and to the left by the same amount the laptop would have gone down and right.
        #expect(origins[1].id == secondary.id)
        #expect(origins[1].origin == CGPoint(x: -574, y: -1440))
    }
}

@Suite struct PointerAnchorTests {
    @Test func pointerFollowsItsDisplayToTheNewPosition() {
        // On the laptop while it sits to the left of the Dell...
        let anchor = PointerAnchor(display: 1, offset: CGPoint(x: 616, y: 923))
        #expect(anchor.location(in: CGRect(x: -1512, y: 319, width: 1512, height: 982)) == CGPoint(x: -896, y: 1242))
        // ...and still on the same spot of the laptop once it has moved underneath.
        #expect(anchor.location(in: CGRect(x: 574, y: 1440, width: 1512, height: 982)) == CGPoint(x: 1190, y: 2363))
    }
}
