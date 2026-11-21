import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Network Errors

public enum NetworkError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited(retryAfter: TimeInterval)
    case serverError(statusCode: Int)
    case decodingFailed
    case noData
    case timeout
    case noConnection
    case unknown(String)

    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.unauthorized, .unauthorized): return true
        case (.forbidden, .forbidden): return true
        case (.notFound, .notFound): return true
        case let (.rateLimited(a), .rateLimited(b)): return a == b
        case let (.serverError(a), .serverError(b)): return a == b
        case (.decodingFailed, .decodingFailed): return true
        case (.noData, .noData): return true
        case (.timeout, .timeout): return true
        case (.noConnection, .noConnection): return true
        case let (.unknown(a), .unknown(b)): return a == b
        default: return false
        }
    }
}

// MARK: - Token Management

public struct OAuthToken: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public var isExpired: Bool {
        Date() >= expiresAt
    }

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

// MARK: - Token Provider Protocol

public protocol TokenProvider: Sendable {
    func currentToken() async -> OAuthToken?
    func refreshToken(_ token: OAuthToken) async throws -> OAuthToken
    func storeToken(_ token: OAuthToken) async
}

// MARK: - Request Configuration

public struct APIRequest: Sendable {
    public let path: String
    public let method: HTTPMethod
    public let body: Data?
    public let queryItems: [URLQueryItem]
    public let idempotencyKey: String?

    public init(
        path: String,
        method: HTTPMethod = .get,
        body: Data? = nil,
        queryItems: [URLQueryItem] = [],
        idempotencyKey: String? = nil
    ) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
        self.idempotencyKey = idempotencyKey
    }

    public enum HTTPMethod: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"
    }
}

// MARK: - API Response

public struct APIResponse<T: Decodable & Sendable>: Sendable {
    public let data: T
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: T, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

// MARK: - Retry Configuration

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let jitterFactor: Double

    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        baseDelay: 0.5,
        maxDelay: 30.0,
        jitterFactor: 0.25
    )

    public init(maxAttempts: Int, baseDelay: TimeInterval, maxDelay: TimeInterval, jitterFactor: Double) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = jitterFactor
    }

    public func delay(for attempt: Int) -> TimeInterval {
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let capped = min(exponential, maxDelay)
        let jitter = capped * jitterFactor * Double.random(in: -1...1)
        return max(0, capped + jitter)
    }
}

// MARK: - HTTP Session Abstraction

public protocol HTTPSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

#if canImport(FoundationNetworking)
extension URLSession: HTTPSession {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let data = data, let response = response {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: NetworkError.noData)
                }
            }
            task.resume()
        }
    }
}
#else
extension URLSession: HTTPSession {}
#endif

// MARK: - Network Client

public actor NetworkClient {
    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let retryPolicy: RetryPolicy
    private let session: HTTPSession
    private let decoder: JSONDecoder
    private var isRefreshing = false

    public init(
        baseURL: URL,
        tokenProvider: TokenProvider,
        retryPolicy: RetryPolicy = .default,
        session: HTTPSession = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.retryPolicy = retryPolicy
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func execute<T: Decodable & Sendable>(_ request: APIRequest) async throws -> APIResponse<T> {
        var lastError: Error = NetworkError.unknown("No attempts made")

        for attempt in 0..<retryPolicy.maxAttempts {
            do {
                let urlRequest = try await buildURLRequest(request)
                let (data, response) = try await session.data(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.unknown("Invalid response type")
                }

                switch httpResponse.statusCode {
                case 200...299:
                    let decoded = try decoder.decode(T.self, from: data)
                    let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                        if let key = pair.key as? String, let value = pair.value as? String {
                            result[key] = value
                        }
                    }
                    return APIResponse(data: decoded, statusCode: httpResponse.statusCode, headers: headers)

                case 401:
                    try await handleTokenRefresh()
                    continue

                case 429:
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init) ?? retryPolicy.delay(for: attempt)
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                    continue

                case 404:
                    throw NetworkError.notFound

                case 500...599:
                    throw NetworkError.serverError(statusCode: httpResponse.statusCode)

                default:
                    throw NetworkError.unknown("HTTP \(httpResponse.statusCode)")
                }
            } catch let error as NetworkError where isRetryable(error) {
                lastError = error
                if attempt < retryPolicy.maxAttempts - 1 {
                    let delay = retryPolicy.delay(for: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                throw error
            }
        }

        throw lastError
    }

    // MARK: - Private

    private func buildURLRequest(_ request: APIRequest) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(request.path), resolvingAgainstBaseURL: false)!
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }

        guard let url = components.url else {
            throw NetworkError.unknown("Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if let idempotencyKey = request.idempotencyKey {
            urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "X-Idempotency-Key")
        }

        if let token = await tokenProvider.currentToken() {
            urlRequest.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        }

        return urlRequest
    }

    private func handleTokenRefresh() async throws {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let token = await tokenProvider.currentToken() else {
            throw NetworkError.unauthorized
        }

        let newToken = try await tokenProvider.refreshToken(token)
        await tokenProvider.storeToken(newToken)
    }

    private func isRetryable(_ error: NetworkError) -> Bool {
        switch error {
        case .serverError, .timeout, .noConnection:
            return true
        default:
            return false
        }
    }
}
