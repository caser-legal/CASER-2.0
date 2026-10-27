import Foundation
import Observation

@MainActor
@Observable
final class SavingsTrackerStore {
    static let shared = SavingsTrackerStore()
    
    let tracker = SavingsTracker()
    
    private var loadTask: Task<Bool, Never>?
    private var hasLoadedOnce = false
    
    func loadIfNeeded(force: Bool = false) async {
        if let task = loadTask {
            _ = await task.value
            if !force { return }
        } else if !force && hasLoadedOnce {
            return
        }
        
        let task = Task {
            await tracker.load()
        }
        loadTask = task
        hasLoadedOnce = await task.value
        loadTask = nil
    }
    
    func markStale(resetData: Bool = false) {
        hasLoadedOnce = false
        if resetData {
            tracker.reset()
        }
    }
    
    func trackLiveScan(billableResults: Int, billablePages: Int) async {
        await loadIfNeeded()
        await tracker.trackLiveScan(billableResults: billableResults, billablePages: billablePages)
    }
}
