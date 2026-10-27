import Foundation
import Observation

struct QuarterRecord: Identifiable, Codable, Sendable {
    let id: String
    let quarterId: String
    let savings: Double
    let searchPages: Int
    let monitorPages: Int
    let searchResults: Int
    let monitorResults: Int
    let totalPages: Int
    let totalResults: Int
}

struct QuarterData: Codable, Sendable {
    var searchPages: Int
    var monitorPages: Int
    var searchResults: Int
    var monitorResults: Int
    var otherSpend: Double
}

struct StoredSavingsData: Codable, Sendable {
    var quarters: [String: QuarterData]
}

@MainActor
@Observable
final class SavingsTracker {
    var currentQuarterBreakdown: SavingsBreakdown = .init(grossCharges: 0, waiverUsed: 0, waiverRemaining: SearchFees.waiverCap, actualSavings: 0)
    var currentQuarterBillablePages: Int = 0
    var currentQuarterBillableResults: Int = 0
    var currentQuarterSearchResults: Int = 0
    var currentQuarterMonitorResults: Int = 0
    var currentQuarterSearchPages: Int = 0
    var currentQuarterMonitorPages: Int = 0
    var lifetimeSavings: Double = 0
    var lifetimeBillablePages: Int = 0
    var lifetimeBillableResults: Int = 0
    var lifetimeSearchResults: Int = 0
    var lifetimeMonitorResults: Int = 0
    var lifetimeSearchPages: Int = 0
    var lifetimeMonitorPages: Int = 0
    var quarterlyHistory: [QuarterRecord] = []

    var displayQuarterSavings: Double {
        guard currentQuarterBillablePages > 0 else { return 0 }
        return currentQuarterBreakdown.grossCharges
    }

    private let storageKey = "SavingsTrackerData"
    private let storageFile = "savings_tracker.json"
    private let secureStore = SecureFileStore(protection: .completeUntilFirstUserAuthentication)
    private var currentQuarterOtherSpend: Double = 0
    private var loadedQuarterID: String?
    
    func reset() {
        currentQuarterBreakdown = .init(grossCharges: 0, waiverUsed: 0, waiverRemaining: SearchFees.waiverCap, actualSavings: 0)
        currentQuarterBillablePages = 0
        currentQuarterBillableResults = 0
        currentQuarterSearchResults = 0
        currentQuarterMonitorResults = 0
        currentQuarterSearchPages = 0
        currentQuarterMonitorPages = 0
        currentQuarterOtherSpend = 0
        lifetimeSavings = 0
        lifetimeBillablePages = 0
        lifetimeBillableResults = 0
        lifetimeSearchResults = 0
        lifetimeMonitorResults = 0
        lifetimeSearchPages = 0
        lifetimeMonitorPages = 0
        quarterlyHistory = []
        save()
    }
    
    @discardableResult
    func load() async -> Bool {
        let quarterId = Calendar.current.quarterID()

        let stored: StoredSavingsData
        switch readStored() {
        case .failure:
            return false
        case .success(nil):
            zeroCurrentQuarterCounters()
            currentQuarterBreakdown = computeQuarterSavings(totalBillablePages: 0, otherSpend: 0)
            loadedQuarterID = quarterId
            return true
        case .success(let value?):
            stored = value
        }
        secureStore.applyProtection(to: storageFile)

        if let quarter = stored.quarters[quarterId] {
            currentQuarterSearchPages = quarter.searchPages
            currentQuarterMonitorPages = quarter.monitorPages
            currentQuarterSearchResults = quarter.searchResults
            currentQuarterMonitorResults = quarter.monitorResults
            currentQuarterBillablePages = quarter.searchPages + quarter.monitorPages
            currentQuarterBillableResults = quarter.searchResults + quarter.monitorResults
            currentQuarterOtherSpend = quarter.otherSpend
            currentQuarterBreakdown = computeQuarterSavings(totalBillablePages: currentQuarterBillablePages, otherSpend: quarter.otherSpend)
        } else {
            zeroCurrentQuarterCounters()
            currentQuarterBreakdown = computeQuarterSavings(totalBillablePages: 0, otherSpend: 0)
        }
        
        calculateLifetime(from: stored)
        quarterlyHistory = stored.quarters.map { id, q in
            let totalPages = q.searchPages + q.monitorPages
            let breakdown = computeQuarterSavings(totalBillablePages: totalPages, otherSpend: q.otherSpend)
            return QuarterRecord(
                id: id,
                quarterId: id,
                savings: totalPages > 0 ? breakdown.grossCharges : 0,
                searchPages: q.searchPages,
                monitorPages: q.monitorPages,
                searchResults: q.searchResults,
                monitorResults: q.monitorResults,
                totalPages: totalPages,
                totalResults: q.searchResults + q.monitorResults
            )
        }.sorted { $0.quarterId > $1.quarterId }
        loadedQuarterID = quarterId
        return true
    }

    private func zeroCurrentQuarterCounters() {
        currentQuarterSearchPages = 0
        currentQuarterMonitorPages = 0
        currentQuarterSearchResults = 0
        currentQuarterMonitorResults = 0
        currentQuarterBillablePages = 0
        currentQuarterBillableResults = 0
        currentQuarterOtherSpend = 0
    }

    private func ensureCurrentQuarterLoaded() async -> Bool {
        if loadedQuarterID == Calendar.current.quarterID() { return true }
        return await load()
    }
    
    func trackSearch(billableResults: Int, billablePages: Int) async {
        guard await ensureCurrentQuarterLoaded() else { return }
        let quarterId = Calendar.current.quarterID()
        
        currentQuarterSearchPages += billablePages
        currentQuarterSearchResults += billableResults
        currentQuarterBillablePages += billablePages
        currentQuarterBillableResults += billableResults
        lifetimeSearchPages += billablePages
        lifetimeSearchResults += billableResults
        lifetimeBillablePages += billablePages
        lifetimeBillableResults += billableResults
        
        currentQuarterBreakdown = computeQuarterSavings(totalBillablePages: currentQuarterBillablePages, otherSpend: currentQuarterOtherSpend)
        
        updateQuarter(quarterId: quarterId)
        recalculateLifetimeSavings()
        save()
    }
    
    func trackLiveScan(billableResults: Int, billablePages: Int) async {
        guard await ensureCurrentQuarterLoaded() else { return }
        let quarterId = Calendar.current.quarterID()
        
        currentQuarterMonitorPages += billablePages
        currentQuarterMonitorResults += billableResults
        currentQuarterBillablePages += billablePages
        currentQuarterBillableResults += billableResults
        lifetimeMonitorPages += billablePages
        lifetimeMonitorResults += billableResults
        lifetimeBillablePages += billablePages
        lifetimeBillableResults += billableResults
        
        currentQuarterBreakdown = computeQuarterSavings(totalBillablePages: currentQuarterBillablePages, otherSpend: currentQuarterOtherSpend)
        
        updateQuarter(quarterId: quarterId)
        recalculateLifetimeSavings()
        save()
    }
    
    func updateOtherSpend(_ amount: Double) async {
        guard await ensureCurrentQuarterLoaded() else { return }
        let quarterId = Calendar.current.quarterID()
        currentQuarterOtherSpend = amount
        currentQuarterBreakdown = computeQuarterSavings(totalBillablePages: currentQuarterBillablePages, otherSpend: amount)
        updateQuarter(quarterId: quarterId)
        save()
    }

    func deleteQuarter(quarterId: String) async -> Result<Void, Error> {
        let result = readStored()
        if case .failure(let error) = result { return .failure(error) }
        guard case .success(var stored?) = result else { return .success(()) }
        stored.quarters.removeValue(forKey: quarterId)
        saveStored(stored)
        await load()
        return .success(())
    }

    func clearAllLifetimeData() async -> Result<Void, Error> {
        try? secureStore.delete(storageFile)
        UserDefaults.standard.removeObject(forKey: storageKey)
        reset()
        return .success(())
    }

    func resetCurrentQuarter() async -> Result<Void, Error> {
        let quarterId = Calendar.current.quarterID()
        return await deleteQuarter(quarterId: quarterId)
    }
    
    private func updateQuarter(quarterId: String) {
        guard loadedQuarterID == quarterId, case .success(let existing) = readStored() else { return }
        var stored = existing ?? StoredSavingsData(quarters: [:])
        stored.quarters[quarterId] = QuarterData(
            searchPages: currentQuarterSearchPages,
            monitorPages: currentQuarterMonitorPages,
            searchResults: currentQuarterSearchResults,
            monitorResults: currentQuarterMonitorResults,
            otherSpend: currentQuarterOtherSpend
        )
        saveStored(stored)
    }
    
    private func calculateLifetime(from stored: StoredSavingsData) {
        var totalSearchPages = 0
        var totalMonitorPages = 0
        var totalSearchResults = 0
        var totalMonitorResults = 0
        
        for (_, q) in stored.quarters {
            totalSearchPages += q.searchPages
            totalMonitorPages += q.monitorPages
            totalSearchResults += q.searchResults
            totalMonitorResults += q.monitorResults
        }
        
        lifetimeSearchPages = totalSearchPages
        lifetimeMonitorPages = totalMonitorPages
        lifetimeSearchResults = totalSearchResults
        lifetimeMonitorResults = totalMonitorResults
        lifetimeBillablePages = totalSearchPages + totalMonitorPages
        lifetimeBillableResults = totalSearchResults + totalMonitorResults
        
        recalculateLifetimeSavings()
    }
    
    private func recalculateLifetimeSavings() {
        guard let stored = loadStored() else {
            lifetimeSavings = max(0, currentQuarterBreakdown.actualSavings)
            return
        }
        
        var total = 0.0
        for (_, q) in stored.quarters {
            let totalPages = q.searchPages + q.monitorPages
            let breakdown = computeQuarterSavings(totalBillablePages: totalPages, otherSpend: q.otherSpend)
            if breakdown.actualSavings > 0 {
                total += breakdown.actualSavings
            }
        }
        lifetimeSavings = total
    }
    
    private func loadStored() -> StoredSavingsData? {
        try? readStored().get()
    }

    private func readStored() -> Result<StoredSavingsData?, Error> {
        if secureStore.exists(storageFile) {
            do {
                return .success(try JSONDecoder().decode(StoredSavingsData.self, from: secureStore.load(from: storageFile)))
            } catch {
                return .failure(error)
            }
        }
        return .success(legacyStored())
    }

    private func legacyStored() -> StoredSavingsData? {
        guard let legacy = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StoredSavingsData.self, from: legacy) else {
            return nil
        }
        if let encoded = try? JSONEncoder().encode(stored),
           (try? secureStore.save(encoded, to: storageFile)) != nil {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        return stored
    }

    private func saveStored(_ stored: StoredSavingsData) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? secureStore.save(data, to: storageFile)
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
    
    private func save() {
        let quarterId = Calendar.current.quarterID()
        updateQuarter(quarterId: quarterId)
    }
}
