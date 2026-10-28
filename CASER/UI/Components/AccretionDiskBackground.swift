import SwiftUI

struct AccretionDiskBackground: View {
    var opacity: Double = 1
    var glow: CGFloat = 1
    var spinSpeed: Double = 52
    var scale: CGFloat = 1

    @State private var isOnScreen = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let paused = !isOnScreen || scenePhase != .active || reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: paused)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            BlackHoleAccretionView(
                rotation: paused ? spinSpeed * 0.42 : (seconds * spinSpeed * 0.42).truncatingRemainder(dividingBy: 360 * 1000),
                glow: glow
            )
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(scale)
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BlackHoleAccretionView: View {
    let rotation: Double
    let glow: CGFloat

    private struct OrbitalTrail {
        let speed: Double
        let phase: Double
        let semiMajorAxis: CGFloat
        let eccentricity: Double
        let inclination: Double
        let ascendingNode: Double
        let nodeDrift: Double
        let trailSweep: Double
        let opacity: Double
    }

    private let orbitalTrails: [OrbitalTrail] = [
        OrbitalTrail(
            speed: 0.46,
            phase: 24,
            semiMajorAxis: 126,
            eccentricity: 0.16,
            inclination: 67,
            ascendingNode: 8,
            nodeDrift: 0.035,
            trailSweep: 92,
            opacity: 0.29
        ),
        OrbitalTrail(
            speed: -0.31,
            phase: 173,
            semiMajorAxis: 145,
            eccentricity: 0.08,
            inclination: 52,
            ascendingNode: 119,
            nodeDrift: -0.018,
            trailSweep: 126,
            opacity: 0.23
        ),
        OrbitalTrail(
            speed: 0.19,
            phase: 286,
            semiMajorAxis: 160,
            eccentricity: 0.23,
            inclination: 76,
            ascendingNode: 237,
            nodeDrift: 0.012,
            trailSweep: 74,
            opacity: 0.18
        ),
    ]

    private let orbitalCount = 7

    private func ringYellow(_ opacity: Double) -> Color {
        Color.caserAccent.opacity(opacity)
    }

    private func orbitalStrokeGradient(peakOpacity: Double) -> AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                ringYellow(peakOpacity * 0.12),
                ringYellow(peakOpacity * 0.40),
                ringYellow(peakOpacity * 0.56),
                ringYellow(peakOpacity * 0.34),
                ringYellow(peakOpacity * 0.12),
                ringYellow(peakOpacity * 0.48),
                ringYellow(peakOpacity * 0.12),
            ]),
            center: .center
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ringYellow(0.16 * Double(glow)),
                            ringYellow(0.06 * Double(glow)),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 48,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .blur(radius: 18)

            ForEach(0..<orbitalCount, id: \.self) { index in
                let peakOpacity = 0.54 - Double(index) * 0.045
                Ellipse()
                    .stroke(
                        orbitalStrokeGradient(peakOpacity: peakOpacity),
                        lineWidth: max(1.0, 2.6 - CGFloat(index) * 0.22)
                    )
                    .frame(
                        width: 168 + CGFloat(index) * 30,
                        height: 58 + CGFloat(index) * 10
                    )
                    .rotationEffect(.degrees(rotation + Double(index) * (360.0 / Double(orbitalCount)) * 0.72))
                    .blur(radius: CGFloat(index) * 0.32)
            }

            Canvas { context, size in
                for orbit in orbitalTrails {
                    draw(orbit: orbit, in: &context, size: size)
                }
            }
            .frame(width: 360, height: 360)
        }
    }

    private func draw(
        orbit: OrbitalTrail,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let sampleCount = 54
        let direction = orbit.speed < 0 ? -1.0 : 1.0
        let headMeanAnomaly = degreesToRadians(rotation * orbit.speed + orbit.phase)
        let trailSweep = degreesToRadians(orbit.trailSweep)
        let node = degreesToRadians(orbit.ascendingNode + rotation * orbit.nodeDrift)
        var previousPoint: CGPoint?
        var previousDepth = 0.0

        for index in 0..<sampleCount {
            let progress = Double(index) / Double(sampleCount - 1)
            let meanAnomaly = headMeanAnomaly - direction * trailSweep * (1 - progress)
            let point = projectedPoint(
                meanAnomaly: meanAnomaly,
                orbit: orbit,
                ascendingNode: node,
                size: size
            )

            if let previousPoint {
                let depth = (previousDepth + point.depth) * 0.5
                let depthLight = 0.72 + 0.28 * ((depth + 1) * 0.5)
                let fade = pow(progress, 1.55)
                let opacity = orbit.opacity * fade * depthLight
                let lineWidth = 1.05 + CGFloat((depth + 1) * 0.24)
                var segment = Path()
                segment.move(to: previousPoint)
                segment.addLine(to: point.position)

                context.stroke(
                    segment,
                    with: .color(ringYellow(opacity * 0.2)),
                    style: StrokeStyle(lineWidth: lineWidth * 3.2, lineCap: .round)
                )
                context.stroke(
                    segment,
                    with: .color(ringYellow(opacity)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }

            previousPoint = point.position
            previousDepth = point.depth
        }
    }

    private func projectedPoint(
        meanAnomaly: Double,
        orbit: OrbitalTrail,
        ascendingNode: Double,
        size: CGSize
    ) -> (position: CGPoint, depth: Double) {
        let eccentricAnomaly = solveEccentricAnomaly(
            meanAnomaly: meanAnomaly,
            eccentricity: orbit.eccentricity
        )
        let xInPlane = cos(eccentricAnomaly) - orbit.eccentricity
        let yInPlane = sqrt(1 - orbit.eccentricity * orbit.eccentricity) * sin(eccentricAnomaly)
        let inclination = degreesToRadians(orbit.inclination)
        let inclinedY = yInPlane * cos(inclination)
        let depth = yInPlane * sin(inclination)
        let x = xInPlane * cos(ascendingNode) - inclinedY * sin(ascendingNode)
        let y = xInPlane * sin(ascendingNode) + inclinedY * cos(ascendingNode)
        let perspective = 1 + depth * 0.11
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

        return (
            CGPoint(
                x: center.x + CGFloat(x * perspective) * orbit.semiMajorAxis,
                y: center.y + CGFloat(y * perspective) * orbit.semiMajorAxis
            ),
            depth
        )
    }

    private func solveEccentricAnomaly(meanAnomaly: Double, eccentricity: Double) -> Double {
        var eccentricAnomaly = meanAnomaly
        for _ in 0..<5 {
            eccentricAnomaly -= (eccentricAnomaly - eccentricity * sin(eccentricAnomaly) - meanAnomaly)
                / (1 - eccentricity * cos(eccentricAnomaly))
        }
        return eccentricAnomaly
    }

    private func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

struct OnboardingAnimatedBackground: View {
    var body: some View {
        MainBackground()
    }
}

struct BrandAccretionHero: View {
    var logoHeight: CGFloat = 120
    var diskSize: CGFloat = 260
    var diskOpacity: Double = 0.62
    var glow: CGFloat = 0.85
    var spinSpeed: Double = 36
    var playLaunchAnimation: Bool = false
    var showsTagline: Bool = false

    @State private var logoScale: CGFloat = 1
    @State private var logoOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                Image("logo-main")
                    .resizable()
                    .scaledToFit()
                    .frame(height: logoHeight)
                    .shadow(color: .black.opacity(0.55), radius: 20)
                    .accessibilityLabel("CASER")
                if showsTagline {
                    BrandTagline()
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
        }
        .frame(minWidth: diskSize, maxWidth: .infinity, minHeight: diskSize, maxHeight: diskSize)
        .task(id: playLaunchAnimation) {
            guard playLaunchAnimation else { return }
            await runLaunchEntrance()
        }
    }

    @MainActor
    private func runLaunchEntrance() async {
        if reduceMotion {
            logoScale = 1
            logoOpacity = 1
            return
        }

        logoScale = 0.94
        logoOpacity = 0

        withAnimation(.easeInOut(duration: 0.9)) {
            logoScale = 1
            logoOpacity = 1
        }
    }
}

struct BrandTagline: View {
    var body: some View {
        Text(AppBranding.fullName)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
            .tracking(0.3)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 24)
    }
}
