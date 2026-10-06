import AppKit
import Darwin
import Foundation
import SwiftUI
import ElemelekCore

/// Link previews fetched by the app itself, never through the homeserver: a link in an encrypted room must not
/// reach anyone but the site it points to. Same behaviour as the desktop (Tauri) app's `link_preview.rs`: public
/// addresses only, a few redirects, 1 MB of HTML, OpenGraph/Twitter/plain meta tags.
struct LinkPreview: Equatable, Sendable {
    var url: URL
    var title: String?
    var description: String?
    var siteName: String?
    var imageURL: URL?
}

actor LinkPreviewer {
    static let shared = LinkPreviewer()

    private static let maxBytes = 1024 * 1024
    private static let userAgent = "Mozilla/5.0 (compatible; Elemelek link preview; +https://github.com/nix1)"

    private var cache: [URL: LinkPreview?] = [:]
    private var inflight: [URL: Task<LinkPreview?, Never>] = [:]
    private var images: [URL: Data] = [:]

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 15
        c.httpCookieStorage = nil
        c.urlCache = nil
        return URLSession(configuration: c, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    func preview(for url: URL) async -> LinkPreview? {
        if let hit = cache[url] { return hit }
        if let t = inflight[url] { return await t.value }
        let t = Task { await self.fetch(url) }
        inflight[url] = t
        let result = await t.value
        inflight[url] = nil
        cache[url] = result
        return result
    }

    func imageData(_ url: URL) async -> Data? {
        if let d = images[url] { return d }
        guard await Self.isAllowed(url) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count < 8 * Self.maxBytes else { return nil }
        images[url] = data
        return data
    }

    // MARK: Fetching

    private func fetch(_ url: URL) async -> LinkPreview? {
        guard await Self.isAllowed(url) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")
        req.setValue("pl,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        guard let (bytes, resp) = try? await session.bytes(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        let finalURL = http.url ?? url
        let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if type.hasPrefix("image/") { return LinkPreview(url: url, imageURL: finalURL) }
        guard type.contains("html") else { return nil }

        var data = Data()
        do {
            for try await b in bytes {
                data.append(b)
                if data.count >= Self.maxBytes { break }
            }
        } catch { return nil }
        let html = String(decoding: data, as: UTF8.self)
        guard let p = Self.parse(html, base: finalURL) else { return nil }
        return LinkPreview(url: url, title: p.title, description: p.description, siteName: p.siteName, imageURL: p.image)
    }

    // MARK: Parsing

    private static let metaRE = try! NSRegularExpression(pattern: "<meta\\b[^>]*>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let attrRE = try! NSRegularExpression(
        pattern: "([a-z:_-]+)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let titleRE = try! NSRegularExpression(pattern: "<title[^>]*>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    private static let numRE = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")

    static func parse(_ html: String, base: URL) -> (title: String?, description: String?, siteName: String?, image: URL?)? {
        func match(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
            re.matches(in: s, range: NSRange(s.startIndex..., in: s))
        }
        func group(_ r: NSTextCheckingResult, _ i: Int, in s: String) -> String? {
            guard i < r.numberOfRanges, let range = Range(r.range(at: i), in: s) else { return nil }
            return String(s[range])
        }
        var tags: [String: String] = [:]
        for tag in match(metaRE, html) {
            guard let t = group(tag, 0, in: html) else { continue }
            var key: String?
            var content: String?
            for a in match(attrRE, t) {
                let name = (group(a, 1, in: t) ?? "").lowercased()
                let value = group(a, 2, in: t) ?? group(a, 3, in: t) ?? group(a, 4, in: t) ?? ""
                switch name {
                case "property", "name", "itemprop": key = value.lowercased()
                case "content": content = decodeEntities(value)
                default: break
                }
            }
            if let k = key, let c = content, !c.isEmpty, tags[k] == nil { tags[k] = c }
        }
        func pick(_ keys: [String]) -> String? { keys.compactMap { tags[$0] }.first }
        let pageTitle = match(titleRE, html).first.flatMap { group($0, 1, in: html) }.map(decodeEntities)
        let title = pick(["og:title", "twitter:title"]) ?? pageTitle
        let desc = pick(["og:description", "twitter:description", "description"])
        let site = pick(["og:site_name", "application-name"])
        var image: URL?
        if let v = pick(["og:image", "og:image:url", "og:image:secure_url", "twitter:image", "twitter:image:src", "image"]),
           let abs = URL(string: v, relativeTo: base)?.absoluteURL, ["http", "https"].contains(abs.scheme) {
            image = abs
        }
        if title == nil, desc == nil, image == nil { return nil }
        return (title, desc, site, image)
    }

    static func decodeEntities(_ s: String) -> String {
        var out = s
        for m in numRE.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let whole = Range(m.range, in: out), let g = Range(m.range(at: 1), in: out) else { continue }
            let v = String(out[g])
            let code = v.hasPrefix("x") ? UInt32(v.dropFirst(), radix: 16) : UInt32(v)
            out.replaceSubrange(whole, with: code.flatMap(Unicode.Scalar.init).map { String($0) } ?? "")
        }
        for (a, b) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: a, with: b)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Safety

    /// Refuses URLs that point at this machine or the local network: a message must not be able to make the app
    /// read internal services.
    static func isAllowed(_ url: URL) async -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host else { return false }
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") || h.hasSuffix(".localhost") { return false }
        let port = String(url.port ?? (scheme == "https" ? 443 : 80))
        return await Task.detached { Self.resolvesToPublicOnly(host: host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), port: port) }.value
    }

    static func resolvesToPublicOnly(host: String, port: String) -> Bool {
        var hints = addrinfo(); hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, port, &hints, &res) == 0, let first = res else { return false }
        defer { freeaddrinfo(res) }
        var p: UnsafeMutablePointer<addrinfo>? = first
        while let ai = p {
            if let sa = ai.pointee.ai_addr {
                if ai.pointee.ai_family == AF_INET {
                    let a = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
                    let b = withUnsafeBytes(of: a) { Array($0) }
                    if !isPublicV4(b) { return false }
                } else if ai.pointee.ai_family == AF_INET6 {
                    let a = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                    let b = withUnsafeBytes(of: a) { Array($0) }
                    if !isPublicV6(b) { return false }
                }
            }
            p = ai.pointee.ai_next
        }
        return true
    }

    static func isPublicV4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        switch (b[0], b[1], b[2]) {
        case (0, _, _), (10, _, _), (127, _, _), (169, 254, _), (192, 168, _): return false
        case (172, 16...31, _), (100, 64...127, _): return false
        case (192, 0, 2), (198, 51, 100), (203, 0, 113), (192, 0, 0): return false
        case (224...255, _, _): return false
        default: return true
        }
    }

    static func isPublicV6(_ b: [UInt8]) -> Bool {
        guard b.count == 16 else { return false }
        if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return isPublicV4(Array(b[12..<16])) } // v4-mapped
        if b.allSatisfy({ $0 == 0 }) { return false }                                    // ::
        if b[0..<15].allSatisfy({ $0 == 0 }), b[15] == 1 { return false }                // ::1
        if b[0] & 0xfe == 0xfc { return false }                                          // unique local
        if b[0] == 0xfe, b[1] & 0xc0 == 0x80 { return false }                            // link local
        if b[0] == 0xff { return false }                                                 // multicast
        return true
    }
}

/// Stops redirects that lead somewhere private or go on for too long.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var hops: [Int: Int] = [:]

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock(); let n = (hops[task.taskIdentifier] ?? 0) + 1; hops[task.taskIdentifier] = n; lock.unlock()
        guard n <= 5, let url = request.url else { completionHandler(nil); return }
        Task { completionHandler(await LinkPreviewer.isAllowed(url) ? request : nil) }
    }
}

// MARK: - Views

/// A preview of the first of `urls` that has one: some sites (x.com) give nothing without running scripts.
struct LinkPreviewCard: View {
    let urls: [URL]
    @State private var url: URL?
    @State private var preview: LinkPreview?
    @State private var image: NSImage?
    @State private var loaded = false
    @State private var hovering = false

    var body: some View {
        // The loader sits on a view that is always there: a modifier on an empty `Group` never runs.
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
                .task(id: urls) {
                    for u in urls {
                        if let p = await LinkPreviewer.shared.preview(for: u), p.title != nil || p.description != nil || p.imageURL != nil {
                            preview = p; url = u
                            if let i = p.imageURL, let d = await LinkPreviewer.shared.imageData(i) { image = NSImage(data: d) }
                            break
                        }
                    }
                    loaded = true
                }
            if let p = preview, p.title != nil || p.description != nil || p.imageURL != nil {
                Button { NSWorkspace.shared.open(p.url) } label: { card(p) }
                    .buttonStyle(.plain).onHover { hovering = $0 }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if loaded { SizeMemo.sizes[key] = CGSize(width: 0, height: h) }
                    }
            }
        }
        // Until it loads again, a preview seen before keeps its height, so the timeline does not jump.
        .frame(minHeight: loaded ? nil : SizeMemo.sizes[key]?.height, alignment: .top)
    }

    private var key: String { "preview:" + urls.map(\.absoluteString).joined(separator: " ") }

    private func card(_ p: LinkPreview) -> some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.accent.opacity(0.7)).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(p.siteName ?? p.url.host ?? "").font(Theme.font(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                if let t = p.title {
                    Text(t).font(Theme.font(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                if let d = p.description {
                    Text(d).font(Theme.font(size: 12)).foregroundStyle(Theme.text.opacity(0.85))
                        .lineLimit(3).multilineTextAlignment(.leading)
                }
                if let image, p.title != nil || p.description != nil {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)).padding(.top, 4)
                } else if let image {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(10)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 440, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.wash(hovering ? 0.08 : 0.05)))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}
