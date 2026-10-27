import Foundation
import Observation
import os.log

protocol SavedCasesStorage: Sendable {
    func load(from filename: String) throws -> Data
    func save(_ data: Data, to filename: String) throws
    func exists(_ filename: String) -> Bool
}

extension SecureFileStore: SavedCasesStorage {}

struct SavedCasesPersistenceError: Identifiable, Equatable, Sendable {
    enum Operation: String, Sendable {
        case load
        case save
        case remove
        case clear
        case resetCount
    }

    let id = UUID()
    let operation: Operation
    let message: String
}

@MainActor
@Observable
class SavedCasesManager {
    private let key = "SavedCases"
    private let storageFile = "saved_cases.json"
    private let countFile = "total_cases_saved.json"
    private let storage: any SavedCasesStorage
    var savedCases: [CaseEntry] = []
    var savedCaseIds: Set<String> = []
    private(set) var lastPersistenceError: SavedCasesPersistenceError?

    private var _totalCasesSaved: Int = 0

    private(set) var totalCasesSaved: Int {
        get { _totalCasesSaved }
        set { _totalCasesSaved = newValue }
    }
    
    init(storage: any SavedCasesStorage = SecureFileStore()) {
        self.storage = storage
        migrateFromUserDefaults()
        _totalCasesSaved = loadTotalCasesSaved()
    }

    private func loadTotalCasesSaved() -> Int {
        if let data = try? storage.load(from: countFile),
           let count = try? JSONDecoder().decode(Int.self, from: data) {
            return count
        }
        let legacy = UserDefaults.standard.integer(forKey: "totalCasesSaved")
        if legacy > 0 {
            do {
                let encoded = try JSONEncoder().encode(legacy)
                try storage.save(encoded, to: countFile)
                UserDefaults.standard.removeObject(forKey: "totalCasesSaved")
            } catch {
                os_log(.error, "Failed to migrate saved-case count: %{public}@", error.localizedDescription)
            }
        }
        return legacy
    }
    
    func loadSaved() async {
        do {
            let data = try storage.load(from: storageFile)
            let cases = try JSONDecoder().decode([CaseEntry].self, from: data)
            savedCases = cases
            savedCaseIds = Set(cases.map { $0.id })
        } catch {
            if storage.exists(storageFile) {
                os_log(.error, "Failed to load saved cases: %{public}@", error.localizedDescription)
                recordPersistenceError(operation: .load, error: error)
            }
        }
    }

    func save(_ entry: CaseEntry) async -> Bool {
        guard !savedCaseIds.contains(entry.id) else { return true }

        var updatedCases = savedCases
        updatedCases.insert(entry, at: 0)
        do {
            try persist(updatedCases)
            savedCases = updatedCases
            savedCaseIds.insert(entry.id)

            let updatedLifetimeCount = totalCasesSaved + 1
            do {
                try persistLifetimeCount(updatedLifetimeCount)
                totalCasesSaved = updatedLifetimeCount
            } catch {
                os_log(.error, "Failed to persist saved-case count: %{public}@", error.localizedDescription)
            }
            lastPersistenceError = nil
            return true
        } catch {
            recordPersistenceError(operation: .save, error: error)
            return false
        }
    }

    @discardableResult
    func unsave(_ caseID: String) async -> Bool {
        let updatedCases = savedCases.filter { $0.id != caseID }
        guard updatedCases.count != savedCases.count else { return true }
        do {
            try persist(updatedCases)
            savedCases = updatedCases
            savedCaseIds.remove(caseID)
            lastPersistenceError = nil
            return true
        } catch {
            recordPersistenceError(operation: .remove, error: error)
            return false
        }
    }

    func isSaved(_ caseID: String) -> Bool {
        savedCaseIds.contains(caseID)
    }

    @discardableResult
    func clearAll() async -> Bool {
        do {
            try persist([])
            savedCases.removeAll()
            savedCaseIds.removeAll()
            lastPersistenceError = nil
            return true
        } catch {
            recordPersistenceError(operation: .clear, error: error)
            return false
        }
    }

    @discardableResult
    func resetLifetimeCount() -> Bool {
        do {
            try persistLifetimeCount(0)
            totalCasesSaved = 0
            return true
        } catch {
            recordPersistenceError(operation: .resetCount, error: error)
            return false
        }
    }

    func clearPersistenceError() {
        lastPersistenceError = nil
    }

    private func persist(_ cases: [CaseEntry]) throws {
        let data = try JSONEncoder().encode(cases)
        try storage.save(data, to: storageFile)
    }

    private func persistLifetimeCount(_ count: Int) throws {
        let data = try JSONEncoder().encode(count)
        try storage.save(data, to: countFile)
    }

    private func recordPersistenceError(operation: SavedCasesPersistenceError.Operation, error: Error) {
        let action: String
        switch operation {
        case .load: action = "load"
        case .save: action = "save"
        case .remove: action = "remove"
        case .clear: action = "clear"
        case .resetCount: action = "reset"
        }
        lastPersistenceError = SavedCasesPersistenceError(
            operation: operation,
            message: "CASER couldn't \(action) saved-case data. Your existing saved cases were left unchanged. \(error.localizedDescription)"
        )
        os_log(.error, "Saved-case persistence failed: %{public}@", error.localizedDescription)
    }

    private func migrateFromUserDefaults() {
        guard !storage.exists(storageFile) else { return }
        guard let data = UserDefaults.standard.data(forKey: key),
              let cases = try? JSONDecoder().decode([CaseEntry].self, from: data) else { return }
        do {
            let encoded = try JSONEncoder().encode(cases)
            try storage.save(encoded, to: storageFile)
            UserDefaults.standard.removeObject(forKey: key)
        } catch {
            os_log(.error, "Failed to migrate saved cases from UserDefaults: %{public}@", error.localizedDescription)
        }
    }
}
