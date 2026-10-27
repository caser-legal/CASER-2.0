import SwiftUI

struct DashboardView: View {
    enum Destination: Hashable {
    }

    @Environment(SavingsTrackerStore.self) private var savingsStore
    @Environment(SavedCasesManager.self) private var savedCasesManager
    @State private var activeMonitors = 0
    @State private var monitorAlerts = 0
    @Binding var path: [Destination]

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                DashboardHeader()

                VStack(spacing: 12) {
                    DashboardOverviewCard(
                        savedCases: savedCasesManager.savedCases.count,
                        activeMonitors: activeMonitors,
                        monitorAlerts: monitorAlerts,
                        onClearMatches: clearAllMatches
                    )

                    SearchSection()
                    MonitorSection()
                    ToolsSection()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .background {
                MainBackground()
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            loadMonitorStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .monitorScanCompleted)) { _ in
            loadMonitorStats()
        }
        .onAppear {
            loadMonitorStats()
        }
    }

    private func loadMonitorStats() {
        let storage = KeywordMonitorStorage.shared
        let keywords = storage.load()
        activeMonitors = keywords.filter { $0.enabled }.count
        monitorAlerts = VisibleMatchProjection.count(
            matches: MatchCacheStorage.shared.load(),
            keywords: keywords
        )
    }
    
    private func clearAllMatches() {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        guard MatchCacheStorage.shared.clearMatches() else { return }
        monitorAlerts = 0
        Task { await NotificationManager.shared.clearAllNotifications() }
    }
}

private struct DashboardHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
            }

            VStack(spacing: 3) {
                Image("logo-4")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120)
                    .accessibilityHidden(true)
                Text(AppBranding.fullName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

private struct DashboardOverviewCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(SavingsTrackerStore.self) private var savingsStore
    let savedCases: Int
    let activeMonitors: Int
    let monitorAlerts: Int
    let onClearMatches: () -> Void
    @State private var isLoading = true
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    router.openSaved()
                } label: {
                    DashboardMetric(
                        title: "Saved Cases",
                        value: savedCases.formatted(),
                        systemImage: "heart.fill",
                        tint: savedCases > 0 ? Color.caserAccent : .secondary,
                        isLoading: false
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48, maxHeight: 80)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Saved cases, \(savedCases)")
                .accessibilityAddTraits(.isButton)

                Divider()
                    .background(Color.white.opacity(0.1))

                Button {
                    NotificationCenter.default.post(name: .openSearchFees, object: nil)
                } label: {
                    DashboardMetric(
                        title: "Quarter Savings",
                        value: savingsStore.tracker.displayQuarterSavings.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")),
                        systemImage: "dollarsign.circle.fill",
                        tint: savingsStore.tracker.displayQuarterSavings > 0 ? Color.caserGreen : .secondary,
                        isLoading: isLoading
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48, maxHeight: 80)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(savingsAccessibilityLabel)
                .accessibilityAddTraits(.isButton)
            }

            Divider()
                .background(Color.white.opacity(0.1))

            HStack(spacing: 0) {
                Button {
                    router.selectedTab = .monitor
                } label: {
                    DashboardMetric(
                        title: "Active Alerts",
                        value: activeMonitors.formatted(),
                        systemImage: "bell.badge.fill",
                        tint: activeMonitors > 0 ? Color.caserGreen : .secondary,
                        isLoading: isLoading
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48, maxHeight: 80)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Active alerts, \(activeMonitors)")
                .accessibilityAddTraits(.isButton)

                Divider()
                    .background(Color.white.opacity(0.1))

                Button {
                    router.selectedTab = .monitor
                } label: {
                    DashboardMetric(
                        title: "New Matches",
                        value: monitorAlerts.formatted(),
                        systemImage: "doc.text.magnifyingglass",
                        tint: monitorAlerts > 0 ? Color.caserAccent : .secondary,
                        isLoading: isLoading
                    )
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48, maxHeight: 80)
                }
                .buttonStyle(.plain)
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            showClearConfirmation = true
                        }
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Alert matches, \(monitorAlerts)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Clear all matches") {
                    showClearConfirmation = true
                }
            }
        }
        .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            await loadFeesSaved()
            isLoading = false
        }
        .alert("Clear alert matches?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear Alert Matches", role: .destructive) {
                onClearMatches()
            }
        } message: {
            Text("Clearing alert matches will remove recent monitor notifications from the dashboard count.")
        }
    }

    private func loadFeesSaved() async {
        await savingsStore.loadIfNeeded(force: false)
    }

    private var savingsAccessibilityLabel: String {
        if isLoading { return "Savings this quarter, loading" }
        let savings = savingsStore.tracker.displayQuarterSavings
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.locale = .current
        let formatted = formatter.string(from: NSNumber(value: savings)) ?? "$\(String(format: "%.2f", savings))"
        return "Savings this quarter, \(formatted)"
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 6)
    }
}

private struct SearchSection: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button {
                    router.selectedTab = .search
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        NotificationCenter.default.post(name: .openNewSearch, object: nil)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .accessibilityLabel("Search")
                        Text("New search")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56, maxHeight: 100)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                
                Button {
                    NotificationCenter.default.post(name: .openSaved, object: nil)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "heart")
                            .font(.title2)
                            .accessibilityLabel("Saved cases")
                        Text("Saved")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56, maxHeight: 100)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
            }
        }
    }
}

private struct MonitorSection: View {
    @Environment(AppRouter.self) private var router
    @State private var monitorStatus = "Idle"
    @State private var hasMonitors = false
    @State private var keywordCount = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alerts")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button {
                    router.selectedTab = .monitor
                } label: {
                    VStack(spacing: 6) {
                        Text("Alert Status")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.secondary)
                        Text(monitorStatus)
                            .font(.body.weight(.medium))
                            .foregroundStyle(hasMonitors ? Color.caserGreen : .red)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56, maxHeight: 100)
                }
                .buttonStyle(.plain)
                .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                
                Button {
                    router.selectedTab = .monitor
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        NotificationCenter.default.post(name: .openAddMonitor, object: nil)
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.title2)
                            .accessibilityLabel("Add alert")
                        Text("Add Alert")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56, maxHeight: 100)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
            }
        }
        .task { await checkMonitorStatus() }
    }

    private func checkMonitorStatus() async {
        let keywords = KeywordMonitorStorage.shared.load()
        let enabledCount = keywords.filter { $0.enabled }.count
        keywordCount = keywords.count
        hasMonitors = enabledCount > 0
        
        if hasMonitors {
            monitorStatus = "Active"
        } else {
            monitorStatus = "Idle"
        }
    }
}

private struct ToolsSection: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.headline)
            
            HStack(spacing: 12) {
                Button {
                    NotificationCenter.default.post(name: .openNotifications, object: nil)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "bell")
                            .font(.title2)
                            .accessibilityLabel("Notifications")
                        Text("Notifications")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56, maxHeight: 100)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                
                Button {
                    NotificationCenter.default.post(name: .openSearchFees, object: nil)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "dollarsign")
                            .font(.title2)
                            .accessibilityLabel("Search fees")
                        Text("Search fees")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56, maxHeight: 100)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                
                Button {
                    router.selectedTab = .settings
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .accessibilityLabel("Settings")
                        Text("Settings")
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56, maxHeight: 100)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassSurface(style: .thick, shape: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
            }
        }
    }
}
