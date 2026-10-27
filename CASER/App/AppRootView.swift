import SwiftUI

struct AppRootView: View {
    @Environment(SavingsTrackerStore.self) private var savingsStore
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(SavedCasesManager.self) private var savedCasesManager
    @Environment(AppRouter.self) private var router
    @Environment(AppLockGate.self) private var appLock
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showLaunchSplash = true

    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !CASERTestMode.isUITesting && !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

    private var isAuthenticated: Bool {
        CASERTestMode.isUITesting || appLock.state == .authenticated
    }

    var body: some View {
        ZStack {
            if !hasCompletedOnboarding && !CASERTestMode.isUITesting {
                Color.black
                    .ignoresSafeArea()
            } else if !isAuthenticated {
                AppLockScreen()
            } else {
                MainContainerView()
                    .tint(Color.caserAccent)
                    .preferredColorScheme(.dark)
                    .task {
                        await savedCasesManager.loadSaved()
                    }
            }

            if showLaunchSplash && hasCompletedOnboarding && isAuthenticated {
                LaunchSplashView {
                    withAnimation(.easeOut(duration: 0.2)) {
                        showLaunchSplash = false
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }

            if scenePhase != .active {
                Color.black
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .zIndex(100)
            }
        }
        .onAppear {
            if CASERTestMode.isUITesting {
                hasCompletedOnboarding = true
                showLaunchSplash = false
                return
            }
            if !hasCompletedOnboarding {
                showLaunchSplash = false
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                appLock.handleForeground()
            case .background:
                appLock.handleBackground()
            default:
                break
            }
        }
        .onChange(of: router.pendingMonitorMatchId) { _, matchId in
            if matchId != nil {
                hasCompletedOnboarding = true
            }
        }
        .fullScreenCover(isPresented: showOnboarding) {
            OnboardingView()
        }
        .alert(
            "Saved Cases",
            isPresented: Binding(
                get: { savedCasesManager.lastPersistenceError != nil },
                set: { isPresented in
                    if !isPresented {
                        savedCasesManager.clearPersistenceError()
                    }
                }
            )
        ) {
            Button("OK") {
                savedCasesManager.clearPersistenceError()
            }
        } message: {
            Text(savedCasesManager.lastPersistenceError?.message ?? "Saved-case data could not be updated.")
        }
    }
}
