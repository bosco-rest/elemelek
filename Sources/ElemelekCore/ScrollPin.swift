import Foundation

/// Whether the timeline follows new messages: pinned while the reader sits at the bottom, free once they
/// scroll up to read history. Pure math over scroll geometry, so the view only feeds it numbers.
public enum ScrollPin {
    /// How close to the end still counts as "at the bottom", in points.
    public static let tolerance = 40.0

    public struct Geometry: Equatable, Sendable {
        public var offsetY: Double
        public var contentHeight: Double
        public var viewportHeight: Double
        public init(offsetY: Double, contentHeight: Double, viewportHeight: Double) {
            self.offsetY = offsetY; self.contentHeight = contentHeight; self.viewportHeight = viewportHeight
        }
        /// Content shorter than the viewport counts as at the bottom.
        public var isAtBottom: Bool { contentHeight - (offsetY + viewportHeight) <= ScrollPin.tolerance }
    }

    /// The next pinned state. When only the content grew (a new message landed below, older ones above),
    /// the reader did not move, so the state stays as it was; otherwise it follows where they now are.
    public static func next(wasPinned: Bool, old: Geometry, new: Geometry) -> Bool {
        if old.contentHeight != new.contentHeight && old.viewportHeight == new.viewportHeight
            && old.offsetY == new.offsetY { return wasPinned }
        return new.isAtBottom
    }
}
