import os

/// One logger per area, so Console.app can filter by category. Messages never carry message content.
enum Log {
    private static let subsystem = "rest.bosco.elemelek"
    static let session = Logger(subsystem: subsystem, category: "session")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let timeline = Logger(subsystem: subsystem, category: "timeline")
    static let media = Logger(subsystem: subsystem, category: "media")
}

extension Logger {
    /// Runs a call that may fail and returns nil when it does, leaving the error in the log instead of dropping it.
    @discardableResult
    func attempt<T>(_ what: String, _ operation: () async throws -> T) async -> T? {
        do { return try await operation() } catch {
            self.error("\(what, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
