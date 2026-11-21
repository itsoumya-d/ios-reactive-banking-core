import Foundation

public enum Currency: String, Codable, Sendable, CaseIterable {
    case eur = "EUR"
    case usd = "USD"
    case gbp = "GBP"
}

public enum AccountType: String, Codable, Sendable {
    case checking
    case savings
    case multiCurrency
}

public struct Account: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let iban: String
    public var balance: Decimal
    public let currency: Currency
    public let type: AccountType
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        iban: String,
        balance: Decimal,
        currency: Currency,
        type: AccountType,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iban = iban
        self.balance = balance
        self.currency = currency
        self.type = type
        self.updatedAt = updatedAt
    }
}

public enum TransactionStatus: String, Codable, Sendable {
    case pending
    case settled
    case failed
}

public struct Transaction: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let accountId: String
    public let amount: Decimal
    public let currency: Currency
    public let counterpartyName: String
    public let counterpartyIban: String
    public let description: String
    public let timestamp: Date
    public var status: TransactionStatus
    public let idempotencyKey: String

    public init(
        id: String,
        accountId: String,
        amount: Decimal,
        currency: Currency,
        counterpartyName: String,
        counterpartyIban: String,
        description: String,
        timestamp: Date = Date(),
        status: TransactionStatus = .settled,
        idempotencyKey: String = UUID().uuidString
    ) {
        self.id = id
        self.accountId = accountId
        self.amount = amount
        self.currency = currency
        self.counterpartyName = counterpartyName
        self.counterpartyIban = counterpartyIban
        self.description = description
        self.timestamp = timestamp
        self.status = status
        self.idempotencyKey = idempotencyKey
    }
}

public struct PaymentIntent: Codable, Sendable, Equatable {
    public let id: String
    public let sourceAccountId: String
    public let destinationIban: String
    public let destinationName: String
    public let amount: Decimal
    public let currency: Currency
    public let description: String
    public let idempotencyKey: String

    public init(
        id: String = UUID().uuidString,
        sourceAccountId: String,
        destinationIban: String,
        destinationName: String,
        amount: Decimal,
        currency: Currency,
        description: String,
        idempotencyKey: String = UUID().uuidString
    ) {
        self.id = id
        self.sourceAccountId = sourceAccountId
        self.destinationIban = destinationIban
        self.destinationName = destinationName
        self.amount = amount
        self.currency = currency
        self.description = description
        self.idempotencyKey = idempotencyKey
    }
}
