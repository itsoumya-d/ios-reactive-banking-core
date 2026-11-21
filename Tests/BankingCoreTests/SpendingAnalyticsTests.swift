import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import BankingCore

final class SpendingAnalyticsTests: XCTestCase {
    func testCategorizationRules() async {
        let engine = SpendingAnalyticsEngine()

        let cat1 = await engine.categorize(description: "Albert Heijn Amsterdam")
        XCTAssertEqual(cat1, .groceries)

        let cat2 = await engine.categorize(description: "Espresso Bar Cafe")
        XCTAssertEqual(cat2, .dining)

        let cat3 = await engine.categorize(description: "NS Train Station Ticket")
        XCTAssertEqual(cat3, .transport)

        let cat4 = await engine.categorize(description: "Netflix Monthly Subscription")
        XCTAssertEqual(cat4, .entertainment)

        let cat5 = await engine.categorize(description: "Vattenfall Electric Bill")
        XCTAssertEqual(cat5, .utilities)

        let cat6 = await engine.categorize(description: "Uncategorized Bookstore")
        XCTAssertEqual(cat6, .general)
    }

    func testCalculateSpendingForSettledTransactions() async {
        let engine = SpendingAnalyticsEngine()

        let txs = [
            Transaction(
                id: "tx-1",
                accountId: "acc-1",
                amount: -55.50,
                currency: .eur,
                counterpartyName: "Albert Heijn",
                counterpartyIban: "NL20INGB0001234567",
                description: "Albert Heijn Groceries",
                status: .settled
            ),
            Transaction(
                id: "tx-2",
                accountId: "acc-1",
                amount: -24.50,
                currency: .eur,
                counterpartyName: "Jumbo Supermarket",
                counterpartyIban: "NL20INGB0001234568",
                description: "Jumbo Supermarket supplies",
                status: .settled
            ),
            Transaction(
                id: "tx-3",
                accountId: "acc-1",
                amount: -12.00,
                currency: .eur,
                counterpartyName: "Coffee Corner",
                counterpartyIban: "NL20INGB0001234569",
                description: "Morning Coffee Cafe",
                status: .settled
            ),
            Transaction(
                id: "tx-pending",
                accountId: "acc-1",
                amount: -100.00,
                currency: .eur,
                counterpartyName: "Pending Store",
                counterpartyIban: "NL20INGB0001234570",
                description: "Albert Heijn pending",
                status: .pending
            )
        ]

        let summary = await engine.calculateSpending(for: txs)
        XCTAssertEqual(summary[.groceries], 80.00)
        XCTAssertEqual(summary[.dining], 12.00)
        XCTAssertNil(summary[.transport])
    }

    func testBudgetLimitsAndThresholdBreaches() async {
        let engine = SpendingAnalyticsEngine()

        await engine.setBudget(CategoryBudget(category: .groceries, monthlyLimit: 100.00, currency: .eur))
        await engine.setBudget(CategoryBudget(category: .dining, monthlyLimit: 50.00, currency: .eur))

        let txs = [
            Transaction(
                id: "tx-1",
                accountId: "acc-1",
                amount: -120.00,
                currency: .eur,
                counterpartyName: "Albert Heijn",
                counterpartyIban: "NL20INGB0001234567",
                description: "Groceries bulk shopping",
                status: .settled
            ),
            Transaction(
                id: "tx-2",
                accountId: "acc-1",
                amount: -25.00,
                currency: .eur,
                counterpartyName: "Cafe",
                counterpartyIban: "NL20INGB0001234568",
                description: "Cafe lunch",
                status: .settled
            )
        ]

        let reports = await engine.generateReports(for: txs)

        let groceryReport = reports.first { $0.category == .groceries }
        XCTAssertNotNil(groceryReport)
        XCTAssertEqual(groceryReport?.spentAmount, 120.00)
        XCTAssertEqual(groceryReport?.monthlyLimit, 100.00)
        XCTAssertEqual(groceryReport?.isOverBudget, true)
        XCTAssertEqual(groceryReport?.percentageUsed, 120.0)

        let diningReport = reports.first { $0.category == .dining }
        XCTAssertNotNil(diningReport)
        XCTAssertEqual(diningReport?.spentAmount, 25.00)
        XCTAssertEqual(diningReport?.monthlyLimit, 50.00)
        XCTAssertEqual(diningReport?.isOverBudget, false)
        XCTAssertEqual(diningReport?.percentageUsed, 50.0)
    }

    func testEmptyTransactionsYieldsNoReports() async {
        let engine = SpendingAnalyticsEngine()
        let reports = await engine.generateReports(for: [])
        XCTAssertTrue(reports.isEmpty)
    }
}
