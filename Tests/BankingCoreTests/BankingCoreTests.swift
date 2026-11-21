import XCTest
@testable import BankingCore

// MARK: - Mock HTTP Session

final class MockHTTPSession: HTTPSession, @unchecked Sendable {
    var responses: [(Data, URLResponse)] = []
    var requestLog: [URLRequest] = []
    private var callIndex = 0
    private let lock = NSLock()

    func enqueue(statusCode: Int, json: String) {
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        responses.append((data, response))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        requestLog.append(request)
        guard callIndex < responses.count else {
            lock.unlock()
            throw NetworkError.noData
        }
        let result = responses[callIndex]
        callIndex += 1
        lock.unlock()
        return result
    }
}

// MARK: - Mock Token Provider

final class MockTokenProvider: TokenProvider, @unchecked Sendable {
    var token: OAuthToken?
    var refreshCallCount = 0

    func currentToken() async -> OAuthToken? { token }

    func refreshToken(_ token: OAuthToken) async throws -> OAuthToken {
        refreshCallCount += 1
        let newToken = OAuthToken(
            accessToken: "new-access-\(refreshCallCount)",
            refreshToken: "new-refresh-\(refreshCallCount)",
            expiresAt: Date().addingTimeInterval(3600)
        )
        self.token = newToken
        return newToken
    }

    func storeToken(_ token: OAuthToken) async {
        self.token = token
    }
}

// MARK: - Account Model Tests

final class AccountTests: XCTestCase {
    func testAccountCreation() {
        let account = Account(
            id: "acc-1",
            name: "Main Account",
            iban: "NL91ABNA0417164300",
            balance: 1250.50,
            currency: .eur,
            type: .checking
        )
        XCTAssertEqual(account.id, "acc-1")
        XCTAssertEqual(account.name, "Main Account")
        XCTAssertEqual(account.iban, "NL91ABNA0417164300")
        XCTAssertEqual(account.balance, 1250.50)
        XCTAssertEqual(account.currency, .eur)
        XCTAssertEqual(account.type, .checking)
    }

    func testAccountCodable() throws {
        let account = Account(
            id: "acc-2",
            name: "Savings",
            iban: "NL91ABNA0417164301",
            balance: 5000,
            currency: .eur,
            type: .savings
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(Account.self, from: data)
        XCTAssertEqual(account.id, decoded.id)
        XCTAssertEqual(account.balance, decoded.balance)
    }

    func testTransactionCreation() {
        let tx = Transaction(
            id: "tx-1",
            accountId: "acc-1",
            amount: -42.50,
            currency: .eur,
            counterpartyName: "Albert Heijn",
            counterpartyIban: "NL20INGB0001234567",
            description: "Groceries"
        )
        XCTAssertEqual(tx.amount, -42.50)
        XCTAssertEqual(tx.counterpartyName, "Albert Heijn")
        XCTAssertEqual(tx.status, .settled)
    }

    func testPaymentIntentIdempotencyKey() {
        let intent = PaymentIntent(
            sourceAccountId: "acc-1",
            destinationIban: "NL20INGB0001234567",
            destinationName: "Bob",
            amount: 100,
            currency: .eur,
            description: "Test"
        )
        XCTAssertFalse(intent.idempotencyKey.isEmpty)
    }

    func testCurrencyAllCases() {
        XCTAssertEqual(Currency.allCases.count, 3)
        XCTAssertTrue(Currency.allCases.contains(.eur))
        XCTAssertTrue(Currency.allCases.contains(.usd))
        XCTAssertTrue(Currency.allCases.contains(.gbp))
    }
}

// MARK: - Network Client Tests

final class NetworkClientTests: XCTestCase {
    func testSuccessfulRequest() async throws {
        let session = MockHTTPSession()
        let tokenProvider = MockTokenProvider()
        tokenProvider.token = OAuthToken(
            accessToken: "test-token",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3600)
        )

        session.enqueue(statusCode: 200, json: """
            {"accounts": [{"id": "a1", "name": "Main", "iban": "NL91ABNA0417164300", "balance": 1000, "currency": "EUR", "type": "checking", "updatedAt": "2024-01-01T00:00:00Z"}]}
            """)

        let client = NetworkClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: tokenProvider,
            session: session
        )

        let request = APIRequest(path: "/v1/accounts")
        let response: APIResponse<AccountsResponse> = try await client.execute(request)
        XCTAssertEqual(response.data.accounts.count, 1)
        XCTAssertEqual(response.data.accounts[0].id, "a1")
    }

    func testIdempotencyKeyHeader() async throws {
        let session = MockHTTPSession()
        let tokenProvider = MockTokenProvider()
        tokenProvider.token = OAuthToken(
            accessToken: "test",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(3600)
        )

        session.enqueue(statusCode: 200, json: """
            {"paymentId": "pay-1", "status": "completed"}
            """)

        let client = NetworkClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: tokenProvider,
            session: session
        )

        let request = APIRequest(
            path: "/v1/payments",
            method: .post,
            idempotencyKey: "idem-key-123"
        )
        let _: APIResponse<PaymentResponse> = try await client.execute(request)

        XCTAssertEqual(session.requestLog.count, 1)
        XCTAssertEqual(session.requestLog[0].value(forHTTPHeaderField: "X-Idempotency-Key"), "idem-key-123")
        XCTAssertEqual(session.requestLog[0].value(forHTTPHeaderField: "Authorization"), "Bearer test")
    }

    func testTokenIsExpired() {
        let token = OAuthToken(
            accessToken: "expired",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(-10)
        )
        XCTAssertTrue(token.isExpired)
    }

    func testTokenIsNotExpired() {
        let token = OAuthToken(
            accessToken: "valid",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertFalse(token.isExpired)
    }
}

// MARK: - Retry Policy Tests

final class RetryPolicyTests: XCTestCase {
    func testExponentialBackoff() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 1.0, maxDelay: 30.0, jitterFactor: 0)
        XCTAssertEqual(policy.delay(for: 0), 1.0)
        XCTAssertEqual(policy.delay(for: 1), 2.0)
        XCTAssertEqual(policy.delay(for: 2), 4.0)
        XCTAssertEqual(policy.delay(for: 3), 8.0)
    }

    func testMaxDelayCap() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 1.0, maxDelay: 10.0, jitterFactor: 0)
        XCTAssertEqual(policy.delay(for: 5), 10.0)   // 2^5 = 32, capped at 10
        XCTAssertEqual(policy.delay(for: 10), 10.0)
    }

    func testDefaultPolicy() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.baseDelay, 0.5)
    }
}

// MARK: - Offline Queue Tests

final class OfflineQueueTests: XCTestCase {
    func testEnqueuePayment() async {
        let session = MockHTTPSession()
        let tokenProvider = MockTokenProvider()
        let client = NetworkClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: tokenProvider,
            session: session
        )
        let queue = OfflinePaymentQueue(networkClient: client)

        let intent = PaymentIntent(
            sourceAccountId: "acc-1",
            destinationIban: "NL20INGB0001234567",
            destinationName: "Bob",
            amount: 50,
            currency: .eur,
            description: "Dinner"
        )

        let queued = await queue.enqueue(intent)
        XCTAssertEqual(queued.status, .queued)
        let size = await queue.queueSize()
        XCTAssertEqual(size, 1)
    }

    func testIdempotencyRejectsDuplicate() async {
        let session = MockHTTPSession()
        let tokenProvider = MockTokenProvider()
        let client = NetworkClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: tokenProvider,
            session: session
        )
        let queue = OfflinePaymentQueue(networkClient: client)

        let intent = PaymentIntent(
            id: "pay-1",
            sourceAccountId: "acc-1",
            destinationIban: "NL20INGB0001234567",
            destinationName: "Bob",
            amount: 50,
            currency: .eur,
            description: "Dinner",
            idempotencyKey: "fixed-key"
        )

        let first = await queue.enqueue(intent)
        XCTAssertEqual(first.status, .queued)

        // Drain successfully
        session.enqueue(statusCode: 200, json: """
            {"paymentId": "pay-1", "status": "completed"}
            """)
        tokenProvider.token = OAuthToken(
            accessToken: "t",
            refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600)
        )
        let results = await queue.drain()
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)

        // Try to enqueue same key again
        let second = await queue.enqueue(intent)
        XCTAssertEqual(second.status, .duplicate)
    }

    func testDrainSuccessful() async {
        let session = MockHTTPSession()
        let tokenProvider = MockTokenProvider()
        tokenProvider.token = OAuthToken(
            accessToken: "t",
            refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600)
        )

        session.enqueue(statusCode: 200, json: """
            {"paymentId": "pay-1", "status": "completed"}
            """)

        let client = NetworkClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: tokenProvider,
            session: session
        )
        let queue = OfflinePaymentQueue(networkClient: client)

        let intent = PaymentIntent(
            sourceAccountId: "acc-1",
            destinationIban: "NL20INGB0001234567",
            destinationName: "Alice",
            amount: 25,
            currency: .eur,
            description: "Coffee"
        )

        _ = await queue.enqueue(intent)
        let results = await queue.drain()

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)

        let size = await queue.queueSize()
        XCTAssertEqual(size, 0)
    }

    func testRemoveCompleted() async {
        let session = MockHTTPSession()
        let tokenProvider = MockTokenProvider()
        tokenProvider.token = OAuthToken(
            accessToken: "t",
            refreshToken: "r",
            expiresAt: Date().addingTimeInterval(3600)
        )

        session.enqueue(statusCode: 200, json: """
            {"paymentId": "pay-1", "status": "completed"}
            """)

        let client = NetworkClient(
            baseURL: URL(string: "https://api.example.com")!,
            tokenProvider: tokenProvider,
            session: session
        )
        let queue = OfflinePaymentQueue(networkClient: client)

        let intent = PaymentIntent(
            sourceAccountId: "acc-1",
            destinationIban: "NL91ABNA0417164301",
            destinationName: "Eve",
            amount: 10,
            currency: .eur,
            description: "Tip"
        )

        _ = await queue.enqueue(intent)
        _ = await queue.drain()
        await queue.removeCompleted()

        let all = await queue.allPayments()
        XCTAssertEqual(all.count, 0)
    }
}

// MARK: - ObjC Bridge Tests

final class ObjCBridgeTests: XCTestCase {
    func testAccountBridgeRoundTrip() {
        let account = Account(
            id: "acc-bridge",
            name: "Bridge Test",
            iban: "NL91ABNA0417164300",
            balance: 999.99,
            currency: .eur,
            type: .checking
        )
        let bridge = ObjCAccountBridge(from: account)
        let back = bridge.toSwiftAccount()
        XCTAssertEqual(back.id, account.id)
        XCTAssertEqual(back.name, account.name)
        XCTAssertEqual(back.iban, account.iban)
        XCTAssertEqual(back.currency, account.currency)
    }

    func testTransactionBridgeRoundTrip() {
        let tx = Transaction(
            id: "tx-bridge",
            accountId: "acc-1",
            amount: -15.00,
            currency: .gbp,
            counterpartyName: "Tesco",
            counterpartyIban: "GB29NWBK60161331926819",
            description: "Shopping"
        )
        let bridge = ObjCTransactionBridge(from: tx)
        let back = bridge.toSwiftTransaction()
        XCTAssertEqual(back.id, tx.id)
        XCTAssertEqual(back.amount, tx.amount)
        XCTAssertEqual(back.currency, .gbp)
        XCTAssertEqual(back.counterpartyName, "Tesco")
    }

    func testArrayBridgeExtensions() {
        let accounts = [
            Account(id: "1", name: "A", iban: "NL1", balance: 100, currency: .eur, type: .checking),
            Account(id: "2", name: "B", iban: "NL2", balance: 200, currency: .usd, type: .savings)
        ]
        let bridges = accounts.toBridgeArray()
        XCTAssertEqual(bridges.count, 2)
        let back = bridges.toSwiftArray()
        XCTAssertEqual(back.count, 2)
        XCTAssertEqual(back[0].id, "1")
        XCTAssertEqual(back[1].id, "2")
    }
}

// MARK: - In-Memory Cache Tests

final class InMemoryCacheTests: XCTestCase {
    func testCacheAndRetrieveTransactions() async {
        let cache = InMemoryTransactionCache()

        let txs = [
            Transaction(
                id: "tx-c1",
                accountId: "acc-1",
                amount: -10,
                currency: .eur,
                counterpartyName: "A",
                counterpartyIban: "NL1",
                description: "X"
            )
        ]

        await cache.cacheTransactions(txs, for: "acc-1")
        let retrieved = await cache.cachedTransactions(for: "acc-1")
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].id, "tx-c1")
    }

    func testCacheReturnsEmptyForUnknownAccount() async {
        let cache = InMemoryTransactionCache()
        let result = await cache.cachedTransactions(for: "unknown")
        XCTAssertTrue(result.isEmpty)
    }

    func testCacheAccounts() async {
        let cache = InMemoryTransactionCache()
        let accounts = [
            Account(id: "1", name: "Main", iban: "NL1", balance: 500, currency: .eur, type: .checking)
        ]
        await cache.cacheAccounts(accounts)
        let retrieved = await cache.cachedAccounts()
        XCTAssertEqual(retrieved.count, 1)
        XCTAssertEqual(retrieved[0].name, "Main")
    }
}

// MARK: - NetworkError Tests

final class NetworkErrorTests: XCTestCase {
    func testEquality() {
        XCTAssertEqual(NetworkError.unauthorized, NetworkError.unauthorized)
        XCTAssertEqual(NetworkError.serverError(statusCode: 500), NetworkError.serverError(statusCode: 500))
        XCTAssertNotEqual(NetworkError.unauthorized, NetworkError.forbidden)
        XCTAssertNotEqual(NetworkError.serverError(statusCode: 500), NetworkError.serverError(statusCode: 503))
    }
}
