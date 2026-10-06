import SwiftUI

/// A grid of emoji to pick a reaction from, the recently used ones first.
struct EmojiPicker: View {
    let recent: [String]
    let onPick: (String) -> Void

    private static let groups: [(String, [String])] = [
        ("Smileys", chars("😀😃😄😁😆😅🤣😂🙂🙃😉😊😇🥰😍🤩😘😋😛😜🤪🤗🤭🤔🤨😐😑😶🙄😏😴😌😎🤓🧐😕😟🙁😮😲😳🥺😢😭😤😠😡🤯😱😰😥🤤🥱")),
        ("Gestures", chars("👍👎👌✌️🤞🤟🤘👈👉👆👇👋🤚🖐✋👏🙌🙏🤝💪🫶🫡🤷🤦🙋")),
        ("Hearts", chars("❤️🧡💛💚💙💜🖤🤍💔❣️💕💞💓💗💖💘💝")),
        ("Animals", chars("🐶🐱🐭🐰🦊🐻🐼🐨🐯🦁🐮🐷🐸🐵🐔🐧🐦🦆🦉🐺🐴🦄🐝🦋🐢🐍🐙🐬🐳")),
        ("Food", chars("🍎🍊🍋🍌🍉🍇🍓🍒🥑🍅🥕🌽🍕🍔🍟🌭🍿🥐🍞🧀🍣🍰🍪🍩☕🍺🍷🥂")),
        ("Activities", chars("⚽🏀🏈🎾🏐🎮🎯🎲🎸🎺🎧🎬🏆🥇🎉🎊🎁🎂")),
        ("Objects", chars("💡📱💻⌨️📷🔥⭐🌟✨⚡💥💯✅❌❗❓⚠️🚀🔔📌📎📝🔒🔑")),
    ]

    private static func chars(_ s: String) -> [String] { s.map(String.init) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if !recent.isEmpty { section("Recent", recent) }
                ForEach(Array(Self.groups.enumerated()), id: \.offset) { _, g in section(LocalizedStringKey(g.0), g.1) }
            }.padding(12)
        }
        .frame(width: 330, height: 300)
    }

    private func section(_ title: LocalizedStringKey, _ emojis: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 8), spacing: 2) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { _, e in
                    EmojiCell(emoji: e) { onPick(e) }
                }
            }
        }
    }
}

private struct EmojiCell: View {
    let emoji: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Text(emoji).font(.system(size: 22)).frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.wash(hovering ? 0.12 : 0)))
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}

/// Chips that wrap onto the next line, like reactions under a message.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(bounds.width, subviews)
        for (i, p) in r.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        var pos: [CGPoint] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            pos.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), pos)
    }
}
