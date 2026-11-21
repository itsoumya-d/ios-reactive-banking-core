# Changelog

All notable changes to `ios-reactive-banking-core` will be documented in this file.

## [1.0.0] - 2026-11-21
### Added
- Initial release of Swift 6 reactive mobile banking domain architecture.
- Strongly typed financial domain models (`Account`, `Transaction`, `PaymentIntent`).
- Actor-isolated `NetworkClient` with automatic OAuth2 token refresh and exponential backoff.
- Modern SwiftUI `@Observable` `BalanceStore` with in-memory transaction caching.
- Idempotent `OfflinePaymentQueue` with write-ahead intent buffering.
- Objective-C bidirectional bridge adapters (`ObjCAccountBridge`, `ObjCTransactionBridge`).
- `SpendingAnalyticsEngine` with automated categorization and budget limits.
- Full test suite with unit tests, benchmarks, and failure resilience verification.
