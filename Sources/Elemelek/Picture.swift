import AppKit

/// Pictures for avatars: a square photo from disk, or a Fluent emoji on a soft colour, both 512 px.
@MainActor enum Picture {
    /// Asks for an image file and crops a square from its middle; JPEG.
    static func pickSquareJPEG() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let src = NSImage(contentsOf: url),
              let cg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = min(cg.width, cg.height)
        guard let square = cg.cropping(to: CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side))
        else { return nil }
        return render { r in NSImage(cgImage: square, size: r.size).draw(in: r) }?
            .representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// The emoji drawn on a colour picked from its code; PNG.
    static func emoji(_ hex: String) -> Data? {
        guard let face = Pics.image("Emoji", hex) else { return nil }
        return render { r in
            NSColor(Theme.tint(for: hex).opacity(0.35)).setFill()
            r.fill()
            face.draw(in: r.insetBy(dx: 80, dy: 80))
        }?.representation(using: .png, properties: [:])
    }

    private static func render(_ draw: (NSRect) -> Void) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(NSRect(x: 0, y: 0, width: 512, height: 512))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
}
