/// How long to wait before asking for the next page of older messages, given how many failed in a row.
public enum PageRetry {
    /// After this many failures in a row paging stops by itself; the reader can still ask with "Try again".
    public static let maxAutomatic = 5

    /// Milliseconds to wait, or nil when it is time to stop retrying on its own.
    public static func delay(afterFailures n: Int) -> Int? {
        if n <= 0 { return 300 }
        if n >= maxAutomatic { return nil }
        return min(30_000, 1_000 << n)
    }
}
