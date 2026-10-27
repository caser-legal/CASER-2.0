import Foundation

struct SavingsBreakdown: Sendable {
    let grossCharges: Double
    let waiverUsed: Double
    let waiverRemaining: Double
    let actualSavings: Double

    var displaySavings: Double {
        grossCharges > 0 ? grossCharges : 0
    }
}

struct SearchFees: Sendable {
    static let pricePerPage: Double = 0.10

    static let waiverCap: Double = 0

    static func billablePagesForSearchRequests(_ resultCount: Int) -> Int {
        max(1, resultCount)
    }
}

func computeSavings(billablePages: Int, otherSpend: Double) -> SavingsBreakdown {
    let grossCharges = (Double(billablePages) * SearchFees.pricePerPage).roundToCents()
    
    let waiverRemainingBefore = max(0.0, SearchFees.waiverCap - otherSpend)
    
    let waiverUsed = min(grossCharges, waiverRemainingBefore)
    
    let waiverRemainingAfter = max(0.0, waiverRemainingBefore - grossCharges)
    
    let actualSavings: Double
    if grossCharges <= waiverRemainingBefore {
        actualSavings = -waiverRemainingAfter
    } else {
        actualSavings = (grossCharges - waiverUsed).roundToCents()
    }
    
    return SavingsBreakdown(
        grossCharges: grossCharges,
        waiverUsed: waiverUsed.roundToCents(),
        waiverRemaining: waiverRemainingAfter.roundToCents(),
        actualSavings: actualSavings.roundToCents()
    )
}

func computeQuarterSavings(totalBillablePages: Int, otherSpend: Double) -> SavingsBreakdown {
    let grossCharges = (Double(totalBillablePages) * SearchFees.pricePerPage).roundToCents()
    let totalSpend = grossCharges + otherSpend
    
    if totalSpend <= SearchFees.waiverCap {
        let waiverRemaining = SearchFees.waiverCap - totalSpend
        return SavingsBreakdown(
            grossCharges: grossCharges,
            waiverUsed: grossCharges,
            waiverRemaining: waiverRemaining.roundToCents(),
            actualSavings: (-waiverRemaining).roundToCents()
        )
    } else {
        let actualSavings = totalSpend - SearchFees.waiverCap
        return SavingsBreakdown(
            grossCharges: grossCharges,
            waiverUsed: max(0, SearchFees.waiverCap - otherSpend),
            waiverRemaining: 0,
            actualSavings: actualSavings.roundToCents()
        )
    }
}

extension Double {
    func roundToCents() -> Double {
        (self * 100).rounded() / 100
    }
}

extension Calendar {
    func currentQuarterRange(from date: Date = Date()) -> (start: Date, end: Date) {
        let comps = dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return (date, date) }
        let quarterIndex = (month - 1) / 3
        let startMonth = quarterIndex * 3 + 1
        let startComps = DateComponents(year: year, month: startMonth, day: 1)
        guard let start = self.date(from: startComps) else { return (date, date) }
        var endComps = DateComponents()
        endComps.month = 3
        guard let end = self.date(byAdding: endComps, to: start) else { return (start, start) }
        return (start, end)
    }
    
    func quarterID(from date: Date = Date()) -> String {
        let comps = dateComponents([.year, .month], from: date)
        guard let year = comps.year, let month = comps.month else { return "" }
        let quarter = (month - 1) / 3 + 1
        return "\(year)-Q\(quarter)"
    }
}
