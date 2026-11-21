# iOS Reactive Banking Core

[![CI](https://github.com/itsoumya-d/ios-reactive-banking-core/actions/workflows/ci.yml/badge.svg)](https://github.com/itsoumya-d/ios-reactive-banking-core/actions/workflows/ci.yml)
![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2016%2B%20%7C%20macOS%2013%2B-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

Production-grade, test-driven Swift domain library for modern reactive mobile banking applications. Engineered to demonstrate scalable iOS architecture, deterministic asynchronous state management, resilient REST networking with OAuth2 token rotation, idempotent offline payment queueing, and seamless Objective-C bridge adapters for legacy UI modernization.

---

## 🏛️ Architecture Overview

```
                      ┌────────────────────────────────────────┐
                      │          SwiftUI Views / App           │
                      └──────────────────┬─────────────────────┘
                                         │ Observes
                                         ▼
                      ┌────────────────────────────────────────┐
                      │    BalanceStore (@Observable / State)  │
                      └──────────────┬─────────────────────────┘
                                     │
            ┌────────────────────────┼────────────────────────┐
            ▼                        ▼                        ▼
┌───────────────────────┐ ┌──────────────────────┐ ┌──────────────────────┐
│     NetworkClient     │ │ OfflinePaymentQueue  │ │  ObjCBridge Adapter  │
│ - OAuth2 interceptor  │ │ - Idempotency keys   │ │ - Legacy model maps  │
│ - Exponential backoff │ │ - FIFO replay buffer │ │ - Modern value types │
│ - Circuit breaker     │ │ - Status transitions │ │ - Safe fallback init │
└───────────────────────┘ └──────────────────────┘ └──────────────────────┘
            │                        │                        │
            └────────────────────────┼────────────────────────┘
                                     ▼
                      ┌────────────────────────────────────────┐
                      │       Banking Domain Data Models       │
                      │  (Account, Transaction, PaymentIntent) │
                      └────────────────────────────────────────┘
```

---

## 🚀 Key Modules

### 1. Strongly Typed Domain Models (`Models/Account.swift`)
- Immutable value semantics (`struct`) conforming to `Codable`, `Sendable`, `Identifiable`, and `Equatable`.
- Precise decimal financial arithmetic with `Decimal` to avoid floating-point rounding errors.
- Strict multi-currency support (`EUR`, `USD`, `GBP`) with validated transaction lifecycle states (`pending`, `settled`, `failed`).

### 2. Resilient Networking & Auth (`Networking/NetworkClient.swift`)
- Fully actor-isolated `NetworkClient` executing asynchronous HTTP requests via Swift structured concurrency (`async`/`await`).
- Automatic `401 Unauthorized` token refresh interception with concurrent deduplication.
- Configurable `RetryPolicy` implementing exponential backoff with randomized jitter to prevent thundering herd spikes.
- Deterministic HTTP status mapping into strongly typed `NetworkError` variants.

### 3. Reactive Balance Store (`State/BalanceStore.swift`)
- Modern `@Observable` architecture (iOS 17+ / macOS 14+) providing zero-boilerplate SwiftUI state binding.
- Integrated `TransactionCache` protocol for instantaneous offline reads and background network reconciliation.
- MainActor-isolated mutating methods for thread-safe UI updates.

### 4. Idempotent Offline Payment Queue (`Offline/OfflinePaymentQueue.swift`)
- Local write-ahead transaction buffer storing `PaymentIntent` payloads during offline operation.
- Unique client-generated `X-Idempotency-Key` headers ensuring duplicate charge prevention even under flaky network conditions.
- Asynchronous sequential queue draining (`drain()`) with automatic status tracking (`queued` → `processing` → `completed` / `retrying` / `failed`).

### 5. Legacy Objective-C Interop Bridge (`Bridge/ObjCBridge.swift`)
- Bidirectional bridging layer (`ObjCAccountBridge`, `ObjCTransactionBridge`) extending `NSObject`.
- Translates legacy string-heavy dictionary structures into type-safe Swift native models, enabling progressive migration of legacy UIKit views into modern SwiftUI components.

---

## 🧪 Test Suite & Quality Verification

Comprehensive automated XCTest suite covering 100% of critical banking paths:
- **`AccountTests`**: Financial model instantiation, serialization/deserialization, and currency integrity.
- **`NetworkClientTests`**: Successful API roundtrips, custom header propagation (`X-Idempotency-Key`, `Authorization`), and OAuth token lifecycle checks.
- **`RetryPolicyTests`**: Mathematical verification of exponential delay formulas and maximum ceiling caps.
- **`OfflineQueueTests`**: Enqueueing, deduplication rejection, sequential draining, and cleanup.
- **`ObjCBridgeTests`**: Bi-directional round-trip conversion parity between Obj-C bridges and Swift value types.
- **`InMemoryCacheTests`**: Thread-safe caching and retrieval under concurrent actor access.

```bash
# Run the test suite
swift test
```

---

## 📦 Requirements

- **Swift**: 5.9 or 6.0+
- **macOS**: 13.0+ (Full `@Observable` support on macOS 14.0+)
- **iOS**: 16.0+ (Full `@Observable` support on iOS 17.0+)
- **Xcode**: 15.0+

---

## 📄 License

MIT License. Designed and engineered by [Soumya Debnath](https://github.com/itsoumya-d).
