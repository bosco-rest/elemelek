import SwiftUI
import AppKit

/// A picture opened full size over the window: dimmed backdrop, pinch or double-click to zoom, drag to pan.
struct LightboxView: View {
    @Environment(AppModel.self) var model
    let box: Lightbox
    @State private var image: NSImage?
    @State private var data: Data?
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.82)).background(.ultraThinMaterial).ignoresSafeArea()
                .onTapGesture { close() }
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
                    .padding(40)
                    .scaleEffect(scale).offset(offset)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { scale = max(1, baseScale * $0.magnification) }
                            .onEnded { _ in baseScale = scale; if scale <= 1 { reset() } }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { if scale > 1 { offset = CGSize(width: baseOffset.width + $0.translation.width, height: baseOffset.height + $0.translation.height) } }
                            .onEnded { _ in baseOffset = offset }
                    )
                    .onTapGesture(count: 2) { withAnimation(.spring(duration: 0.3)) { if scale > 1 { reset() } else { scale = 2.5; baseScale = 2.5 } } }
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
            VStack {
                HStack(spacing: 6) {
                    if let name = box.row.imageName {
                        Text(name).font(Theme.font(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    }
                    Spacer()
                    IconButton(pic: "memo", help: "Save", size: 36) { save() }.disabled(data == nil)
                    IconButton(pic: "cross_mark", help: "Close", size: 36) { close() }
                }
                .padding(.horizontal, 18).padding(.top, 14)
                Spacer()
            }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.escape) { close(); return .handled }
        .onAppear { focused = true }
        .task(id: box.row.id) {
            if let d = await box.model.fullImageData(box.row) { data = d; image = NSImage(data: d) }
        }
    }

    private func reset() { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
    private func close() { model.lightbox = nil }

    private func save() {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = box.row.imageName ?? "image"
        if panel.runModal() == .OK, let url = panel.url { try? data.write(to: url) }
    }
}
