import Foundation

// MARK: - Objective-C Bridge Adapters

/// Bridge layer for translating legacy Objective-C banking models into modern Swift value types.
/// Used during incremental migration from UIKit Obj-C views to SwiftUI.

@objc public class ObjCAccountBridge: NSObject {
    @objc public let accountId: String
    @objc public let accountName: String
    @objc public let iban: String
    @objc public let balanceString: String
    @objc public let currencyCode: String
    @objc public let accountType: String

    public init(from account: Account) {
        self.accountId = account.id
        self.accountName = account.name
        self.iban = account.iban
        self.balanceString = "\(account.balance)"
        self.currencyCode = account.currency.rawValue
        self.accountType = account.type.rawValue
        super.init()
    }

    public func toSwiftAccount() -> Account {
        Account(
            id: accountId,
            name: accountName,
            iban: iban,
            balance: Decimal(string: balanceString) ?? 0,
            currency: Currency(rawValue: currencyCode) ?? .eur,
            type: AccountType(rawValue: accountType) ?? .checking
        )
    }
}

@objc public class ObjCTransactionBridge: NSObject {
    @objc public let transactionId: String
    @objc public let accountId: String
    @objc public let amountString: String
    @objc public let currencyCode: String
    @objc public let counterpartyName: String
    @objc public let counterpartyIban: String
    @objc public let transactionDescription: String
    @objc public let timestamp: Date
    @objc public let statusString: String

    public init(from transaction: Transaction) {
        self.transactionId = transaction.id
        self.accountId = transaction.accountId
        self.amountString = "\(transaction.amount)"
        self.currencyCode = transaction.currency.rawValue
        self.counterpartyName = transaction.counterpartyName
        self.counterpartyIban = transaction.counterpartyIban
        self.transactionDescription = transaction.description
        self.timestamp = transaction.timestamp
        self.statusString = transaction.status.rawValue
        super.init()
    }

    public func toSwiftTransaction() -> Transaction {
        Transaction(
            id: transactionId,
            accountId: accountId,
            amount: Decimal(string: amountString) ?? 0,
            currency: Currency(rawValue: currencyCode) ?? .eur,
            counterpartyName: counterpartyName,
            counterpartyIban: counterpartyIban,
            description: transactionDescription,
            timestamp: timestamp,
            status: TransactionStatus(rawValue: statusString) ?? .pending
        )
    }
}

// MARK: - Convenience Arrays

extension Array where Element == Account {
    public func toBridgeArray() -> [ObjCAccountBridge] {
        map { ObjCAccountBridge(from: $0) }
    }
}

extension Array where Element == ObjCAccountBridge {
    public func toSwiftArray() -> [Account] {
        map { $0.toSwiftAccount() }
    }
}

extension Array where Element == Transaction {
    public func toBridgeArray() -> [ObjCTransactionBridge] {
        map { ObjCTransactionBridge(from: $0) }
    }
}

extension Array where Element == ObjCTransactionBridge {
    public func toSwiftArray() -> [Transaction] {
        map { $0.toSwiftTransaction() }
    }
}
