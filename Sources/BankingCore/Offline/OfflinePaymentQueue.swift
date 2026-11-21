import Foundation

// MARK: - Offline Queue

/// Offline payment queue with idempotency keys and retry logic.
/// Queues payment intents while offline and drains them when connectivity is restored.
public actor OfflinePaymentQueue {
    public private(set) var pendingPayments: [QueuedPayment] = []
    public private(set) var processedKeys: Set<String> = []
    private let networkClient: NetworkClient
    private let maxRetries: Int

    public init(networkClient: NetworkClient, maxRetries: Int = 5) {
        self.networkClient = networkClient
        self.maxRetries = maxRetries
    }

    // MARK: - Queue Operations

    public func enqueue(_ intent: PaymentIntent) -> QueuedPayment {
        // Idempotency: reject duplicates by key
        guard !processedKeys.contains(intent.idempotencyKey) else {
            return QueuedPayment(intent: intent, status: .duplicate)
        }

        let queued = QueuedPayment(
            intent: intent,
            status: .queued,
            enqueuedAt: Date(),
            retryCount: 0
        )
        pendingPayments.append(queued)
        return queued
    }

    public func drain() async -> [DrainResult] {
        var results: [DrainResult] = []

        for index in pendingPayments.indices {
            guard pendingPayments[index].status == .queued ||
                  pendingPayments[index].status == .retrying else {
                continue
            }

            pendingPayments[index].status = .processing

            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let body = try encoder.encode(pendingPayments[index].intent)

                let request = APIRequest(
                    path: "/v1/payments",
                    method: .post,
                    body: body,
                    idempotencyKey: pendingPayments[index].intent.idempotencyKey
                )

                let _: APIResponse<PaymentResponse> = try await networkClient.execute(request)
                pendingPayments[index].status = .completed
                processedKeys.insert(pendingPayments[index].intent.idempotencyKey)
                results.append(DrainResult(
                    paymentId: pendingPayments[index].intent.id,
                    idempotencyKey: pendingPayments[index].intent.idempotencyKey,
                    success: true,
                    error: nil
                ))
            } catch {
                pendingPayments[index].retryCount += 1
                if pendingPayments[index].retryCount >= maxRetries {
                    pendingPayments[index].status = .failed
                } else {
                    pendingPayments[index].status = .retrying
                }
                results.append(DrainResult(
                    paymentId: pendingPayments[index].intent.id,
                    idempotencyKey: pendingPayments[index].intent.idempotencyKey,
                    success: false,
                    error: error.localizedDescription
                ))
            }
        }

        return results
    }

    public func queueSize() -> Int {
        pendingPayments.filter { $0.status == .queued || $0.status == .retrying }.count
    }

    public func removeCompleted() {
        pendingPayments.removeAll { $0.status == .completed || $0.status == .duplicate }
    }

    public func removeFailed() {
        pendingPayments.removeAll { $0.status == .failed }
    }

    public func allPayments() -> [QueuedPayment] {
        pendingPayments
    }
}

// MARK: - Queue Models

public struct QueuedPayment: Sendable, Equatable {
    public let intent: PaymentIntent
    public var status: QueuedPaymentStatus
    public let enqueuedAt: Date
    public var retryCount: Int

    public init(
        intent: PaymentIntent,
        status: QueuedPaymentStatus,
        enqueuedAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.intent = intent
        self.status = status
        self.enqueuedAt = enqueuedAt
        self.retryCount = retryCount
    }
}

public enum QueuedPaymentStatus: String, Sendable, Equatable {
    case queued
    case processing
    case completed
    case failed
    case retrying
    case duplicate
}

public struct DrainResult: Sendable, Equatable {
    public let paymentId: String
    public let idempotencyKey: String
    public let success: Bool
    public let error: String?
}

public struct PaymentResponse: Decodable, Sendable {
    public let paymentId: String
    public let status: String
}
