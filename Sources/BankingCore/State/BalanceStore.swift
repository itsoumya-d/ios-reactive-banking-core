import Foundation
#if canImport(Observation)
import Observation
#endif

// MARK: - Balance Store

/// Reactive balance store for SwiftUI integration.
/// Provides real-time account and transaction state with automatic UI updates.
#if canImport(Observation)
@available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, *)
@Observable
public final class BalanceStore: @unchecked Sendable {
    public private(set) var accounts: [Account] = []
    public private(set) var transactions: [String: [Transaction]] = [:]
    public private(set) var isLoading = false
    public private(set) var lastSyncDate: Date?
    public private(set) var error: BalanceStoreError?

    private let networkClient: NetworkClient
    private let cache: TransactionCache
    private let syncLock = NSLock()

    public init(networkClient: NetworkClient, cache: TransactionCache = InMemoryTransactionCache()) {
        self.networkClient = networkClient
        self.cache = cache
    }

    @MainActor
    public func loadAccounts() async {
        isLoading = true
        error = nil

        do {
            let request = APIRequest(path: "/v1/accounts")
            let response: APIResponse<AccountsResponse> = try await networkClient.execute(request)
            accounts = response.data.accounts
            lastSyncDate = Date()
        } catch {
            self.error = .fetchFailed(error.localizedDescription)
            let cached = await cache.cachedAccounts()
            if !cached.isEmpty {
                accounts = cached
            }
        }

        isLoading = false
    }

    @MainActor
    public func loadTransactions(for accountId: String, page: Int = 0, pageSize: Int = 50) async {
        isLoading = true

        do {
            let request = APIRequest(
                path: "/v1/accounts/\(accountId)/transactions",
                queryItems: [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "size", value: "\(pageSize)")
                ]
            )
            let response: APIResponse<TransactionsResponse> = try await networkClient.execute(request)
            transactions[accountId] = response.data.transactions
            await cache.cacheTransactions(response.data.transactions, for: accountId)
        } catch {
            self.error = .fetchFailed(error.localizedDescription)
            let cached = await cache.cachedTransactions(for: accountId)
            if !cached.isEmpty {
                transactions[accountId] = cached
            }
        }

        isLoading = false
    }

    @MainActor
    public func updateBalance(accountId: String, newBalance: Decimal) {
        guard let index = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        accounts[index].balance = newBalance
        accounts[index].updatedAt = Date()
    }

    public func accountBalance(_ accountId: String) -> Decimal? {
        accounts.first(where: { $0.id == accountId })?.balance
    }

    public func totalBalance(currency: Currency) -> Decimal {
        accounts
            .filter { $0.currency == currency }
            .reduce(Decimal.zero) { $0 + $1.balance }
    }
}
#endif

// MARK: - Balance Store Errors

public enum BalanceStoreError: Error, Sendable, Equatable {
    case fetchFailed(String)
    case accountNotFound(String)
    case syncConflict
}

// MARK: - API Response Models

public struct AccountsResponse: Decodable, Sendable {
    public let accounts: [Account]
}

public struct TransactionsResponse: Decodable, Sendable {
    public let transactions: [Transaction]
}

// MARK: - Transaction Cache Protocol

public protocol TransactionCache: Sendable {
    func cacheTransactions(_ transactions: [Transaction], for accountId: String) async
    func cachedTransactions(for accountId: String) async -> [Transaction]
    func cachedAccounts() async -> [Account]
    func cacheAccounts(_ accounts: [Account]) async
}

// MARK: - In-Memory Transaction Cache

public actor InMemoryTransactionCache: TransactionCache {
    private var transactionStore: [String: [Transaction]] = [:]
    private var accountStore: [Account] = []

    public init() {}

    public func cacheTransactions(_ transactions: [Transaction], for accountId: String) {
        transactionStore[accountId] = transactions
    }

    public func cachedTransactions(for accountId: String) -> [Transaction] {
        transactionStore[accountId] ?? []
    }

    public func cachedAccounts() -> [Account] {
        accountStore
    }

    public func cacheAccounts(_ accounts: [Account]) {
        accountStore = accounts
    }
}
