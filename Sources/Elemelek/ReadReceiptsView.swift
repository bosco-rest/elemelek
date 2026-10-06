import SwiftUI
import ElemelekCore

/// Floating read receipts indicator displayed below a message in the timeline.
struct ReadReceiptsView: View {
    let receipts: [ReadReceipt]
    var style: ReadReceiptStyle = .avatarsAndNames
    @State private var hovering = false
    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails = true
        } label: {
            HStack(spacing: 5) {
                if style != .namesOnly {
                    avatarStack
                }
                let labelText = ReadReceiptFormatter.label(for: receipts, style: style)
                if !labelText.isEmpty {
                    Text(labelText)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule()
                    .fill(Theme.wash(hovering ? 0.08 : 0.035))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Theme.hairline.opacity(hovering ? 0.8 : 0.35), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(ReadReceiptFormatter.tooltip(for: receipts))
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            ReadReceiptsPopover(receipts: receipts)
        }
    }

    private var avatarStack: some View {
        let maxVisible = 4
        let visible = Array(receipts.prefix(maxVisible))
        let remaining = receipts.count - maxVisible
        return HStack(spacing: -5) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, r in
                Avatar(name: r.displayName, url: r.avatarURL, size: 16)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 1.5))
                    .zIndex(Double(visible.count - index))
            }
            if remaining > 0 && style == .avatarsOnly {
                Text("+\(remaining)")
                    .font(Theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.wash(0.08)))
                    .padding(.leading, 2)
            }
        }
    }
}

/// Detailed popover listing all readers with their avatars, names, Matrix IDs, and read timestamps.
struct ReadReceiptsPopover: View {
    let receipts: [ReadReceipt]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Read by \(receipts.count)")
                    .font(Theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }
            .padding(.bottom, 2)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(receipts) { r in
                        HStack(spacing: 8) {
                            Avatar(name: r.displayName, url: r.avatarURL, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.displayName)
                                    .font(Theme.font(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text(r.userID)
                                    .font(Theme.font(size: 10))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 12)
                            if let date = r.date {
                                Text(Self.timeFormatter.string(from: date))
                                    .font(Theme.font(size: 10))
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: min(CGFloat(receipts.count * 38 + 12), 260))
        }
        .padding(12)
        .frame(minWidth: 240, maxWidth: 320)
    }
}
