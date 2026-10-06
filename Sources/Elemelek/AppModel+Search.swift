import Foundation
import MatrixRustSDK

struct SearchHit: Identifiable, Hashable {
    let id: String
    var roomID: String
    var roomName: String
    var sender: String
    var text: String
    var date: Date
}

final class SearchListener: SearchServiceResultsListener, @unchecked Sendable {
    let cb: @Sendable ([SearchServiceResultsUpdate]) -> Void
    init(_ f: @escaping @Sendable ([SearchServiceResultsUpdate]) -> Void) { cb = f }
    func onUpdate(updates: [SearchServiceResultsUpdate]) { cb(updates) }
}

extension AppModel {
    func search(_ query: String) async {
        guard let client else { return }
        if searchService == nil {
            let svc = client.searchService()
            searchService = svc
            searchHandle = await svc.subscribeToResults(listener: SearchListener { [weak self] ups in
                Task { @MainActor in self?.apply(ups) }
            })
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { rawHits = []; searchHits = []; return }
        do { try await searchService?.setQuery(query: q) } catch { self.error = "\(error)" }
    }

    /// The next page of results for the current query.
    func loadMoreSearch() async {
        await Log.sync.attempt("search paginate") { try await searchService?.paginate() }
    }

    func apply(_ ups: [SearchServiceResultsUpdate]) {
        for u in ups {
            switch u {
            case .append(let v): rawHits += v
            case .clear: rawHits = []
            case .pushFront(let v): rawHits.insert(v, at: 0)
            case .pushBack(let v): rawHits.append(v)
            case .popFront: if !rawHits.isEmpty { rawHits.removeFirst() }
            case .popBack: if !rawHits.isEmpty { rawHits.removeLast() }
            case .insert(let i, let v): rawHits.insert(v, at: Int(i))
            case .set(let i, let v): rawHits[Int(i)] = v
            case .remove(let i): rawHits.remove(at: Int(i))
            case .truncate(let n): rawHits = Array(rawHits.prefix(Int(n)))
            case .reset(let v): rawHits = v
            }
        }
        searchHits = rawHits.map { r in
            switch r {
            case .message(let roomId, let m):
                var text = ""
                if case .msgLike(let c) = m.content, case .message(let mc) = c.kind { text = mc.body }
                var name = m.sender
                if case .ready(let dn, _, _, _, _) = m.senderProfile, let dn { name = dn }
                let rn = rooms.first { $0.id == roomId }?.name ?? roomId
                return SearchHit(id: m.eventId, roomID: roomId, roomName: rn, sender: name, text: text,
                                 date: Date(timeIntervalSince1970: Double(m.timestamp) / 1000))
            }
        }
    }
}
