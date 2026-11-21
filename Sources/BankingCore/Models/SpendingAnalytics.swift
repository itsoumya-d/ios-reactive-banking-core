import Foundation

public enum SpendingCategory: String, Codable, Sendable, CaseIterable {
    case groceries = "Groceries"
    case utilities = "Utilities"
    case entertainment = "Entertainment"
    case transport = "Transport"
    case dining = "Dining"
    case general = "General"
}

public struct CategoryBudget: Codable, Sendable, Equatable {
    public let category: SpendingCategory
    public let monthlyLimit: Decimal
    public let currency: Currency

    public init(category: SpendingCategory, monthlyLimit: Decimal, currency: Currency = .eur) {
        self.category = category
        self.monthlyLimit = monthlyLimit
        self.currency = currency
    }
}

public struct CategorySpendingReport: Sendable, Equatable {
    public let category: SpendingCategory
    public let spentAmount: Decimal
    public let monthlyLimit: Decimal?
    public let percentageUsed: Double?
    public let isOverBudget: Bool

    public init(
        category: SpendingCategory,
        spentAmount: Decimal,
        monthlyLimit: Decimal? = nil,
        percentageUsed: Double? = nil,
        isOverBudget: Bool = false
    ) {
        self.category = category
        self.spentAmount = spentAmount
        self.monthlyLimit = monthlyLimit
        self.percentageUsed = percentageUsed
        self.isOverBudget = isOverBudget
    }
}

public actor SpendingAnalyticsEngine {
    private var budgets: [SpendingCategory: CategoryBudget] = [:]

    public init() {}

    public func setBudget(_ budget: CategoryBudget) {
        budgets[budget.category] = budget
    }

    public func calculateSpending(for transactions: [Transaction]) -> [SpendingCategory: Decimal] {
        var summary: [SpendingCategory: Decimal] = [:]

        for tx in transactions where tx.status == .settled && tx.amount < 0 {
            let cat = categorize(description: tx.description)
            let positiveAmount = abs(tx.amount)
            summary[cat, default: 0] += positiveAmount
        }

        return summary
    }

    public func generateReports(for transactions: [Transaction]) -> [CategorySpendingReport] {
        let spending = calculateSpending(for: transactions)

        return SpendingCategory.allCases.compactMap { category in
            let spent = spending[category] ?? 0
            if let budget = budgets[category] {
                let limit = budget.monthlyLimit
                let ratio = limit > 0 ? (Double(truncating: spent as NSDecimalNumber) / Double(truncating: limit as NSDecimalNumber)) * 100.0 : 0.0
                return CategorySpendingReport(
                    category: category,
                    spentAmount: spent,
                    monthlyLimit: limit,
                    percentageUsed: ratio,
                    isOverBudget: spent > limit
                )
            } else if spent > 0 {
                return CategorySpendingReport(
                    category: category,
                    spentAmount: spent,
                    monthlyLimit: nil,
                    percentageUsed: nil,
                    isOverBudget: false
                )
            }
            return nil
        }
    }

    public func categorize(description: String) -> SpendingCategory {
        let lower = description.lowercased()
        if lower.contains("supermarket") || lower.contains("heijn") || lower.contains("jumbo") || lower.contains("groceries") {
            return .groceries
        } else if lower.contains("restaurant") || lower.contains("cafe") || lower.contains("coffee") || lower.contains("bar") {
            return .dining
        } else if lower.contains("train") || lower.contains("ns") || lower.contains("uber") || lower.contains("metro") || lower.contains("flight") {
            return .transport
        } else if lower.contains("cinema") || lower.contains("netflix") || lower.contains("spotify") || lower.contains("steam") {
            return .entertainment
        } else if lower.contains("electric") || lower.contains("gas") || lower.contains("water") || lower.contains("telecom") {
            return .utilities
        }
        return .general
    }
}
