import MatrixRustSDK
import AppKit
import SwiftUI

/// The palette and the look. Neutral graphite with a faint cool cast, hairlines instead of bevels, one accent
/// (the bird's blue) and colour only where it carries meaning. Adapts to light and dark by itself.
enum Theme {
    private static func dyn(_ dark: NSColor, _ light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }
    private static func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static let background = dyn(c(0.105, 0.110, 0.122), c(0.969, 0.971, 0.976))
    static let sidebar = dyn(c(0.118, 0.140, 0.190), c(0.918, 0.937, 0.972))
    static let panel = dyn(c(0.138, 0.144, 0.158), c(0.929, 0.932, 0.940))
    static let panelLight = dyn(c(0.176, 0.183, 0.200), c(0.996, 0.996, 0.998))
    static let inset = dyn(c(0.086, 0.090, 0.100), c(0.897, 0.900, 0.910))
    static let hairline = dyn(c(1, 1, 1, 0.08), c(0, 0, 0, 0.09))
    static let edge = dyn(c(1, 1, 1, 0.10), c(0, 0, 0, 0.12))
    static let text = dyn(c(0.90, 0.91, 0.93), c(0.09, 0.10, 0.12))
    static let dim = dyn(c(0.56, 0.58, 0.62), c(0.38, 0.40, 0.44))
    static let accent = dyn(c(0.36, 0.64, 0.97), c(0.14, 0.44, 0.84))
    static let red = dyn(c(1.0, 0.36, 0.33), c(0.85, 0.20, 0.18))
    static let green = dyn(c(0.31, 0.78, 0.47), c(0.16, 0.58, 0.32))
    static let orange = dyn(c(1.0, 0.66, 0.24), c(0.80, 0.45, 0.05))
    static let blueprint = dyn(c(0.45, 0.68, 1.0), c(0.18, 0.40, 0.80))

    static let radius: CGFloat = 12
    static let chromeRadius: CGFloat = 18

    /// A translucent wash for hover and chips: white on dark, black on light.
    static func wash(_ opacity: Double) -> Color {
        dyn(c(1, 1, 1, opacity), c(0, 0, 0, opacity))
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    /// A stable colour for a person's name and avatar.
    static func tint(for s: String) -> Color {
        var h: UInt64 = 5381
        for u in s.unicodeScalars { h = (h &* 33) &+ UInt64(u.value) }
        return Color(hue: Double(h % 360) / 360, saturation: 0.55, brightness: 0.88)
    }
}

// MARK: - Surfaces

struct Surface: ViewModifier {
    var fill: Color
    var raised = true
    var radius: CGFloat = Theme.radius
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: raised ? 1 : 0))
    }
}

/// The navigation layer: Liquid Glass on macOS 26, a panel with a hairline before.
struct Chrome: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            content.glassEffect(Glass.regular, in: shape)
        } else {
            content
                .background(shape.fill(Theme.panel))
                .overlay(shape.strokeBorder(Theme.edge, lineWidth: 1))
        }
    }
}

extension View {
    func plate(_ fill: Color = Theme.panel, radius: CGFloat = Theme.radius) -> some View {
        modifier(Surface(fill: fill, radius: radius))
    }
    func sunken(_ fill: Color = Theme.inset, radius: CGFloat = Theme.radius) -> some View {
        modifier(Surface(fill: fill, raised: false, radius: radius))
    }
    func chrome(radius: CGFloat = Theme.chromeRadius) -> some View { modifier(Chrome(radius: radius)) }

    /// A text field in a quiet well.
    func kitField() -> some View {
        textFieldStyle(.plain)
            .font(Theme.font(size: 13))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.inset))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }
}

// MARK: - Controls

/// Quiet capsule: a wash of its tint; `prominent` is the one solid action of a context.
struct KitButton: ButtonStyle {
    var tint: Color?
    var prominent = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        KitButtonBody(configuration: configuration, tint: tint, prominent: prominent, compact: compact)
    }
}

private struct KitButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color?
        let prominent: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @State private var hovering = false
        var body: some View {
            let fill: Color = prominent
                ? Theme.accent.opacity(configuration.isPressed ? 0.8 : hovering ? 0.92 : 1)
                : (tint.map { $0.opacity(configuration.isPressed ? 0.26 : hovering ? 0.22 : 0.14) }
                    ?? Theme.wash(configuration.isPressed ? 0.16 : hovering ? 0.12 : 0.06))
            configuration.label
                .font(Theme.font(size: compact ? 11 : 13, weight: prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? Color.white : (tint ?? Theme.text))
                .padding(.horizontal, compact ? 8 : 14).padding(.vertical, compact ? 3 : 7)
                .background(fill, in: Capsule(style: .continuous))
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
                .animation(.spring(duration: 0.22, bounce: 0.35), value: configuration.isPressed)
        }
}

/// The flat pictures (Fluent Emoji, Flat — Microsoft, MIT): icons in `Icons`, avatars in `Faces`.
@MainActor
enum Pics {
    private static var cache: [String: NSImage] = [:]
    static func image(_ dir: String, _ name: String) -> NSImage? {
        let key = dir + "/" + name
        if let hit = cache[key] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: dir),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[key] = img
        return img
    }

    /// Animals that make good avatars, in a fixed order so a name always gets the same one.
    static let animals = [
        "badger", "bear", "beaver", "bee", "bison", "boar", "butterfly", "camel", "cat", "chick", "chipmunk", "cow",
        "crab", "deer", "dino", "dodo", "dog", "dolphin", "duck", "eagle", "elephant", "flamingo", "fox", "frog",
        "giraffe", "goat", "goose", "gorilla", "hamster", "hedgehog", "hippo", "horse", "kangaroo", "koala", "ladybug",
        "leopard", "lion", "lizard", "lobster", "mammoth", "monkey", "moose", "mouse", "octopus", "otter", "owl",
        "panda", "parrot", "peacock", "penguin", "pig", "puffer", "rabbit", "raccoon", "rhino", "rooster", "seal",
        "shark", "skunk", "sloth", "snail", "tiger", "turkey", "turtle", "unicorn", "whale", "wolf",
    ]
    static func animal(for s: String) -> String {
        var h: UInt64 = 1469598103934665603
        for u in s.unicodeScalars { h = (h ^ UInt64(u.value)) &* 1099511628211 }
        return animals[Int(h % UInt64(animals.count))]
    }
}

/// A verification emoji drawn as its Fluent Emoji (Flat) picture; the system glyph if there is none.
struct SASEmoji: View {
    let symbol: String
    var size: CGFloat = 36
    var body: some View {
        let hex = symbol.unicodeScalars.filter { $0.value != 0xFE0F }.map { String($0.value, radix: 16) }.joined(separator: "-")
        if let img = Pics.image("FluentSAS", hex) {
            Image(nsImage: img).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(symbol).font(.system(size: size * 0.85)).frame(width: size, height: size)
        }
    }
}

/// An interface glyph: an SF Symbol, drawn in the text colour so it follows light, dark and contrast settings.
struct Pic: View {
    let name: String
    var size: CGFloat = 18
    static let symbols = [
        "cross_mark": "xmark", "thread": "bubble.left.and.bubble.right", "right_arrow_curving_left": "arrowshape.turn.up.left",
        "speech_balloon": "bubble.left", "smiling_face": "face.smiling", "shield": "checkmark.shield", "pushpin": "pin",
        "pencil": "pencil", "paperclip": "paperclip", "outbox_tray": "square.and.arrow.up", "mobile_phone": "iphone",
        "memo": "doc.text", "magnifier": "magnifyingglass", "key": "key",
    ]
    var body: some View {
        Image(systemName: Self.symbols[name] ?? name)
            .font(.system(size: size * 0.8, weight: .medium))
            .foregroundStyle(Theme.text)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A small round icon button: a flat picture, quiet at rest, a wash and full colour on hover.
struct IconButton: View {
    let pic: String
    var help: LocalizedStringKey
    var size: CGFloat = 30
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Pic(name: pic, size: size * 0.6)
                .opacity(hovering ? 1 : 0.78)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.wash(hovering ? 0.10 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A round avatar: the picture set on Matrix when there is one, otherwise a stable animal on a stable colour.
struct Avatar: View {
    let name: String
    var url: String? = nil
    var size: CGFloat = 32
    @State private var image: NSImage?
    var body: some View {
        let tint = Theme.tint(for: name)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(tint.opacity(0.22))
                if let img = Pics.image("Faces", "face-" + Pics.animal(for: name)) {
                    Image(nsImage: img).resizable().scaledToFit().padding(size * 0.14)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: url) { image = await AvatarStore.shared.image(url) }
    }
}

/// Avatar pictures from the homeserver, fetched once at a small size and kept in memory.
@MainActor final class AvatarStore {
    static let shared = AvatarStore()
    weak var client: Client?
    private let cache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 300; return c }()
    func image(_ url: String?) async -> NSImage? {
        guard let url, !url.isEmpty, let client else { return nil }
        if let i = cache.object(forKey: url as NSString) { return i }
        guard let src = try? MediaSource.fromUrl(url: url),
              let data = try? await client.getMediaThumbnail(mediaSource: src, width: 96, height: 96),
              let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: url as NSString)
        return img
    }
}
