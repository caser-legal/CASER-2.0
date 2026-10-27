import SwiftUI

struct SavedCasesView: View {
    @Environment(AppRouter.self) private var router
    @Environment(SavedCasesManager.self) private var manager
    @State private var showClearConfirmation = false
    @State private var openedCase: CaseEntry?
    @State private var searchAgainCase: CaseEntry?
    @State private var isLoading = true
    @State private var visibleCount = PaginatedBatch.pageSize

    private var visibleCases: [CaseEntry] {
        PaginatedBatch.page(manager.savedCases, visibleCount: visibleCount)
    }
    
    var body: some View {
        List {
            if isLoading {
                Section {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
                .caserListRow()
            } else if manager.savedCases.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "heart.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.3))
                        Text("No saved cases")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Tap the heart on any case to keep it here.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
                .caserListRow()
            } else {
                Section {
                    ForEach(visibleCases) { entry in
                        Button {
                            openedCase = entry
                        } label: {
                            CaseRow(item: entry)
                        }
                        .buttonStyle(.plain)
                        .caserListRow()
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                searchAgainCase = entry
                            } label: {
                                Label("Search Again", systemImage: "magnifyingglass")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await manager.unsave(entry.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                openedCase = entry
                            } label: {
                                Label("Open Case", systemImage: "doc.text.magnifyingglass")
                            }
                            Button {
                                searchAgainCase = entry
                            } label: {
                                Label("Search Again", systemImage: "magnifyingglass")
                            }
                            Button(role: .destructive) {
                                Task { await manager.unsave(entry.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onAppear {
                            loadMoreCasesIfNeeded(for: entry.id)
                        }
                    }

                    if PaginatedBatch.canLoadMore(totalCount: manager.savedCases.count, visibleCount: visibleCount) {
                        HStack {
                            Spacer()
                            ProgressView()
                                .tint(.white.opacity(0.6))
                            Spacer()
                        }
                    }
                } header: {
                    CaserSectionHeader(title: "Saved Cases", trailing: manager.savedCases.count.formatted())
                } footer: {
                    if manager.savedCases.count > visibleCount {
                        Text("Showing \(visibleCount) of \(manager.savedCases.count) saved cases.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .caserListBackground()
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !manager.savedCases.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear All") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .sheet(item: $openedCase) { entry in
            NavigationStack {
                CaseDetailView(entry: entry)
            }
        }
        .alert("Search again?", isPresented: Binding(get: { searchAgainCase != nil }, set: { if !$0 { searchAgainCase = nil } })) {
            Button("Cancel", role: .cancel) { searchAgainCase = nil }
            Button("Search") {
                if let entry = searchAgainCase {
                    let query = entry.displayTitle
                    let states = searchAgainStates(for: entry)
                    router.selectedTab = .search
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        NotificationCenter.default.post(
                            name: .performSearch,
                            object: nil,
                            userInfo: ["query": query, "states": states]
                        )
                    }
                }
                searchAgainCase = nil
            }
        } message: {
            if let entry = searchAgainCase {
                Text("Search for \"\(entry.displayTitle)\" again?")
            }
        }
        .alert("Clear all saved cases?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                Task {
                    await manager.clearAll()
                }
            }
        } message: {
            Text("This will permanently delete all saved cases. This action cannot be undone.")
        }
        .task {
            visibleCount = PaginatedBatch.pageSize
            await manager.loadSaved()
            isLoading = false
        }
    }

    private func loadMoreCasesIfNeeded(for caseID: String) {
        guard caseID == visibleCases.last?.id else { return }
        guard PaginatedBatch.canLoadMore(totalCount: manager.savedCases.count, visibleCount: visibleCount) else { return }
        visibleCount = PaginatedBatch.nextVisibleCount(
            current: visibleCount,
            totalCount: manager.savedCases.count
        )
    }

    private func searchAgainStates(for entry: CaseEntry) -> [String] {
        if let courtState = entry.modsCourtState?.trimmedNonEmpty ?? entry.state?.trimmedNonEmpty {
            return [courtState]
        }
        return []
    }
}
