import Testing
@testable import ElemelekCore

private struct Msg: ComposerMessage {
    var isOwn: Bool
    var isEditable: Bool
    var id: String
}

@Suite struct ComposerEditTests {
    private func rows() -> [Msg] {
        [
            Msg(isOwn: true, isEditable: true, id: "first"),
            Msg(isOwn: false, isEditable: false, id: "theirs"),
            Msg(isOwn: true, isEditable: false, id: "locked"),
            Msg(isOwn: true, isEditable: true, id: "last"),
        ]
    }

    @Test func emptyDraftPicksNewestEditableOwnMessage() {
        #expect(ComposerEdit.arrowUpTarget(rows: rows(), draft: "", isEditing: false, isReplying: false, hasAttachments: false)?.id == "last")
    }

    @Test func whitespaceOnlyDraftCountsAsEmpty() {
        #expect(ComposerEdit.arrowUpTarget(rows: rows(), draft: "  \n ", isEditing: false, isReplying: false, hasAttachments: false)?.id == "last")
    }

    @Test func typedDraftLeavesArrowUpAlone() {
        #expect(ComposerEdit.arrowUpTarget(rows: rows(), draft: "hi", isEditing: false, isReplying: false, hasAttachments: false) == nil)
    }

    @Test func activeEditReplyOrAttachmentsLeaveArrowUpAlone() {
        #expect(ComposerEdit.arrowUpTarget(rows: rows(), draft: "", isEditing: true, isReplying: false, hasAttachments: false) == nil)
        #expect(ComposerEdit.arrowUpTarget(rows: rows(), draft: "", isEditing: false, isReplying: true, hasAttachments: false) == nil)
        #expect(ComposerEdit.arrowUpTarget(rows: rows(), draft: "", isEditing: false, isReplying: false, hasAttachments: true) == nil)
    }

    @Test func escapeClosesEditOrReplyModeOnly() {
        #expect(ComposerEdit.shouldCancelComposeOnEscape(isEditing: true, isReplying: false))
        #expect(ComposerEdit.shouldCancelComposeOnEscape(isEditing: false, isReplying: true))
        #expect(!ComposerEdit.shouldCancelComposeOnEscape(isEditing: false, isReplying: false))
    }

    @Test func noEditableOwnMessageReturnsNil() {
        let onlyTheirs = [Msg(isOwn: false, isEditable: true, id: "x")]
        #expect(ComposerEdit.arrowUpTarget(rows: onlyTheirs, draft: "", isEditing: false, isReplying: false, hasAttachments: false) == nil)
        #expect(ComposerEdit.arrowUpTarget(rows: [Msg](), draft: "", isEditing: false, isReplying: false, hasAttachments: false) == nil)
    }
}
