import Foundation

/// The two flags the composer needs from a timeline row to decide whether
/// ArrowUp may pull it into the message box for editing.
public protocol ComposerMessage: Sendable {
    var isOwn: Bool { get }
    var isEditable: Bool { get }
}

/// ArrowUp handling for the message box, shared by the room and thread composers.
///
/// Standard chat behaviour: with an empty box and nothing already being
/// composed, ArrowUp loads the newest editable message of yours so it can be
/// edited. Anything else (text typed, an edit or reply already active, staged
/// attachments) leaves the key alone so it keeps its normal caret behaviour.
public enum ComposerEdit {
    public static func arrowUpTarget<Row: ComposerMessage>(
        rows: [Row],
        draft: String,
        isEditing: Bool,
        isReplying: Bool,
        hasAttachments: Bool
    ) -> Row? {
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isEditing, !isReplying, !hasAttachments
        else { return nil }
        return rows.last(where: { $0.isOwn && $0.isEditable })
    }

    /// Whether Escape should exit the active edit/reply mode, matching the
    /// cross button next to the banner. Plain typing is left alone.
    public static func shouldCancelComposeOnEscape(isEditing: Bool, isReplying: Bool) -> Bool {
        isEditing || isReplying
    }
}
