import SwiftUI

struct AmbientDarkWallpaper: View {
    private struct ClusterSpec: Identifiable {
        let id: Int
        let anchor: CGPoint
        let extendsRight: Bool
        let spacing: CGFloat
        let dotCount: Int
        let phase: Double
        let cycles: Double
        let drift: CGVector
    }

    private struct ClusterDot: Identifiable {
        let id: Int
        let cluster: ClusterSpec
        let order: Int
        let coreDiameter: CGFloat
        let opacityScale: Double
    }

    private struct AmbientDot: Identifiable {
        let id: Int
        let position: CGPoint
        let drift: CGVector
        let diameter: CGFloat
        let phase: Double
        let cycles: Double
        let opacity: Double
    }

    private let clusters: [ClusterSpec] = [
        .init(id: 0, anchor: .init(x: 0.08, y: 0.11), extendsRight: true, spacing: 18, dotCount: 9, phase: 0.02, cycles: 1, drift: .init(dx: 0.018, dy: 0.012)),
        .init(id: 1, anchor: .init(x: 0.91, y: 0.20), extendsRight: false, spacing: 20, dotCount: 8, phase: 0.29, cycles: 1, drift: .init(dx: 0.016, dy: 0.014)),
        .init(id: 2, anchor: .init(x: 0.07, y: 0.39), extendsRight: true, spacing: 19, dotCount: 9, phase: 0.56, cycles: 1, drift: .init(dx: 0.020, dy: 0.012)),
        .init(id: 3, anchor: .init(x: 0.92, y: 0.48), extendsRight: false, spacing: 18, dotCount: 9, phase: 0.80, cycles: 1, drift: .init(dx: 0.018, dy: 0.013)),
        .init(id: 4, anchor: .init(x: 0.10, y: 0.67), extendsRight: true, spacing: 20, dotCount: 8, phase: 0.17, cycles: 1, drift: .init(dx: 0.017, dy: 0.014)),
        .init(id: 5, anchor: .init(x: 0.58, y: 0.055), extendsRight: false, spacing: 19, dotCount: 9, phase: 0.45, cycles: 1, drift: .init(dx: 0.020, dy: 0.011)),
        .init(id: 6, anchor: .init(x: 0.40, y: 0.28), extendsRight: true, spacing: 18, dotCount: 8, phase: 0.69, cycles: 1, drift: .init(dx: 0.017, dy: 0.013)),
    ]

    private var clusterDots: [ClusterDot] {
        clusters.flatMap { cluster in
            (0..<cluster.dotCount).map { order in
                let id = cluster.id * 100 + order
                return ClusterDot(
                    id: id,
                    cluster: cluster,
                    order: order,
                    coreDiameter: 8.5 + 3.2 * unit(id, salt: 0.31),
                    opacityScale: 0.86 + 0.14 * unitDouble(id, salt: 0.73)
                )
            }
        }
    }

    private var ambientDots: [AmbientDot] {
        (0..<32).map { id in
            AmbientDot(
                id: id,
                position: .init(
                    x: 0.025 + 0.95 * unit(id, salt: 0.11),
                    y: 0.035 + 0.93 * unit(id, salt: 0.67)
                ),
                drift: .init(
                    dx: 0.012 + 0.018 * unit(id, salt: 0.38),
                    dy: 0.009 + 0.016 * unit(id, salt: 0.84)
                ),
                diameter: 8 + 5 * unit(id, salt: 0.52),
                phase: unitDouble(id, salt: 0.26),
                cycles: id.isMultiple(of: 3) ? 2 : 1,
                opacity: 0.075 + 0.055 * unitDouble(id, salt: 0.94)
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            wallpaper(phase: 0.25, canvas: geometry.size)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func wallpaper(phase: Double, canvas: CGSize) -> some View {
        ZStack {
            Color(white: 21.0 / 255.0)

            ZStack {
                ForEach(ambientDots) { dot in
                    ambientLight(dot, phase: phase, canvas: canvas)
                }

                ForEach(clusterDots) { dot in
                    trailLight(dot, phase: phase, canvas: canvas)
                }
            }
            .compositingGroup()
            .opacity(0.82)
        }
    }

    private func fraction(_ value: Double) -> Double {
        value - floor(value)
    }

    private func unit(_ id: Int, salt: Double) -> CGFloat {
        CGFloat(unitDouble(id, salt: salt))
    }

    private func unitDouble(_ id: Int, salt: Double) -> Double {
        fraction(sin(Double(id + 1) * 12.9898 + salt * 78.233) * 43758.5453)
    }

    private func orthogonalPath(progress: Double, spacing: CGFloat, extendsRight: Bool) -> CGPoint {
        let direction: CGFloat = extendsRight ? 1 : -1
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: direction * spacing * 4.2, y: 0),
            CGPoint(x: direction * spacing * 4.2, y: spacing * 4.0),
            CGPoint(x: direction * spacing * 1.2, y: spacing * 4.0),
            CGPoint(x: direction * spacing * 1.2, y: spacing * 1.5),
            CGPoint(x: direction * spacing * 6.0, y: spacing * 1.5),
            CGPoint(x: direction * spacing * 6.0, y: spacing * 5.0),
        ]

        let scaled = min(max(progress, 0), 0.999_999) * Double(points.count - 1)
        let segment = min(Int(floor(scaled)), points.count - 2)
        let local = scaled - floor(scaled)
        let eased = CGFloat(local * local * (3 - 2 * local))
        let start = points[segment]
        let end = points[segment + 1]

        return CGPoint(
            x: start.x + (end.x - start.x) * eased,
            y: start.y + (end.y - start.y) * eased
        )
    }

    @ViewBuilder
    private func trailLight(_ dot: ClusterDot, phase: Double, canvas: CGSize) -> some View {
        let cluster = dot.cluster
        let theta = .pi * 2 * (phase * cluster.cycles + cluster.phase)
        let delayedTheta = theta - Double(dot.order) * 0.115

        let travel = 0.50 + 0.42 * sin(delayedTheta)
        let point = orthogonalPath(
            progress: travel,
            spacing: cluster.spacing,
            extendsRight: cluster.extendsRight
        )
        let groupDriftX = CGFloat(sin(theta * 0.5)) * canvas.width * cluster.drift.dx
        let groupDriftY = CGFloat(cos(theta * 0.5)) * canvas.height * cluster.drift.dy
        let breathe = 0.92 + 0.10 * CGFloat(sin(theta * 3 + Double(dot.order)))

        Circle()
            .fill(Color.white.opacity(0.17 * dot.opacityScale))
            .frame(width: dot.coreDiameter, height: dot.coreDiameter)
            .scaleEffect(breathe)
            .blur(radius: dot.coreDiameter * 0.46, opaque: false)
            .position(
                x: canvas.width * cluster.anchor.x + point.x + groupDriftX,
                y: canvas.height * cluster.anchor.y + point.y + groupDriftY
            )
    }

    @ViewBuilder
    private func ambientLight(_ dot: AmbientDot, phase: Double, canvas: CGSize) -> some View {
        let theta = .pi * 2 * (phase * dot.cycles + dot.phase)
        let x = canvas.width * (dot.position.x + dot.drift.dx * CGFloat(sin(theta)))
        let y = canvas.height * (dot.position.y + dot.drift.dy * CGFloat(cos(theta * 0.83)))
        let pulse = 0.45 + 0.55 * (0.5 + 0.5 * sin(theta * 1.7))

        Circle()
            .fill(Color.white.opacity(dot.opacity * pulse))
            .frame(width: dot.diameter, height: dot.diameter)
            .blur(radius: dot.diameter * 0.52, opaque: false)
            .position(x: x, y: y)
    }
}

#Preview("Ambient dark wallpaper") {
    AmbientDarkWallpaper()
}
