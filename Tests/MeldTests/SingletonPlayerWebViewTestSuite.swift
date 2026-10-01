import Foundation
import Testing

// MARK: - SingletonPlayerWebViewTestSuite

/// Serialized parent suite grouping test suites that manipulate `SingletonPlayerWebView.shared`
/// to eliminate parallel execution races and document generation collisions.
@Suite("SingletonPlayerWebView Test Suite", .serialized)
enum SingletonPlayerWebViewTestSuite {}
