import SwiftUI

struct SearchFeesView: View {
    enum Tab: String, CaseIterable {
        case current = "Current Quarter"
        case lifetime = "Lifetime"
        case history = "Quarterly History"
    }

    enum AlertType {
        case deleteQuarter(QuarterRecord)
        case clearLifetime
        case resetCurrent
        case success(String)
        case error(String)
    }

    @State private var tab: Tab = .current
    @Environment(SavingsTrackerStore.self) private var savingsStore
    @State private var alertType: AlertType?
    @State private var showAlert = false
    
    private var tracker: SavingsTracker { savingsStore.tracker }

    private var alertTitle: String {
        switch alertType {
        case .deleteQuarter: "Delete Quarter"
        case .clearLifetime: "Clear All Lifetime Data"
        case .resetCurrent: "Reset Current Quarter"
        case .success: "Success"
        case .error: "Error"
        case .none: ""
        }
    }

    private var alertMessage: String {
        switch alertType {
        case .deleteQuarter(let record): "Are you sure you want to delete \(record.quarterId)? This action cannot be undone."
        case .clearLifetime: "Are you sure you want to delete ALL quarterly history? This will permanently remove all saved data and cannot be undone."
        case .resetCurrent: "Are you sure you want to reset the current quarter? This will delete all data for the current quarter and cannot be undone."
        case .success(let message): message
        case .error(let message): message
        case .none: ""
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            
            ScrollView {
                switch tab {
                case .current:
                    CurrentQuarterCard(
                        displaySavings: tracker.displayQuarterSavings,
                        breakdown: tracker.currentQuarterBreakdown,
                        searchResults: tracker.currentQuarterSearchResults,
                        monitorResults: tracker.currentQuarterMonitorResults,
                        searchPages: tracker.currentQuarterSearchPages,
                        monitorPages: tracker.currentQuarterMonitorPages,
                        onReset: {
                            alertType = .resetCurrent
                            showAlert = true
                        }
                    )
                case .lifetime:
                    LifetimeCard(
                        savings: tracker.lifetimeSavings,
                        searchResults: tracker.lifetimeSearchResults,
                        monitorResults: tracker.lifetimeMonitorResults,
                        searchPages: tracker.lifetimeSearchPages,
                        monitorPages: tracker.lifetimeMonitorPages,
                        onClearAll: {
                            alertType = .clearLifetime
                            showAlert = true
                        }
                    )
                case .history:
                    QuarterlyHistoryList(
                        items: tracker.quarterlyHistory,
                        onDelete: { record in
                            alertType = .deleteQuarter(record)
                            showAlert = true
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background {
            MainBackground()
        }
        .navigationTitle("PACER Savings Tracker")
        .navigationBarTitleDisplayMode(.large)
        .alert(alertTitle, isPresented: $showAlert) {
            switch alertType {
            case .deleteQuarter(let record):
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        let result = await tracker.deleteQuarter(quarterId: record.quarterId)
                        switch result {
                        case .success:
                            alertType = .success("Quarter deleted successfully")
                        case .failure(let error):
                            alertType = .error("Failed to delete quarter: \(error.localizedDescription)")
                        }
                        showAlert = true
                    }
                }
            case .clearLifetime:
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    Task {
                        let result = await tracker.clearAllLifetimeData()
                        switch result {
                        case .success:
                            alertType = .success("All lifetime data cleared successfully")
                        case .failure(let error):
                            alertType = .error("Failed to clear data: \(error.localizedDescription)")
                        }
                        showAlert = true
                    }
                }
            case .resetCurrent:
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    Task {
                        let result = await tracker.resetCurrentQuarter()
                        switch result {
                        case .success:
                            alertType = .success("Current quarter reset successfully")
                        case .failure(let error):
                            alertType = .error("Failed to reset quarter: \(error.localizedDescription)")
                        }
                        showAlert = true
                    }
                }
            case .success, .error:
                Button("OK", role: .cancel) {}
            case .none:
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
        .task {
            await savingsStore.loadIfNeeded(force: false)
        }
    }
}

private struct CurrentQuarterCard: View {
    let displaySavings: Double
    let breakdown: SavingsBreakdown
    let searchResults: Int
    let monitorResults: Int
    let searchPages: Int
    let monitorPages: Int
    let onReset: () -> Void

    private var totalResults: Int { searchResults + monitorResults }
    private var totalPages: Int { searchPages + monitorPages }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Savings this quarter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("$\(displaySavings, specifier: "%.2f")")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(displaySavings > 0 ? Color.caserGreen : .secondary)
                        .contentTransition(.numericText(value: displaySavings))
                        .animation(.smooth, value: displaySavings)
                }
                
                Spacer()
                
                Button {
                    onReset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(.red.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("Reset current quarter")
                .accessibilityHint("Clears savings data for the current quarter")
            }

            Divider().background(.white.opacity(0.1))
            
            VStack(alignment: .leading, spacing: 12) {
                MetricRow(title: "Search results (if on PACER)", value: "\(totalResults) results")
                BreakdownRow(searchValue: searchResults, monitorValue: monitorResults, unit: "result")
                MetricRow(title: "PACER pages (hypothetical)", value: "\(totalPages) pages")
                BreakdownRow(searchValue: searchPages, monitorValue: monitorPages, unit: "page")
                
                HStack {
                    Text("What PACER would charge")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("$\(breakdown.grossCharges, specifier: "%.2f")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PACER Uncapped Search Warning")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text("PACER search-result screens are NOT covered by the $3 per-document cap. Name searches, non-case-specific reports, and transcripts bill $0.10 per result with no ceiling. This tracker reflects the worst-case PACER bill for the same activity.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }

            Text("CASER has no per-search or per-result fees. This tracker compares your activity to PACER's $0.10-per-result billing on its uncapped search screens. Monitor alerts count as 1 billable result per match.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(style: .regular, shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct MetricRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
    }
}

private struct BreakdownRow: View {
    let searchValue: Int
    let monitorValue: Int
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("• Manual searches: \(searchValue) \(pluralizedUnit(for: searchValue))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text("• Monitor alerts: \(monitorValue) \(pluralizedUnit(for: monitorValue))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func pluralizedUnit(for value: Int) -> String {
        value == 1 ? unit : "\(unit)s"
    }
}

private struct LifetimeCard: View {
    let savings: Double
    let searchResults: Int
    let monitorResults: Int
    let searchPages: Int
    let monitorPages: Int
    let onClearAll: () -> Void

    private var totalResults: Int { searchResults + monitorResults }
    private var totalPages: Int { searchPages + monitorPages }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lifetime savings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("$\(savings, specifier: "%.2f")")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(Color.caserGreen)
                }
                
                Spacer()
                
                Button {
                    onClearAll()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(.red.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("Clear lifetime savings data")
                .accessibilityHint("Removes all quarterly history and lifetime totals")
            }

            Text("\(totalResults) search results across all searches (hypothetical PACER charges)")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            BreakdownRow(searchValue: searchResults, monitorValue: monitorResults, unit: "result")
            Text("\(totalPages) PACER pages (one per manual search or monitor poll)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            BreakdownRow(searchValue: searchPages, monitorValue: monitorPages, unit: "page")
            
            Text("Running total of what you would have paid on PACER's uncapped search screens. CASER has no per-search or per-result fees — this tracker shows your cost savings compared to PACER ($0.10 per result, no cap on search-result screens).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .glassSurface(style: .regular, shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct QuarterlyHistoryList: View {
    let items: [QuarterRecord]
    let onDelete: (QuarterRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quarterly history")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No history yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(items) { record in
                    QuarterCard(record: record, onDelete: {
                        onDelete(record)
                    })
                }
            }
        }
        .padding(24)
        .glassSurface(style: .regular, shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct QuarterCard: View {
    let record: QuarterRecord
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.quarterId)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(record.totalResults) results (\(record.searchResults) search, \(record.monitorResults) monitor)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(record.totalPages) billable search pages (manual + monitor)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Text("$\(record.savings, specifier: "%.2f")")
                .font(.headline)
                .foregroundStyle(Color.caserGreen)
        }
        .padding(16)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
