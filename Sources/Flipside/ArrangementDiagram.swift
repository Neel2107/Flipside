import FlipsideCore
import SwiftUI

struct DiagramPalette {
    var anchor: Color
    var satellite: Color
    /// The menu bar strip on whichever display is main.
    var menuBar: Color

    static let active = DiagramPalette(
        anchor: .accentColor,
        satellite: .accentColor.opacity(0.5),
        menuBar: .white.opacity(0.5)
    )
    static let idle = DiagramPalette(
        anchor: .primary.opacity(0.4),
        satellite: .primary.opacity(0.2),
        menuBar: .white.opacity(0.35)
    )
    // The anchor is opaque here because the HUD animates, and the satellite slides behind it.
    static let hud = DiagramPalette(
        anchor: Color(white: 0.93),
        satellite: .white.opacity(0.5),
        menuBar: .black.opacity(0.22)
    )
}

/// How the tiles travel when the arrangement changes. Horizontal and vertical movement are
/// timed separately so one can lead the other.
struct DiagramMotion {
    var x: Animation
    var y: Animation
}

/// A to-scale picture of two displays in a given arrangement, like the one in System Settings.
struct ArrangementDiagram: View {
    var placement: Placement
    var geometry: PreviewGeometry
    var palette: DiagramPalette
    /// Arrangements that should all be drawn at one scale, so the displays stay the same size
    /// from one card to the next and while morphing between arrangements.
    var scaleWith: [Placement] = []
    var cornerRadius: CGFloat = 3.5
    /// Animates changes of `placement`; nil redraws without animation.
    var motion: DiagramMotion?

    var body: some View {
        GeometryReader { proxy in
            let frames = frames(in: proxy.size)
            ZStack(alignment: .topLeading) {
                // Satellite first, so that while the two trade places it passes behind the anchor.
                tile(palette.satellite, isMain: !geometry.anchorIsMain, frame: frames.satellite)
                tile(palette.anchor, isMain: geometry.anchorIsMain, frame: frames.anchor)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }

    private func tile(_ fill: Color, isMain: Bool, frame: CGRect) -> some View {
        DisplayTile(fill: fill, menuBar: isMain ? palette.menuBar : nil, cornerRadius: cornerRadius)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX)
            .animation(motion?.x, value: frame.minX)
            .offset(y: frame.minY)
            .animation(motion?.y, value: frame.minY)
    }

    private func bounds(for placement: Placement) -> (anchor: CGRect, satellite: CGRect) {
        let anchor = CGRect(origin: .zero, size: geometry.anchorSize)
        let offset = placement.offset(anchor: geometry.anchorSize, satellite: geometry.satelliteSize)
        return (anchor, CGRect(origin: offset, size: geometry.satelliteSize))
    }

    private func frames(in size: CGSize) -> (anchor: CGRect, satellite: CGRect) {
        let scale = ([placement] + scaleWith)
            .map { placement -> CGFloat in
                let union = bounds(for: placement).anchor.union(bounds(for: placement).satellite)
                return min(size.width / union.width, size.height / union.height)
            }
            .min() ?? 1

        let (anchor, satellite) = bounds(for: placement)
        let union = anchor.union(satellite)
        let shift = CGPoint(
            x: (size.width - union.width * scale) / 2 - union.minX * scale,
            y: (size.height - union.height * scale) / 2 - union.minY * scale
        )
        func fit(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX * scale + shift.x,
                y: rect.minY * scale + shift.y,
                width: rect.width * scale,
                height: rect.height * scale
            )
            // Displays touch in the real arrangement; a hairline of air reads better here.
            .insetBy(dx: 1, dy: 1)
        }
        return (fit(anchor), fit(satellite))
    }
}

private struct DisplayTile: View {
    var fill: Color
    var menuBar: Color?
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(fill)
            .overlay(alignment: .top) {
                if let menuBar {
                    menuBar.frame(height: 3)
                }
            }
            .clipShape(shape)
    }
}
