import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
@Observable
final class AppLockGate {
    enum State: Equatable {
        case idle
        case authenticating
        case authenticated
        case locked
        case failed(String)
    }

    var state: State = .locked

    let reason: String

    let backgroundTimeout: TimeInterval

    private var backgroundEnteredAt: ContinuousClock.Instant?

    init(
        reason: String = "Authenticate to unlock your saved cases, alerts, and search history.",
        backgroundTimeout: TimeInterval = 30
    ) {
        self.reason = reason
        self.backgroundTimeout = backgroundTimeout
    }

    func lock() {
        state = .locked
    }

    func handleBackground(now: ContinuousClock.Instant = .now) {
        backgroundEnteredAt = now
    }

    func handleForeground(now: ContinuousClock.Instant = .now) {
        defer { backgroundEnteredAt = nil }
        guard let entered = backgroundEnteredAt else { return }
        if entered.duration(to: now) > .seconds(backgroundTimeout) {
            state = .locked
        }
    }

    func authenticate() async {
        if state == .authenticating { return }
        state = .authenticating

        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"

        var policyError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &policyError
        ) else {
            if let policyError, policyError.domain == LAErrorDomain,
               policyError.code == LAError.Code.passcodeNotSet.rawValue {
                state = .authenticated
                return
            }
            let message = Self.message(for: policyError)
            state = .failed(message)
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if success {
                state = .authenticated
            } else {
                state = .failed("Authentication failed. Please try again.")
            }
        } catch let error as LAError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    nonisolated static func canEvaluateBiometrics() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        )
    }

    private static func message(for error: (any Error)?) -> String {
        guard let error else { return "Authentication is unavailable on this device." }
        if let laError = error as? LAError {
            switch laError.code {
            case .userCancel, .appCancel, .systemCancel:
                return "Authentication was cancelled. Tap Unlock to try again."
            case .userFallback:
                return "Use the device passcode to continue."
            case .biometryNotAvailable, .touchIDNotAvailable:
                return "Biometric authentication isn't available. Use your device passcode to continue."
            case .biometryNotEnrolled, .touchIDNotEnrolled:
                return "No biometrics are enrolled. Use your device passcode to continue."
            case .biometryLockout, .touchIDLockout:
                return "Biometrics are temporarily locked. Use your device passcode to continue."
            case .companionNotAvailable:
                return "A paired device is required to authenticate. Use your device passcode to continue."
            case .passcodeNotSet:
                return "Set a device passcode in Settings to use CASER."
            case .authenticationFailed:
                return "Authentication failed. Please try again."
            case .invalidContext:
                return "Authentication is not available right now. Please try again."
            case .notInteractive:
                return "Authentication requires your attention. Please try again."
            case .invalidDimensions:
                return "Authentication input was invalid. Please try again."
            @unknown default:
                return laError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

struct AppLockScreen: View {
    @Environment(AppLockGate.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase
    @State private var heroReady = false
    @State private var biometrySymbol: String = "faceid"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MainBackground()

            Image("logo-main")
                .resizable()
                .scaledToFit()
                .frame(height: 148)
                .scaleEffect(heroReady ? 1 : 0.94)
                .opacity(heroReady ? 1 : 0)
                .shadow(color: .black.opacity(0.55), radius: 20)
                .accessibilityLabel("CASER")

            VStack {
                Spacer()
                unlockAffordance
                    .padding(.bottom, 56)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            biometrySymbol = Self.detectBiometrySymbol()
            await runHeroIntro()
            promptIfNeeded()
        }
        .onChange(of: scenePhase) { _, _ in
            promptIfNeeded()
        }
    }

    private func promptIfNeeded() {
        guard scenePhase == .active, appLock.state == .locked else { return }
        Task { await appLock.authenticate() }
    }

    @MainActor
    private func runHeroIntro() async {
        if reduceMotion {
            heroReady = true
            return
        }
        withAnimation(.easeInOut(duration: 0.9)) { heroReady = true }
    }

    @ViewBuilder
    private var unlockAffordance: some View {
        VStack(spacing: 18) {
            if case .failed(let message) = appLock.state {
                Text(message)
                    .font(.system(.footnote, design: .serif).weight(.medium))
                    .foregroundStyle(Color.caserAccent)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }

            Button {
                Task { await appLock.authenticate() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.caserAccent.opacity(0.18))
                        .frame(width: 88, height: 88)
                    Circle()
                        .stroke(Color.caserAccent.opacity(0.55), lineWidth: 1)
                        .frame(width: 88, height: 88)
                    if appLock.state == .authenticating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.caserAccent)
                            .scaleEffect(1.4)
                    } else {
                        Image(systemName: biometrySymbol)
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color.caserAccent)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityLabel(accessibilityLabel)
                    }
                }
                .contentShape(Circle())
            }
            .buttonStyle(BiometryButtonStyle())
            .disabled(appLock.state == .authenticating)
            .opacity(heroReady ? 1 : 0)
            .animation(.easeOut(duration: 0.35), value: heroReady)
        }
    }

    private static func detectBiometrySymbol() -> String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return "lock.fill"
        }
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock.fill"
        @unknown default: return "faceid"
        }
    }

    private var accessibilityLabel: String {
        switch biometrySymbol {
        case "faceid": return "Authenticate with Face ID"
        case "touchid": return "Authenticate with Touch ID"
        case "opticid": return "Authenticate with Optic ID"
        default: return "Authenticate"
        }
    }
}

private struct BiometryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
