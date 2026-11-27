import SwiftUI

enum SyntheticSpectrum {
    static func bands(t: Double, active: Bool, count: Int = SpectrumAnalyzer.bandCount) -> [Float] {
        guard active else { return [Float](repeating: 0.04, count: count) }
        let beat = pow(max(0, sin(t * 2 * Double.pi * 2.0)), 6)
        return (0..<count).map { i in
            let x = Double(i) / Double(count)
            let w1 = 0.5 + 0.5 * sin(t * (1.5 + x * 5) + Double(i) * 0.7)
            let w2 = 0.5 + 0.5 * sin(t * 2.3 + Double(i) * 1.9)
            let body = (0.25 + 0.45 * w1 * w2) * (1 - 0.55 * x)
            let kick = beat * (1 - x) * 0.5
            return Float(min(1, body + kick))
        }
    }
}

struct VisualizerView: View {
    @EnvironmentObject var store: NowPlayingStore

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let analyzer = SpectrumAnalyzer.shared
            let bands = analyzer.isLive ? analyzer.snapshot()
                                        : SyntheticSpectrum.bands(t: t, active: store.isPlaying)
            let bass = CGFloat(bands.prefix(6).reduce(0, +) / 6)
            let spin = store.position(at: tl.date) * 12  

            GeometryReader { geo in
                let m = min(geo.size.width, geo.size.height)
                ZStack {
                    Canvas { gc, size in
                        draw(&gc, size: size, bands: bands, bass: bass, t: t)
                    }
                    disc(diameter: m * 0.54 * (1 + bass * 0.05), spin: spin)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // MARK: Planet

    @ViewBuilder
    private func disc(diameter d: CGFloat, spin: Double) -> some View {
        Group {
            if let art = store.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                Circle().fill(LinearGradient(colors: [store.accent.opacity(0.8), .black],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
        .overlay(Circle().fill(.black.opacity(0.85)).frame(width: d * 0.08, height: d * 0.08))
        .rotationEffect(.degrees(spin))
        .shadow(color: store.accent.opacity(0.7), radius: 30)
    }

    // MARK: Rays + ring

    private func draw(_ gc: inout GraphicsContext, size: CGSize, bands: [Float], bass: CGFloat, t: Double) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let m = min(size.width, size.height)
        let r0 = m * 0.27 * (1 + bass * 0.05)
        let maxLen = m * 0.20
        let accent = store.accent
        let half = bands.count
        let total = half * 2

        // аура
        gc.fill(
            Path(ellipseIn: CGRect(x: c.x - r0 * 2, y: c.y - r0 * 2, width: r0 * 4, height: r0 * 4)),
            with: .radialGradient(Gradient(colors: [accent.opacity(0.25 + 0.3 * bass), .clear]),
                                  center: c, startRadius: r0 * 0.9, endRadius: r0 * 2)
        )

        var rays = Path()
        var ring = Path()
        for i in 0..<total {
            let k = i < half ? i : total - 1 - i          
            let prev = bands[max(0, k - 1)], next = bands[min(half - 1, k + 1)]
            let v = CGFloat((bands[k] * 2 + prev + next) / 4)

            let a = Double(i) / Double(total) * 2 * Double.pi - Double.pi / 2 + t * 0.05
            let dir = CGPoint(x: cos(a), y: sin(a))
            let start = r0 + 6
            let len = 4 + pow(v, 1.3) * maxLen

            rays.move(to: CGPoint(x: c.x + dir.x * start, y: c.y + dir.y * start))
            rays.addLine(to: CGPoint(x: c.x + dir.x * (start + len), y: c.y + dir.y * (start + len)))

            let rr = r0 + 2 + v * 6
            let p = CGPoint(x: c.x + dir.x * rr, y: c.y + dir.y * rr)
            if i == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
        }
        ring.closeSubpath()

        gc.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.stroke(rays, with: .color(accent), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [accent, .white]), center: c, startRadius: r0, endRadius: r0 + maxLen + 6)
        gc.stroke(rays, with: shading, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        gc.stroke(ring, with: .color(.white.opacity(0.55)), lineWidth: 1.2)
    }
}
