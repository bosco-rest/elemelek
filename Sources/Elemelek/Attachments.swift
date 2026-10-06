import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// A file waiting to be sent with the message: a picture pasted from the clipboard, a file dropped on the window
/// or picked with the paperclip. The text typed in the composer becomes its caption.
struct Attachment: Identifiable, Equatable {
    enum Kind { case image, video, audio, file }

    let id = UUID()
    let url: URL
    let kind: Kind
    let mime: String
    let size: UInt64
    var width: UInt64?
    var height: UInt64?
    var duration: TimeInterval?
    var thumbnail: NSImage?

    var name: String { url.lastPathComponent }

    static func == (a: Attachment, b: Attachment) -> Bool { a.id == b.id }

    static func make(url: URL) -> Attachment? {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .isDirectoryKey]),
              values.isDirectory != true else { return nil }
        let type = values.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
        let mime = type.preferredMIMEType ?? "application/octet-stream"
        let size = UInt64(values.fileSize ?? 0)
        var a = Attachment(url: url, kind: .file, mime: mime, size: size)
        if type.conforms(to: .image), let img = NSImage(contentsOf: url) {
            a = Attachment(url: url, kind: .image, mime: mime, size: size,
                           width: UInt64(imagePixelSize(url, fallback: img).width), height: UInt64(imagePixelSize(url, fallback: img).height),
                           thumbnail: img)
        } else if type.conforms(to: .movie) || type.conforms(to: .video) {
            let asset = AVURLAsset(url: url)
            var w: UInt64?, h: UInt64?
            if let track = asset.tracks(withMediaType: .video).first {
                let s = track.naturalSize.applying(track.preferredTransform)
                w = UInt64(abs(s.width)); h = UInt64(abs(s.height))
            }
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            let thumb = (try? gen.copyCGImage(at: .zero, actualTime: nil)).map { NSImage(cgImage: $0, size: .zero) }
            a = Attachment(url: url, kind: .video, mime: mime, size: size, width: w, height: h,
                           duration: CMTimeGetSeconds(asset.duration), thumbnail: thumb)
        } else if type.conforms(to: .audio) {
            a = Attachment(url: url, kind: .audio, mime: mime, size: size, duration: CMTimeGetSeconds(AVURLAsset(url: url).duration))
        }
        return a
    }

    private static func imagePixelSize(_ url: URL, fallback: NSImage) -> CGSize {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            return CGSize(width: w, height: h)
        }
        return fallback.size
    }

    // MARK: Compression

    static let maxSide = 2048

    /// A smaller copy for sending: longest side capped at `maxSide`, re-encoded as JPEG (PNG when it has
    /// transparency). Animated GIFs and anything that would not get smaller are left alone (returns nil).
    func compressed() -> Attachment? {
        guard kind == .image, mime != "image/gif", let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) == 1 else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let alpha = (props?[kCGImagePropertyHasAlpha] as? Bool) ?? false
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: Self.maxSide]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let type = alpha ? UTType.png : UTType.jpeg
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dst), UInt64(data.length) < size else { return nil }
        let out = Self.pasteDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let file = out.appendingPathComponent(url.deletingPathExtension().lastPathComponent + (alpha ? ".png" : ".jpg"))
        guard (try? (data as Data).write(to: file)) != nil else { return nil }
        return Attachment(url: file, kind: .image, mime: type.preferredMIMEType ?? mime, size: UInt64(data.length),
                          width: UInt64(img.width), height: UInt64(img.height), thumbnail: thumbnail)
    }

    // MARK: Pasteboard

    static var pasteDir: URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ElemelekPaste", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// What the pasteboard holds that can be sent: files copied in Finder, or a picture (a screenshot, a copied
    /// image) which is saved as a PNG first. Plain text returns nothing, so an ordinary paste goes through.
    static func fromPasteboard(_ pb: NSPasteboard) -> [Attachment] {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return urls.compactMap(make)
        }
        guard let data = pb.data(forType: .png) ?? pb.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: data),
              let png = rep.representation(using: .png, properties: [:]) else { return [] }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = pasteDir.appendingPathComponent("Screenshot \(f.string(from: Date())).png")
        guard (try? png.write(to: url)) != nil else { return [] }
        return make(url: url).map { [$0] } ?? []
    }

    static func formattedSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// ⌘V with a picture or files on the clipboard goes to the composer that has the focus; plain text pastes as usual.
enum PasteRouter {
    nonisolated(unsafe) private static var monitor: Any?
    @MainActor static var current: (([Attachment]) -> Void)?

    @MainActor static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers == "v",
                  let handler = current,
                  let editor = event.window?.firstResponder as? NSTextView, editor.isEditable else { return event }
            let items = Attachment.fromPasteboard(.general)
            guard !items.isEmpty else { return event }
            handler(items)
            return nil
        }
    }
}
