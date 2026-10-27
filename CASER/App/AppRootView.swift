import SwiftUI

struct AppRootView: View {
    @Environment(SavingsTrackerStore.self) private var savingsStore
    @Environment(UserSettingsStore.self) private var userSettings
    @Environment(SavedCasesManager.self) private var savedCasesManager
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showLaunchSplash = true

    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !CASERTestMode.isUITesting && !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

    var body: some View {
        ZStack {
            if !hasCompletedOnboarding && !CASERTestMode.isUITesting {
                Color.black
                    .ignoresSafeArea()
            } else {
                MainContainerView()
                    .tint(Color.caserAccent)
                    .preferredColorScheme(.dark)
                    .task {
                        await savedCasesManager.loadSaved()
                    }
            }

            if showLaunchSplash && hasCompletedOnboarding {
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
