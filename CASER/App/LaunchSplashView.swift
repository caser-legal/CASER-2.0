import SwiftUI

struct LaunchSplashView: View {
    var onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.94
    @State private var logoOpacity: Double = 0
    @State private var exitOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MainBackground()

            VStack(spacing: 6) {
                Image("logo-main")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 148)
                    .shadow(color: .black.opacity(0.55), radius: 20)
                    .accessibilityLabel("CASER")
                BrandTagline()
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
        }
        .opacity(exitOpacity)
        .allowsHitTesting(exitOpacity > 0.01)
        .task { await runLaunchSequence() }
    }

    @MainActor
    private func runLaunchSequence() async {
        if reduceMotion {
            logoScale = 1
            logoOpacity = 1
            try? await Task.sleep(for: .milliseconds(700))
        } else {
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeInOut(duration: 0.9)) {
                logoScale = 1
                logoOpacity = 1
            }
            try? await Task.sleep(for: .milliseconds(1900))
        }

        withAnimation(.easeInOut(duration: 0.5)) {
            exitOpacity = 0
            logoOpacity = 0
        }
        try? await Task.sleep(for: .milliseconds(520))
        onComplete()
    }
}
