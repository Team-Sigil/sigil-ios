import SwiftUI

/// The 16×16 pixel-art Sigil mark, drawn from the same rect paths as the design.
struct SigilMark: View {
    var size: CGFloat = 24

    private struct Layer {
        let color: Color
        let rects: [CGRect]
    }

    private static let layers: [Layer] = [
        (0x2A1250, "M5 0h6v1H5zM3 1h10v1H3zM2 2h12v1H2zM1 3h14v2H1zM0 5h16v6H0zM1 11h14v2H1zM2 13h12v1H2zM3 14h10v1H3zM5 15h6v1H5z"),
        (0x8B5CF6, "M5 1h6v1H5zM3 2h10v1H3zM2 3h12v2H2zM1 5h14v6H1zM2 11h12v2H2zM3 13h10v1H3zM5 14h6v1H5z"),
        (0xC4B0FF, "M5 1h3v1H5zM3 2h2v1H3zM2 3h1v2H2zM1 5h1v3H1z"),
        (0x5B2BC4, "M14 8h1v3h-1zM13 11h1v2h-1zM11 13h2v1h-2zM8 14h3v1H8z"),
        (0x6D3FD9, "M5 3h6v1H5zM4 4h1v1H4zM11 4h1v1h-1zM3 5h1v6H3zM12 5h1v6h-1zM4 11h1v1H4zM11 11h1v1h-1zM5 12h6v1H5z"),
        (0x3B1580, "M7 4h2v1H7zM6 5h4v1H6zM5 6h2v1H5zM6 7h4v1H6zM9 8h2v1H9zM6 9h4v1H6zM7 10h2v1H7z"),
        (0xEDE6FF, "M2 5h1v1H2zM6 2h1v1H6z"),
    ].map { hex, path in Layer(color: Color(hex: hex), rects: parse(path)) }

    /// Each subpath is `M{x} {y}h{w}v{h}…z`, so the first four numbers are a rect.
    private static func parse(_ path: String) -> [CGRect] {
        path.split(separator: "M").compactMap { segment in
            let numbers = segment.matches(of: /-?\d+/).compactMap { Int($0.output) }
            guard numbers.count >= 4 else { return nil }
            return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
        }
    }

    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 16
            for layer in Self.layers {
                for rect in layer.rects {
                    let scaled = CGRect(
                        x: rect.minX * unit,
                        y: rect.minY * unit,
                        width: rect.width * unit,
                        height: rect.height * unit
                    )
                    context.fill(Path(scaled), with: .color(layer.color))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Concentric orbit rings used as decoration on dark and accent cards.
struct OrbitRings: View {
    var radii: [CGFloat]
    var opacities: [Double]
    var dashedLast = true
    var color: Color = Palette.paper

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for (index, radius) in radii.enumerated() {
                let circle = Path(ellipseIn: CGRect(
                    x: center.x - radius, y: center.y - radius,
                    width: radius * 2, height: radius * 2
                ))
                let isDashed = dashedLast && index == radii.count - 1
                context.stroke(
                    circle,
                    with: .color(color.opacity(opacities[index])),
                    style: StrokeStyle(lineWidth: 1, dash: isDashed ? [2, 6] : [])
                )
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    SigilMark(size: 96)
}
